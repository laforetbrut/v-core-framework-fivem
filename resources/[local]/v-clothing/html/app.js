// v-clothing — catalogue UI (click a tile -> preview on the ped)
const byId = (id) => document.getElementById(id);
const post = (n, b) => fetch(`https://v-clothing/${n}`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(b || {}) }).then(r => r.json()).catch(() => false);
const fmt = (n) => '$' + Math.floor(Number(n) || 0).toLocaleString('en-US');

let strings = {}, cats = [], catMap = {}, worn = [];
let curCat = null, curDraw = 0, curTex = 0, texCount = 0, filter = '';
let thumbSet = new Set(), thumbObserver = null;
const t = (k) => strings[k] || k;
const applyStrings = () => document.querySelectorAll('[data-i18n]').forEach(el => { el.textContent = t(el.getAttribute('data-i18n')); });

function setTab(tab) {
  document.querySelectorAll('.tab').forEach(b => b.classList.toggle('on', b.getAttribute('data-tab') === tab));
  byId('pane-store').classList.toggle('hidden', tab !== 'store');
  byId('pane-worn').classList.toggle('hidden', tab !== 'worn');
  if (tab === 'worn') renderWorn();
}

function renderCats() {
  const wrap = byId('cats'); wrap.innerHTML = '';
  cats.forEach(c => {
    const b = document.createElement('button');
    b.className = 'chip' + (c.key === curCat ? ' on' : '');
    b.textContent = t(c.i18n);
    b.onclick = () => selectCategory(c.key);
    wrap.appendChild(b);
  });
}

async function selectCategory(key) {
  curCat = key; filter = ''; byId('search').value = '';
  renderCats();
  const c = catMap[key];
  curDraw = c.drawable;
  thumbSet = new Set();
  renderTiles();                       // instant grid (numbers)
  await selectDrawable(curDraw, false);
  // then discover which drawables have a generated thumbnail and upgrade
  const list = await post('thumbsFor', { category: key });
  if (key !== curCat) return;
  const set = new Set(Array.isArray(list) ? list.map(Number) : []);
  if (set.size) { thumbSet = set; renderTiles(); }
}

// ── Thumbnail loading: memory cache + batched fetches (one round-trip
//    per viewport instead of one per tile) ──
const thumbMem = new Map();            // "cat_d" -> data URI
let batchQueue = [], batchTimer = null;

async function flushThumbBatch() {
  batchTimer = null;
  const imgs = batchQueue.splice(0, 24);
  if (batchQueue.length && !batchTimer) batchTimer = setTimeout(flushThumbBatch, 60);
  if (!imgs.length) return;
  const out = await post('thumbsBatch', { list: imgs.map(i => ({ cat: i.dataset.cat, d: +i.dataset.d })) });
  const map = new Map((Array.isArray(out) ? out : []).map(e => [e.cat + '_' + e.d, e.uri]));
  imgs.forEach(img => {
    const key = img.dataset.cat + '_' + img.dataset.d;
    const uri = map.get(key);
    if (uri) { thumbMem.set(key, uri); img.src = uri; img.parentElement.classList.add('ready'); }
    else img.parentElement.classList.add('noimg');
  });
}

function requestThumb(img) {
  const key = img.dataset.cat + '_' + img.dataset.d;
  const hit = thumbMem.get(key);
  if (hit) { img.src = hit; img.parentElement.classList.add('ready'); return; }
  batchQueue.push(img);
  if (!batchTimer) batchTimer = setTimeout(flushThumbBatch, 60);
}

// Lazy-load a tile's thumbnail only when it scrolls into view.
function ensureObserver() {
  if (thumbObserver) return thumbObserver;
  thumbObserver = new IntersectionObserver((entries) => {
    entries.forEach((en) => {
      if (!en.isIntersecting) return;
      const img = en.target;
      thumbObserver.unobserve(img);
      if (img.dataset.loaded) return;
      img.dataset.loaded = '1';
      requestThumb(img);
    });
  }, { root: byId('tiles'), rootMargin: '160px' });
  return thumbObserver;
}

function renderTiles() {
  const c = catMap[curCat];
  const grid = byId('tiles'); grid.innerHTML = '';
  const obs = ensureObserver(); obs.disconnect();
  for (let d = c.min; d < c.count; d++) {
    if (filter && !String(d).includes(filter)) continue;
    const has = thumbSet.has(d);
    const tile = document.createElement('div');
    tile.className = 'tile' + (d === curDraw ? ' sel' : '') + (has ? ' has' : '');
    tile.dataset.d = d;
    if (d < 0) {
      tile.innerHTML = `<span class="none">&times;</span>`;
    } else if (has) {
      const img = document.createElement('img');
      img.className = 'thumb'; img.dataset.cat = curCat; img.dataset.d = d; img.alt = '';
      const badge = document.createElement('span'); badge.className = 'num'; badge.textContent = d;
      tile.append(img, badge);
      obs.observe(img);
    } else {
      tile.innerHTML = `<span class="num">${d}</span>`;
    }
    tile.onclick = () => selectDrawable(d, true);
    grid.appendChild(tile);
  }
}

