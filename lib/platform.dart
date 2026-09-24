import 'package:flutter/foundation.dart';

const _desktopPlatforms = {TargetPlatform.macOS, TargetPlatform.windows, TargetPlatform.linux};

/// True on the three desktop targets. Gates window_manager (OS-window
/// fullscreen) and any other desktop-only chrome.
bool get isDesktop => !kIsWeb && _desktopPlatforms.contains(defaultTargetPlatform);

/// True when built with `--dart-define=STORE_BUILD=true` (e.g. for Microsoft Store).
/// In-app updates must be disabled for store distributions because the store
/// manages background updates directly.
const isStoreBuild = bool.fromEnvironment('STORE_BUILD', defaultValue: false);

/// True for the Mac App Store build (`--dart-define=STORE_BUILD=true`) and for
/// **every** iOS build, since iOS has no distribution channel other than
/// Apple's - a debug or TestFlight build must sell through StoreKit exactly
/// like the release one. Under Apple App Store guidelines 2.1(b) and 3.1.3(b),
/// external upsells and web checkout links must be suppressed in favour of
/// In-App Purchase. Non-Apple store distributions (such as Microsoft Store)
/// are not subject to these restrictions.
bool get isAppleStoreBuild =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.iOS ||
        (isStoreBuild && defaultTargetPlatform == TargetPlatform.macOS));

/// Whether WebViews should be served content via a loopback [HttpServer].
///
/// False only on macOS Store builds: the App Sandbox requires
/// `com.apple.security.network.server` to call `bind()` on any socket
/// (loopback included), and Apple rejects that entitlement for apps that do
/// not expose a genuine server to external clients. macOS WKWebView correctly
/// honours `InAppWebViewInitialData.baseUrl`, so inline data is a clean
/// alternative. On every other target the loopback path stays in use (Windows
/// WebView2 drops `baseUrl` on the floor, making inline data unusable for
/// origin-sensitive content like Turnstile).
bool get useLoopbackServer =>
    kIsWeb || !isStoreBuild || defaultTargetPlatform != TargetPlatform.macOS;

const _selfUpdatePlatforms = {TargetPlatform.macOS, TargetPlatform.windows};

bool get supportsSelfUpdate =>
    !kIsWeb && !isStoreBuild && _selfUpdatePlatforms.contains(defaultTargetPlatform);
