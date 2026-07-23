// v-phone — iFruit, Clear Glass 27 shell
//
// Every built-in app below is a VIEW. It renders what the owning module answered and
// sends actions back to that module; it never keeps a copy. The moment an app caches a
// balance or a vehicle list there are two sources of truth, and one of them is wrong.
//
// The same UI kit that draws the built-in apps is handed to third-party apps through
// sdk.js, so an app somebody else ships looks native without copying a stylesheet.

const byId = (id) => document.getElementById(id);
// The escaper, the icon set and the component kit all live in sdk.js, so the built-in
// apps and any app a third party ships are drawing themselves with the same code. Two
// copies of a design system drift the first time either side is touched.
const esc = PhoneUI.esc;
const svg = PhoneUI.svg;
const UI = PhoneUI;

// Every call into Lua goes through here. Network failures become renderable errors;
// read requests from an abandoned view are suspended so they cannot repaint its successor.
let viewController = typeof AbortController === 'function' ? new AbortController() : null;
let viewEpoch = 0;

function beginView() {
  viewEpoch += 1;
  if (!viewController) return;
  viewController.abort();
  viewController = new AbortController();
}

const RESOURCE_NAME = typeof GetParentResourceName === 'function'
  ? GetParentResourceName()
  : 'v-phone';

function isViewRead(name, payload) {
  const op = payload && payload.op;
  if (['ambient', 'calls', 'conversation', 'app', 'card', 'places', 'airdropScan'].includes(name)) return true;
  if (name === 'health') return op == null || op === 'get';
  if (name === 'notes') return op === 'list';
  if (name === 'mail') return op === 'me' || op === 'list' || op === 'saved';
  if (name === 'photos' || name === 'voicemail') return op === 'list';
  if (name === 'appStorage') return op === 'get';
  if (name === 'mdt') return op === 'lookup' || op === 'warrants';
  if (name === 'social') return ['me', 'feed', 'hushMe', 'hushNext'].includes(op);
  return false;
}

const post = (n, b) => {
  const options = {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(b || {}),
  };
  // Only read requests owned by a renderer are cancellable. Mutations, controls and
  // refreshes must finish even when the player navigates while their response is in flight.
  if (viewController && isViewRead(n, b)) options.signal = viewController.signal;
  return fetch(`https://${RESOURCE_NAME}/${n}`, options)
    .then((r) => r.json())
    .catch((error) => {
      if (error && error.name === 'AbortError') {
        // Keep the abandoned async renderer suspended so it cannot paint an error state
        // over the view that replaced it.
        return new Promise(() => {});
      }
      return { error: 'x' };
    });
};

// Tile backgrounds come from the icon table in sdk.js (UI.appIcon).

// ══ State ══════════════════════════════════════════════════════
let S = {};             // strings
let state = {};         // number, apps, prefs, contacts, conversations
let call = null;
let callStart = 0, callTimer = null;
let openApp = null;
let thread = null;
let threadGroup = null;
let dialed = '';
let page = 0;
let notifs = [];        // the notification centre, newest first
let notifSeq = 0;       // stable ids so a card can be dismissed by hand
let notificationOwner = null;
let shadeManage = false;

// An app id from whatever the banner carried. Most callers name the app; the SDK path
// only knows an icon, so it falls back to that.
function notifApp(b) { return b.app || b.icon || 'dot'; }

// A player can silence an app from the shade. A muted app still runs; it just does not
// light the island or land in the centre. The list lives in prefs, so it survives.
function appMuted(id) { return ((state.prefs || {}).notifMuted || []).indexOf(id) !== -1; }
async function setAppMuted(id, on) {
  const cur = ((state.prefs || {}).notifMuted || []).filter((x) => x !== id);
  if (on) cur.push(id);
  const r = await post('prefs', { notifMuted: cur });
  if (r && r.ok) state.prefs = r.prefs;
}
let recents = [];       // app ids, most recently opened first
let available = [];     // what the operator permits; the store lists these
let editing = false;    // home screen in arrange mode
let navBackAction = null;
let activeAppEpoch = 0;

const L = (k) => S[k] || k;
const money = (n) => '$' + Number(n || 0).toLocaleString('en-US');

// ══ Clock ══════════════════════════════════════════════════════
function tick() {
  const d = new Date();
  const hh = String(d.getHours()).padStart(2, '0');
  const mm = String(d.getMinutes()).padStart(2, '0');
  byId('clock').textContent = `${hh}:${mm}`;
  byId('lockclock').textContent = `${hh}:${mm}`;
  byId('lockdate').textContent = d.toLocaleDateString(undefined, { weekday: 'long', day: 'numeric', month: 'long' });
}
setInterval(tick, 10000);

// ══ Screens ════════════════════════════════════════════════════
// The island is the phone's face. It should react to the phone being locked and unlocked
// the way a real one does: a short pinch around a padlock, then back to a pill.
let glanceTimer = null, shutterTimer = null;
const ISLAND_MODES = ['live', 'notif', 'glance'];

// Dynamic Island modes are mutually exclusive. Calls always win: a notification or
// lock glance may be queued elsewhere, but it never paints over an active call.
function setIslandMode(mode) {
  const isl = byId('island');
  const next = call ? 'live' : (ISLAND_MODES.includes(mode) ? mode : null);
  ISLAND_MODES.forEach((name) => isl.classList.toggle(name, name === next));
  delete isl.dataset.notif;
}

function islandGlance(icon, tint) {
  if (call) return;                       // a live call owns the island outright
  const isl = byId('island');
  byId('inicon').innerHTML = '<span class="iglyph" style="color:' + (tint || '#fff') + '">' + svg(icon) + '</span>';
  byId('inTitle').textContent = '';
  byId('inBody').textContent = '';
  setIslandMode('glance');
  clearTimeout(glanceTimer);
  glanceTimer = setTimeout(() => {
    if (!call && isl.classList.contains('glance')) setIslandMode(null);
  }, 1500);
}

function unlock() {
  byId('lock').classList.add('out');
  byId('lockquick').classList.add('hidden');
  byId('home').classList.remove('behind');
  islandGlance('lockopen', '#30D158');
  renderHome();
}

function lockScreen() {
  closeApp(true);
  byId('lock').classList.remove('out');
  byId('lockquick').classList.remove('hidden');
  byId('home').classList.add('behind');
  islandGlance('lockshut', '#fff');
}

function goHome() {
  if (byId('cc').classList.contains('on')) { byId('cc').classList.remove('on'); return; }
  if (byId('sheet').classList.contains('on')) { closeSheet(); return; }
  if (byId('app').classList.contains('on')) { closeApp(); return; }
  // The Home indicator returns to Home; locking belongs to the power button.
}

// ══ Home ═══════════════════════════════════════════════════════
function unreadTotal() {
  return (state.conversations || []).reduce((n, c) => n + (c.unread || 0), 0);
}

function tileHTML(a, i) {
  const badge = a.id === 'messages' ? unreadTotal()
    : a.id === 'phone' ? Number(state.vmUnread || 0)
    : (a.badge || 0);
  return `<button class="tile" type="button" data-app="${esc(a.id)}" style="--i:${i}">` +
    `<span class="wrap">${UI.appIcon(a.icon)}` +
    (badge > 0 ? `<span class="badge">${badge > 99 ? '99+' : badge}</span>` : '') +
    `</span><span class="nm">${esc(L(a.label))}</span></button>`;
}

function renderHome() {
  byId('pages').classList.remove('jiggle');
  const apps = (state.apps || []).slice();
  // The last four go in the dock, the way iOS ships: the apps you reach for without
  // thinking stay put while the grid pages move.
  const dockApps = apps.filter((a) => a.dock).slice(0, 4);

  const items = layoutItems();
  paintPages(items);
  byId('dock').innerHTML = dockApps.map((a, i) => tileHTML(a, i)).join('');
  // The dock lives outside #pages, so paintPages does not reach it - it needs its own
  // click wiring or the four apps at the bottom stop opening (which they did).
  [...byId('dock').querySelectorAll('.tile')].forEach((t) => {
    t.addEventListener('click', () => {
      if (editing) return;
      const a = (state.apps || []).find((x) => x.id === t.dataset.app);
      if (a) enterApp(a, t);
    });
  });


  // Arrange mode survives a re-render: a drop stays in the jiggle until Done.
  byId('home').classList.toggle('arrange', editing);
  byId('pages').classList.toggle('jiggle', editing);

  initArrange();
  renderWidgets();
}

// Four rows is what fits beneath the widgets. Splitting 17 icons as 16 + 1 strands a
// single app on page two, which reads as "the rest did not load"; so on overflow the
// pages are BALANCED - nine and eight both look like pages, sixteen and one does not.
let arrPerPage = 16;

function fitGrid(cols, rows) {
  const pg = byId('pages');
  const page = pg.querySelector('.page');
  if (!page) return;
  const cs = getComputedStyle(page);
  const h = page.clientHeight - parseFloat(cs.paddingTop || 0) - parseFloat(cs.paddingBottom || 0);
  const w = page.clientWidth - parseFloat(cs.paddingLeft || 0) - parseFloat(cs.paddingRight || 0);
  if (h <= 0 || w <= 0) return;

  const apply = (size) => {
    pg.style.setProperty('--isz', size + 'px');
    pg.style.setProperty('--iradius', Math.round(size * 0.225) + 'px');
    pg.style.setProperty('--ilabel', (size >= 52 ? 11.5 : size >= 42 ? 10.5 : 9.5) + 'px');
    // The spacing has to give way with the icon, or a tight grid stays too tall to fit
    // however small the icons get.
    pg.style.setProperty('--tgap', (size >= 50 ? 6 : size >= 38 ? 4 : 2) + 'px');
    pg.style.setProperty('--rgap', (size >= 50 ? 8 : size >= 38 ? 5 : 3) + 'px');
  };

  // Start from an estimate, then check it against the real thing. Arithmetic about
  // padding, gaps and label height is exactly the sort of guess that ends up one row
  // short, so the estimate is only a starting point: what settles it is measuring.
  const cellH = h / rows, cellW = w / cols;
  let size = Math.max(22, Math.min(60, Math.floor(Math.min(cellH - 24, cellW - 8))));
  apply(size);

  // Whether it overflows is a question about the page, not about the last tile: in a grid
  // that exactly fills its rows the last row's bottom IS the page's bottom, and comparing
  // those two was a tie the loop could never win - it shrank the icons to the floor.
  for (let i = 0; i < 14 && size > 22; i++) {
    // A row that genuinely does not fit is tens of pixels tall. A handful of pixels is
    // chrome - a badge sitting proud of its icon - and shrinking for that collapsed the
    // icons to nothing on grids that were actually fine.
    if (page.scrollHeight <= page.clientHeight + 18) break;
    size -= 3;
    apply(size);
  }
}

// The track is what slides; the pager around it is a fixed window that clips.
function slideTrack() {
  const t = byId('pages').querySelector('.ptrack');
  if (t) t.style.transform = 'translateX(' + (-page * 100) + '%)';
}
function paintPages(items) {
  // A FIXED page size, not a balanced one. Balancing spread the icons evenly across
  // however many pages were needed, which meant installing a single app re-flowed every
  // page and threw away an arrangement the player had made. A page holds what a page
  // holds; anything past that starts a new one, and the pages before it never move.
  // How much that is, is the player's own choice of grid.
  const gp = state.prefs || {};
  const gCols = Math.max(3, Math.min(6, Number(gp.gridCols) || 4));
  const gRows = Math.max(3, Math.min(7, Number(gp.gridRows) || 4));
  byId('pages').style.setProperty('--gcols', String(gCols));
  byId('pages').style.setProperty('--grows', String(gRows));
  arrPerPage = gCols * gRows;
  const pages = [];
  for (let i = 0; i < items.length; i += arrPerPage) pages.push(items.slice(i, i + arrPerPage));
  if (!pages.length) pages.push([]);
  page = Math.max(0, Math.min(pages.length - 1, page));

  byId('pages').innerHTML = '<div class="ptrack">' + pages.map((pg) =>
    '<div class="page">' + pg.map((it, i) => {
      if (it.t === 'gap') return '<div class="tile gap"></div>';
      return it.t === 'folder' ? folderTile(it, i)
                               : tileHTML(appById(it.id) || { id: it.id, icon: 'dot', label: it.id }, i);
    }).join('') + '</div>').join('') + '</div>';
  // data-idx is the position in `items`, counting only real tiles, so a drop can read it.
  let k = -1;
  [...byId('pages').querySelectorAll('.tile')].forEach((t) => {
    if (t.classList.contains('gap')) return;
    k += 1; t.dataset.idx = k;
  });
  slideTrack();
  byId('dots').innerHTML = pages.map((_, i) => `<i class="${i === page ? 'on' : ''}"></i>`).join('');

  // The grid only "works" if it fits. Rows share the page height, so the icon has to be
  // sized from what a cell actually gets - otherwise six rows of 60px icons simply spill
  // past the bottom of the screen and the last rows look like they were never drawn.
  fitGrid(gCols, gRows);

  [...byId('pages').querySelectorAll('.tile:not(.gap)')].forEach((t) => {
    t.addEventListener('click', () => {
      if (editing) return;   // a tap in arrange mode never launches
      const gi = Number(t.dataset.idx);
      if (t.classList.contains('isfolder')) { openFolder(gi); return; }
      const a = (state.apps || []).find((x) => x.id === t.dataset.app);
      if (a) enterApp(a, t);
    });
  });
}

// ══ Home layout ════════════════════════════════════════════════
// The player's arrangement is a list of ITEMS, each an app or a folder. Anything
// installed but not in the list is appended, so an app added next month appears at the
// end rather than vanishing because it was not in a saved layout.
function layoutItems() {
  const apps = (state.apps || []).filter((a) => !a.dock);
  const byId2 = {};
  apps.forEach((a) => { byId2[a.id] = a; });

  const saved = ((state.prefs || {}).layout || {}).items;
  const items = [];
  const seen = new Set();

  (Array.isArray(saved) ? saved : []).forEach((it) => {
    if (!it) return;
    if (it.t === 'folder') {
      const inside = (it.apps || []).filter((id) => byId2[id] && !seen.has(id));
      inside.forEach((id) => seen.add(id));
      // A folder that lost every app it held is not a folder any more.
      if (inside.length) items.push({ t: 'folder', name: it.name || L('ph.folder'), apps: inside });
    } else if (byId2[it.id] && !seen.has(it.id)) {
      seen.add(it.id);
      items.push({ t: 'app', id: it.id });
    }
  });

  apps.forEach((a) => { if (!seen.has(a.id)) items.push({ t: 'app', id: a.id }); });
  return items;
}

function saveLayout(items) {
  state.prefs = state.prefs || {};
  state.prefs.layout = { items };
  return post('prefs', { layout: state.prefs.layout });
}

function appById(id) { return (state.apps || []).find((a) => a.id === id); }

function folderTile(it, i) {
  const four = it.apps.slice(0, 4).map((id) => {
    const a = appById(id);
    return '<span>' + (a ? UI.appIcon(a.icon) : '') + '</span>';
  }).join('');
  return '<button class="tile isfolder" type="button" data-folder="1" style="--i:' + i + '">' +
    '<span class="wrap"><span class="folder glass">' + four + '</span></span>' +
    '<span class="nm">' + esc(it.name) + '</span></button>';
}

function openFolder(i) {
  const it = layoutItems()[i];
  if (!it || it.t !== 'folder') return;
  byId('foldername').textContent = it.name;
  byId('folderapps').innerHTML = it.apps.map((id, k) => {
    const a = appById(id);
    return a ? tileHTML(a, k) : '';
  }).join('');
  byId('folderview').classList.add('on');
  [...byId('folderapps').querySelectorAll('.tile')].forEach((t) =>
    t.addEventListener('click', () => {
      byId('folderview').classList.remove('on');
      const a = appById(t.dataset.app);
      if (a) enterApp(a, t);
    }));
}

byId('folderview').addEventListener('click', (e) => {
  if (e.target.id === 'folderview') byId('folderview').classList.remove('on');
});

// ══ Arrange mode ═══════════════════════════════════════════════
// A real drag: the tile lifts into a clone that follows the finger, the grid opens a gap
// where it will land, and it stays in arrange mode until Done - a drop no longer kicks
// you out. Hold a tile to enter; drag onto another app to make a folder.
let arr = null;          // the live drag session, or null
let arrWired = false;

function enterArrange() {
  editing = true;
  byId('arrangedone').textContent = L('ph.arrange_done');
  byId('home').classList.add('arrange');
  byId('pages').classList.add('jiggle');
}
function exitArrange() {
  editing = false;
  endDrag(true);
  byId('home').classList.remove('arrange');
  byId('pages').classList.remove('jiggle');
}

function ptOf(e) {
  const r = byId('screen').getBoundingClientRect();
  return { x: e.clientX - r.left, y: e.clientY - r.top };
}
function moveGhost(e) {
  const p = ptOf(e), g = byId('dragghost');
  g.style.left = p.x + 'px'; g.style.top = p.y + 'px';
}

function beginDrag(tile, e) {
  const items = layoutItems();
  const idx = Number(tile.dataset.idx);
  if (Number.isNaN(idx)) return;
  const item = items[idx];
  arr = { item, items: items.filter((_, i) => i !== idx), insert: idx,
          hoverEl: null, since: 0, folderIdx: null, folderTimer: null, edgeTimer: null };

  const g = byId('dragghost');
  const ic = tile.querySelector('.ic, .folder');
  const nm = tile.querySelector('.nm');
  g.innerHTML = (ic ? ic.outerHTML : '') + (nm ? nm.outerHTML : '');
  g.classList.add('on');
  moveGhost(e);
  paintArrange();
}

function paintArrange() {
  const withGap = arr.items.slice();
  withGap.splice(Math.max(0, Math.min(withGap.length, arr.insert)), 0, { t: 'gap' });
  paintPages(withGap);
  byId('pages').classList.add('jiggle');
}

function clearFolder() {
  if (arr.folderTimer) { clearTimeout(arr.folderTimer); arr.folderTimer = null; }
  arr.folderIdx = null;
  [...byId('pages').querySelectorAll('.tile.folderready')].forEach((t) => t.classList.remove('folderready'));
}

function onDragMove(e) {
  if (!arr) return;
  moveGhost(e);

  const pages = byId('pages').querySelectorAll('.page');
  const cur = pages[page];
  if (!cur) return;

  // Edge of the screen, held: flip to the next page, so a drag can cross pages.
  const p = ptOf(e), w = byId('screen').clientWidth;
  const edge = (p.x < 24 && page > 0) ? -1 : (p.x > w - 24 && page < pages.length - 1) ? 1 : 0;
  if (edge && !arr.edgeTimer) {
    arr.edgeTimer = setTimeout(() => { arr.edgeTimer = null; flipPage(edge); }, 420);
  } else if (!edge && arr.edgeTimer) { clearTimeout(arr.edgeTimer); arr.edgeTimer = null; }

  const base = page * arrPerPage;

  // Nearest real tile, worked out first: if the finger is deep inside one, that is a
  // folder gesture and the grid must HOLD STILL - the reorder gap only opens in the seams
  // between tiles. Chasing the finger into the centre of a tile is exactly what made the
  // old version feel broken, because the target kept fleeing the drop.
  let near = null, best = 1e9;
  const tiles = [...cur.querySelectorAll('.tile:not(.gap)')];
  tiles.forEach((t) => {
    const r = t.getBoundingClientRect();
    const d = Math.hypot(e.clientX - (r.left + r.width / 2), e.clientY - (r.top + r.height / 2));
    if (d < best) { best = d; near = t; }
  });
  const deep = near && best < near.getBoundingClientRect().width * 0.34;

  if (deep && arr.item.t === 'app') {
    // Fold zone: leave the layout alone, arm the folder after a short dwell.
    if (near !== arr.hoverEl) {
      clearFolder();
      arr.hoverEl = near;
      const oi = Number(near.dataset.idx);
      arr.folderTimer = setTimeout(() => { arr.folderIdx = oi; near.classList.add('folderready'); }, 300);
    }
    return;
  }

  // Seam: a plain reorder. Drop before the first tile the pointer is above-or-left of.
  if (arr.hoverEl) { arr.hoverEl = null; clearFolder(); }
  let ins = base + tiles.length;
  for (let i = 0; i < tiles.length; i++) {
    const r = tiles[i].getBoundingClientRect();
    const cx = r.left + r.width / 2, cy = r.top + r.height / 2;
    if (e.clientY < cy - 6 || (Math.abs(e.clientY - cy) <= r.height / 2 && e.clientX < cx)) { ins = base + i; break; }
  }
  if (ins !== arr.insert) { arr.insert = ins; paintArrange(); }
}

function onDragEnd() {
  if (!arr) return;
  const a = arr;
  if (a.edgeTimer) clearTimeout(a.edgeTimer);
  if (a.folderTimer) clearTimeout(a.folderTimer);
  byId('dragghost').classList.remove('on');

  if (a.folderIdx != null && a.item.t === 'app') {
    const tgt = a.items[a.folderIdx];
    if (tgt && tgt.t === 'folder') tgt.apps.push(a.item.id);
    else if (tgt && tgt.t === 'app') a.items[a.folderIdx] = { t: 'folder', name: L('ph.folder'), apps: [tgt.id, a.item.id] };
    else a.items.splice(a.insert, 0, a.item);
  } else {
    a.items.splice(Math.max(0, Math.min(a.items.length, a.insert)), 0, a.item);
  }
  arr = null;
  saveLayout(a.items).then(() => renderHome());
}

function endDrag(cancel) {
  if (!arr) return;
  if (arr.edgeTimer) clearTimeout(arr.edgeTimer);
  if (arr.folderTimer) clearTimeout(arr.folderTimer);
  byId('dragghost').classList.remove('on');
  const items = cancel ? layoutItems() : arr.items;
  arr = null;
  paintPages(items);
  byId('pages').classList.toggle('jiggle', editing);
}

// Attached once to the stable #pages container, so it survives every re-render.
function initArrange() {
  if (arrWired) return;
  arrWired = true;
  const pagesEl = byId('pages');
  let hold = null, downTile = null, downXY = null;

  pagesEl.addEventListener('pointerdown', (e) => {
    const tile = e.target.closest ? e.target.closest('.tile:not(.gap)') : null;
    downXY = { x: e.clientX, y: e.clientY };
    if (editing) { downTile = tile; if (tile) beginDrag(tile, e); return; }
    if (!tile) return;
    downTile = tile;
    hold = setTimeout(() => { hold = null; enterArrange(); beginDrag(tile, e); }, 380);
  });

  window.addEventListener('pointermove', (e) => {
    if (hold && downXY && Math.hypot(e.clientX - downXY.x, e.clientY - downXY.y) > 10) {
      clearTimeout(hold); hold = null;   // a swipe, not a hold
    }
    if (arr) { e.preventDefault(); onDragMove(e); }
  }, { passive: false });

  window.addEventListener('pointerup', () => {
    if (hold) { clearTimeout(hold); hold = null; }
    if (arr) { onDragEnd(); downTile = null; return; }
    // A tap on empty space in arrange mode leaves it, the way iOS does.
    if (editing && !downTile) exitArrange();
    downTile = null;
  });

  byId('arrangedone').addEventListener('click', exitArrange);
}

function flipPage(dir) {
  // Clamped to the pages that exist, so flipping past the end cannot slide the grid off
  // the screen and leave nothing showing.
  const n = byId('pages').querySelectorAll('.page').length;
  page = Math.max(0, Math.min(n - 1, page + dir));
  slideTrack();
  byId('dots').innerHTML = [...Array(n)].map((_, i) => `<i class="${i === page ? 'on' : ''}"></i>`).join('');
}

// ══ Widgets ════════════════════════════════════════════════════
// Both show something true: the weather the server is running, and the in-game date.
// A widget showing the player's real-world clock would be showing the wrong clock.
const WEATHER_ICON = {
  EXTRASUNNY: 'sun', CLEAR: 'sun', CLOUDS: 'cloud', OVERCAST: 'cloud', SMOG: 'cloud',
  FOGGY: 'cloud', RAIN: 'rain', THUNDER: 'rain', CLEARING: 'cloud', NEUTRAL: 'sun',
  SNOW: 'snow', BLIZZARD: 'snow', SNOWLIGHT: 'snow', XMAS: 'snow', HALLOWEEN: 'cloud',
};
const MONTHS = ['jan', 'feb', 'mar', 'apr', 'may', 'jun', 'jul', 'aug', 'sep', 'oct', 'nov', 'dec'];

async function renderWidgets() {
  const host = byId('widgets');
  if (!host) return;
  const d = await post('ambient');
  if (!d || !d.ok) { host.innerHTML = ''; return; }
  gameHour = Number(d.hours);
  applyTheme();
  const w = String(d.weather || 'CLEAR').toUpperCase();
  const icon = WEATHER_ICON[w] || 'sun';
  const hh = String(d.hours).padStart(2, '0') + ':' + String(d.minutes).padStart(2, '0');
  host.innerHTML =
    '<div class="widget weather"><div class="wtop"><span>' + esc(L('ph.los_santos')) + '</span>' +
      '<span class="wicon">' + svg(icon) + '</span></div>' +
      '<div><div class="wbig">' + esc(hh) + '</div>' +
      '<div class="wsub">' + esc(L('ph.weather_' + icon)) + '</div></div></div>' +
    '<div class="widget cal"><div class="wday">' + esc(L('ph.month_' + MONTHS[(d.month || 1) - 1])) + '</div>' +
      '<div class="wnum">' + esc(d.day || 1) + '</div>' +
      '<div class="wsub">' + esc(L('ph.in_game_date')) + '</div></div>';
}