async function selectDrawable(d, scroll) {
  curDraw = d;
  const res = await post('select', { category: curCat, drawable: d });
  texCount = (res && res.textureCount) || 0;
  curTex = 0;
  document.querySelectorAll('#tiles .tile').forEach(x => x.classList.toggle('sel', +x.dataset.d === d));
  if (scroll) { const el = [...document.querySelectorAll('#tiles .tile')].find(x => +x.dataset.d === d); if (el) el.scrollIntoView({ block: 'nearest' }); }
  renderTex();
  updateBar();
}

function renderTex() {
  const wrap = byId('tex'); wrap.innerHTML = '';
  for (let i = 0; i < Math.max(1, texCount); i++) {
    const b = document.createElement('button');
    b.className = 'tx' + (i === curTex ? ' sel' : '');
    b.textContent = i;
    b.onclick = async () => { curTex = i; await post('selectTexture', { category: curCat, drawable: curDraw, texture: i }); renderTex(); };
    wrap.appendChild(b);
  }
}

function updateBar() {
  const c = catMap[curCat];
  byId('bsel').innerHTML = `<b>${t(c.i18n)}</b> · <span class="bnum">#<b>${curDraw}</b></span>`;
  byId('buy').innerHTML = c.price > 0
    ? `${t('cl.buy')} · <b>${fmt(c.price)}</b>`
    : `${t('cl.buy')} · <em class="freetag">${t('cl.free')}</em>`;
}

byId('buy').onclick = async () => {
  const res = await post('buy', { category: curCat });
  if (res && res.cash !== undefined) byId('cash').textContent = fmt(res.cash);
};

byId('search').oninput = (e) => { filter = e.target.value.trim(); renderTiles(); };

function renderWorn() {
  const pane = byId('pane-worn'); pane.innerHTML = '';
  if (!worn.length) { pane.innerHTML = `<div class="empty">${t('cl.none')}</div>`; return; }
  worn.forEach(w => {
    const row = document.createElement('div');
    row.className = 'wrow';
    row.innerHTML = `<span class="wl">${t('item.' + w.item)}</span><button class="wu">${t('cl.unequip')}</button>`;
    row.querySelector('.wu').onclick = async () => { const res = await post('unequip', { category: w.cat }); if (Array.isArray(res)) { worn = res; renderWorn(); } };
    pane.appendChild(row);
  });
}

// ── Mouse drag → rotate the ped ──
let dragging = false, lastX = 0, accDx = 0, raf = false;
function flush() { if (accDx) { post('rotate', { dx: accDx }); accDx = 0; } raf = false; }
byId('stage').addEventListener('mousedown', (e) => { dragging = true; lastX = e.clientX; });
window.addEventListener('mouseup', () => { dragging = false; });
window.addEventListener('mousemove', (e) => { if (!dragging) return; accDx += e.clientX - lastX; lastX = e.clientX; if (!raf) { raf = true; requestAnimationFrame(flush); } });

document.querySelectorAll('.tab').forEach(b => b.onclick = () => setTab(b.getAttribute('data-tab')));
function close() { byId('cl').classList.add('hidden'); byId('stage').classList.add('hidden'); post('close'); }
byId('close').onclick = close;
document.addEventListener('keydown', (e) => { if (e.key === 'Escape' && !byId('cl').classList.contains('hidden')) close(); });

// ── Admin scan: isolate the garment and upload the thumbnail ──
// Two shots arrive from Lua: the bare slot and the dressed slot. Keeping only
// the pixels that CHANGED leaves the garment alone on a transparent
// background (no character, no scenery), which is then cropped, squared,
// downscaled and POSTed to the game server over HTTP (net events would kick).
const loadImg = (uri) => new Promise((res, rej) => { const i = new Image(); i.onload = () => res(i); i.onerror = rej; i.src = uri; });

