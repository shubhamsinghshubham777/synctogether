#include "system_fonts.h"

#include <windows.h>

#include <dwrite.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <wrl/client.h>

#include <memory>
#include <string>

using flutter::EncodableList;
using flutter::EncodableMap;
using flutter::EncodableValue;
using Microsoft::WRL::ComPtr;

namespace {

std::string ToUtf8(const std::wstring& wide) {
  if (wide.empty()) return std::string();
  int size = WideCharToMultiByte(CP_UTF8, 0, wide.data(),
                                 static_cast<int>(wide.size()), nullptr, 0,
                                 nullptr, nullptr);
  std::string out(size, '\0');
  WideCharToMultiByte(CP_UTF8, 0, wide.data(), static_cast<int>(wide.size()),
                      out.data(), size, nullptr, nullptr);
  return out;
}

// The en-us string if there is one, else the first.
std::wstring PickName(IDWriteLocalizedStrings* strings) {
  if (!strings || strings->GetCount() == 0) return std::wstring();
  UINT32 index = 0;
  BOOL exists = FALSE;
  if (FAILED(strings->FindLocaleName(L"en-us", &index, &exists)) || !exists) {
    index = 0;
  }
  UINT32 length = 0;
  if (FAILED(strings->GetStringLength(index, &length))) return std::wstring();
  std::wstring name(length + 1, L'\0');
  if (FAILED(strings->GetString(index, name.data(), length + 1))) {
    return std::wstring();
  }
  name.resize(length);
  return name;
}

EncodableList ListFamilies() {
  EncodableList families;
  ComPtr<IDWriteFactory> factory;
  if (FAILED(DWriteCreateFactory(DWRITE_FACTORY_TYPE_SHARED,
                                 __uuidof(IDWriteFactory),
                                 reinterpret_cast<IUnknown**>(
                                     factory.GetAddressOf())))) {
    return families;
  }
  ComPtr<IDWriteFontCollection> collection;
  if (FAILED(factory->GetSystemFontCollection(&collection, FALSE))) {
    return families;
  }
  for (UINT32 i = 0; i < collection->GetFontFamilyCount(); ++i) {
    ComPtr<IDWriteFontFamily> family;
    if (FAILED(collection->GetFontFamily(i, &family))) continue;
    ComPtr<IDWriteLocalizedStrings> family_names;
    if (FAILED(family->GetFamilyNames(&family_names))) continue;
    std::wstring family_name = PickName(family_names.Get());
    if (family_name.empty()) continue;

    EncodableList faces;
    for (UINT32 j = 0; j < family->GetFontCount(); ++j) {
      ComPtr<IDWriteFont> font;
      if (FAILED(family->GetFont(j, &font))) continue;
      // Simulated bold/oblique faces are not real files libass can find.
      if (font->GetSimulations() != DWRITE_FONT_SIMULATIONS_NONE) continue;
      ComPtr<IDWriteLocalizedStrings> full_names;
      BOOL has_full = FALSE;
      font->GetInformationalStrings(DWRITE_INFORMATIONAL_STRING_FULL_NAME,
                                    &full_names, &has_full);
      std::wstring full = has_full ? PickName(full_names.Get()) : L"";
      ComPtr<IDWriteLocalizedStrings> face_names;
      std::wstring style;
      if (SUCCEEDED(font->GetFaceNames(&face_names))) {
        style = PickName(face_names.Get());
      }
      if (full.empty()) full = family_name + L" " + style;
      faces.push_back(EncodableValue(EncodableMap{
          {EncodableValue("name"), EncodableValue(ToUtf8(full))},
          {EncodableValue("style"), EncodableValue(ToUtf8(style))},
          {EncodableValue("weight"),
           EncodableValue(static_cast<int32_t>(font->GetWeight()))},
          {EncodableValue("italic"),
           EncodableValue(font->GetStyle() != DWRITE_FONT_STYLE_NORMAL)},
      }));
    }
    if (faces.empty()) continue;
    families.push_back(EncodableValue(EncodableMap{
        {EncodableValue("family"), EncodableValue(ToUtf8(family_name))},
        {EncodableValue("faces"), EncodableValue(faces)},
    }));
  }
  return families;
}

}  // namespace

void RegisterSystemFontsChannel(flutter::BinaryMessenger* messenger) {
  // Leaked on purpose: the channel lives as long as the engine does.
  auto channel = new flutter::MethodChannel<EncodableValue>(
      messenger, "app.synctogether/system_fonts",
      &flutter::StandardMethodCodec::GetInstance());
  channel->SetMethodCallHandler(
      [](const flutter::MethodCall<EncodableValue>& call,
         std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
        if (call.method_name() != "list") {
          result->NotImplemented();
          return;
        }
        result->Success(EncodableValue(ListFamilies()));
      });
}
