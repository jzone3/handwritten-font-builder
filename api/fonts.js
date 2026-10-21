import { json, readIndex } from './_store.js';

// GET → {fonts:[...]} sorted by downloads; ?sort=new → newest first (for the live ticker)
export default async function handler(req, res) {
  const idx = await readIndex();
  const sort = new URL(req.url, 'http://x').searchParams.get('sort');
  if (sort === 'new') idx.fonts = idx.fonts.slice().sort((a, b) => (b.createdAt > a.createdAt ? 1 : -1)).slice(0, 30);
  return json(res, 200, idx, { 'Cache-Control': 'public, max-age=0, s-maxage=5, stale-while-revalidate=30' });
}