// Soft-ramp diff matte + block-density bounding box (kills speckle noise).
function isolateGarment(pxI, pxB, W, H, t0, t1, pad) {
  const a = pxI.data, b = pxB.data;
  const B = 8, bw = Math.ceil(W / B), bh = Math.ceil(H / B);
  const blocks = new Uint16Array(bw * bh);
  for (let y = 0; y < H; y++) {
    const rowB = Math.floor(y / B) * bw;
    for (let x = 0; x < W; x++) {
      const i = (y * W + x) * 4;
      const dl = Math.abs(a[i] - b[i]) + Math.abs(a[i + 1] - b[i + 1]) + Math.abs(a[i + 2] - b[i + 2]);
      let al = 0;
      if (dl >= t1) al = 255; else if (dl > t0) al = Math.round(((dl - t0) / (t1 - t0)) * 255);
      a[i + 3] = al;
      if (al > 96) blocks[rowB + Math.floor(x / B)]++;
    }
  }
  let minX = W, minY = H, maxX = -1, maxY = -1;
  for (let by = 0; by < bh; by++) for (let bx = 0; bx < bw; bx++) {
    if (blocks[by * bw + bx] >= 10) {
      if (bx * B < minX) minX = bx * B;
      if (by * B < minY) minY = by * B;
      if ((bx + 1) * B > maxX) maxX = (bx + 1) * B;
      if ((by + 1) * B > maxY) maxY = (by + 1) * B;
    }
  }
  if (maxX < 0) { minX = W / 2 - 96; minY = H / 2 - 96; maxX = W / 2 + 96; maxY = H / 2 + 96; }  // nothing changed -> transparent thumb
  const w = maxX - minX, h = maxY - minY;
  const padPx = Math.round(Math.max(w, h) * pad);
  const side = Math.max(w, h) + padPx * 2;
  const sx = Math.round((minX + maxX) / 2 - side / 2), sy = Math.round((minY + maxY) / 2 - side / 2);
  const full = document.createElement('canvas'); full.width = W; full.height = H;
  full.getContext('2d').putImageData(pxI, 0, 0);
  const out = document.createElement('canvas'); out.width = side; out.height = side;
  out.getContext('2d').drawImage(full, sx, sy, side, side, 0, 0, side, side);
  return out;
}

async function handleThumbProcess(d) {
  const done = (ok) => post('thumbDone', { ok });
  try {
    const item = await loadImg(d.item);
    const W = item.width, H = item.height;
    let cropped = null;
    if (d.base) {
      const base = await loadImg(d.base);
      const cvI = document.createElement('canvas'); cvI.width = W; cvI.height = H;
      const gI = cvI.getContext('2d'); gI.drawImage(item, 0, 0);
      const cvB = document.createElement('canvas'); cvB.width = W; cvB.height = H;
      const gB = cvB.getContext('2d'); gB.drawImage(base, 0, 0, W, H);
      cropped = isolateGarment(gI.getImageData(0, 0, W, H), gB.getImageData(0, 0, W, H),
        W, H, d.diffMin || 30, d.diffMax || 90, (d.pad === 0 || d.pad) ? d.pad : 0.1);
    }
    if (!cropped) {   // isolation disabled -> plain centered square
      const side = Math.min(W, H);
      cropped = document.createElement('canvas'); cropped.width = side; cropped.height = side;
      cropped.getContext('2d').drawImage(item, (W - side) / 2, (H - side) / 2, side, side, 0, 0, side, side);
    }
    const s = d.size || 384;
    const fin = document.createElement('canvas'); fin.width = s; fin.height = s;
    fin.getContext('2d').drawImage(cropped, 0, 0, s, s);
    const uri = (d.format === 'png') ? fin.toDataURL('image/png') : fin.toDataURL('image/webp', d.quality || 0.9);
    const r = await fetch(`http://${d.endpoint}/${d.res}/upload`, {
      method: 'POST', headers: { 'Content-Type': 'text/plain' },   // simple request: no CORS preflight
      body: JSON.stringify({ t: d.token, cat: d.cat, d: d.drawable, uri }),
    });
    done(r.ok);
  } catch (e) { done(false); }
}

// Scan progress overlay (driven by local Lua messages).
function scanUI(d) {
  const ov = byId('scanov');
  if (d.phase === 'start') {
    byId('scantitle').textContent = d.title || 'Scan';
    byId('scanfill').style.width = '0%';
    byId('scanlabel').textContent = '';
    byId('scancount').textContent = `0 / ${d.total || 0}`;
    ov.classList.remove('hidden');
  } else if (d.phase === 'item') {
    byId('scanfill').style.width = (d.total ? Math.round((d.done / d.total) * 100) : 0) + '%';
    byId('scanlabel').textContent = d.label || '';
    byId('scancount').textContent = `${d.done} / ${d.total}`;
  } else if (d.phase === 'done') {
    byId('scanfill').style.width = '100%';
    setTimeout(() => ov.classList.add('hidden'), 1600);
  }
}

window.addEventListener('message', (e) => {
  const d = e.data || {};
  if (d.action === 'processThumb') {
    handleThumbProcess(d);
  } else if (d.action === 'scanUI') {
    scanUI(d);
  } else if (d.action === 'open') {
    strings = d.strings || {}; cats = d.cats || []; worn = d.worn || [];
    catMap = {}; cats.forEach(c => catMap[c.key] = c);
    if (d.cash !== undefined) byId('cash').textContent = fmt(d.cash);
    applyStrings(); setTab('store');
    if (cats[0]) selectCategory(cats[0].key);
    byId('cl').classList.remove('hidden');
    byId('stage').classList.remove('hidden');
  } else if (d.action === 'close') {
    byId('cl').classList.add('hidden');
    byId('stage').classList.add('hidden');
  }
});