// ══ App shell ══════════════════════════════════════════════════
// The zoom origin is taken from the icon that launched it. That one detail is most of
// what makes opening an app feel like iOS rather than a page swap.
function clearActiveApp() {
  const epoch = ++activeAppEpoch;
  return post('activeApp', { app: '', epoch });
}

function clearAppVisualState() {
  const app = byId('app');
  app.classList.remove('black', 'camfull');
  byId('screen').classList.remove('appblack');
  byId('navbar').classList.remove('hidden');
}

function enterApp(a, tile) {
  beginView();
  resetTransientUI();
  openApp = a; thread = null;
  threadGroup = null;
  navBackAction = null;
  // Most recent first, no duplicates. This is the switcher's whole model.
  recents = [a.id].concat(recents.filter((id) => id !== a.id)).slice(0, 8);
  const app = byId('app');
  // Leaving the camera for anywhere else drops its immersive chrome and unrotates.
  clearAppVisualState();
  app.dataset.app = a.id;
  if (landscape) setLandscape(false);
  if (tile) {
    const r = tile.getBoundingClientRect();
    const s = byId('screen').getBoundingClientRect();
    app.style.transformOrigin = `${r.left + r.width / 2 - s.left}px ${r.top + r.height / 2 - s.top}px`;
  }
  app.classList.remove('closing');
  app.classList.add('on');
  byId('screen').classList.add('app-open');
  setNav(L(a.label), null);
  byId('appfoot').innerHTML = '';

  if (a.page) {
    // A third-party app only receives a URL after Lua has bound this exact app id to
    // the current NUI session. The opaque sandbox prevents same-origin parent access.
    const epoch = ++activeAppEpoch;
    byId('appbody').innerHTML =
      `<iframe class="appframe" id="appframe" sandbox="allow-scripts" ` +
      `title="${esc(L(a.label))}" aria-busy="true"></iframe>`;
    byId('appbody').style.padding = '0';
    byId('navbar').classList.add('hidden');
    const frame = byId('appframe');
    post('activeApp', { app: a.id, epoch }).then((r) => {
      if (epoch !== activeAppEpoch || openApp !== a || byId('appframe') !== frame) return;
      if (!r || !r.ok) {
        clearActiveApp();
        byId('navbar').classList.remove('hidden');
        byId('appbody').style.padding = '';
        body(UI.empty(L('ph.err_' + ((r && r.error) || 'x')), a.icon || 'dot'));
        return;
      }
      frame.setAttribute('aria-busy', 'false');
      frame.src = String(a.page || '');
    });
    return;
  }
  clearActiveApp();
  byId('appbody').style.padding = '';
  const fn = RENDER[a.id];
  if (fn) fn(); else body(UI.empty(L('ph.no_app')));
}

function closeApp(instant) {
  beginView();
  const app = byId('app');
  const wasOpen = app.classList.contains('on');
  resetTransientUI();
  clearActiveApp();
  clearAppVisualState();
  delete app.dataset.app;
  if (landscape) setLandscape(false);
  byId('screen').classList.remove('app-open');
  navBackAction = null;
  foot('');
  if (!wasOpen || instant) {
    app.classList.remove('on', 'closing');
    openApp = null; thread = null; threadGroup = null;
    clearSocialAccounts();
    return;
  }
  app.classList.remove('on');
  app.classList.add('closing');
  setTimeout(() => { app.classList.remove('closing'); }, 300);
  openApp = null; thread = null; threadGroup = null; clearSocialAccounts();
}

function setNav(title, backLabel, action, onBack) {
  navBackAction = typeof onBack === 'function' ? onBack : null;
  byId('navtitle').textContent = title || '';
  byId('navtitlesm').textContent = title || '';
  const backText = backLabel || L('ph.home');
  byId('navbacktxt').textContent = backText;
  byId('navback').setAttribute('aria-label', backText);
  const act = byId('navact');
  if (action) {
    act.classList.remove('hidden');
    act.className = 'navact' + (action.icon ? ' round' : '');
    act.innerHTML = action.icon ? svg(action.icon) : esc(action.label);
    act.setAttribute('aria-label', action.label || (action.icon === 'phone' ? L('ph.call') : title) || 'Action');
    act.onclick = action.onClick;
  } else {
    act.classList.add('hidden');
    act.onclick = null;
  }
  byId('navbar').classList.remove('collapsed');
}

const body = (html) => { byId('appbody').innerHTML = html; };
const foot = (html) => { byId('appfoot').innerHTML = html || ''; };
const loading = () => body(UI.empty(L('ph.loading')));
const rows = (sel, fn) => [...byId('appbody').querySelectorAll(sel)].forEach(fn);
const qrows = (root, sel, fn) => [...byId(root).querySelectorAll(sel)].forEach(fn);

// The iOS push: new content slides in from the right. A swap with no motion reads as a
// refresh rather than a step deeper.
const pushAnim = () => {
  const b = byId('appbody');
  b.classList.remove('pushin');
  void b.offsetWidth;
  b.classList.add('pushin');
};

// The large title collapses into the bar on scroll, as it does on iOS.
byId('appbody').addEventListener('scroll', (e) => {
  byId('navbar').classList.toggle('collapsed', e.target.scrollTop > 22);
});

// ══ Built-in apps ══════════════════════════════════════════════
const RENDER = new Proxy({}, {
  set(target, key, render) {
    target[key] = (...args) => {
      if (!openApp || openApp.id !== String(key)) return;
      beginView();
      return render(...args);
    };
    return true;
  },
});

// ── Phone ──────────────────────────────────────────────────────
const KEYS = [['1', ''], ['2', 'ABC'], ['3', 'DEF'], ['4', 'GHI'], ['5', 'JKL'], ['6', 'MNO'],
  ['7', 'PQRS'], ['8', 'TUV'], ['9', 'WXYZ'], ['*', ''], ['0', '+'], ['#', '']];

let phoneTab = 'keypad';

RENDER.phone = () => {
  tabbar([
    { id: 'favourites', icon: 'star', label: 'ph.favourites' },
    { id: 'recents', icon: 'phone', label: 'ph.recents' },
    { id: 'voicemail', icon: 'voicemail', label: 'ph.voicemail' },
    { id: 'contacts', icon: 'contacts', label: 'app.contacts' },
    { id: 'keypad', icon: 'keypad', label: 'ph.keypad_tab' },
  ], phoneTab, (t) => { phoneTab = t; RENDER.phone(); });

  if (phoneTab === 'voicemail') { renderVoicemail(); return; }

  if (phoneTab === 'recents') {
    body('<div id="recents">' + UI.empty(L('ph.loading'), 'phone') + '</div>');
    post('calls').then((r) => {
      const host = byId('recents');
      if (!host) return;
      const calls = (r && r.calls) || [];
      if (!calls.length) { host.innerHTML = UI.empty(L('ph.no_recents_call'), 'phone'); return; }
      host.innerHTML = UI.group(calls.map((c) => {
        const missed = c.direction === 'in' && !Number(c.answered);
        const dir = missed ? 'missed' : c.direction;
        const name = c.number ? nameOfNumber(c.number) : L('ph.unknown');
        return UI.row({
          icon: dir === 'out' ? 'callout' : (missed ? 'callmissed' : 'callin'),
          tint: missed ? '#FF453A' : '#34C759',
          title: name,
          subtitle: (L('ph.call_' + dir) + '  ') + String(c.at || '').slice(5, 16),
          value: c.number || '', chevron: true, data: { n: c.number || '' },
        });
      }));
      qrows('recents', '.row', (el) => el.addEventListener('click', () => {
        if (el.dataset.n) post('call', { number: el.dataset.n });
      }));
    });
    return;
  }

  if (phoneTab !== 'keypad') {
    // Favourites is the contacts the player marked, not a second address book.
    const list = (state.contacts || []).filter((c) => phoneTab === 'contacts' || Number(c.favourite) === 1);
    body(list.length
      ? UI.group(list.map((c) => UI.row({
          avatar: c.name, title: c.name, subtitle: c.number, chevron: true, data: { n: c.number },
        })))
      : UI.empty(L(phoneTab === 'contacts' ? 'ph.no_contacts' : 'ph.no_favourites'), 'contacts'));
    rows('.row[data-n]', (r) => r.addEventListener('click', () => post('call', { number: r.dataset.n })));
    return;
  }

  const known = (state.contacts || []).find((c) => c.number === dialed);
  body(
    `<div class="dialed" id="dialed">${esc(dialed)}</div>` +
    `<div class="dialsub" id="dialsub">${esc(known ? known.name : '')}</div>` +
    `<div class="keypad">${KEYS.map(([k, l]) =>
      `<button class="key" data-k="${k}" type="button"><b>${k}</b><i>${l}</i></button>`).join('')}</div>` +
    `<div class="dialrow">` +
      `<span class="dialspace"></span>` +
      `<button class="callbtn" id="dial" type="button">${svg('answer')}</button>` +
      `<button class="delbtn ${dialed ? '' : 'hidden'}" id="delkey" type="button">${svg('del')}</button>` +
    `</div>`
  );
  const paint = () => {
    byId('dialed').textContent = dialed;
    const c = (state.contacts || []).find((x) => x.number === dialed);
    byId('dialsub').textContent = c ? c.name : '';
    byId('delkey').classList.toggle('hidden', !dialed);
  };
  rows('.key', (b) => b.addEventListener('click', () => {
    dialed = (dialed + b.dataset.k).slice(0, 20); paint();
  }));
  byId('delkey').addEventListener('click', () => { dialed = dialed.slice(0, -1); paint(); });
  byId('dial').addEventListener('click', () => { if (dialed) post('call', { number: dialed }); });
};

// ── Health record ──────────────────────────────────────────────
// The half of a Health app the game cannot work out for itself: blood type, allergies,
// what you are on, who to call. It rides on the character, so it survives the handset.
function healthRecord() {
  if (!openApp || openApp.id !== 'health') return;
  beginView();
  setNav(L('app.health'), L('app.health'), null, () => {
    healthTab = 'today';
    RENDER.health();
  });
  loading();
  post('health', { op: 'get' }).then((d) => {
    const r = (d && d.record) || {};
    body(
      UI.hero({
        appicon: 'health',
        eyebrow: L('ph.steps'),
        value: String(r.steps || 0),
        subtitle: L('ph.steps_today'),
      }) +
      UI.field('hblood', L('ph.blood'), r.blood || '', 'maxlength="6"') +
      UI.field('hallerg', L('ph.allergies'), r.allergies || '', 'maxlength="300"') +
      UI.field('hcond', L('ph.conditions'), r.conditions || '', 'maxlength="300"') +
      UI.field('hmeds', L('ph.meds'), r.meds || '', 'maxlength="300"') +
      UI.field('hice', L('ph.ice'), r.ice || '', 'maxlength="60"') +
      UI.group([UI.row({ icon: 'heart', tint: '#FF2D55', title: L('ph.donor'),
        toggle: r.donor === true, data: { t: 'donor' } })]) +
      UI.button(L('ph.save'), 'hsave', 'tinted') +
      '<div class="groupfoot">' + esc(L('ph.health_hint')) + '</div>'
    );
    let donor = r.donor === true;
    rows('.row', (el) => el.addEventListener('click', () => {
      donor = !donor;
      el.querySelector('.sw').classList.toggle('on', donor);
      el.setAttribute('aria-checked', donor ? 'true' : 'false');
    }));
    byId('hsave').addEventListener('click', async () => {
      const res = await post('health', { op: 'set', blood: byId('hblood').value,
        allergies: byId('hallerg').value, conditions: byId('hcond').value,
        meds: byId('hmeds').value, ice: byId('hice').value, donor });
      toast(res && res.ok ? L('ph.saved') : L('ph.err_x'));
    });
  });
}

// ── Notes ──────────────────────────────────────────────────────
// Part of the phone rather than a sample resource: notes are the one thing people expect
// to survive everything else, so they live with the phone's own data.
RENDER.notes = async () => {
  setNav(L('app.notes'), null, { icon: 'add', onClick: () => noteEdit({}) });
  loading();
  const d = await post('notes', { op: 'list' });
  const list = (d && d.notes) || [];
  if (!list.length) { body(UI.empty(L('ph.no_notes'), 'note')); return; }
  body(UI.group(list.map((n) => UI.row({
    icon: 'note', tint: '#FFCC00', title: n.title || L('ph.untitled'),
    subtitle: String(n.at || '').slice(5, 16), chevron: true, data: { id: n.id },
  }))));
  rows('.row', (el) => el.addEventListener('click', () => {
    const n = list.find((x) => String(x.id) === el.dataset.id);
    if (n) noteEdit(n);
  }));
};

function noteEdit(n) {
  if (!openApp || openApp.id !== 'notes') return;
  beginView();
  setNav(n.id ? (n.title || L('ph.untitled')) : L('ph.note_new'), L('app.notes'), null,
    () => RENDER.notes());
  body(
    UI.field('ntitle', L('ph.note_title'), n.title || '', 'maxlength="80"') +
    '<textarea class="mailedit" id="nbody" maxlength="4000" placeholder="' + esc(L('ph.note_body')) + '">' +
      esc(n.body || '') + '</textarea>' +
    UI.button(L('ph.save'), 'nsave', 'tinted') +
    (n.id ? UI.button(L('ph.delete'), 'ndel', 'destructive') : '')
  );
  byId('nsave').addEventListener('click', async () => {
    const r = await post('notes', { op: 'save', id: n.id, title: byId('ntitle').value, body: byId('nbody').value });
    if (r && r.ok) { toast(L('ph.saved')); RENDER.notes(); }
    else toast(L('ph.err_' + ((r && r.error) || 'x')));
  });
  const del = byId('ndel');
  if (del) del.addEventListener('click', async () => {
    await post('notes', { op: 'del', id: n.id });
    toast(L('ph.deleted')); RENDER.notes();
  });
}

// ── Mail ───────────────────────────────────────────────────────
// A mail client, not a second Messages: an address you own, folders, group recipients,
// drafts you can come back to, replies that quote who they answer, and a keep flag that
// works from any folder.
let mailFolder = 'inbox';
let mailAcc = null;

RENDER.mail = async () => {
  setNav(L('app.mail'), null);
  loading();
  const me = await post('mail', { op: 'me' });
  if (!me || me.error) { body(UI.empty(L('ph.err_' + ((me && me.error) || 'off')), 'mail')); return; }
  if (!me.address) { mailSignup(me.domains || []); return; }
  mailAcc = me.address;
  mailList();
};

// The address is chosen once and is what people write to, which is why it cannot be
// edited away afterwards.
function mailSignup(domains) {
  if (!openApp || openApp.id !== 'mail') return;
  setNav(L('app.mail'), null);
  let domain = domains[0] || 'eyefind.info';
  body(
    '<div class="accthead">' + UI.appIcon('mail') +
      '<div class="acctname">' + esc(L('app.mail')) + '</div>' +
      '<div class="acctsub">' + esc(L('ph.mail_pick_sub')) + '</div></div>' +
    UI.field('mlocal', L('ph.mail_localpart'), '', 'maxlength="20"') +
    '<div class="seg scroll" id="mdoms">' + domains.map((d, i) =>
      '<button class="' + (i === 0 ? 'on' : '') + '" data-d="' + esc(d) + '" type="button">@' + esc(d) + '</button>').join('') + '</div>' +
    UI.button(L('ph.mail_create'), 'mmake', 'tinted') +
    '<div class="groupfoot">' + esc(L('ph.mail_pick_hint')) + '</div>'
  );
  qrows('mdoms', 'button', (b) => b.addEventListener('click', () => {
    domain = b.dataset.d;
    [...byId('mdoms').querySelectorAll('button')].forEach((x) => x.classList.toggle('on', x === b));
  }));
  byId('mmake').addEventListener('click', async () => {
    const r = await post('mail', { op: 'create', localpart: byId('mlocal').value.trim(), domain });
    if (r && r.ok) { mailAcc = r.address; toast(L('ph.mail_made')); mailList(); }
    else toast(L('ph.err_' + ((r && r.error) || 'x')));
  });
}

const MAIL_TABS = [
  { id: 'inbox', icon: 'mail', label: 'ph.mail_inbox' },
  { id: 'sent', icon: 'send', label: 'ph.mail_sent' },
  { id: 'draft', icon: 'note', label: 'ph.mail_drafts' },
  { id: 'saved', icon: 'star', label: 'ph.mail_saved' },
];

async function mailList() {
  if (!openApp || openApp.id !== 'mail') return;
  beginView();
  setNav(L('app.mail'), null, { icon: 'add', onClick: () => mailCompose({}) });
  tabbar(MAIL_TABS, mailFolder, (t) => { mailFolder = t; mailList(); });
  body('<div class="mailaddr">' + esc(mailAcc || '') + '</div><div id="mlist"></div>');

  const r = mailFolder === 'saved'
    ? await post('mail', { op: 'saved' })
    : await post('mail', { op: 'list', folder: mailFolder });
  const host = byId('mlist');
  if (!host) return;
  const list = (r && r.mail) || [];
  if (!list.length) { host.innerHTML = UI.empty(L('ph.mail_empty'), 'mail'); return; }

  host.innerHTML = UI.group(list.map((m) => {
    // Inbox shows who wrote; everywhere else, who it went to.
    const who = (m.folder === 'inbox') ? m.from_addr : (m.to_addr || L('ph.mail_noto'));
    return UI.row({
      avatar: who, title: who,
      subtitle: (m.subject || L('ph.mail_nosubject')) + '  -  ' + String(m.at || '').slice(5, 16),
      badge: (m.folder === 'inbox' && !Number(m.seen)) ? L('ph.vm_new_short') : undefined,
      value: Number(m.saved) ? '\u2605' : '',
      chevron: true, data: { b: m.box_id },
    });
  }));
  qrows('mlist', '.row', (el) => el.addEventListener('click', () => {
    const m = list.find((x) => String(x.box_id) === el.dataset.b);
    if (m) mailRead(m);
  }));
}

function mailRead(m) {
  if (!openApp || openApp.id !== 'mail') return;
  beginView();
  // A draft is not something you read; it is something you carry on writing.
  if (m.folder === 'draft') { mailCompose({ draft: m }); return; }
  if (m.folder === 'inbox' && !Number(m.seen)) post('mail', { op: 'seen', boxId: m.box_id });

  setNav(m.subject || L('ph.mail_nosubject'), L('app.mail'), {
    icon: 'star', onClick: async () => {
      const saved = !Number(m.saved);
      await post('mail', { op: 'save', boxId: m.box_id, saved });
      m.saved = saved ? 1 : 0;
      toast(L(saved ? 'ph.mail_kept' : 'ph.mail_unkept'));
    },
  }, () => mailList());
  body(
    '<div class="mailhead">' +
      '<div class="mailsubj">' + esc(m.subject || L('ph.mail_nosubject')) + '</div>' +
      '<div class="mailmeta"><b>' + esc(m.from_addr) + '</b></div>' +
      '<div class="mailmeta">' + esc(L('ph.mail_to')) + ' ' + esc(m.to_addr || '') + '</div>' +
      '<div class="mailmeta">' + esc(String(m.at || '').slice(0, 16)) + '</div>' +
    '</div>' +
    '<div class="mailbody">' + esc(m.body || '') + '</div>' +
    UI.button(L('ph.mail_reply'), 'mreply', 'tinted') +
    UI.button(L('ph.mail_forward'), 'mfwd', 'plain') +
    ((m.to_addr || '').indexOf(',') !== -1 ? UI.button(L('ph.mail_reply_all'), 'mreplyall', 'plain') : '') +
    UI.button(L('ph.delete'), 'mdel', 'destructive')
  );
  byId('mreply').addEventListener('click', () => mailCompose({ reply: m, all: false }));
  // Forward keeps the message and clears the recipients: the point is to send it on.
  byId('mfwd').addEventListener('click', () => mailCompose({ forward: m }));
  const ra = byId('mreplyall');
  if (ra) ra.addEventListener('click', () => mailCompose({ reply: m, all: true }));
  byId('mdel').addEventListener('click', async () => {
    await post('mail', { op: 'del', boxId: m.box_id });
    toast(L('ph.mail_deleted')); mailList();
  });
}

// One composer for a new mail, a reply, a reply-all and an unfinished draft.
function mailCompose(o) {
  if (!openApp || openApp.id !== 'mail') return;
  beginView();
  o = o || {};
  const d = o.draft, r = o.reply;
  let to = '', subject = '', bodyTxt = '', replyTo = 0, boxId = 0;

  if (d) {
    to = d.to_addr || ''; subject = d.subject || ''; bodyTxt = d.body || '';
    replyTo = Number(d.reply_to || 0); boxId = Number(d.box_id || 0);
  } else if (o.forward) {
    const f = o.forward;
    subject = /^(fwd|tr):/i.test(f.subject || '') ? f.subject : ('Fwd: ' + (f.subject || ''));
    bodyTxt = '\n\n--- ' + (f.from_addr || '') + ' ---\n' + (f.body || '');
  } else if (r) {
    // Reply goes to the writer; reply-all adds everyone it was addressed to but you.
    const others = o.all
      ? (r.to_addr || '').split(',').map((x) => x.trim()).filter((x) => x && x !== mailAcc)
      : [];
    to = [r.from_addr].concat(others).filter(Boolean).join(', ');
    subject = /^re:/i.test(r.subject || '') ? r.subject : ('Re: ' + (r.subject || ''));
    bodyTxt = '\n\n--- ' + (r.from_addr || '') + ' ---\n' + (r.body || '');
    replyTo = Number(r.mail_id || 0);
  }

  setNav(L('ph.mail_new'), L('app.mail'), null, () => mailList());
  body(
    UI.field('mto', L('ph.mail_to_ph'), to, 'maxlength="400"') +
    UI.field('msubj', L('ph.mail_subject'), subject, 'maxlength="80"') +
    '<textarea class="mailedit" id="mbody" maxlength="2000" placeholder="' + esc(L('ph.mail_body_ph')) + '">' + esc(bodyTxt) + '</textarea>' +
    UI.button(L('ph.mail_send'), 'msend', 'tinted') +
    UI.button(L('ph.mail_savedraft'), 'msave', 'plain') +
    '<div class="groupfoot">' + esc(L('ph.mail_group_hint')) + '</div>'
  );

  const payload = (op) => ({ op, to: byId('mto').value, subject: byId('msubj').value,
    body: byId('mbody').value, replyTo, boxId });

  byId('msend').addEventListener('click', async () => {
    const res = await post('mail', payload('send'));
    if (res && res.ok) { toast(L('ph.mail_sent')); mailFolder = 'sent'; mailList(); }
    else if (res && res.error === 'noaddr') toast(L('ph.err_noaddr') + ' ' + (res.address || ''));
    else toast(L('ph.err_' + ((res && res.error) || 'x')));
  });
  byId('msave').addEventListener('click', async () => {
    const res = await post('mail', payload('draft'));
    if (res && res.ok) { toast(L('ph.mail_drafted')); mailFolder = 'draft'; mailList(); }
    else toast(L('ph.err_' + ((res && res.error) || 'x')));
  });
}

// ── Photos: filters, albums, and a picker every app can raise ──
// A filter is a stored name drawn with CSS, never a re-encoded image: the phone holds a
// link and how to draw it, which is the only thing it can honestly hold.
const FILTERS = ['none', 'mono', 'noir', 'fade', 'warm', 'cool', 'vivid'];
function filterCss(f) {
  return ({
    mono:  'grayscale(1)',
    noir:  'grayscale(1) contrast(1.5) brightness(.9)',
    fade:  'saturate(.7) contrast(.88) brightness(1.08)',
    warm:  'sepia(.35) saturate(1.25) hue-rotate(-12deg)',
    cool:  'saturate(1.1) hue-rotate(14deg) brightness(1.03)',
    vivid: 'saturate(1.6) contrast(1.12)',
  })[f] || 'none';
}

