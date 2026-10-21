#!/usr/bin/env python3
"""Render the DMG Finder-window background (dmg/background.png and dmg/background@2x.png): white, one black arrow
between the app icon (left) and the Applications link (right). Geometry matches scripts/build-dmg.sh. Needs Pillow."""
import os
from PIL import Image, ImageDraw

WIDTH, HEIGHT = 660, 400
ARROW_Y = 180            # vertical centre of the icons (ICON_Y in build-dmg.sh)
ARROW_X0, ARROW_X1 = 300, 360
OUT = os.path.join(os.path.dirname(__file__), "..", "dmg")


def render(scale):
    img = Image.new("RGB", (WIDTH * scale, HEIGHT * scale), "white")
    d = ImageDraw.Draw(img)
    s = scale
    d.line([(ARROW_X0 * s, ARROW_Y * s), (ARROW_X1 * s, ARROW_Y * s)], fill="black", width=2 * s)
    d.polygon([(ARROW_X1 * s, ARROW_Y * s), ((ARROW_X1 - 12) * s, (ARROW_Y - 8) * s), ((ARROW_X1 - 12) * s, (ARROW_Y + 8) * s)], fill="black")
    return img


os.makedirs(OUT, exist_ok=True)
render(1).save(os.path.join(OUT, "background.png"))
render(2).save(os.path.join(OUT, "background@2x.png"))
print("wrote dmg/background.png and dmg/background@2x.png")
