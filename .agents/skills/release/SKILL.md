---
name: release
description: >-
  Cut a SyncTogether release across direct distribution (GitHub/website) and desktop app stores (Microsoft Store & Mac App Store). Analyzes commits since the last release tag, composes the AI "What's Changed" notes, bumps the pubspec version, pushes to main, and triggers the appropriate release workflows. Use when the user says "cut a release", "ship a release", "publish everywhere", "release to stores", or "/release". Supports "/release", "/release stores", or "/release all", with optional version arguments (e.g. "/release all 0.5.0" or "/release all patch").
---

# Cut a release

Bumps `version:` in `pubspec.yaml`, commits and pushes to `main`, and dispatches the build and publishing workflows.

> [!IMPORTANT]
> **Do NOT create or push a git tag locally** - the workflow's `release` job tags the commit itself as `v<version>_<run_id>`.

## Release Targets

- **Direct / Sideload (`/release` or `/release direct`)**:
  Dispatches `build_installers.yaml`. Builds signed Windows Inno Setup `.exe`, macOS Developer ID `.dmg`, and signed `appcast.xml` for in-app self-updates, publishing immediately to GitHub Releases.
- **Desktop App Stores (`/release stores`)**:
  Dispatches `publish_stores.yaml`. Builds store-only artifacts with `--dart-define=STORE_BUILD=true` (in-app updater disabled):
  - Windows: MSIX package submitted to Microsoft Partner Center via `publish_microsoft_store.yaml`.
  - macOS: Sandboxed PKG installer submitted to Mac App Store Connect via `publish_mac_app_store.yaml`.
- **Unified Release Everywhere (`/release all`)**:
  Dispatches both `build_installers.yaml` AND `publish_stores.yaml` in parallel for complete multi-channel distribution.

## Steps

1. **Preflight**:
   - `git branch --show-current` must be `main`.
   - Working tree must be clean (`git status --porcelain` empty).
   - `git pull --ff-only origin main` must succeed.

2. **Find last release tag**:
   ```bash
   git tag --sort=-creatordate | head -1
   ```
   Extract the version (e.g. `0.4.0` from `v0.4.0_123456`).

3. **Decide new version & target mode**:
   - Parse any target mode (`direct`, `stores`, `all`) and explicit version/bump type passed by the user.
   - If no version passed, analyze `git log <last-tag>..HEAD --oneline`:
     - **minor**: New user-facing feature/capability or behavioral change.
     - **patch**: Bug fixes, polish, refactors, docs, chores.
     - **pre-release (`pre`)**: Default to patch unless commits clearly warrant minor.

4. **Bump version**:
   Edit `version:` in `pubspec.yaml` (bare `X.Y.Z`).

5. **Commit and push**:
   ```bash
   git add pubspec.yaml
   git commit -m "Bump app version to <version>"
   git push origin main
   ```

6. **Compose User-Friendly "What's New" Release Notes**:
   When analyzing `git log <last-tag>..HEAD`, translate the technical git history into clear, user-centric language.

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
   >    Use clean markdown bullet points grouped into `### What's New` and `### Improvements & Fixes`:
   >    ```bash
   >    RELEASE_NOTES="$(cat <<'EOF'
   >    ## What's Changed
   >    
   >    ### ✨ What's New
   >    - **Feature Name**: Clear, friendly 1-2 sentence description of what the user can do now.
   >    
   >    ### 🛠️ Improvements & Fixes
   >    - **Fix or Polish**: Clear explanation of an annoyance resolved or performance boosted.
   >    EOF
   >    )"
   >    ```

7. **Trigger CI workflows**:
   - If target includes **Direct Release** (`/release` or `/release all`):
     ```bash
     gh workflow run build_installers.yaml --ref main -f release_notes="$RELEASE_NOTES"
     ```
     *(For a pre-release, append `-f prerelease=true`)*

   - If target includes **App Stores** (`/release stores` or `/release all`):
     ```bash
     gh workflow run publish_stores.yaml --ref main
     ```

8. **Monitor dispatch**:
   ```bash
   gh run list --limit 3 --json workflowName,url,createdAt,status
   ```
   Report the workflow run URL(s) and new version to the user.