// Photos arrive as rows now; older saves were bare strings.
function photoRow(v) { return (typeof v === 'string') ? { url: v, album: '', filter: '' } : (v || {}); }
function inlineBackground(url) {
  const clean = Array.from(String(url || '')).filter((char) => {
    const code = char.charCodeAt(0);
    return code >= 32 && code !== 127;
  }).join('');
  const safe = clean
    .replace(/\\/g, '\\\\')
    .replace(/"/g, '\\"');
  return 'background-image:url(&quot;' + esc(safe) + '&quot;)';
}
function photoStyle(v) {
  const r = photoRow(v);
  return inlineBackground(r.url) + ';filter:' + filterCss(r.filter);
}

// The shared picker: any composer can ask for a photo from the phone rather than making
// the player paste a link they do not have.
function pickPhoto(onPick) {
  const host = byId('sheet');
  const sourceOpen = host.classList.contains('on');
  const sourceNode = host.firstChild;
  post('photos', { op: 'list' }).then((d) => {
    if (sourceOpen
      ? (!host.classList.contains('on') || host.firstChild !== sourceNode)
      : host.classList.contains('on')) return;
    const shots = (d && d.photos) || [];
    if (!shots.length) { toast(L('ph.no_photos')); return; }
    // A picker may be raised from a composer sheet. Detach that sheet instead of
    // destroying it, so its fields and listeners are intact when a photo is chosen.
    const restore = host.classList.contains('on') ? document.createDocumentFragment() : null;
    if (restore) while (host.firstChild) restore.appendChild(host.firstChild);
    const restoreComposer = restore ? () => {
      sheetReturn = null;
      emojiClose();
      host.replaceChildren(restore);
      host.classList.add('on');
      byId('scrim').classList.add('on');
    } : null;
    sheet(L('ph.pick_photo'),
      '<div class="shots">' + shots.map((v, i) =>
        '<div class="shot" data-i="' + i + '" style="' + photoStyle(v) + '"></div>').join('') + '</div>',
      () => [...byId('sheet').querySelectorAll('.shot')].forEach((el) => el.addEventListener('click', () => {
        const r = photoRow(shots[Number(el.dataset.i)]);
        if (restoreComposer) restoreComposer();
        else closeSheet();
        onPick(r.url, r);
      })));
    sheetReturn = restoreComposer;
  });
}

// Forwarding a message: the same text, sent on to somebody else. Picked from contacts,
// or typed, because the person you want may not be in the book.
function forwardSms(m) {
  const all = state.contacts || [];
  sheet(L('ph.forward'),
    '<div class="mailbody">' + esc(m.body || L('ph.attach')) + '</div>' +
    UI.field('fwdnum', L('ph.number'), '', 'maxlength="20"') +
    UI.button(L('ph.send'), 'fwdgo', 'tinted') +
    (all.length ? UI.group(all.map((c) => UI.row({
      avatar: c.name, title: c.name, subtitle: c.number, data: { n: c.number },
    })), { header: L('app.contacts') }) : ''),
    () => {
      const go = async (number) => {
        if (!number) return;
        const r = await post('send', { number, body: m.body || '', kind: m.kind || 'text',
                                       attachment: m.attachment || '' });
        closeSheet();
        toast(r && r.ok ? L('ph.forwarded') : L('ph.err_' + ((r && r.error) || 'x')));
      };
      byId('fwdgo').addEventListener('click', () => go(byId('fwdnum').value.trim()));
      [...byId('sheet').querySelectorAll('.row')].forEach((el) =>
        el.addEventListener('click', () => go(el.dataset.n)));
    });
}

// ── Voicemail ──────────────────────────────────────────────────
// A missed call leaves a written message rather than a recording: nothing here can hold
// audio, and a note you can actually read beats a fake tape.
function renderVoicemail() {
  if (!openApp || openApp.id !== 'phone' || phoneTab !== 'voicemail') return;
  beginView();
  body('<div id="vmlist">' + UI.empty(L('ph.loading'), 'phone') + '</div>');
  post('voicemail', { op: 'list' }).then((r) => {
    const host = byId('vmlist');
    if (!host) return;
    const list = (r && r.voicemail) || [];
    if (!list.length) { host.innerHTML = UI.empty(L('ph.no_voicemail'), 'phone'); return; }
    host.innerHTML = UI.group(list.map((v) => UI.row({
      icon: 'voicemail', tint: Number(v.seen) ? '#8E8E93' : '#0A84FF',
      title: v.number ? nameOfNumber(v.number) : L('ph.unknown'),
      subtitle: String(v.at || '').slice(5, 16),
      badge: Number(v.seen) ? undefined : L('ph.vm_new_short'),
      chevron: true, data: { id: v.id },
    })));
    qrows('vmlist', '.row', (el) => el.addEventListener('click', () => {
      const v = list.find((x) => String(x.id) === el.dataset.id);
      if (v) voicemailSheet(v);
    }));
    // Opening the list is hearing them: the unread mark is gone from here on.
    if (list.some((v) => !Number(v.seen))) {
      post('voicemail', { op: 'seen' }).then(() => { state.vmUnread = 0; });
    }
  });
}

function voicemailSheet(v) {
  const who = v.number ? nameOfNumber(v.number) : L('ph.unknown');
  sheet(who,
    '<div class="vmbody">' + esc(v.body || '') + '</div>' +
    '<div class="vmwhen">' + esc(String(v.at || '').slice(0, 16)) + '</div>' +
    (v.number ? UI.button(L('ph.call'), 'vmcall', 'tinted') : '') +
    UI.button(L('ph.delete'), 'vmdel', 'destructive'),
    () => {
      const c = byId('vmcall');
      if (c) c.addEventListener('click', () => { closeSheet(); post('call', { number: v.number }); });
      byId('vmdel').addEventListener('click', async () => {
        await post('voicemail', { op: 'del', id: v.id });
        closeSheet(); renderVoicemail();
      });
    });
}

// Offered to the CALLER when nobody picked up.
function voicemailOffer(number) {
  sheet(L('ph.vm_leave'),
    '<div class="groupfoot">' + esc(L('ph.vm_leave_hint')) + ' ' + esc(nameOfNumber(number)) + '</div>' +
    UI.field('vmtext', L('ph.vm_placeholder'), '', 'maxlength="200"') +
    UI.button(L('ph.vm_send'), 'vmgo', 'tinted'),
    () => byId('vmgo').addEventListener('click', async () => {
      const txt = byId('vmtext').value.trim();
      if (!txt) return;
      closeSheet();
      const r = await post('voicemail', { op: 'leave', number, body: txt });
      toast(r && r.ok ? L('ph.vm_sent') : L('ph.err_' + ((r && r.error) || 'x')));
    }));
}

// ── Messages ───────────────────────────────────────────────────
function nameOfNumber(number) {
  const c = (state.contacts || []).find((x) => x.number === number);
  return c ? c.name : (number || L('ph.unknown'));
}

RENDER.messages = () => {
  threadGroup = null;
  setNav(L('app.messages'), null, { icon: 'add', onClick: newMessageSheet });
  const list = state.conversations || [];
  const groups = state.groups || [];
  if (!list.length && !groups.length) { body(UI.empty(L('ph.no_messages'), 'messages')); return; }
  body(
    (groups.length ? UI.group(groups.map((g) => UI.row({
      icon: 'contacts', tint: '#34C759', title: g.name, chevron: true, data: { g: g.id, gn: g.name },
    })), { header: L('ph.groups') }) : '') +
    (list.length ? UI.group(list.map((c) => UI.row({
      avatar: nameOfNumber(c.number), title: nameOfNumber(c.number), subtitle: c.body,
      badge: c.unread > 0 ? c.unread : null, chevron: true, data: { n: c.number },
    }))) : '')
  );
  rows('.row[data-n]', (r) => r.addEventListener('click', () => openThread(r.dataset.n)));
  rows('.row[data-g]', (r) => r.addEventListener('click', () =>
    openGroup(Number(r.dataset.g), r.dataset.gn)));
};

async function openGroup(id, name) {
  if (!openApp || openApp.id !== 'messages') return;
  beginView();
  thread = null;
  threadGroup = { id, name };
  setNav(name, L('app.messages'), null, () => {
    threadGroup = null;
    foot('');
    RENDER.messages();
  });
  loading();
  const res = await post('conversation', { group: id });
  if (!res || res.error) { body(UI.empty(L('ph.err_' + ((res && res.error) || 'x')))); return; }
  paintThread(res.messages || []);
}

async function openThread(number) {
  if (!openApp || openApp.id !== 'messages') return;
  beginView();
  thread = number;
  threadGroup = null;
  setNav(nameOfNumber(number), L('app.messages'), {
    icon: 'phone', onClick: () => post('call', { number }),
  }, () => {
    thread = null;
    foot('');
    RENDER.messages();
  });
  loading();
  const res = await post('conversation', { number });
  if (!res || res.error) { body(UI.empty(L('ph.err_' + ((res && res.error) || 'x')))); return; }
  paintThread(res.messages || []);
  pushAnim();
  const c = (state.conversations || []).find((x) => x.number === number);
  if (c) c.unread = 0;
}

function bubbleHtml(m) {
  let inner;
  if (m.kind === 'image') {
    inner = '<img class="mimg" src="' + esc(m.attachment) + '" />' +
      (m.body ? '<div class="mcap">' + esc(m.body) + '</div>' : '');
  } else if (m.kind === 'location') {
    // A shared position opens in Maps, which here means: it sets your waypoint.
    inner = '<button class="locbtn" type="button" data-loc="' + esc(m.attachment) + '">' +
      svg('map') + esc(L('ph.msg_location')) + '</button>';
  } else {
    inner = esc(m.body);
  }
  const sender = (!m.mine && threadGroup && m.from)
    ? '<div class="gsender">' + esc(nameOfNumber(m.from)) + '</div>' : '';
  return sender + '<div class="bub ' + (m.mine ? 'me' : 'them') +
    (m.kind === 'image' ? ' imgb' : '') + '">' + inner + '</div>';
}

function wireLocButtons() {
  rows('.locbtn', (b) => b.addEventListener('click', async () => {
    const parts = String(b.dataset.loc || '').split(';');
    const r = await post('waypoint', { x: Number(parts[0]), y: Number(parts[1]) });
    if (r && r.ok) toast(L('ph.waypoint_set'));
  }));
}

function paintThread(messages) {
  body(`<div class="thread" id="thread">${messages.map(bubbleHtml).join('')}</div>`);
  wireLocButtons();
  // A message you can act on: forwarding is the one thing people always want from one.
  [...byId('thread').querySelectorAll('.bub')].forEach((b, i) => {
    b.addEventListener('click', (e) => {
      if (e.target.closest('button') || e.target.closest('.locbtn')) return;
      const m = messages[i];
      if (m) forwardSms(m);
    });
  });
  foot(`<div class="compose">` +
    `<button class="attach" id="attach" type="button">+</button>` +
    `<button class="emoji" id="msgemoji" type="button">😊</button>` +
    UI.field('msg', L('ph.write'), '', 'maxlength="250"') +
    `<button class="sendbtn" id="sendmsg" type="button">${svg('send')}</button></div>`);
  byId('attach').addEventListener('click', () => attachSheet());
  byId('msgemoji').addEventListener('click', () => emojiOpen('msg'));
  byId('msg').addEventListener('focus', emojiClose);
  const el = byId('thread');
  el.scrollTop = el.scrollHeight;
  byId('appbody').scrollTop = byId('appbody').scrollHeight;

  const target = () => threadGroup ? { group: threadGroup.id } : { number: thread };
  const send = async () => {
    const input = byId('msg');
    const text = input.value.trim();
    if (!text) return;
    input.value = '';
    const res = await post('send', Object.assign({ body: text }, target()));
    if (res && res.ok) {
      el.insertAdjacentHTML('beforeend', bubbleHtml({ mine: true, body: res.body, kind: res.kind, attachment: res.attachment }));
      byId('appbody').scrollTop = byId('appbody').scrollHeight;
    } else {
      toast(L('ph.err_' + ((res && res.error) || 'x')));
    }
  };

  // Anything that is not typed: a photo from the gallery, an image or GIF by link, or
  // where you are standing. All of it lands as a message like any other.
  window.attachSheet = () => {
    const shots = state.photos || [];
    sheet(L('ph.attach'),
      (shots.length
        ? '<div class="grouphead">' + esc(L('ph.attach_photo')) + '</div>' +
          '<div class="shots" style="margin-bottom:12px">' + shots.map((v, i) =>
            '<div class="shot" data-i="' + i + '" style="' + photoStyle(v) + '"></div>').join('') + '</div>'
        : '') +
      UI.button(L('ph.pick_photo'), 'atpick', 'plain') +
      UI.field('aturl', L('ph.attach_url'), '', 'maxlength="300"') +
      UI.button(L('ph.attach_send'), 'atgo') +
      UI.button(L('ph.attach_loc'), 'atloc', 'plain'),
      () => {
        const sendMedia = async (payload) => {
          const res = await post('send', Object.assign(payload, target()));
          closeSheet();
          if (res && res.ok) {
            el.insertAdjacentHTML('beforeend', bubbleHtml({ mine: true, body: res.body, kind: res.kind, attachment: res.attachment }));
            wireLocButtons();
            byId('appbody').scrollTop = byId('appbody').scrollHeight;
          } else toast(L('ph.err_' + ((res && res.error) || 'x')));
        };
        [...byId('sheet').querySelectorAll('.shot')].forEach((sh) =>
          sh.addEventListener('click', () => sendMedia({
            kind: 'image', attachment: photoRow(shots[Number(sh.dataset.i)]).url, body: '',
          })));
        byId('atpick').addEventListener('click', () =>
          pickPhoto((url) => sendMedia({ body: '', kind: 'image', attachment: url })));
        byId('atgo').addEventListener('click', () => {
          const u = byId('aturl').value.trim();
          if (u) sendMedia({ kind: 'image', attachment: u, body: '' });
        });
        byId('atloc').addEventListener('click', async () => {
          const res = await post('sendloc', target());
          closeSheet();
          if (res && res.ok) {
            el.insertAdjacentHTML('beforeend', bubbleHtml({ mine: true, kind: 'location', attachment: res.attachment || '0;0', body: '' }));
            wireLocButtons();
            byId('appbody').scrollTop = byId('appbody').scrollHeight;
          } else toast(L('ph.err_' + ((res && res.error) || 'x')));
        });
      });
  };
  byId('sendmsg').addEventListener('click', send);
  byId('msg').addEventListener('keydown', (e) => { if (e.key === 'Enter') send(); });
}

function newMessageSheet() {
  sheet(L('ph.new_message_to'),
    UI.field('nmnum', L('ph.number')) + UI.button(L('ph.write'), 'nmgo') +
    UI.button(L('ph.new_group'), 'nggo', 'plain'),
    () => {
      byId('nmgo').addEventListener('click', () => {
        const n = byId('nmnum').value.trim();
        closeSheet();
        if (n) openThread(n);
      });
      byId('nggo').addEventListener('click', newGroupSheet);
    });
}

// A group is a name and some contacts. Every number must be somebody real - the server
// refuses ghosts - and you are a member by construction.
function newGroupSheet() {
  const contacts = state.contacts || [];
  sheet(L('ph.new_group'),
    UI.field('gname', L('ph.group_name'), '', 'maxlength="40"') +
    (contacts.length
      ? contacts.map((c) => '<label class="gpick"><input type="checkbox" value="' + esc(c.number) + '" />' +
          esc(c.name) + '</label>').join('')
      : UI.empty(L('ph.no_contacts'))) +
    UI.button(L('ph.group_make'), 'ggo'),
    () => byId('ggo').addEventListener('click', async () => {
      const numbers = [...byId('sheet').querySelectorAll('input:checked')].map((i) => i.value);
      const r = await post('groupCreate', { name: byId('gname').value.trim(), numbers });
      closeSheet();
      if (r && r.ok) { await refresh(); RENDER.messages(); openGroup(r.id, r.name); }
      else toast(L('ph.err_' + ((r && r.error) || 'x')));
    }));
}

// ── Contacts ───────────────────────────────────────────────────
RENDER.contacts = () => {
  setNav(L('app.contacts'), null, { icon: 'add', onClick: () => contactSheet({}) });
  const all = state.contacts || [];
  const draw = (q) => {
    const list = q ? all.filter((c) => (c.name + ' ' + c.number).toLowerCase().includes(q)) : all;
    byId('clist').innerHTML = list.length
      ? UI.group(list.map((c) => UI.row({
          avatar: c.name, title: c.name, subtitle: c.number, chevron: true,
          data: { id: c.id, n: c.number },
        })))
      : UI.empty(L('ph.no_contacts'), 'contacts');
    wire();
  };
  const wire = () => rows('.row', (r) => r.addEventListener('click', () => {
    const c = (state.contacts || []).find((x) => String(x.id) === r.dataset.id);
    if (c) contactSheet(c);
  }));
  body(searchHtml(L('ph.search_contacts')) +
    UI.group([UI.row({ icon: 'airdrop', tint: '#0A84FF', title: L('ph.share_my_number'),
      subtitle: state.number || '', chevron: true, data: { me: '1' } })]) +
    '<div id="clist"></div>');
  rows('.row', (r) => { if (r.dataset.me) r.addEventListener('click',
    () => airdropShare('number', { name: '', number: state.number })); });
  draw('');
  onSearch(draw);
};

function contactSheet(c) {
  const isNew = !c.id;
  sheet(isNew ? L('ph.new_contact') : c.name,
    // The card, not just a name and a number: a face, a way to write, where they are,
    // when it is their birthday, and whatever you needed to remember about them.
    (c.photo ? '<div class="cardphoto" style="' + inlineBackground(c.photo) + '"></div>' : '') +
    UI.field('cname', L('ph.name'), c.name, 'maxlength="40"') +
    UI.field('cnum', L('ph.number'), c.number, 'maxlength="20"') +
    UI.field('cphoto', L('ph.c_photo'), c.photo || '', 'maxlength="400"') +
    UI.field('cmail', L('ph.c_email'), c.email || '', 'maxlength="64"') +
    UI.field('caddr', L('ph.c_address'), c.address || '', 'maxlength="120"') +
    UI.field('cbday', L('ph.c_birthday'), c.birthday || '', 'maxlength="20"') +
    UI.field('cnote', L('ph.c_note'), c.note || '', 'maxlength="300"') +
    UI.button(L('ph.pick_photo'), 'cpick', 'plain') +
    UI.button(L('ph.save'), 'csave') +
    (isNew ? '' : UI.button(L('ph.call'), 'ccall', 'tinted')) +
    (isNew ? '' : UI.button(L('ph.message'), 'cmsg', 'plain')) +
    (isNew ? '' : UI.button(L('ph.airdrop_share'), 'cshare', 'plain')) +
    (isNew ? '' : UI.button(L('ph.delete'), 'cdel', 'destructive')),
    () => {
      byId('cpick').addEventListener('click', () => pickPhoto((url) => { byId('cphoto').value = url; }));
      byId('csave').addEventListener('click', async () => {
        const res = await post('contactSave', { id: c.id, name: byId('cname').value, number: byId('cnum').value,
          photo: byId('cphoto').value.trim(), email: byId('cmail').value.trim(),
          address: byId('caddr').value.trim(), birthday: byId('cbday').value.trim(),
          note: byId('cnote').value.trim() });
        if (res && res.ok) { closeSheet(); await refresh(); RENDER.contacts(); }
        else toast(L('ph.err_' + ((res && res.error) || 'x')));
      });
      if (isNew) return;
      byId('ccall').addEventListener('click', () => { closeSheet(); post('call', { number: c.number }); });
      byId('cshare').addEventListener('click', () => airdropShare('contact', { name: c.name, number: c.number }));
      byId('cmsg').addEventListener('click', () => { closeSheet(); openThread(c.number); });
      byId('cdel').addEventListener('click', async () => {
        await post('contactDelete', { id: c.id });
        closeSheet(); await refresh(); RENDER.contacts();
      });
    });
}

// ── Bank ───────────────────────────────────────────────────────
RENDER.bank = async () => {
  loading();
  const d = await post('app', { app: 'bank' });
  if (!d || d.error) { body(UI.empty(L('ph.err_off'), 'bank')); return; }
  const tx = d.transactions || [];
  body(
    UI.hero({
      appicon: 'bank',
      eyebrow: L('ph.balance'),
      value: money(d.bank),
      subtitle: `${L('ph.cash')} ${money(d.cash)}`,
    }) +
    (tx.length
      ? UI.group(tx.map((t) => UI.row({
          title: t.label || t.type || '', subtitle: t.at || '',
          value: money(t.amount), mono: true, tone: Number(t.amount) < 0 ? 'neg' : 'pos',
        })), { header: L('ph.history') })
      : UI.empty(L('ph.no_history')))
  );
};

// ── Garage ─────────────────────────────────────────────────────
// Where a car is, not how to spawn one: taking it out is the garage's job and needs the
// player standing at one.
RENDER.garage = async () => {
  loading();
  const d = await post('app', { app: 'garage' });
  if (!d || d.error) { body(UI.empty(L('ph.err_off'), 'garage')); return; }
  const list = Array.isArray(d) ? d : (d.vehicles || []);
  if (!list.length) { body(UI.empty(L('ph.no_vehicles'), 'garage')); return; }
  body(UI.group(list.map((v) => UI.row({
    icon: 'garage', tint: '#0A84FF', title: v.model || '', subtitle: `${v.plate || ''}  ${v.garage || L('ph.out')}`,
    value: v.live ? L('ph.veh_out') : L('ph.veh_stored'),
  }))));
};

// ── Wallet ─────────────────────────────────────────────────────
RENDER.wallet = async () => {
  loading();
  // The card is v-banking's, not the phone's: it mints the number and it is the thing
  // one player hands another instead of a citizen id.
  const card = await post('card');
  const d = await post('app', { app: 'wallet' });
  if (!d || d.error) { body(UI.empty(L('ph.err_off'), 'wallet')); return; }
  const list = Array.isArray(d) ? d : (d.licenses || []);
  // No card until one has been ordered from the bank, so say where to get one rather
  // than drawing an empty rectangle.
  const cardHtml = (card && card.ok && card.card)
    ? '<div class="bankcard"><div class="brand"><span>FLEECA</span><span class="chip"></span></div>' +
      '<div class="num">' + esc(card.card || '') + '</div>' +
      '<div class="foot"><span>' + esc(card.holder || '') + '</span>' +
      '<span class="bal">' + esc(money(card.bank)) + '</span></div></div>'
    : (card && card.ok ? UI.group([UI.row({ icon: 'bank', title: L('ph.no_card'), subtitle: L('ph.no_card_hint') })]) : '');
  if (!list.length) { body(cardHtml + UI.empty(L('ph.no_licenses'), 'wallet')); return; }
  const wireCard = () => {
    const el = document.querySelector('.bankcard');
    if (el && card && card.card) {
      el.style.cursor = 'pointer';
      el.addEventListener('click', () => copyText(card.card, L('ph.card_copied')));
    }
  };
  body(cardHtml + UI.group(list.map((l) => UI.row({
    icon: 'wallet', tint: '#5856D6', title: (L(l.i18n) !== l.i18n ? L(l.i18n) : (l.label || l.key)),
    subtitle: l.issuer || '', value: l.held ? L('ph.lic_held') : L('ph.lic_none'),
    tone: l.held ? 'pos' : '',
  }))));
  wireCard();
};

// ── Jobs ───────────────────────────────────────────────────────
// Read only, and deliberately: signing on happens at a desk.
let jobsTab = 'me';

RENDER.jobs = async () => {
  tabbar([
    { id: 'me', icon: 'id', label: 'ph.my_job' },
    { id: 'open', icon: 'jobs', label: 'ph.openings' },
  ], jobsTab, (t) => { jobsTab = t; RENDER.jobs(); });
  loading();
  const d = await post('app', { app: 'jobs' });
  if (!d || d.error) { body(UI.empty(L('ph.err_off'), 'jobs')); return; }

  if (jobsTab === 'open') {
    const list = d.jobs || [];
    body(list.length
      ? UI.group(list.map((j) => UI.row({
          icon: 'jobs', tint: '#5856D6', title: j.label || j.name,
          subtitle: (j.grade || '') + (j.ranks ? '  -  ' + j.ranks + ' ' + L('ph.ranks') : ''),
          value: money(j.salary), mono: true,
        })), { header: L('ph.openings'), footer: L('ph.jobs_hint') })
      : UI.empty(L('ph.no_jobs'), 'jobs'));
    return;
  }

  // The employment card: the job, the rank held inside it, and the whole ladder, so a
  // player can see where they stand rather than only what they are called.
  const me = d.me || {};
  const unemployed = !me.name || me.name === 'unemployed';
  if (unemployed) {
    body(UI.empty(L('ph.unemployed'), 'jobs') +
      '<div class="groupfoot">' + esc(L('ph.unemployed_hint')) + '</div>');
    return;
  }

  const ladder = me.ladder || [];
  const top = ladder.length ? ladder[ladder.length - 1].grade : me.grade;
  const pct = top > 0 ? Math.round((Number(me.grade) / top) * 100) : 100;

  body(
    // Who you are at work, in the shape a payslip uses.
    '<div class="jobcard">' +
      '<div class="jobname">' + esc(me.label || me.name) + '</div>' +
      '<div class="jobgrade">' + esc(me.gradeLabel || (L('ph.grade') + ' ' + me.grade)) + '</div>' +
      '<div class="jobpay">' + esc(money(me.salary)) + ' <span>' + esc(L('ph.per_pay')) + '</span></div>' +
    '</div>' +
    UI.group([
      UI.row({ icon: 'jobs', tint: '#5856D6', title: L('ph.employer'), value: me.label || me.name }),
      UI.row({ icon: 'id', tint: '#8E8E93', title: L('ph.rank'),
               value: (Number(me.grade) + 1) + ' / ' + (me.ranks || ladder.length || 1) }),
      UI.row({ icon: 'bank', tint: '#34C759', title: L('ph.salary'), value: money(me.salary), mono: true }),
    ]) +
    // Progress through the ladder, because a rank means nothing without the rungs.
    '<div class="grouphead">' + esc(L('ph.progression')) + '</div>' +
    '<div class="jobbar"><i style="width:' + pct + '%"></i></div>' +
    (ladder.length
      ? UI.group(ladder.map((g) => UI.row({
          icon: Number(g.grade) === Number(me.grade) ? 'check' : 'chevron',
          tint: Number(g.grade) === Number(me.grade) ? '#34C759' : '#48484A',
          title: g.name || (L('ph.grade') + ' ' + g.grade),
          subtitle: Number(g.grade) === Number(me.grade) ? L('ph.you_are_here') : '',
          value: money(g.salary), mono: true,
        })), { header: L('ph.ladder') })
      : '')
  );
};

// ── Settings ───────────────────────────────────────────────────
RENDER.settings = () => {
  const p = state.prefs || {};
  body(
    UI.group([
      UI.row({ icon: 'phone', tint: '#34C759', title: L('ph.my_number'), value: state.number || '',
               data: { copy: state.number || '' } }),
      UI.row({ icon: 'folder', tint: '#5AC8FA', title: L('ph.grid'),
        value: (p.gridCols || 4) + ' x ' + (p.gridRows || 4), chevron: true, data: { t: 'grid' } }),
      UI.row({ icon: 'moon', tint: '#5856D6', title: L('ph.dark_mode'),
        value: L('ph.theme_' + (p.darkMode || (p.dark ? 'dark' : 'light'))), chevron: true, data: { t: 'theme' } }),
      UI.row({ icon: 'phone', tint: '#34C759', title: L('ph.vibrate'), toggle: p.vibrate !== false, data: { t: 'vibrate' } }),
      UI.row({ icon: 'speaker', tint: '#FF9500', title: L('ph.ringer'),
        value: Math.round((p.ringVolume ?? 0.7) * 100) + '%', chevron: true, data: { t: 'ringer' } }),
      UI.row({ icon: 'music', tint: '#FF2D55', title: L('ph.ringtone'),
        value: p.ringUrl ? L('ph.tone_custom') : L('ph.tone_' + (p.ringtone || 'classic')),
        chevron: true, data: { t: 'ringtone' } }),
      UI.row({ icon: 'bell', tint: '#FF9F0A', title: L('ph.alerttone'),
        value: p.alertUrl ? L('ph.tone_custom') : L('ph.tone_' + (p.alertTone || 'ping')),
        chevron: true, data: { t: 'alerttone' } }),
    ]) +
    (p.wallpaperUrl ? '<div class="wallpreview" style="' + inlineBackground(p.wallpaperUrl) + '"></div>' : '') +
    (state.customWallpaper === false ? '' :
      UI.field('wurl', L('ph.wall_url'), p.wallpaperUrl || '') +
      '<div class="seg">' +
        '<button class="' + (p.wallFit !== 'contain' ? 'on' : '') + '" data-fit="cover">' + esc(L('ph.fit_cover')) + '</button>' +
        '<button class="' + (p.wallFit === 'contain' ? 'on' : '') + '" data-fit="contain">' + esc(L('ph.fit_contain')) + '</button>' +
      '</div>' +
      UI.button(L('ph.wall_apply'), 'wapply') +
      (p.wallpaperUrl ? UI.button(L('ph.wall_clear'), 'wclear', 'plain') : '') +
      '<div class="groupfoot">' + esc(L('ph.wall_hint')) + '</div>') +
    UI.group((state.wallpapers || []).map((w) => UI.row({
      icon: 'wall', tint: '#007AFF', title: L('ph.wall_' + w),
      value: (!p.wallpaperUrl && p.wallpaper === w) ? L('ph.on') : '',
      data: { w },
    })), { header: L('ph.wallpaper') }) +
    // The device itself: how big, and which side it sits on.
    '<div class="grouphead">' + esc(L('ph.device')) + '</div>' +
    '<div class="sliderow">' +
      '<div class="sl"><span>' + esc(L('ph.size')) + '</span><span>' + Math.round((p.size || 1) * 100) + '%</span></div>' +
      '<input type="range" id="dsize" min="75" max="115" step="1" value="' + Math.round((p.size || 1) * 100) + '" />' +
      '<div class="seg" style="margin-top:12px">' +
        '<button class="' + (p.side !== 'left' ? 'on' : '') + '" data-side="right">' + esc(L('ph.side_right')) + '</button>' +
        '<button class="' + (p.side === 'left' ? 'on' : '') + '" data-side="left">' + esc(L('ph.side_left')) + '</button>' +
      '</div>' +
    '</div>' +
    UI.group([UI.row({ icon: 'moon', tint: '#5856D6', title: L('ph.dnd'), toggle: !!p.dnd, data: { t: 'dnd' } })],
      { footer: L('ph.dnd_hint') }) +
    // iOS 27's headline user-facing change. It is a stored preference every layer of
    // the glass derives from, not a fade on one overlay.
    '<div class="grouphead">' + esc(L('ph.transparency')) + '</div>' +
    '<div class="sliderow">' +
      '<div class="sl"><span>' + esc(L('ph.glass_clear')) + '</span>' +
      '<span>' + esc(L('ph.glass_tinted')) + '</span></div>' +
      '<input type="range" id="glass" min="0" max="100" step="1" value="' + (p.glass ?? 55) + '" />' +
    '</div>' +
    '<div class="groupfoot">' + esc(L('ph.glass_hint')) + '</div>' +
    UI.group((state.apps || []).map((a) => UI.row({
      appicon: a.icon, title: L(a.label),
      value: p.actionApp === a.id ? L('ph.on') : '', data: { act: a.id },
    })), { header: L('ph.action_button'), footer: L('ph.action_hint') }) +
    // About, where a phone puts it: the last thing in Settings.
    UI.group([
      UI.row({ icon: 'phone', tint: '#8E8E93', title: L('ph.about_device'), value: 'iFruit' }),
      UI.row({ icon: 'settings', tint: '#8E8E93', title: L('ph.about_framework'), value: 'v-core' }),
      UI.row({ icon: 'id', tint: '#8E8E93', title: L('ph.about_dev'), value: 'vyrriox' }),
    ], { header: L('ph.about_title'), footer: L('ph.about_foot') })
  );
  const wa = byId('wapply');
  if (wa) wa.addEventListener('click', async () => {
    const res = await post('prefs', { wallpaperUrl: byId('wurl').value.trim() });
    if (res && res.ok) { state.prefs = res.prefs; applyWallpaper(); RENDER.settings(); }
    else toast(L('ph.err_' + ((res && res.error) || 'x')));
  });
  const wc = byId('wclear');
  if (wc) wc.addEventListener('click', async () => {
    const res = await post('prefs', { wallpaperUrl: '' });
    if (res && res.ok) { state.prefs = res.prefs; applyWallpaper(); RENDER.settings(); }
  });
  [...byId('appbody').querySelectorAll('[data-fit]')].forEach((b) =>
    b.addEventListener('click', async () => {
      const res = await post('prefs', { wallFit: b.dataset.fit });
      if (res && res.ok) { state.prefs = res.prefs; applyWallpaper(); RENDER.settings(); }
    }));
  [...byId('appbody').querySelectorAll('[data-side]')].forEach((b) =>
    b.addEventListener('click', async () => {
      const res = await post('prefs', { side: b.dataset.side });
      if (res && res.ok) { state.prefs = res.prefs; applyDevice(); RENDER.settings(); }
    }));
  const ds = byId('dsize');
  if (ds) {
    ds.addEventListener('input', () => {
      state.prefs.size = Number(ds.value) / 100;
      applyDevice();
      ds.style.setProperty('--fill-pct', ((Number(ds.value) - 75) / 40 * 100) + '%');
    });
    ds.addEventListener('change', async () => {
      const res = await post('prefs', { size: Number(ds.value) / 100 });
      if (res && res.ok) state.prefs = res.prefs;
    });
    ds.style.setProperty('--fill-pct', (((p.size || 1) * 100 - 75) / 40 * 100) + '%');
  }

  const gl = byId('glass');
  if (gl) {
    // Repaint live while dragging so the value is judged by looking at it, and only
    // persist on release: one write per adjustment, not one per pixel.
    gl.addEventListener('input', () => {
      applyGlass(Number(gl.value));
      gl.style.setProperty('--fill-pct', gl.value + '%');
    });
    gl.addEventListener('change', async () => {
      const res = await post('prefs', { glass: Number(gl.value) });
      if (res && res.ok) state.prefs = res.prefs;
    });
    gl.style.setProperty('--fill-pct', (p.glass ?? 55) + '%');
  }

  rows('.row', (r) => r.addEventListener('click', async () => {
    if (r.dataset.w) {
      const res = await post('prefs', { wallpaper: r.dataset.w });
      if (res && res.ok) { state.prefs = res.prefs; applyWallpaper(); RENDER.settings(); }
    } else if (r.dataset.copy) {
      copyText(r.dataset.copy);
    } else if (r.dataset.t === 'grid') {
      // The layouts a phone actually offers: fewer, larger icons or more, smaller ones.
      const opts = [[4, 4], [4, 5], [4, 6], [5, 5], [5, 6], [6, 6], [3, 4]];
      sheet(L('ph.grid'),
        UI.group(opts.map(([c, rw]) => UI.row({
          title: c + ' x ' + rw, subtitle: (c * rw) + ' ' + L('ph.grid_per_page'),
          value: ((p.gridCols || 4) === c && (p.gridRows || 4) === rw) ? '✓' : '',
          data: { gc: String(c), gr: String(rw) },
        }))) + '<div class="groupfoot">' + esc(L('ph.grid_hint')) + '</div>',
        () => [...byId('sheet').querySelectorAll('.row')].forEach((el) => el.addEventListener('click', async () => {
          const res = await post('prefs', { gridCols: Number(el.dataset.gc), gridRows: Number(el.dataset.gr) });
          closeSheet();
          if (res && res.ok) { state.prefs = res.prefs; renderHome(); RENDER.settings(); }
        })));
      return;
    } else if (r.dataset.t === 'theme') {
      const t = state.theme || {};
      const opts = [['light', 'ph.theme_light'], ['dark', 'ph.theme_dark']];
      if (t.auto) opts.push(['auto', 'ph.theme_auto']);
      sheet(L('ph.dark_mode'),
        UI.group(opts.map(([k, lbl]) => UI.row({
          title: L(lbl), value: (state.prefs || {}).darkMode === k ? '\u2713' : '', data: { m: k },
        }))) + (t.auto ? '<div class="groupfoot">' + esc(L('ph.theme_auto_hint')) + '</div>' : ''),
        () => [...byId('sheet').querySelectorAll('.row')].forEach((el) => el.addEventListener('click', async () => {
          const res2 = await post('prefs', { darkMode: el.dataset.m });
          closeSheet();
          if (res2 && res2.ok) { state.prefs = res2.prefs; applyTheme(); RENDER.settings(); }
        })));
      return;
    } else if (r.dataset.t === 'vibrate') {
      const res2 = await post('prefs', { vibrate: !((state.prefs || {}).vibrate !== false) });
      if (res2 && res2.ok) { state.prefs = res2.prefs; RENDER.settings(); }
      return;
    } else if (r.dataset.t === 'ringtone' || r.dataset.t === 'alerttone') {
      const isRing = r.dataset.t === 'ringtone';
      const sc = (state.sounds || {});
      const list = (isRing ? sc.ringtones : sc.alerts) || (isRing ? ['classic'] : ['ping']);
      const curTone = isRing ? (p.ringtone || 'classic') : (p.alertTone || 'ping');
      const curUrl = (isRing ? p.ringUrl : p.alertUrl) || '';
      sheet(L(isRing ? 'ph.ringtone' : 'ph.alerttone'),
        UI.group(list.map((t) => UI.row({
          icon: 'music', title: L('ph.tone_' + t),
          value: (!curUrl && curTone === t) ? '\u2713' : '', data: { tone: t },
        }))) +
        (sc.allowCustom === false ? '' :
          '<div class="grouphead">' + esc(L('ph.tone_link')) + '</div>' +
          UI.field('toneurl', L('ph.tone_link_ph'), curUrl, 'maxlength="400"') +
          UI.button(L('ph.tone_use'), 'toneset', 'tinted') +
          (curUrl ? UI.button(L('ph.tone_clear'), 'tonedel', 'plain') : '') +
          '<div class="groupfoot">' + esc(L('ph.tone_hint')) + '</div>'),
        () => {
          // Tapping a tone previews it, then saves - you hear what you picked.
          [...byId('sheet').querySelectorAll('.row')].forEach((el) => el.addEventListener('click', async () => {
            const tone = el.dataset.tone;
            playTone(tone, null, (state.prefs || {}).ringVolume, false);
            const res = await post('prefs', isRing ? { ringtone: tone, ringUrl: '' } : { alertTone: tone, alertUrl: '' });
            if (res && res.ok) { state.prefs = res.prefs; closeSheet(); RENDER.settings(); }
          }));
          const setBtn = byId('toneset');
          if (setBtn) setBtn.addEventListener('click', async () => {
            const url = byId('toneurl').value.trim();
            const res = await post('prefs', isRing ? { ringUrl: url } : { alertUrl: url });
            if (res && res.ok) { state.prefs = res.prefs; closeSheet(); RENDER.settings();
              playTone(null, url, (state.prefs || {}).ringVolume, false); toast(L('ph.tone_saved')); }
            else toast(L('ph.err_' + ((res && res.error) || 'x')));
          });
          const delBtn = byId('tonedel');
          if (delBtn) delBtn.addEventListener('click', async () => {
            const res = await post('prefs', isRing ? { ringUrl: '' } : { alertUrl: '' });
            if (res && res.ok) { state.prefs = res.prefs; closeSheet(); RENDER.settings(); }
          });
        });
      return;
    } else if (r.dataset.t === 'ringer') {
      sheet(L('ph.ringer'),
        UI.group([0, 0.3, 0.7, 1].map((v) => UI.row({
          title: Math.round(v * 100) + '%', subtitle: v === 0 ? L('ph.ringer_off') : '',
          value: Math.abs(((state.prefs || {}).ringVolume ?? 0.7) - v) < 0.01 ? '\u2713' : '', data: { v: String(v) },
        }))),
        () => [...byId('sheet').querySelectorAll('.row')].forEach((el) => el.addEventListener('click', async () => {
          const res2 = await post('prefs', { ringVolume: Number(el.dataset.v) });
          closeSheet();
          if (res2 && res2.ok) { state.prefs = res2.prefs; RENDER.settings(); }
        })));
      return;
    } else if (r.dataset.t === 'dark') {
      const res = await post('prefs', { dark: !(state.prefs || {}).dark });
      if (res && res.ok) { state.prefs = res.prefs; applyTheme(); RENDER.settings(); }
    } else if (r.dataset.act) {
      // Tapping the app already chosen clears it, so there is a way back to "nothing".
      const next = (state.prefs || {}).actionApp === r.dataset.act ? '' : r.dataset.act;
      const res = await post('prefs', { actionApp: next });
      if (res && res.ok) { state.prefs = res.prefs; RENDER.settings(); }
    } else if (r.dataset.t === 'dnd') {
      const res = await post('prefs', { dnd: !(state.prefs || {}).dnd });
      if (res && res.ok) {
        state.prefs = res.prefs;
        syncDndAudio();
        RENDER.settings();
      }
    }
  }));
};

// 0 is ultra clear, 100 fully tinted. Every material alpha is resolved from this value.
function applyGlass(v) {
  const k = Math.max(0, Math.min(100, Number(v) || 0)) / 100;
  const screen = byId('screen');
  screen.style.setProperty('--gk', String(k));
  // CEF is inconsistent with multiplication inside calc() when the factor comes from a
  // custom property. Resolve the material alphas here into plain numeric channels.
  screen.style.setProperty('--tint-a', (0.10 + k * 0.46).toFixed(3));
  screen.style.setProperty('--sheen-a', (0.12 + k * 0.10).toFixed(3));
  screen.style.setProperty('--rim-a', (0.22 + k * 0.18).toFixed(3));
}

function applyWallpaper() {
  const w = byId('wallpaper');
  const p = state.prefs || {};
  (state.wallpapers || []).forEach((x) => w.classList.remove('wall-' + x));
  if (p.wallpaperUrl) {
    // A linked image replaces the gradient rather than sitting on top of it, so the
    // class list cannot leave a stripe of the old one showing at the edges.
    w.style.backgroundImage = 'url("' + p.wallpaperUrl + '")';
    w.style.backgroundSize = (p.wallFit === 'contain') ? 'contain' : 'cover';
    w.style.backgroundPosition = 'center';
    w.style.backgroundRepeat = 'no-repeat';
    w.style.backgroundColor = '#000';
  } else {
    w.style.backgroundImage = '';
    w.style.backgroundSize = '';
    w.style.backgroundColor = '';
    w.classList.add('wall-' + (p.wallpaper || 'aurora'));
  }
}

// The device's own shape. Both are per character, because a small screen and a
// left-handed player are not the same person's problem.
// An app is light by default, as it is on iOS. The chrome around it stays dark glass
// over the wallpaper, which is also how iOS behaves: the two are different surfaces.
// The status bar tells the truth about both. Neither number is the client's to invent:
// the server works them out from where the player actually is.
function applyPower(p) {
  if (!p) return;
  // A payload without a level (an old server, a fixture, a race at open) must fall
  // back to full rather than to NaN: Math.round(undefined) is the word NaN drawn in
  // the status bar, and it was.
  const raw = Number(p.battery);
  const b = Number.isFinite(raw) ? Math.max(0, Math.min(100, raw)) : 100;
  const el = byId('battery');
  el.style.setProperty('--batt', String(b / 100));
  el.style.setProperty('--batt-col', p.charging ? '#34C759' : (b <= 5 ? '#FF3B30' : (b <= 20 ? '#FF9500' : 'var(--sb-ink, #fff)')));
  byId('battpct').textContent = Math.round(b);

  state._power = p;
  const pr = state.prefs || {};
  // Airplane and a cellular kill-switch both mean no service, whatever the tower says.
  const off = pr.airplane || pr.cellular === false;
  const bars = off ? 0 : Math.max(0, Math.min(4, Number(p.signal ?? 4)));
  [...byId('bars').querySelectorAll('rect')].forEach((r) =>
    r.classList.toggle('off', Number(r.dataset.b) > bars));
  // No service is worth saying in words: an icon of four empty bars reads as a glitch.
  byId('nosvc').classList.toggle('hidden', bars > 0 || pr.airplane);
  applyStatusFlags();
}

// Airplane replaces the bars with its own glyph; wifi hides when switched off.
function applyStatusFlags() {
  const p = state.prefs || {};
  byId('apmode').classList.toggle('hidden', !p.airplane);
  byId('bars').classList.toggle('hidden', !!p.airplane);
  const wifi = byId('status').querySelector('.sright > svg:not(#bars):not(#apmode)');
  if (wifi) wifi.style.opacity = p.wifi === false ? '0' : '';
}

// Brightness is a real dimming veil, 0.35 to 1 of the wallpaper's light.
function applyBrightness() {
  const b = Math.max(0.35, Math.min(1, (state.prefs || {}).brightness ?? 1));
  byId('screen').style.setProperty('--dim', String(1 - b));
}

// Light, dark, or follow the in-game clock. Automatic is only offered if the operator
// left it on; the hours it flips at are theirs to set too.
let gameHour = null;      // last in-game hour we were told about

function darkNow() {
  const p = state.prefs || {}, t = state.theme || {};
  const mode = p.darkMode || (p.dark ? 'dark' : 'light');
  if (mode !== 'auto' || !t.auto) return mode === 'dark';
  if (gameHour == null) return p.dark === true;
  const from = Number(t.from ?? 20), to = Number(t.to ?? 6);
  // A start later than the end wraps over midnight, which is the normal case.
  return from <= to ? (gameHour >= from && gameHour < to)
                    : (gameHour >= from || gameHour < to);
}

function applyTheme() {
  byId('screen').classList.toggle('dark', darkNow());
}

let landscape = false;
function applyDevice() {
  const p = state.prefs || {};
  const d = byId('device');
  const size = Math.max(0.75, Math.min(1.15, Number(p.size) || 1));
  const viewport = window.visualViewport;
  const vw = (viewport && viewport.width) || window.innerWidth || 1280;
  const vh = (viewport && viewport.height) || window.innerHeight || 720;
  const rawW = d.offsetWidth || 372;
  const rawH = d.offsetHeight || 784;
  const footprintW = landscape ? rawH : rawW;
  const footprintH = landscape ? rawW : rawH;
  const fit = Math.max(0.10, Math.min(1,
    (vw - 24) / (footprintW * size),
    (vh - 24) / (footprintH * size)));
  const scale = size * fit;
  d.style.setProperty('--device-fit', String(fit));
  d.style.setProperty('--device-scale', String(scale));
  if (landscape) {
    // The phone lies on its side, centred so it cannot swing off-screen.
    d.style.left = '50%'; d.style.right = 'auto'; d.style.top = '50%'; d.style.bottom = 'auto';
    d.style.transformOrigin = 'center center';
    d.style.transform = 'translate(-50%, -50%) rotate(-90deg) scale(' + scale + ')';
  } else {
    d.style.top = 'auto'; d.style.bottom = '2.5vh';
    d.style.transformOrigin = (p.side === 'left') ? 'left bottom' : 'right bottom';
    d.style.transform = 'scale(' + scale + ')';
    d.style.right = (p.side === 'left') ? 'auto' : '3vw';
    d.style.left = (p.side === 'left') ? '3vw' : 'auto';
  }
}
function setLandscape(on) { landscape = on === true; applyDevice(); }

// -- Maps -------------------------------------------------------
// Everywhere the map already shows, turned into a waypoint. A phone map that could not
// set a waypoint would be a list of place names.
let placeFilter = 'all';

RENDER.maps = async () => {
  loading();
  const d = await post('places');
  if (!d || d.error) { body(UI.empty(L('ph.err_off'), 'map')); return; }
  const all = d.places || [];
  const kinds = [...new Set(all.map((p) => p.kind))];
  const shown = placeFilter === 'all' ? all : all.filter((p) => p.kind === placeFilter);

  body(
    '<div class="seg">' +
      '<button class="' + (placeFilter === 'all' ? 'on' : '') + '" data-k="all">' + esc(L('ph.all')) + '</button>' +
      kinds.map((k) => '<button class="' + (placeFilter === k ? 'on' : '') + '" data-k="' + esc(k) + '">' + esc(L('ph.place_' + k)) + '</button>').join('') +
    '</div>' +
    (shown.length
      ? UI.group(shown.map((pl, i) => UI.row({
          icon: pl.icon, title: pl.label, subtitle: L('ph.place_' + pl.kind),
          chevron: true, data: { i },
        })), { footer: L('ph.maps_hint') })
      : UI.empty(L('ph.no_places'), 'map'))
  );
  [...byId('appbody').querySelectorAll('.seg button')].forEach((b) =>
    b.addEventListener('click', () => { placeFilter = b.dataset.k; RENDER.maps(); }));
  rows('.row[data-i]', (r) => r.addEventListener('click', async () => {
    const pl = shown[Number(r.dataset.i)];
    if (!pl) return;
    await post('waypoint', { x: pl.x, y: pl.y, label: pl.label });
    toast(L('ph.waypoint_set'));
  }));
};

// -- Music ------------------------------------------------------
// v-music owns every source and decides who may touch which one; this lists what it
// answered and sends the same actions its own UI does.
// A library of your own, kept on the phone, plus whatever is already playing around you.
// A track is a link - YouTube or any host the operator allows - and playing it on the
// phone speaker puts a short-range source at your feet, so the people you are standing
// with hear it and nobody across the street does.
let musicTab = 'library';

async function musicLibrary() {
  const r = await post('appStorage', { app: 'music', op: 'get', key: 'library' });
  let lib = [];
  try { lib = JSON.parse((r && r.value) || '[]'); } catch { lib = []; }
  return Array.isArray(lib) ? lib : [];
}
async function musicSaveLibrary(lib) {
  return post('appStorage', { app: 'music', op: 'set', key: 'library', value: JSON.stringify(lib.slice(0, 60)) });
}

RENDER.music = async () => {
  setNav(L('app.music'), null, { icon: 'add', onClick: () => musicAdd() });
  tabbar([
    { id: 'library', icon: 'music', label: 'ph.library' },
    { id: 'around', icon: 'speaker', label: 'ph.playing_around' },
  ], musicTab, (t) => { musicTab = t; RENDER.music(); });

  if (musicTab === 'library') {
    const lib = await musicLibrary();
    if (!lib.length) { body(UI.empty(L('ph.library_empty'), 'music')); return; }
    body(UI.group(lib.map((t, i) => UI.row({
      icon: 'music', tint: '#FA2D48', title: t.title || L('ph.untitled'),
      subtitle: t.url, chevron: true, data: { i },
    })), { header: L('ph.library'), footer: L('ph.library_hint') }));
    rows('.row[data-i]', (el) => el.addEventListener('click', () => musicTrack(lib[Number(el.dataset.i)], Number(el.dataset.i))));
    return;
  }

  loading();
  const d = await post('app', { app: 'music' });
  if (!d || d.error || d.enabled === false) { body(UI.empty(L('ph.err_off'), 'music')); return; }
  const list = d.sources || [];
  if (!list.length) { body(UI.empty(L('ph.no_music'), 'music')); return; }
  body(UI.group(list.map((m, i) => UI.row({
    icon: 'music', tint: '#FA2D48', title: m.title || L('ph.untitled'),
    subtitle: L('ph.music_' + (m.kind || 'boombox')),
    value: m.paused ? L('ph.paused') : L('ph.playing'),
    tone: m.paused ? '' : 'pos', chevron: true, data: { i },
  })), { header: L('ph.music_sources') }));
  rows('.row[data-i]', (r) => r.addEventListener('click', () => musicSheet(list[Number(r.dataset.i)])));
};

function musicAdd(existing, index) {
  sheet(L(existing ? 'ph.track_edit' : 'ph.track_add'),
    UI.field('mtitle', L('ph.track_title'), (existing && existing.title) || '', 'maxlength="80"') +
    UI.field('murl', L('ph.track_url'), (existing && existing.url) || '', 'maxlength="400"') +
    UI.button(L('ph.save'), 'mtsave', 'tinted') +
    '<div class="groupfoot">' + esc(L('ph.track_hint')) + '</div>',
    () => byId('mtsave').addEventListener('click', async () => {
      const url = byId('murl').value.trim();
      if (!url) { toast(L('ph.track_nourl')); return; }
      const lib = await musicLibrary();
      const t = { title: byId('mtitle').value.trim() || url, url };
      if (index != null) lib[index] = t; else lib.unshift(t);
      await musicSaveLibrary(lib);
      closeSheet(); RENDER.music();
    }));
}

function musicTrack(t, i) {
  sheet(t.title || L('ph.untitled'),
    '<div class="mailmeta">' + esc(t.url) + '</div>' +
    UI.button(L('ph.play_ear'), 'mear', 'tinted') +
    UI.button(L('ph.play_speaker'), 'mplay', 'plain') +
    UI.button(L('ph.track_edit'), 'medit', 'plain') +
    UI.button(L('ph.delete'), 'mdelt', 'destructive'),
    () => {
      // Headphones: a private source only this player's client will play.
      byId('mear').addEventListener('click', async () => {
        const r = await post('music', { action: 'play', kind: 'headphones', url: t.url, title: t.title });
        closeSheet();
        toast(r && r.ok ? L('ph.playing_ear') : L('ph.err_' + ((r && r.error) || 'x')));
      });
      byId('mplay').addEventListener('click', async () => {
        // kind 'phone' is a short-range source that follows the player: a phone on
        // speaker, not a boombox.
        const r = await post('music', { action: 'play', kind: 'phone', url: t.url, title: t.title });
        closeSheet();
        toast(r && r.ok ? L('ph.playing') : L('ph.err_' + ((r && r.error) || 'x')));
      });
      byId('medit').addEventListener('click', () => { closeSheet(); musicAdd(t, i); });
      byId('mdelt').addEventListener('click', async () => {
        const lib = await musicLibrary();
        lib.splice(i, 1);
        await musicSaveLibrary(lib);
        closeSheet(); RENDER.music();
      });
    });
}

function musicSheet(m) {
  const act = async (action) => {
    const res = await post('music', { id: m.id, action });
    closeSheet();
    if (!res || res.error) toast(L('ph.err_' + ((res && res.error) || 'x')));
    else RENDER.music();
  };
  sheet(m.title || L('ph.untitled'),
    UI.button(L(m.paused ? 'ph.resume' : 'ph.pause'), 'mpause') +
    UI.button(L('ph.stop'), 'mstop', 'destructive'),
    () => {
      byId('mpause').addEventListener('click', () => act(m.paused ? 'resume' : 'pause'));
      byId('mstop').addEventListener('click', () => act('stop'));
    });
}

// -- Property ---------------------------------------------------
// A failed rent locks a door rather than deleting a property, so the one thing this app
// has to be able to do is pay it off from anywhere.
RENDER.property = async () => {
  loading();
  const d = await post('app', { app: 'property' });
  if (!d || d.error) { body(UI.empty(L('ph.err_off'), 'house')); return; }
  const list = d.rows || [];
  if (!list.length) { body(UI.empty(L('ph.no_property'), 'house')); return; }
  body(UI.group(list.map((pr, i) => UI.row({
    icon: 'house', tint: '#12A5BC', title: pr.label,
    subtitle: L('ph.tenancy_' + (pr.tenancy || 'own')) +
      (Number(pr.arrears) > 0 ? '  ' + String(L('ph.arrears')).replace('%s', pr.arrears) : ''),
    value: pr.locked ? L('ph.locked') : '',
    tone: pr.locked ? 'neg' : '',
    chevron: !!pr.locked, data: { i },
  })), { footer: L('ph.property_hint') }));
  rows('.row[data-i]', (r) => r.addEventListener('click', async () => {
    const pr = list[Number(r.dataset.i)];
    if (!pr || !pr.locked) return;
    const res = await post('payRent', { id: pr.property });
    if (res && res.ok) { toast(L('ph.rent_paid')); RENDER.property(); }
    else toast(L('ph.err_' + ((res && res.error) || 'x')));
  }));
};

// -- MDT --------------------------------------------------------
// Police only by default, and the server re-checks that on every call: the app gate only
// decides whether the icon is drawn.
let mdtTab = 'warrants';
let mdtLookupSeq = 0;

RENDER.mdt = async () => {
  mdtLookupSeq += 1;
  const seg =
    '<div class="seg">' +
      '<button class="' + (mdtTab === 'warrants' ? 'on' : '') + '" data-t="warrants">' + esc(L('ph.warrants')) + '</button>' +
      '<button class="' + (mdtTab === 'lookup' ? 'on' : '') + '" data-t="lookup">' + esc(L('ph.lookup')) + '</button>' +
    '</div>';
  const wire = () => [...byId('appbody').querySelectorAll('.seg button')].forEach((b) =>
    b.addEventListener('click', () => { mdtTab = b.dataset.t; RENDER.mdt(); }));

  if (mdtTab === 'lookup') {
    body(seg + UI.field('mq', L('ph.lookup_ph')) + UI.button(L('ph.search'), 'mgo') + '<div id="mres"></div>');
    wire();
    byId('mgo').addEventListener('click', async () => {
      const seq = ++mdtLookupSeq;
      const host = byId('mres');
      const query = byId('mq').value.trim();
      const res = await post('mdt', { op: 'lookup', query });
      if (seq !== mdtLookupSeq || byId('mres') !== host) return;
      if (!res || res.error) { host.innerHTML = UI.empty(L('ph.err_' + ((res && res.error) || 'x'))); return; }
      host.innerHTML =
        UI.group([UI.row({ icon: 'id', title: res.name || '', subtitle: res.cid || '' })]) +
        ((res.records || []).length
          ? UI.group(res.records.map((r) => UI.row({
              title: r.charges || '', subtitle: r.at || '',
              value: r.paid ? L('ph.paid') : L('ph.unpaid'), tone: r.paid ? 'pos' : 'neg',
            })), { header: L('ph.record') })
          : UI.empty(L('ph.no_record')));
    });
    return;
  }

  loading();
  const d = await post('mdt', { op: 'warrants' });
  if (!d || d.error) { body(seg + UI.empty(L('ph.err_' + ((d && d.error) || 'x')), 'shield')); wire(); return; }
  const list = d.rows || [];
  body(seg + (list.length
    ? UI.group(list.map((w) => UI.row({
        icon: 'shield',
        title: ((w.firstname || '') + ' ' + (w.lastname || '')).trim() || w.citizenid,
        subtitle: w.reason || '', time: w.at || '',
      })), { header: L('ph.warrants_active') })
    : UI.empty(L('ph.no_warrants'), 'shield')));
  wire();
};

// -- Calculator -------------------------------------------------
// Owned by the phone, and the one app here that needs no module: splitting a payment
// three ways is something players do constantly and currently do in their heads.
let calcAcc = null, calcOp = null, calcVal = '0', calcFresh = true;

function calcPress(k) {
  const put = (v) => { calcVal = calcFresh ? v : (calcVal === '0' ? v : calcVal + v); calcFresh = false; };
  if (k >= '0' && k <= '9') put(k);
  else if (k === '.') { if (!calcVal.includes('.')) put(calcFresh ? '0.' : '.'); }
  else if (k === 'c') { calcAcc = null; calcOp = null; calcVal = '0'; calcFresh = true; }
  else if (k === 'neg') calcVal = String(-parseFloat(calcVal));
  else if (k === 'pct') calcVal = String(parseFloat(calcVal) / 100);
  else if (k === '=') {
    if (calcOp !== null && calcAcc !== null) {
      const b = parseFloat(calcVal);
      const r = { '+': calcAcc + b, '-': calcAcc - b, '*': calcAcc * b, '/': b === 0 ? 0 : calcAcc / b }[calcOp];
      calcVal = String(Math.round(r * 1e6) / 1e6);
      calcAcc = null; calcOp = null; calcFresh = true;
    }
  } else {
    if (calcOp !== null && !calcFresh) calcPress('=');
    calcAcc = parseFloat(calcVal); calcOp = k; calcFresh = true;
  }
  const out = byId('calcout');
  if (out) out.textContent = calcVal;
}

RENDER.calc = () => {
  byId('app').classList.add('black');
  byId('screen').classList.add('appblack');
  const K = [['c', 'fn', 'AC'], ['neg', 'fn', '+/-'], ['pct', 'fn', '%'], ['/', 'op', '÷'],
             ['7', '', '7'], ['8', '', '8'], ['9', '', '9'], ['*', 'op', '×'],
             ['4', '', '4'], ['5', '', '5'], ['6', '', '6'], ['-', 'op', '−'],
             ['1', '', '1'], ['2', '', '2'], ['3', '', '3'], ['+', 'op', '+'],
             ['0', 'wide', '0'], ['.', '', ','], ['=', 'op', '=']];
  body('<div class="calcout" id="calcout">' + esc(calcVal) + '</div>' +
    '<div class="calcgrid">' + K.map(function (e) {
      return '<button class="ckey ' + e[1] + '" data-k="' + esc(e[0]) + '" type="button">' + e[2] + '</button>';
    }).join('') + '</div>');
  rows('.ckey', (b) => b.addEventListener('click', () => calcPress(b.dataset.k)));
};


// ══ Gestures ═══════════════════════════════════════════════════
// The phone is driven by a mouse, so a "swipe" is a click-drag. Where the drag STARTS is
// what decides its meaning, exactly as on the real thing: the bottom edge is the home
// gesture, the top edge is the shade and the control centre, and everywhere else belongs
// to whatever is on screen.
const EDGE = 34;          // how deep the bottom edge zone reaches
const EDGE_TOP = 56;      // the top zone is the whole status bar, or a drag that
                          // starts on the clock would not count as from the top
const SWIPE = 46;         // travel before a drag counts as a swipe

let g = null;

function screenPoint(e) {
  const r = byId('screen').getBoundingClientRect();
  return { x: e.clientX - r.left, y: e.clientY - r.top, w: r.width, h: r.height };
}

function anyOverlayOpen() {
  return ['cc', 'shade', 'switcher', 'sheet'].some((id) => byId(id).classList.contains('on'));
}

function closeOverlays() {
  ['cc', 'shade', 'switcher'].forEach((id) => byId(id).classList.remove('on'));
  closeSheet(true);
}

function resetTransientUI() {
  ['cc', 'shade', 'switcher'].forEach((id) => byId(id).classList.remove('on'));
  shadeManage = false;
  closeSheet(true);
  emojiClose();
  byId('folderview').classList.remove('on');
  if (editing) exitArrange();
  else if (arr) endDrag(true);

  clearTimeout(glanceTimer); glanceTimer = null;
  clearTimeout(islandTimer); islandTimer = null;
  clearTimeout(peekTimer); peekTimer = null;
  clearTimeout(buzzTimer); buzzTimer = null;
  clearTimeout(hudTimer); hudTimer = null;
  clearTimeout(toastTimer); toastTimer = null;
  clearTimeout(shutterTimer); shutterTimer = null;

  byId('toast').classList.remove('on');
  byId('hud').classList.remove('on');
  byId('device').classList.remove('peeking', 'buzz', 'capturing');
  byId('app').classList.remove('black');
  byId('screen').classList.remove('appblack');
  setIslandMode(call ? 'live' : null);
}

byId('screen').addEventListener('pointerdown', (e) => {
  const p = screenPoint(e);
  g = { x0: p.x, y0: p.y, t0: Date.now(), w: p.w, h: p.h,
        fromBottom: p.y > p.h - EDGE, fromTop: p.y < EDGE_TOP, fromLeft: p.x < 18,
        insideOverlay: !!(e.target.closest && e.target.closest('#sheet,#shade,#cc,#switcher')) };
});

let glassFrame = 0;
let pendingGlassPoint = null;

function trackGlassPointer(e) {
  const p = screenPoint(e);
  const x = Math.max(0, Math.min(100, (p.x / Math.max(1, p.w)) * 100));
  const y = Math.max(0, Math.min(100, (p.y / Math.max(1, p.h)) * 100));
  pendingGlassPoint = [x, y];
  if (glassFrame) return;
  glassFrame = requestAnimationFrame(() => {
    const point = pendingGlassPoint;
    glassFrame = 0;
    pendingGlassPoint = null;
    if (!point) return;
    const screen = byId('screen');
    screen.style.setProperty('--glass-x', point[0].toFixed(2) + '%');
    screen.style.setProperty('--glass-y', point[1].toFixed(2) + '%');
  });
}

byId('screen').addEventListener('pointermove', trackGlassPointer, { passive: true });
byId('screen').addEventListener('pointerdown', (e) => {
  trackGlassPointer(e);
  const target = e.target.closest && e.target.closest(
    'button, .tile, .row, .card, .ncard, .lnotif, .strowitem, .shot'
  );
  if (!target || !byId('screen').contains(target) || target.disabled) return;
  const r = target.getBoundingClientRect();
  if (getComputedStyle(target).position === 'static') target.style.position = 'relative';
  const flare = document.createElement('span');
  flare.className = 'touch-flare';
  flare.setAttribute('aria-hidden', 'true');
  flare.style.left = (e.clientX - r.left) + 'px';
  flare.style.top = (e.clientY - r.top) + 'px';
  target.appendChild(flare);
  setTimeout(() => flare.remove(), 520);
});

byId('screen').addEventListener('pointerup', (e) => {
  if (!g) return;
  const p = screenPoint(e);
  const dx = p.x - g.x0, dy = p.y - g.y0;
  const held = Date.now() - g.t0;
  const gg = g; g = null;

  if (Math.abs(dx) < SWIPE && Math.abs(dy) < SWIPE) return;   // a tap, not a swipe

  // Bottom edge, upwards: home. Held for a moment first: the app switcher. That pause is
  // the whole difference between the two gestures on a real phone.
  if (gg.fromBottom && dy < -SWIPE) {
    if (held > 320) openSwitcher(); else { closeOverlays(); goHome(); }
    return;
  }

  // Top edge, downwards: left half is the notification shade, right half the control
  // centre. Same split iOS uses, and it means neither one needs a button.
  if (gg.fromTop && dy > SWIPE) {
    if (gg.x0 < gg.w / 2) openShade(); else openCC();
    return;
  }

  // Scrolling a sheet/shade, moving a CC slider or flicking a switcher card belongs to
  // that overlay. Only a genuine edge gesture above is allowed to escape it.
  if (gg.insideOverlay) return;

  if (anyOverlayOpen()) { closeOverlays(); return; }

  // Inside an app, a drag in from the left edge goes back, which is the one gesture
  // people reach for without being told.
  if (byId('app').classList.contains('on') && gg.fromLeft && dx > SWIPE) {
    byId('navback').click();
    return;
  }

  // On the home screen, sideways moves between pages - but never while a tile is being
  // carried, which owns the pointer.
  if (!arr && !byId('home').classList.contains('behind') && !byId('app').classList.contains('on')
      && Math.abs(dx) > Math.abs(dy)) {
    flipPage(dx < 0 ? 1 : -1);
    return;
  }

  // On the lock screen, up unlocks.
  if (!byId('lock').classList.contains('out') && dy < -SWIPE) unlock();
});

// ══ App switcher ═══════════════════════════════════════════════
function openSwitcher() {
  const list = recents
    .map((id) => (state.apps || []).find((a) => a.id === id))
    .filter(Boolean);
  if (!list.length) { toast(L('ph.no_recents')); return; }

  byId('cards').innerHTML = list.map((a) =>
    '<div class="card glass" data-app="' + esc(a.id) + '">' +
      '<div class="chead"><span class="ic">' + svg(a.icon) + '</span>' +
      '<b>' + esc(L(a.label)) + '</b></div><div class="cbody">' +
      '<div class="cpreview">' + UI.appIcon(a.icon, 'previewicon') +
      '<b class="previewname">' + esc(L(a.label)) + '</b></div></div></div>').join('') +
    '<div class="switchhint">' + esc(L('ph.switch_hint')) + '</div>';
  byId('switcher').classList.add('on');

  [...byId('cards').querySelectorAll('.card')].forEach((c) => {
    let y0 = null;
    c.addEventListener('pointerdown', (e) => { y0 = e.clientY; });
    c.addEventListener('pointerup', (e) => {
      const flicked = y0 !== null && e.clientY - y0 < -60;
      y0 = null;
      if (flicked) {
        // Flick a card away to close the app, as on a real phone.
        const id = c.dataset.app;
        c.classList.add('gone');
        recents = recents.filter((recent) => recent !== id);
        setTimeout(() => {
          if (openApp && openApp.id === id) closeApp(true);
          if (!recents.length) byId('switcher').classList.remove('on');
          else openSwitcher();
        }, 240);
        return;
      }
      const a = (state.apps || []).find((x) => x.id === c.dataset.app);
      byId('switcher').classList.remove('on');
      if (a) enterApp(a, null);
    });
  });
}

// ══ Notification shade ═════════════════════════════════════════
function openShade() {
  const d = new Date();
  byId('shadeclock').textContent =
    String(d.getHours()).padStart(2, '0') + ':' + String(d.getMinutes()).padStart(2, '0');
  byId('shadedate').textContent =
    d.toLocaleDateString(undefined, { weekday: 'long', day: 'numeric', month: 'long' });
  shadeManage = false;
  renderShade();
  byId('shade').classList.add('on');
}

// The app a notification belongs to, resolved to something printable.
function appOf(id) {
  return (state.apps || available || []).find((a) => a.id === id)
      || (available || []).find((a) => a.id === id) || { id, label: id, icon: id };
}

function renderShade() {
  const sh = byId('shade');
  sh.classList.toggle('manage', shadeManage);
  byId('shtitle').textContent = L('ph.notifs');
  const mng = byId('shmanage'), clr = byId('shclear');
  mng.textContent = shadeManage ? L('ph.notif_done') : L('ph.notif_manage');
  clr.textContent = L('ph.clear_all');
  clr.classList.toggle('hidden', !notifs.length || shadeManage);

  const list = byId('shadelist');
  if (!notifs.length) { list.innerHTML = '<div class="nempty">' + esc(L('ph.notif_empty')) + '</div>'; return; }

  // Grouped by app, groups in the order their newest notification arrived.
  const order = [], byApp = {};
  notifs.forEach((n) => { if (!byApp[n.app]) { byApp[n.app] = []; order.push(n.app); } byApp[n.app].push(n); });

  list.innerHTML = order.map((appId) => {
    const a = appOf(appId);
    const muted = appMuted(appId);
    const head = '<div class="ngrouphead">' + UI.appIcon(a.icon) +
      '<span class="gname">' + esc(L(a.label) || a.id) + '</span>' +
      (shadeManage ? '<button class="gmute ' + (muted ? 'on' : '') + '" data-mute="' + esc(appId) + '">' +
        esc(muted ? L('ph.notif_muted') : L('ph.notif_mute_app')) + '</button>' : '') + '</div>';
    const cards = byApp[appId].map((n) =>
      '<div class="ncard" data-nid="' + n.id + '">' +
        '<span class="nic">' + UI.appIcon(n.icon) + '</span>' +
        '<span class="nbody"><span class="nt">' + esc(n.title) + '</span>' +
        '<span class="nb">' + esc(n.body) + '</span></span>' +
        '<span class="nw">' + esc(relTime(n.at)) + '</span>' +
        '<button class="nx" data-x="' + n.id + '">' + svg('xmark') + '</button></div>').join('');
    return '<div class="ngroup">' + head + cards + '</div>';
  }).join('');

  qrows('shadelist', '.ncard', (c) => c.addEventListener('click', (e) => {
    if (e.target.closest('.nx')) return;
    if (shadeManage) return;
    const n = notifs.find((x) => String(x.id) === c.dataset.nid);
    byId('shade').classList.remove('on');
    if (n && n.onClick) n.onClick();
  }));
  qrows('shadelist', '.nx', (x) => x.addEventListener('click', (e) => {
    e.stopPropagation();
    notifs = notifs.filter((n) => String(n.id) !== x.dataset.x);
    paintNotifs(); renderShade();
  }));
  qrows('shadelist', '.gmute', (b) => b.addEventListener('click', async (e) => {
    e.stopPropagation();
    await setAppMuted(b.dataset.mute, !appMuted(b.dataset.mute));
    renderShade();
  }));
}

function openCC() { byId('cc').classList.add('on'); renderCC(); primeNowPlaying().then(() => { if (byId('cc').classList.contains('on')) renderCC(); }); }

byId('shmanage').addEventListener('click', () => { shadeManage = !shadeManage; renderShade(); });
byId('shclear').addEventListener('click', () => { notifs = []; paintNotifs(); renderShade(); });

// ══ Side buttons ═══════════════════════════════════════════════
// Real controls, not decoration. Volume moves the volume of whatever v-music says this
// player may control; if nothing is playing it says so rather than pretending.
let hudTimer = null;

function hud(icon, label, pct) {
  const el = byId('hud');
  el.innerHTML = svg(icon) + '<span>' + esc(label) + '</span>' +
    (pct === undefined ? '' : '<span class="bar"><i style="width:' + Math.round(pct * 100) + '%"></i></span>');
  el.classList.add('on');
  clearTimeout(hudTimer);
  hudTimer = setTimeout(() => el.classList.remove('on'), 1400);
}

let volume = 0.5;

async function nudgeVolume(delta) {
  const d = await post('app', { app: 'music' });
  const list = (d && d.sources) || [];
  if (!list.length) { hud('speaker', L('ph.nothing_playing')); return; }
  const src = list[0];
  volume = Math.max(0, Math.min(1, (src.volume ?? volume) + delta));
  hud('speaker', src.title || L('ph.untitled'), volume);
  await post('music', { id: src.id, action: 'volume', volume });
}

function wireSideButtons() {
  // Power: lock and wake, the way the real button behaves.
  document.querySelector('.btn-side.power').addEventListener('click', () => {
    if (byId('lock').classList.contains('out')) { closeOverlays(); lockScreen(); }
    else unlock();
  });
  document.querySelector('.btn-side.vol-up').addEventListener('click', () => nudgeVolume(0.1));
  document.querySelector('.btn-side.vol-down').addEventListener('click', () => nudgeVolume(-0.1));

  // Action button: opens whichever app the player chose in Settings. Unset, it says so
  // instead of quietly doing nothing.
  document.querySelector('.btn-side.action').addEventListener('click', () => {
    const id = (state.prefs || {}).actionApp;
    const a = id && (state.apps || []).find((x) => x.id === id);
    if (!a) { hud('settings', L('ph.action_unset')); return; }
    if (!byId('lock').classList.contains('out')) unlock();
    closeOverlays();
    enterApp(a, null);
  });
}

// ══ FruitStore ═════════════════════════════════════════════════
// Two decisions, kept apart: the OPERATOR decides what is available (Editor -> Phone
// apps), the PLAYER decides what to keep. The store can never conjure an app the operator
// has not permitted, and it refuses to remove the ones the phone needs to work.
// One page per app, like a store has. The description comes from the locale when the
// framework ships one, from RegisterApp's `desc` when a third party wrote one, and from
// an honest fallback when nobody did.
function descOf(a) {
  const k = 'ph.desc_' + a.id;
  const v = L(k);
  if (v !== k) return v;
  if (a.desc) return a.desc;
  return L('ph.desc_generic');
}

function storeDetail(a) {
  if (!openApp || openApp.id !== 'store') return;
  beginView();
  const has = isInstalled(a.id);
  setNav(L('app.store'), L('app.store'), null, () => {
    RENDER.store();
  });
  body(
    '<div class="sthead">' + UI.appIcon(a.icon) +
      '<div class="stinfo"><div class="stbig">' + esc(L(a.label)) + '</div>' +
      '<div class="stcat">' + esc(L('ph.cat_' + (a.category || 'utilities'))) + '</div>' +
      '<div class="stact">' +
        (a.required
          ? '<span class="stget have">' + esc(L('ph.store_required')) + '</span>'
          : (has
              ? '<button class="stget have" id="stopen" type="button">' + esc(L('ph.store_open')) + '</button>' +
                '<button class="stdel" id="stdel" type="button">' + esc(L('ph.store_delete')) + '</button>'
              : '<button class="stget" id="stget" type="button">' + esc(L('ph.store_install')) + '</button>')) +
      '</div></div></div>' +
    '<div class="group"><div class="stmeta">' +
      '<div><div class="mk">' + esc(L('ph.store_dev')) + '</div>' +
        '<div class="mv">' + esc(a.owner || 'iFruit') + '</div></div>' +
      '<div><div class="mk">' + esc(L('ph.store_cat')) + '</div>' +
        '<div class="mv">' + esc(L('ph.cat_' + (a.category || 'utilities'))) + '</div></div>' +
      '<div><div class="mk">' + esc(L('ph.store_state')) + '</div>' +
        '<div class="mv">' + esc(has ? L('ph.store_installed') : L('ph.store_get')) + '</div></div>' +
    '</div></div>' +
    '<div class="grouphead">' + esc(L('ph.about')) + '</div>' +
    '<div class="storedesc">' + esc(descOf(a)) + '</div>'
  );
  pushAnim();

  const so = byId('stopen');
  if (so) so.addEventListener('click', () => {
    const app = (state.apps || []).find((x) => x.id === a.id);
    if (app) enterApp(app, null);
  });
  const sg = byId('stget');
  if (sg) sg.addEventListener('click', async () => { if (await storeInstall(a.id, true)) storeDetail(a); });
  const sd = byId('stdel');
  if (sd) sd.addEventListener('click', async () => { if (await storeInstall(a.id, false)) storeDetail(a); });
}

let storeCat = 'all';

function isInstalled(id) { return (state.apps || []).some((x) => x.id === id); }

// Only the categories that actually have an app in them, in a fixed order so the store
// does not reshuffle itself every time somebody installs something.
const CAT_ORDER = ['social', 'finance', 'utilities', 'travel', 'work', 'duty',
                   'entertainment', 'health', 'essentials'];

function storeCats(all) {
  const present = new Set(all.map((a) => a.category || 'utilities'));
  return CAT_ORDER.filter((c) => present.has(c));
}

async function storeInstall(id, install) {
  // The arrangement you already have is yours. Without this the new app landed wherever
  // its slot said, shoving every icon after it along and spilling the last one onto a new
  // page - which is not what installing one app should do to a home screen.
  const before = layoutItems();

  const r = await post('install', { app: id, install });
  if (!r || r.error) { toast(L('ph.err_' + ((r && r.error) || 'x'))); return false; }
  await refresh();
  available = state.available || available;

  // Keep the old order exactly, drop anything that left, and put anything new on the end -
  // so it fills the gap on the last page, or starts a new one when there is no room.
  const live = new Set((state.apps || []).filter((a) => !a.dock).map((a) => a.id));
  const kept = before.filter((it) => it.t === 'folder'
    ? (it.apps || []).some((x) => live.has(x))
    : live.has(it.id));
  const seen = new Set();
  kept.forEach((it) => { if (it.t === 'folder') (it.apps || []).forEach((x) => seen.add(x)); else seen.add(it.id); });
  const added = [...live].filter((x) => !seen.has(x)).map((x) => ({ t: 'app', id: x }));
  if (added.length || kept.length !== before.length) await saveLayout(kept.concat(added));

  renderHome();
  toast(L(install ? 'ph.store_added' : 'ph.store_removed'));
  return true;
}

function storeRow(a) {
  const has = isInstalled(a.id);
  const label = a.required ? L('ph.store_required')
    : (has ? L('ph.store_open') : L('ph.store_install'));
  return '<div class="strowitem" data-app="' + esc(a.id) + '">' + UI.appIcon(a.icon) +
    '<div class="stmid"><div class="stt">' + esc(L(a.label)) + '</div>' +
    '<div class="stc">' + esc(L('ph.cat_' + (a.category || 'utilities'))) + '</div></div>' +
    '<button class="stget ' + (has || a.required ? 'have' : '') + '" data-act="' +
      (a.required ? 'none' : (has ? 'open' : 'get')) + '" type="button">' + esc(label) + '</button></div>';
}

RENDER.store = () => {
  setNav(L('app.store'), null);

  // Deduplicated by id: the registry is a config seed merged with the operator's rows, and
  // a duplicate there used to surface as the same app listed twice in the store.
  const byIdSeen = new Set();
  const all = (available || [])
    .filter((a) => a && a.id && !byIdSeen.has(a.id) && byIdSeen.add(a.id))
    .sort((a, b) => (a.slot || 99) - (b.slot || 99));
  if (!all.length) { body(UI.empty(L('ph.store_empty'), 'store')); return; }

  // The featured slot goes to something you do NOT have yet: a shop window showing what
  // you already own is a shelf, not a window.
  const cats = storeCats(all);

  body(
    searchHtml(L('ph.store_search')) +
    '<div class="seg scroll">' +
      '<button class="' + (storeCat === 'all' ? 'on' : '') + '" data-c="all">' + esc(L('ph.all')) + '</button>' +
      cats.map((c) => '<button class="' + (storeCat === c ? 'on' : '') + '" data-c="' + esc(c) + '">' +
        esc(L('ph.cat_' + c)) + '</button>').join('') +
    '</div><div id="stbody"></div>'
  );

  const wire = () => {
    rows('.stfeat, .strowitem', (el) => el.addEventListener('click', (e) => {
      if (e.target.closest('.stget')) return;
      const a = all.find((x) => x.id === el.dataset.app);
      if (a) storeDetail(a);
    }));
    rows('.stget', (b) => b.addEventListener('click', async (e) => {
      e.stopPropagation();
      const act = b.dataset.act;
      if (act === 'none') return;
      const id = b.closest('[data-app]').dataset.app;
      if (act === 'open') {
        const app = (state.apps || []).find((x) => x.id === id);
        if (app) enterApp(app, null);
        return;
      }
      if (await storeInstall(id, true)) paint(byId('q') ? byId('q').value.trim().toLowerCase() : '');
    }));
  };

  const paint = (q) => {
    const shown = storeCat === 'all' ? all : all.filter((a) => (a.category || 'utilities') === storeCat);
    const list = q ? all.filter((a) => L(a.label).toLowerCase().includes(q)) : shown;
    let html = '';

    // Recomputed on every paint, never captured once: installing the featured app used to
    // leave it in the window still offering something you now own. If there is nothing
    // left to get, the window goes away rather than advertising your own apps back at you.
    const feat = all.find((a) => a.optional && !isInstalled(a.id))
              || all.find((a) => !a.required && !isInstalled(a.id))
              || null;
    if (!q && storeCat === 'all' && feat) {
      html += '<div class="stfeat" data-app="' + esc(feat.id) + '">' +
        '<div class="stkick">' + esc(L('ph.store_featured')) + '</div>' +
        '<div class="strow">' + UI.appIcon(feat.icon) +
        '<div><div class="stname">' + esc(L(feat.label)) + '</div>' +
        '<div class="stsub">' + esc(descOf(feat)) + '</div></div></div></div>';
    }

    if (!list.length) {
      byId('stbody').innerHTML = html + UI.empty(L('ph.store_none'), 'store');
      wire(); return;
    }

    if (q || storeCat !== 'all') {
      html += '<div class="group" style="padding:0 14px">' + list.map(storeRow).join('') + '</div>';
    } else {
      cats.forEach((c) => {
        const inCat = list.filter((a) => (a.category || 'utilities') === c);
        if (!inCat.length) return;
        html += '<div class="stsection">' + esc(L('ph.cat_' + c)) + '</div>' +
          '<div class="group" style="padding:0 14px;margin-bottom:20px">' +
          inCat.map(storeRow).join('') + '</div>';
      });
    }
    byId('stbody').innerHTML = html;
    wire();
  };

  [...byId('appbody').querySelectorAll('.seg button')].forEach((b) =>
    b.addEventListener('click', () => { storeCat = b.dataset.c; RENDER.store(); }));
  paint('');
  onSearch(paint);
};

// -- Health -----------------------------------------------------
// v-status already tracks every one of these. A second copy here would drift the first
// time either side changed, so this reads and never stores.
function ringHtml(label, value, max, colour) {
  const pct = Math.max(0, Math.min(1, (Number(value) || 0) / max));
  const C = 2 * Math.PI * 31;
  return '<div class="ring"><div class="dial">' +
    '<svg viewBox="0 0 78 78"><circle class="bg" cx="39" cy="39" r="31"/>' +
    '<circle cx="39" cy="39" r="31" stroke="' + colour + '" stroke-dasharray="' + C + '" ' +
    'stroke-dashoffset="' + (C * (1 - pct)) + '"/></svg>' +
    '<span class="val">' + Math.round(pct * 100) + '</span></div>' +
    '<div class="lab">' + esc(label) + '</div></div>';
}

let healthTab = 'today';

RENDER.health = async () => {
  tabbar([
    { id: 'today', icon: 'heart', label: 'ph.today' },
    { id: 'record', icon: 'id', label: 'ph.record' },
  ], healthTab, (t) => { healthTab = t; RENDER.health(); });
  if (healthTab === 'record') { healthRecord(); return; }
  loading();
  const d = await post('health');
  if (!d || d.error) { body(UI.empty(L('ph.err_off'), 'heart')); return; }
  const rows = [];
  if (d.bleed > 0) rows.push(UI.row({ icon: 'heart', tint: '#FF3B30', title: L('ph.bleeding'), value: String(d.bleed), tone: 'neg' }));
  if (d.sick > 0) rows.push(UI.row({ icon: 'heart', tint: '#FF3B30', title: L('ph.illness'), value: String(d.sick), tone: 'neg' }));
  body(
    '<div class="rings">' +
      ringHtml(L('ph.vitality'), d.health, 100, '#ff453a') +
      ringHtml(L('ph.armour'), d.armour, 100, '#0a84ff') +
      ringHtml(L('ph.hunger'), d.hunger, 100, '#ff9f0a') +
      ringHtml(L('ph.thirst'), d.thirst, 100, '#64d2ff') +
    '</div>' +
    ringHtml(L('ph.stress'), d.stress, 100, '#bf5af2').replace('class="ring"', 'class="ring" style="margin-bottom:20px"') +
    (rows.length ? UI.group(rows, { header: L('ph.attention') })
                 : UI.group([UI.row({ icon: 'heart', tint: '#FF3B30', title: L('ph.all_well') })]))
  );
};

// -- Reminders --------------------------------------------------
// Owned by the phone, and stored the same way a third-party app would store it: through
// the per-app storage the SDK exposes. If the example app's path were not good enough
// for a built-in one, it would not be good enough to hand to anybody else either.
let reminders = null;

async function loadReminders() {
  if (reminders) return reminders;
  const r = await post('appStorage', { app: 'reminders', op: 'get', key: 'items' });
  try { reminders = JSON.parse((r && r.value) || '[]') || []; } catch { reminders = []; }
  return reminders;
}

function saveReminders() {
  return post('appStorage', { app: 'reminders', op: 'set', key: 'items', value: JSON.stringify(reminders) });
}

RENDER.reminders = async () => {
  setNav(L('app.reminders'), null, { icon: 'add', onClick: () => {
    sheet(L('ph.new_reminder'), UI.field('rtext', L('ph.reminder_ph')) + UI.button(L('ph.save'), 'rsave'),
      () => byId('rsave').addEventListener('click', async () => {
        const v = byId('rtext').value.trim();
        if (!v) return;
        reminders.unshift({ t: v, done: false });
        await saveReminders(); closeSheet(); RENDER.reminders();
      }));
  } });
  await loadReminders();
  if (!reminders.length) { body(UI.empty(L('ph.no_reminders'), 'check')); return; }
  const open = reminders.filter((r) => !r.done);
  const done = reminders.filter((r) => r.done);
  body(
    (open.length ? UI.group(open.map((r) => UI.row({
      icon: 'check', tint: '#FF9500', title: r.t, data: { i: reminders.indexOf(r) },
    })), { header: L('ph.to_do') }) : '') +
    (done.length ? UI.group(done.map((r) => UI.row({
      icon: 'check', tint: '#FF9500', title: r.t, value: L('ph.done'), tone: 'pos', data: { i: reminders.indexOf(r) },
    })), { header: L('ph.done') }) : '')
  );
  rows('.row[data-i]', (el) => el.addEventListener('click', async () => {
    const r = reminders[Number(el.dataset.i)];
    if (!r) return;
    // Ticking a done one removes it: a list you can never shorten stops being a list.
    if (r.done) reminders.splice(Number(el.dataset.i), 1); else r.done = true;
    await saveReminders(); RENDER.reminders();
  }));
};

// -- Camera -----------------------------------------------------
// Real, and only as real as the operator made it: with no upload target configured there
// is nowhere for a photo to go, and the app says so rather than pretending to save one.
// The camera, drawn like the iOS one: a black viewfinder with framing marks, a shutter
// ring, the last shot as a roll thumbnail, and a control to lay the phone on its side.
RENDER.camera = async () => {
  if (!state.camera) { body(UI.empty(L('ph.camera_off'), 'camera')); return; }
  const d = await post('photos', { op: 'list' });
  const shots = (d && d.photos) || [];
  const last = shots[0];

  // Immersive: no title bar, no padding, the black fills the screen edge to edge.
  byId('navbar').classList.add('hidden');
  byId('app').classList.add('camfull');

  body(
    '<div class="camui">' +
      '<div class="camtop">' +
        '<button class="camchip back" id="camback" type="button">' + svg('chevron') + '</button>' +
        '<button class="camchip ' + (landscape ? 'on' : '') + '" id="camland" type="button">' + svg('landscape') + '</button>' +
      '</div>' +
      '<div class="camview">' +
        '<span class="cammark tl"></span><span class="cammark tr"></span>' +
        '<span class="cammark bl"></span><span class="cammark br"></span>' +
        '<div class="camgrid"></div>' +
        '<div class="camhint">' + esc(L('ph.vf_hint')) + '</div>' +
      '</div>' +
      '<div class="cammode"><span class="on">' + esc(L('ph.cam_photo')) + '</span></div>' +
      '<div class="camctl">' +
        (last ? '<button class="camroll" id="camroll" type="button" style="' + photoStyle(last) + '"></button>'
              : '<span class="camroll empty"></span>') +
        '<button class="camshutter" id="shoot" type="button"><span></span></button>' +
        '<button class="camflip" id="camland2" type="button">' + svg('landscape') + '</button>' +
      '</div>' +
    '</div>'
  );

  byId('shoot').addEventListener('click', async () => {
    toast(L('ph.shooting'));
    const res = await post('shoot');
    if (!res || res.error) { toast(L('ph.err_' + ((res && res.error) || 'x'))); return; }
    RENDER.camera();
  });
  byId('camback').addEventListener('click', () => closeApp());
  const toggle = () => { setLandscape(!landscape); RENDER.camera(); };
  byId('camland').addEventListener('click', toggle);
  byId('camland2').addEventListener('click', toggle);
  const roll = byId('camroll');
  if (roll) roll.addEventListener('click', () => {
    const a = (state.apps || []).find((x) => x.id === 'gallery');
    if (a) enterApp(a, null); else photoSheet(shots, 0);
  });
};

// The Gallery: every photo, tap to view, and from there set it as wallpaper, AirDrop it,
// or delete it. Same store as the camera - one shoots, one keeps.
let galleryAlbum = '';     // '' is everything

RENDER.gallery = async () => {
  const d = await post('photos', { op: 'list' });
  const shots = (d && d.photos) || [];
  const albums = (d && d.albums) || [];
  setNav(L('app.gallery'), null);
  if (!shots.length) { body(UI.empty(L('ph.no_photos'), 'images')); return; }

  // Albums are worked out from the photos, so the strip can never list one that is empty.
  const strip = '<div class="seg scroll" id="galbums">' +
    '<button class="' + (galleryAlbum === '' ? 'on' : '') + '" data-a="">' + esc(L('ph.all_photos')) + '</button>' +
    albums.map((a) => '<button class="' + (galleryAlbum === a ? 'on' : '') + '" data-a="' + esc(a) + '">' +
      esc(a) + '</button>').join('') + '</div>';

  const shown = shots.map((v, i) => ({ v: photoRow(v), i }))
    .filter((x) => galleryAlbum === '' || x.v.album === galleryAlbum);

  body(strip + (shown.length
    ? '<div class="shots">' + shown.map((x) =>
        '<div class="shot" data-i="' + x.i + '" style="' + photoStyle(x.v) + '"></div>').join('') + '</div>'
    : UI.empty(L('ph.album_empty'), 'images')));

  qrows('galbums', 'button', (b) => b.addEventListener('click', () => {
    galleryAlbum = b.dataset.a; RENDER.gallery();
  }));
  rows('.shot', (el) => el.addEventListener('click', () => photoSheet(shots, Number(el.dataset.i), albums)));
};

function photoSheet(shots, i, albums) {
  const r = photoRow(shots[i]);
  const url = r.url;
  sheet(L('app.gallery'),
    '<img class="shotbig" id="shotbig" src="' + esc(url) + '" style="filter:' + filterCss(r.filter) + '" />' +
    // Retouching: pick a look, it applies live and is remembered with the photo.
    '<div class="grouphead">' + esc(L('ph.filters')) + '</div>' +
    '<div class="seg scroll" id="sfilters">' + FILTERS.map((f) =>
      '<button class="' + ((r.filter || 'none') === f ? 'on' : '') + '" data-f="' + f + '">' +
      esc(L('ph.filter_' + f)) + '</button>').join('') + '</div>' +
    UI.button(L('ph.album_set'), 'salbum', 'plain') +
    UI.button(L('ph.airdrop_share'), 'sshare', 'tinted') +
    UI.button(L('ph.set_wallpaper'), 'swall') +
    UI.button(L('ph.delete'), 'sdel', 'destructive'),
    () => {
      [...byId('sheet').querySelectorAll('#sfilters button')].forEach((b) =>
        b.addEventListener('click', async () => {
          const f = b.dataset.f;
          byId('shotbig').style.filter = filterCss(f);
          [...byId('sfilters').querySelectorAll('button')].forEach((x) => x.classList.toggle('on', x === b));
          await post('photos', { op: 'edit', index: i + 1, filter: f === 'none' ? '' : f });
        }));
      byId('salbum').addEventListener('click', () => {
        const list = (albums || []).slice();
        sheet(L('ph.album_set'),
          UI.field('albname', L('ph.album_name'), r.album || '', 'maxlength="40"') +
          UI.button(L('ph.save'), 'albgo', 'tinted') +
          (list.length ? UI.group(list.map((a) => UI.row({ icon: 'folder', title: a, data: { alb: a } }))) : ''),
          () => {
            byId('albgo').addEventListener('click', async () => {
              await post('photos', { op: 'edit', index: i + 1, album: byId('albname').value.trim() });
              closeSheet(); RENDER.gallery();
            });
            [...byId('sheet').querySelectorAll('.row')].forEach((el) => el.addEventListener('click', async () => {
              await post('photos', { op: 'edit', index: i + 1, album: el.dataset.alb });
              closeSheet(); RENDER.gallery();
            }));
          });
      });
      byId('sshare').addEventListener('click', () => airdropShare('photo', { url }));
      byId('swall').addEventListener('click', async () => {
        const r = await post('prefs', { wallpaperUrl: url });
        closeSheet();
        if (r && r.ok) { state.prefs = r.prefs; applyWallpaper(); toast(L('ph.wall_set')); }
        else toast(L('ph.err_' + ((r && r.error) || 'x')));
      });
      byId('sdel').addEventListener('click', async () => {
        await post('photos', { op: 'del', index: i + 1 });
        closeSheet();
        toast(L('ph.photo_deleted'));
        if (openApp && openApp.id === 'gallery') RENDER.gallery(); else RENDER.camera();
      });
    });
}

// ══ AirDrop ════════════════════════════════════════════════════
// Pick a nearby device and send. The scan and the send are both gated server-side on
// Bluetooth and range, so this only ever draws what the server says is reachable.
function airdropShare(kind, payload) {
  sheet(L('ph.airdrop'),
    '<div class="airhint">' + esc(L('ph.airdrop_hint')) + '</div><div id="airlist"></div>',
    async () => {
      const host = byId('airlist');
      host.innerHTML = '<div class="airscan">' + esc(L('ph.airdrop_scanning')) + '</div>';
      const r = await post('airdropScan');
      if (byId('airlist') !== host || !host.isConnected) return;
      if (!r || r.error) { host.innerHTML = UI.empty(L('ph.airdrop_' + ((r && r.error) || 'x')), 'airdrop'); return; }
      const devs = r.devices || [];
      if (!devs.length) { host.innerHTML = UI.empty(L('ph.airdrop_none'), 'airdrop'); return; }
      host.innerHTML = UI.group(devs.map((dv) => UI.row({
        icon: 'airdrop', tint: '#0A84FF', title: dv.name, subtitle: L('ph.airdrop_nearby'),
        chevron: true, data: { to: dv.id },
      })));
      [...host.querySelectorAll('.row')].forEach((el) => el.addEventListener('click', async () => {
        const to = Number(el.dataset.to);
        closeSheet();
        const res = await post('airdropSend', { to, kind, payload });
        toast(res && res.ok ? L('ph.airdrop_sent') : L('ph.airdrop_' + ((res && res.error) || 'x')));
      }));
    });
}

// The receiver's prompt. Nothing is written until they accept.
function airdropOffer(o) {
  o = o || {};
  const preview = o.kind === 'photo'
    ? '<img class="shotbig" src="' + esc(o.preview || '') + '" />'
    : '<div class="airbig">' + svg(o.kind === 'photo' ? 'images' : 'contacts') + '<span>' + esc(o.preview || '') + '</span></div>';
  sheet(L('ph.airdrop_incoming'),
    preview +
    '<div class="airfrom">' + esc(L('ph.airdrop_from')) + ' <b>' + esc(o.from || '') + '</b></div>' +
    UI.button(L('ph.airdrop_accept'), 'airok', 'tinted') +
    UI.button(L('ph.airdrop_decline'), 'airno', 'plain'),
    () => {
      byId('airok').addEventListener('click', async () => {
        closeSheet();
        const r = await post('airdropRespond', { offerId: o.offerId, accept: true });
        if (r && r.ok) { await refresh(); toast(L('ph.airdrop_saved')); }
        else toast(L('ph.airdrop_' + ((r && r.error) || 'x')));
      });
      byId('airno').addEventListener('click', async () => {
        closeSheet();
        await post('airdropRespond', { offerId: o.offerId, accept: false });
      });
    });
}


// ══ Clipboard ══════════════════════════════════════════════════
// navigator.clipboard needs a secure context, and cfx-nui:// is not one, so this is the
// textarea trick. It is the only thing that works in CEF, and a number you cannot copy
// is a number you have to read out loud.
function copyText(text, said) {
  // The page is served from https://cfx-nui-<resource>/, which CEF treats as a secure
  // context, so the real clipboard API is available. The textarea trick stays as the
  // fallback: it is the only thing that works when it is not.
  if (navigator.clipboard && navigator.clipboard.writeText) {
    navigator.clipboard.writeText(text)
      .then(() => toast(said || L('ph.copied')))
      .catch(() => legacyCopy(text, said));
    return true;
  }
  return legacyCopy(text, said);
}

function legacyCopy(text, said) {
  const ta = document.createElement('textarea');
  ta.value = text;
  ta.setAttribute('readonly', '');
  ta.style.cssText = 'position:absolute;left:-9999px;opacity:0';
  document.body.appendChild(ta);
  ta.select();
  ta.setSelectionRange(0, ta.value.length);
  let ok = false;
  try { ok = document.execCommand('copy'); } catch { ok = false; }
  document.body.removeChild(ta);
  toast(ok ? (said || L('ph.copied')) : L('ph.copy_failed'));
  return ok;
}

// ══ Search field ═══════════════════════════════════════════════
function searchHtml(placeholder) {
  return '<div class="search">' + svg('search') +
    '<input id="q" placeholder="' + esc(placeholder) + '" autocomplete="off" /></div>';
}

function onSearch(fn) {
  const q = byId('q');
  if (!q) return;
  q.addEventListener('input', () => fn(q.value.trim().toLowerCase()));
}

// ══ Tab bar ════════════════════════════════════════════════════
function tabbar(tabs, current, onPick) {
  foot('<div class="tabbar">' + tabs.map((t) =>
    '<button class="' + (t.id === current ? 'on' : '') + '" data-t="' + esc(t.id) + '" type="button">' +
    svg(t.icon) + '<span>' + esc(L(t.label)) + '</span></button>').join('') + '</div>');
  [...byId('appfoot').querySelectorAll('button')].forEach((b) =>
    b.addEventListener('click', () => onPick(b.dataset.t)));
}


// ══ Social ═════════════════════════════════════════════════════
// Three views over v-social. The account gate is shared: none of them work without a
// handle, and the handle is the identity every post travels under.
// One account PER APP, because that is how the real ones work: your Bleeter handle is
// not your Snapmatic handle unless you choose it twice.
const socialAcc = {};
function clearSocialAccounts() {
  Object.keys(socialAcc).forEach((app) => { delete socialAcc[app]; });
}

const APP_ICON = { bleeter: 'bleet', snap: 'snap', hush: 'hush' };
const socialActive = (app, epoch) =>
  !!openApp && openApp.id === app && (epoch == null || epoch === viewEpoch);

// A real account gate: a live session either opens the app, asks for a password, or runs
// the sign-up wizard, decided by whether an account exists and whether you are logged in.
async function needAccount(app, then) {
  const epoch = viewEpoch;
  if (!socialActive(app, epoch)) return;
  if (socialAcc[app]) { then(); return; }
  const r = await post('social', { op: 'me', app });
  if (!socialActive(app, epoch)) return;
  if (!r || r.error) { body(UI.empty(L('ph.err_' + ((r && r.error) || 'off')), APP_ICON[app] || 'bleet')); return; }
  if (r.authed && r.account) { socialAcc[app] = r.account; then(); return; }
  if (r.exists) { socialLogin(app, then); return; }
  socialSignup(app, then);
}

// The account header: the app's icon and name over a form, so every screen of the flow
// looks like it belongs to the app you are joining.
function acctHead(app, sub) {
  return '<div class="accthead">' + UI.appIcon(APP_ICON[app] || 'bleet') +
    '<div class="acctname">' + esc(L('app.' + app)) + '</div>' +
    (sub ? '<div class="acctsub">' + esc(sub) + '</div>' : '') + '</div>';
}

// Returning to a registered account: unlock it with the password.
function socialLogin(app, then) {
  const epoch = viewEpoch;
  if (!socialActive(app, epoch)) return;
  body(
    acctHead(app, L('ph.soc_login_sub')) +
    UI.field('lpw', L('ph.soc_password'), '', 'type="password" maxlength="40"') +
    UI.button(L('ph.soc_signin'), 'lgo') +
    '<button class="linkbtn" id="lforget" type="button">' + esc(L('ph.soc_switch')) + '</button>'
  );
  byId('lgo').addEventListener('click', async () => {
    const r = await post('social', { op: 'login', app, password: byId('lpw').value });
    if (r && r.ok) socialAcc[app] = r.account;
    if (!socialActive(app, epoch)) return;
    if (r && r.ok) then();
    else toast(L('ph.err_' + ((r && r.error) || 'x')));
  });
  // "Not you?" logs the stored account out for this session and starts a fresh sign-up.
  byId('lforget').addEventListener('click', async () => {
    await post('social', { op: 'logout', app });
    if (!socialActive(app, epoch)) return;
    socialSignup(app, then);
  });
}

// Sign-up: number -> texted code -> username, display name and password. Three steps, a
// progress line, and nothing skippable - the account the network knows you by is built
// here, not guessed.
function socialSignup(app, then) {
  const epoch = viewEpoch;
  if (!socialActive(app, epoch)) return;
  const st = { step: 1, number: '' };
  const steps = 3;
  const prog = (n) => '<div class="signprog">' + esc(L('ph.soc_step')) + ' ' + n + '/' + steps + '</div>';

  const render = () => {
    if (!socialActive(app, epoch)) return;
    if (st.step === 1) {
      body(
        acctHead(app, L('ph.soc_join_sub')) + prog(1) +
        UI.group([UI.row({ icon: 'phone', tint: '#34C759', title: L('ph.soc_number'),
          value: state.number || L('ph.soc_no_number') })]) +
        UI.button(L('ph.soc_sendcode'), 'sc1') +
        '<div class="groupfoot">' + esc(L('ph.soc_number_hint')) + '</div>'
      );
      byId('sc1').addEventListener('click', async () => {
        const r = await post('social', { op: 'requestCode', app });
        if (!socialActive(app, epoch)) return;
        if (r && r.ok) { st.number = r.number; st.step = 2; render(); toast(L('ph.soc_code_sent')); }
        else toast(L('ph.err_' + ((r && r.error) || 'x')));
      });
    } else if (st.step === 2) {
      body(
        acctHead(app, L('ph.soc_code_sub') + ' ' + (st.number || '')) + prog(2) +
        UI.field('scode', L('ph.soc_code'), '', 'maxlength="4" inputmode="numeric"') +
        UI.button(L('ph.soc_verify'), 'sc2') +
        '<button class="linkbtn" id="sc2r" type="button">' + esc(L('ph.soc_resend')) + '</button>'
      );
      byId('scode').focus();
      byId('sc2').addEventListener('click', async () => {
        const r = await post('social', { op: 'verifyCode', app, code: byId('scode').value.trim() });
        if (!socialActive(app, epoch)) return;
        if (r && r.ok) { st.step = 3; render(); }
        else toast(L('ph.err_' + ((r && r.error) || 'x')));
      });
      byId('sc2r').addEventListener('click', async () => {
        const r = await post('social', { op: 'requestCode', app });
        if (!socialActive(app, epoch)) return;
        if (r && r.ok) { st.number = r.number; toast(L('ph.soc_code_sent')); }
        else toast(L('ph.err_' + ((r && r.error) || 'x')));
      });
    } else {
      body(
        acctHead(app, L('ph.soc_profile_sub')) + prog(3) +
        UI.field('shandle', L('ph.soc_identifier'), '', 'maxlength="20"') +
        UI.field('sdisplay', L('ph.soc_pseudo'), '', 'maxlength="40"') +
        UI.field('spw', L('ph.soc_password'), '', 'type="password" maxlength="40"') +
        UI.field('spw2', L('ph.soc_password2'), '', 'type="password" maxlength="40"') +
        UI.field('savatar', L('ph.soc_avatar'), '', 'maxlength="300"') +
        UI.field('sbio', L('ph.soc_bio'), '', 'maxlength="160"') +
        UI.button(L('ph.soc_create'), 'smake') +
        '<div class="groupfoot">' + esc(L('ph.soc_identifier_hint')) + '</div>'
      );
      byId('smake').addEventListener('click', async () => {
        if (byId('spw').value !== byId('spw2').value) { toast(L('ph.soc_pw_mismatch')); return; }
        const r = await post('social', { op: 'register', app,
          handle: byId('shandle').value.trim(), displayname: byId('sdisplay').value.trim(),
          password: byId('spw').value, avatar: byId('savatar').value.trim(), bio: byId('sbio').value.trim() });
        if (r && r.ok) socialAcc[app] = r.account;
        if (!socialActive(app, epoch)) return;
        if (r && r.ok) { toast(L('ph.soc_made')); then(); }
        else toast(L('ph.err_' + ((r && r.error) || 'x')));
      });
    }
  };
  render();
}

function postCard(pst) {
  const av = pst.avatar
    ? '<span class="pav" style="' + inlineBackground(pst.avatar) + '"></span>'
    : '<span class="pav">' + esc(String(pst.handle || '?').slice(0, 1).toUpperCase()) + '</span>';
  return '<div class="post" data-id="' + pst.id + '">' +
    '<div class="phead">' + av +
      '<span class="pnames">' +
        (pst.displayname ? '<span class="pdn">' + esc(pst.displayname) + '</span>' : '') +
        '<span class="ph">@' + esc(pst.handle) + '</span></span>' +
      '<span class="pt">' + esc(String(pst.at || '').slice(5, 16)) + '</span></div>' +
    (pst.body ? '<div class="pbody">' + esc(pst.body) + '</div>' : '') +
    (pst.image ? '<img class="pimg" src="' + esc(pst.image) + '" />' : '') +
    '<div class="pfoot"><button class="plike ' + (pst.liked ? 'on' : '') + '" type="button">' +
      svg('heart') + '<span>' + (pst.likes || 0) + '</span></button></div></div>';
}

function wireLikes() {
  rows('.post .plike', (b) => b.addEventListener('click', async () => {
    const id = Number(b.closest('.post').dataset.id);
    const r = await post('social', { op: 'like', id });
    if (r && r.ok) {
      b.classList.toggle('on', r.liked);
      b.querySelector('span').textContent = r.likes;
    }
  }));
}

async function socialFeed(kind, emptyKey) {
  const appId = kind === 'photo' ? 'snap' : 'bleeter';
  if (!openApp || openApp.id !== appId) return;
  beginView();
  loading();
  const r = await post('social', { op: 'feed', kind });
  if (!r || r.error) { body(UI.empty(L('ph.err_' + ((r && r.error) || 'x')), 'bleet')); return; }
  const list = r.posts || [];
  body(list.length ? list.map(postCard).join('') : UI.empty(L(emptyKey), kind === 'photo' ? 'snap' : 'bleet'));
  wireLikes();
}

// -- Bleeter ----------------------------------------------------
RENDER.bleeter = () => needAccount('bleeter', async () => {
  setNav(L('app.bleeter'), null, { icon: 'add', onClick: () => {
    sheet(L('ph.bleet_new'),
      UI.field('btext', L('ph.bleet_ph'), '', 'maxlength="280"') +
        UI.button('😊 ' + L('ph.emoji'), 'bemoji', 'plain') +
        UI.button(L('ph.pick_photo'), 'bpick', 'plain') + UI.button(L('ph.bleet_send'), 'bgo'),
      () => {
        byId('bemoji').addEventListener('click', () => emojiOpen('btext'));
        // A post can carry a photo straight off the phone rather than a pasted link.
        byId('bpick').addEventListener('click', () => pickPhoto(async (url) => {
          const r = await post('social', { op: 'post', kind: 'photo', body: byId('btext').value, image: url });
          closeSheet();
          if (r && r.ok) RENDER.bleeter(); else toast(L('ph.err_' + ((r && r.error) || 'x')));
        }));
        byId('bgo').addEventListener('click', async () => {
          const r = await post('social', { op: 'post', kind: 'text', body: byId('btext').value });
          emojiClose(); closeSheet();
          if (r && r.ok) RENDER.bleeter(); else toast(L('ph.err_' + ((r && r.error) || 'x')));
        });
      });
  } });
  await socialFeed('text', 'ph.bleet_none');
});

// -- Snapmatic --------------------------------------------------
// Posting starts from the gallery, because that is where photos already are: the camera
// shoots, Snapmatic shows.
RENDER.snap = () => needAccount('snap', async () => {
  setNav(L('app.snap'), null, { icon: 'add', onClick: () => {
    const shots = state.photos || [];
    if (!shots.length) { toast(L('ph.snap_noshots')); return; }
    sheet(L('ph.snap_new'),
      '<div class="shots" style="margin-bottom:10px">' + shots.map((v, i) =>
        '<div class="shot" data-i="' + i + '" style="' + photoStyle(v) + '"></div>').join('') + '</div>' +
      UI.field('scap', L('ph.snap_caption'), '', 'maxlength="140"') +
        UI.button('😊 ' + L('ph.emoji'), 'semoji', 'plain'),
      () => {
        byId('semoji').addEventListener('click', () => emojiOpen('scap'));
        [...byId('sheet').querySelectorAll('.shot')].forEach((el) =>
          el.addEventListener('click', async () => {
            const r = await post('social', { op: 'post', kind: 'photo',
              image: photoRow(shots[Number(el.dataset.i)]).url, body: byId('scap').value });
            emojiClose(); closeSheet();
            if (r && r.ok) RENDER.snap(); else toast(L('ph.err_' + ((r && r.error) || 'x')));
          }));
      });
  } });
  await socialFeed('photo', 'ph.snap_none');
});

// -- Hush -------------------------------------------------------
RENDER.hush = () => needAccount('hush', hushMain);
async function hushMain() {
  if (!openApp || openApp.id !== 'hush') return;
  beginView();
  setNav(L('app.hush'), null);
  loading();
  const me = await post('social', { op: 'hushMe' });
  if (!me || me.error) { body(UI.empty(L('ph.err_' + ((me && me.error) || 'off')), 'hush')); return; }

  if (!me.profile) {
    // Hush has its own profile, because who you are to a date is not who you are to the
    // whole network. The photo defaults to the account avatar.
    body(
      UI.field('hbio', L('ph.hush_bio'), '', 'maxlength="160"') +
      UI.field('hphoto', L('ph.hush_photo'), '', 'maxlength="300"') +
      UI.button(L('ph.hush_join'), 'hgo') +
      '<div class="groupfoot">' + esc(L('ph.hush_hint')) + '</div>'
    );
    byId('hgo').addEventListener('click', async () => {
      const r = await post('social', { op: 'hushSetup', bio: byId('hbio').value, photo: byId('hphoto').value });
      if (r && r.ok) RENDER.hush(); else toast(L('ph.err_' + ((r && r.error) || 'x')));
    });
    return;
  }

  const r = await post('social', { op: 'hushNext' });
  if (!r || r.error) { body(UI.empty(L('ph.err_' + ((r && r.error) || 'x')), 'hush')); return; }
  const pf = r.profile;
  if (!pf) { body(UI.empty(L('ph.hush_empty'), 'hush')); return; }

  body(
    '<div class="hushcard">' +
      '<div class="hphoto"' + (pf.photo ? ' style="' + inlineBackground(pf.photo) + '"' : '') + '>' +
        '<div class="hname">' + esc(pf.name || '?') + (pf.age ? ', ' + pf.age : '') + '</div></div>' +
      (pf.bio ? '<div class="hbio">' + esc(pf.bio) + '</div>' : '') +
    '</div>' +
    '<div class="hushrow">' +
      '<button class="hushbtn no" id="hno" type="button">' + svg('del') + '</button>' +
      '<button class="hushbtn yes" id="hyes" type="button">' + svg('heart') + '</button>' +
    '</div>'
  );
  pushAnim();
  const choose = async (like) => {
    const c = await post('social', { op: 'hushChoice', ref: pf.ref, like });
    if (c && c.error) { toast(L('ph.err_' + ((c && c.error) || 'x'))); return; }
    if (c && c.match) {
      banner({ app: 'hush', icon: 'hush', title: L('ph.hush_match'),
               body: (c.name || '?') + (c.number ? '  ' + c.number : '') });
    }
    RENDER.hush();
  };
  byId('hno').addEventListener('click', () => choose(false));
  byId('hyes').addEventListener('click', () => choose(true));
};


// ══ Sound ══════════════════════════════════════════════════════
// Tones are made here rather than shipped: the built-ins are a few oscillator notes, so
// the resource carries no audio files and nothing is fetched at all unless a player has
// pointed a tone at their own MP3. That link is host-gated on the server.
let AC = null;
function audio() {
  if (!AC) { try { AC = new (window.AudioContext || window.webkitAudioContext)(); } catch { AC = false; } }
  if (AC && AC.state === 'suspended') AC.resume();
  return AC || null;
}

// One note. `t` is an offset in seconds so a tone can be written as a little score.
function note(freq, t, dur, gain, type) {
  const ac = audio(); if (!ac) return;
  const o = ac.createOscillator(), g = ac.createGain();
  o.type = type || 'sine';
  o.frequency.value = freq;
  const at = ac.currentTime + t;
  g.gain.setValueAtTime(0, at);
  g.gain.linearRampToValueAtTime(gain, at + 0.012);
  g.gain.exponentialRampToValueAtTime(0.0001, at + dur);
  o.connect(g); g.connect(ac.destination);
  o.start(at); o.stop(at + dur + 0.02);
}

// Each built-in is a short score: [frequency, start, length].
const TONES = {
  classic: [[880, 0, .16], [1175, .18, .16], [880, .36, .16], [1175, .54, .26]],
  chime:   [[1319, 0, .5], [1568, .12, .5], [2093, .24, .7]],
  pulse:   [[440, 0, .1], [440, .14, .1], [440, .28, .1], [660, .42, .3]],
  radar:   [[523, 0, .22], [659, .22, .22], [784, .44, .22], [1047, .66, .4]],
  ping:    [[1568, 0, .18], [2093, .07, .22]],
  pop:     [[880, 0, .09], [1320, .05, .12]],
  tick:    [[1200, 0, .05]],
};

let ringEl = null;      // the <audio> for a custom link, so it can be stopped
let ringTimer = null;

function stopTone() {
  if (ringEl) { try { ringEl.pause(); } catch {} ringEl = null; }
  clearInterval(ringTimer); ringTimer = null;
}

// Play one pass of a tone: a custom URL if there is one, otherwise the synthesised score.
function playTone(name, url, vol, loop) {
  const p = state.prefs || {};
  const v = vol == null ? (p.ringVolume ?? 0.7) : vol;
  if (v <= 0 || name === 'none') return;

  if (url) {
    try {
      const el = new Audio(url);
      el.volume = Math.max(0, Math.min(1, v));
      el.loop = !!loop;
      el.play().catch(() => {});
      if (loop) ringEl = el;
      return;
    } catch { /* fall through to the built-in */ }
  }
  const score = TONES[name] || TONES.classic;
  score.forEach(([f, t, d]) => note(f, t, d, 0.12 * v, 'sine'));
}

// A call rings until it is answered or gives up.
function playRingtone() {
  const p = state.prefs || {};
  stopTone();
  if (p.dnd) return;
  const name = p.ringtone || 'classic', url = p.ringUrl || null;
  playTone(name, url, p.ringVolume, true);
  if (!url) {
    playTone(name, null, p.ringVolume, false);
    ringTimer = setInterval(() => playTone(name, null, p.ringVolume, false), 1600);
  }
}
function stopRingtone() { stopTone(); }

// Everything that is not a call: a message, a mail, a notification.
function playAlert() {
  const p = state.prefs || {};
  if (p.dnd) return;
  playTone(p.alertTone || 'ping', p.alertUrl || null, p.ringVolume, false);
}

function syncDndAudio() {
  if ((state.prefs || {}).dnd) {
    stopRingtone();
    const island = byId('island');
    if (island && island.classList.contains('notif')) {
      clearTimeout(islandTimer);
      islandTimer = null;
      setIslandMode(null);
    }
    return;
  }
  if (call && call.state === 'in') playRingtone();
}

// ══ Buzz and peek ══════════════════════════════════════════════
// The handset shakes for a notification, and - when it is in a pocket rather than in the
// hand - the top of it rises into view carrying that notification, then slides back. The
// peek never takes focus: you are being shown something, not asked to do anything.
let buzzTimer = null, peekTimer = null;

function buzzDevice() {
  if ((state.prefs || {}).dnd) return;
  const d = byId('device');
  d.classList.remove('buzz');
  void d.offsetWidth;               // restart the animation rather than ignore a re-trigger
  d.classList.add('buzz');
  clearTimeout(buzzTimer);
  buzzTimer = setTimeout(() => d.classList.remove('buzz'), 700);
}

function showPeek(kind, data) {
  const d = byId('device');
  if (call || (state.prefs || {}).dnd) return;
  // No phone on them, nothing to lift out of a pocket. The client checks this too; it is
  // repeated here so the rule holds whoever sends the message.
  if (data && data.hasItem === false) return;
  if (!d.classList.contains('hidden') && !d.classList.contains('peeking')) return; // it is open
  const title = kind === 'message'
    ? (nameOfNumber(data.from) || L('ph.new_message_t'))
    : (data.title || L('ph.notification'));
  const bodyTxt = kind === 'message' ? (data.body || L('ph.attach')) : (data.body || '');

  d.classList.remove('hidden');
  d.classList.add('peeking');
  byId('inicon').innerHTML = UI.appIcon(kind === 'message' ? 'messages' : (data.app || data.icon || 'dot'));
  byId('inTitle').textContent = title;
  byId('inBody').textContent = bodyTxt;
  setIslandMode('notif');
  buzzDevice();

  clearTimeout(peekTimer);
  peekTimer = setTimeout(() => {
    if (!call) setIslandMode(null);
    d.classList.remove('peeking');
    d.classList.add('hidden');
    peekTimer = null;
  }, 4600);
}

function archivePeek(kind, data) {
  data = data || {};
  const app = kind === 'message' ? 'messages' : notifApp(data);
  if (appMuted(app)) return;
  const title = kind === 'message'
    ? (data.groupName || nameOfNumber(data.from) || L('ph.new_message_t'))
    : (data.title || L('ph.notification'));
  const bodyText = kind === 'message' ? (data.body || L('ph.attach')) : (data.body || '');
  const onClick = () => {
    const target = (state.apps || []).find((entry) => entry.id === app);
    if (!target) return;
    enterApp(target, null);
    if (kind === 'message') {
      if (data.group) openGroup(data.group, data.groupName || L('ph.groups'));
      else if (data.from) openThread(data.from);
    }
  };
  notifs.unshift({
    id: ++notifSeq,
    app,
    icon: kind === 'message' ? 'messages' : (data.icon || app),
    title,
    body: bodyText,
    at: Date.now(),
    onClick,
  });
  notifs = notifs.slice(0, 40);
  paintNotifs();
}

// ══ Emoji ══════════════════════════════════════════════════════
// A picker any composer can raise - Messages and the social apps both point it at their
// own input. Emoji are ordinary text, so they travel and store like the rest of a message.
const EMOJI = {
  faces: ['😀','😃','😄','😁','😅','😂','🤣','🙂','😉','😊','😇','🥰','😍','😘','😗','😋','😜','🤪','🤨','😎','🥳','😏','😒','😌','😔','😴','😪','😜','🤗','🤭','🤫','🤔','😐','😑','😬','🙄','😯','😦','😧','😮','😲','🥱','😴','😌','😛','😳','🥺','😢','😭','😤','😠','😡','🤬','🤯','😱','😨','😰','😥','😓','🤥','🥴','🤢','🤮','🤧','😷'],
  gestures: ['👍','👎','👌','🤌','✌️','🤞','🤟','🤙','👈','👉','👆','👇','☝️','✋','🤚','🖐️','🖖','👋','🤝','🙏','💪','👏','🙌','👐','🤲','✊','👊','🤛','🤜','💅','👀','👁️','🧠','🫶'],
  hearts: ['❤️','🧡','💛','💚','💙','💜','🖤','🤍','🤎','💔','❣️','💕','💞','💓','💗','💖','💘','💝','💟','♥️'],
  things: ['🔥','⭐','🌟','✨','💫','🎉','🎊','💯','✅','❌','❓','❗','💤','💢','💥','💦','💨','🕳️','💣','💬','🗨️','👑','💎','🔔','🎵','🎶','🚗','🏠','💰','💵','💊','🍺','🍻','🥂','🍔','🍕','☕','⚽','🎧','📱','💻','⏰','📅','☀️','🌧️','⛈️','❄️','🌙','⚡','🌈','🎁'],
};
const EMOJI_TABS = [['faces','😀'],['gestures','👍'],['hearts','❤️'],['things','🔥']];
let emojiTarget = null, emojiCat = 'faces';

function paintEmoji() {
  const pan = byId('emojipanel');
  pan.innerHTML =
    '<div class="emojitabs">' + EMOJI_TABS.map(([k, g]) =>
      '<button data-c="' + k + '" class="' + (emojiCat === k ? 'on' : '') + '" type="button">' + g + '</button>').join('') + '</div>' +
    '<div class="emojigrid">' + (EMOJI[emojiCat] || []).map((e) =>
      '<button data-e="' + e + '" type="button">' + e + '</button>').join('') + '</div>';
  [...pan.querySelectorAll('.emojitabs button')].forEach((b) =>
    b.addEventListener('click', () => { emojiCat = b.dataset.c; paintEmoji(); }));
  [...pan.querySelectorAll('.emojigrid button')].forEach((b) =>
    b.addEventListener('click', () => {
      const inp = byId(emojiTarget);
      if (!inp) return;
      // Insert at the caret if there is one, otherwise append; then keep typing.
      const at = (inp.selectionStart != null) ? inp.selectionStart : inp.value.length;
      inp.value = inp.value.slice(0, at) + b.dataset.e + inp.value.slice(at);
      const pos = at + b.dataset.e.length;
      try { inp.setSelectionRange(pos, pos); } catch {}
      inp.focus();
    }));
}
function emojiOpen(inputId) {
  if (emojiTarget === inputId && byId('emojipanel').classList.contains('on')) { emojiClose(); return; }
  emojiTarget = inputId; emojiCat = 'faces'; paintEmoji();
  byId('emojipanel').classList.add('on');
}
function emojiClose() { byId('emojipanel').classList.remove('on'); emojiTarget = null; }

// ══ Sheet, toast, banner ═══════════════════════════════════════
let sheetReturn = null;
const promptQueue = [];
let activePrompt = false;
let promptExpiryTimer = null;

function pumpPrompts() {
  if (activePrompt || byId('sheet').classList.contains('on')) return;
  while (promptQueue.length) {
    const entry = promptQueue.shift();
    const remaining = entry.expires - Date.now();
    if (remaining <= 0) continue;
    activePrompt = true;
    entry.show();
    clearTimeout(promptExpiryTimer);
    promptExpiryTimer = setTimeout(() => {
      promptExpiryTimer = null;
      if (activePrompt) closeSheet();
    }, remaining);
    return;
  }
}

function enqueuePrompt(show, ttlMs) {
  if (typeof show !== 'function') return;
  const now = Date.now();
  for (let i = promptQueue.length - 1; i >= 0; i -= 1) {
    if (promptQueue[i].expires <= now) promptQueue.splice(i, 1);
  }
  while (promptQueue.length >= 6) promptQueue.shift();
  promptQueue.push({
    show,
    expires: now + Math.max(1000, Number(ttlMs) || 30000),
  });
  pumpPrompts();
}

function sheet(title, html, after) {
  sheetReturn = null;
  byId('sheet').innerHTML = `<div class="grab"></div><div class="sh">${esc(title)}</div>${html}`;
  byId('sheet').classList.add('on');
  byId('scrim').classList.add('on');
  if (after) after();
}
function closeSheet(force) {
  if (typeof emojiClose === 'function') emojiClose();
  if (!force && sheetReturn) {
    const restore = sheetReturn;
    sheetReturn = null;
    restore();
    return;
  }
  sheetReturn = null;
  clearTimeout(promptExpiryTimer);
  promptExpiryTimer = null;
  byId('sheet').classList.remove('on');
  byId('scrim').classList.remove('on');
  activePrompt = false;
  if (force) promptQueue.length = 0;
  else setTimeout(pumpPrompts, 0);
}
byId('scrim').addEventListener('click', () => closeSheet());

let toastTimer = null;
function toast(text) {
  const t = byId('toast');
  t.textContent = text;
  t.classList.add('on');
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => t.classList.remove('on'), 2200);
}

