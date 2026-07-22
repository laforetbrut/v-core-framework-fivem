// v-phone — iFruit
//
// Every app below is a VIEW. It renders what the owning module answered and sends actions
// back to that module; it never keeps a copy. The moment an app caches a balance or a
// vehicle list there are two sources of truth, and one of them is wrong.

const byId = (id) => document.getElementById(id);
const esc = (s) => String(s ?? '').replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
const post = (n, b) => fetch(`https://v-phone/${n}`, {
  method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(b || {}),
}).then((r) => r.json()).catch(() => ({ error: 'x' }));

const ICONS = {
  phone: 'M7 2h10v20H7zM10 5h4M12 19h.01',
  messages: 'M4 5h16v11H9l-5 4V5Z',
  contacts: 'M5 3h14v18H5zM12 9a2.5 2.5 0 1 0 0 5 2.5 2.5 0 0 0 0-5ZM8 18c1-2.6 7-2.6 8 0M3 7h2M3 12h2M3 17h2',
  bank: 'M3 10h18L12 4 3 10ZM5 10v8M10 10v8M14 10v8M19 10v8M3 20h18',
  garage: 'M3 20V9l9-5 9 5v11M7 20v-7h10v7M7 16h10',
  wallet: 'M3 7h15a2 2 0 0 1 2 2v9H3zM3 7V5h13M17 12h3v3h-3z',
  jobs: 'M4 8h16v12H4zM9 8V6a2 2 0 0 1 2-2h2a2 2 0 0 1 2 2v2M4 13h16',
  settings: 'M12 9a3 3 0 1 0 0 6 3 3 0 0 0 0-6ZM19 12a7 7 0 0 0-.1-1.2l2-1.5-2-3.4-2.3 1a7 7 0 0 0-2-1.2L14.2 3H9.8l-.4 2.7a7 7 0 0 0-2 1.2l-2.3-1-2 3.4 2 1.5a7 7 0 0 0 0 2.4l-2 1.5 2 3.4 2.3-1a7 7 0 0 0 2 1.2l.4 2.7h4.4l.4-2.7a7 7 0 0 0 2-1.2l2.3 1 2-3.4-2-1.5c.06-.4.1-.8.1-1.2Z',
  camera: 'M4 8h3l2-3h6l2 3h3v12H4zM12 10a4 4 0 1 0 0 8 4 4 0 0 0 0-8Z',
  hangup: 'M3 11c5-4 13-4 18 0l-2 3-4-1v-2a12 12 0 0 0-6 0v2l-4 1-2-3ZM4 4l16 16',
  answer: 'M6 3l3 5-2 2a12 12 0 0 0 7 7l2-2 5 3-2 4C11 22 2 13 2 5l4-2Z',
  dot: 'M12 8a4 4 0 1 0 0 8 4 4 0 0 0 0-8Z',
};
const svg = (n, cls) =>
  `<svg ${cls ? `class="${cls}" ` : ''}viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"><path d="${ICONS[n] || ICONS.dot}"/></svg>`;

// ── State ──────────────────────────────────────────────────────
// `state` is what the server last told us. Apps read from it and re-fetch rather than
// mutating it, so a stale render is impossible by construction.
let S = {};             // strings
let state = {};         // number, apps, prefs, contacts, conversations
let call = null;
let openApp = null;
let thread = null;      // number of the conversation being read
let dialed = '';

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
function show(which) {
  byId('lock').classList.toggle('hidden', which !== 'lock');
  byId('home').classList.toggle('hidden', which !== 'home');
  byId('app').classList.toggle('hidden', which !== 'app');
}

function goHome() {
  openApp = null; thread = null;
  show('home');
  renderHome();
}

// ══ Home ═══════════════════════════════════════════════════════
function unreadTotal() {
  return (state.conversations || []).reduce((n, c) => n + (c.unread || 0), 0);
}

