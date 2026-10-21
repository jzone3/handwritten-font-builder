#!/usr/bin/env bash
# Round-trip test for the .strokes.json writer/reader against FORMAT.md: compiles the format code with a small
# driver (no Xcode project needed), exports a sample file, validates it with scripts/validate-strokes.py, imports it back.
set -euo pipefail
cd "$(dirname "$0")/.."
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

cat > "$WORK/main.swift" <<'SWIFT'
import Foundation

var glyphs: [Character: [Stroke]] = [:]
glyphs["A"] = [[StrokePoint(x: 0.12, y: 0.74, t: 0), StrokePoint(x: 0.30, y: 0.21, t: 80), StrokePoint(x: 0.48, y: 0.74, t: 160)],
               [StrokePoint(x: 0.20, y: 0.55, t: 0), StrokePoint(x: 0.40, y: 0.55, t: 50)]]
glyphs["\""] = [[StrokePoint(x: 0.5, y: 0.2, t: 0)]]          // a dot, and a key that needs escaping
glyphs["\\"] = [[StrokePoint(x: 0.1, y: 0.2, t: 0), StrokePoint(x: 1.3, y: 0.76, t: 120)]]
glyphs["z"] = []                                               // "drawn as nothing" must not be written
let contents = StrokeFile.Contents(fontName: "Test \"Hand\"", glyphs: glyphs)
let data = StrokeFile.encode(contents)
try data.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))

let back = try StrokeFile.decode(data)
precondition(back.fontName == contents.fontName, "fontName round trip")
precondition(Set(back.glyphs.keys) == Set(["A", "\"", "\\"]), "glyph keys round trip: \(back.glyphs.keys)")
precondition(back.glyphs["A"]!.count == 2 && back.glyphs["A"]![0].count == 3, "stroke counts")
precondition(abs(back.glyphs["A"]![0][1].y - 0.21) < 1e-9 && back.glyphs["A"]![0][1].t == 80, "point values")
precondition(back.glyphs["\\"]![0][1].x == 1.3, "x may exceed 1")

// Files from the website: [x, y] points, no t, unknown keys, empty glyph arrays.
let web = """
{"format":"handwritten-font-strokes","version":1,"source":"web","extra":true,
 "glyphs":{"B":[[[0.1,0.2],[0.3,0.4]]],"C":[],"ab":[[[0,0]]]}}
"""
let fromWeb = try StrokeFile.decode(Data(web.utf8))
precondition(fromWeb.glyphs.keys.sorted() == ["B"], "web import keys: \(fromWeb.glyphs.keys)")
precondition(fromWeb.glyphs["B"]![0][1].t == 0, "missing t reads as 0")
precondition((try? StrokeFile.decode(Data("{\"format\":\"other\",\"version\":1,\"glyphs\":{}}".utf8))) == nil, "wrong format rejected")
print("round trip OK")
SWIFT

swiftc -O -o "$WORK/test" HandwrittenFontBuilder/Model/GlyphSet.swift HandwrittenFontBuilder/Model/StrokeFile.swift "$WORK/main.swift"
"$WORK/test" "$WORK/out.strokes.json"
cat "$WORK/out.strokes.json"
python3 scripts/validate-strokes.py "$WORK/out.strokes.json"
