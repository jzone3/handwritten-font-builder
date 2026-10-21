/* Builds an OpenType font from traced glyph outlines with opentype.js. */
(function () {
  'use strict';

  const UPM = 1000;
  // The glyph box is taller than one em so a letter drawn to the cap-height guide
  // comes out ~700 units tall, like a normal font (box height 1250 → cap 0.56 × 1250 = 700).
  const BOX = 1250;
  const BASELINE = 0.76;      // box units from the top (see FORMAT.md)
  const ASCENDER = Math.round(BASELINE * BOX);
  const DESCENDER = -Math.round((1 - BASELINE) * BOX);

  // Contour polygon (pixels, y down) → opentype.Path using the vertices as quadratic
  // control points and midpoints as on-curve points (smooth, compact).
  function contourToPath(path, poly, toFontX, toFontY) {
    const n = poly.length;
    const mid = (i) => {
      const a = poly[i % n], b = poly[(i + 1) % n];
      return [(a[0] + b[0]) / 2, (a[1] + b[1]) / 2];
    };
    const m0 = mid(0);
    path.moveTo(toFontX(m0[0]), toFontY(m0[1]));
    for (let i = 1; i <= n; i++) {
      const c = poly[i % n];
      const m = mid(i);
      path.quadraticCurveTo(toFontX(c[0]), toFontY(c[1]), toFontX(m[0]), toFontY(m[1]));
    }
    path.close();
  }

  /* glyphData: { char: strokes }  (em units, y down)
     opts: { name, thickness (em), spacing (em side bearing), traceCache (Map) } */
  function buildFont(glyphData, opts) {
    const name = (opts.name || 'My Handwriting').trim() || 'My Handwriting';
    const thickness = opts.thickness || 0.045;
    const sb = Math.round((opts.spacing == null ? 0.06 : opts.spacing) * BOX);
    const cache = opts.traceCache;

    const glyphs = [];
    glyphs.push(new opentype.Glyph({ name: '.notdef', unicode: 0, advanceWidth: 500, path: new opentype.Path() }));
    glyphs.push(new opentype.Glyph({ name: 'space', unicode: 32, advanceWidth: Math.round(0.28 * BOX), path: new opentype.Path() }));

    const chars = Object.keys(glyphData).filter(c => glyphData[c] && glyphData[c].length && c !== ' ');
    for (const ch of chars) {
      const strokes = glyphData[ch];
      const cacheKey = cache ? ch + '|' + thickness + '|' + (opts.versions ? opts.versions[ch] : JSON.stringify(strokes).length) : null;
      let traced = cache && cache.get(cacheKey);
      if (!traced) {
        traced = Tracer.traceStrokes(strokes, thickness);
        if (cache) cache.set(cacheKey, traced);
      }
      if (!traced.contours.length) continue;

      let minPx = Infinity, maxPx = -Infinity;
      for (const c of traced.contours) for (const p of c) { if (p[0] < minPx) minPx = p[0]; if (p[0] > maxPx) maxPx = p[0]; }
      const scale = BOX / traced.res;
      const toFontX = (px) => Math.round((px - minPx) * scale) + sb;
      const toFontY = (py) => Math.round((BASELINE - (traced.oy + py / traced.res)) * BOX);
      const path = new opentype.Path();
      for (const c of traced.contours) contourToPath(path, c, toFontX, toFontY);
      const advance = Math.round((maxPx - minPx) * scale) + 2 * sb;
      glyphs.push(new opentype.Glyph({ name: glyphName(ch), unicode: ch.codePointAt(0), advanceWidth: advance, path }));
    }

    const font = new opentype.Font({
      familyName: name,
      styleName: 'Regular',
      unitsPerEm: UPM,
      ascender: ASCENDER,
      descender: DESCENDER,
      glyphs,
    });
    return font;
  }

  const NAMES = { '.': 'period', ',': 'comma', '!': 'exclam', '?': 'question', "'": 'quotesingle', '"': 'quotedbl', '-': 'hyphen', '_': 'underscore', '(': 'parenleft', ')': 'parenright', '[': 'bracketleft', ']': 'bracketright', '{': 'braceleft', '}': 'braceright', '/': 'slash', '\\': 'backslash', ':': 'colon', ';': 'semicolon', '@': 'at', '#': 'numbersign', '$': 'dollar', '%': 'percent', '&': 'ampersand', '*': 'asterisk', '+': 'plus', '=': 'equal', '<': 'less', '>': 'greater', '~': 'asciitilde', '^': 'asciicircum', '|': 'bar', '`': 'grave' };
  const DIGITS = ['zero', 'one', 'two', 'three', 'four', 'five', 'six', 'seven', 'eight', 'nine'];
  function glyphName(ch) {
    if (/[A-Za-z]/.test(ch)) return ch;
    if (/[0-9]/.test(ch)) return DIGITS[+ch];
    return NAMES[ch] || ('uni' + ch.codePointAt(0).toString(16).toUpperCase().padStart(4, '0'));
  }

  window.FontBuild = { buildFont, UPM, BOX, BASELINE };
})();
