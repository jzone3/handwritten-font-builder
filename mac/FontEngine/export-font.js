/* Offline font export for the Mac app: strokes file (FORMAT.md) in, base64 .otf out.
   Runs in a hidden web view next to the site's own tracer.js, fontbuild.js and opentype.min.js,
   so the app and the website build identical fonts. */
(function () {
  'use strict';

  function build(data, name) {
    const file = typeof data === 'string' ? JSON.parse(data) : data;
    const glyphs = {};
    for (const [ch, strokes] of Object.entries((file && file.glyphs) || {})) {
      if (Array.isArray(strokes) && strokes.length) glyphs[ch] = strokes;
    }
    const drawn = Object.keys(glyphs).length;
    if (!drawn) throw new Error('No glyphs have been drawn yet.');
    const font = FontBuild.buildFont(glyphs, { name: name || file.fontName });
    const bytes = new Uint8Array(font.toArrayBuffer());
    let s = '';
    for (let i = 0; i < bytes.length; i += 0x8000) s += String.fromCharCode.apply(null, bytes.subarray(i, i + 0x8000));
    return { otf: btoa(s), glyphs: drawn };
  }

  window.HFBExport = { build };
})();
