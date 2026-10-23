---
name: release
description: >-
  Cut a SyncTogether release across the app stores (Mac App Store, Microsoft Store and iOS App Store). Analyzes commits since the last release tag, bumps the pubspec version, pushes to main, writes user-facing release notes, and dispatches the store workflows. Use when the user says "cut a release", "ship a release", "publish everywhere", "release to stores", "bump the version and publish", or "/release". Targets: "/release" (Mac + Microsoft Store, default), "/release ios", "/release all" (all three stores). Optional version override (e.g. "/release 0.5.0", "/release all patch").
---

# Cut a release

Bumps `version:` in pubspec.yaml, commits and pushes to `main`, and triggers the
`publish_stores.yaml` workflow. **Do NOT create or push a git tag** - the
workflow's `tag` job tags the built commit itself as `v<version>` once a store
job has succeeded; a locally pushed tag would be a duplicate. (Older releases
carry `v<version>_<run_id>` tags from the retired installer workflow.)

There is **no direct distribution any more**: no GitHub release, no installers,
no appcast, no in-app updater. The stores deliver updates. If the user asks
for a direct build, tell them it was removed with the Creem/web-billing pivot.

The tag is created with `gh api POST /git/refs`, **not `git push`**. A pushed ref
is rejected with "refusing to allow a GitHub App to create or update workflow ...
without `workflows` permission" whenever the history being pushed touches a
`.github/workflows` file, and `GITHUB_TOKEN` can never hold that permission (1.11.0
hit this). The REST call points a ref at an existing commit and changes no files.

**Do not push to `main` between dispatching and the run finishing.** Let the
run finish (or cancel it) first, then push and re-dispatch.

## Release Targets

- **Desktop App Stores (`/release`, `/release stores`)**:
  Dispatches `publish_stores.yaml`. Builds store artifacts with `--dart-define=STORE_BUILD=true`:
  - Windows: MSIX package submitted to Microsoft Partner Center via `publish_microsoft_store.yaml`.
  - macOS: Sandboxed PKG installer submitted to Mac App Store Connect via `publish_mac_app_store.yaml`.
  - iOS/iPadOS: **opt-in** (`publish_to_ios_app_store` defaults to false), see below.
- **iOS App Store (`/release ios`, or `/release stores ios`)**:
  Dispatches `publish_ios_app_store.yaml` directly, or `publish_stores.yaml` with
  `-f publish_to_ios_app_store=true` when the desktop stores go too. It uploads a
  signed IPA to App Store Connect, where it lands in **TestFlight only**. The
  upload does not submit for review; that is a separate `asc` step (below).
- **All stores (`/release all`)**:
  Dispatches `publish_stores.yaml -f publish_to_ios_app_store=true`.

## Steps

1. **Preflight** - abort with a clear message if any of these fail:
   - `git branch --show-current` must be `main`.
   - Working tree must be clean (`git status --porcelain` empty). If dirty, stop
     and tell the user what's uncommitted - never bundle unrelated changes into
     the bump commit.
   - `git pull --ff-only origin main` must succeed.

2. **Find the last release** - release tags look like `v1.12.0` (older ones
   `v0.3.0_20682763842`, version + run id), created by CI:

   ```bash
   git tag --sort=-creatordate | grep -E '^v[0-9]' | head -1
   ```

   The `grep` matters: the repo also carries non-release tags such as
   `deps-libmpv-win-<date>` (the Windows libmpv mirror), and a bare `head -1`
   returns that one and makes the whole commit range wrong.

   Extract the version from the tag name (strip leading `v` and any trailing
   `_<run_id>`). Sanity-check it against `version:` in pubspec.yaml - they
   should match; if they don't, tell the user and ask before continuing.

3. **Decide the new version.**
   - If the user passed an explicit version (`0.5.0`) or a bump keyword
     (`patch` / `minor` / `major`), use that and skip the analysis.
   - Otherwise analyze `git log <last-tag>..HEAD --oneline`. If there are zero
     commits, abort - there is nothing to release. Read the commit subjects
     (use `git show --stat` on any that are unclear) and pick the bump using
     the 0.x scheme this app follows:
     - **minor** - any new user-facing feature or capability (new screens,
       modes, sync features, redesigns), or a breaking/behavioral change.
     - **patch** - only fixes, polish, refactors, CI/docs/chores.
     - **major** (→ 1.0.0) - never infer this; only when the user explicitly
       asks for it.
   - State the chosen version **with a one-line rationale citing the commits
     that drove the decision**, then proceed - no confirmation needed unless
     the analysis is genuinely ambiguous.

   Even when the user passed an explicit version and the bump analysis is
   skipped, still read `git log <last-tag>..HEAD --oneline` - the release
   notes in step 6 are written from it either way.

