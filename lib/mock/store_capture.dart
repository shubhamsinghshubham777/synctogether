import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:synctogether/platform.dart';
import 'package:synctogether/profile/apple_iap_service.dart';
import 'package:window_manager/window_manager.dart';

final GlobalKey storeCaptureBoundaryKey = GlobalKey();

Future<void> captureBoundaryToFile(String path, {double pixelRatio = 1.0}) async {
  final boundary =
      storeCaptureBoundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
  if (boundary == null) {
    // ignore: avoid_print
    print('[CAPTURE ERROR] RenderRepaintBoundary not found for key');
    return;
  }
  final image = await boundary.toImage(pixelRatio: pixelRatio);
  final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
  if (byteData == null) {
    // ignore: avoid_print
    print('[CAPTURE ERROR] Failed to encode PNG');
    return;
  }
  final file = File(path);
  file.parent.createSync(recursive: true);
  file.writeAsBytesSync(byteData.buffer.asUint8List());
  // ignore: avoid_print
  print('[STORE CAPTURE SUCCESS] Wrote $path (${file.lengthSync()} bytes)');
}

// Laid out at 1280x720 and rendered at 1.5x: the files are still a crisp
// 1920x1080, but the chrome reads at the size it has in a normal window - a
// 1920-logical layout made every control tiny.
const _kCaptureLogical = Size(1280, 720);
const _kCaptureRatio = 1.5;

/// Sizes the window so the *content* is exactly [logical]. setSize is the
/// frame, title bar included, so grow by whatever the content came up short.
Future<void> _sizeContentTo(Size logical) async {
  if (!isDesktop) return;
  try {
    await windowManager.ensureInitialized();
    await windowManager.setSize(logical);
    await Future.delayed(const Duration(milliseconds: 300));
    final box = storeCaptureBoundaryKey.currentContext?.size;
    if (box != null && box != logical) {
      await windowManager.setSize(
        Size(logical.width * 2 - box.width, logical.height * 2 - box.height),
      );
    }
    await windowManager.center();
  } catch (_) {}
}

Future<void> runStoreCaptureFlow(BuildContext context, GoRouter router) async {
  // ignore: avoid_print
  print('[STORE CAPTURE] Starting automated store capture flow...');

  await _sizeContentTo(_kCaptureLogical);

  // 1. Capture Lobby Screen
  // ignore: avoid_print
  print('[STORE CAPTURE] Step 1: Capturing Lobby Screen...');
  router.go('/lobby');
  await Future.delayed(const Duration(milliseconds: 2500));
  await captureBoundaryToFile('assets/store/1_violet_glass_lobby.png', pixelRatio: _kCaptureRatio);

  // 2. Capture Room Theater View
  // ignore: avoid_print
  print('[STORE CAPTURE] Step 2: Capturing Room Theater View...');
  router.go('/lobby/room/demo-room-1');
  await Future.delayed(const Duration(milliseconds: 3000));
  await captureBoundaryToFile('assets/store/2_theater_room.png', pixelRatio: _kCaptureRatio);

  // 3. Capture Room with Live Chat Panel
  // ignore: avoid_print
  print('[STORE CAPTURE] Step 3: Capturing Room with Live Chat...');
  router.go('/lobby/room/demo-room-1?chat=true');
  await Future.delayed(const Duration(milliseconds: 2500));
  await captureBoundaryToFile('assets/store/3_room_chat.png', pixelRatio: _kCaptureRatio);

  // 4. Capture Media Source Chooser Dialog
  // ignore: avoid_print
  print('[STORE CAPTURE] Step 4: Capturing Media Chooser Dialog...');
  router.go('/lobby/room/demo-room-1?dialog=media');
  await Future.delayed(const Duration(milliseconds: 2500));
  await captureBoundaryToFile('assets/store/4_media_chooser.png', pixelRatio: _kCaptureRatio);

  // 5. Subscription purchase screen - the App Review screenshot each App
  // Store subscription needs. Only meaningful with STORE_BUILD=true, which is
  // what shows the StoreKit offer; 1440x900 at 2x is a Mac App Store size.
  if (isAppleStoreBuild) {
    // ignore: avoid_print
    print('[STORE CAPTURE] Step 5: Capturing Subscription Purchase Screen...');
    AppleIapService.instance.seedDemoProducts([
      ProductDetails(
        id: kAppleMonthlyProductId,
        title: 'Premium Monthly',
        description: 'Bigger rooms, video facecams and 24-hour sessions.',
        price: r'$3.99',
        rawPrice: 3.99,
        currencyCode: 'USD',
      ),
      ProductDetails(
        id: kAppleAnnualProductId,
        title: 'Premium Annual',
        description: 'A year of bigger rooms, video facecams and more.',
        price: r'$29.99',
        rawPrice: 29.99,
        currencyCode: 'USD',
      ),
    ]);
    if (isDesktop) {
      try {
        await windowManager.setSize(const Size(1440, 900));
      } catch (_) {}
    }
    router.go('/lobby/subscribe');
    await Future.delayed(const Duration(milliseconds: 2500));
    await captureBoundaryToFile('assets/store/5_subscription_purchase.png', pixelRatio: 2.0);
  }

  // ignore: avoid_print
  print('[STORE CAPTURE] Complete! All store screenshots generated in assets/store/');
  exit(0);
}

/// The homepage product shot, at the same 1280x720 @ 1.5x as the store shots.
Future<void> runWebsiteCaptureFlow(GoRouter router) async {
  await _sizeContentTo(_kCaptureLogical);
  router.go('/lobby/room/demo-room-1?chat=true');
  await Future.delayed(const Duration(milliseconds: 4000));
  // ignore: avoid_print
  print('[WEBSITE CAPTURE] boundary ${storeCaptureBoundaryKey.currentContext?.size}');
  await captureBoundaryToFile('website/public/shots/room-theater.png', pixelRatio: _kCaptureRatio);
  exit(0);
}
