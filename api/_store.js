import { put, list, del } from '@vercel/blob';

// Layout in the blob store. Every write gets a new, timestamped pathname and older versions are
// deleted afterwards: overwriting the same URL is edge-cached for up to a minute, which made
// publish/unpublish/download counts show stale values.
//   fonts/<id>/meta/<ts>.json      {id, name, glyphs, createdAt, updatedAt, published, downloads, city…, tokenHash}
//   fonts/<id>/font/<ts>.otf
//   fonts/<id>/strokes/<ts>.json
//   index/<ts>.json                 gallery index (published fonts only)
const PUT_OPTS = { access: 'public', addRandomSuffix: false, cacheControlMaxAge: 60 };
const ts = () => String(Date.now()).padStart(14, '0');

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

// Newest blob under a prefix (pathnames sort by timestamp) plus the older ones.
export async function versions(prefix) {
  const r = await list({ prefix, limit: 100 });
  const blobs = r.blobs.slice().sort((a, b) => (a.pathname < b.pathname ? 1 : -1));
  return { latest: blobs[0] || null, older: blobs.slice(1) };
}

export async function findLatest(prefix) {
  return (await versions(prefix)).latest;
}

export async function fetchBlob(url) {
  const r = await fetch(url, { cache: 'no-store' });
  if (!r.ok) throw new Error('blob fetch ' + r.status);
  return r;
}

async function putVersioned(prefix, ext, body, contentType) {
  const b = await put(`${prefix}${ts()}${ext}`, body, { ...PUT_OPTS, contentType });
  // Best-effort cleanup of previous versions.
  try {
    const { older } = await versions(prefix);
    const stale = older.filter(o => o.url !== b.url);
    if (stale.length) await del(stale.map(o => o.url));
  } catch (e) { console.error('cleanup failed', e); }
  return b;
}

export async function readMeta(id) {
  const b = await findLatest(`fonts/${id}/meta/`);
  if (!b) return null;
  return (await fetchBlob(b.url)).json();
}

export async function writeMeta(meta) {
  return putVersioned(`fonts/${meta.id}/meta/`, '.json', JSON.stringify(meta), 'application/json');
}

export async function writeFile(id, kind, body, contentType) {
  const ext = kind === 'strokes' ? '.json' : '.otf';
  return putVersioned(`fonts/${id}/${kind}/`, ext, body, contentType);
}

export async function readFile(id, kind) {
  const b = await findLatest(`fonts/${id}/${kind}/`);
  if (!b) return null;
  return Buffer.from(await (await fetchBlob(b.url)).arrayBuffer());
}

export async function deleteFont(id) {
  const r = await list({ prefix: `fonts/${id}/`, limit: 1000 });
  if (r.blobs.length) await del(r.blobs.map(b => b.url));
}

export function publicMeta(m) {
  const { tokenHash, ...rest } = m;
  return rest;
}

export async function readIndex() {
  const b = await findLatest('index/');
  if (!b) return { fonts: [] };
  try { return await (await fetchBlob(b.url)).json(); } catch { return { fonts: [] }; }
}

export async function upsertIndex(meta) {
  const idx = await readIndex();
  const entry = { id: meta.id, name: meta.name, glyphs: meta.glyphs, downloads: meta.downloads, createdAt: meta.createdAt, updatedAt: meta.updatedAt, city: meta.city, region: meta.region, country: meta.country, tz: meta.tz };
  idx.fonts = idx.fonts.filter(f => f.id !== meta.id);
  if (meta.published) idx.fonts.push(entry);
  idx.fonts.sort((a, b) => (b.downloads - a.downloads) || (b.updatedAt > a.updatedAt ? 1 : -1));
  idx.fonts = idx.fonts.slice(0, 500);
  await putVersioned('index/', '.json', JSON.stringify(idx), 'application/json');
  return idx;
}
