# thodw_aqx

Flutter app for deck operations and diver check‑ins. Deployed to GitHub Pages at:

- https://rickc2025.github.io/thodw_app/

## Web deployment notes (iPad compatibility)

On iPadOS, Safari defaults to “Request Desktop Website,” which makes the browser identify as desktop Safari. Flutter’s default auto renderer may select the CanvasKit/WASM renderer for desktop user‑agents, which can fail on some iPads (older GPUs/OS or WebAssembly limitations), resulting in a blank page.

To ensure maximum compatibility, this app forces the HTML renderer via:

- `docs/index.html`: `<meta name="flutter-web-renderer" content="html">`
- `web/index.html`: same meta (so future builds inherit the setting)

If you change renderers, test on iPad Safari with and without “Request Desktop Website.”

## Local development

Run on web:

```pwsh
flutter run -d chrome
```

Build for GitHub Pages (project site under `/thodw_app/`):

```pwsh
flutter build web --base-href "/thodw_app/" --release
# Copy build/web to docs/ (or configure your workflow)
```

## Structure

- `lib/app.dart` – root `MyApp` and theme
- `lib/main.dart` – minimal entrypoint (initialization only)
- `lib/screens/*` – UI screens
- `lib/widgets/*` – shared widgets
- `lib/services/*` – data helpers (Hive)
- `lib/core/*` – constants, utils, navigation

## Requirements

- Flutter 3.x
- Web support enabled
- GitHub Pages configured to serve the `docs/` folder
