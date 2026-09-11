import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:livekit_client/livekit_client.dart' as lk;

// CoreAudio FFI struct definitions
final class _AudioObjectPropertyAddress extends Struct {
  @Uint32()
  external int mSelector;
  @Uint32()
  external int mScope;
  @Uint32()
  external int mElement;
}

typedef _AudioObjectGetPropertyDataSizeNative =
    Int32 Function(
      Uint32 inObjectID,
      Pointer<_AudioObjectPropertyAddress> inAddress,
      Uint32 inQualifierDataSize,
      Pointer<Void> inQualifierData,
      Pointer<Uint32> outDataSize,
    );
typedef _AudioObjectGetPropertyDataSizeDart =
    int Function(
      int inObjectID,
      Pointer<_AudioObjectPropertyAddress> inAddress,
      int inQualifierDataSize,
      Pointer<Void> inQualifierData,
      Pointer<Uint32> outDataSize,
    );

typedef _AudioObjectGetPropertyDataNative =
    Int32 Function(
      Uint32 inObjectID,
      Pointer<_AudioObjectPropertyAddress> inAddress,
      Uint32 inQualifierDataSize,
      Pointer<Void> inQualifierData,
      Pointer<Uint32> ioDataSize,
      Pointer<Void> outData,
    );
typedef _AudioObjectGetPropertyDataDart =
    int Function(
      int inObjectID,
      Pointer<_AudioObjectPropertyAddress> inAddress,
      int inQualifierDataSize,
      Pointer<Void> inQualifierData,
      Pointer<Uint32> ioDataSize,
      Pointer<Void> outData,
    );

typedef _CFStringGetLengthNative = IntPtr Function(Pointer<Void> theString);
typedef _CFStringGetLengthDart = int Function(Pointer<Void> theString);

typedef _CFStringGetCStringNative =
    Uint8 Function(
      Pointer<Void> theString,
      Pointer<Uint8> buffer,
      IntPtr bufferSize,
      Uint32 encoding,
    );
typedef _CFStringGetCStringDart =
    int Function(Pointer<Void> theString, Pointer<Uint8> buffer, int bufferSize, int encoding);

typedef _CFReleaseNative = Void Function(Pointer<Void> cf);
typedef _CFReleaseDart = void Function(Pointer<Void> cf);

typedef _MallocNative = Pointer<Void> Function(IntPtr size);
typedef _MallocDart = Pointer<Void> Function(int size);

typedef _FreeNative = Void Function(Pointer<Void> ptr);
typedef _FreeDart = void Function(Pointer<Void> ptr);

/// Native CoreAudio device enumerator for macOS via direct FFI.
///
/// Discovers audio hardware and virtual devices accurately by querying
/// `kAudioDevicePropertyDeviceCanBeDefaultDevice` and `kAudioDevicePropertyStreams`,
/// which exactly matches macOS System Settings.
abstract final class MacOSAudioDevices {
  static const _kAudioObjectSystemObject = 1;
  static const _kAudioHardwarePropertyDevices = 0x64657623; // 'dev#'
  static const _kAudioDevicePropertyStreams = 0x73746d23; // 'stm#'
  static const _kAudioDevicePropertyDeviceCanBeDefaultDevice = 0x64666c74; // 'dflt'
  static const _kAudioDevicePropertyDeviceNameCFString = 0x6c6e616d; // 'lnam'
  static const _kAudioDevicePropertyDeviceUID = 0x75696420; // 'uid '
  static const _kAudioObjectPropertyScopeGlobal = 0x676c6f62; // 'glob'
  static const _kAudioObjectPropertyScopeInput = 0x696e7074; // 'inpt'
  static const _kAudioObjectPropertyScopeOutput = 0x6f757470; // 'outp'
  static const _kAudioObjectPropertyElementMain = 0;
  static const _kCFStringEncodingUTF8 = 0x08000100;