function renderHome() {
  const grid = byId('grid');
  grid.innerHTML = '';
  (state.apps || []).forEach((a, i) => {
    const badge = a.id === 'messages' ? unreadTotal() : 0;
    const t = document.createElement('button');
    t.className = 'tile'; t.type = 'button';
    t.style.setProperty('--i', i);
    t.innerHTML =
      `<span class="wrap"><span class="ic">${svg(a.icon)}</span>` +
      (badge > 0 ? `<span class="badge">${badge > 99 ? '99+' : badge}</span>` : '') +
      `</span><span class="nm">${esc(L(a.label))}</span>`;
    t.addEventListener('click', () => enterApp(a));
    grid.appendChild(t);
  });
}

// ══ Apps ═══════════════════════════════════════════════════════
// An app that another resource registered carries a `page`: it is iframed rather than
// rendered here, which is the whole point of the registry.
const RENDER = {};

function enterApp(a) {
  openApp = a;
  thread = null;
  byId('apptitle').textContent = L(a.label);
  show('app');
  if (a.page) {
    byId('appbody').innerHTML = `<iframe src="${esc(a.page)}" style="width:100%;height:100%;border:0"></iframe>`;
    return;
  }
  const fn = RENDER[a.id];
  if (fn) fn(); else byId('appbody').innerHTML = `<div class="empty">${esc(L('ph.no_app'))}</div>`;
}

const body = (html) => { byId('appbody').innerHTML = html; };
const loading = () => body(`<div class="empty">${esc(L('ph.loading'))}</div>`);

// ── Phone (keypad) ─────────────────────────────────────────────
RENDER.phone = () => {
  const keys = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '*', '0', '#'];
  body(
    `<div class="dialed" id="dialed">${esc(dialed)}</div>` +
    `<div class="keypad">${keys.map((k) => `<button class="key" data-k="${k}" type="button">${k}</button>`).join('')}</div>` +
    `<button class="btn" id="dial" type="button">${esc(L('ph.call'))}</button>` +
    `<div class="btnrow"><button class="btn ghost" id="delkey" type="button">${esc(L('ph.delete'))}</button></div>`
  );
  byId('appbody').querySelectorAll('.key').forEach((b) => {
    b.addEventListener('click', () => { dialed = (dialed + b.dataset.k).slice(0, 20); byId('dialed').textContent = dialed; });
  });
  byId('delkey').addEventListener('click', () => { dialed = dialed.slice(0, -1); byId('dialed').textContent = dialed; });
  byId('dial').addEventListener('click', () => { if (dialed) post('call', { number: dialed }); });
};

// ── Messages ───────────────────────────────────────────────────
function nameOfNumber(number) {
  const c = (state.contacts || []).find((x) => x.number === number);
  return c ? c.name : number;
}

RENDER.messages = () => {
  const list = state.conversations || [];
  if (!list.length) { body(`<div class="empty">${esc(L('ph.no_messages'))}</div>`); return; }
  body(`<div class="rowlist">${list.map((c) => `
    <button class="item" data-n="${esc(c.number)}" type="button">
      <span class="av">${esc(nameOfNumber(c.number).slice(0, 1).toUpperCase())}</span>
      <span class="main"><span class="t">${esc(nameOfNumber(c.number))}</span>
      <span class="s">${esc(c.body)}</span></span>
      ${c.unread > 0 ? `<span class="unread">${c.unread}</span>` : ''}
    </button>`).join('')}</div>`);
  byId('appbody').querySelectorAll('.item').forEach((b) =>
    b.addEventListener('click', () => openThread(b.dataset.n)));
};

async function openThread(number) {
  thread = number;
  byId('apptitle').textContent = nameOfNumber(number);
  loading();
  const res = await post('conversation', { number });
  if (!res || res.error) { body(`<div class="empty">${esc(L('ph.err_' + ((res && res.error) || 'x')))}</div>`); return; }
  paintThread(res.messages || []);

  // Read: clear the badge locally as well, or the home screen keeps claiming unread mail
  // the player just looked at.
  const c = (state.conversations || []).find((x) => x.number === number);
  if (c) c.unread = 0;
}

