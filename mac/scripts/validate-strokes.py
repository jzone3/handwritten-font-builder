#!/usr/bin/env python3
"""Check a .strokes.json file against FORMAT.md. Usage: validate-strokes.py FILE  (exit 1 and a message on the first problem)."""
import json, sys

CHARS = list("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789" + ".,!?'\"-_()[]{}/\\:;@#$%&*+=<>~^|`")

def fail(msg):
    sys.exit(f"INVALID: {msg}")

d = json.load(open(sys.argv[1]))
if d.get("format") != "handwritten-font-strokes": fail(f"format is {d.get('format')!r}")
if d.get("version") != 1: fail(f"version is {d.get('version')!r}")
if d.get("source") not in ("mac-app", "web"): fail(f"source is {d.get('source')!r}")
if "fontName" in d and not isinstance(d["fontName"], str): fail("fontName is not a string")
if not isinstance(d.get("glyphs"), dict): fail("glyphs is not an object")
points = 0
for key, strokes in d["glyphs"].items():
    if key not in CHARS: fail(f"glyph key {key!r} is not in the character set")
    if not isinstance(strokes, list): fail(f"{key!r}: strokes is not a list")
    for stroke in strokes:
        if not isinstance(stroke, list) or not stroke: fail(f"{key!r}: empty or non-list stroke")
        for p in stroke:
            if not (isinstance(p, list) and len(p) >= 2 and all(isinstance(v, (int, float)) for v in p)): fail(f"{key!r}: bad point {p!r}")
            if not (-0.5 <= p[1] <= 1.5): fail(f"{key!r}: y={p[1]} is far outside the box")
            if len(p) >= 3 and p[2] < 0: fail(f"{key!r}: negative timestamp")
            points += 1
print(f"OK: {len(d['glyphs'])} glyphs, {points} points, font {d.get('fontName')!r}, source {d['source']}")
