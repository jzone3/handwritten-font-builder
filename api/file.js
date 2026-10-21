import { json, ID_RE, findBlob, fetchFresh } from './_store.js';

// GET ?id=&kind=otf|strokes → the raw file, no download counting (used by the font page preview)
export default async function handler(req, res) {
  const u = new URL(req.url, 'http://x');
  const id = u.searchParams.get('id');
  const kind = u.searchParams.get('kind') === 'strokes' ? 'strokes.json' : 'font.otf';
  if (!ID_RE.test(id || '')) return json(res, 400, { error: 'bad id' });
  const b = await findBlob(`fonts/${id}/${kind}`);
  if (!b) return json(res, 404, { error: 'not found' });
  const bytes = Buffer.from(await (await fetchFresh(b.url)).arrayBuffer());
  res.statusCode = 200;
  res.setHeader('Content-Type', kind.endsWith('.json') ? 'application/json' : 'font/otf');
  res.setHeader('Cache-Control', 'public, max-age=60');
  res.end(bytes);
}
