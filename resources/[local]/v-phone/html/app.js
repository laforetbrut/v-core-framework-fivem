// v-phone — iFruit, iOS 26 shell
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

// Every call into Lua goes through here. The rejection is swallowed into an error
// object rather than left to reject: an app that awaits this must get an answer it can
// render, not a promise that never settles behind a loading spinner.
const post = (n, b) => fetch(`https://v-phone/${n}`, {
  method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(b || {}),
}).then((r) => r.json()).catch(() => ({ error: 'x' }));

// Tile backgrounds come from the icon table in sdk.js (UI.appIcon).

// ══ State ══════════════════════════════════════════════════════
let S = {};             // strings
let state = {};         // number, apps, prefs, contacts, conversations
let call = null;
let callStart = 0, callTimer = null;
let openApp = null;
let thread = null;
let dialed = '';
let page = 0;
let notifs = [];        // the notification centre, newest first
let notifSeq = 0;       // stable ids so a card can be dismissed by hand
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
let folderOpen = null;
let storeView = null;   // app id while a store page is open

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
function unlock() {
  byId('lock').classList.add('out');
  byId('lockquick').classList.add('hidden');
  byId('home').classList.remove('behind');
  renderHome();
}

function lockScreen() {
  closeApp(true);
  byId('lock').classList.remove('out');
  byId('lockquick').classList.remove('hidden');
  byId('home').classList.add('behind');
}

function goHome() {
  if (byId('cc').classList.contains('on')) { byId('cc').classList.remove('on'); return; }
  if (byId('sheet').classList.contains('on')) { closeSheet(); return; }
  if (byId('app').classList.contains('on')) { closeApp(); return; }
  if (!byId('lock').classList.contains('out')) return;
  lockScreen();
}

// ══ Home ═══════════════════════════════════════════════════════
function unreadTotal() {
  return (state.conversations || []).reduce((n, c) => n + (c.unread || 0), 0);
}

function tileHTML(a, i) {
  const badge = a.id === 'messages' ? unreadTotal() : (a.badge || 0);
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
  const gridApps = apps.filter((a) => !dockApps.includes(a));

  const items = layoutItems();
  paintPages(items);
  byId('dock').innerHTML = dockApps.map((a, i) => tileHTML(a, i)).join('');
  byId('pages').style.transition = 'transform .34s cubic-bezier(.32,.72,0,1)';

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
function paintPages(items) {
  const CAP = 16;
  const pageCount = Math.max(1, Math.ceil(items.length / CAP));
  arrPerPage = Math.max(1, Math.ceil(items.length / pageCount));
  const pages = [];
  for (let i = 0; i < items.length; i += arrPerPage) pages.push(items.slice(i, i + arrPerPage));
  if (!pages.length) pages.push([]);

  byId('pages').innerHTML = pages.map((pg) =>
    '<div class="page">' + pg.map((it, i) => {
      if (it.t === 'gap') return '<div class="tile gap"></div>';
      return it.t === 'folder' ? folderTile(it, i)
                               : tileHTML(appById(it.id) || { id: it.id, icon: 'dot', label: it.id }, i);
    }).join('') + '</div>').join('');
  // data-idx is the position in `items`, counting only real tiles, so a drop can read it.
  let k = -1;
  [...byId('pages').querySelectorAll('.tile')].forEach((t) => {
    if (t.classList.contains('gap')) return;
    k += 1; t.dataset.idx = k;
  });
  byId('pages').style.transform = `translateX(${-page * 100}%)`;
  byId('dots').innerHTML = pages.map((_, i) => `<i class="${i === page ? 'on' : ''}"></i>`).join('');

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
  folderOpen = i;
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
  if (e.target.id === 'folderview') { byId('folderview').classList.remove('on'); folderOpen = null; }
});

// ══ Arrange mode ═══════════════════════════════════════════════
// A real drag: the tile lifts into a clone that follows the finger, the grid opens a gap
// where it will land, and it stays in arrange mode until Done - a drop no longer kicks
// you out. Hold a tile to enter; drag onto another app to make a folder.
let arr = null;          // the live drag session, or null
let arrWired = false;

