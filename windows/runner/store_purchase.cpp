#include "store_purchase.h"

#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <shobjidl_core.h>
#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Services.Store.h>

#include <cstdint>
#include <cstdio>
#include <deque>
#include <functional>
#include <memory>
#include <mutex>
#include <string>
#include <thread>

using flutter::EncodableList;
using flutter::EncodableMap;
using flutter::EncodableValue;
using Result = flutter::MethodResult<EncodableValue>;
namespace store = winrt::Windows::Services::Store;

namespace {

HWND g_window = nullptr;
std::mutex g_mutex;
std::deque<std::function<void()>> g_pending;

// Hands `fn` to the platform thread.
void PostToPlatform(std::function<void()> fn) {
  {
    std::lock_guard<std::mutex> lock(g_mutex);
    g_pending.push_back(std::move(fn));
  }
  // A lost wake-up leaves the Dart future pending forever; report it instead.
  if (!g_window || !PostMessage(g_window, kStorePurchaseMessage, 0, 0)) {
    OutputDebugStringA("store_purchase: could not wake the platform thread\n");
  }
}

std::string ToUtf8(const winrt::hstring& s) {
  if (s.empty()) return {};
  int n = WideCharToMultiByte(CP_UTF8, 0, s.c_str(), (int)s.size(), nullptr, 0,
                              nullptr, nullptr);
  std::string out(n, '\0');
  WideCharToMultiByte(CP_UTF8, 0, s.c_str(), (int)s.size(), out.data(), n,
                      nullptr, nullptr);
  return out;
}

winrt::hstring FromUtf8(const std::string& s) {
  if (s.empty()) return {};
  int n = MultiByteToWideChar(CP_UTF8, 0, s.c_str(), (int)s.size(), nullptr, 0);
  std::wstring out(n, L'\0');
  MultiByteToWideChar(CP_UTF8, 0, s.c_str(), (int)s.size(), out.data(), n);
  return winrt::hstring(out);
}

store::StoreContext Context() {
  auto ctx = store::StoreContext::GetDefault();
  // A desktop app must tell the Store which window owns its dialogs.
  ctx.as<IInitializeWithWindow>()->Initialize(g_window);
  return ctx;
}

const char* PeriodOf(store::StoreSubscriptionInfo const& info) {
  switch (info.BillingPeriodUnit()) {
    case store::StoreDurationUnit::Year:
      return "year";
    case store::StoreDurationUnit::Month:
      return info.BillingPeriod() >= 12 ? "year" : "month";
    default:
      return "other";
  }
}

const char* PurchaseStatus(store::StorePurchaseStatus s) {
  switch (s) {
    case store::StorePurchaseStatus::Succeeded:
      return "succeeded";
    case store::StorePurchaseStatus::AlreadyPurchased:
      return "alreadyPurchased";
    case store::StorePurchaseStatus::NotPurchased:
      return "notPurchased";
    case store::StorePurchaseStatus::NetworkError:
      return "networkError";
    default:
      return "serverError";
  }
}

// Runs `work` on a worker thread and reports its value or error to `result`
// on the platform thread.
void RunAsync(std::shared_ptr<Result> result,
              std::function<EncodableValue()> work) {
  std::thread([result, work = std::move(work)]() {
    winrt::init_apartment(winrt::apartment_type::multi_threaded);
    EncodableValue value;
    std::string error;
    try {
      value = work();
    } catch (winrt::hresult_error const& e) {
      char code[16];
      snprintf(code, sizeof(code), " (0x%08X)", static_cast<unsigned>(e.code().value));
      error = ToUtf8(e.message()) + code;
    } catch (std::exception const& e) {
      error = e.what();
    } catch (...) {
      error = "unknown native error";
    }
    // `error` must never be empty on a failure, or Dart would read it as success.
    if (error.empty() && value.IsNull()) error = "native call returned nothing";
    PostToPlatform([result, value, error]() {
      if (error.empty()) {
        result->Success(value);
      } else {
        result->Error("store_error", error);
      }
    });
  }).detach();
}

EncodableValue ListProducts() {
  auto ctx = Context();
  auto query = ctx.GetAssociatedStoreProductsAsync({L"Durable"}).get();
  if (query.ExtendedError().value != 0) {
    char code[40];
    snprintf(code, sizeof(code), "product query failed (0x%08X)",
             static_cast<unsigned>(query.ExtendedError().value));
    throw std::runtime_error(code);
  }
  EncodableList out;
  for (auto const& pair : query.Products()) {
    auto product = pair.Value();
    for (auto const& sku : product.Skus()) {
      if (!sku.IsSubscription()) continue;
      out.push_back(EncodableValue(EncodableMap{
          {EncodableValue("storeId"), EncodableValue(ToUtf8(sku.StoreId()))},
          {EncodableValue("title"), EncodableValue(ToUtf8(sku.Title()))},
          {EncodableValue("price"),
           EncodableValue(ToUtf8(sku.Price().FormattedPrice()))},
          {EncodableValue("currency"),
           EncodableValue(ToUtf8(sku.Price().CurrencyCode()))},
          {EncodableValue("period"),
           EncodableValue(std::string(PeriodOf(sku.SubscriptionInfo())))},
      }));
    }
  }
  return EncodableValue(out);
}

std::string StringArg(const EncodableMap& args, const char* key) {
  auto it = args.find(EncodableValue(key));
  if (it == args.end()) return {};
  auto* s = std::get_if<std::string>(&it->second);
  return s ? *s : std::string();
}

}  // namespace

