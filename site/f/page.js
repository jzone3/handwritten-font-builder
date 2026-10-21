(function () {
  'use strict';
  const $ = (id) => document.getElementById(id);
  const id = (location.pathname.match(/\/f\/([a-z0-9]{6,12})/) || [])[1] || new URLSearchParams(location.search).get('id');
  if (!id) { $('fontTitle').textContent = 'No font here.'; return; }
  const token = localStorage.getItem('hfb.pub.' + id);
  $('previewBox').style.fontSize = $('previewSize').value + 'px';
  $('previewSize').addEventListener('input', (e) => { $('previewBox').style.fontSize = e.target.value + 'px'; });

  const pageUrl = location.origin + '/f/' + id;
  $('downloadBtn').href = '/api/download?id=' + id;
  $('strokesBtn').href = '/api/file?id=' + id + '&kind=strokes';
  $('strokesBtn').download = 'strokes.json';
  $('shareBtn').addEventListener('click', async () => {
    const data = { title: document.title, text: 'A font made from my handwriting', url: pageUrl };
    if (navigator.share) { try { await navigator.share(data); } catch (e) {} return; }
    try { await navigator.clipboard.writeText(pageUrl); $('shareBtn').textContent = 'Link copied'; setTimeout(() => $('shareBtn').textContent = 'Share…', 1500); } catch (e) { prompt('Copy this link', pageUrl); }
  });

  async function load() {
    const r = await fetch('/api/font?id=' + id);
    if (!r.ok) { $('fontTitle').textContent = r.status === 404 ? 'This font was taken down.' : 'Could not load this font.'; return; }
    const m = await r.json();
    document.title = m.name + ' · a handwritten font';
    $('fontTitle').textContent = m.name;
    $('fontMeta').textContent = m.glyphs + ' letters · ' + m.downloads + ' download' + (m.downloads === 1 ? '' : 's') + (m.published ? '' : ' · unlisted');
    try {
      const face = new FontFace('HFBPage', 'url(/api/file?id=' + id + '&kind=otf)');
      await face.load(); document.fonts.add(face);
      $('previewBox').style.fontFamily = '"HFBPage", "Comic Sans MS", cursive';
    } catch (e) { $('fontMeta').textContent += ' · preview failed to load'; }
    if (token) {
      $('ownerBox').hidden = false;
      $('publishedToggle').checked = !!m.published;
      $('publishedToggle').addEventListener('change', async (e) => {
        const pr = await fetch('/api/font', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ id, token, published: e.target.checked }) });
        $('ownerStatus').textContent = pr.ok ? (e.target.checked ? 'Published.' : 'Unpublished. Only people with the link can still open it.') : 'Could not save that.';
      });
      $('deleteLink').addEventListener('click', async (e) => {
        e.preventDefault();
        if (!confirm('Delete this font from the site? Your drawings stay in your browser.')) return;
        const pr = await fetch('/api/font', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ id, token, delete: true }) });
        if (pr.ok) { localStorage.removeItem('hfb.pub.' + id); location.href = '/#done'; } else $('ownerStatus').textContent = 'Could not delete.';
      });
    }
  }
  load();
})();
