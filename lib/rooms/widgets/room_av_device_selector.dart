import 'dart:async';

import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:synctogether/av/device_preference_service.dart';
import 'package:synctogether/av/device_selector_popup.dart';
import 'package:synctogether/av/livekit_service.dart';
import 'package:synctogether/player/chooser_dialog.dart';
import 'package:synctogether/ui/booth_icons.g.dart';
import 'package:synctogether/ui/glass.dart';

/// Shows popup menu for selecting an input microphone.
void showRoomMicDeviceSelector({
  required BuildContext context,
  required BuildContext buttonContext,
  required LiveKitService av,
}) {
  final renderBox = buttonContext.findRenderObject() as RenderBox?;
  if (renderBox == null || !renderBox.hasSize) return;
  final anchor = renderBox.localToGlobal(Offset.zero) & renderBox.size;

  final prefMic = DevicePreferenceService.instance.preferredMic;
  showDeviceSelectorPopup(
    context: context,
    anchor: anchor,
    title: 'Select Microphone',
    icon: BoothIcons.mic,
    enumerateDevices: av.audioInputDevices,
    selectedDeviceId: av.selectedAudioInputId ?? prefMic?.id,
    selectedDeviceLabel: av.selectedAudioInputLabel ?? prefMic?.label,
    onDeviceSelected: (device) {
      unawaited(av.setAudioInputDevice(device));
      unawaited(DevicePreferenceService.instance.setPreferredMic(device));
    },
    onDeviceChange: av.onDeviceChange,
  );
}

/// Shows popup menu for selecting a video camera.
void showRoomCamDeviceSelector({
  required BuildContext context,
  required BuildContext buttonContext,
  required LiveKitService av,
}) {
  final renderBox = buttonContext.findRenderObject() as RenderBox?;
  if (renderBox == null || !renderBox.hasSize) return;
  final anchor = renderBox.localToGlobal(Offset.zero) & renderBox.size;

  final prefCam = DevicePreferenceService.instance.preferredCam;
  showDeviceSelectorPopup(
    context: context,
    anchor: anchor,
    title: 'Select Camera',
    icon: BoothIcons.videocam,
    enumerateDevices: av.videoInputDevices,
    selectedDeviceId: av.selectedVideoInputId ?? prefCam?.id,
    selectedDeviceLabel: av.selectedVideoInputLabel ?? prefCam?.label,
    onDeviceSelected: (device) {
      unawaited(av.setVideoInputDevice(device));
      unawaited(DevicePreferenceService.instance.setPreferredCam(device));
    },
    onDeviceChange: av.onDeviceChange,
  );
}

/// Shows popup menu for selecting an audio output device.
void showRoomAudioOutputDeviceSelector({
  required BuildContext context,
  required BuildContext buttonContext,
  required LiveKitService av,
  Future<void> Function(lk.MediaDevice device)? onAudioOutputSelected,
}) {
  final renderBox = buttonContext.findRenderObject() as RenderBox?;
  if (renderBox == null || !renderBox.hasSize) return;
  final anchor = renderBox.localToGlobal(Offset.zero) & renderBox.size;

  final prefOutput = DevicePreferenceService.instance.preferredOutput;
  showDeviceSelectorPopup(
    context: context,
    anchor: anchor,
    title: 'Select Audio Output',
    icon: BoothIcons.volume,
    enumerateDevices: av.audioOutputDevices,
    selectedDeviceId: av.selectedAudioOutputId ?? prefOutput?.id,
    selectedDeviceLabel: av.selectedAudioOutputLabel ?? prefOutput?.label,
    onDeviceSelected: (device) async {
      unawaited(av.setAudioOutputDevice(device));
      unawaited(DevicePreferenceService.instance.setPreferredOutput(device));
      if (onAudioOutputSelected != null) {
        await onAudioOutputSelected(device);
      }
    },
    onDeviceChange: av.onDeviceChange,
  );
}

/// Displays chooser dialog for manually switching LiveKit AV endpoints (debug mode).
Future<void> showRoomAvEndpointChooser({
  required BuildContext context,
  required LiveKitService av,
}) async {
  await showGlassDialog(
    context: context,
    width: 380,
    builder: (dialogContext) => ChooserDialog<String>(
      type: 'AV endpoint',
      values: av.endpoints,
      selected: av.endpoint,
      onChosen: (endpoint) {
        Navigator.of(dialogContext).pop();
        unawaited(av.debugSwitchTo(endpoint));
      },
    ),
  );
}
