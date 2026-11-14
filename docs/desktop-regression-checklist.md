# Desktop regression checklist (macOS and Windows)

Run this before releasing desktop builds (Mac App Store, Microsoft Store) that change shared layouts, navigation or playback - it was written for the mobile-readiness work (commits after `066bc0a`) and still covers what the unit and layout suites cannot: actually *using* the desktop apps. One column per platform: mark each item PASS / FAIL / N/A and note what you saw.

**Setup (macOS):** `./scripts/dev.sh` (Docker first), `fvm flutter run -d macos` (instance A) and `./scripts/run-instance-b.sh` (instance B, a second identity). Debug builds point at the *local* Supabase; guest sign-in needs the real `TURNSTILE_SITE_KEY` dart-define (the local GoTrue holds the real Turnstile secret). Edge/production items are marked **[PROD]**: they need a release-style build against production and a signed-in host, so they are done by the owner or with the owner's explicit say-so.

**Test media:** a short MP4 (H.264), an MKV, a MOV, a WebM, an AVI (generate small synthetic clips with ffmpeg; they are throwaway test files, not user media), plus one PDF and one image to prove rejection. A 10-bit HEVC clip and a long (30 min+) file for the proxy/cache items.

## 1. Launch and splash
- [ ] Cold start is **silent** (no sound at launch) on both platforms.
- [ ] The logo animation starts immediately (no half-second hold waiting on audio), then the app fades in; no flash of white; window remembers size/position across restarts.
- [ ] With macOS *Reduce motion* on: end state shown, hand-off fade only.
- [ ] A `synctogether://join/ABC123` link arriving during the splash still lands (toast "couldn't find a room", no error page).

## 2. Window, chrome, shortcuts
- [ ] Minimum window 900x600 holds; resize across 900, 1100, 1280, 1600 and a very wide window without overflow or clipped controls.
- [ ] macOS traffic lights / Windows min-max-close sit in the marquee bar; drag area works; fullscreen via F and Esc (and green button) stays in sync.
- [ ] Room keyboard shortcuts work when no text field is focused (space, arrows, F, H, M, C, R, E as documented in the shortcuts dialog); **typing in the chat field does not trigger them**; clicking empty space (not the field) does **not** break shortcuts afterward.

## 3. Lobby
- [ ] The greeting line ("FRI · 10:04 · GOOD MORNING, NAME") **updates when the minute changes** and is correct after the Mac sleeps and wakes (compare with the menu-bar clock).
- [ ] Open a room and Enter a code forms are both visible on desktop (no collapsed panel); creating and joining work; Streak/quota chips fold into the avatar menu as the window narrows (no wrapping).
- [ ] Tickets list, delete, "Paste invite", ended-room handling unchanged.

## 4. Navigation and back stack
- [ ] Lobby -> Leaderboard -> Profile, Back -> Leaderboard, Back -> Lobby.
- [ ] Lobby -> Profile -> Patron seats (subscribe), Back -> Profile, Back -> Lobby.
- [ ] Profile -> Leaderboard -> (profile link) does not grow the stack: Back goes once to Profile.
- [ ] Room -> Subscribe (from a locked feature) -> Back returns to the room. Leaving a room still lands on the lobby.
- [ ] Unknown route (`open "synctogether://nope"` or a bad deep link) shows the in-app "Lost in sync" page with a working "Back to lobby" button.
- [ ] Profile and Leaderboard headers: back button left-aligned, space below it, content fades in under it while scrolling; the badge tile ("+N") opens the catalog on click and shows a hover preview.

