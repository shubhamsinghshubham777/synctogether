import 'dart:async';

import 'package:flutter/services.dart';

/// Where shakes come from. One event per shake; subscribing starts the source
/// and cancelling stops it, so an idle app pays nothing.
abstract interface class ShakeSource {
  Stream<void> get shakes;
}

/// iOS: Apple's own shake gesture, the one every app and the system use, so
/// there is nothing to tune and no sensor is read from Dart. The Swift side
/// (`ShakeFlutterViewController` in `AppDelegate.swift`) calls `shake` with no
/// arguments; the handler is installed only while something is listening.
class NativeShakeSource implements ShakeSource {
  NativeShakeSource({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('app.synctogether/shake');

  final MethodChannel _channel;

  @override
  Stream<void> get shakes {
    late final StreamController<void> controller;
    controller = StreamController<void>(
      onListen: () => _channel.setMethodCallHandler((call) async {
        if (call.method == 'shake') controller.add(null);
      }),
      onCancel: () => _channel.setMethodCallHandler(null),
    );
    return controller.stream;
  }
}
