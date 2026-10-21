import { json, readBody, ID_RE, sha256, readMeta, writeMeta, upsertIndex, publicMeta, deleteFont } from './_store.js';

// GET  ?id=        → public meta
// POST {id, token, published} → flip visibility; {id, token, delete:true} → remove everything
export default async function handler(req, res) {
  const id = req.method === 'GET' ? new URL(req.url, 'http://x').searchParams.get('id') : null;
  if (req.method === 'GET') {
    if (!ID_RE.test(id || '')) return json(res, 400, { error: 'bad id' });
    const meta = await readMeta(id);
    if (!meta) return json(res, 404, { error: 'not found' });
    return json(res, 200, publicMeta(meta), { 'Cache-Control': 'public, max-age=0, s-maxage=5, stale-while-revalidate=30' });
  }
  if (req.method !== 'POST') return json(res, 405, { error: 'GET or POST' });
  let body;
  try { body = await readBody(req); } catch { return json(res, 400, { error: 'bad json' }); }
  if (!ID_RE.test(body.id || '') || typeof body.token !== 'string') return json(res, 400, { error: 'bad id' });
  const meta = await readMeta(body.id);
  if (!meta) return json(res, 404, { error: 'not found' });
  if (meta.tokenHash !== await sha256(body.token)) return json(res, 403, { error: 'wrong token' });
  if (body.delete === true) {
    await upsertIndex({ ...meta, published: false });
    await deleteFont(meta.id);
    return json(res, 200, { deleted: true });
  }
  if (typeof body.published === 'boolean') meta.published = body.published;
  if (typeof body.name === 'string' && body.name.trim()) meta.name = body.name.trim().slice(0, 40);
  meta.updatedAt = new Date().toISOString();
  await writeMeta(meta);
  await upsertIndex(meta);
  return json(res, 200, publicMeta(meta));
}
