#ifndef RUNNER_PUSH_CHANNEL_H_
#define RUNNER_PUSH_CHANNEL_H_

#include <windows.h>

#include <flutter/binary_messenger.h>

// Push notifications over WNS for the Dart `PushService`
// (lib/pairing/push_service.dart), channel `app.synctogether/push` - the same
// contract the Apple and Android runners answer.
//
//   configure                 -> null
//   permission                -> "granted" | "denied" | "unsupported"
//   request                   -> same; Windows has no prompt to show
//   token                     -> {token: <channel URI>, environment}
//   launchRoute               -> null (a toast opens a synctogether://push link)
//   openSettings              -> null
//
// A WNS channel needs package identity, so this only works in the packaged
// (MSIX) Store build; unpackaged, every call answers "unsupported" and the Dart
// side offers no switches. Taps need no native handling: the server writes the
// toast with protocol activation, so Windows launches `synctogether://push?...`
// and the app's existing deep-link handler does the rest.
//
// Channel creation blocks on the network, so it runs on a worker thread and the
// answer hops back to the platform thread with a window message (MethodResult
// is not thread safe).
void RegisterPushChannel(flutter::BinaryMessenger* messenger, HWND window);

// Posted by worker threads; the window procedure calls this on WM_APP + 0x52.
constexpr UINT kPushMessage = WM_APP + 0x52;
void RunPushCallbacks();

#endif  // RUNNER_PUSH_CHANNEL_H_
