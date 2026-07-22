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

// Icon tints, so the home grid is not eight identical squares.
const TINT = { phone: 't-green', messages: 't-green', contacts: 't-grey', bank: 't-green',
  garage: 't-blue', wallet: 't-dark', jobs: 't-blue', settings: 't-grey' };

// ══ State ══════════════════════════════════════════════════════
let S = {};             // strings
let state = {};         // number, apps, prefs, contacts, conversations
let call = null;
let callStart = 0, callTimer = null;
let openApp = null;
let thread = null;
let dialed = '';
let page = 0;
let notifs = [];        // lock-screen stack

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
    `<span class="wrap"><span class="ic ${TINT[a.icon] || ''}">${svg(a.icon)}</span>` +
    (badge > 0 ? `<span class="badge">${badge > 99 ? '99+' : badge}</span>` : '') +
    `</span><span class="nm">${esc(L(a.label))}</span></button>`;
}

function renderHome() {
  const apps = (state.apps || []).slice();
  // The last four go in the dock, the way iOS ships: the apps you reach for without
  // thinking stay put while the grid pages move.
  const dockApps = apps.filter((a) => a.dock).slice(0, 4);
  const gridApps = apps.filter((a) => !dockApps.includes(a));

  const perPage = 24;
  const pages = [];
  for (let i = 0; i < gridApps.length; i += perPage) pages.push(gridApps.slice(i, i + perPage));
  if (!pages.length) pages.push([]);

  byId('pages').innerHTML = pages.map((p) =>
    `<div class="page">${p.map((a, i) => tileHTML(a, i)).join('')}</div>`).join('');
  byId('dock').innerHTML = dockApps.map((a, i) => tileHTML(a, i)).join('');
  byId('dots').innerHTML = pages.map((_, i) => `<i class="${i === page ? 'on' : ''}"></i>`).join('');
  byId('pages').style.transform = `translateX(${-page * 100}%)`;
  byId('pages').style.transition = 'transform .34s cubic-bezier(.32,.72,0,1)';

  [...document.querySelectorAll('.tile')].forEach((t) => {
    t.addEventListener('click', () => {
      const a = (state.apps || []).find((x) => x.id === t.dataset.app);
      if (a) enterApp(a, t);
    });
  });
}

function flipPage(dir) {
  const n = byId('pages').children.length;
  page = Math.max(0, Math.min(n - 1, page + dir));
  byId('pages').style.transform = `translateX(${-page * 100}%)`;
  byId('dots').innerHTML = [...Array(n)].map((_, i) => `<i class="${i === page ? 'on' : ''}"></i>`).join('');
}

// ══ App shell ══════════════════════════════════════════════════
// The zoom origin is taken from the icon that launched it. That one detail is most of
// what makes opening an app feel like iOS rather than a page swap.
function enterApp(a, tile) {
  openApp = a; thread = null;
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
  byId('navbar').classList.remove('hidden');
  const fn = RENDER[a.id];
  if (fn) fn(); else body(UI.empty(L('ph.no_app')));
}