function paintThread(messages) {
  body(
    `<div class="thread" id="thread">${messages.map((m) =>
      `<div class="bub ${m.mine ? 'me' : 'them'}">${esc(m.body)}</div>`).join('')}</div>` +
    `<div class="compose"><input class="fld" id="msg" maxlength="250" placeholder="${esc(L('ph.write'))}" />` +
    `<button class="btn" id="sendmsg" type="button">${esc(L('ph.send'))}</button></div>`
  );
  const el = byId('thread');
  el.scrollTop = el.scrollHeight;
  const send = async () => {
    const input = byId('msg');
    const text = input.value.trim();
    if (!text) return;
    input.value = '';
    const res = await post('send', { number: thread, body: text });
    if (res && res.ok) {
      el.insertAdjacentHTML('beforeend', `<div class="bub me">${esc(res.body)}</div>`);
      el.scrollTop = el.scrollHeight;
    }
  };
  byId('sendmsg').addEventListener('click', send);
  byId('msg').addEventListener('keydown', (e) => { if (e.key === 'Enter') send(); });
}

// ── Contacts ───────────────────────────────────────────────────
RENDER.contacts = () => {
  const list = state.contacts || [];
  body(
    `<button class="btn" id="newcontact" type="button">${esc(L('ph.new_contact'))}</button>` +
    `<div class="sechead">${esc(L('ph.contacts'))}</div>` +
    (list.length
      ? `<div class="rowlist">${list.map((c) => `
        <div class="item" data-id="${c.id}">
          <span class="av">${esc((c.name || '?').slice(0, 1).toUpperCase())}</span>
          <span class="main"><span class="t">${esc(c.name)}</span><span class="s">${esc(c.number)}</span></span>
          <button class="pill act" data-a="call" data-n="${esc(c.number)}" type="button">${esc(L('ph.call'))}</button>
          <button class="pill act" data-a="msg" data-n="${esc(c.number)}" type="button">${esc(L('ph.message'))}</button>
          <button class="pill act" data-a="del" data-id="${c.id}" type="button">${esc(L('ph.delete'))}</button>
        </div>`).join('')}</div>`
      : `<div class="empty">${esc(L('ph.no_contacts'))}</div>`)
  );
  byId('newcontact').addEventListener('click', contactForm);
  byId('appbody').querySelectorAll('.act').forEach((b) => b.addEventListener('click', async () => {
    if (b.dataset.a === 'call') post('call', { number: b.dataset.n });
    else if (b.dataset.a === 'msg') { openApp = (state.apps || []).find((a) => a.id === 'messages') || openApp; openThread(b.dataset.n); }
    else { await post('contactDelete', { id: Number(b.dataset.id) }); await refresh(); RENDER.contacts(); }
  }));
};

function contactForm() {
  body(
    `<input class="fld" id="cname" maxlength="40" placeholder="${esc(L('ph.name'))}" />` +
    `<input class="fld" id="cnum" maxlength="20" placeholder="${esc(L('ph.number'))}" />` +
    `<button class="btn" id="csave" type="button">${esc(L('ph.save'))}</button>`
  );
  byId('csave').addEventListener('click', async () => {
    const res = await post('contactSave', { name: byId('cname').value, number: byId('cnum').value });
    if (res && res.ok) { await refresh(); RENDER.contacts(); }
  });
}

// ── Bank ───────────────────────────────────────────────────────
RENDER.bank = async () => {
  loading();
  const d = await post('app', { app: 'bank' });
  if (!d || d.error) { body(`<div class="empty">${esc(L('ph.err_off'))}</div>`); return; }
  const tx = d.transactions || [];
  body(
    `<div class="hero"><span class="lab">${esc(L('ph.balance'))}</span>` +
    `<span class="val">${money(d.bank)}</span>` +
    `<span class="sub">${esc(L('ph.cash'))} ${money(d.cash)}</span></div>` +
    `<div class="sechead">${esc(L('ph.history'))}</div>` +
    (tx.length
      ? `<div class="rowlist">${tx.map((t) => `
        <div class="item"><span class="main">
          <span class="t">${esc(t.label || t.type || '')}</span>
          <span class="s">${esc(t.at || '')}</span></span>
          <span class="amt ${Number(t.amount) < 0 ? 'neg' : 'pos'}">${money(t.amount)}</span>
        </div>`).join('')}</div>`
      : `<div class="empty">${esc(L('ph.no_history'))}</div>`)
  );
};