function enterArrange() {
  editing = true;
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

  window.addEventListener('pointerup', (e) => {
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
  const n = byId('pages').children.length;
  page = Math.max(0, Math.min(n - 1, page + dir));
  byId('pages').style.transform = `translateX(${-page * 100}%)`;
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
function enterApp(a, tile) {
  openApp = a; thread = null;
  // Most recent first, no duplicates. This is the switcher's whole model.
  recents = [a.id].concat(recents.filter((id) => id !== a.id)).slice(0, 8);
  const app = byId('app');
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
    // A third-party app is iframed and talks to us through sdk.js.
    byId('appbody').innerHTML = `<iframe class="appframe" id="appframe" src="${esc(a.page)}"></iframe>`;
    byId('appbody').style.padding = '0';
    byId('navbar').classList.add('hidden');
    return;
  }
  byId('appbody').style.padding = '';
  byId('app').classList.remove('black');
  byId('screen').classList.remove('appblack');
  byId('navbar').classList.remove('hidden');
  const fn = RENDER[a.id];
  if (fn) fn(); else body(UI.empty(L('ph.no_app')));
}

function closeApp(instant) {
  const app = byId('app');
  if (!app.classList.contains('on')) return;
  byId('screen').classList.remove('app-open');
  if (instant) { app.classList.remove('on'); openApp = null; thread = null; threadGroup = null; storeView = null; socialAcc.bleeter = null; socialAcc.snap = null; return; }
  app.classList.remove('on');
  app.classList.add('closing');
  setTimeout(() => { app.classList.remove('closing'); }, 300);
  openApp = null; thread = null; threadGroup = null; storeView = null; socialAcc.bleeter = null; socialAcc.snap = null;
}

function setNav(title, backLabel, action) {
  byId('navtitle').textContent = title || '';
  byId('navtitlesm').textContent = title || '';
  byId('navbacktxt').textContent = backLabel || L('ph.home');
  const act = byId('navact');
  if (action) {
    act.classList.remove('hidden');
    act.className = 'navact' + (action.icon ? ' round' : '');
    act.innerHTML = action.icon ? svg(action.icon) : esc(action.label);
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
const RENDER = {};

// ── Phone ──────────────────────────────────────────────────────
const KEYS = [['1', ''], ['2', 'ABC'], ['3', 'DEF'], ['4', 'GHI'], ['5', 'JKL'], ['6', 'MNO'],
  ['7', 'PQRS'], ['8', 'TUV'], ['9', 'WXYZ'], ['*', ''], ['0', '+'], ['#', '']];

let phoneTab = 'keypad';

RENDER.phone = () => {
  tabbar([
    { id: 'favourites', icon: 'star', label: 'ph.favourites' },
    { id: 'contacts', icon: 'contacts', label: 'app.contacts' },
    { id: 'keypad', icon: 'keypad', label: 'ph.keypad_tab' },
  ], phoneTab, (t) => { phoneTab = t; RENDER.phone(); });

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
      `<span style="width:74px"></span>` +
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
  thread = null;
  threadGroup = { id, name };
  setNav(name, L('app.messages'));
  loading();
  const res = await post('conversation', { group: id });
  if (!res || res.error) { body(UI.empty(L('ph.err_' + ((res && res.error) || 'x')))); return; }
  paintThread(res.messages || []);
}

async function openThread(number) {
  thread = number;
  threadGroup = null;
  setNav(nameOfNumber(number), L('app.messages'), {
    icon: 'phone', onClick: () => post('call', { number }),
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
  foot(`<div class="compose">` +
    `<button class="attach" id="attach" type="button">+</button>` +
    UI.field('msg', L('ph.write'), '', 'maxlength="250"') +
    `<button class="sendbtn" id="sendmsg" type="button">${svg('send')}</button></div>`);
  byId('attach').addEventListener('click', () => attachSheet());
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
          '<div class="shots" style="margin-bottom:12px">' + shots.map((u, i) =>
            '<div class="shot" data-i="' + i + '" style="background-image:url(' + esc(u) + ')"></div>').join('') + '</div>'
        : '') +
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
          sh.addEventListener('click', () => sendMedia({ kind: 'image', attachment: shots[Number(sh.dataset.i)], body: '' })));
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
  body(searchHtml(L('ph.search_contacts')) + '<div id="clist"></div>');
  draw('');
  onSearch(draw);
};

function contactSheet(c) {
  const isNew = !c.id;
  sheet(isNew ? L('ph.new_contact') : c.name,
    UI.field('cname', L('ph.name'), c.name, 'maxlength="40"') +
    UI.field('cnum', L('ph.number'), c.number, 'maxlength="20"') +
    UI.button(L('ph.save'), 'csave') +
    (isNew ? '' : UI.button(L('ph.call'), 'ccall', 'tinted')) +
    (isNew ? '' : UI.button(L('ph.message'), 'cmsg', 'plain')) +
    (isNew ? '' : UI.button(L('ph.delete'), 'cdel', 'destructive')),
    () => {
      byId('csave').addEventListener('click', async () => {
        const res = await post('contactSave', { id: c.id, name: byId('cname').value, number: byId('cnum').value });
        if (res && res.ok) { closeSheet(); await refresh(); RENDER.contacts(); }
        else toast(L('ph.err_' + ((res && res.error) || 'x')));
      });
      if (isNew) return;
      byId('ccall').addEventListener('click', () => { closeSheet(); post('call', { number: c.number }); });
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
    UI.bigNumber(L('ph.balance'), money(d.bank), `${L('ph.cash')} ${money(d.cash)}`) +
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
RENDER.jobs = async () => {
  loading();
  const d = await post('app', { app: 'jobs' });
  if (!d || d.error) { body(UI.empty(L('ph.err_off'), 'jobs')); return; }
  const list = d.jobs || [];
  body(
    UI.bigNumber(L('ph.current_job'), d.current || '') +
    (list.length
      ? UI.group(list.map((j) => UI.row({
          icon: 'jobs', tint: '#5856D6', title: j.label || j.name, subtitle: j.grade || '',
          value: money(j.salary), mono: true,
        })), { header: L('ph.openings'), footer: L('ph.jobs_hint') })
      : UI.empty(L('ph.no_jobs'), 'jobs'))
  );
};

// ── Settings ───────────────────────────────────────────────────
RENDER.settings = () => {
  const p = state.prefs || {};
  body(
    UI.group([
      UI.row({ icon: 'phone', tint: '#34C759', title: L('ph.my_number'), value: state.number || '',
               data: { copy: state.number || '' } }),
      UI.row({ icon: 'moon', tint: '#5856D6', title: L('ph.dark_mode'), toggle: !!p.dark, data: { t: 'dark' } }),
    ]) +
    (p.wallpaperUrl ? '<div class="wallpreview" style="background-image:url(' + esc(p.wallpaperUrl) + ')"></div>' : '') +
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
    })), { header: L('ph.action_button'), footer: L('ph.action_hint') })
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
      if (res && res.ok) { state.prefs = res.prefs; RENDER.settings(); }
    }
  }));
};