  /// Returns audio input devices (microphones) currently available on macOS.
  static List<lk.MediaDevice> getAudioInputs() => _enumerate(isInput: true);

  /// Returns audio output devices (speakers/headphones) currently available on macOS.
  static List<lk.MediaDevice> getAudioOutputs() => _enumerate(isInput: false);

  static List<lk.MediaDevice> _enumerate({required bool isInput}) {
    if (!Platform.isMacOS) return const [];

    try {
      final libc = DynamicLibrary.process();
      final malloc = libc.lookupFunction<_MallocNative, _MallocDart>('malloc');
      final free = libc.lookupFunction<_FreeNative, _FreeDart>('free');

      final coreAudio = DynamicLibrary.open(
        '/System/Library/Frameworks/CoreAudio.framework/CoreAudio',
      );
      final coreFoundation = DynamicLibrary.open(
        '/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation',
      );

      final getPropertyDataSize = coreAudio
          .lookupFunction<
            _AudioObjectGetPropertyDataSizeNative,
            _AudioObjectGetPropertyDataSizeDart
          >('AudioObjectGetPropertyDataSize');
      final getPropertyData = coreAudio
          .lookupFunction<_AudioObjectGetPropertyDataNative, _AudioObjectGetPropertyDataDart>(
            'AudioObjectGetPropertyData',
          );

      final cfStringGetLength = coreFoundation
          .lookupFunction<_CFStringGetLengthNative, _CFStringGetLengthDart>('CFStringGetLength');
      final cfStringGetCString = coreFoundation
          .lookupFunction<_CFStringGetCStringNative, _CFStringGetCStringDart>('CFStringGetCString');
      final cfRelease = coreFoundation.lookupFunction<_CFReleaseNative, _CFReleaseDart>(
        'CFRelease',
      );

      final addr = malloc(
        sizeOf<_AudioObjectPropertyAddress>(),
      ).cast<_AudioObjectPropertyAddress>();
      final sizePtr = malloc(sizeOf<Uint32>()).cast<Uint32>();
      final u32Ptr = malloc(sizeOf<Uint32>()).cast<Uint32>();

      try {
        addr.ref.mSelector = _kAudioHardwarePropertyDevices;
        addr.ref.mScope = _kAudioObjectPropertyScopeGlobal;
        addr.ref.mElement = _kAudioObjectPropertyElementMain;

        final status = getPropertyDataSize(_kAudioObjectSystemObject, addr, 0, nullptr, sizePtr);
        if (status != 0 || sizePtr.value == 0) return const [];

        final dataSize = sizePtr.value;
        final deviceCount = dataSize ~/ sizeOf<Uint32>();
        final deviceIds = malloc(dataSize).cast<Uint32>();

        try {
          final fetchStatus = getPropertyData(
            _kAudioObjectSystemObject,
            addr,
            0,
            nullptr,
            sizePtr,
            deviceIds.cast(),
          );
          if (fetchStatus != 0) return const [];

          final scope = isInput
              ? _kAudioObjectPropertyScopeInput
              : _kAudioObjectPropertyScopeOutput;
          final kind = isInput ? 'audioinput' : 'audiooutput';
          final devices = <lk.MediaDevice>[];

          for (var i = 0; i < deviceCount; i++) {
            final devId = deviceIds[i];

            // 1. Check if device can be default for this scope (filters out devices
            // that don't belong to this direction in macOS Sound System Settings).
            addr.ref.mSelector = _kAudioDevicePropertyDeviceCanBeDefaultDevice;
            addr.ref.mScope = scope;
            addr.ref.mElement = _kAudioObjectPropertyElementMain;
            sizePtr.value = 4;
            final canDefStat = getPropertyData(devId, addr, 0, nullptr, sizePtr, u32Ptr.cast());
            final canBeDefault = canDefStat == 0 && u32Ptr.value == 1;

            // 2. Check if device has streams for this scope.
            addr.ref.mSelector = _kAudioDevicePropertyStreams;
            addr.ref.mScope = scope;
            addr.ref.mElement = _kAudioObjectPropertyElementMain;
            final streamStat = getPropertyDataSize(devId, addr, 0, nullptr, sizePtr);
            final hasStreams = streamStat == 0 && sizePtr.value > 0;

            if (!canBeDefault && !hasStreams) continue;
            // If it can't be default and has no proper streams, skip it.
            // Specifically, virtual inputs like Camo Microphone declare dummy output
            // streams but canDefOut == 0. So for outputs, require canBeDefault.
            if (!isInput && !canBeDefault) continue;
            if (isInput && !canBeDefault && !hasStreams) continue;

            // 3. Read Device Name.
            addr.ref.mSelector = _kAudioDevicePropertyDeviceNameCFString;
            addr.ref.mScope = _kAudioObjectPropertyScopeGlobal;
            addr.ref.mElement = _kAudioObjectPropertyElementMain;
            sizePtr.value = sizeOf<Pointer<Void>>();
            final cfNamePtr = malloc(sizeOf<Pointer<Void>>()).cast<Pointer<Void>>();
            var name = 'Unknown';
            try {
              if (getPropertyData(devId, addr, 0, nullptr, sizePtr, cfNamePtr.cast()) == 0 &&
                  cfNamePtr.value != nullptr) {
                final cfStr = cfNamePtr.value;
                final len = cfStringGetLength(cfStr);
                final bufSize = len * 4 + 1;
                final cStr = malloc(bufSize).cast<Uint8>();
                try {
                  if (cfStringGetCString(cfStr, cStr, bufSize, _kCFStringEncodingUTF8) != 0) {
                    final bytes = <int>[];
                    for (var b = 0; b < bufSize; b++) {
                      final byte = cStr[b];
                      if (byte == 0) break;
                      bytes.add(byte);
                    }
                    name = utf8.decode(bytes);
                  }
                } finally {
                  free(cStr.cast());
                  cfRelease(cfStr);
                }
              }
            } finally {
              free(cfNamePtr.cast());
            }

            // 4. Read Device UID.
            addr.ref.mSelector = _kAudioDevicePropertyDeviceUID;
            addr.ref.mScope = _kAudioObjectPropertyScopeGlobal;
            addr.ref.mElement = _kAudioObjectPropertyElementMain;
            sizePtr.value = sizeOf<Pointer<Void>>();
            final cfUidPtr = malloc(sizeOf<Pointer<Void>>()).cast<Pointer<Void>>();
            var uid = '';
            try {
              if (getPropertyData(devId, addr, 0, nullptr, sizePtr, cfUidPtr.cast()) == 0 &&
                  cfUidPtr.value != nullptr) {
                final cfStr = cfUidPtr.value;
                final len = cfStringGetLength(cfStr);
                final bufSize = len * 4 + 1;
                final cStr = malloc(bufSize).cast<Uint8>();
                try {
                  if (cfStringGetCString(cfStr, cStr, bufSize, _kCFStringEncodingUTF8) != 0) {
                    final bytes = <int>[];
                    for (var b = 0; b < bufSize; b++) {
                      final byte = cStr[b];
                      if (byte == 0) break;
                      bytes.add(byte);
                    }
                    uid = utf8.decode(bytes);
                  }
                } finally {
                  free(cStr.cast());
                  cfRelease(cfStr);
                }
              }
            } finally {
              free(cfUidPtr.cast());
            }

            final deviceId = uid.isNotEmpty ? uid : devId.toString();
            devices.add(lk.MediaDevice(deviceId, name, kind, null));
          }

          return devices;
        } finally {
          free(deviceIds.cast());
        }
      } finally {
        free(addr.cast());
        free(sizePtr.cast());
        free(u32Ptr.cast());
      }
    } catch (_) {
      return const [];
    }
  }
}