// A notification now grows out of the black camera pill, iOS 27 style, and is filed in
// the centre. A muted app is filed nowhere and shows nothing.
let islandTimer = null;
function banner(b) {
  const app = notifApp(b);
  if (appMuted(app)) return;

  const n = { id: ++notifSeq, app, icon: b.icon || app, title: b.title || '', body: b.body || '',
              at: Date.now(), onClick: b.onClick || null };
  notifs.unshift(n);
  notifs = notifs.slice(0, 40);
  paintNotifs();
  if (byId('shade').classList.contains('on')) renderShade();
  // Focus keeps a quiet history in Notification Centre without lighting the island.
  if ((state.prefs || {}).dnd) return;
  playAlert();
  islandNotify(n);
}

// The pill expands, holds the notification, then collapses back. It yields to a live
// call, which owns the island outright.
function islandNotify(n) {
  if (call) return;
  const isl = byId('island');
  byId('inicon').innerHTML = UI.appIcon(n.icon);
  byId('inTitle').textContent = n.title;
  byId('inBody').textContent = n.body;
  setIslandMode('notif');
  isl.dataset.notif = n.id;
  clearTimeout(islandTimer);
  islandTimer = setTimeout(() => {
    if (!call && isl.classList.contains('notif')) setIslandMode(null);
    islandTimer = null;
  }, 4200);
}
byId('island').addEventListener('click', () => {
  const isl = byId('island');
  if (!isl.classList.contains('notif')) return;
  const n = notifs.find((x) => String(x.id) === isl.dataset.notif);
  setIslandMode(null);
  clearTimeout(islandTimer);
  if (n && n.onClick) n.onClick();
});

