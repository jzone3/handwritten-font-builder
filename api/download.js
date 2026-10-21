import { json, ID_RE, readMeta, writeMeta, upsertIndex, findBlob, fetchFresh } from './_store.js';

// GET ?id=&count=1 → the .otf as an attachment (counts a download unless count=0)
export default async function handler(req, res) {
  const u = new URL(req.url, 'http://x');
  const id = u.searchParams.get('id');
  if (!ID_RE.test(id || '')) return json(res, 400, { error: 'bad id' });
  const meta = await readMeta(id);
  if (!meta) return json(res, 404, { error: 'not found' });
  const b = await findBlob(`fonts/${id}/font.otf`);
  if (!b) return json(res, 404, { error: 'no file' });
  const bytes = Buffer.from(await (await fetchFresh(b.url)).arrayBuffer());
  if (u.searchParams.get('count') !== '0') {
    meta.downloads = (meta.downloads || 0) + 1;
    try { await writeMeta(meta); await upsertIndex(meta); } catch (e) { console.error('count failed', e); }
  }
  const file = (meta.name || 'font').replace(/[^A-Za-z0-9]+/g, '-').replace(/^-|-$/g, '') || 'font';
  res.statusCode = 200;
  res.setHeader('Content-Type', 'font/otf');
  res.setHeader('Content-Length', String(bytes.length));
  res.setHeader('Cache-Control', 'no-store');
  res.setHeader('Content-Disposition', `attachment; filename="${file}.otf"`);
  res.end(bytes);
}
