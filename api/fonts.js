import { json, readIndex } from './_store.js';

// GET → {fonts:[{id,name,glyphs,downloads,createdAt,updatedAt}]} sorted by downloads
export default async function handler(req, res) {
  const idx = await readIndex();
  return json(res, 200, idx, { 'Cache-Control': 'public, max-age=30' });
}