function closeApp(instant) {
  const app = byId('app');
  if (!app.classList.contains('on')) return;
  byId('screen').classList.remove('app-open');
  if (instant) { app.classList.remove('on'); openApp = null; thread = null; return; }
  app.classList.remove('on');
  app.classList.add('closing');
  setTimeout(() => { app.classList.remove('closing'); }, 300);
  openApp = null; thread = null;
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

// The large title collapses into the bar on scroll, as it does on iOS.
byId('appbody').addEventListener('scroll', (e) => {
  byId('navbar').classList.toggle('collapsed', e.target.scrollTop > 22);
});

// ══ Built-in apps ══════════════════════════════════════════════
const RENDER = {};

// ── Phone ──────────────────────────────────────────────────────
const KEYS = [['1', ''], ['2', 'ABC'], ['3', 'DEF'], ['4', 'GHI'], ['5', 'JKL'], ['6', 'MNO'],
  ['7', 'PQRS'], ['8', 'TUV'], ['9', 'WXYZ'], ['*', ''], ['0', '+'], ['#', '']];

RENDER.phone = () => {
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
  setNav(L('app.messages'), null, { icon: 'add', onClick: newMessageSheet });
  const list = state.conversations || [];
  if (!list.length) { body(UI.empty(L('ph.no_messages'), 'messages')); return; }
  body(UI.group(list.map((c) => UI.row({
    avatar: nameOfNumber(c.number), title: nameOfNumber(c.number), subtitle: c.body,
    badge: c.unread > 0 ? c.unread : null, chevron: true, data: { n: c.number },
  }))));
  rows('.row', (r) => r.addEventListener('click', () => openThread(r.dataset.n)));
};

async function openThread(number) {
  thread = number;
  setNav(nameOfNumber(number), L('app.messages'), {
    icon: 'phone', onClick: () => post('call', { number }),
  });
  loading();
  const res = await post('conversation', { number });
  if (!res || res.error) { body(UI.empty(L('ph.err_' + ((res && res.error) || 'x')))); return; }
  paintThread(res.messages || []);
  const c = (state.conversations || []).find((x) => x.number === number);
  if (c) c.unread = 0;
}

function paintThread(messages) {
  body(`<div class="thread" id="thread">${messages.map((m) =>
    `<div class="bub ${m.mine ? 'me' : 'them'}">${esc(m.body)}</div>`).join('')}</div>`);
  foot(`<div class="compose">` +
    UI.field('msg', L('ph.write'), '', 'maxlength="250"') +
    `<button class="sendbtn" id="sendmsg" type="button">${svg('send')}</button></div>`);
  const el = byId('thread');
  el.scrollTop = el.scrollHeight;
  byId('appbody').scrollTop = byId('appbody').scrollHeight;

  const send = async () => {
    const input = byId('msg');
    const text = input.value.trim();
    if (!text) return;
    input.value = '';
    const res = await post('send', { number: thread, body: text });
    if (res && res.ok) {
      el.insertAdjacentHTML('beforeend', `<div class="bub me">${esc(res.body)}</div>`);
      byId('appbody').scrollTop = byId('appbody').scrollHeight;
    } else {
      toast(L('ph.err_' + ((res && res.error) || 'x')));
    }
  };
  byId('sendmsg').addEventListener('click', send);
  byId('msg').addEventListener('keydown', (e) => { if (e.key === 'Enter') send(); });
}

function newMessageSheet() {
  sheet(L('ph.new_message_to'),
    UI.field('nmnum', L('ph.number')) + UI.button(L('ph.write'), 'nmgo'),
    () => { byId('nmgo').addEventListener('click', () => {
      const n = byId('nmnum').value.trim();
      closeSheet();
      if (n) openThread(n);
    }); });
}

// ── Contacts ───────────────────────────────────────────────────
RENDER.contacts = () => {
  setNav(L('app.contacts'), null, { icon: 'add', onClick: () => contactSheet({}) });
  const list = state.contacts || [];
  if (!list.length) { body(UI.empty(L('ph.no_contacts'), 'contacts')); return; }
  body(UI.group(list.map((c) => UI.row({
    avatar: c.name, title: c.name, subtitle: c.number, chevron: true,
    data: { id: c.id, n: c.number },
  }))));
  rows('.row', (r) => r.addEventListener('click', () => {
    const c = (state.contacts || []).find((x) => String(x.id) === r.dataset.id);
    if (c) contactSheet(c);
  }));
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
    icon: 'garage', title: v.model || '', subtitle: `${v.plate || ''}  ${v.garage || L('ph.out')}`,
    value: v.live ? L('ph.veh_out') : L('ph.veh_stored'),
  }))));
};

// ── Wallet ─────────────────────────────────────────────────────
RENDER.wallet = async () => {
  loading();
  const d = await post('app', { app: 'wallet' });
  if (!d || d.error) { body(UI.empty(L('ph.err_off'), 'wallet')); return; }
  const list = Array.isArray(d) ? d : (d.licenses || []);
  if (!list.length) { body(UI.empty(L('ph.no_licenses'), 'wallet')); return; }
  body(UI.group(list.map((l) => UI.row({
    icon: 'wallet', title: (L(l.i18n) !== l.i18n ? L(l.i18n) : (l.label || l.key)),
    subtitle: l.issuer || '', value: l.held ? L('ph.lic_held') : L('ph.lic_none'),
    tone: l.held ? 'pos' : '',
  }))));
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
          icon: 'jobs', title: j.label || j.name, subtitle: j.grade || '',
          value: money(j.salary), mono: true,
        })), { header: L('ph.openings'), footer: L('ph.jobs_hint') })
      : UI.empty(L('ph.no_jobs'), 'jobs'))
  );
};

// ── Settings ───────────────────────────────────────────────────
RENDER.settings = () => {
  const p = state.prefs || {};
  body(
    UI.group([UI.row({ icon: 'phone', title: L('ph.my_number'), value: state.number || '' })]) +
    UI.group((state.wallpapers || []).map((w) => UI.row({
      icon: 'wall', title: L('ph.wall_' + w), value: p.wallpaper === w ? L('ph.on') : '',
      data: { w },
    })), { header: L('ph.wallpaper') }) +
    UI.group([UI.row({ icon: 'moon', title: L('ph.dnd'), toggle: !!p.dnd, data: { t: 'dnd' } })],
      { footer: L('ph.dnd_hint') })
  );
  rows('.row', (r) => r.addEventListener('click', async () => {
    if (r.dataset.w) {
      const res = await post('prefs', { wallpaper: r.dataset.w });
      if (res && res.ok) { state.prefs = res.prefs; applyWallpaper(); RENDER.settings(); }
    } else if (r.dataset.t === 'dnd') {
      const res = await post('prefs', { dnd: !(state.prefs || {}).dnd });
      if (res && res.ok) { state.prefs = res.prefs; RENDER.settings(); }
    }
  }));
};