function relTime(t) {
  const m = Math.round((Date.now() - t) / 60000);
  if (m < 1) return L('ph.now') || 'now';
  if (m < 60) return m + ' min';
  return Math.round(m / 60) + ' h';
}

// The lock screen shows the most recent handful; the shade shows everything, grouped.
function paintNotifs() {
  const host = byId('locknotifs');
  const shown = notifs.slice(0, 4);
  host.innerHTML =
    (notifs.length > 1
      ? `<button class="lockclear" id="lockclear" type="button">${esc(L('ph.clear_all'))}</button>`
      : '') +
    shown.map((n, i) =>
      `<div class="lnotif glass" style="animation-delay:${i * 50}ms" data-nid="${n.id}">` +
      `<span class="lic">${UI.appIcon(n.icon)}</span>` +
      `<span class="lbody"><span class="lt">${esc(n.title || '')}</span>` +
      `<span class="lb">${esc(n.body || '')}</span></span>` +
      `<button class="lx" data-x="${n.id}" type="button">${svg('xmark')}</button></div>`).join('');

  // Clear one, or clear the stack. A notification you have read is one you should be able
  // to get rid of without unlocking the phone first.
  [...host.querySelectorAll('.lx')].forEach((b) => b.addEventListener('click', (e) => {
    e.stopPropagation();
    notifs = notifs.filter((n) => String(n.id) !== b.dataset.x);
    paintNotifs();
    if (byId('shade').classList.contains('on')) renderShade();
  }));
  const all = byId('lockclear');
  if (all) all.addEventListener('click', (e) => {
    e.stopPropagation();
    notifs = [];
    paintNotifs();
    if (byId('shade').classList.contains('on')) renderShade();
  });
  // Tapping the card itself still does what the notification is for.
  [...host.querySelectorAll('.lnotif')].forEach((c) => c.addEventListener('click', (e) => {
    if (e.target.closest('.lx')) return;
    const n = notifs.find((x) => String(x.id) === c.dataset.nid);
    if (n && n.onClick) { unlock(); n.onClick(); }
  }));
}

