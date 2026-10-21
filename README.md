# Handwritten Font Builder

[![Built by Devin](https://raw.githubusercontent.com/club-cog/built-by-devin/main/badges/built-by-devin.svg)](https://devin.ai)

Write a few letters, get a real font. No photo needed.

- **Website** (`site/`): draw each character with a mouse, finger or trackpad, see a live preview, and download an `.otf`. Everything runs in the browser; nothing is uploaded.
- **Mac app** (`mac/`): turns the trackpad into a drawing tablet (touch to write, lift to stop, no clicking) and exports a strokes file you drop onto the website. Much nicer than drawing with a mouse.

The two share one file format: see [FORMAT.md](FORMAT.md).

## Run the site locally

It is plain HTML/JS with no build step:

```sh
cd site && python3 -m http.server 8000
```

Then open http://localhost:8000.

## How the font is made

Strokes are rasterized with round caps, the pixel boundary is traced and simplified, and the contours become quadratic outlines in an OpenType font built with [opentype.js](https://opentype.js.org/). Guides on the pad (cap height, x-height, baseline) keep the letters lined up.

Inspired by [Ivan Leo's handwriting font](https://x.com/ivanleomk/status/2112802990482657770).