// ── Garage ─────────────────────────────────────────────────────
// Where a car is, not how to spawn one: taking it out is the garage's job and needs the
// player to be standing at one.
RENDER.garage = async () => {
  loading();
  const d = await post('app', { app: 'garage' });
  if (!d || d.error) { body(`<div class="empty">${esc(L('ph.err_off'))}</div>`); return; }
  const list = Array.isArray(d) ? d : (d.vehicles || []);
  if (!list.length) { body(`<div class="empty">${esc(L('ph.no_vehicles'))}</div>`); return; }
  body(`<div class="rowlist">${list.map((v) => `
    <div class="item"><span class="main">
      <span class="t">${esc(v.model || '')}</span>
      <span class="s">${esc(v.plate || '')} &middot; ${esc(v.garage || L('ph.out'))}</span></span>
      <span class="pill ${v.live ? 'on' : ''}">${esc(v.live ? L('ph.veh_out') : L('ph.veh_stored'))}</span>
    </div>`).join('')}</div>`);
};

// ── Wallet ─────────────────────────────────────────────────────
RENDER.wallet = async () => {
  loading();
  const d = await post('app', { app: 'wallet' });
  if (!d || d.error) { body(`<div class="empty">${esc(L('ph.err_off'))}</div>`); return; }
  const list = Array.isArray(d) ? d : (d.licenses || []);
  if (!list.length) { body(`<div class="empty">${esc(L('ph.no_licenses'))}</div>`); return; }
  body(`<div class="rowlist">${list.map((l) => `
    <div class="item"><span class="main">
      <span class="t">${esc(L(l.i18n) !== l.i18n ? L(l.i18n) : (l.label || l.key))}</span>
      <span class="s">${esc(l.issuer || '')}</span></span>
      <span class="pill ${l.held ? 'on' : ''}">${esc(l.held ? L('ph.lic_held') : L('ph.lic_none'))}</span>
    </div>`).join('')}</div>`);
};

// ── Jobs ───────────────────────────────────────────────────────
// Read only, and deliberately: signing on happens at a desk. Browsing vacancies from a
// sofa is fine; being hired from one is not.
RENDER.jobs = async () => {
  loading();
  const d = await post('app', { app: 'jobs' });
  if (!d || d.error) { body(`<div class="empty">${esc(L('ph.err_off'))}</div>`); return; }
  const list = d.jobs || [];
  body(
    `<div class="hero"><span class="lab">${esc(L('ph.current_job'))}</span>` +
    `<span class="val" style="font-size:17px">${esc(d.current || '')}</span></div>` +
    `<div class="sechead">${esc(L('ph.openings'))}</div>` +
    (list.length
      ? `<div class="rowlist">${list.map((j) => `
        <div class="item"><span class="main">
          <span class="t">${esc(j.label || j.name)}</span>
          <span class="s">${esc(j.grade || '')} &middot; ${money(j.salary)}</span></span>
        </div>`).join('')}</div>`
      : `<div class="empty">${esc(L('ph.no_jobs'))}</div>`) +
    `<div class="empty">${esc(L('ph.jobs_hint'))}</div>`
  );
};

// ── Settings ───────────────────────────────────────────────────
RENDER.settings = () => {
  const p = state.prefs || {};
  body(
    `<div class="hero"><span class="lab">${esc(L('ph.my_number'))}</span>` +
    `<span class="val" style="font-size:20px">${esc(state.number || '')}</span></div>` +
    `<div class="sechead">${esc(L('ph.wallpaper'))}</div>` +
    `<div class="rowlist">${(state.wallpapers || []).map((w) => `
      <button class="item wp" data-w="${esc(w)}" type="button">
        <span class="main"><span class="t">${esc(L('ph.wall_' + w))}</span></span>
        <span class="pill ${p.wallpaper === w ? 'on' : ''}">${esc(p.wallpaper === w ? L('ph.on') : '')}</span>
      </button>`).join('')}</div>` +
    `<div class="sechead">${esc(L('ph.dnd'))}</div>` +
    `<button class="btn ${p.dnd ? '' : 'ghost'}" id="dnd" type="button">${esc(p.dnd ? L('ph.dnd_on') : L('ph.dnd_off'))}</button>`
  );
  byId('appbody').querySelectorAll('.wp').forEach((b) => b.addEventListener('click', async () => {
    const res = await post('prefs', { wallpaper: b.dataset.w });
    if (res && res.ok) { state.prefs = res.prefs; applyWallpaper(); RENDER.settings(); }
  }));
  byId('dnd').addEventListener('click', async () => {
    const res = await post('prefs', { dnd: !(state.prefs || {}).dnd });
    if (res && res.ok) { state.prefs = res.prefs; RENDER.settings(); }
  });
};