// 0 is ultra clear, 100 fully tinted. Every alpha in the material is a calc() off this.
function applyGlass(v) {
  const k = Math.max(0, Math.min(100, Number(v) || 0)) / 100;
  byId('screen').style.setProperty('--gk', String(k));
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
    w.classList.add('wall-' + (p.wallpaper || 'ember'));
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

function applyTheme() {
  byId('screen').classList.toggle('dark', (state.prefs || {}).dark === true);
}

function applyDevice() {
  const p = state.prefs || {};
  const d = byId('device');
  d.style.transform = 'scale(' + (p.size || 1) + ')';
  d.style.transformOrigin = (p.side === 'left') ? 'left bottom' : 'right bottom';
  d.style.right = (p.side === 'left') ? 'auto' : '3vw';
  d.style.left = (p.side === 'left') ? '3vw' : 'auto';
}

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
RENDER.music = async () => {
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

RENDER.mdt = async () => {
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
      const res = await post('mdt', { op: 'lookup', query: byId('mq').value.trim() });
      if (!res || res.error) { byId('mres').innerHTML = UI.empty(L('ph.err_' + ((res && res.error) || 'x'))); return; }
      byId('mres').innerHTML =
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
  closeSheet();
}

byId('screen').addEventListener('pointerdown', (e) => {
  const p = screenPoint(e);
  g = { x0: p.x, y0: p.y, t0: Date.now(), w: p.w, h: p.h,
        fromBottom: p.y > p.h - EDGE, fromTop: p.y < EDGE_TOP, fromLeft: p.x < 18 };
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
      '<b>' + esc(L(a.label)) + '</b></div><div class="cbody"></div></div>').join('') +
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
        c.classList.add('gone');
        recents = recents.filter((id) => id !== c.dataset.app);
        setTimeout(() => { if (!recents.length) byId('switcher').classList.remove('on'); else openSwitcher(); }, 240);
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
  storeView = a.id;
  const has = isInstalled(a.id);
  setNav(L('app.store'), null);
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
    if (app) { storeView = null; enterApp(app, null); }
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
  const r = await post('install', { app: id, install });
  if (!r || r.error) { toast(L('ph.err_' + ((r && r.error) || 'x'))); return false; }
  await refresh();
  available = state.available || available;
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
  storeView = null;
  setNav(L('app.store'), null);

  const all = (available || []).slice().sort((a, b) => a.slot - b.slot);
  if (!all.length) { body(UI.empty(L('ph.store_empty'), 'store')); return; }

  // The featured slot goes to something you do NOT have yet: a shop window showing what
  // you already own is a shelf, not a window.
  const feat = all.find((a) => a.optional && !isInstalled(a.id)) || all[0];
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

    if (!q && storeCat === 'all') {
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

RENDER.health = async () => {
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
  const r = await post('sdkStorage', { app: 'reminders', op: 'get', key: 'items' });
  try { reminders = JSON.parse((r && r.value) || '[]') || []; } catch (e) { reminders = []; }
  return reminders;
}

function saveReminders() {
  return post('sdkStorage', { app: 'reminders', op: 'set', key: 'items', value: JSON.stringify(reminders) });
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
RENDER.camera = async () => {
  if (!state.camera) { body(UI.empty(L('ph.camera_off'), 'camera')); return; }
  const d = await post('photos', { op: 'list' });
  const shots = (d && d.photos) || [];
  body(
    (shots.length
      ? '<div class="shots">' + shots.map((u, i) =>
          '<div class="shot" data-i="' + i + '" style="background-image:url(' + esc(u) + ')"></div>').join('') + '</div>'
      : UI.empty(L('ph.no_photos'), 'camera')) +
    '<button class="shutter" id="shoot" type="button"></button>'
  );
  byId('shoot').addEventListener('click', async () => {
    toast(L('ph.shooting'));
    const res = await post('shoot');
    if (!res || res.error) { toast(L('ph.err_' + ((res && res.error) || 'x'))); return; }
    RENDER.camera();
  });
  rows('.shot', (el) => el.addEventListener('click', () => {
    const url = shots[Number(el.dataset.i)];
    sheet(L('app.camera'),
      '<img class="shotbig" src="' + esc(url) + '" />' +
      UI.button(L('ph.set_wallpaper'), 'swall') +
      UI.button(L('ph.delete'), 'sdel', 'destructive'),
      () => {
        byId('swall').addEventListener('click', async () => {
          const r = await post('prefs', { wallpaperUrl: url });
          closeSheet();
          if (r && r.ok) { state.prefs = r.prefs; applyWallpaper(); toast(L('ph.wall_set')); }
          else toast(L('ph.err_' + ((r && r.error) || 'x')));
        });
        byId('sdel').addEventListener('click', async () => {
          await post('photos', { op: 'del', index: Number(el.dataset.i) + 1 });
          closeSheet(); RENDER.camera();
        });
      });
  }));
};


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
  try { ok = document.execCommand('copy'); } catch (e) { ok = false; }
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

async function needAccount(app, then) {
  if (socialAcc[app]) { then(); return; }
  const r = await post('social', { op: 'me', app });
  if (!r || r.error) { body(UI.empty(L('ph.err_' + ((r && r.error) || 'off')), 'bleet')); return; }
  if (r.account) { socialAcc[app] = r.account; then(); return; }

  // First run: pick a handle. This IS the account the network knows you by, which is
  // why it is the one thing you cannot skip.
  body(
    UI.bigNumber(L('ph.soc_welcome'), '@') +
    UI.field('shandle', L('ph.soc_handle'), '', 'maxlength="20"') +
    UI.field('savatar', L('ph.soc_avatar'), '', 'maxlength="300"') +
    UI.field('sbio', L('ph.soc_bio'), '', 'maxlength="160"') +
    UI.button(L('ph.soc_create'), 'smake') +
    '<div class="groupfoot">' + esc(L('ph.soc_hint')) + '</div>'
  );
  byId('smake').addEventListener('click', async () => {
    const r2 = await post('social', { op: 'setup', app, handle: byId('shandle').value.trim(),
      avatar: byId('savatar').value.trim(), bio: byId('sbio').value.trim() });
    if (r2 && r2.ok) { socialAcc[app] = r2.account; toast(L('ph.soc_made')); then(); }
    else toast(L('ph.err_' + ((r2 && r2.error) || 'x')));
  });
}

function postCard(pst) {
  const av = pst.avatar
    ? '<span class="pav" style="background-image:url(' + esc(pst.avatar) + ')"></span>'
    : '<span class="pav">' + esc(String(pst.handle || '?').slice(0, 1).toUpperCase()) + '</span>';
  return '<div class="post" data-id="' + pst.id + '">' +
    '<div class="phead">' + av +
      '<span class="ph">@' + esc(pst.handle) + '</span>' +
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
      UI.field('btext', L('ph.bleet_ph'), '', 'maxlength="280"') + UI.button(L('ph.bleet_send'), 'bgo'),
      () => byId('bgo').addEventListener('click', async () => {
        const r = await post('social', { op: 'post', kind: 'text', body: byId('btext').value });
        closeSheet();
        if (r && r.ok) RENDER.bleeter(); else toast(L('ph.err_' + ((r && r.error) || 'x')));
      }));
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
      '<div class="shots" style="margin-bottom:10px">' + shots.map((u, i) =>
        '<div class="shot" data-i="' + i + '" style="background-image:url(' + esc(u) + ')"></div>').join('') + '</div>' +
      UI.field('scap', L('ph.snap_caption'), '', 'maxlength="140"'),
      () => [...byId('sheet').querySelectorAll('.shot')].forEach((el) =>
        el.addEventListener('click', async () => {
          const r = await post('social', { op: 'post', kind: 'photo',
            image: shots[Number(el.dataset.i)], body: byId('scap').value });
          closeSheet();
          if (r && r.ok) RENDER.snap(); else toast(L('ph.err_' + ((r && r.error) || 'x')));
        })));
  } });
  await socialFeed('photo', 'ph.snap_none');
});