// ══ Calls ══════════════════════════════════════════════════════
let callSpeaker = false;

function fmtDuration(s) {
  const m = Math.floor(s / 60), r = s % 60;
  return `${m}:${String(r).padStart(2, '0')}`;
}

function renderCall() {
  const ui = byId('callui');
  // The page owns the ringing: it is the only side that can play a player's own MP3.
  if (call && call.state === 'in') playRingtone(); else stopRingtone();
  if (!call) {
    ui.classList.remove('on');
    setIslandMode(null);
    clearInterval(callTimer); callTimer = null;
    return;
  }
  ui.classList.add('on');
  const name = call.number ? nameOfNumber(call.number) : L('ph.unknown');
  byId('callav').textContent = name.slice(0, 1).toUpperCase();
  byId('callnum').textContent = name;
  byId('callstate').textContent =
    call.state === 'in' ? L('ph.incoming') : call.state === 'out' ? L('ph.calling') : '';

  // Live activity in the island, which is what a modern iPhone does with a call.
  setIslandMode('live');
  byId('islandIcon').innerHTML = svg('phone');
  byId('islandT1').textContent = name;
  byId('islandT2').textContent = call.state === 'active' ? L('ph.in_call')
    : call.state === 'in' ? L('ph.incoming') : L('ph.calling');

  if (call.state === 'active') {
    if (!callTimer) callStart = Date.now();
    const elapsed = Math.floor((Date.now() - callStart) / 1000);
    byId('callstate').innerHTML =
      `<span class="calltimer" id="ctimer">${fmtDuration(elapsed)}</span>`;
    byId('islandT2').textContent = fmtDuration(elapsed);
    if (!callTimer) {
      callTimer = setInterval(() => {
        const s = Math.floor((Date.now() - callStart) / 1000);
        const el = byId('ctimer'); if (el) el.textContent = fmtDuration(s);
        byId('islandT2').textContent = fmtDuration(s);
      }, 1000);
    }
    byId('callpad').innerHTML =
      `<div class="cpad ${callSpeaker ? 'on' : ''}" data-a="speaker"><span>${svg('speaker')}</span><em>${esc(L('ph.speaker'))}</em></div>`;
    [...byId('callpad').querySelectorAll('.cpad')].forEach((p) => p.addEventListener('click', () => {
      // The only exposed audio control is backed by the real proximity speaker bridge.
      if (p.dataset.a === 'speaker') {
        // A real speaker: the server works out who is close enough to hear it.
        callSpeaker = !callSpeaker;
        post('speaker', { on: callSpeaker }).then((r) => {
          if (!r || r.error) { callSpeaker = false; toast(L('ph.err_' + ((r && r.error) || 'x'))); renderCall(); }
          else toast(L(callSpeaker ? 'ph.speaker_on' : 'ph.speaker_off'));
        });
      }
      else return;
      renderCall();
    }));
  } else {
    byId('callpad').innerHTML = '';
  }

  byId('callbtns').innerHTML =
    (call.state === 'in' ? `<button class="cbtn ok" id="cans" type="button">${svg('answer')}</button>` : '') +
    `<button class="cbtn no" id="chang" type="button">${svg('hangup')}</button>`;
  const ans = byId('cans');
  if (ans) ans.addEventListener('click', () => post('answer'));
  byId('chang').addEventListener('click', () => post('hangup'));
}

