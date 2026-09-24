---
name: release
description: >-
  Cut a SyncTogether release or pre-release across direct distribution (GitHub Releases + self-update appcast) and the desktop app stores (Microsoft Store & Mac App Store). Analyzes commits since the last release tag, bumps the pubspec version, pushes to main, writes user-facing "What's Changed" notes, and dispatches the matching workflows. Use when the user says "cut a release", "ship a release", "cut a pre-release", "publish everywhere", "release to stores", "bump the version and build installers", or "/release". Targets: "/release" (direct, default), "/release stores", "/release all". Optional version override (e.g. "/release 0.5.0", "/release all patch"); a "pre" arg (e.g. "/release pre", "/release pre minor") publishes the direct release as a GitHub pre-release.
---

# Cut a release

Bumps `version:` in pubspec.yaml, commits and pushes to `main`, and triggers the
`build_installers.yaml` workflow. **Do NOT create or push a git tag** - the
workflow's `release` job tags the commit itself as `v<version>_<run_id>` (see
`tag_name:` in `.github/workflows/build_installers.yaml`); a locally pushed tag
would be a duplicate that matches nothing.

The `release` job pushes that tag itself, from the built commit, before it calls
`softprops/action-gh-release`. That step is what makes a release survive a push
to `main` while the 15-30 min build is in flight: `GITHUB_TOKEN` is allowed to
create a release whose target is a branch *tip*, but gets a 403 "Resource not
accessible by integration" when the target commit has been overtaken - which is
how the first 0.9.0 attempt failed. Creating the tag first leaves the release
API nothing to resolve. The step is a no-op if the tag already exists, so
re-running a failed `release` job is safe.

## Release Targets

- **Direct / Sideload (`/release` or `/release direct`)**:
  Dispatches `build_installers.yaml`. Builds signed Windows Inno Setup `.exe`, macOS Developer ID `.dmg`, and signed `appcast.xml` for in-app self-updates, publishing immediately to GitHub Releases.
- **Desktop App Stores (`/release stores`)**:
  Dispatches `publish_stores.yaml`. Builds store-only artifacts with `--dart-define=STORE_BUILD=true` (in-app updater disabled):
  - Windows: MSIX package submitted to Microsoft Partner Center via `publish_microsoft_store.yaml`.
  - macOS: Sandboxed PKG installer submitted to Mac App Store Connect via `publish_mac_app_store.yaml`.
- **Unified Release Everywhere (`/release all`)**:
  Dispatches both `build_installers.yaml` AND `publish_stores.yaml` in parallel for complete multi-channel distribution.

## Self-update: what the release flow now carries

Installed desktop apps update themselves from this workflow's output, so a few
things that used to be cosmetic are now load-bearing. Nothing here needs extra
release steps - the `release` job generates and attaches `appcast.xml`
unconditionally - but do not "tidy" any of it:

- **The asset filenames and the tag format are a published contract.**
  `.github/scripts/generate-appcast.sh` composes the enclosure URLs from
  `tag_name` (`v<version>_<run_id>`) and the exact names
  `SyncTogether-<version>-{Windows.exe,macOS.dmg}`. Renaming either publishes a
  feed pointing at 404s, and every installed copy silently stops updating.
- **Every release must carry `appcast.xml`.** Apps read it through the
  `releases/latest/download/appcast.xml` permalink, which resolves to the newest
  *non-pre-release* - if that release lacks the asset, the permalink 404s and
  updates stop until the next good release.
- **Pre-releases are invisible to the updater** (that's the `/latest/`
  permalink), so `pre` is the safe way to ship something you don't want pushed
  out to existing installs.
- **The release job fails loudly on a signing mismatch.** It verifies both
  signatures against the public keys committed in the repo before publishing. If
  it fails with "drifted apart", the `SPARKLE_ED_PRIVATE_KEY` /
  `WINSPARKLE_DSA_PRIVATE_KEY` secret no longer matches
  `macos/Runner/Info.plist` / `windows/runner/resources/dsa_pub.pem` - do not
  work around it by regenerating keys, that strands every installed copy.
