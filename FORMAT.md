# Stroke file format (`.strokes.json`)

The website and the Mac app exchange one JSON file. The Mac app captures strokes on the trackpad and
exports this file; the website imports it, builds the font, and can also export the same file as a
project save. Either side must accept files written by the other.

```json
{
  "format": "handwritten-font-strokes",
  "version": 1,
  "source": "mac-app",
  "fontName": "Jared Hand",
  "createdAt": "2026-10-21T08:00:00Z",
  "glyphs": {
    "A": [ [[0.12, 0.74], [0.30, 0.21], [0.48, 0.74]], [[0.20, 0.55], [0.40, 0.55]] ],
    "a": [ ... ],
    "0": [ ... ],
    "!": [ ... ]
  }
}
```

- `glyphs` keys are the characters themselves (one Unicode character, e.g. `"A"`, `"a"`, `"7"`, `"&"`, `"\""`).
  Missing keys = not drawn yet. An empty array = drawn as nothing (space-like); the website treats it as missing.
- Each glyph is a list of strokes. Each stroke is a list of points `[x, y]` (optionally `[x, y, t]` with `t` in
  milliseconds since the stroke started; readers ignore extra values). A stroke with one point is a dot.
- Units: **1.0 = the height of the glyph box** (one em). `y` grows downward: `0` = top of the box, `1` = bottom.
  `x` grows rightward from the left edge of the box and may exceed 1 for wide glyphs like `W` or `m`.
- Guide lines inside the box (both apps draw these; writers should place letters against them):
  - ascender / top of box: `y = 0.00`
  - cap height: `y = 0.20`
  - x-height: `y = 0.46`
  - **baseline: `y = 0.76`**
  - descender / bottom of box: `y = 1.00`
- The drawing box is wider than tall. Recommended box aspect is the Mac trackpad's, about 1.6 : 1, so `x` ranges
  about `0..1.6`. The website's pad uses the same aspect.
- Glyph advance width is NOT stored; the website computes it from the ink bounds (left/right of the drawn
  strokes plus side bearings). So draw each letter anywhere horizontally; only vertical placement matters.
- The space character is never stored; the website gives it a fixed width.
- `source` is `"mac-app"` or `"web"`. `fontName` is optional. Unknown top-level keys are ignored.

## Character set (both apps offer these, in this order)

```
A-Z  a-z  0-9  . , ! ? ' " - _ ( ) [ ] { } / \ : ; @ # $ % & * + = < > ~ ^ | `

The website only asks people to draw the opening `( [ { <`; when `) ] } >` are missing from a file it mirrors
the opener left-to-right. A file that does contain them is used as-is. Curly quotes (`‘ ’ “ ”`), dashes
(`‐ – — −`) and `·` are derived from `' " - .` at font-build time and are never stored. `~ ^ | \`` are
offered last as optional.
```

A font can be exported as soon as at least one glyph is drawn; missing glyphs fall back to the system font
in the browser preview and are simply absent from the exported font.
