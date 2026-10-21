import { json, ID_RE, readFile } from './_store.js';

// GET ?id=&kind=otf|strokes → the raw file, no download counting (used by the font page preview)
export default async function handler(req, res) {
  const u = new URL(req.url, 'http://x');
  const id = u.searchParams.get('id');
  const kind = u.searchParams.get('kind') === 'strokes' ? 'strokes' : 'font';
  if (!ID_RE.test(id || '')) return json(res, 400, { error: 'bad id' });
  const bytes = await readFile(id, kind);
  if (!bytes) return json(res, 404, { error: 'not found' });
  res.statusCode = 200;
  res.setHeader('Content-Type', kind === 'strokes' ? 'application/json' : 'font/otf');
  res.setHeader('Cache-Control', 'public, max-age=30');
  res.end(bytes);
}