// ══ Control centre ═════════════════════════════════════════════
// iOS 27 Liquid Glass. Every control is real: airplane and cellular drive the signal
// the status bar draws, wifi and bluetooth their own glyphs, the sliders brightness and
// volume, the toggles focus and the flashlight. A switch that changed nothing would be a
// lie about what the phone can do.
let ccNow = null;   // last-known now-playing, so the panel opens without a flash

async function toggleCC(key) {
  const p = state.prefs || {};
  const defaultsOn = key === 'wifi' || key === 'cellular';
  const current = defaultsOn ? p[key] !== false : p[key] === true;
  const r = await post('prefs', { [key]: !current });
  if (r && r.ok) {
    state.prefs = r.prefs;
    if (key === 'dnd') syncDndAudio();
    applyPower(state._power || {});
    applyStatusFlags();
    renderCC();
  }
}

function renderCC() {
  const p = state.prefs || {};

  byId('ccconn').innerHTML =
    `<button class="ccbtn air ${p.airplane ? 'on' : ''}" data-t="airplane" type="button">${svg('airplane')}</button>` +
    `<button class="ccbtn cel ${p.cellular !== false && !p.airplane ? 'on' : ''}" data-t="cellular" type="button">${svg('cell')}</button>` +
    `<button class="ccbtn wif ${p.wifi !== false ? 'on' : ''}" data-t="wifi" type="button">${svg('wifi')}</button>` +
    `<button class="ccbtn blu ${p.bluetooth ? 'on' : ''}" data-t="bluetooth" type="button">${svg('bt')}</button>`;
  qrows('ccconn', '.ccbtn', (b) => b.addEventListener('click', () => toggleCC(b.dataset.t)));

  const m = ccNow;
  byId('ccnow').innerHTML =
    `<div class="nowlab">${esc(L('ph.nowplaying'))}</div>` +
    (m
      ? `<div class="nowmid"><span class="nowart">${svg('music')}</span>` +
          `<span style="min-width:0"><span class="nowt">${esc(m.title || L('ph.untitled'))}</span>` +
          `<span class="nows">${esc(L('ph.music_' + (m.kind || 'boombox')))}</span></span></div>` +
        `<div class="nowbtns"><button data-n="toggle">${svg(m.paused ? 'play' : 'pause')}</button></div>`
      : `<div class="nowmid"><span class="nowart">${svg('music')}</span>` +
          `<span class="nows">${esc(L('ph.nothing_playing'))}</span></div>`);
  if (m) byId('ccnow').querySelector('[data-n="toggle"]').addEventListener('click', async () => {
    await post('music', { id: m.id, action: m.paused ? 'play' : 'pause' });
    m.paused = !m.paused; renderCC();
  });

  const bright = Math.max(0.35, Math.min(1, p.brightness ?? 1));
  byId('ccbright').innerHTML =
    `<div class="fill" style="height:${Math.round(bright * 100)}%"></div><div class="gl">${svg('sun')}</div>`;
  byId('ccvol').innerHTML =
    `<div class="fill" style="height:${Math.round(volume * 100)}%"></div><div class="gl">${svg('speaker')}</div>`;
  wireSlab('ccbright', (v) => {
    const brightness = 0.35 + v * 0.65;
    state.prefs = Object.assign({}, state.prefs || {}, { brightness });
    applyBrightness();
    byId('ccbright').querySelector('.fill').style.height = Math.round(brightness * 100) + '%';
  }, async (v) => {
    const commit = ++brightnessCommit;
    const r = await post('prefs', { brightness: 0.35 + v * 0.65 });
    if (commit === brightnessCommit && r && r.ok) state.prefs = r.prefs;
  });
  wireSlab('ccvol', (v) => {
    volume = v;
    byId('ccvol').querySelector('.fill').style.height = Math.round(v * 100) + '%';
  }, async (v) => {
    if (ccNow) await post('music', { id: ccNow.id, action: 'volume', volume: v });
  });

  byId('cctoggles').innerHTML =
    `<button class="ccpill focus ${p.dnd ? 'on' : ''}" data-c="dnd" type="button">${svg('focus')}</button>` +
    `<button class="ccpill torch ${ccTorch ? 'on' : ''}" data-c="torch" type="button">${svg('torch')}</button>` +
    `<button class="ccpill" data-c="wall" type="button">${svg('wall')}</button>` +
    `<button class="ccpill" data-c="camera" type="button">${svg('camera')}</button>`;
  qrows('cctoggles', '.ccpill', (b) => b.addEventListener('click', () => ccToggle(b.dataset.c)));
}

