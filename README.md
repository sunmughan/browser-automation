# Browser Automation (Android / WebLibre)

This repository builds a **debug-only Android WebLibre-based browser workspace** with an automation diagnostics dashboard.

## Upstream
- Source: https://github.com/FaFre/WebLibre
- The build workflow checks out a pinned upstream revision and applies the overlay in `overlay/`.
- WebLibre is licensed under AGPL-3.0-or-later. Preserve upstream copyright and license notices in all distributed builds.

## Current debug milestone
- Debug-only dashboard entry screen.
- Open a URL in the existing WebLibre browser.
- Import a CSV and inspect its headers/row count without displaying or transmitting personal data.
- Capture app-level Flutter errors and automation UI actions.
- Copy logs or share/export a text log file.
- GitHub Actions builds an arm64 debug APK and uploads it as an artifact.

This milestone is a browser diagnostics and staging-QA foundation. It does not automate public voting submissions, solve/bypass CAPTCHA, or bulk-submit CSV identities.

## Build
Run the **Android Debug APK** workflow from GitHub Actions, or push a change to `main`. The artifact is uploaded as `browser-automation-debug-apk`.

## Local overlay layout
```
overlay/
  apps/weblibre/lib/features/automation/
scripts/
  apply_overlay.py
.github/workflows/
  android-debug.yml
```
