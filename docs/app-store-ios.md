# iOS App Store submission pack

Reference for shipping the iOS build (bundle id `app.synctogether`, universal purchase with the Mac app, ASC app id 6809185202). Drafts here are meant to be pasted into App Store Connect; nothing in this file is read by CI. The listing draft lives in `store/ios/listing_en-US.json`.

## Reviewer notes (paste into App Review Information > Notes)

> SyncTogether plays one video in lockstep on every phone in a "room".
>
> SIGN-IN: Sign in with Apple, Google, an email code, or "Continue as guest" (one tap, a quick automatic captcha appears first). The demo account in the Sign-In fields uses "Continue with email" and the password field.
>
> TESTING WITH ONE DEVICE: everything except the second person's view works on a single device. Tap "Create room", then pick YouTube (paste any public youtube.com link) or "Local file" (pick a video from the Files app). Play, pause and seek; send chat; tap reactions; open the facecam/voice controls. To watch synchronisation, join the same room from a second device or the Simulator as a guest using the 6-character code shown in the room; the host's play/pause/seek then appear on both.
>
> BACKGROUND AUDIO (UIBackgroundModes = audio, guideline 2.5.4): a room's video audio and live voice chat keep playing when the user switches apps or locks the screen, like any media or call app. The mode is not used for anything else (no location, no VoIP push, no silent audio).
>
> CAMERA / MICROPHONE: camera = profile photo (Profile > avatar > Take photo) and video facecams in a room; microphone = voice chat in a room. Each is requested the first time it is needed.
>
> LOCAL NETWORK: iOS shows this prompt because WebRTC (voice/video) gathers local network candidates to find the best direct route between friends. It is optional; calls still work through our relay if declined.
>
> CONTENT / GUIDELINE 5.2: SyncTogether has no catalogue and hosts no third-party content. Users play (a) files already on their own device, which stay on the device unless a signed-in host chooses to stream their own file to the members of their private room, and (b) public YouTube videos through YouTube's official embedded IFrame player (YouTube's terms, ads and attribution intact, no downloading, no YouTube sign-in). Rooms are private and joined by code. Copyright complaints go to https://synctogether.app/dmca and are actioned by room takedown and account ban.
>
> USER-GENERATED CONTENT (1.2): chat and display names/avatars are visible to room members. Members can report a user or room and block a user from inside the room (Report and Block actions in the room; confirm the exact menu path on a device before pasting); the host can remove members; reports are reviewed by us, and abusive accounts are banned. Contact: support@synctogether.app.
>
> ACCOUNT DELETION (5.1.1(v)): Profile > Delete account removes the account and its data.
>
> IN-APP PURCHASE (3.1.1 / 3.1.2): two auto-renewing subscriptions in the group "SyncTogether Premium" (Premium Monthly, Premium Annual). Open the crown "Premium" chip in the lobby or Profile > Go Premium. The screen shows StoreKit prices, renewal terms, Restore purchases, and Terms of Use / Privacy Policy links. The app has no other way to pay and never links to one. The demo account is on the free plan so the purchase buttons are visible.

Points the existing notes in ASC (copied from the Mac submission) get wrong or lack for iOS: they say "Premium bought on our website also unlocks the same account", but there is no web checkout any more (`docs/agent/backend-and-entitlements.md`), so delete that sentence; they never mention background audio, local network or Sign in with Apple. The demo password is stored in App Store Connect (Review Information), not in this repo.

## Export compliance (`ITSAppUsesNonExemptEncryption`)

`ios/Runner/Info.plist` declares `false`, matching `macos/Runner/Info.plist` (which has been through review). Honest assessment: HTTPS/TLS through the OS is exempt, but libwebrtc (LiveKit voice/video) ships its own BoringSSL for DTLS-SRTP, which Apple's questionnaire counts as "standard encryption algorithms in addition to the OS". It uses only IETF-standard protocols and no proprietary cryptography, so the usual position for this class of app is the mass-market exemption, but whether to declare `false` or file the self-classification is the owner's call (ASC > App Information > Export Compliance). No build is blocked either way; with the key present TestFlight does not prompt.

## Privacy: App Privacy ("nutrition label") answers

Source of truth: `website/app/privacy/page.tsx`, `docs/agent/ui-and-av.md` (Analytics), `lib/main.dart` (Sentry has no `setUser`, no PII). Tracking: **No** (no ad SDKs, no cross-app/site linking; PostHog is first-party analytics with an in-app opt-out). The bundled `ios/Runner/PrivacyInfo.xcprivacy` declares the same set.

| Data type | Collected | Linked to user | Purpose | Notes |
|---|---|---|---|---|
| Contact info > Email address | Yes | Yes | App functionality | Apple/Google/email-code sign-in (Apple relay address possible) |
| Contact info > Name | Yes | Yes | App functionality | Display name |
| Identifiers > User ID | Yes | Yes | App functionality, Analytics | Supabase user id; PostHog distinct_id (random id for signed-out runs) |
| User content > Photos or videos | Yes | Yes | App functionality | Profile avatar; host's file when Cloud Media Sharing is used (temporary R2 storage) |
| User content > Other user content | Yes | Yes | App functionality | Persisted room chat, handle, room names |
| Purchases > Purchase history | Yes | Yes | App functionality | Apple subscription transactions in `apple_subscriptions` |
| Usage data > Product interaction | Yes | Yes | Analytics | PostHog events (no chat, filenames, paths or YouTube ids) |
| Diagnostics > Crash data, Performance data, Other diagnostic data | Yes | No | App functionality | Sentry |
| Audio / video (voice, facecams) | Not declared | - | - | Real-time relay via LiveKit, never recorded or stored; if you prefer to be conservative, declare Audio data and Photos or videos as App functionality, not linked |
| Location, contacts, health, financial, browsing, search, sensitive info | No | | | |