let ccTorch = false;
let torchCommit = 0;
let torchPending = false;

function paintTorchState() {
  const quick = byId('qtorch');
  quick.classList.toggle('on', ccTorch);
  quick.setAttribute('aria-pressed', ccTorch ? 'true' : 'false');
}

async function toggleTorch() {
  if (torchPending) return;
  torchPending = true;
  const commit = ++torchCommit;
  const next = !ccTorch;
  const r = await post('torch', { on: next });
  if (commit !== torchCommit) return;
  torchPending = false;
  if (!r || !r.ok) {
    toast(L('ph.err_' + ((r && r.error) || 'x')));
    return;
  }
  ccTorch = next;
  paintTorchState();
  toast(L(ccTorch ? 'ph.torch_on' : 'ph.torch_off'));
  if (byId('cc').classList.contains('on')) renderCC();
}

async function ccToggle(c) {
  if (c === 'dnd') { await toggleCC('dnd'); return; }
  if (c === 'torch') { await toggleTorch(); return; }
  byId('cc').classList.remove('on');
  const id = c === 'camera' ? 'camera' : 'settings';
  const a = (state.apps || []).find((x) => x.id === id);
  if (a) enterApp(a, null);
}

// A vertical slider: press or drag anywhere in the slab, the fill follows the finger.
const slabCallbacks = new WeakMap();
const slabCommits = new WeakMap();
const wiredSlabs = new WeakSet();
let brightnessCommit = 0;

function wireSlab(id, onChange, onCommit) {
  const el = byId(id);
  slabCallbacks.set(el, onChange);
  slabCommits.set(el, onCommit);
  if (wiredSlabs.has(el)) return;
  wiredSlabs.add(el);
  const to = (e) => {
    const r = el.getBoundingClientRect();
    return Math.max(0, Math.min(1, 1 - (e.clientY - r.top) / r.height));
  };
  const emit = (e) => {
    const value = to(e);
    const fn = slabCallbacks.get(el);
    if (fn) fn(value);
    return value;
  };
  let down = false, value = 0;
  el.addEventListener('pointerdown', (e) => {
    down = true;
    el.setPointerCapture(e.pointerId);
    value = emit(e);
  });
  el.addEventListener('pointermove', (e) => { if (down) value = emit(e); });
  el.addEventListener('pointerup', (e) => {
    if (!down) return;
    value = emit(e);
    down = false;
    const commit = slabCommits.get(el);
    if (commit) commit(value);
  });
  el.addEventListener('pointercancel', () => { down = false; });
}

// The control centre's media tile reads from v-music, refreshed each time it opens.
async function primeNowPlaying() {
  const d = await post('app', { app: 'music' });
  const list = (d && d.sources) || [];
  ccNow = list[0] || null;
}

// ══ Third-party app bridge ═════════════════════════════════════
// sdk.js inside an app frame posts here. Everything it can ask for is listed once, so
// what an app is allowed to do is readable in one place rather than inferred.
const SDK_ALLOWED = {
  request:  (d) => post('sdkRequest', d),         // <appId>:<method>, composed by Lua
  emit:     (d) => post('sdkEmit', d),            // <appId>:<event>, composed by Lua
  storage:  (d) => post('sdkStorage', d),         // per app, per character
  contacts: () => Promise.resolve({ ok: true, contacts: state.contacts || [] }),
  me:       () => Promise.resolve({ ok: true, number: state.number, apps: state.apps }),
  message:  (d) => post('send', d),
  call:     (d) => post('call', d),
};

window.addEventListener('message', async (e) => {
  const d = e.data || {};
  if (d.__phone !== 'sdk') return;
  const frame = byId('appframe');
  if (!frame || !frame.contentWindow || e.source !== frame.contentWindow ||
      !openApp || !openApp.page) return;
  const source = e.source;
  const appId = openApp.id;
  const appIcon = openApp.icon || 'dot';
  const reply = (payload) => {
    // Reply to the window that made this request, even if navigation has replaced the
    // current iframe while an asynchronous callback was in flight.
    if (source) source.postMessage({ __phone: 'reply', id: d.id, payload }, '*');
  };

  if (d.op === 'title') { setNav(d.data && d.data.title, null); byId('navbar').classList.remove('hidden'); return reply({ ok: true }); }
  if (d.op === 'close') { reply({ ok: true }); closeApp(); return; }
  if (d.op === 'toast') { toast((d.data && d.data.text) || ''); return reply({ ok: true }); }
  if (d.op === 'notify') {
    const data = d.data || {};
    banner({ app: appId, icon: appIcon, title: data.title, body: data.body });
    return reply({ ok: true });
  }
  if (d.op === 'badge') {
    const a = (state.apps || []).find((x) => x.id === appId);
    if (a) {
      a.badge = Number(d.data && d.data.count) || 0;
      // Repaint, or the count only appears the next time something else happens to
      // rebuild the grid - which from the app's side looks like badge() did nothing.
      renderHome();
    }
    return reply({ ok: true });
  }
  const fn = SDK_ALLOWED[d.op];
  if (!fn) return reply({ error: 'forbidden' });
  // The app id is stamped LAST, so a page cannot claim to be a different app by
  // putting its own `app` in the payload. Everything an app is allowed to reach is
  // namespaced under this id.
  reply(await fn(Object.assign({}, d.data || {}, { app: appId })));
});

// ══ Refresh ════════════════════════════════════════════════════
// Re-asks the server for everything it owns. Called after any write, because re-rendering
// from a locally patched copy is how a UI starts disagreeing with the database.
async function refresh() {
  const res = await post('refresh');
  if (res && res.ok) Object.assign(state, res);
}

// ══ Wiring ═════════════════════════════════════════════════════
byId('lock').addEventListener('click', unlock);
byId('homebar').addEventListener('click', goHome);

// Spotlight: the pill above the dock finds an app by name and launches it. It exists
// because a sixth page of icons is where apps go to be forgotten.
byId('spill').addEventListener('click', () => {
  sheet(L('ph.search'),
    UI.field('appq', L('ph.search_apps')) + '<div id="appres"></div>',
    () => {
      const draw = (q) => {
        const list = (state.apps || []).filter((a) => !q || L(a.label).toLowerCase().includes(q));
        byId('appres').innerHTML = list.length
          ? UI.group(list.map((a) => UI.row({ appicon: a.icon, title: L(a.label), chevron: true, data: { app: a.id } })))
          : UI.empty(L('ph.no_app'));
        [...byId('appres').querySelectorAll('.row')].forEach((r) => r.addEventListener('click', () => {
          const a = (state.apps || []).find((x) => x.id === r.dataset.app);
          closeSheet();
          if (a) enterApp(a, null);
        }));
      };
      draw('');
      byId('appq').addEventListener('input', () => draw(byId('appq').value.trim().toLowerCase()));
    });
});
byId('island').addEventListener('click', () => { if (call) renderCall(); });
// The status bar takes pointer events so a drag can START on it, but a tap does
// nothing on purpose: the shade and the control centre are pull-downs, and a click
// that also opened them made every stray tap up there flash a panel.
byId('status').style.pointerEvents = 'auto';

byId('navback').addEventListener('click', () => {
  const onBack = navBackAction;
  navBackAction = null;
  if (onBack) { onBack(); return; }
  closeApp();
});

byId('qcam').addEventListener('click', () => {
  const camera = (state.apps || []).find((a) => a.id === 'camera');
  if (!state.camera || !camera) {
    toast(L('ph.camera_off'));
    return;
  }
  if (!byId('lock').classList.contains('out')) unlock();
  enterApp(camera, byId('qcam'));
});
byId('qtorch').addEventListener('click', toggleTorch);

document.addEventListener('keydown', (e) => {
  if (e.key === 'Escape') {
    const hadTransient = anyOverlayOpen() || byId('folderview').classList.contains('on') ||
      byId('emojipanel').classList.contains('on') || editing || !!arr;
    resetTransientUI();
    if (hadTransient) return;
    if (byId('app').classList.contains('on')) { closeApp(); return; }
    clearActiveApp();
    post('close');
    return;
  }
  if (e.key === 'ArrowLeft') flipPage(-1);
  if (e.key === 'ArrowRight') flipPage(1);
});

byId('pages').addEventListener('wheel', (e) => { flipPage(e.deltaY > 0 ? 1 : -1); }, { passive: true });
window.addEventListener('resize', applyDevice, { passive: true });
if (window.visualViewport) window.visualViewport.addEventListener('resize', applyDevice, { passive: true });

// The phone keeps game input flowing so you can walk and drive while using it. A focused
// text field is the exception: the client holds the keyboard for the page while you type,
// so pressing "w" writes a w instead of walking you off, and releases it on blur.
const TYPEABLE = 'input, textarea, [contenteditable="true"]';
document.addEventListener('focusin', (e) => {
  if (e.target && e.target.matches && e.target.matches(TYPEABLE)) post('holdInput', { focused: true });
});
document.addEventListener('focusout', (e) => {
  if (e.target && e.target.matches && e.target.matches(TYPEABLE)) post('holdInput', { focused: false });
});

// ══ Lua → page ═════════════════════════════════════════════════
window.addEventListener('message', (e) => {
  // CEF host messages have no foreign Window source. An iframe must never be able to
  // impersonate Lua with an { action: ... } payload.
  if (e.source && e.source !== window) return;
  const d = e.data || {};
  if (d.__phone) return;                       // SDK traffic, handled above
  if (d.action === 'open') {
    torchCommit += 1;
    torchPending = false;
    resetTransientUI();
    S = d.strings || {};
    if (notificationOwner && notificationOwner !== d.number) notifs = [];
    notificationOwner = d.number || null;
    state = d;
    available = d.available || d.apps || [];
    state.sounds = d.sounds || state.sounds || {};
    call = d.call || null;
    dialed = ''; thread = null; threadGroup = null; openApp = null; page = 0;
    const locale = String(d.locale || d.lang || 'en').trim().replace('_', '-');
    document.documentElement.lang = locale || 'en';
    byId('device').classList.remove('hidden');
    byId('qtorch').setAttribute('aria-label', L('ph.torch'));
    byId('qcam').setAttribute('aria-label', L('app.camera'));
    byId('homebar').setAttribute('aria-label', L('ph.home'));
    byId('arrangedone').setAttribute('aria-label', L('ph.arrange_done'));
    byId('locknum').textContent = d.number || '';
    applyWallpaper();
    applyDevice();
    applyTheme();
    applyPower(d.power || { battery: d.battery, charging: d.charging, signal: d.signal });
    applyGlass((d.prefs && d.prefs.glass) ?? 55);
    applyBrightness();
    applyStatusFlags();
    primeNowPlaying();
    tick();
    paintNotifs();
    const sp = byId('spilltxt'); if (sp) sp.textContent = L('ph.search');
    byId('lock').classList.remove('out');
    byId('lockquick').classList.remove('hidden');
    byId('home').classList.add('behind');
    closeApp(true);
    renderCall();
  } else if (d.action === 'close') {
    torchCommit += 1;
    torchPending = false;
    resetTransientUI();
    closeApp(true);
    ccTorch = false;
    paintTorchState();
    byId('device').classList.add('hidden');
  } else if (d.action === 'call') {
    const was = call && call.state;
    call = d.call || null;
    if (!call || call.state !== 'active') { clearInterval(callTimer); callTimer = null; }
    if (call && call.state !== was) { callSpeaker = false; }
    renderCall();
  } else if (d.action === 'message') {
    const m = d.message || {};
    const inOpenThread = (threadGroup && m.group != null &&
                          String(m.group) === String(threadGroup.id)) ||
                         (!m.group && thread && m.from === thread);
    if (inOpenThread) {
      const el = byId('thread');
      if (el) {
        el.insertAdjacentHTML('beforeend', bubbleHtml({ mine: false, body: m.body, kind: m.kind, attachment: m.attachment, from: m.from }));
        wireLocButtons();
        byId('appbody').scrollTop = byId('appbody').scrollHeight;
      }
    } else {
      const groupId = m.group;
      const groupName = m.groupName || L('ph.groups');
      banner({ app: 'messages', icon: 'messages',
        title: groupId ? groupName : nameOfNumber(m.from), body: m.body || L('ph.attach'),
        onClick: () => {
          const a = (state.apps || []).find((x) => x.id === 'messages');
          if (!a) return;
          enterApp(a, null);
          if (groupId) openGroup(groupId, groupName);
          else openThread(m.from);
        } });
      refresh().then(() => { if (!openApp) renderHome(); });
    }
  } else if (d.action === 'power') {
    applyPower(d.power);
  } else if (d.action === 'banner') {
    banner(d.banner || {});
  } else if (d.action === 'buzz') {
    buzzDevice();
  } else if (d.action === 'shutter') {
    const device = byId('device');
    device.classList.remove('capturing');
    void device.offsetWidth;
    device.classList.add('capturing');
    clearTimeout(shutterTimer);
    shutterTimer = setTimeout(() => {
      device.classList.remove('capturing');
      shutterTimer = null;
    }, 220);
  } else if (d.action === 'shutterDone') {
    clearTimeout(shutterTimer);
    shutterTimer = null;
    byId('device').classList.remove('capturing');
  } else if (d.action === 'peek') {
    if (d.strings && !Object.keys(S || {}).length) S = d.strings;
    showPeek(d.kind, d.data || {});
  } else if (d.action === 'archive') {
    if (d.strings && !Object.keys(S || {}).length) S = d.strings;
    archivePeek(d.kind, d.data || {});
  } else if (d.action === 'voicemailOffer') {
    enqueuePrompt(() => voicemailOffer(d.number || ''), d.ttlMs);
  } else if (d.action === 'airdrop') {
    const offer = d.offer || {};
    enqueuePrompt(() => airdropOffer(offer), offer.ttlMs);
  } else if (d.action === 'airdropResult') {
    const r = d.result || {};
    toast(r.ok ? (L('ph.airdrop_took') + (r.name ? ' ' + r.name : '')) : L('ph.airdrop_declined'));
  }
});

wireSideButtons();
tick();
