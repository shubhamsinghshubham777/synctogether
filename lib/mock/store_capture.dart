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

/// `STORE_TARGET=mac` shoots the Mac App Store set instead: 1440x900 at 2x
/// (2880x1800, a size App Store Connect accepts - 1920x1080 is not one) into
/// `assets/store/mac/`. The default is the Microsoft Store / README set.
const _kStoreTarget = String.fromEnvironment('STORE_TARGET', defaultValue: 'windows');
const _kMacStore = _kStoreTarget == 'mac';
const _kStoreDir = _kMacStore ? 'assets/store/mac' : 'assets/store';
const _kStoreLogical = _kMacStore ? Size(1440, 900) : _kCaptureLogical;
const _kStoreRatio = _kMacStore ? 2.0 : _kCaptureRatio;

Future<void> runStoreCaptureFlow(BuildContext context, GoRouter router) async {
  // ignore: avoid_print
  print('[STORE CAPTURE] Starting automated store capture flow...');

  await _sizeContentTo(_kStoreLogical);

  // 1. Capture Lobby Screen
  // ignore: avoid_print
  print('[STORE CAPTURE] Step 1: Capturing Lobby Screen...');
  router.go('/lobby');
  await Future.delayed(const Duration(milliseconds: 2500));
  await captureBoundaryToFile('$_kStoreDir/1_lobby.png', pixelRatio: _kStoreRatio);

  // 2. Capture Room Theater View
  // ignore: avoid_print
  print('[STORE CAPTURE] Step 2: Capturing Room Theater View...');
  router.go('/lobby/room/demo-room-1');
  await Future.delayed(const Duration(milliseconds: 3000));
  await captureBoundaryToFile('$_kStoreDir/2_theater_room.png', pixelRatio: _kStoreRatio);

  // 3. Capture Room with Live Chat Panel
  // ignore: avoid_print
  print('[STORE CAPTURE] Step 3: Capturing Room with Live Chat...');
  router.go('/lobby/room/demo-room-1?chat=true');
  await Future.delayed(const Duration(milliseconds: 2500));
  await captureBoundaryToFile('$_kStoreDir/3_room_chat.png', pixelRatio: _kStoreRatio);

  // 4. Capture Media Source Chooser Dialog
  // ignore: avoid_print
  print('[STORE CAPTURE] Step 4: Capturing Media Chooser Dialog...');
  router.go('/lobby/room/demo-room-1?dialog=media');
  await Future.delayed(const Duration(milliseconds: 2500));
  await captureBoundaryToFile('$_kStoreDir/4_media_chooser.png', pixelRatio: _kStoreRatio);

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
    // The content, not the window frame, must be 1440x900: a frame-sized
    // window loses the title bar and yields 2880x1736, which App Store
    // Connect rejects.
    await _sizeContentTo(const Size(1440, 900));
    router.go('/lobby/subscribe');
    await Future.delayed(const Duration(milliseconds: 2500));
    await captureBoundaryToFile('$_kStoreDir/5_subscription_purchase.png', pixelRatio: 2.0);
  }

  // ignore: avoid_print
  print('[STORE CAPTURE] Complete! All store screenshots generated in $_kStoreDir/');
  exit(0);
}

/// The homepage product shot, at the same 1280x720 @ 1.5x as the store shots.
/// The site serves a JPEG: `magick build/review/website/room-theater.png
/// -quality 86 -strip website/public/shots/room-theater.jpg`.
Future<void> runWebsiteCaptureFlow(GoRouter router) async {
  await _sizeContentTo(_kCaptureLogical);
  router.go('/lobby/room/demo-room-1?chat=true');
  await Future.delayed(const Duration(milliseconds: 4000));
  // ignore: avoid_print
  print('[WEBSITE CAPTURE] boundary ${storeCaptureBoundaryKey.currentContext?.size}');
  await captureBoundaryToFile('build/review/website/room-theater.png', pixelRatio: _kCaptureRatio);
  exit(0);
}

/// Every screen and state the design canvas has a board for, rendered by the
/// real app at the store/website size - for comparing the build against the
/// boards. `--dart-define=CAPTURE_REVIEW=true` (with DEMO_MODE, and
/// DEMO_TIER=premium for the Patron-side states). Writes `build/review/<tier>/`.
///
/// `REVIEW_WIDTH`/`REVIEW_HEIGHT` override the 1280x720 default so a capture
/// can match a board's own size (the desktop boards are 1440x900).
Future<void> runReviewCaptureFlow(GoRouter router) async {
  const w = int.fromEnvironment('REVIEW_WIDTH', defaultValue: 1280);
  const h = int.fromEnvironment('REVIEW_HEIGHT', defaultValue: 720);
  await _sizeContentTo(Size(w.toDouble(), h.toDouble()));
  const tier = String.fromEnvironment('DEMO_TIER', defaultValue: 'free');
  const shots = <(String, String)>[
    ('lobby', '/lobby'),
    ('room', '/lobby/room/demo-room-1'),
    ('room-chat', '/lobby/room/demo-room-1?chat=true'),
    ('room-source-dialog', '/lobby/room/demo-room-1?dialog=media'),
    ('profile', '/lobby/profile'),
    ('leaderboard', '/lobby/leaderboard'),
    ('patron', '/lobby/subscribe'),
    ('patron-verifying', '/lobby/subscribe?state=verifying'),
    ('patron-activated', '/lobby/subscribe?state=activated'),
  ];
  for (final (name, path) in shots) {
    router.go(path);
    // Long enough for entrance staggers and the room's mock media to settle.
    await Future.delayed(const Duration(milliseconds: 3500));
    await captureBoundaryToFile('build/review/$tier/$name.png', pixelRatio: _kCaptureRatio);
  }
  // ignore: avoid_print
  print('[REVIEW CAPTURE] Complete - build/review/$tier/');
  exit(0);
}
