---
description: OAuth PKCE deep linking, Apple Sign-In, Passwordless Email OTP, Cloudflare Turnstile loopback bridge, Windows WebView2 runtime, TLS root cert overrides, and native silent desktop updates.
trigger: model_decision
---


# Authentication, Security & Platform Specifics

Guidance for authentication (`lib/auth/`), TLS overrides, platform runtimes, and desktop self-updates (`lib/updates/`).

## 1. Authentication & Deep Linking

`AuthService` supports Google OAuth (`signInWithOAuth`), Apple Sign-In (`signInWithApple`), Passwordless Email OTP (`signInWithOtp`), anonymous guest logins (`signInAnonymously`), and guest-to-account upgrades (`linkIdentity`).

### OAuth & Deep Link Flows
- Browser opens OAuth -> redirects to web bridge (`synctogether.app/auth/desktop-callback` or `localhost:3000`) -> web bridge relays PKCE params to `synctogether://auth-callback`.
- **Apple Sign-In**: Uses native Apple Sign In credentials on iOS/macOS and OAuth web flow on other platforms.
- **Passwordless Email OTP**: Sends a one-time login link or numeric code via email; protected by Turnstile captcha.
- **Windows Single-Instance**: `windows/runner/main.cpp` calls `app_links`' `SendAppLinkToInstance()` first in `wWinMain` to forward deep link parameters via `WM_COPYDATA` rather than spawning orphaned processes.
- **Config & Manual Linking**: `enable_manual_linking = true` must be enabled in `config.toml` for `linkIdentity` to work (ships via `supabase config push`).
- **Deep Link Stream**: `AuthService.start()` must remain subscribed; its `onError` handler catches unhandled deep-link authentication exceptions.

### Cloudflare Turnstile Captcha (`lib/auth/turnstile_dialog.dart`)
- Anonymous logins, guest account upgrades, and email OTP require a Turnstile captcha token.
- **Loopback Origin**: Served from a throwaway `HttpServer` on the loopback (`127.0.0.1`), because Windows WebView2 drops `InAppWebViewInitialData.baseUrl` and yields an opaque origin. Keep `localhost` in the Turnstile hostname allow-list.

---

## 2. Platform Runtimes & TLS Overrides

### Windows WebView2 Runtime (`lib/auth/webview_runtime.dart`)
- **Explicit `userDataFolder`**: Initialized under `LOCALAPPDATA`. (If null, WebView2 attempts to write to Program Files, failing with unhandled platform exceptions).
- `PTWebView.init()` probes `WebViewEnvironment.getAvailableVersion()` and configures `--autoplay-policy=no-user-gesture-required`.

### TLS Overrides (`lib/tls.dart`)
- Windows Dart snapshots the Windows ROOT store and fails to build dynamic CryptoAPI chains on demand.
- `installTlsOverrides()` injects Mozilla's root CA bundle (`assets/ca/cacert.pem`) **additively** (`withTrustedRoots: true`).
- `badCertificateCallback` logs diagnostics and returns `false` (never blindly trusts bad certs).

---

## 3. Desktop Self-Updates (`lib/updates/`)

Self-update is implemented entirely in native Dart (`UpdateService`), checking against `releases/latest/download/appcast.xml`.

- **Platform Scope**: `supportsSelfUpdate` (`lib/platform.dart`) gates update logic (macOS and Windows desktop only; excludes Linux and mobile).
- **Background Downloads**: Downloads update artifacts in the background with tracked byte progress before notifying the user.
- **Silent Installation**:
  - **macOS**: Mounts the signed and notarized DMG via `hdiutil attach`, waits for the running app PID to terminate, copies the new bundle via `ditto`, detaches the mount, and relaunches with `open -n`.
  - **Windows**: Executes the Inno Setup executable installer detached with `/VERYSILENT /SP- /NORESTARTAPPLICATIONS` and terminates the current instance.
- **Code Signing & Notarization**:
  - macOS builds are signed with Apple Developer ID Application certificates and notarized via `notarytool` using `scripts/sign-macos.sh`.
  - Windows builds are packaged via Inno Setup (`windows/inno/setup.iss`) or packaged as MSIX for the Microsoft Store (`.github/workflows/publish_microsoft_store.yaml`).
- **Startup Check**: Pure Dart HTTP request (`UpdateService.checkForUpdate`), unawaited in `_bootstrap`. Does not interrupt active playback or room sessions.
