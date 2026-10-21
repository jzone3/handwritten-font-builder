/* Strokes → filled outlines.
   Rasterizes round-capped strokes on an offscreen canvas, traces the pixel boundary,
   simplifies it, and returns closed contours in pixel space (y down).
   Outer contours and holes come out with opposite winding automatically. */
(function () {
  'use strict';

  function smoothPoints(pts) {
    if (pts.length < 3) return pts.slice();
    const out = [pts[0]];
    for (let i = 1; i < pts.length - 1; i++) {
      out.push([
        (pts[i - 1][0] + 2 * pts[i][0] + pts[i + 1][0]) / 4,
        (pts[i - 1][1] + 2 * pts[i][1] + pts[i + 1][1]) / 4,
      ]);
    }
    out.push(pts[pts.length - 1]);
    return out;
  }

  // Draws a polyline as a smooth curve through midpoints.
  function strokePath(ctx, pts, sx, sy, scale) {
    if (pts.length === 1) {
      const [x, y] = pts[0];
      ctx.beginPath();
      ctx.arc((x - sx) * scale, (y - sy) * scale, ctx.lineWidth / 2, 0, Math.PI * 2);
      ctx.fill();
      return;
    }
    const p = smoothPoints(pts);
    ctx.beginPath();
    ctx.moveTo((p[0][0] - sx) * scale, (p[0][1] - sy) * scale);
    if (p.length === 2) {
      ctx.lineTo((p[1][0] - sx) * scale, (p[1][1] - sy) * scale);
    } else {
      for (let i = 1; i < p.length - 1; i++) {
        const mx = (p[i][0] + p[i + 1][0]) / 2, my = (p[i][1] + p[i + 1][1]) / 2;
        ctx.quadraticCurveTo((p[i][0] - sx) * scale, (p[i][1] - sy) * scale, (mx - sx) * scale, (my - sy) * scale);
      }
      const l = p[p.length - 1];
      ctx.lineTo((l[0] - sx) * scale, (l[1] - sy) * scale);
    }
    ctx.stroke();
  }

  function bounds(strokes) {
    let minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity;
    for (const s of strokes) for (const [x, y] of s) {
      if (x < minX) minX = x; if (x > maxX) maxX = x;
      if (y < minY) minY = y; if (y > maxY) maxY = y;
    }
    return { minX, minY, maxX, maxY };
  }

  let scratch = null;
  function rasterize(strokes, thickness, res) {
    const b = bounds(strokes);
    const pad = thickness;
    const W = Math.ceil((b.maxX - b.minX + 2 * pad) * res) + 2;
    const H = Math.ceil((b.maxY - b.minY + 2 * pad) * res) + 2;
    if (!scratch) scratch = document.createElement('canvas');
    scratch.width = W; scratch.height = H;
    const ctx = scratch.getContext('2d', { willReadFrequently: true });
    ctx.clearRect(0, 0, W, H);
    ctx.fillStyle = '#000'; ctx.strokeStyle = '#000';
    ctx.lineCap = 'round'; ctx.lineJoin = 'round';
    ctx.lineWidth = thickness * res;
    const ox = b.minX - pad - 1 / res, oy = b.minY - pad - 1 / res;
    for (const s of strokes) strokePath(ctx, s, ox, oy, res);
    const data = ctx.getImageData(0, 0, W, H).data;
    const grid = new Uint8Array(W * H);
    for (let i = 0, j = 3; i < grid.length; i++, j += 4) grid[i] = data[j] > 127 ? 1 : 0;
    return { grid, W, H, ox, oy };
  }

  // Directed boundary edges with ink on the right-hand side (y down), chained into loops.
  function traceBoundary(grid, W, H) {
    const filled = (x, y) => x >= 0 && y >= 0 && x < W && y < H && grid[y * W + x] === 1;
    const key = (x, y) => y * (W + 1) + x;
    const next = new Map(); // start key -> array of end keys
    const add = (x0, y0, x1, y1) => {
      const k = key(x0, y0);
      const arr = next.get(k);
      if (arr) arr.push(key(x1, y1)); else next.set(k, [key(x1, y1)]);
    };
    for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) {
      if (!grid[y * W + x]) continue;
      if (!filled(x, y - 1)) add(x, y, x + 1, y);
      if (!filled(x + 1, y)) add(x + 1, y, x + 1, y + 1);
      if (!filled(x, y + 1)) add(x + 1, y + 1, x, y + 1);
      if (!filled(x - 1, y)) add(x, y + 1, x, y);
    }
    const loops = [];
    for (const [startKey, ends] of next) {
      while (ends.length) {
        const loop = [startKey];
        let cur = ends.pop();
        let guard = 0;
        while (cur !== startKey && guard++ < 1e6) {
          loop.push(cur);
          const e = next.get(cur);
          if (!e || !e.length) break;
          cur = e.pop();
        }
        if (loop.length > 3) loops.push(loop.map(k => [k % (W + 1), Math.floor(k / (W + 1))]));
      }
    }
    return loops;
  }

  function perpDist(p, a, b) {
    const dx = b[0] - a[0], dy = b[1] - a[1];
    const len2 = dx * dx + dy * dy;
    if (len2 === 0) return Math.hypot(p[0] - a[0], p[1] - a[1]);
    let t = ((p[0] - a[0]) * dx + (p[1] - a[1]) * dy) / len2;
    t = Math.max(0, Math.min(1, t));
    return Math.hypot(p[0] - (a[0] + t * dx), p[1] - (a[1] + t * dy));
  }

  function douglasPeucker(pts, tol) {
    if (pts.length < 3) return pts;
    const keep = new Uint8Array(pts.length);
    keep[0] = keep[pts.length - 1] = 1;
    const stack = [[0, pts.length - 1]];
    while (stack.length) {
      const [s, e] = stack.pop();
      let maxD = 0, idx = -1;
      for (let i = s + 1; i < e; i++) {
        const d = perpDist(pts[i], pts[s], pts[e]);
        if (d > maxD) { maxD = d; idx = i; }
      }
      if (maxD > tol && idx > 0) { keep[idx] = 1; stack.push([s, idx], [idx, e]); }
    }
    const out = [];
    for (let i = 0; i < pts.length; i++) if (keep[i]) out.push(pts[i]);
    return out;
  }

  function simplifyLoop(loop, tol) {
    // Split the closed loop at the two farthest-apart-ish points so DP keeps a closed shape.
    let far = 0, maxD = -1;
    for (let i = 1; i < loop.length; i++) {
      const d = Math.hypot(loop[i][0] - loop[0][0], loop[i][1] - loop[0][1]);
      if (d > maxD) { maxD = d; far = i; }
    }
    const a = douglasPeucker(loop.slice(0, far + 1), tol);
    const b = douglasPeucker(loop.slice(far).concat([loop[0]]), tol);
    const out = a.concat(b.slice(1, -1));
    return out.length >= 3 ? out : null;
  }

  function signedArea(poly) {
    let a = 0;
    for (let i = 0, n = poly.length; i < n; i++) {
      const p = poly[i], q = poly[(i + 1) % n];
      a += p[0] * q[1] - q[0] * p[1];
    }
    return a / 2;
  }

  /* strokes: [[[x,y],...],...] in em units (y down).
     Returns { contours: [[[x,y],...]], ox, oy, res } where contour points are pixels in the
     scratch raster (y down); x_em = ox + px/res, y_em = oy + py/res. */
  function traceStrokes(strokes, thickness, res, tol) {
    res = res || 400; tol = tol || 1.1;
    const valid = strokes.filter(s => s && s.length);
    if (!valid.length) return { contours: [], ox: 0, oy: 0, res };
    const { grid, W, H, ox, oy } = rasterize(valid, thickness, res);
    const loops = traceBoundary(grid, W, H);
    const contours = [];
    for (const loop of loops) {
      const simp = simplifyLoop(loop, tol);
      if (!simp) continue;
      if (Math.abs(signedArea(simp)) < (thickness * res) * (thickness * res) * 0.05) continue;
      contours.push(simp);
    }
    return { contours, ox, oy, res };
  }

  window.Tracer = { traceStrokes, smoothPoints, strokePath, bounds };
})();