function applyWallpaper() {
  const s = byId('screen');
  (state.wallpapers || []).forEach((w) => s.classList.remove('wall-' + w));
  s.classList.add('wall-' + ((state.prefs || {}).wallpaper || 'ember'));
}

// ══ Calls ══════════════════════════════════════════════════════
function renderCall() {
  const ui = byId('callui');
  if (!call) { ui.classList.add('hidden'); return; }
  ui.classList.remove('hidden');
  byId('callnum').textContent = call.number ? nameOfNumber(call.number) : L('ph.unknown');
  byId('callstate').textContent =
    call.state === 'in' ? L('ph.incoming') : call.state === 'out' ? L('ph.calling') : L('ph.in_call');

  byId('callbtns').innerHTML =
    (call.state === 'in' ? `<button class="cbtn ok" id="cans" type="button">${svg('answer')}</button>` : '') +
    `<button class="cbtn no" id="chang" type="button">${svg('hangup')}</button>`;
  const ans = byId('cans');
  if (ans) ans.addEventListener('click', () => post('answer'));
  byId('chang').addEventListener('click', () => post('hangup'));
}

// ══ Refresh ════════════════════════════════════════════════════
// Re-asks the server for everything it owns. Called after any write, because re-rendering
// from a locally patched copy is how a UI starts disagreeing with the database.
async function refresh() {
  const res = await post('refresh');
  if (res && res.ok) { Object.assign(state, res); }
}

// ══ Wiring ═════════════════════════════════════════════════════
byId('unlock').addEventListener('click', goHome);
byId('appback').addEventListener('click', () => {
  // Inside a thread, back returns to the conversation list rather than to the home grid.
  if (openApp && openApp.id === 'messages' && thread) {
    thread = null;
    byId('apptitle').textContent = L(openApp.label);
    RENDER.messages();
    return;
  }
  goHome();
});

document.addEventListener('keydown', (e) => {
  if (e.key === 'Escape') post('close');
});

let bannerTimer = null;
function banner(b) {
  const el = byId('banner');
  el.innerHTML = `<div class="bt">${esc(b.title || '')}</div><div class="bb">${esc(b.body || '')}</div>`;
  el.classList.remove('hidden');
  clearTimeout(bannerTimer);
  bannerTimer = setTimeout(() => el.classList.add('hidden'), 4500);
}

window.addEventListener('message', (e) => {
  const d = e.data || {};
  if (d.action === 'open') {
    S = d.strings || {};
    state = d;
    call = d.call || null;
    dialed = ''; thread = null; openApp = null;
    byId('device').classList.remove('hidden');
    byId('locknum').textContent = d.number || '';
    applyWallpaper();
    tick();
    show('lock');
    renderCall();
  } else if (d.action === 'close') {
    byId('device').classList.add('hidden');
  } else if (d.action === 'call') {
    call = d.call || null;
    renderCall();
  } else if (d.action === 'message') {
    // A message that arrives while the thread it belongs to is open lands in the thread;
    // otherwise it bumps the badge, which is what the conversation list is refreshed for.
    if (thread && d.message && d.message.from === thread) {
      const el = byId('thread');
      if (el) { el.insertAdjacentHTML('beforeend', `<div class="bub them">${esc(d.message.body)}</div>`); el.scrollTop = el.scrollHeight; }
    } else {
      banner({ title: nameOfNumber(d.message.from), body: d.message.body });
      refresh().then(() => { if (!openApp) renderHome(); });
    }
  } else if (d.action === 'banner') {
    banner(d.banner || {});
  }
});

tick();
