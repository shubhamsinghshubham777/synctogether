import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:synctogether/av/macos_audio_devices.dart';

void main() {
  test('MacOSAudioDevices lists inputs and outputs accurately on macOS', () {
    final inputs = MacOSAudioDevices.getAudioInputs();
    final outputs = MacOSAudioDevices.getAudioOutputs();

    // Camo Microphone must NEVER be in outputs
    expect(outputs.any((d) => d.label.contains('Camo Microphone')), isFalse);
    // Real outputs like Mac mini Speakers or External Headphones must be present on Mac
    expect(outputs.any((d) => d.kind == 'audiooutput'), isTrue);
    // Real inputs like USB or Camo must have kind == 'audioinput'
    expect(inputs.every((d) => d.kind == 'audioinput'), isTrue);
  }, skip: !Platform.isMacOS);
}
