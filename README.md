# Decant

Paste anything; Decant detects the format and converts it. Native macOS app (SwiftUI, macOS 14+).

```bash
swift run Decant      # build and launch
swift test            # engine tests
```

- `Sources/DecantCore` — deterministic detection/conversion engine (escaped JSON, JSON, Base64 with nested decoding, JS/TS, Unix time). No network, no AI.
- `Sources/Decant` — the app. History is stored in `~/Library/Application Support/Decant/history.json`.
- JS/TS formatting uses a small built-in token formatter (indentation, spacing, semicolons). It doesn't wrap long lines. If you need full Prettier output, bundle Prettier and run it through JavaScriptCore.
- Debug builds: `DECANT_INPUT=… DECANT_SNAPSHOT=out.png [DECANT_DARK=1] .build/debug/Decant` writes a PNG of the window and quits.
