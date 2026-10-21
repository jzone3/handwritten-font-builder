import { json, readBody, ID_RE, sha256, readMeta, writeMeta, writeFile, upsertIndex, publicMeta } from './_store.js';

// POST {name, strokes, otf (base64), id?, token?, published?}
// First call creates the font and returns {id, token}; later calls with the same id+token replace it.
export default async function handler(req, res) {
  if (req.method !== 'POST') return json(res, 405, { error: 'POST only' });
  let body;
  try { body = await readBody(req); } catch { return json(res, 400, { error: 'bad json' }); }
  const name = String(body.name || 'My Handwriting').trim().slice(0, 40) || 'My Handwriting';
  const strokes = body.strokes;
  if (!strokes || strokes.format !== 'handwritten-font-strokes' || typeof strokes.glyphs !== 'object') return json(res, 400, { error: 'bad strokes' });
  const glyphCount = Object.keys(strokes.glyphs).filter(k => Array.isArray(strokes.glyphs[k]) && strokes.glyphs[k].length).length;
  if (!glyphCount) return json(res, 400, { error: 'no glyphs' });
  if (typeof body.otf !== 'string' || body.otf.length > 4_000_000) return json(res, 400, { error: 'bad otf' });
  const otf = Buffer.from(body.otf, 'base64');
  if (otf.length < 100 || otf.readUInt32BE(0) !== 0x4F54544F) return json(res, 400, { error: 'not an otf' });

  const now = new Date().toISOString();
  let meta, token = null;
  if (body.id) {
    if (!ID_RE.test(body.id) || typeof body.token !== 'string') return json(res, 400, { error: 'bad id' });
    meta = await readMeta(body.id);
    if (!meta) return json(res, 404, { error: 'unknown font' });
    if (meta.tokenHash !== await sha256(body.token)) return json(res, 403, { error: 'wrong token' });
  } else {
    const { randomBytes } = await import('node:crypto');
    const id = randomBytes(6).toString('base64url').toLowerCase().replace(/[^a-z0-9]/g, '').slice(0, 8).padEnd(8, '0');
    token = randomBytes(18).toString('base64url');
    meta = { id, createdAt: now, downloads: 0, published: true, tokenHash: await sha256(token) };
  }
  meta.name = name;
  meta.glyphs = glyphCount;
  meta.updatedAt = now;
  if (typeof body.published === 'boolean') meta.published = body.published;

  await Promise.all([
    writeFile(meta.id, 'font.otf', otf, 'font/otf'),
    writeFile(meta.id, 'strokes.json', JSON.stringify(strokes), 'application/json'),
  ]);
  await writeMeta(meta);
  await upsertIndex(meta);
  return json(res, 200, { ...publicMeta(meta), token: token || undefined });
}
