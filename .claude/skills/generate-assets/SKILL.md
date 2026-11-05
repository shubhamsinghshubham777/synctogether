---
name: generate-assets
description: >-
  Regenerate build-time assets for SyncTogether - speaker-test chime audio, reaction emoji Lottie files, Mozilla CA certificate bundle, and application icons. Use when the user asks to "regenerate assets", "update app icons", "fetch reaction emoji", "update ca bundle", or "generate the speaker-test chime".
---

# Asset Generation Runbook

All non-source media assets in `assets/` are generated via reproducible scripts in `tool/`. Never edit generated binaries or JSON files directly.

## Asset Generators

### 1. App Icons
Rebuilds vector SVGs from the design system, extracts glyphs, and generates multi-platform app icon sets:
```bash
python3 tool/generate_app_icon.py && fvm dart run flutter_launcher_icons
```
*(Requires `fonttools` and `rsvg-convert`)*

### 2. Speaker-Test Chime (`assets/sfx/splash.wav`)
Synthesizes the audio-output test chime used by the AV settings dialog (riser -> impact -> bell tail; the splash screen itself is silent):
```bash
python3 tool/generate_splash_sound.py
```
*(Standard Python library only. Filename is historical.)*

### 3. Animated Reaction Emoji (`assets/emoji/*.json`)
Downloads and SHA-256 verifies Google Noto Animated Emoji (CC BY 4.0):
```bash
python3 tool/fetch_reaction_emoji.py
```
*(Validates manifest alignment against `lib/rooms/reactions.dart`)*

### 4. Mozilla CA Root Bundle (`assets/ca/cacert.pem`)
Updates Mozilla's trusted root CA certificates for Windows TLS chain resolution:
```bash
python3 tool/update_ca_bundle.py
```
