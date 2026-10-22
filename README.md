# Build Your Own Font

[![Built by Devin](https://raw.githubusercontent.com/club-cog/built-by-devin/main/badges/built-by-devin.svg)](https://builtbydevin.ai/)

**https://buildyourownfont.com** — write a few letters, get a real font. No photo, no upload of anything you don't choose to share.

- **Website** (`site/`): draw each character with a finger, mouse or trackpad, see the Jabberwocky in your handwriting, download an `.otf`. When you finish, your font gets its own page (`/f/<id>`) you can share; `/fonts` is the leaderboard and the start screen shows a live ticker of new fonts. Turn publishing off with one checkbox.
- **Mac app** (`mac/`): turns the trackpad into a drawing tablet (touch to write, lift to stop, no clicking). Finish opens "Your font" right in the app (same engine and database as the site): preview, download the `.otf`, publish and share. You can also export a strokes file and import it on the website. Download: [latest release](https://github.com/jzone3/handwritten-font-builder/releases/latest).
- **API** (`api/`): small Vercel functions on top of Vercel Blob that store published fonts.

The site and the app share one file format: see [FORMAT.md](FORMAT.md).

## Run it locally

The site is plain HTML/JS with no build step:

```sh
cd site && python3 -m http.server 8000
```

Publishing needs the Vercel functions and a Blob store: `vercel dev` with `BLOB_READ_WRITE_TOKEN` set, or just deploy to Vercel and connect a Blob store to the project. Without them the site still draws and downloads fonts; publishing shows an error and nothing else breaks.

The Mac app: `cd mac && xcodegen generate && open HandwrittenFontBuilder.xcodeproj` (see [mac/README.md](mac/README.md)).

## How the font is made

Strokes are rasterized with round caps, the pixel boundary is traced and simplified, and the contours become quadratic outlines in an OpenType font built with [opentype.js](https://opentype.js.org/). Guides on the pad (cap height, x-height, baseline) keep the letters lined up; closing brackets are mirrored from the opening ones, and curly quotes and dashes reuse the plain ones you drew.

Inspired by [Ivan Leo's handwriting font](https://x.com/ivanleomk/status/2112802990482657770). MIT licensed.