void RunStorePurchaseCallbacks() {
  for (;;) {
    std::function<void()> fn;
    {
      std::lock_guard<std::mutex> lock(g_mutex);
      if (g_pending.empty()) return;
      fn = std::move(g_pending.front());
      g_pending.pop_front();
    }
    fn();
  }
}

void RegisterStorePurchaseChannel(flutter::BinaryMessenger* messenger,
                                  HWND window) {
  g_window = window;
  // Leaked on purpose: the channel lives as long as the engine does.
  auto channel = new flutter::MethodChannel<EncodableValue>(
      messenger, "app.synctogether/store_purchase",
      &flutter::StandardMethodCodec::GetInstance());
  channel->SetMethodCallHandler(
      [](const flutter::MethodCall<EncodableValue>& call,
         std::unique_ptr<Result> unique_result) {
        std::shared_ptr<Result> result(std::move(unique_result));
        const auto* args = std::get_if<EncodableMap>(call.arguments());
        const EncodableMap none;
        const EncodableMap& a = args ? *args : none;
        const std::string& method = call.method_name();

        if (method == "products") {
          RunAsync(result, [] { return ListProducts(); });
        } else if (method == "purchase") {
          auto id = StringArg(a, "storeId");
          RunAsync(result, [id] {
            auto r = Context().RequestPurchaseAsync(FromUtf8(id)).get();
            // ExtendedError is the only decline reason the Store gives us, and
            // the status alone cannot tell a closed dialog from a refusal.
            return EncodableValue(EncodableMap{
                {EncodableValue("status"),
                 EncodableValue(std::string(PurchaseStatus(r.Status())))},
                {EncodableValue("hresult"),
                 EncodableValue(static_cast<int32_t>(r.ExtendedError().value))},
            });
          });
        } else if (method == "idKey") {
          auto ticket = StringArg(a, "serviceTicket");
          auto user = StringArg(a, "userId");
          RunAsync(result, [ticket, user] {
            auto key = Context()
                           .GetCustomerPurchaseIdAsync(FromUtf8(ticket),
                                                       FromUtf8(user))
                           .get();
            return EncodableValue(ToUtf8(key));
          });
        } else {
          result->NotImplemented();
        }
      });
}