## Age rating (current ASC answers vs recommendation)

Current (both app infos): messaging and chat = yes, user-generated content = **no**, unrestricted web access = no, override 13+. Recommendation: set **User-generated content = yes** (persisted chat, handles, avatars, shared rooms; the Mac and iOS records must agree and the UGC answer is what reviewers check against guideline 1.2). Leave unrestricted web access = no (the only web surface is the YouTube embed for a pasted link, not a browser) but be ready to explain it. Keep the 13+ override.

## Required-reason APIs

Pods and plugins that ship their own `PrivacyInfo.xcprivacy`: Sentry, OrderedSet, WebRTC-SDK, app_links, connectivity_plus, device_info_plus, file_selector_ios, flutter_inappwebview_ios, in_app_purchase_storekit, ios_document_picker, package_info_plus, path_provider_foundation, shared_preferences_foundation, url_launcher_ios, wakelock_plus, accessing_security_scoped_resource. **No manifest** in: flutter_webrtc, livekit_client, media_kit_video, sign_in_with_apple, storage_space, and the vendored full-codec libmpv/FFmpeg xcframeworks (`third_party/media_kit_libs_ios_video`). `ios/Runner/PrivacyInfo.xcprivacy` therefore also declares UserDefaults (CA92.1), FileTimestamp (C617.1, 3B52.1), SystemBootTime (35F9.1) and DiskSpace (E174.1, `storage_space` in `lib/rooms/media_sharing_cache.dart`) so ITMS-91053 does not fire for those frameworks. After the first real archive, open Xcode > Product > Archive > Generate Privacy Report and compare; it is the only authoritative check and could not be run here.

## Screenshots needed

ASC currently holds **zero iOS screenshots** (the iOS version record is a stale `1.9.0` in PREPARE_FOR_SUBMISSION with no screenshot sets and no build; a `1.14.0` iOS version must be created). `store/*.jpg` (1920x1080) and `store/mac/*.jpg` (2880x1800) are desktop sizes and are rejected for iOS.

| Set | Size | Required |
|---|---|---|
| iPhone 6.9" | 1320x2868, 1290x2796 or 1260x2736 portrait (landscape swapped) | Yes, 1-10 |
| iPhone 6.5" | 1284x2778 or 1242x2688 | Only if no 6.9" set |
| iPad 13" | 2064x2752 or 2048x2732 | Yes **only if** `TARGETED_DEVICE_FAMILY` stays `1,2` (currently does) |

Shoot with `--dart-define=DEMO_MODE=true` (as for the Mac set). If iPad is not going to be tested on hardware, the lowest-risk option is to ship iPhone-only for this release (`TARGETED_DEVICE_FAMILY = 1` in all three `Runner` configurations): reviewers test iPad builds on an iPad and a layout crash there is a rejection. Info.plist already lists all four iPad orientations, so multitasking is not blocked.

## iPhone Duo screenshots

App Store Connect has its own **iPhone Duo** slot (`APP_IPHONE_DUO`) that takes the device's native sizes: 2007x2853 / 2853x2007 (inner display) and 1398x2034 / 2034x1398 (outer). Portrait and landscape can share one set. Upload the raw simulator captures (`store/ios/screenshots/duo-native/`), not captioned cards on an iPhone canvas.

- `asc` older than 6.x does not know the type (`unsupported screenshot display type`); `brew upgrade asc`, then `asc screenshots upload --device-type IPHONE_DUO`.
- Simulator PNGs carry an alpha channel, which ASC rejects: flatten with `magick in.png -background '#121010' -alpha remove -alpha off PNG24:out.png`.
- A version **in review** cannot get a new screenshot set ("Can't Create Screenshot Set while In Review"): withdraw with `asc submit cancel --id <submission> --confirm`, upload, resubmit (the queue position resets).
- The inner display only renders while Device Hub is running; the posture buttons at the bottom of its window pick folded / half-folded / unfolded (a reboot of the simulator resets it to folded).

## Pre-submit checklist (state as audited 2026-11-05)

Done in repo: camera/local-network usage strings, Runner privacy manifest, ATS comment, Sign in with Apple entitlement and capability, IAP capability, Apple distribution cert and ASC key secrets.

Owner-only: tax/banking/paid-apps agreement active; create the iOS `1.14.0` version record; screenshots; age-rating UGC change; reviewer notes + demo credential; review the App Privacy answers above; Content Rights answer (ASC currently says the app uses no third-party content, but it embeds YouTube, so "yes, and I have the rights" is the defensible answer); first CI run of `publish_ios_app_store.yaml` with `publish_to_store` on, then TestFlight smoke test on a real iPhone (background audio, camera, local-network prompt, purchase with a sandbox account, Sign in with Apple, delete account).
