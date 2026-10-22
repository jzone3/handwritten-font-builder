(function () {
  'use strict';

  // What we ask people to draw. ) ] } > are mirrored from ( [ { < by the font builder;
  // curly quotes and dashes are derived from ' " -.
  const CHARSET = ('ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789' + '.,!?\'"-_([{/\\:;@#$%&*+=<~^|`').split('');
  const ACCEPTED = new Set(CHARSET.concat([')', ']', '}', '>']));  // files may still carry the closers
  const ASPECT = 1.6;
  const GUIDES = { cap: 0.20, xh: 0.46, base: 0.76 };
  const STORAGE_KEY = 'hfb.project.v1';
  // ?embed=mac: the Mac app shows only the "Your font" screen inside a web view and feeds strokes through window.HFB.
  const EMBED = new URLSearchParams(location.search).has('embed');
  const native = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.native;
  const tellNative = (msg) => { try { if (native) native.postMessage(msg); } catch (e) {} };
  const MAC_DOWNLOAD = 'https://github.com/jzone3/handwritten-font-builder/releases/latest/download/Handwritten-Font-Builder.dmg';
  const NAMES = { '.': 'period', ',': 'comma', '!': 'exclamation mark', '?': 'question mark', "'": 'apostrophe', '"': 'double quote', '-': 'hyphen', '_': 'underscore', '(': 'open paren', ')': 'close paren', '[': 'open bracket', ']': 'close bracket', '{': 'open brace', '}': 'close brace', '/': 'slash', '\\': 'backslash', ':': 'colon', ';': 'semicolon', '@': 'at sign', '#': 'hash', '$': 'dollar', '%': 'percent', '&': 'ampersand', '*': 'asterisk', '+': 'plus', '=': 'equals', '<': 'less than', '>': 'greater than', '~': 'tilde', '^': 'caret', '|': 'vertical bar', '`': 'backtick' };

  const $ = (id) => document.getElementById(id);
  const pad = $('pad'), ctx = pad.getContext('2d');
  const grid = $('glyphGrid');

  const state = {
    glyphs: {},          // char -> strokes
    versions: {},        // char -> int, bumps on edit (trace cache key)
    current: 0,
    fontName: 'My Handwriting',
    publish: true,          // auto-publish on Finish; user can switch it off
    pub: null,              // { id, token } once published
    thickness: 0.06,
    spacing: 0.06,
  };
  const traceCache = new Map();
  let drawing = null;      // { points, startTime }
  let spaceDown = false;
  let lastPointer = null;
  let advanceTimer = null, advanceStart = 0;

  // ---------- persistence ----------
  function save() {
    try {
      localStorage.setItem(STORAGE_KEY, JSON.stringify({ glyphs: state.glyphs, fontName: state.fontName, thickness: state.thickness, spacing: state.spacing, current: state.current, publish: state.publish, pub: state.pub }));
      if (state.pub) localStorage.setItem('hfb.pub.' + state.pub.id, state.pub.token);
      if (state.pubKey) localStorage.setItem(state.pubKey, state.pub ? JSON.stringify(state.pub) : '');
    } catch (e) {}
  }
  function load() {
    try {
      const raw = localStorage.getItem(STORAGE_KEY);
      if (!raw) return;
      const d = JSON.parse(raw);
      if (d.glyphs) state.glyphs = d.glyphs;
      if (d.fontName) state.fontName = d.fontName;
      if (typeof d.publish === 'boolean') state.publish = d.publish;
      if (d.pub && d.pub.id && d.pub.token) state.pub = d.pub;
      if (d.thickness) state.thickness = d.thickness;
      if (d.spacing != null) state.spacing = d.spacing;
      if (Number.isInteger(d.current)) state.current = Math.min(Math.max(d.current, 0), CHARSET.length - 1);
    } catch (e) {}
  }

  // ---------- pad ----------
  function padSize() {
    const w = pad.clientWidth;
    const aspect = w < 520 ? 1.25 : ASPECT;
    // Keep the whole pad on screen on short viewports (phones in landscape).
    const maxH = Math.max(160, window.innerHeight - 170);
    return { w, h: Math.min(w / aspect, maxH) };
  }
  function resizePad() {
    const { w, h } = padSize();
    const dpr = window.devicePixelRatio || 1;
    pad.width = Math.round(w * dpr); pad.height = Math.round(h * dpr);
    pad.style.height = h + 'px';
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    drawPad();
  }
  function emToPx(p) { const { h } = padSize(); return [p[0] * h, p[1] * h]; }
  function pxToEm(x, y) { const { h } = padSize(); return [x / h, y / h]; }

  function drawGuides(w, h) {
    ctx.save();
    ctx.lineWidth = 1;
    for (const [k, y] of Object.entries(GUIDES)) {
      ctx.strokeStyle = k === 'base' ? '#8a8a8a' : '#dcdcdc';
      ctx.setLineDash(k === 'base' ? [] : [4, 4]);
      ctx.beginPath(); ctx.moveTo(0, y * h + 0.5); ctx.lineTo(w, y * h + 0.5); ctx.stroke();
    }
    ctx.setLineDash([]);
    ctx.fillStyle = '#b5b5b5'; ctx.font = '11px -apple-system, system-ui, sans-serif'; ctx.textBaseline = 'bottom';
    ctx.fillText('cap height', 8, GUIDES.cap * h - 2);
    ctx.fillText('x-height', 8, GUIDES.xh * h - 2);
    ctx.fillText('baseline', 8, GUIDES.base * h - 2);
    ctx.restore();
  }
  function drawStrokes(strokes, h, color, width) {
    ctx.save();
    ctx.strokeStyle = color; ctx.fillStyle = color;
    ctx.lineCap = 'round'; ctx.lineJoin = 'round';
    ctx.lineWidth = width;
    for (const s of strokes) Tracer.strokePath(ctx, s, 0, 0, h);
    ctx.restore();
  }
  function drawPad() {
    const { w, h } = padSize();
    ctx.clearRect(0, 0, w, h);
    drawGuides(w, h);
    const ch = CHARSET[state.current];
    const strokes = state.glyphs[ch] || [];
    drawStrokes(strokes, h, '#111', state.thickness * h);
    if (drawing) drawStrokes([drawing.points], h, '#111', state.thickness * h);
  }

  function beginStroke(x, y) {
    cancelAdvance();
    const [ex, ey] = pxToEm(x, y);
    drawing = { points: [[ex, ey, 0]], startTime: performance.now() };
    drawPad();
  }
  function moveStroke(x, y) {
    if (!drawing) return;
    const [ex, ey] = pxToEm(x, y);
    const last = drawing.points[drawing.points.length - 1];
    if (Math.hypot(ex - last[0], ey - last[1]) < 0.002) return;
    drawing.points.push([ex, ey, Math.round(performance.now() - drawing.startTime)]);
    drawPad();
  }
  function endStroke() {
    if (!drawing) return;
    const ch = CHARSET[state.current];
    const pts = drawing.points.map(p => [+p[0].toFixed(4), +p[1].toFixed(4), p[2]]);
    (state.glyphs[ch] = state.glyphs[ch] || []).push(pts);
    bump(ch);
    drawing = null;
    drawPad();
    afterEdit(ch);
    if ($('autoAdvance').checked) scheduleAdvance();
  }
  function bump(ch) { state.versions[ch] = (state.versions[ch] || 0) + 1; }

  function localPos(e) {
    const r = pad.getBoundingClientRect();
    return [e.clientX - r.left, e.clientY - r.top];
  }
  // iOS: stop scroll / rubber-band / long-press while the finger is on the pad.
  for (const t of ['touchstart', 'touchmove', 'touchend']) pad.addEventListener(t, (e) => e.preventDefault(), { passive: false });
  pad.addEventListener('contextmenu', (e) => e.preventDefault());
  pad.addEventListener('pointerdown', (e) => {
    if (e.button !== 0 && e.pointerType === 'mouse') return;
    e.preventDefault();
    pad.setPointerCapture(e.pointerId);
    const [x, y] = localPos(e);
    beginStroke(x, y);
  });
  pad.addEventListener('pointermove', (e) => {
    const [x, y] = localPos(e);
    lastPointer = [x, y];
    if (drawing) { moveStroke(x, y); return; }
    if (spaceDown && e.pointerType === 'mouse') beginStroke(x, y);
  });
  const up = (e) => { if (drawing && !(spaceDown && e.type !== 'pointerup' && e.pointerType === 'mouse')) endStroke(); };
  pad.addEventListener('pointerup', up);
  pad.addEventListener('pointercancel', up);
  pad.addEventListener('pointerleave', () => { if (drawing && !spaceDown) endStroke(); });

  // Hold Space: draw while moving the mouse/trackpad without clicking.
  const isTyping = () => { const el = document.activeElement; return el && (el.tagName === 'INPUT' || el.tagName === 'TEXTAREA' || el.isContentEditable); };
  window.addEventListener('keydown', (e) => {
    if (isTyping() || $('screen-draw').hidden) return;
    if (e.code === 'Space') {
      e.preventDefault();
      if (!spaceDown) {
        spaceDown = true; pad.classList.add('space-mode');
        if (lastPointer && !drawing) beginStroke(lastPointer[0], lastPointer[1]);
      }
      return;
    }
    if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === 'z') { e.preventDefault(); undo(); return; }
    if (e.key === 'Backspace') { e.preventDefault(); undo(); return; }
    if (e.key === 'ArrowRight' || e.key === 'Enter') { e.preventDefault(); goTo(state.current + 1); return; }
    if (e.key === 'ArrowLeft') { e.preventDefault(); goTo(state.current - 1); return; }
    if (e.key === 'Escape') { clearGlyph(); return; }
    if (e.key.length === 1 && !e.metaKey && !e.ctrlKey && !e.altKey) {
      const i = CHARSET.indexOf(e.key);
      if (i >= 0) { e.preventDefault(); goTo(i); }
    }
  });
  window.addEventListener('keyup', (e) => {
    if (e.code === 'Space' && spaceDown) {
      spaceDown = false; pad.classList.remove('space-mode');
      if (drawing) endStroke();
    }
  });
  window.addEventListener('blur', () => { spaceDown = false; pad.classList.remove('space-mode'); if (drawing) endStroke(); });

  // ---------- glyph navigation ----------
  function goTo(i) {
    cancelAdvance();
    if (drawing) endStroke();
    if (i < 0 || i >= CHARSET.length) return;
    state.current = i;
    updateCurrent();
    save();
  }
  function hintFor(ch) {
    if (/[A-Z]/.test(ch)) return 'Draw the capital ' + ch;
    if (/[a-z]/.test(ch)) return 'Draw the lowercase ' + ch;
    if (/[0-9]/.test(ch)) return 'Draw the digit ' + ch;
    if ('([{<'.includes(ch)) return 'Draw the ' + NAMES[ch] + ' (the closing one is mirrored for you)';
    return 'Draw the ' + (NAMES[ch] || ch);
  }
  function updateCurrent() {
    const ch = CHARSET[state.current];
    $('padChar').textContent = ch;
    $('padHint').textContent = hintFor(ch);
    $('prevBtn').disabled = state.current === 0;
    $('nextBtn').disabled = state.current === CHARSET.length - 1;
    grid.querySelectorAll('.glyph-cell').forEach((el, i) => el.classList.toggle('current', i === state.current));
    const cell = grid.children[state.current];
    if (cell && grid.scrollWidth > grid.clientWidth + 4) {
      const target = cell.offsetLeft - (grid.clientWidth - cell.offsetWidth) / 2;
      grid.scrollTo({ left: Math.max(0, target), behavior: 'smooth' });
    }
    drawPad();
  }
  function scheduleAdvance() {
    cancelAdvance();
    if (state.current >= CHARSET.length - 1) return;
    advanceStart = performance.now();
    const fill = $('nextBtn').querySelector('.fill');
    const tick = () => {
      const t = (performance.now() - advanceStart) / 1400;
      if (fill) fill.style.width = Math.min(100, t * 100) + '%';
      if (t >= 1) { advanceTimer = null; if (fill) fill.style.width = '0'; goTo(state.current + 1); return; }
      advanceTimer = requestAnimationFrame(tick);
    };
    advanceTimer = requestAnimationFrame(tick);
  }
  function cancelAdvance() {
    if (advanceTimer) cancelAnimationFrame(advanceTimer);
    advanceTimer = null;
    const fill = $('nextBtn').querySelector('.fill');
    if (fill) fill.style.width = '0';
  }
  function undo() {
    cancelAdvance();
    const ch = CHARSET[state.current];
    if (drawing) { drawing = null; drawPad(); return; }
    const s = state.glyphs[ch];
    if (!s || !s.length) return;
    s.pop();
    if (!s.length) delete state.glyphs[ch];
    bump(ch);
    drawPad();
    afterEdit(ch);
  }
  function clearGlyph() {
    cancelAdvance();
    const ch = CHARSET[state.current];
    drawing = null;
    if (!state.glyphs[ch]) { drawPad(); return; }
    delete state.glyphs[ch];
    bump(ch);
    drawPad();
    afterEdit(ch);
  }

  // ---------- grid ----------
  function buildGrid() {
    grid.innerHTML = '';
    CHARSET.forEach((ch, i) => {
      const b = document.createElement('button');
      b.className = 'glyph-cell'; b.type = 'button'; b.title = hintFor(ch);
      b.innerHTML = '<span class="lbl"></span><canvas></canvas>';
      b.querySelector('.lbl').textContent = ch;
      b.addEventListener('click', () => goTo(i));
      grid.appendChild(b);
    });
  }
  function renderThumb(ch) {
    const i = CHARSET.indexOf(ch);
    const cell = grid.children[i];
    if (!cell) return;
    const strokes = state.glyphs[ch];
    const c = cell.querySelector('canvas');
    cell.classList.toggle('drawn', !!(strokes && strokes.length));
    const size = 42, dpr = window.devicePixelRatio || 1;
    c.width = size * dpr; c.height = size * dpr;
    const g = c.getContext('2d');
    g.setTransform(dpr, 0, 0, dpr, 0, 0);
    g.clearRect(0, 0, size, size);
    if (!strokes || !strokes.length) return;
    const b = Tracer.bounds(strokes);
    const bw = Math.max(b.maxX - b.minX, 0.05), bh = Math.max(b.maxY - b.minY, 0.05);
    // Fit the glyph box vertically (full em), center horizontally: keeps relative sizes honest.
    const scale = (size - 10) / 1.0;
    const ox = (size - bw * scale) / 2 - b.minX * scale;
    const oy = 5;
    g.save();
    g.translate(ox, oy);
    g.strokeStyle = '#111'; g.fillStyle = '#111'; g.lineCap = 'round'; g.lineJoin = 'round';
    g.lineWidth = Math.max(1.2, state.thickness * scale);
    for (const s of strokes) Tracer.strokePath(g, s, 0, 0, scale);
    g.restore();
  }
  function renderAllThumbs() { CHARSET.forEach(renderThumb); updateProgress(); }
  function updateProgress() {
    const n = CHARSET.filter(c => state.glyphs[c] && state.glyphs[c].length).length;
    $('progress').textContent = n + ' / ' + CHARSET.length + ' drawn';
    $('downloadFont').disabled = n === 0;
    $('saveProject').disabled = n === 0;
    $('finishBtn').disabled = n === 0;
  }

  // ---------- font preview ----------
  let buildSeq = 0, buildTimer = null, currentFace = null, currentFont = null;
  const status = $('previewStatus');

  function scheduleBuild() {
    clearTimeout(buildTimer);
    buildTimer = setTimeout(rebuild, 250);
  }
  async function rebuild() {
    const n = Object.keys(state.glyphs).length;
    if (!n) {
      currentFont = null; updateShareBox();
      $('previewBox').style.fontFamily = '';
      status.textContent = 'Draw a letter to see it here.';
      return;
    }
    const seq = ++buildSeq;
    status.textContent = 'Building…';
    await new Promise(r => setTimeout(r, 0));
    let font;
    try {
      font = FontBuild.buildFont(state.glyphs, { name: state.fontName, thickness: state.thickness, spacing: state.spacing, traceCache, versions: state.versions });
    } catch (err) {
      console.error(err); status.textContent = 'Could not build the font: ' + err.message; return;
    }
    if (seq !== buildSeq) return;
    const buf = font.toArrayBuffer();
    const family = 'HFBPreview' + seq;
    const face = new FontFace(family, buf);
    try { await face.load(); } catch (err) { console.error(err); status.textContent = 'Could not load the preview font.'; return; }
    if (seq !== buildSeq) return;
    if (currentFace) document.fonts.delete(currentFace);
    document.fonts.add(face);
    currentFace = face; currentFont = font;
    $('previewBox').style.fontFamily = '"' + family + '", "Comic Sans MS", cursive';
    const n2 = CHARSET.filter(c => state.glyphs[c] && state.glyphs[c].length).length;
    status.textContent = n2 + ' of ' + CHARSET.length + ' letters drawn · ' + Math.round(buf.byteLength / 1024) + ' KB' + (n2 < CHARSET.length ? ' · missing letters show in a plain font' : '');
    if (traceCache.size > 400) traceCache.clear();
    if (!$('screen-done').hidden) schedulePublish(buf);
  }

  // ---------- publish / share ----------
  const shareBox = $('shareBox'), pubStatus = $('publishStatus');
  let publishTimer = null, publishing = false, pendingBuf = null;
  function b64(buf) { let s = ''; const u = new Uint8Array(buf); for (let i = 0; i < u.length; i += 0x8000) s += String.fromCharCode.apply(null, u.subarray(i, i + 0x8000)); return btoa(s); }
  function updateShareBox() {
    shareBox.hidden = !Object.keys(state.glyphs).length;
    $('publishToggle').checked = state.publish;
    const has = !!state.pub;
    $('pageLink').hidden = !has; $('shareBtn').hidden = !has;
    if (has) $('pageLink').href = '/f/' + state.pub.id;
    if (!state.publish && !has) pubStatus.textContent = 'Not published. Tick the box to get a link you can share.';
  }
  function schedulePublish(buf) {
    pendingBuf = buf;
    updateShareBox();
    if (!state.publish) return;
    clearTimeout(publishTimer);
    publishTimer = setTimeout(publishNow, 1200);
  }
  async function publishNow() {
    if (publishing || !pendingBuf || !state.publish) return;
    publishing = true;
    pubStatus.textContent = state.pub ? 'Saving…' : 'Publishing…';
    const buf = pendingBuf; pendingBuf = null;
    const body = { name: state.fontName, strokes: JSON.parse(projectJSON()), otf: b64(buf), published: true };
    if (state.pub) { body.id = state.pub.id; body.token = state.pub.token; }
    try {
      let r = await fetch('/api/publish', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) });
      if ((r.status === 403 || r.status === 404) && state.pub) {
        // Our copy was deleted or the token is stale: publish fresh.
        state.pub = null; delete body.id; delete body.token;
        r = await fetch('/api/publish', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) });
      }
      if (!r.ok) throw new Error('HTTP ' + r.status);
      const m = await r.json();
      if (m.token) state.pub = { id: m.id, token: m.token };
      save();
      updateShareBox();
      pubStatus.innerHTML = '';
      const link = document.createElement('a'); link.href = '/f/' + m.id; link.target = '_blank'; link.rel = 'noopener'; link.className = 'share-url'; link.textContent = location.origin + '/f/' + m.id;
      pubStatus.append('Your font page: ', link, ' · ' + m.downloads + ' download' + (m.downloads === 1 ? '' : 's'));
    } catch (err) {
      console.error(err);
      pubStatus.textContent = 'Could not publish (' + err.message + '). Your font still works locally.';
    } finally {
      publishing = false;
      if (pendingBuf) schedulePublish(pendingBuf);
    }
  }
  $('publishToggle').addEventListener('change', async (e) => {
    state.publish = e.target.checked; save();
    if (state.publish) { if (currentFont) schedulePublish(currentFont.toArrayBuffer()); }
    else if (state.pub) {
      pubStatus.textContent = 'Unpublishing…';
      try {
        const r = await fetch('/api/font', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ id: state.pub.id, token: state.pub.token, published: false }) });
        pubStatus.textContent = r.ok ? 'Unpublished. The page still opens for people who have the link; delete it from the font page if you want it gone.' : 'Could not unpublish.';
      } catch (err) { pubStatus.textContent = 'Could not unpublish.'; }
    }
    updateShareBox();
  });
  $('shareBtn').addEventListener('click', async () => {
    if (!state.pub) return;
    const url = location.origin + '/f/' + state.pub.id;
    const data = { title: state.fontName, text: 'A font made from my handwriting', url };
    if (navigator.share) { try { await navigator.share(data); } catch (e) {} return; }
    try { await navigator.clipboard.writeText(url); $('shareBtn').textContent = 'Link copied'; setTimeout(() => $('shareBtn').textContent = 'Share…', 1500); } catch (e) { prompt('Copy this link', url); }
  });

  function afterEdit(ch) {
    renderThumb(ch);
    updateProgress();
    save();
    scheduleBuild();
  }

  // ---------- export / import ----------
  function slug(s) { return (s || 'font').replace(/[^A-Za-z0-9]+/g, '-').replace(/^-|-$/g, '') || 'font'; }
  function downloadBlob(blob, filename) {
    const a = document.createElement('a');
    a.href = URL.createObjectURL(blob); a.download = filename;
    document.body.appendChild(a); a.click(); a.remove();
    setTimeout(() => URL.revokeObjectURL(a.href), 2000);
  }
  $('downloadFont').addEventListener('click', () => {
    if (state.pub && state.publish && !pendingBuf && !publishing) { location.href = '/api/download?id=' + state.pub.id; return; }
    const font = FontBuild.buildFont(state.glyphs, { name: state.fontName, thickness: state.thickness, spacing: state.spacing, traceCache, versions: state.versions });
    downloadBlob(new Blob([font.toArrayBuffer()], { type: 'font/otf' }), slug(state.fontName) + '.otf');
  });
  function projectJSON() {
    return JSON.stringify({ format: 'handwritten-font-strokes', version: 1, source: 'web', fontName: state.fontName, createdAt: new Date().toISOString(), glyphs: state.glyphs }, null, 0);
  }
  $('saveProject').addEventListener('click', () => {
    downloadBlob(new Blob([projectJSON()], { type: 'application/json' }), slug(state.fontName) + '.strokes.json');
  });
  $('importBtn').addEventListener('click', () => $('importFile').click());
  $('importFile').addEventListener('change', (e) => { if (e.target.files[0]) importFile(e.target.files[0]); e.target.value = ''; });

  function importFile(file) {
    const reader = new FileReader();
    reader.onload = () => {
      try { importData(JSON.parse(reader.result)); }
      catch (err) { alert('That file is not a strokes file this site understands.\n' + err.message); }
    };
    reader.readAsText(file);
  }
  function importData(d, replace) {
    if (!d || d.format !== 'handwritten-font-strokes' || typeof d.glyphs !== 'object') throw new Error('Expected format "handwritten-font-strokes".');
    if (replace) { state.glyphs = {}; state.versions = {}; traceCache.clear(); }
    let count = 0;
    for (const [ch, strokes] of Object.entries(d.glyphs)) {
      if (!ACCEPTED.has(ch) || !Array.isArray(strokes)) continue;
      const clean = strokes.filter(s => Array.isArray(s) && s.length).map(s => s.filter(p => Array.isArray(p) && p.length >= 2 && isFinite(p[0]) && isFinite(p[1])).map(p => [+p[0], +p[1], p.length > 2 ? +p[2] : 0])).filter(s => s.length);
      if (!clean.length) continue;
      state.glyphs[ch] = clean; bump(ch); count++;
    }
    if (typeof d.fontName === 'string' && d.fontName.trim()) { state.fontName = d.fontName.trim().slice(0, 40); $('fontName').value = state.fontName; }
    renderAllThumbs(); updateCurrent(); save(); scheduleBuild();
    showScreen('done');
    status.textContent = 'Imported ' + count + ' letters' + (d.source === 'mac-app' ? ' from the Mac app.' : '.');
  }

  // Drag & drop anywhere.
  let dragDepth = 0;
  window.addEventListener('dragenter', (e) => { e.preventDefault(); dragDepth++; document.body.classList.add('dragging'); });
  window.addEventListener('dragover', (e) => { e.preventDefault(); });
  window.addEventListener('dragleave', () => { if (--dragDepth <= 0) { dragDepth = 0; document.body.classList.remove('dragging'); } });
  window.addEventListener('drop', (e) => {
    e.preventDefault(); dragDepth = 0; document.body.classList.remove('dragging');
    const f = e.dataTransfer.files && e.dataTransfer.files[0];
    if (f) importFile(f);
  });

  $('resetBtn').addEventListener('click', () => {
    if (!confirm('Erase every letter and start over?')) return;
    state.glyphs = {}; state.versions = {}; state.current = 0; state.pub = null; traceCache.clear();
    renderAllThumbs(); updateCurrent(); save(); scheduleBuild();
    showScreen('draw');
  });

  // ---------- screens ----------
  const SCREENS = ['start', 'draw', 'done'];
  function showScreen(name, push) {
    if (!SCREENS.includes(name)) name = 'start';
    if (EMBED) name = 'done';
    else if (name === 'done' && !Object.keys(state.glyphs).length) name = 'draw';
    if (drawing) endStroke();
    cancelAdvance();
    for (const s of SCREENS) $('screen-' + s).hidden = s !== name;
    document.querySelectorAll('nav a[data-nav]').forEach(a => a.classList.toggle('active', a.dataset.nav === name));
    if (!EMBED && location.hash !== '#' + name) history.replaceState(null, '', '#' + name);
    window.scrollTo(0, 0);
    if (name === 'draw') { resizePad(); updateCurrent(); }
    if (name === 'done') { rebuild(); }
  }
  window.addEventListener('hashchange', () => showScreen(location.hash.slice(1) || 'start', false));
  document.querySelectorAll('a[data-nav]').forEach(a => a.addEventListener('click', (e) => { e.preventDefault(); showScreen(a.dataset.nav); }));
  $('finishBtn').addEventListener('click', () => showScreen('done'));
  $('backToDraw').addEventListener('click', () => { if (EMBED) tellNative({ type: 'keepWriting' }); else showScreen('draw'); });
  if (EMBED) {
    document.body.classList.add('embed');
    $('fontName').addEventListener('input', () => tellNative({ type: 'fontName', value: $('fontName').value }));
    // Called by the Mac app once the page has loaded: strokes JSON (string or object) plus a stable id per Mac project,
    // so re-opening the screen keeps updating the same published font page instead of making a new one.
    window.HFB = {
      importStrokes(data, projectId) {
        const d = typeof data === 'string' ? JSON.parse(data) : data;
        state.pubKey = projectId ? 'hfb.embedpub.' + String(projectId).replace(/[^A-Za-z0-9-]/g, '') : null;
        state.pub = null;
        try { const saved = state.pubKey && localStorage.getItem(state.pubKey); if (saved) { const p = JSON.parse(saved); if (p && p.id && p.token) state.pub = p; } } catch (e) {}
        importData(d, true);
      },
    };
  }
  $('importLink').addEventListener('click', (e) => { e.preventDefault(); $('importFile').click(); });

  // Live ticker on the start screen: the newest fonts, each showing its creation time written in that font.
  async function loadTicker() {
    let fonts = [];
    try { const r = await fetch('/api/fonts?sort=new'); if (r.ok) fonts = (await r.json()).fonts || []; } catch (e) {}
    if (!fonts.length) return;
    const track = $('tickerTrack');
    const row = document.createElement('div'); row.className = 'ticker-row';
    const ago = (iso) => { const m = Math.round((Date.now() - new Date(iso)) / 60000); return m < 1 ? 'just now' : m < 60 ? m + ' min ago' : m < 1440 ? Math.round(m / 60) + ' h ago' : Math.round(m / 1440) + ' d ago'; };
    for (const f of fonts.slice(0, 20)) {
      const card = document.createElement('a'); card.className = 'ticker-card'; card.href = '/f/' + f.id;
      const t = document.createElement('div'); t.className = 'ticker-time';
      let time;
      try { time = new Date(f.createdAt).toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit', timeZone: f.tz || undefined }); } catch (e) { time = new Date(f.createdAt).toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit' }); }
      t.textContent = time;
      const where = document.createElement('div'); where.className = 'ticker-where';
      const place = [f.city, f.region || (f.country && f.country !== 'US' ? f.country : null)].filter(Boolean).join(', ');
      where.textContent = (place ? place + ' · ' : '') + ago(f.createdAt);
      card.append(t, where); row.appendChild(card);
      const fam = 'HFBT_' + f.id;
      const face = new FontFace(fam, 'url(/api/file?id=' + f.id + '&kind=otf)');
      face.load().then(() => { document.fonts.add(face); t.style.fontFamily = '"' + fam + '", cursive'; }).catch(() => {});
    }
    track.appendChild(row);
    if (fonts.length > 3) track.appendChild(row.cloneNode(true));  // seamless loop
    else row.style.animation = 'none';
    $('ticker').hidden = false;
  }

  function detectDevice() {
    const ua = navigator.userAgent || '';
    const touchMac = navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1;
    if (/iPhone|iPod/.test(ua)) return 'iphone';
    if (/iPad/.test(ua) || touchMac) return 'ipad';
    if (/Android/.test(ua)) return 'android';
    if (/Macintosh|Mac OS X/.test(ua)) return 'mac';
    if (/Windows/.test(ua)) return 'windows';
    return 'other';
  }
  function setupStart() {
    const d = detectDevice();
    const line = $('deviceLine'), acts = $('deviceActions'), note = $('deviceNote');
    const btn = (label, cls, onClick) => { const b = document.createElement('button'); b.textContent = label; b.className = cls; b.addEventListener('click', onClick); return b; };
    const start = () => showScreen('draw');
    acts.innerHTML = '';
    if (d === 'mac') {
      line.textContent = 'Looks like you\'re on a Mac. The free Mac app turns your trackpad into a drawing tablet: write each letter with a finger, no clicking.';
      const a = document.createElement('a'); a.className = 'button primary'; a.textContent = 'Download the Mac app'; a.href = MAC_DOWNLOAD;
      acts.appendChild(a);
      acts.appendChild(btn('Continue on the web →', '', start));
      note.textContent = 'In the browser you click and drag to draw, which is clumsier. The app exports a file you import here.';
    } else if (d === 'iphone' || d === 'ipad' || d === 'android') {
      line.textContent = 'Looks like you\'re on ' + (d === 'iphone' ? 'an iPhone' : d === 'ipad' ? 'an iPad' : 'an Android phone') + '. Draw the letters with your finger' + (d === 'ipad' ? ' or a Pencil' : '') + '; that works nicely.';
      acts.appendChild(btn('Start writing →', 'primary', start));
      note.textContent = 'Sit each letter on the dark baseline; tails like g and y go below it.';
    } else {
      line.textContent = 'Looks like you\'re on ' + (d === 'windows' ? 'Windows' : 'a computer') + '. Draw with a mouse, trackpad, or touchscreen.';
      acts.appendChild(btn('Start writing →', 'primary', start));
      note.textContent = 'Tip: hold Space and move the pointer to draw without clicking.';
    }
  }

  // ---------- controls ----------
  $('undoBtn').addEventListener('click', undo);
  $('clearBtn').addEventListener('click', clearGlyph);
  $('prevBtn').addEventListener('click', () => goTo(state.current - 1));
  $('nextBtn').addEventListener('click', () => goTo(state.current + 1));
  $('nextBtn').insertAdjacentHTML('beforeend', '<span class="fill"></span>');
  $('fontName').addEventListener('input', (e) => { state.fontName = e.target.value; save(); scheduleBuild(); });
  $('thickness').addEventListener('input', (e) => { state.thickness = +e.target.value; drawPad(); renderAllThumbs(); save(); scheduleBuild(); });
  $('spacing').addEventListener('input', (e) => { state.spacing = +e.target.value; save(); scheduleBuild(); });
  $('previewSize').addEventListener('input', (e) => { $('previewBox').style.fontSize = e.target.value + 'px'; });
  window.addEventListener('resize', resizePad);
  if (window.ResizeObserver) new ResizeObserver(() => { if (!$('screen-draw').hidden && Math.abs(pad.clientWidth * (window.devicePixelRatio || 1) - pad.width) > 1) resizePad(); }).observe(pad);

  // ---------- boot ----------
  load();
  $('fontName').value = state.fontName;
  $('thickness').value = state.thickness;
  $('spacing').value = state.spacing;
  $('previewBox').style.fontSize = $('previewSize').value + 'px';
  buildGrid();
  renderAllThumbs();
  setupStart();
  loadTicker();
  const initial = location.hash.slice(1);
  showScreen(initial || (Object.keys(state.glyphs).length ? 'draw' : 'start'), false);
  scheduleBuild();
})();
