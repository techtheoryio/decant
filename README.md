# Decant

Paste anything; Decant detects the format and converts it — plus a set of focused developer tools. Native macOS app (SwiftUI + AppKit, macOS 14+). Everything runs locally.

```bash
swift run Decant      # build and launch
swift test            # engine tests
```

## Tools

| Category | Tools |
| --- | --- |
| Format | Auto Detect (New), Formatter (JSON tree/query/repair; JS, TS, CSS, SCSS, Less, HTML, XML, Markdown, YAML, GraphQL), Markdown preview |
| Encoding | Base64 (text and files, URL-safe, padding, MIME wrap, data: URIs, magic-byte detection), URL encode with query table |
| Time | Unix time (live clock, results table, date picker, time zones, differences), Cron (plain words, next runs) |
| Tokens & Security | JWT decoder with HMAC check, UUID v4/v7 + ULID generator and inspector, password generator |
| Data | CSV ↔ JSON with table preview |
| Text | Diff (side by side / unified, word highlights, folding), Regex tester, character/word/line counter |
| Miscellaneous | Color converter (color panel, eyedropper, contrast), QR code generator and reader |

Shortcuts: ⌘K command palette, ⌘1–⌘9 tools (order from Settings → Sidebar), ⌘N new document, ⌘O open file, ⌘S save output, ⇧⌘C copy output, ⌘F find in output, ⌘+ / ⌘− font size, ⌥⌘Z wrap lines.

## Notes

- `Sources/DecantCore` — deterministic engine and tool logic, no UI. `Sources/Decant` — the app.
- History lives in `~/Library/Application Support/Decant/history.json`; retention and size are set in Settings → History. Pinned entries are kept.
- The Formatter uses Biome or Prettier when either is on your login-shell `PATH` (looked up via `zsh -lic`), Biome first for the languages it supports. Without them it falls back to the built-in JSON and JS/TS formatters and Foundation's XML/HTML pretty-printer; other languages are shown unformatted.
- App icon: source `Assets/AppIcon.svg`; after editing run `Assets/make-icon.sh` (needs `rsvg-convert`) to rebuild `Sources/Decant/Resources/AppIcon.icns`.
- Debug builds: `[DECANT_TOOL=base64] DECANT_INPUT=… [DECANT_AUX=…] DECANT_SNAPSHOT=out.png [DECANT_DARK=1] .build/debug/Decant` writes a PNG of the window and quits without touching history. UserDefaults can be set per run with launch arguments, e.g. `-formatterTree YES`.