4. **Bump** - edit the `version:` line in pubspec.yaml (bare `X.Y.Z`, no
   `+build` suffix - CI's version extraction depends on this format).

5. **Commit and push** - message follows repo precedent, exactly:

   ```
   Bump app version to X.Y.Z
   ```

   No co-author trailers. Then `git push origin main`.

   That subject line is matched by a `startsWith` guard in `test.yaml`, which
   skips the push-triggered test run for a bump commit - the dispatch in step 6
   re-runs both suites on the same tree and gates the release on them, so the
   push-triggered run is pure duplication. Rewording the subject only costs the
   duplicate run back; it cannot let an untested commit reach a release.

6. **Write the release notes and trigger the workflow.** Compose a Markdown
   "What's Changed" section from the commits since the last tag - user-facing
   summaries grouped by theme, not raw commit subjects. Lead with features,
   then fixes; fold internal work (CI, refactors, docs) into a single line or
   omit it. Keep it short - a handful of bullets. Include the heading, e.g.:

   ```markdown
   ## What's Changed
   - The desktop app now opens in fullscreen
   - Room names are length-limited on both client and server
   - Faster CI builds (Windows 14 min → 90 s)
   ```

   > [!IMPORTANT]
   > **Release Notes Audience Guidelines**:
   > 1. **Filter Out Internal Developer Noise**:
   >    - NEVER include CI/CD workflows, build scripts, GitHub Actions, or FVM bumps.
   >    - NEVER include internal refactors, code styling/formatting (`dart format`), or linter fixes.
   >    - NEVER include test suites (`pgTAP`, unit tests), local dev tooling (`dev.sh`), or scratch scripts.
   >    - NEVER mention database tables, RLS policies, RPC names, regexes, or raw dependency names.
   > 2. **Translate to Human Benefits**:
   >    - *Technical commit*: `feat(rooms): add persistent rooms that rest between sessions`
   >      -> *User-friendly note*: **Rooms That Stay**: Premium rooms now wait for you between shows, so your name, code and invite link are ready next time.
   >    - *Technical commit*: `feat(auth): add sign in with apple, passwordless email otp`
   >      -> *User-friendly note*: **Sign In with Apple & Email Code**: You can now sign in instantly with your Apple ID or request a quick, passwordless login code sent to your email.
   >    - *Technical commit*: `fix(media): resolve sync drift on high-latency WebRTC facecam streams`
   >      -> *User-friendly note*: **Smoother Video Sync**: Improved playback synchronization and video facecam stability on slower internet connections.
   > 3. **Format**:

   The notes are not a workflow input any more: they become the stores' "What's
   New". Mac App Store reads `metadata/version/X.Y.Z/en-US.json` (add it **before**
   dispatching, or the version keeps its copied What's New) and the Microsoft
   Store reads `metadata/msstore_listing_en-US.json`. Write the user-facing notes
   into both, commit them with the bump, then dispatch:

   ```bash
   gh workflow run publish_stores.yaml --ref main
   ```

   For iOS, add `-f publish_to_ios_app_store=true` to that dispatch, or on its own:

   ```bash
   gh workflow run publish_ios_app_store.yaml --ref main
   ```

   TestFlight *is* the iOS pre-release channel. Three things differ from the desktop stores:
   - **Build numbers come from `github.run_number`**, not pubspec (which stays a
     bare `X.Y.Z`). Never add a `+build` suffix to get a new iOS build; re-run
     the workflow instead.
   - **The iOS App Store version must match pubspec.** App Store Connect keeps a
     separate version record per platform. If the iOS one is still on the
     previous number, create or rename it
     (`asc versions create --app 6809185202 --platform IOS --version X.Y.Z --copy-metadata-from <prev>`),
     or the uploaded build has nothing to attach to.
   - **Submitting for review is manual and deliberate.** Once the build has
     processed, use the `asc-release-flow` skill: attach the build, run
     `asc validate --platform IOS`, then submit. Never submit without the
     user's go-ahead: review cannot be undone cleanly.

   **Desktop Stores Review & Listing Lifecycle (`publish_stores.yaml`):**

   - **Mac App Store (`asc`)**:
     `publish_mac_app_store.yaml` now does the whole path itself when the App Store Connect API key secrets are set: it uploads the `.pkg`, waits for Apple to finish processing (`asc builds wait`), creates the macOS version record if missing (copying metadata from the live version), pushes `metadata/version/X.Y.Z` (What's New), runs `asc validate`, then attaches the build and submits for review (`asc review submit --confirm`). Without the API key (Apple ID fallback only) it uploads and warns that review submission is manual.
     - **Secrets**: `APP_STORE_CONNECT_KEY_ID`, `APP_STORE_CONNECT_ISSUER_ID` and `APP_STORE_CONNECT_API_KEY_P8` (the full `.p8`, BEGIN/END lines included; an App Manager role key). `APPLE_ID` / `APPLE_APP_SPECIFIC_PASSWORD` can only upload, not drive review, so they are the fallback, not a substitute.
     - **Before releasing**, add `metadata/version/X.Y.Z/en-US.json`, or the version keeps its copied What's New.
     - **Opt out** of auto-submission with `-f submit_for_review=false` on a direct `publish_mac_app_store.yaml` dispatch (the `publish_stores.yaml` fan-out always submits).
     - **Screenshots are still manual** (only needed when the UI changed): `asc screenshots upload --app 6809185202 --version "X.Y.Z" --locale en-US --platform MAC_OS --display-type APP_DESKTOP --files assets/store/mac/*.jpg`, and do it *before* the build is submitted.
     - If the submit step fails, check `asc review status --app 6809185202 --platform MAC_OS`; the build is already uploaded, so fix the cause and submit by hand with `asc review submit`.

   - **Microsoft Store (`msstore`)**:
     1. **Automated Publishing**: CI automatically runs `msstore reconfigure` with GitHub Actions secrets and `msstore publish` with the built `.msix`.
     2. **State Machine Invariant**: A committed package submission progresses through `CommitStarted` -> `PreProcessing` -> `Certification` -> `Published`. During `PreProcessing` and `Certification`, Microsoft Partner Center locks the submission against metadata edits (`InvalidState`).
     3. **Listing Metadata Updates**: Canonical listing text and release notes are maintained in `metadata/msstore_listing_en-US.json`. Once the package submission finishes certification and publishes (or on a draft submission before commit), push updated listing metadata via:
        ```bash
        msstore submission updateMetadata 9P1BZTSXHDFS -p metadata/msstore_updated_submission.json
        msstore submission publish 9P1BZTSXHDFS
        ```
     4. **Store Assets**: 16:9 desktop screenshots reside in `assets/store/*.jpg` (1920 x 1080) and store logos (`store_logo_300x300.png`, `store_logo_150x150.png`).

   The dispatch is async - poll until the new run appears:

   ```bash
   gh run list --limit 3 --json workflowName,url,createdAt,status
   ```

   (re-run the list command if the newest run predates the dispatch; it
   usually appears within a few seconds).

   **Re-running after a failure - dispatch only the leg that failed.** `publish_stores.yaml`
   fans out to Microsoft Store, Mac App Store and (opt-in) iOS, and each leg submits
   independently. If the Microsoft Store leg already succeeded, dispatching
   `publish_stores.yaml` again would resubmit the same version to Partner Center. Check
   first:

   ```bash
   gh run view <run-id> --json jobs --jq '.jobs[] | .name + " => " + (.conclusion // .status)'
   ```

   then dispatch just the failed workflow, e.g.
   `gh workflow run publish_mac_app_store.yaml --ref main -f publish_to_store=true -f submit_for_review=true`.
   The `tag` job only runs when a store job succeeded, so a fully failed run leaves no tag.

   **Reading a failure.** `gh run view <id> --log-failed` is dominated by checkout cleanup
   noise. Filter it: `gh run view <id> --log-failed | grep -E '##\[error\]|rejected|denied'`.

   **macOS caches must be exact-key.** `publish_mac_app_store.yaml`
   caches `macos/Pods`; restoring an older one through `restore-keys` skips CocoaPods and
   embeds a stale, slim `Avcodec`, which the "full-codec" assertion then (rightly) fails.
   Keep `third_party/**` in the key and do not add a `restore-keys` fallback.

7. **Report and stop** - print the new version and the run URL(s). Do **not**
   watch the build (it takes 15-30 min). Remind the user that each store has its
   own review queue: Mac and iOS builds land in App Store Connect (Mac is
   auto-submitted), and the Microsoft submission goes to certification.
