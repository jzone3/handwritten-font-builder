# Handwritten Font Builder (macOS app)

Write each character on the trackpad with a finger. **Finish** (→ on the last glyph, ⌘⏎, or the Your Font… button) opens the site's "Your font" screen inside the app: live preview, name, thickness, Download `.otf`, Publish and Share, backed by the same database as fonts made on the website. The strokes go straight in, no file. File → Export Strokes… (`<Font Name>.strokes.json`) still works for importing on the website by hand. **New ⌘N** clears every glyph.
The file format is `FORMAT.md` at the repo root.

## Build

```sh
brew install xcodegen
cd mac
xcodegen generate
xcodebuild -project HandwrittenFontBuilder.xcodeproj -scheme HandwrittenFontBuilder -configuration Debug CODE_SIGNING_ALLOWED=NO build
```

`scripts/test-format.sh` round-trips the writer/reader and validates the output with `scripts/validate-strokes.py FILE`.

## How the trackpad path works

`Pad/PadView.swift` opts into `NSTouch` (`allowedTouchTypes = [.indirect]`) and maps `touch.normalizedPosition` to the glyph box:
pad height = box height, `x = nx * (deviceWidth / deviceHeight)`, `y = 1 - ny`. One touch identity is tracked at a time; a tap is a one-point stroke.
Touches are ignored until "Enter Trackpad Mode" (bottom-left button, ⌘T) is on: it hides the cursor, parks it over the pad and decouples it from
the trackpad (`CGAssociateMouseAndMouseCursorPosition(false)`) while a finger is down, so a finger can roam the whole pad without the cursor leaving
the view. Esc, the button, a click outside the box, opening a menu, the window resigning key, or quitting all go back to mouse mode, where the
trackpad only moves the pointer and click-drag in the box draws. The Debug build has Glyph → "Simulate Trackpad Stroke"
(⇧⌘T), which feeds synthetic touches through the same mapping code.

## Release

Pushes to `master` that touch `mac/` run `.github/workflows/release.yml`: next patch tag, signed + notarized DMG, published as
`Handwritten-Font-Builder-<version>.dmg` and the stable `Handwritten-Font-Builder.dmg`.
Secrets: `APPLE_TEAM_ID`, `MAC_CERT_P12`, `MAC_CERT_PASSWORD`, `NOTARY_KEY_P8`, `NOTARY_KEY_ID`, `NOTARY_ISSUER_ID`.