- **The first updater-enabled release needs a manual-install note.** Anyone on
  0.8.x or earlier has no updater, so its release notes must tell them to
  download and install this one by hand, once. macOS users should also be told
  they will be signed out once (the app left its sandbox container).

A `pre` argument (alone or alongside a version/bump arg) cuts a **pre-release**:
the flow is identical except that step 3 defaults the bump to patch, step 6
passes `-f prerelease=true` to the dispatch, and step 7 reports it as a
pre-release. Pre-releases still get a real version and tag - "promoting" one to
stable later means cutting a new, higher version, not re-tagging.

## Steps

1. **Preflight** - abort with a clear message if any of these fail:
   - `git branch --show-current` must be `main`.
   - Working tree must be clean (`git status --porcelain` empty). If dirty, stop
     and tell the user what's uncommitted - never bundle unrelated changes into
     the bump commit.
   - `git pull --ff-only origin main` must succeed.

2. **Find the last release** - release tags look like `v0.3.0_20682763842`
   (version + workflow run id, created by CI):

   ```bash
   git tag --sort=-creatordate | head -1
   ```

   Extract the version from the tag name (strip leading `v` and trailing
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
     - **pre-release** (`pre` with no version/bump arg) - default to **patch**
       unless the commits clearly warrant minor; the eventual stable release
       takes the next, higher version.
   - State the chosen version **with a one-line rationale citing the commits
     that drove the decision**, then proceed - no confirmation needed unless
     the analysis is genuinely ambiguous.

   Even when the user passed an explicit version and the bump analysis is
   skipped, still read `git log <last-tag>..HEAD --oneline` - the release
   notes in step 6 are written from it either way.

4. **Bump** - edit the `version:` line in pubspec.yaml (bare `X.Y.Z`, no
   `+build` suffix - CI's version extraction and installer names depend on
   this format).

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
   >    - *Technical commit*: `feat(updates): support silent desktop updates with auto-download toggle`
   >      -> *User-friendly note*: **Background Updates**: The desktop app now quietly downloads updates in the background, showing smooth progress and keeping your player up to date without interrupting your watch party.
   >    - *Technical commit*: `feat(auth): add sign in with apple, passwordless email otp`
   >      -> *User-friendly note*: **Sign In with Apple & Email Code**: You can now sign in instantly with your Apple ID or request a quick, passwordless login code sent to your email.
   >    - *Technical commit*: `fix(media): resolve sync drift on high-latency WebRTC facecam streams`
   >      -> *User-friendly note*: **Smoother Video Sync**: Improved playback synchronization and video facecam stability on slower internet connections.
   > 3. **Format**:

   Pass it via the workflow's `release_notes` input (it lands at the top of
   the GitHub release body, above the auto-generated Downloads section):

   ```bash
   gh workflow run build_installers.yaml --ref main -f release_notes="$(cat <<'EOF'
   ## What's Changed
   - ...
   EOF
   )"
   ```

   For a pre-release, append `-f prerelease=true` to that command (the input
   defaults to false, so stable releases never pass it).

   That dispatch is for the **direct** target (`/release`, `/release direct`,
   `/release all`). For the **stores** target (`/release stores`,
   `/release all`), also dispatch:

   ```bash
   gh workflow run publish_stores.yaml --ref main
   ```

   Pre-release only applies to the direct target; the stores have their own
   review queues.

   The dispatch is async - poll until the new run appears:

   ```bash
   gh run list --limit 3 --json workflowName,url,createdAt,status
   ```

   (re-run the list command if the newest run predates the dispatch; it
   usually appears within a few seconds).

7. **Report and stop** - print the new version and the run URL(s). Do **not**
   watch the build (it takes 15–30 min); the workflow will create the GitHub
   release, tag, and installer artifacts on its own. Remind the user the
   release will appear at
   `https://github.com/shubhamsinghshubham777/synctogether/releases` when the
   run finishes. For a pre-release, say so and note it will carry the
   Pre-release badge and stay excluded from "Latest".
