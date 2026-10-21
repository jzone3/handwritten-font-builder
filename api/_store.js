import { put, list, del } from '@vercel/blob';

// Layout in the blob store:
//   fonts/<id>/meta.json     {id, name, glyphs, createdAt, updatedAt, published, downloads, tokenHash}
//   fonts/<id>/font.otf
//   fonts/<id>/strokes.json
// Blob URLs are cached at the edge; we keep the max-age short so edits show up quickly.
const PUT_OPTS = { access: 'public', addRandomSuffix: false, allowOverwrite: true, cacheControlMaxAge: 60 };

export function json(res, status, body, extra = {}) {
  res.statusCode = status;
  res.setHeader('Content-Type', 'application/json; charset=utf-8');
  res.setHeader('Cache-Control', 'no-store');
  for (const [k, v] of Object.entries(extra)) res.setHeader(k, v);
  res.end(JSON.stringify(body));
}

export async function readBody(req) {
  const chunks = [];
  for await (const c of req) chunks.push(c);
  const raw = Buffer.concat(chunks).toString('utf8');
  return raw ? JSON.parse(raw) : {};
}

export const ID_RE = /^[a-z0-9]{6,12}$/;

export async function sha256(s) {
  const { createHash } = await import('node:crypto');
  return createHash('sha256').update(s).digest('hex');
}

export async function findBlob(pathname) {
  const r = await list({ prefix: pathname, limit: 1 });
  return r.blobs.find(b => b.pathname === pathname) || null;
}

export async function fetchFresh(url) {
  const r = await fetch(url + (url.includes('?') ? '&' : '?') + 't=' + Date.now(), { cache: 'no-store' });
  if (!r.ok) throw new Error('blob fetch ' + r.status);
  return r;
}

export async function readMeta(id) {
  const b = await findBlob(`fonts/${id}/meta.json`);
  if (!b) return null;
  return (await fetchFresh(b.url)).json();
}

export async function writeMeta(meta) {
  await put(`fonts/${meta.id}/meta.json`, JSON.stringify(meta), { ...PUT_OPTS, contentType: 'application/json' });
}

export async function writeFile(id, name, body, contentType) {
  return put(`fonts/${id}/${name}`, body, { ...PUT_OPTS, contentType });
}

export async function deleteFont(id) {
  const r = await list({ prefix: `fonts/${id}/` });
  if (r.blobs.length) await del(r.blobs.map(b => b.url));
}

export function publicMeta(m) {
  const { tokenHash, ...rest } = m;
  return rest;
}

// Gallery index: one small JSON blob rewritten on publish/unpublish/download.
export async function readIndex() {
  const b = await findBlob('index.json');
  if (!b) return { fonts: [] };
  try { return await (await fetchFresh(b.url)).json(); } catch { return { fonts: [] }; }
}

export async function upsertIndex(meta) {
  const idx = await readIndex();
  const entry = { id: meta.id, name: meta.name, glyphs: meta.glyphs, downloads: meta.downloads, createdAt: meta.createdAt, updatedAt: meta.updatedAt };
  idx.fonts = idx.fonts.filter(f => f.id !== meta.id);
  if (meta.published) idx.fonts.push(entry);
  idx.fonts.sort((a, b) => (b.downloads - a.downloads) || (b.updatedAt > a.updatedAt ? 1 : -1));
  idx.fonts = idx.fonts.slice(0, 500);
  await put('index.json', JSON.stringify(idx), { ...PUT_OPTS, contentType: 'application/json' });
  return idx;
}
