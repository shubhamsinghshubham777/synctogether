#include "mic_level.h"

#include <windows.h>

#include <audioclient.h>
#include <endpointvolume.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <mmdeviceapi.h>
#include <propkeydef.h>
// Defines (rather than declares) the PKEY_ constants below in this file.
#include <initguid.h>
#include <functiondiscoverykeys_devpkey.h>
#include <wrl/client.h>

#include <algorithm>
#include <cwctype>
#include <memory>
#include <string>

using flutter::EncodableMap;
using flutter::EncodableValue;
using Microsoft::WRL::ComPtr;

namespace {

std::wstring ToWide(const std::string& utf8) {
  if (utf8.empty()) return std::wstring();
  int size = MultiByteToWideChar(CP_UTF8, 0, utf8.data(),
                                 static_cast<int>(utf8.size()), nullptr, 0);
  std::wstring out(size, L'\0');
  MultiByteToWideChar(CP_UTF8, 0, utf8.data(), static_cast<int>(utf8.size()),
                      out.data(), size);
  return out;
}

std::wstring Lower(std::wstring s) {
  std::transform(s.begin(), s.end(), s.begin(),
                 [](wchar_t c) { return static_cast<wchar_t>(std::towlower(c)); });
  return s;
}

// One open input: a shared-mode capture stream that is started and never
// read (the engine only meters an endpoint something is capturing from), plus
// the endpoint's peak meter.
struct Session {
  ComPtr<IAudioClient> client;
  ComPtr<IAudioMeterInformation> meter;

  ~Session() {
    if (client) client->Stop();
  }
};

std::unique_ptr<Session> g_session;

bool NameMatches(IMMDevice* device, const std::wstring& wanted) {
  ComPtr<IPropertyStore> props;
  if (FAILED(device->OpenPropertyStore(STGM_READ, &props))) return false;
  PROPVARIANT name;
  PropVariantInit(&name);
  bool match = false;
  if (SUCCEEDED(props->GetValue(PKEY_Device_FriendlyName, &name)) &&
      name.vt == VT_LPWSTR && name.pwszVal) {
    // WebRTC labels can carry a "Default - " style prefix, so containment in
    // either direction counts.
    const std::wstring have = Lower(name.pwszVal);
    const std::wstring want = Lower(wanted);
    match = have == want || want.find(have) != std::wstring::npos ||
            have.find(want) != std::wstring::npos;
  }
  PropVariantClear(&name);
  return match;
}

ComPtr<IMMDevice> FindDevice(const std::wstring& wanted) {
  ComPtr<IMMDeviceEnumerator> enumerator;
  if (FAILED(CoCreateInstance(__uuidof(MMDeviceEnumerator), nullptr,
                              CLSCTX_ALL, IID_PPV_ARGS(&enumerator)))) {
    return nullptr;
  }
  ComPtr<IMMDevice> device;
  if (!wanted.empty()) {
    ComPtr<IMMDeviceCollection> devices;
    UINT count = 0;
    if (SUCCEEDED(enumerator->EnumAudioEndpoints(eCapture, DEVICE_STATE_ACTIVE,
                                                 &devices)) &&
        SUCCEEDED(devices->GetCount(&count))) {
      for (UINT i = 0; i < count; i++) {
        ComPtr<IMMDevice> candidate;
        if (SUCCEEDED(devices->Item(i, &candidate)) &&
            NameMatches(candidate.Get(), wanted)) {
          return candidate;
        }
      }
    }
  }
  // No name, or none matched: the system default input.
  enumerator->GetDefaultAudioEndpoint(eCapture, eConsole, &device);
  return device;
}

bool Start(const std::wstring& wanted) {
  g_session.reset();
  ComPtr<IMMDevice> device = FindDevice(wanted);
  if (!device) return false;

  auto session = std::make_unique<Session>();
  if (FAILED(device->Activate(__uuidof(IAudioMeterInformation), CLSCTX_ALL,
                              nullptr, &session->meter))) {
    return false;
  }
  if (FAILED(device->Activate(__uuidof(IAudioClient), CLSCTX_ALL, nullptr,
                              &session->client))) {
    return false;
  }
  WAVEFORMATEX* format = nullptr;
  if (FAILED(session->client->GetMixFormat(&format))) return false;
  // 100 ms buffer in 100 ns units; we never read it.
  HRESULT hr = session->client->Initialize(AUDCLNT_SHAREMODE_SHARED, 0,
                                           1000000, 0, format, nullptr);
  CoTaskMemFree(format);
  if (FAILED(hr) || FAILED(session->client->Start())) return false;

  g_session = std::move(session);
  return true;
}

}  // namespace

void RegisterMicLevelChannel(flutter::BinaryMessenger* messenger) {
  // Leaked on purpose: the channel lives as long as the engine does.
  auto channel = new flutter::MethodChannel<EncodableValue>(
      messenger, "app.synctogether/mic_level",
      &flutter::StandardMethodCodec::GetInstance());
  channel->SetMethodCallHandler(
      [](const flutter::MethodCall<EncodableValue>& call,
         std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
        const std::string& method = call.method_name();
        if (method == "start") {
          std::wstring name;
          if (const auto* args = std::get_if<EncodableMap>(call.arguments())) {
            auto it = args->find(EncodableValue("name"));
            if (it != args->end()) {
              if (const auto* s = std::get_if<std::string>(&it->second)) {
                name = ToWide(*s);
              }
            }
          }
          result->Success(EncodableValue(Start(name)));
        } else if (method == "peak") {
          float peak = 0.0f;
          if (g_session && g_session->meter) {
            g_session->meter->GetPeakValue(&peak);
          }
          result->Success(EncodableValue(static_cast<double>(peak)));
        } else if (method == "stop") {
          g_session.reset();
          result->Success();
        } else {
          result->NotImplemented();
        }
      });
}
