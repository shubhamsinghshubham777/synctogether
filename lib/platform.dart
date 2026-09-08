import 'package:flutter/foundation.dart';

const _desktopPlatforms = {TargetPlatform.macOS, TargetPlatform.windows, TargetPlatform.linux};

/// True on the three desktop targets. Gates window_manager (OS-window
/// fullscreen) and any other desktop-only chrome.
bool get isDesktop => !kIsWeb && _desktopPlatforms.contains(defaultTargetPlatform);

/// True when built with `--dart-define=STORE_BUILD=true` (e.g. for Microsoft Store).
/// In-app updates must be disabled for store distributions because the store
/// manages background updates directly.
const isStoreBuild = bool.fromEnvironment('STORE_BUILD', defaultValue: false);

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