function applyWallpaper() {
  const w = byId('wallpaper');
  (state.wallpapers || []).forEach((x) => w.classList.remove('wall-' + x));
  w.classList.add('wall-' + ((state.prefs || {}).wallpaper || 'ember'));
}

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

let bannerTimer = null;
function banner(b) {
  const el = byId('banner');
  el.innerHTML = `<span class="bic">${svg(b.icon || 'messages')}</span>` +
    `<span class="btext"><span class="bt">${esc(b.title || '')}</span>` +
    `<span class="bb">${esc(b.body || '')}</span></span>`;
  el.classList.add('on');
  el.onclick = () => { el.classList.remove('on'); if (b.onClick) b.onClick(); };
  clearTimeout(bannerTimer);
  bannerTimer = setTimeout(() => el.classList.remove('on'), 4500);

  notifs.unshift({ icon: b.icon || 'messages', title: b.title, body: b.body });
  notifs = notifs.slice(0, 4);
  paintNotifs();
}

function paintNotifs() {
  byId('locknotifs').innerHTML = notifs.map((n, i) =>
    `<div class="lnotif glass" style="--i:${i}"><span class="lic">${svg(n.icon)}</span>` +
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
// Only real controls. A tile that toggles nothing is decoration, and decoration that
// looks like a switch is a lie about what the phone can do.
function renderCC() {
  const p = state.prefs || {};
  byId('ccgrid').innerHTML =
    `<div class="cctile glass w2 h2"><div class="cch">${svg('wall')}<span>${esc(L('ph.wallpaper'))}</span></div>` +
      `<div class="ccv" id="ccwall">${esc(L('ph.wall_' + (p.wallpaper || 'ember')))}</div></div>` +
    `<div class="cctile glass"><div class="cch">${svg('moon')}</div>` +
      `<button class="ccpill ${p.dnd ? 'on' : ''}" id="ccdnd" type="button">${svg('moon')}</button></div>` +
    `<div class="cctile glass"><div class="cch">${svg('phone')}</div>` +
      `<div class="ccv" style="font-size:12px">${esc(state.number || '')}</div></div>` +
    `<div class="cctile glass w2"><div class="cch">${svg('messages')}<span>${esc(L('ph.unread'))}</span></div>` +
      `<div class="ccv">${unreadTotal()}</div></div>`;

  byId('ccdnd').addEventListener('click', async () => {
    const res = await post('prefs', { dnd: !(state.prefs || {}).dnd });
    if (res && res.ok) { state.prefs = res.prefs; renderCC(); }
  });
  byId('ccwall').parentElement.addEventListener('click', () => {
    byId('cc').classList.remove('on');
    const a = (state.apps || []).find((x) => x.id === 'settings');
    if (a) enterApp(a, null);
  });
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
  if (d.op === 'notify') { banner({ icon: (openApp && openApp.icon) || 'dot', title: d.data.title, body: d.data.body }); return reply({ ok: true }); }
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
byId('island').addEventListener('click', () => { if (call) renderCall(); });
byId('status').style.pointerEvents = 'auto';
byId('status').addEventListener('click', () => {
  if (!byId('lock').classList.contains('out')) return;
  const cc = byId('cc');
  cc.classList.toggle('on');
  if (cc.classList.contains('on')) renderCC();
});

byId('navback').addEventListener('click', () => {
  if (openApp && openApp.id === 'messages' && thread) {
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
    call = d.call || null;
    dialed = ''; thread = null; openApp = null; page = 0;
    byId('device').classList.remove('hidden');
    byId('locknum').textContent = d.number || '';
    applyWallpaper();
    tick();
    paintNotifs();
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
    if (thread && d.message && d.message.from === thread) {
      const el = byId('thread');
      if (el) {
        el.insertAdjacentHTML('beforeend', `<div class="bub them">${esc(d.message.body)}</div>`);
        byId('appbody').scrollTop = byId('appbody').scrollHeight;
      }
    } else {
      banner({ icon: 'messages', title: nameOfNumber(d.message.from), body: d.message.body,
               onClick: () => { const a = (state.apps || []).find((x) => x.id === 'messages');
                                if (a) { enterApp(a, null); openThread(d.message.from); } } });
      refresh().then(() => { if (!openApp) renderHome(); });
    }
  } else if (d.action === 'banner') {
    banner(d.banner || {});
  }
});

tick();