## 5. Choosing a video (the new chooser)
- [ ] Room empty state: card sits at the **bottom** of the picture, "Choose a video" opens the chooser (Files + Recent; **no Photos** on desktop). Member view shows only the waiting line.
- [ ] Files picker accepts MP4, MKV, MOV, WebM, AVI; **rejects** the PDF and image with the friendly message and the chooser stays open. Windows: the "All files" filter is offered.
- [ ] Recent shelf: the pick appears (name, size, duration, "Opened ... ago"); tapping it reopens; **after quitting and relaunching** it still reopens (macOS Store sandbox: note whether it falls back to "Locate" - known/accepted); Remove and Clear all work; renaming/moving the file shows "File moved" with Locate and Remove.
- [ ] A file that fails to open shows "Choose a different video" as the primary action ("Locate copy" only when you simply lack the host's file).
- [ ] Same movie in a different container (MKV vs MP4 of the same clip) on instance B: the gate accepts it (or shows the "Same movie" prompt once) and playback syncs.

## 6. Room layout on desktop
- [ ] Docked control bar at 1600, 1280, 1100, 900: seek bar and play/pause always visible; **no icon shrinking**; below about 820 px Audio, Subtitles and volume fold into the room menu with their current values; menu items work.
- [ ] Chat open/closed, roster column "IN THE ROOM" (unchanged on desktop - not collapsible), reactions strip, facecam rail never overlapping the bar or chat, fullscreen collapse hides header and bar together.
- [ ] Empty-room card, banners (failed file, "Same movie", fallback notice) never overlap the control bar at any width.
- [ ] Subtitle style dialog: font list scrolls, no overflow at 900x600.

## 7. Streaming shared video **[PROD]**
- [ ] Host (signed in, release-style build) uploads a video; member on another instance plays it; **starts quickly** and seeks (forward/back) respond fast.
- [ ] The player plays through the loopback proxy (a `127.0.0.1` listener exists while in the room: `lsof -iTCP -sTCP:LISTEN -nP | grep <app>`), and **the listener is gone after leaving the room**.
- [ ] Disk cache: its folder grows while watching, stays under the 3 GiB cap, and is cleared by account deletion; no leftover temp files after leaving.
- [ ] Memory and CPU during a 10+ minute watch stay steady (Activity Monitor): no growth, no runaway threads.
- [ ] Edge: the stream URL is on `media.synctogether.app`; a second viewer's start is at least as fast as the first. Turning the proxy off (`--dart-define=STREAM_PROXY=false`) still plays (direct URL).
- [ ] Connection notice: throttle the link (Network Link Conditioner or `dnctl`/`pfctl`, needs admin) below the file's bitrate: after repeated stalls a gentle, dismissible notice appears; on a fast link nothing appears; "Buffer ahead" holds the member at "loading" then releases.

## 8. Two-instance sync (use `run-instance-b.sh`)
- [ ] Play/pause/seek on A mirrors on B within the usual drift (the sync label shows a plausible +-s); late join catches up; readiness gate shows loading -> ready; reactions and chat deliver; roster shows both, ready rings correct.
- [ ] Leaving and rejoining a room reopens the remembered local file without streaming (desktop path always valid).

## 9. Audio/video and settings
- [ ] "Test your mic and camera": the **speaker-test chime still plays** (it reuses the old splash file); mic meter and camera preview work.
- [ ] Mic/camera toggles, device pickers (right-click), facecams render at 16:9, a single tile is not stretched.
- [ ] Profile: display name edit, email note names the right provider, password rows, leaderboard opt-in, handle (Patron).

## 10. Platform specifics
- **macOS:** App Store sandbox build (STORE_BUILD=true) can read user-picked files and the Recent bookmarks behave as documented; Sign in with Apple; HDR/10-bit clip plays without a tint (the copy-path guard is iOS-only, so macOS must look as before).
- **Windows:** WebView2 YouTube mode and Turnstile guest sign-in work; the picker's All files filter; window controls/snap; high-DPI scaling; Microsoft Store purchase bar unchanged.

## Evidence to keep
Screenshots at 900x600, 1280x800 and fullscreen of: lobby, room with chat, room with empty state, chooser with Recent populated, the profile and leaderboard, the badge catalog, and the Not found page. Note app version/commit, OS version, Mac model, and any FAIL with exact repro steps.
