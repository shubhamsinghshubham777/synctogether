#include "push_channel.h"

#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <appmodel.h>
#include <shellapi.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Networking.PushNotifications.h>
#include <winrt/Windows.UI.Notifications.h>

#include <deque>
#include <functional>
#include <memory>
#include <mutex>
#include <string>
#include <thread>

using flutter::EncodableMap;
using flutter::EncodableValue;
using Result = flutter::MethodResult<EncodableValue>;
namespace push = winrt::Windows::Networking::PushNotifications;
namespace notif = winrt::Windows::UI::Notifications;

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
  if (!g_window || !PostMessage(g_window, kPushMessage, 0, 0)) {
    OutputDebugStringA("push: could not wake the platform thread\n");
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

// WNS channels (and the toast API) exist only for an app with package identity.
bool IsPackaged() {
  UINT32 length = 0;
  return GetCurrentPackageFullName(&length, nullptr) != APPMODEL_ERROR_NO_PACKAGE;
}

// "denied" when the person switched this app's toasts off in Windows settings.
std::string Permission() {
  if (!IsPackaged()) return "unsupported";
  try {
    return notif::ToastNotificationManager::CreateToastNotifier().Setting() ==
                   notif::NotificationSetting::Enabled
               ? "granted"
               : "denied";
  } catch (...) {
    return "unsupported";
  }
}

}  // namespace

void RunPushCallbacks() {
  std::deque<std::function<void()>> batch;
  {
    std::lock_guard<std::mutex> lock(g_mutex);
    batch.swap(g_pending);
  }
  for (auto& fn : batch) fn();
}

void RegisterPushChannel(flutter::BinaryMessenger* messenger, HWND window) {
  g_window = window;
  // Leaked on purpose: the channel lives as long as the engine does.
  auto channel = new flutter::MethodChannel<EncodableValue>(
      messenger, "app.synctogether/push",
      &flutter::StandardMethodCodec::GetInstance());
  channel->SetMethodCallHandler(
      [](const flutter::MethodCall<EncodableValue>& call,
         std::unique_ptr<Result> unique_result) {
        std::shared_ptr<Result> result(std::move(unique_result));
        const std::string& method = call.method_name();

        if (method == "configure" || method == "launchRoute") {
          result->Success();
        } else if (method == "permission" || method == "request") {
          result->Success(EncodableValue(Permission()));
        } else if (method == "openSettings") {
          ShellExecuteW(nullptr, L"open", L"ms-settings:notifications", nullptr,
                        nullptr, SW_SHOWNORMAL);
          result->Success();
        } else if (method == "token") {
          if (!IsPackaged()) {
            result->Success();
            return;
          }
          std::thread([result]() {
            winrt::init_apartment(winrt::apartment_type::multi_threaded);
            EncodableValue value;
            try {
              auto channel = push::PushNotificationChannelManager::
                                 CreatePushNotificationChannelForApplicationAsync()
                                     .get();
              value = EncodableValue(EncodableMap{
                  {EncodableValue("token"), EncodableValue(ToUtf8(channel.Uri()))},
                  {EncodableValue("environment"),
                   EncodableValue(std::string("production"))},
              });
            } catch (...) {
              // No channel (offline, WNS unreachable): not an error worth a
              // dialog. Dart treats null as "no token yet" and tries next launch.
            }
            PostToPlatform([result, value]() {
              if (value.IsNull()) {
                result->Success();
              } else {
                result->Success(value);
              }
            });
          }).detach();
        } else {
          result->NotImplemented();
        }
      });
}