// -- Hush -------------------------------------------------------
RENDER.hush = async () => {
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
      '<div class="hphoto"' + (pf.photo ? ' style="background-image:url(' + esc(pf.photo) + ')"' : '') + '>' +
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


// ══ Sheet, toast, banner ═══════════════════════════════════════
function sheet(title, html, after) {
  byId('sheet').innerHTML = `<div class="grab"></div><div class="sh">${esc(title)}</div>${html}`;
  byId('sheet').classList.add('on');
  byId('scrim').classList.add('on');
  if (after) after();
}
function closeSheet() {
  byId('sheet').classList.remove('on');
  byId('scrim').classList.remove('on');
}
byId('scrim').addEventListener('click', closeSheet);

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
  isl.classList.add('notif');
  isl.dataset.notif = n.id;
  clearTimeout(islandTimer);
  islandTimer = setTimeout(() => { if (!call) isl.classList.remove('notif'); }, 4200);
}
byId('island').addEventListener('click', () => {
  const isl = byId('island');
  if (!isl.classList.contains('notif')) return;
  const n = notifs.find((x) => String(x.id) === isl.dataset.notif);
  isl.classList.remove('notif');
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
  byId('locknotifs').innerHTML = notifs.slice(0, 4).map((n, i) =>
    `<div class="lnotif glass" style="--i:${i}"><span class="lic">${UI.appIcon(n.icon)}</span>` +
    `<span class="lbody"><span class="lt">${esc(n.title || '')}</span>` +
    `<span class="lb">${esc(n.body || '')}</span></span></div>`).join('');
}

// ══ Calls ══════════════════════════════════════════════════════
let callMuted = false, callSpeaker = false;

function fmtDuration(s) {
  const m = Math.floor(s / 60), r = s % 60;
  return `${m}:${String(r).padStart(2, '0')}`;
}

function renderCall() {
  const ui = byId('callui');
  const island = byId('island');
  if (!call) {
    ui.classList.remove('on');
    island.classList.remove('live');
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
  island.classList.add('live');
  byId('islandIcon').innerHTML = svg('phone');
  byId('islandT1').textContent = name;
  byId('islandT2').textContent = call.state === 'active' ? L('ph.in_call')
    : call.state === 'in' ? L('ph.incoming') : L('ph.calling');

  if (call.state === 'active') {
    if (!callTimer) {
      callStart = Date.now();
      byId('callstate').innerHTML = `<span class="calltimer" id="ctimer">0:00</span>`;
      callTimer = setInterval(() => {
        const s = Math.floor((Date.now() - callStart) / 1000);
        const el = byId('ctimer'); if (el) el.textContent = fmtDuration(s);
        byId('islandT2').textContent = fmtDuration(s);
      }, 1000);
    }
    byId('callpad').innerHTML =
      `<div class="cpad ${callMuted ? 'on' : ''}" data-a="mute"><span>${svg('mute')}</span><em>${esc(L('ph.mute'))}</em></div>` +
      `<div class="cpad" data-a="keypad"><span>${svg('keypad')}</span><em>${esc(L('ph.keypad'))}</em></div>` +
      `<div class="cpad ${callSpeaker ? 'on' : ''}" data-a="speaker"><span>${svg('speaker')}</span><em>${esc(L('ph.speaker'))}</em></div>`;
    [...byId('callpad').querySelectorAll('.cpad')].forEach((p) => p.addEventListener('click', () => {
      // Local comfort toggles only: the audio itself belongs to v-voice, and a phone
      // that pretended to mute a Mumble channel would be lying about being heard.
      if (p.dataset.a === 'mute') callMuted = !callMuted;
      else if (p.dataset.a === 'speaker') callSpeaker = !callSpeaker;
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
  const r = await post('prefs', { [key]: !p[key] });
  if (r && r.ok) { state.prefs = r.prefs; applyPower(state._power || {}); applyStatusFlags(); renderCC(); }
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
  wireSlab('ccbright', async (v) => {
    const r = await post('prefs', { brightness: 0.35 + v * 0.65 });
    if (r && r.ok) { state.prefs = r.prefs; applyBrightness(); }
    byId('ccbright').querySelector('.fill').style.height = Math.round((0.35 + v * 0.65) * 100) + '%';
  });
  wireSlab('ccvol', async (v) => {
    volume = v;
    byId('ccvol').querySelector('.fill').style.height = Math.round(v * 100) + '%';
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
async function ccToggle(c) {
  if (c === 'dnd') { await toggleCC('dnd'); return; }
  if (c === 'torch') { ccTorch = !ccTorch; post('torch', { on: ccTorch }); toast(L(ccTorch ? 'ph.torch_on' : 'ph.torch_off')); renderCC(); return; }
  byId('cc').classList.remove('on');
  const id = c === 'camera' ? 'camera' : 'settings';
  const a = (state.apps || []).find((x) => x.id === id);
  if (a) enterApp(a, null);
}

// A vertical slider: press or drag anywhere in the slab, the fill follows the finger.
function wireSlab(id, onChange) {
  const el = byId(id);
  const to = (e) => {
    const r = el.getBoundingClientRect();
    return Math.max(0, Math.min(1, 1 - (e.clientY - r.top) / r.height));
  };
  let down = false;
  el.addEventListener('pointerdown', (e) => { down = true; el.setPointerCapture(e.pointerId); onChange(to(e)); });
  el.addEventListener('pointermove', (e) => { if (down) onChange(to(e)); });
  el.addEventListener('pointerup', () => { down = false; });
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
  const reply = (payload) => {
    if (frame && frame.contentWindow) {
      frame.contentWindow.postMessage({ __phone: 'reply', id: d.id, payload }, '*');
    }
  };

  if (d.op === 'title') { setNav(d.data && d.data.title, null); byId('navbar').classList.remove('hidden'); return reply({ ok: true }); }
  if (d.op === 'close') { closeApp(); return reply({ ok: true }); }
  if (d.op === 'toast') { toast((d.data && d.data.text) || ''); return reply({ ok: true }); }
  if (d.op === 'notify') { banner({ app: (openApp && openApp.id) || 'dot', icon: (openApp && openApp.icon) || 'dot', title: d.data.title, body: d.data.body }); return reply({ ok: true }); }
  if (d.op === 'badge') {
    const a = (state.apps || []).find((x) => openApp && x.id === openApp.id);
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
  reply(await fn(Object.assign({}, d.data || {}, { app: openApp && openApp.id })));
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
  if (openApp && openApp.id === 'store' && storeView) {
    storeView = null;
    RENDER.store();
    return;
  }
  if (openApp && openApp.id === 'messages' && (thread || threadGroup)) {
    if (threadGroup) {
      // Back from a group steps to the list, exactly as it does from a DM. Falling
      // through to closeApp here is how back used to throw you out of the app.
      threadGroup = null; foot('');
      RENDER.messages();
      return;
    }
    thread = null; foot('');
    RENDER.messages();
    return;
  }
  closeApp();
});

byId('qcam').addEventListener('click', () => toast(L('ph.camera_off')));
byId('qtorch').addEventListener('click', () => toast(L('ph.torch_hint')));

document.addEventListener('keydown', (e) => {
  if (e.key === 'Escape') {
    if (byId('cc').classList.contains('on')) { byId('cc').classList.remove('on'); return; }
    if (byId('sheet').classList.contains('on')) { closeSheet(); return; }
    if (byId('app').classList.contains('on')) { closeApp(); return; }
    post('close');
    return;
  }
  if (e.key === 'ArrowLeft') flipPage(-1);
  if (e.key === 'ArrowRight') flipPage(1);
});

byId('pages').addEventListener('wheel', (e) => { flipPage(e.deltaY > 0 ? 1 : -1); }, { passive: true });

// ══ Lua → page ═════════════════════════════════════════════════
window.addEventListener('message', (e) => {
  const d = e.data || {};
  if (d.__phone) return;                       // SDK traffic, handled above
  if (d.action === 'open') {
    S = d.strings || {};
    state = d;
    available = d.available || d.apps || [];
    call = d.call || null;
    dialed = ''; thread = null; openApp = null; page = 0;
    byId('device').classList.remove('hidden');
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
    byId('device').classList.add('hidden');
    byId('cc').classList.remove('on');
    closeSheet();
  } else if (d.action === 'call') {
    const was = call && call.state;
    call = d.call || null;
    if (!call || call.state !== 'active') { clearInterval(callTimer); callTimer = null; }
    if (call && call.state !== was) { callMuted = false; callSpeaker = false; }
    renderCall();
  } else if (d.action === 'message') {
    const m = d.message || {};
    const inOpenThread = (threadGroup && m.group === threadGroup.id) ||
                         (!m.group && thread && m.from === thread);
    if (inOpenThread) {
      const el = byId('thread');
      if (el) {
        el.insertAdjacentHTML('beforeend', bubbleHtml({ mine: false, body: m.body, kind: m.kind, attachment: m.attachment, from: m.from }));
        wireLocButtons();
        byId('appbody').scrollTop = byId('appbody').scrollHeight;
      }
    } else {
      banner({ app: 'messages', icon: 'messages', title: d.message.group ? (d.message.groupName || L('ph.groups')) : nameOfNumber(d.message.from), body: d.message.body || L('ph.attach'),
               onClick: () => { const a = (state.apps || []).find((x) => x.id === 'messages');
                                if (a) { enterApp(a, null); openThread(d.message.from); } } });
      refresh().then(() => { if (!openApp) renderHome(); });
    }
  } else if (d.action === 'power') {
    applyPower(d.power);
  } else if (d.action === 'banner') {
    banner(d.banner || {});
  }
});

wireSideButtons();
tick();
