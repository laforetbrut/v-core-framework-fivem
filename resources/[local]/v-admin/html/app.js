// v-admin — panel logic
const byId = (id) => document.getElementById(id);
const post = (n, b) => fetch(`https://v-admin/${n}`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(b || {}) }).then(r => r.json()).catch(() => false);
const fmt = (n) => '$' + Math.floor(Number(n) || 0).toLocaleString('en-US');
const esc = (s) => String(s ?? '').replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));

let strings = {}, isSuper = false, weathers = [], curTab = 'dash';
let players = [], frozen = new Set(), tools = {};
const t = (k) => strings[k] || k;

// Typing in a search box used to rebuild the whole list on every keystroke. With 300+
// catalogue rows that is a visible stutter, so every search is debounced through here.
function debounce(fn, ms) {
  let h = null;
  return (...a) => { clearTimeout(h); h = setTimeout(() => fn(...a), ms); };
}

// Appending rows one at a time costs one reflow per row. Building into a fragment and
// attaching once costs exactly one.
function paint(wrap, nodes) {
  const frag = document.createDocumentFragment();
  nodes.forEach(n => frag.appendChild(n));
  wrap.innerHTML = '';
  wrap.appendChild(frag);
}

function applyStrings() {
  document.querySelectorAll('[data-i18n]').forEach(el => { el.textContent = t(el.getAttribute('data-i18n')); });
  document.querySelectorAll('[data-i18n-ph]').forEach(el => { el.placeholder = t(el.getAttribute('data-i18n-ph')); });
}

function setTab(tab) {
  curTab = tab;
  document.querySelectorAll('.rtab').forEach(b => b.classList.toggle('on', b.dataset.tab === tab));
  document.querySelectorAll('.tab').forEach(s => s.classList.toggle('hidden', s.id !== 'tab-' + tab));
  byId('ctitle').textContent = t('adm.tab_' + (tab === 'res' ? 'res' : tab));
  loadTab();
}

async function loadTab() {
  if (curTab === 'dash') {
    const d = await post('dash');
    if (!d) return;
    const up = Math.floor(d.uptime / 3600) + 'h ' + Math.floor((d.uptime % 3600) / 60) + 'm';
    byId('dashcards').innerHTML = [
      [t('adm.uptime'), up], [t('adm.players'), `${d.players} / ${d.maxPlayers}`],
      [t('adm.resources'), `${d.running} / ${d.resources}`], [t('adm.characters'), d.characters],
    ].map(([k, v]) => `<div class="card"><span class="ck">${esc(k)}</span><span class="cv">${esc(v)}</span></div>`).join('');
  } else if (curTab === 'players') {
    const res = await post('players');
    players = Array.isArray(res) ? res : [];
    renderPlayers();
  } else if (curTab === 'tools') {
    renderTools();
    renderCoords();
  } else if (curTab === 'editor') {
    loadEditor();
  } else if (curTab === 'settings') {
    loadSettings();
  } else if (curTab === 'res') {
    const res = await post('resources');
    renderResources(Array.isArray(res) ? res : []);
  } else if (curTab === 'logs') {
    const res = await post('logs', { filter: byId('logfilter').value.trim() });
    renderLogs(Array.isArray(res) ? res : []);
  }
}

// ── Players ──
function renderPlayers() {
  const q = byId('psearch').value.trim().toLowerCase();
  const wrap = byId('plist'); wrap.innerHTML = '';
  players
    .filter(p => !q || String(p.id) === q || (p.name || '').toLowerCase().includes(q) || (p.citizenid || '').toLowerCase().includes(q))
    .forEach(p => {
      const row = document.createElement('div'); row.className = 'prow';
      row.innerHTML = `
        <div class="phead">
          <span class="pid">${p.id}</span>
          <span class="pname">${esc(p.name)} <i class="pacc">(${esc(p.account)})</i></span>
          <span class="pjob">${esc(p.job)}</span>
          <span class="pmoney">${fmt(p.cash)} · ${fmt(p.bank)}</span>
          <span class="pping">${p.ping}ms</span>
          <span class="pperm ${esc(p.permission)}">${esc(p.permission)}</span>
        </div>
        <div class="pacts hidden">
          <div class="agroup">
            <button class="mini" data-a="goto">${t('adm.act_goto')}</button>
            <button class="mini" data-a="bring">${t('adm.act_bring')}</button>
            <button class="mini" data-a="spectate">${t('adm.act_spectate')}</button>
            <button class="mini" data-a="openinv">${t('adm.act_inv')}</button>
            <button class="mini" data-a="heal">${t('adm.act_heal')}</button>
            <button class="mini" data-a="freeze">${frozen.has(p.id) ? t('adm.act_unfreeze') : t('adm.act_freeze')}</button>
          </div>
          <div class="agroup">
            <span class="alabel">${t('adm.give_money')}</span>
            <select class="sel" data-f="account" aria-label="${t('adm.give_money')}"><option value="cash">${t('adm.cash')}</option><option value="bank">${t('adm.bank')}</option></select>
            <input class="ain" data-f="amount" placeholder="${t('adm.amount')}" aria-label="${t('adm.amount')}" />
            <button class="mini accent" data-a="money">${t('adm.act_apply')}</button>
          </div>
          <div class="agroup">
            <span class="alabel">${t('adm.give_item')}</span>
            <input class="ain" data-f="item" placeholder="${t('adm.item')}" aria-label="${t('adm.item')}" />
            <input class="ain sm" data-f="count" placeholder="${t('adm.count')}" value="1" aria-label="${t('adm.count')}" />
            <button class="mini accent" data-a="giveitem">${t('adm.act_apply')}</button>
          </div>
          <div class="agroup">
            <span class="alabel">${t('adm.set_perm')}</span>
            <select class="sel" data-f="level" aria-label="${t('adm.set_perm')}">
              <option>user</option><option>mod</option><option>admin</option><option>superadmin</option>
            </select>
            <button class="mini accent" data-a="setperm" ${isSuper ? '' : 'disabled'}>${t('adm.act_apply')}</button>
            <span class="spacer"></span>
            <input class="ain" data-f="reason" placeholder="${t('adm.reason')}" aria-label="${t('adm.reason')}" />
            <button class="mini danger" data-a="kick">${t('adm.act_kick')}</button>
          </div>
        </div>`;
      row.querySelector('.phead').onclick = () => row.querySelector('.pacts').classList.toggle('hidden');
      row.querySelectorAll('[data-a]').forEach(btn => {
        btn.onclick = async (e) => {
          e.stopPropagation();
          const acts = row.querySelector('.pacts');
          const get = (f) => { const el = acts.querySelector(`[data-f="${f}"]`); return el ? el.value : undefined; };
          const type = btn.dataset.a;
          if (type === 'openinv') { post('openinv', { target: p.id }); return; }
          const payload = { type, target: p.id };
          if (type === 'money') { payload.account = get('account'); payload.amount = parseInt(get('amount'), 10) || 0; }
          if (type === 'giveitem') { payload.item = get('item'); payload.count = parseInt(get('count'), 10) || 1; }
          if (type === 'setperm') { payload.level = get('level'); }
          if (type === 'kick') { payload.reason = get('reason'); }
          if (type === 'freeze') { payload.state = !frozen.has(p.id); }
          const ok = await post('action', payload);
          flash(btn, ok);
          if (ok && type === 'freeze') { frozen.has(p.id) ? frozen.delete(p.id) : frozen.add(p.id); }
          if (ok && (type === 'money' || type === 'setperm' || type === 'kick')) setTimeout(loadTab, 400);
        };
      });
      wrap.appendChild(row);
    });
}

// ── Tools (self) ──
const TOOLTOGGLES = [
  { k: 'noclip', i18n: 'adm.noclip' }, { k: 'god', i18n: 'adm.godmode' },
  { k: 'invisible', i18n: 'adm.invisible' }, { k: 'esp', i18n: 'adm.esp' },
];
function renderTools() {
  const wrap = byId('toolgrid'); wrap.innerHTML = '';
  TOOLTOGGLES.forEach(tg => {
    const on = !!tools[tg.k];
    const b = document.createElement('button');
    b.className = 'toolbtn' + (on ? ' on' : '');
    b.innerHTML = `<span class="tname">${esc(t(tg.i18n))}</span><span class="tstate">${on ? t('adm.on') : t('adm.off')}</span>`;
    b.onclick = async () => {
      const res = await post('tool', { tool: tg.k });
      if (res && typeof res === 'object') { tools = res; renderTools(); }
      else flash(b, false);
    };
    wrap.appendChild(b);
  });
  renderScan();
}

// ── Clothing thumbnail scan (was a keybind + a chat command) ──
let scanCats = null;
async function renderScan() {
  const sel = byId('scan-cat'), go = byId('scan-go');
  if (!sel || !go) return;
  if (scanCats === null) scanCats = (await post('scanCats')) || [];
  sel.innerHTML = `<option value="">${esc(t('adm.scan_allcats'))}</option>` +
    scanCats.map(c => `<option value="${esc(c)}">${esc(c)}</option>`).join('');
  go.onclick = async () => {
    go.disabled = true;
    const ok = await post('scan', { mode: byId('scan-mode').value, cat: sel.value });
    flash(go, !!ok);
    setTimeout(() => { go.disabled = false; }, 3000);
  };
}

// ── Settings ──
// This renders whatever the server describes. It has no knowledge of any module's
// settings, which is precisely what lets a third-party script appear here for free.
let setData = null;

async function loadSettings() {
  const res = await post('settings');
  setData = (res && res.modules) ? res : { modules: [] };
  renderSettings();
}

function setInput(mod, s) {
  const id = `st_${mod}_${s.key}`;
  if (s.type === 'bool') {
    return `<label class="swrap"><input type="checkbox" id="${id}"${s.value ? ' checked' : ''} /></label>`;
  }
  if (s.type === 'select') {
    return `<select id="${id}">` + (s.options || []).map(o =>
      `<option value="${esc(o)}"${o === s.value ? ' selected' : ''}>${esc(o)}</option>`).join('') + `</select>`;
  }
  if (s.type === 'color') return `<input type="color" id="${id}" value="${esc(s.value || '#ff7a1a')}" />`;
  if (s.type === 'number') {
    return `<input type="number" id="${id}" value="${esc(s.value)}"` +
      (s.min !== undefined ? ` min="${s.min}"` : '') + (s.max !== undefined ? ` max="${s.max}"` : '') +
      ` step="${s.step === 1 ? 1 : 'any'}" />`;
  }
  return `<input type="text" id="${id}" value="${esc(s.value ?? '')}" />`;
}

function renderSettings() {
  const wrap = byId('setlist'); wrap.innerHTML = '';
  const q = (byId('setsearch').value || '').trim().toLowerCase();
  const mods = (setData && setData.modules) || [];
  const shown = mods.filter(m => !q || m.label.toLowerCase().includes(q) || m.name.toLowerCase().includes(q)
    || (m.settings || []).some(s => (s.label || '').toLowerCase().includes(q) || s.key.toLowerCase().includes(q)));
  if (!shown.length) { wrap.appendChild(el('div', 'empty-ed', t('adm.set_none'))); return; }

  const nodes = [];
  shown.forEach((m, i) => {
    const box = document.createElement('div');
    box.className = 'setmod'; box.style.setProperty('--i', i);
    const rows = (m.settings || []).filter(s => !q || (s.label || '').toLowerCase().includes(q)
      || s.key.toLowerCase().includes(q) || m.label.toLowerCase().includes(q) || m.name.toLowerCase().includes(q));
    box.innerHTML = `
      <div class="sethead">
        <span class="setname">${esc(m.label)}</span>
        <span class="setcat">${esc(m.category)}</span>
        <span class="setres">${esc(m.name)}</span>
        <span class="setdot ${m.running ? 'on' : 'off'}"></span>
      </div>
      ${rows.length ? '' : `<div class="setempty">${esc(t(m.silent ? 'adm.set_silent' : 'adm.set_nokeys'))}</div>`}
      <div class="setrows"></div>`;
    const rowsBox = box.querySelector('.setrows');

    rows.forEach(s => {
      const r = document.createElement('div');
      r.className = 'setrow' + (s.overridden ? ' over' : '');
      r.innerHTML = `
        <span class="setlbl">${esc(s.label)}${s.hint ? `<i>${esc(s.hint)}</i>` : ''}</span>
        <span class="setval">${setInput(m.name, s)}</span>
        <button class="mini setsave">${esc(t('adm.ed_save'))}</button>
        <button class="mini setreset"${s.overridden ? '' : ' disabled'}>${esc(t('adm.set_reset'))}</button>`;

      // one control per row: no need to escape a module name into a CSS selector
      const el = r.querySelector('input, select');
      r.querySelector('.setsave').onclick = async (e) => {
        const b = e.currentTarget; b.disabled = true;
        const value = s.type === 'bool' ? el.checked
          : s.type === 'number' ? parseFloat(el.value)
          : el.value;
        const res = await post('setSetting', { module: m.name, key: s.key, value });
        flash(b, !!(res && res.ok));
        b.disabled = false;
        // patch the one value we changed rather than refetching the whole registry
        if (res && res.ok) {
          s.value = res.value !== undefined ? res.value : value;
          s.overridden = true;
          r.classList.add('over');
          r.querySelector('.setreset').disabled = false;
        }
      };
      r.querySelector('.setreset').onclick = async (e) => {
        const b = e.currentTarget; b.disabled = true;
        const res = await post('setSetting', { module: m.name, key: s.key, reset: true });
        flash(b, !!(res && res.ok));
        if (res && res.ok) {
          s.value = s.default; s.overridden = false;
          r.classList.remove('over');
          const c = r.querySelector('input, select');
          if (s.type === 'bool') c.checked = !!s.default; else c.value = s.default;
        }
        b.disabled = false;
      };
      rowsBox.appendChild(r);
    });
    nodes.push(box);
  });
  paint(wrap, nodes);
}

byId('setsearch').oninput = debounce(renderSettings, 140);

// ── Coordinates copy tool ──
function copyText(txt) {
  try { navigator.clipboard.writeText(txt); return; } catch (e) {}
  const ta = document.createElement('textarea');
  ta.value = txt; ta.style.position = 'fixed'; ta.style.opacity = '0';
  document.body.appendChild(ta); ta.select();
  try { document.execCommand('copy'); } catch (e) {}
  ta.remove();
}
async function renderCoords() {
  const d = await post('coords');
  if (!d || typeof d !== 'object') return;
  byId('c-v3').textContent = d.v3 || '—';
  byId('c-v4').textContent = d.v4 || '—';
  byId('c-h').textContent = d.heading || '—';
  byId('c-raw').textContent = d.raw || '—';
  byId('c-meta').textContent = [d.street, d.model].filter(Boolean).join(' · ');
}

// ══ World editor: blips / shop locations / jobs ══
let edDomain = 'blips', edData = { rows: [] };

async function loadEditor() {
  const res = await post('worldList', { domain: edDomain });
  edData = (res && typeof res === 'object') ? res : { rows: [] };
  byId('ed-form').classList.add('hidden');
  renderEdList();
}

function edRowTitle(r) {
  if (edDomain === 'blips') {
    const gate = [r.job ? `${r.job}${r.grade ? '+' + r.grade : ''}` : '', r.perm || ''].filter(Boolean).join(' / ');
    return `${esc(r.label)} <i class="dim">sprite ${r.sprite} · ${Math.round(r.x)}, ${Math.round(r.y)}${gate ? ' · 🔒 ' + esc(gate) : ''}</i>`;
  }
  if (edDomain === 'shops') return `${esc(r.shop)} <i class="dim">${Math.round(r.x)}, ${Math.round(r.y)} · ${r.ped ? esc(r.ped) : 'no ped'}</i>`;
  if (edDomain === 'items') return `${esc(r.label)} <i class="dim">${esc(r.name)} · ${esc(r.category)} · ${r.weight}g${r.usable ? ' · usable' : ''}</i>`;
  if (edDomain === 'uitheme') {
    // list only what this row overrides — the rest is inherited, and saying so is the point
    const bits = [];
    if (r.preset) bits.push(r.preset);
    if (r.accent) bits.push(r.accent);
    if (r.panel_alpha != null) bits.push(t('adm.ed_opacity') + ' ' + Number(r.panel_alpha).toFixed(2));
    if (r.backdrop_alpha != null) bits.push(t('adm.ed_backdrop') + ' ' + Number(r.backdrop_alpha).toFixed(2));
    if (r.radius != null) bits.push(t('adm.ed_radius') + ' ' + Number(r.radius).toFixed(2));
    if (r.motion != null) bits.push(t('adm.ed_motion') + ' ' + Number(r.motion).toFixed(2));
    if (r.font_scale != null) bits.push(t('adm.ed_fontscale') + ' ' + Number(r.font_scale).toFixed(2));
    return `${esc(r.module)} <i class="dim">${bits.length ? esc(bits.join(' · ')) : esc(t('adm.ed_inherits'))}</i>`;
  }
  if (edDomain === 'dealers') {
    return `${esc(r.label)} <i class="dim">${esc(r.id)} · ${Math.round(r.x)}, ${Math.round(r.y)} · ${esc(r.cats || t('adm.ed_allcats'))}${r.job ? ' · 🔒 ' + esc(r.job) : ''}</i>`;
  }
  if (edDomain === 'vehcat') {
    if (r.rent_deposit !== null && r.rent_deposit !== undefined) {
      return `${esc(r.label)} <i class="dim">${esc(r.model)} · ${esc(r.cat)} · ${fmt(r.price)}` +
        ` · 🔑 ${fmt(r.rent_deposit)}${r.job ? ' · 🔒 ' + esc(r.job) : ''}</i>`;
    }
  }
  if (edDomain === 'vehcat') {
    return `${esc(r.label)} <i class="dim">${esc(r.model)} · ${esc(r.cat)} · ${fmt(r.price)}${r.stock >= 0 ? ' · ' + r.stock + ' stock' : ''}${r.license ? ' · 🪪 ' + esc(r.license) : ''}${r.job ? ' · 🔒 ' + esc(r.job) : ''}</i>`;
  }
  if (edDomain === 'licenses') {
    return `${esc(r.label)} <i class="dim">${esc(r.key)} · ${esc(r.issuer)} · ${fmt(r.price)} · ${r.days ? r.days + 'd' : t('adm.ed_never')}${r.test ? ' · ' + t('adm.ed_needstest') : ''}</i>`;
  }
  if (edDomain === 'mechshops') {
    return `${esc(r.label)} <i class="dim">${esc(r.id)} · ${Math.round(r.x)}, ${Math.round(r.y)}${r.job ? ' · 🔒 ' + esc(r.job) : ' · self-service'} · x${(Number(r.mult) || 1).toFixed(2)}</i>`;
  }
  if (edDomain === 'stations') {
    return `${esc(r.label)} <i class="dim">${esc(r.id)} · ${esc(r.types)} · x${(Number(r.mult) || 1).toFixed(2)} · ${Math.round(r.x)}, ${Math.round(r.y)}</i>`;
  }
  if (edDomain === 'gangs') {
    const n = (r.grades || []).length;
    return `${esc(r.label)} <i class="dim">${esc(r.name)} · ${esc(r.type)} · ${n} ${esc(t('adm.ed_ranks'))}</i>`;
  }
  if (edDomain === 'turfs') {
    const owner = r.owner ? esc(r.owner) : esc(t('adm.ed_unclaimed'));
    return `${esc(r.label)} <i class="dim">${esc(r.id)} · ${Math.round(r.x)}, ${Math.round(r.y)}` +
      ` · r${Math.round(r.radius)} · ${owner} ${Math.round(r.influence || 0)}%</i>`;
  }
  if (edDomain === 'factions') {
    return `${esc(r.label)} <i class="dim">${esc(r.name)} · ${esc(r.kind)} · ` +
      `${esc(t('adm.ed_balance'))} ${fmt(r.balance)}</i>`;
  }
  if (edDomain === 'rentals') {
    return `${esc(r.label)} <i class="dim">${esc(r.id)} · ${Math.round(r.x)}, ${Math.round(r.y)}` +
      `${r.cats ? ' · ' + esc(r.cats) : ' · ' + esc(t('adm.ed_anycat'))}` +
      `${r.job ? ' · 🔒 ' + esc(r.job) : ''}</i>`;
  }
  if (edDomain === 'garages') {
    return `${esc(r.label)} <i class="dim">${esc(r.id)} · ${esc(r.type)} · ${Math.round(r.x)}, ${Math.round(r.y)}${r.job ? ' · 🔒 ' + esc(r.job) : ''}${r.fee ? ' · ' + fmt(r.fee) : ''}</i>`;
  }
  if (edDomain === 'clothstores') {
    return `${esc(r.label)} <i class="dim">${Math.round(r.x)}, ${Math.round(r.y)}${r.ped ? ' · ' + esc(r.ped) : ' · no ped'}${r.job ? ' · 🔒 ' + esc(r.job) : ''}</i>`;
  }
  if (edDomain === 'clothcats') {
    return `${esc(r.label)} <i class="dim">${esc(r.key)} · ${esc(r.kind)} ${r.slot} · ${fmt(r.price)} · ${esc(r.item)}</i>`;
  }
  if (edDomain === 'recipes') {
    const ing = Object.entries(r.inputs || {}).map(([k, v]) => `${v}× ${k}`).join(', ');
    return `${esc(r.output)} ×${r.count} <i class="dim">${esc(r.station)} · ${esc(ing)}</i>`;
  }
  return `${esc(r.label || r.name)} <i class="dim">${esc(r.name)} · ${esc(r.type || 'civ')} · ${(r.grades || []).length} ${t('adm.ed_grades')}${r.whitelisted ? ' · 🔒 ' + esc(t('adm.ed_wl')) : ''}</i>`;
}

function edFilter(rows) {
  const q = (byId('ed-search').value || '').trim().toLowerCase();
  if (!q) return rows;
  return rows.filter(r => JSON.stringify(r).toLowerCase().includes(q));
}

// The vehicle catalogue gets a scan bar: it enumerates every model this client can spawn
// (base game + any addon pack) and offers the ones missing from the catalogue.
let scanRows = null;

function renderScanBar(wrap) {
  const bar = document.createElement('div');
  bar.className = 'scanbar';
  bar.innerHTML = `
    <span class="sblbl">${esc(t('adm.veh_scan_hint'))}</span>
    <span class="spacer"></span>
    <button class="mini" id="vs-run">${esc(t('adm.veh_scan'))}</button>
    <button class="mini" id="vs-show"${scanRows ? '' : ' disabled'}>${esc(t('adm.veh_scan_review'))}${scanRows ? ' (' + scanRows.length + ')' : ''}</button>`;
  wrap.appendChild(bar);

  bar.querySelector('#vs-run').onclick = async (e) => {
    const b = e.currentTarget; b.disabled = true;
    b.textContent = t('adm.veh_scanning');
    await post('vehScan');
    // the scan runs on this client and reports to the server; poll once it has had time
    setTimeout(async () => {
      const res = await post('vehScanList');
      scanRows = (res && res.rows) || [];
      b.disabled = false; b.textContent = t('adm.veh_scan');
      renderEdList();
    }, 4000);
  };
  bar.querySelector('#vs-show').onclick = () => { if (scanRows) renderScanReview(); };
}

function renderScanReview() {
  const wrap = byId('ed-list'); wrap.innerHTML = '';
  const back = document.createElement('div');
  back.className = 'scanbar';
  back.innerHTML = `<span class="sblbl">${esc(t('adm.veh_scan_found'))} ${scanRows.length}</span>
    <span class="spacer"></span>
    <button class="mini" id="vs-back">${esc(t('adm.cancel'))}</button>
    <button class="mini accent" id="vs-import">${esc(t('adm.veh_import'))}</button>`;
  wrap.appendChild(back);
  back.querySelector('#vs-back').onclick = () => { renderEdList(); };
  back.querySelector('#vs-import').onclick = async (e) => {
    const b = e.currentTarget; b.disabled = true;
    const picked = [...wrap.querySelectorAll('.vs-row')]
      .filter(r => r.querySelector('.vs-cb').checked)
      .map(r => ({ model: r.dataset.model, cat: r.querySelector('.vs-cat').value,
                   price: parseInt(r.querySelector('.vs-price').value, 10) || 0 }));
    const res = await post('vehScanImport', { rows: picked });
    flash(b, !!(res && res.ok));
    if (res && res.ok) { scanRows = null; loadEditor(); }
    else b.disabled = false;
  };

  const scanNodes = [];
  scanRows.slice(0, 400).forEach((r, i) => {
    const el = document.createElement('div');
    el.className = 'edrow vs-row'; el.dataset.model = r.model; el.style.setProperty('--i', i);
    el.innerHTML = `
      <label class="vs-pick"><input type="checkbox" class="vs-cb" checked /></label>
      <span class="edname">${esc(r.label)} <i class="dim">${esc(r.model)}${r.top ? ' · ' + r.top + ' km/h' : ''}${r.seats ? ' · ' + r.seats + 'p' : ''}</i></span>
      <span class="edacts">
        <select class="vs-cat">${(edData.cats || []).map(c => `<option value="${esc(c)}"${c === r.cat ? ' selected' : ''}>${esc(c)}</option>`).join('')}</select>
        <input class="vs-price" type="number" value="${r.price}" />
      </span>`;
    scanNodes.push(el);
  });
  // 400 rows one at a time is 400 reflows; a fragment is one
  const sfrag = document.createDocumentFragment();
  scanNodes.forEach(n => sfrag.appendChild(n));
  wrap.appendChild(sfrag);
  if (scanRows.length > 400) {
    const more = document.createElement('div');
    more.className = 'empty-ed';
    more.textContent = t('adm.veh_scan_more') + ' ' + (scanRows.length - 400);
    wrap.appendChild(more);
  }
}

const ED_PAGE = 200;        // rows drawn at once; the rest is one click away
let edShown = ED_PAGE;

function renderEdList() {
  const wrap = byId('ed-list'); wrap.innerHTML = '';
  if (edDomain === 'vehcat') renderScanBar(wrap);
  const rows = edFilter(edData.rows || []);
  if (!rows.length) { wrap.appendChild(el('div', 'empty-ed', t('adm.ed_empty'))); return; }

  const nodes = [];
  rows.slice(0, edShown).forEach((r, i) => {
    const row = document.createElement('div'); row.className = 'edrow'; row.style.setProperty('--i', i);
    const off = (r.enabled === 0 || r.enabled === false);
    row.innerHTML = `<span class="edname${off ? ' off' : ''}">${edRowTitle(r)}</span>
      <span class="edacts">
        <button class="mini" data-act="edit">${esc(t('adm.ed_edit'))}</button>
        ${edDomain === 'factions' ? '' : `<button class="mini danger" data-act="del">${esc(t('adm.ed_del'))}</button>`}
      </span>`;
    row.querySelector('[data-act="edit"]').onclick = () => openEdForm(r);
    const delBtn = row.querySelector('[data-act="del"]');
    if (delBtn) delBtn.onclick = async () => {
      const id = (edDomain === 'jobs' || edDomain === 'items' || edDomain === 'gangs') ? r.name
        : (edDomain === 'clothcats' || edDomain === 'licenses') ? r.key
        : (edDomain === 'vehcat') ? r.model
        : (edDomain === 'uitheme') ? r.module : r.id;   // garages/dealers key on `id`
      const ok = await post('worldDelete', { domain: edDomain, id });
      if (ok && ok.ok) loadEditor();
    };
    nodes.push(row);
  });
  const frag = document.createDocumentFragment();
  nodes.forEach(n => frag.appendChild(n));
  wrap.appendChild(frag);

  // Never truncate silently: say how many are hidden and offer them.
  if (rows.length > edShown) {
    const more = document.createElement('button');
    more.className = 'mini showmore';
    more.textContent = `${t('adm.ed_showmore')} (${rows.length - edShown})`;
    more.onclick = () => { edShown += ED_PAGE; renderEdList(); };
    wrap.appendChild(more);
  }
}

// tiny element helper, used where a node is simpler than an innerHTML string
function el(tag, cls, text) {
  const n = document.createElement(tag);
  if (cls) n.className = cls;
  if (text !== undefined) n.textContent = text;
  return n;
}

const field = (label, id, val, type) =>
  `<label class="edf"><span>${esc(label)}</span><input id="${id}" type="${type || 'text'}" value="${esc(val ?? '')}" /></label>`;
const check = (label, id, on) =>
  `<label class="edf chk"><input id="${id}" type="checkbox" ${on ? 'checked' : ''} /><span>${esc(label)}</span></label>`;

function openEdForm(row) {
  row = row || {};
  const f = byId('ed-form'); f.classList.remove('hidden');
  let html = '';
  if (edDomain === 'blips') {
    const presets = (edData.presets || []).map(p => `<option value="${p.sprite}"${p.sprite == row.sprite ? ' selected' : ''}>${esc(p.label)} (${p.sprite})</option>`).join('');
    const colors = (edData.colors || []).map(c => `<option value="${c.color}"${c.color == row.color ? ' selected' : ''}>${esc(c.label)} (${c.color})</option>`).join('');
    html = field(t('adm.ed_label'), 'ef-label', row.label) +
      `<label class="edf"><span>${esc(t('adm.ed_sprite'))}</span><select id="ef-sprite">${presets}</select></label>` +
      `<label class="edf"><span>${esc(t('adm.ed_color'))}</span><select id="ef-color">${colors}</select></label>` +
      field(t('adm.ed_scale'), 'ef-scale', row.scale ?? 0.8, 'number') +
      field('X', 'ef-x', row.x ?? '', 'number') + field('Y', 'ef-y', row.y ?? '', 'number') + field('Z', 'ef-z', row.z ?? '', 'number') +
      // Visibility gate — empty option = visible to everyone.
      `<label class="edf"><span>${esc(t('adm.ed_onlyjob'))}</span><select id="ef-job">` +
        `<option value="">${esc(t('adm.ed_everyone'))}</option>` +
        (edData.jobs || []).map(j => `<option value="${esc(j.name)}"${j.name === row.job ? ' selected' : ''}>${esc(j.label || j.name)}</option>`).join('') +
      `</select></label>` +
      field(t('adm.ed_mingrade'), 'ef-grade', row.grade ?? 0, 'number') +
      `<label class="edf"><span>${esc(t('adm.ed_onlyperm'))}</span><select id="ef-perm">` +
        `<option value="">${esc(t('adm.ed_everyone'))}</option>` +
        (edData.perms || []).map(p => `<option value="${esc(p)}"${p === row.perm ? ' selected' : ''}>${esc(p)}</option>`).join('') +
      `</select></label>` +
      check(t('adm.ed_short'), 'ef-short', row.shortrange !== 0) + check(t('adm.ed_enabled'), 'ef-en', row.enabled !== 0);
  } else if (edDomain === 'shops') {
    const shops = (edData.shops || []).map(s => `<option value="${esc(s.id)}"${s.id === row.shop ? ' selected' : ''}>${esc(s.label)} (${esc(s.id)})</option>`).join('');
    html = `<label class="edf"><span>${esc(t('adm.ed_shop'))}</span><select id="ef-shop">${shops}</select></label>` +
      field('X', 'ef-x', row.x ?? '', 'number') + field('Y', 'ef-y', row.y ?? '', 'number') +
      field('Z', 'ef-z', row.z ?? '', 'number') + field(t('adm.ed_head'), 'ef-h', row.h ?? 0, 'number') +
      field(t('adm.ed_ped'), 'ef-ped', row.ped ?? '') +
      check(t('adm.ed_blip'), 'ef-blip', row.blip !== 0) + check(t('adm.ed_enabled'), 'ef-en', row.enabled !== 0);
  } else if (edDomain === 'items') {
    const isNew = !row.name;
    const cats = (edData.categories || []).map(c => `<option value="${esc(c)}"${c === row.category ? ' selected' : ''}>${esc(c)}</option>`).join('');
    const m = row.metadata || {};
    const types = (edData.types || []).map(x => `<option value="${esc(x)}"${x === m.type ? ' selected' : ''}>${esc(x)}</option>`).join('');
    html =
      `<label class="edf"><span>${esc(t('adm.ed_itemname'))}</span><input id="ef-name" value="${esc(row.name ?? '')}" ${isNew ? '' : 'disabled'} /></label>` +
      field(t('adm.ed_label'), 'ef-label', row.label) +
      `<label class="edf"><span>${esc(t('adm.ed_cat'))}</span><select id="ef-cat">${cats}</select></label>` +
      `<label class="edf"><span>${esc(t('adm.ed_itype'))}</span><select id="ef-itype">${types}</select></label>` +
      field(t('adm.ed_weight'), 'ef-weight', row.weight ?? 100, 'number') +
      field(t('adm.ed_image'), 'ef-image', row.image ?? '') +
      field(t('adm.ed_rarity'), 'ef-rarity', m.rarity ?? 'common') +
      field(t('adm.ed_desc'), 'ef-desc', m.desc ?? '') +
      check(t('adm.ed_stack'), 'ef-stack', row.stackable !== 0) + check(t('adm.ed_usable'), 'ef-usable', row.usable === 1);
  } else if (edDomain === 'uitheme') {
    const isNew = !row.module;
    const mods = (edData.modules || []).map(m =>
      `<option value="${esc(m.name)}"${m.name === row.module ? ' selected' : ''}>${esc(m.label)} (${esc(m.name)})</option>`).join('');
    const presets = (edData.presets || []).map(p =>
      `<option value="${esc(p.key)}"${p.key === row.preset ? ' selected' : ''}>${esc(p.label || p.key)}</option>`).join('');
    // a blank field means INHERIT — never 0, which would read as a deliberate
    // "fully transparent" or "no roundness"
    const optNum = (label, id, val) =>
      `<label class="edf"><span>${esc(label)}</span><input id="${id}" type="number" step="any" ` +
      `value="${val === null || val === undefined ? '' : esc(val)}" placeholder="${esc(t('adm.ed_inherit'))}" /></label>`;
    html =
      `<label class="edf"><span>${esc(t('adm.ed_module'))}</span><select id="ef-mod" ${isNew ? '' : 'disabled'}>${mods}</select></label>` +
      `<label class="edf"><span>${esc(t('adm.ed_preset'))}</span><select id="ef-preset">` +
        `<option value="">${esc(t('adm.ed_inherit'))}</option>${presets}</select></label>` +
      `<label class="edf"><span>${esc(t('adm.ed_accent'))}</span>` +
        `<input id="ef-accent" type="text" value="${esc(row.accent || '')}" placeholder="${esc(t('adm.ed_inherit'))}" /></label>` +
      optNum(t('adm.ed_opacity'), 'ef-pa', row.panel_alpha) +
      optNum(t('adm.ed_backdrop'), 'ef-ba', row.backdrop_alpha) +
      optNum(t('adm.ed_radius'), 'ef-rad', row.radius) +
      optNum(t('adm.ed_motion'), 'ef-mot', row.motion) +
      optNum(t('adm.ed_fontscale'), 'ef-fs', row.font_scale) +
      check(t('adm.ed_enabled'), 'ef-en', row.enabled !== 0);
  } else if (edDomain === 'dealers') {
    const isNew = !row.id;
    const have = String(row.cats || '').split(',').map(x => x.trim()).filter(Boolean);
    const boxes = (edData.cats || []).map(c =>
      `<label class="edf chk"><input type="checkbox" class="cat-cb" value="${esc(c)}"${have.includes(c) ? ' checked' : ''} /><span>${esc(c)}</span></label>`).join('');
    html =
      `<label class="edf"><span>${esc(t('adm.ed_dealerid'))}</span><input id="ef-did" value="${esc(row.id ?? '')}" ${isNew ? '' : 'disabled'} /></label>` +
      field(t('adm.ed_label'), 'ef-label', row.label) +
      field('X', 'ef-x', row.x ?? '', 'number') + field('Y', 'ef-y', row.y ?? '', 'number') + field('Z', 'ef-z', row.z ?? '', 'number') +
      field(t('adm.ed_spawnx'), 'ef-sx', row.sx ?? '', 'number') + field(t('adm.ed_spawny'), 'ef-sy', row.sy ?? '', 'number') +
      field(t('adm.ed_spawnz'), 'ef-sz', row.sz ?? '', 'number') + field(t('adm.ed_spawnh'), 'ef-sh', row.sh ?? 0, 'number') +
      `<div class="edf full"><span>${esc(t('adm.ed_sellscats'))}</span><div class="ftypes">${boxes}</div></div>` +
      `<label class="edf"><span>${esc(t('adm.ed_onlyjob'))}</span><select id="ef-job">` +
        `<option value="">${esc(t('adm.ed_everyone'))}</option>` +
        (edData.jobs || []).map(j => `<option value="${esc(j.name)}"${j.name === row.job ? ' selected' : ''}>${esc(j.label || j.name)}</option>`).join('') +
      `</select></label>` +
      check(t('adm.ed_blip'), 'ef-blip', row.blip !== 0) + check(t('adm.ed_enabled'), 'ef-en', row.enabled !== 0);
  } else if (edDomain === 'vehcat') {
    const isNew = !row.model;
    const cats = (edData.cats || []).map(c => `<option value="${esc(c)}"${c === row.cat ? ' selected' : ''}>${esc(c)}</option>`).join('');
    const lics = (edData.licenses || []).map(l => `<option value="${esc(l.key)}"${l.key === row.license ? ' selected' : ''}>${esc(l.label || l.key)}</option>`).join('');
    html =
      `<label class="edf"><span>${esc(t('adm.ed_vehmodel'))}</span><input id="ef-model" value="${esc(row.model ?? '')}" ${isNew ? '' : 'disabled'} /></label>` +
      field(t('adm.ed_label'), 'ef-label', row.label) +
      `<label class="edf"><span>${esc(t('adm.ed_cat'))}</span><select id="ef-cat">${cats}</select></label>` +
      field(t('adm.ed_price'), 'ef-price', row.price ?? 0, 'number') +
      field(t('adm.ed_stock'), 'ef-stock', row.stock ?? -1, 'number') +
      // blank = not rentable. NOT 0, which would be a free hire with no deposit.
      `<label class="edf"><span>${esc(t('adm.ed_rentdep'))}</span><input id="ef-rdep" type="number" ` +
        `value="${row.rent_deposit ?? ''}" placeholder="${esc(t('adm.ed_norent'))}" /></label>` +
      `<label class="edf"><span>${esc(t('adm.ed_rentfee'))}</span><input id="ef-rfee" type="number" ` +
        `value="${row.rent_fee ?? ''}" placeholder="${esc(t('adm.ed_norent'))}" /></label>` +
      `<label class="edf"><span>${esc(t('adm.ed_reqlic'))}</span><select id="ef-lic">` +
        `<option value="">${esc(t('adm.ed_byclass'))}</option>${lics}</select></label>` +
      `<label class="edf"><span>${esc(t('adm.ed_onlyjob'))}</span><select id="ef-job">` +
        `<option value="">${esc(t('adm.ed_everyone'))}</option>` +
        (edData.jobs || []).map(j => `<option value="${esc(j.name)}"${j.name === row.job ? ' selected' : ''}>${esc(j.label || j.name)}</option>`).join('') +
      `</select></label>` +
      check(t('adm.ed_enabled'), 'ef-en', row.enabled !== 0);
  } else if (edDomain === 'licenses') {
    const isNew = !row.key;
    const issuers = (edData.places || []).map(p => `<option value="${esc(p)}"${p === row.issuer ? ' selected' : ''}>${esc(p)}</option>`).join('')
      + (edData.jobs || []).map(j => `<option value="${esc(j.name)}"${j.name === row.issuer ? ' selected' : ''}>${esc(j.label || j.name)}</option>`).join('');
    html =
      `<label class="edf"><span>${esc(t('adm.ed_lickey'))}</span><input id="ef-lkey" value="${esc(row.key ?? '')}" ${isNew ? '' : 'disabled'} /></label>` +
      field(t('adm.ed_label'), 'ef-label', row.label) +
      `<label class="edf"><span>${esc(t('adm.ed_issuer'))}</span><select id="ef-issuer">${issuers}</select></label>` +
      field(t('adm.ed_price'), 'ef-price', row.price ?? 0, 'number') +
      field(t('adm.ed_validdays'), 'ef-days', row.days ?? 0, 'number') +
      field(t('adm.ed_sort'), 'ef-sort', row.sort ?? 0, 'number') +
      check(t('adm.ed_needstest'), 'ef-test', row.test === 1 || row.test === true) +
      check(t('adm.ed_enabled'), 'ef-en', row.enabled !== 0);
  } else if (edDomain === 'mechshops') {
    const isNew = !row.id;
    html =
      `<label class="edf"><span>${esc(t('adm.ed_mechid'))}</span><input id="ef-mid" value="${esc(row.id ?? '')}" ${isNew ? '' : 'disabled'} /></label>` +
      field(t('adm.ed_label'), 'ef-label', row.label) +
      field('X', 'ef-x', row.x ?? '', 'number') + field('Y', 'ef-y', row.y ?? '', 'number') + field('Z', 'ef-z', row.z ?? '', 'number') +
      `<label class="edf"><span>${esc(t('adm.ed_onlyjob'))}</span><select id="ef-job">` +
        `<option value="">${esc(t('adm.ed_selfserv'))}</option>` +
        (edData.jobs || []).map(j => `<option value="${esc(j.name)}"${j.name === row.job ? ' selected' : ''}>${esc(j.label || j.name)}</option>`).join('') +
      `</select></label>` +
      field(t('adm.ed_labourmult'), 'ef-mult', row.mult ?? 1.0, 'number') +
      check(t('adm.ed_blip'), 'ef-blip', row.blip !== 0) + check(t('adm.ed_enabled'), 'ef-en', row.enabled !== 0);
  } else if (edDomain === 'stations') {
    const isNew = !row.id;
    const have = String(row.types || 'regular').split(',').map(x => x.trim());
    const boxes = (edData.types || []).map(k =>
      `<label class="edf chk"><input type="checkbox" class="ftype-cb" value="${esc(k)}"${have.includes(k) ? ' checked' : ''} /><span>${esc(k)}</span></label>`).join('');
    html =
      `<label class="edf"><span>${esc(t('adm.ed_statid'))}</span><input id="ef-sid" value="${esc(row.id ?? '')}" ${isNew ? '' : 'disabled'} /></label>` +
      field(t('adm.ed_label'), 'ef-label', row.label) +
      field('X', 'ef-x', row.x ?? '', 'number') + field('Y', 'ef-y', row.y ?? '', 'number') + field('Z', 'ef-z', row.z ?? '', 'number') +
      `<div class="edf full"><span>${esc(t('adm.ed_fueltypes'))}</span><div class="ftypes">${boxes}</div></div>` +
      field(t('adm.ed_pricemult'), 'ef-mult', row.mult ?? 1.0, 'number') +
      check(t('adm.ed_blip'), 'ef-blip', row.blip !== 0) + check(t('adm.ed_enabled'), 'ef-en', row.enabled !== 0);
  } else if (edDomain === 'gangs') {
    const isNew = !row.name;
    html =
      `<label class="edf"><span>${esc(t('adm.ed_jobid'))}</span>` +
        `<input id="ef-gname" value="${esc(row.name ?? '')}" ${isNew ? '' : 'disabled'} /></label>` +
      field(t('adm.ed_label'), 'ef-label', row.label) +
      `<label class="edf"><span>${esc(t('adm.ed_type'))}</span><select id="ef-type">` +
        ['gang', 'mafia'].map(x =>
          `<option value="${x}"${x === row.type ? ' selected' : ''}>${x}</option>`).join('') +
      `</select></label>` +
      `<label class="edf"><span>${esc(t('adm.ed_ranks'))}</span>` +
        `<textarea id="ef-grades" rows="5">${esc(JSON.stringify(row.grades || [{ grade: 0, name: 'Member', salary: 0 }]))}</textarea></label>`;
  } else if (edDomain === 'turfs') {
    const isNew = !row.id;
    const gangs = (edData.gangs || []).map(g =>
      `<option value="${esc(g.name)}"${g.name === row.owner ? ' selected' : ''}>${esc(g.label || g.name)}</option>`).join('');
    html =
      `<label class="edf"><span>${esc(t('adm.ed_garid'))}</span>` +
        `<input id="ef-tid" value="${esc(row.id ?? '')}" ${isNew ? '' : 'disabled'} /></label>` +
      field(t('adm.ed_label'), 'ef-label', row.label) +
      field('X', 'ef-x', row.x ?? '', 'number') + field('Y', 'ef-y', row.y ?? '', 'number') +
      field('Z', 'ef-z', row.z ?? '', 'number') +
      field(t('adm.ed_radius2'), 'ef-rad', row.radius ?? 90, 'number') +
      // handing a turf over is an ownership change, not an edit: it is logged like a capture
      `<label class="edf"><span>${esc(t('adm.ed_owner'))}</span><select id="ef-owner">` +
        `<option value="">${esc(t('adm.ed_unclaimed'))}</option>${gangs}</select></label>` +
      check(t('adm.ed_blip'), 'ef-blip', row.blip !== 0) + check(t('adm.ed_enabled'), 'ef-en', row.enabled !== 0);
  } else if (edDomain === 'factions') {
    // The balance is shown, never typed: the only way it moves is a signed adjustment
    // that lands in the transaction log with a reason next to it.
    html =
      `<label class="edf"><span>${esc(t('adm.ed_faction'))}</span>` +
        `<input id="ef-fac" value="${esc(row.label ?? '')}" disabled /></label>` +
      `<label class="edf"><span>${esc(t('adm.ed_balance'))}</span>` +
        `<input id="ef-bal" value="${fmt(row.balance ?? 0)}" disabled /></label>` +
      field(t('adm.ed_adjust'), 'ef-delta', '', 'number') +
      field(t('adm.ed_reason'), 'ef-reason', '');
  } else if (edDomain === 'rentals') {
    const isNew = !row.id;
    html =
      `<label class="edf"><span>${esc(t('adm.ed_garid'))}</span><input id="ef-rid" value="${esc(row.id ?? '')}" ${isNew ? '' : 'disabled'} /></label>` +
      field(t('adm.ed_label'), 'ef-label', row.label) +
      field('X', 'ef-x', row.x ?? '', 'number') + field('Y', 'ef-y', row.y ?? '', 'number') + field('Z', 'ef-z', row.z ?? '', 'number') +
      field(t('adm.ed_spawnx'), 'ef-sx', row.sx ?? '', 'number') + field(t('adm.ed_spawny'), 'ef-sy', row.sy ?? '', 'number') +
      field(t('adm.ed_spawnz'), 'ef-sz', row.sz ?? '', 'number') + field(t('adm.ed_spawnh'), 'ef-sh', row.sh ?? 0, 'number') +
      // a comma list rather than a multi-select: the categories come from config and an
      // operator adding one should not have to wait for a UI change
      `<label class="edf"><span>${esc(t('adm.ed_rentcats'))}</span>` +
        `<input id="ef-cats" value="${esc(row.cats ?? '')}" placeholder="${esc((edData.cats || []).join(', '))}" /></label>` +
      `<label class="edf"><span>${esc(t('adm.ed_onlyjob'))}</span><select id="ef-job">` +
        `<option value="">${esc(t('adm.ed_everyone'))}</option>` +
        (edData.jobs || []).map(j => `<option value="${esc(j.name)}"${j.name === row.job ? ' selected' : ''}>${esc(j.label || j.name)}</option>`).join('') +
      `</select></label>` +
      check(t('adm.ed_blip'), 'ef-blip', row.blip !== 0) + check(t('adm.ed_enabled'), 'ef-en', row.enabled !== 0);
  } else if (edDomain === 'garages') {
    const isNew = !row.id;
    const types = (edData.types || ['public'])
      .map(x => `<option value="${esc(x)}"${x === row.type ? ' selected' : ''}>${esc(x)}</option>`).join('');
    html =
      `<label class="edf"><span>${esc(t('adm.ed_garid'))}</span><input id="ef-gid" value="${esc(row.id ?? '')}" ${isNew ? '' : 'disabled'} /></label>` +
      field(t('adm.ed_label'), 'ef-label', row.label) +
      `<label class="edf"><span>${esc(t('adm.ed_gartype'))}</span><select id="ef-type">${types}</select></label>` +
      field('X', 'ef-x', row.x ?? '', 'number') + field('Y', 'ef-y', row.y ?? '', 'number') + field('Z', 'ef-z', row.z ?? '', 'number') +
      field(t('adm.ed_spawnx'), 'ef-sx', row.sx ?? '', 'number') + field(t('adm.ed_spawny'), 'ef-sy', row.sy ?? '', 'number') +
      field(t('adm.ed_spawnz'), 'ef-sz', row.sz ?? '', 'number') + field(t('adm.ed_spawnh'), 'ef-sh', row.sh ?? 0, 'number') +
      `<label class="edf"><span>${esc(t('adm.ed_onlyjob'))}</span><select id="ef-job">` +
        `<option value="">${esc(t('adm.ed_everyone'))}</option>` +
        (edData.jobs || []).map(j => `<option value="${esc(j.name)}"${j.name === row.job ? ' selected' : ''}>${esc(j.label || j.name)}</option>`).join('') +
      `</select></label>` +
      field(t('adm.ed_fee'), 'ef-fee', row.fee ?? 0, 'number') +
      check(t('adm.ed_blip'), 'ef-blip', row.blip !== 0) + check(t('adm.ed_enabled'), 'ef-en', row.enabled !== 0);
  } else if (edDomain === 'clothstores') {
    html = field(t('adm.ed_label'), 'ef-label', row.label ?? '') +
      field('X', 'ef-x', row.x ?? '', 'number') + field('Y', 'ef-y', row.y ?? '', 'number') +
      field('Z', 'ef-z', row.z ?? '', 'number') + field(t('adm.ed_head'), 'ef-h', row.h ?? 0, 'number') +
      field(t('adm.ed_ped'), 'ef-ped', row.ped ?? '') +
      `<label class="edf"><span>${esc(t('adm.ed_onlyjob'))}</span><select id="ef-job">` +
        `<option value="">${esc(t('adm.ed_everyone'))}</option>` +
        (edData.jobs || []).map(j => `<option value="${esc(j.name)}"${j.name === row.job ? ' selected' : ''}>${esc(j.label || j.name)}</option>`).join('') +
      `</select></label>` +
      check(t('adm.ed_blip'), 'ef-blip', row.blip !== 0) + check(t('adm.ed_enabled'), 'ef-en', row.enabled !== 0);
  } else if (edDomain === 'clothcats') {
    const isNew = !row.key;
    const kinds = (edData.kinds || ['comp', 'prop'])
      .map(k => `<option value="${esc(k)}"${k === row.kind ? ' selected' : ''}>${esc(k)}</option>`).join('');
    const frs = (edData.framings || [])
      .map(f => `<option value="${esc(f)}"${f === row.framing ? ' selected' : ''}>${esc(f)}</option>`).join('');
    html =
      `<label class="edf"><span>${esc(t('adm.ed_catkey'))}</span><input id="ef-key" value="${esc(row.key ?? '')}" ${isNew ? '' : 'disabled'} /></label>` +
      field(t('adm.ed_label'), 'ef-label', row.label) +
      `<label class="edf"><span>${esc(t('adm.ed_kind'))}</span><select id="ef-kind">${kinds}</select></label>` +
      field(t('adm.ed_slot'), 'ef-slot', row.slot ?? 0, 'number') +
      field(t('adm.ed_catitem'), 'ef-item', row.item ?? '') +
      field(t('adm.ed_price'), 'ef-price', row.price ?? 0, 'number') +
      `<label class="edf"><span>${esc(t('adm.ed_framing'))}</span><select id="ef-framing">${frs}</select></label>` +
      field(t('adm.ed_sort'), 'ef-sort', row.sort ?? 0, 'number') +
      check(t('adm.ed_enabled'), 'ef-en', row.enabled !== 0);
  } else if (edDomain === 'recipes') {
    const stations = (edData.stations || []).map(s => `<option value="${esc(s)}"${s === row.station ? ' selected' : ''}>${esc(s)}</option>`).join('');
    const opts = (edData.items || []).map(i => `<option value="${esc(i.name)}"${i.name === row.output ? ' selected' : ''}>${esc(i.label)} (${esc(i.name)})</option>`).join('');
    html = `<label class="edf"><span>${esc(t('adm.ed_station'))}</span><select id="ef-station">${stations}</select></label>` +
      `<label class="edf"><span>${esc(t('adm.ed_output'))}</span><select id="ef-output">${opts}</select></label>` +
      field(t('adm.ed_count'), 'ef-count', row.count ?? 1, 'number') +
      field(t('adm.ed_time'), 'ef-time', row.time ?? 3000, 'number') +
      check(t('adm.ed_enabled'), 'ef-en', row.enabled !== 0) +
      `<div class="grades" id="ef-ing"></div><button class="mini" id="ef-adding">+ ${esc(t('adm.ed_ingredient'))}</button>`;
  } else {
    html = field(t('adm.ed_jobid'), 'ef-name', row.name) + field(t('adm.ed_label'), 'ef-label', row.label) +
      field(t('adm.ed_type'), 'ef-type', row.type || 'civ') +
      check(t('adm.ed_wl'), 'ef-wl', row.whitelisted === 1 || row.whitelisted === true) +
      `<div class="grades" id="ef-grades"></div><button class="mini" id="ef-addgrade">+ ${esc(t('adm.ed_grade'))}</button>`;
  }
  f.innerHTML = `<div class="edfields">${html}</div>
    <div class="edbtns">
      ${(edDomain === 'blips' || edDomain === 'shops' || edDomain === 'clothstores' || edDomain === 'garages' || edDomain === 'rentals' || edDomain === 'turfs' || edDomain === 'stations' || edDomain === 'mechshops' || edDomain === 'dealers') ? `<button class="mini" id="ef-here">${esc(t('adm.ed_here'))}</button>` : ''}
      <span class="spacer"></span>
      <button class="mini" id="ef-cancel">${esc(t('adm.cancel'))}</button>
      <button class="mini accent" id="ef-save">${esc(t('adm.ed_save'))}</button>
    </div>`;

  if (edDomain === 'jobs') {
    const g = byId('ef-grades');
    const addGrade = (gr) => {
      const d = document.createElement('div'); d.className = 'grow';
      d.innerHTML = `<input class="gin sm" placeholder="#" type="number" value="${esc(gr?.grade ?? 0)}" />
        <input class="gin" placeholder="${esc(t('adm.ed_gradename'))}" value="${esc(gr?.name ?? '')}" />
        <input class="gin sm" placeholder="$" type="number" value="${esc(gr?.salary ?? 0)}" />
        <button class="mini danger grem">×</button>`;
      d.querySelector('.grem').onclick = () => d.remove();
      g.appendChild(d);
    };
    (row.grades && row.grades.length ? row.grades : [{ grade: 0, name: 'Employee', salary: 0 }]).forEach(addGrade);
    byId('ef-addgrade').onclick = () => addGrade({ grade: g.children.length, name: '', salary: 0 });
  }

  if (edDomain === 'recipes') {
    const box = byId('ef-ing');
    const itemOpts = (sel) => (edData.items || [])
      .map(i => `<option value="${esc(i.name)}"${i.name === sel ? ' selected' : ''}>${esc(i.label)} (${esc(i.name)})</option>`).join('');
    const addIng = (name, qty) => {
      const d = document.createElement('div'); d.className = 'grow';
      d.innerHTML = `<select class="gin ing-name">${itemOpts(name)}</select>
        <input class="gin sm ing-qty" type="number" min="1" value="${esc(qty ?? 1)}" />
        <button class="mini danger grem">×</button>`;
      d.querySelector('.grem').onclick = () => d.remove();
      box.appendChild(d);
    };
    const cur = Object.entries(row.inputs || {});
    if (cur.length) cur.forEach(([n, q]) => addIng(n, q)); else addIng(undefined, 1);
    byId('ef-adding').onclick = () => addIng(undefined, 1);
  }

  if (edDomain === 'dealers' && !row.id) {
    const dd = byId('ef-did');
    dd.oninput = () => { dd.value = dd.value.toLowerCase().replace(/[^a-z0-9_]/g, '').slice(0, 40); };
  }
  if (edDomain === 'vehcat' && !row.model) {
    const vm = byId('ef-model');
    vm.oninput = () => { vm.value = vm.value.toLowerCase().replace(/[^a-z0-9_]/g, '').slice(0, 50); };
  }
  if (edDomain === 'licenses' && !row.key) {
    const lk = byId('ef-lkey');
    lk.oninput = () => { lk.value = lk.value.toLowerCase().replace(/[^a-z0-9_]/g, '').slice(0, 40); };
  }

  if (edDomain === 'mechshops' && !row.id) {
    const mm = byId('ef-mid');
    mm.oninput = () => { mm.value = mm.value.toLowerCase().replace(/[^a-z0-9_]/g, '').slice(0, 40); };
  }

  if (edDomain === 'stations' && !row.id) {
    const st = byId('ef-sid');
    st.oninput = () => { st.value = st.value.toLowerCase().replace(/[^a-z0-9_]/g, '').slice(0, 40); };
  }

  if (edDomain === 'turfs' && !row.id) {
    const e = byId('ef-tid');
    e.oninput = () => { e.value = e.value.toLowerCase().replace(/[^a-z0-9_-]/g, '').slice(0, 40); };
  }

  if (edDomain === 'gangs' && !row.name) {
    const e = byId('ef-gname');
    e.oninput = () => { e.value = e.value.toLowerCase().replace(/[^a-z0-9_]/g, '').slice(0, 50); };
  }

  if (edDomain === 'rentals' && !row.id) {
    const r = byId('ef-rid');
    r.oninput = () => { r.value = r.value.toLowerCase().replace(/[^a-z0-9_-]/g, '').slice(0, 40); };
  }

  if (edDomain === 'garages' && !row.id) {
    const g = byId('ef-gid');
    g.oninput = () => { g.value = g.value.toLowerCase().replace(/[^a-z0-9_]/g, '').slice(0, 40); };
  }

  if (edDomain === 'clothcats' && !row.key) {
    const k = byId('ef-key');
    k.oninput = () => { k.value = k.value.toLowerCase().replace(/[^a-z0-9_]/g, '').slice(0, 30); };
  }

  if (edDomain === 'items' && !row.name) {
    // Mirror the server-side slug so the admin sees the real internal name before saving.
    const n = byId('ef-name');
    n.oninput = () => { n.value = n.value.toLowerCase().replace(/[^a-z0-9_]/g, '').slice(0, 50); };
  }

  const here = byId('ef-here');
  if (here) here.onclick = async () => {
    const c = await post('coords');
    if (!c || !c.raw) return;
    const p = c.raw.split(',').map(s => parseFloat(s.trim()));
    if (byId('ef-x')) byId('ef-x').value = p[0];
    if (byId('ef-y')) byId('ef-y').value = p[1];
    if (byId('ef-z')) byId('ef-z').value = p[2];
    if (byId('ef-h')) byId('ef-h').value = parseFloat(c.heading) || 0;
  };
  byId('ef-cancel').onclick = () => f.classList.add('hidden');
  byId('ef-save').onclick = async () => {
    const v = (id) => { const el = byId(id); return el ? el.value : undefined; };
    const ck = (id) => { const el = byId(id); return el ? el.checked : false; };
    let payload;
    if (edDomain === 'blips') {
      payload = { id: row.id, label: v('ef-label'), sprite: +v('ef-sprite'), color: +v('ef-color'),
                  scale: parseFloat(v('ef-scale')) || 0.8, x: parseFloat(v('ef-x')), y: parseFloat(v('ef-y')),
                  z: parseFloat(v('ef-z')), job: v('ef-job'), grade: parseInt(v('ef-grade'), 10) || 0,
                  perm: v('ef-perm'), shortrange: ck('ef-short'), enabled: ck('ef-en') };
    } else if (edDomain === 'shops') {
      payload = { id: row.id, shop: v('ef-shop'), x: parseFloat(v('ef-x')), y: parseFloat(v('ef-y')),
                  z: parseFloat(v('ef-z')), h: parseFloat(v('ef-h')) || 0, ped: v('ef-ped'),
                  blip: ck('ef-blip'), enabled: ck('ef-en') };
    } else if (edDomain === 'items') {
      payload = { name: v('ef-name'), isNew: !row.name, label: v('ef-label'), category: v('ef-cat'),
                  itype: v('ef-itype'), weight: parseInt(v('ef-weight'), 10) || 0, image: v('ef-image'),
                  rarity: v('ef-rarity'), desc: v('ef-desc'), stackable: ck('ef-stack'), usable: ck('ef-usable') };
    } else if (edDomain === 'uitheme') {
      payload = { module: v('ef-mod'), preset: v('ef-preset'), accent: v('ef-accent'),
                  panelAlpha: v('ef-pa'), backdropAlpha: v('ef-ba'), radius: v('ef-rad'),
                  motion: v('ef-mot'), fontScale: v('ef-fs'), enabled: ck('ef-en') };
    } else if (edDomain === 'dealers') {
      const cats = [...document.querySelectorAll('.cat-cb')].filter(c => c.checked).map(c => c.value);
      payload = { did: v('ef-did'), isNew: !row.id, label: v('ef-label'),
                  x: parseFloat(v('ef-x')), y: parseFloat(v('ef-y')), z: parseFloat(v('ef-z')),
                  sx: parseFloat(v('ef-sx')), sy: parseFloat(v('ef-sy')), sz: parseFloat(v('ef-sz')),
                  sh: parseFloat(v('ef-sh')) || 0, cats: cats.join(','), job: v('ef-job'),
                  blip: ck('ef-blip'), enabled: ck('ef-en') };
    } else if (edDomain === 'vehcat') {
      payload = { model: v('ef-model'), isNew: !row.model, label: v('ef-label'), cat: v('ef-cat'),
                  price: parseInt(v('ef-price'), 10) || 0,
                  stock: parseInt(v('ef-stock'), 10),
                  license: v('ef-lic'), job: v('ef-job'), enabled: ck('ef-en'),
                  rentDeposit: v('ef-rdep'), rentFee: v('ef-rfee') };
    } else if (edDomain === 'licenses') {
      payload = { key: v('ef-lkey'), isNew: !row.key, label: v('ef-label'), issuer: v('ef-issuer'),
                  price: parseInt(v('ef-price'), 10) || 0, days: parseInt(v('ef-days'), 10) || 0,
                  sort: parseInt(v('ef-sort'), 10) || 0, test: ck('ef-test'), enabled: ck('ef-en') };
    } else if (edDomain === 'mechshops') {
      payload = { mid: v('ef-mid'), isNew: !row.id, label: v('ef-label'),
                  x: parseFloat(v('ef-x')), y: parseFloat(v('ef-y')), z: parseFloat(v('ef-z')),
                  job: v('ef-job'), mult: parseFloat(v('ef-mult')) || 1.0,
                  blip: ck('ef-blip'), enabled: ck('ef-en') };
    } else if (edDomain === 'stations') {
      const types = [...document.querySelectorAll('.ftype-cb')].filter(c => c.checked).map(c => c.value);
      payload = { sid: v('ef-sid'), isNew: !row.id, label: v('ef-label'),
                  x: parseFloat(v('ef-x')), y: parseFloat(v('ef-y')), z: parseFloat(v('ef-z')),
                  types: types.join(','), mult: parseFloat(v('ef-mult')) || 1.0,
                  blip: ck('ef-blip'), enabled: ck('ef-en') };
    } else if (edDomain === 'gangs') {
      let grades = [];
      try { grades = JSON.parse(v('ef-grades')) || []; } catch (e) { grades = []; }
      payload = { name: v('ef-gname'), label: v('ef-label'), type: v('ef-type'), grades };
    } else if (edDomain === 'turfs') {
      payload = { id: v('ef-tid'), isNew: !row.id, label: v('ef-label'),
                  x: parseFloat(v('ef-x')), y: parseFloat(v('ef-y')), z: parseFloat(v('ef-z')),
                  radius: parseFloat(v('ef-rad')) || 90, owner: v('ef-owner'),
                  blip: ck('ef-blip'), enabled: ck('ef-en') };
    } else if (edDomain === 'factions') {
      payload = { faction: row.name, kind: row.kind,
                  delta: parseInt(v('ef-delta'), 10) || 0, reason: v('ef-reason') };
    } else if (edDomain === 'rentals') {
      payload = { id: v('ef-rid'), isNew: !row.id, label: v('ef-label'),
                  x: parseFloat(v('ef-x')), y: parseFloat(v('ef-y')), z: parseFloat(v('ef-z')),
                  sx: parseFloat(v('ef-sx')), sy: parseFloat(v('ef-sy')), sz: parseFloat(v('ef-sz')),
                  sh: parseFloat(v('ef-sh')) || 0, cats: v('ef-cats'), job: v('ef-job'),
                  blip: ck('ef-blip'), enabled: ck('ef-en') };
    } else if (edDomain === 'garages') {
      payload = { gid: v('ef-gid'), isNew: !row.id, label: v('ef-label'), type: v('ef-type'),
                  x: parseFloat(v('ef-x')), y: parseFloat(v('ef-y')), z: parseFloat(v('ef-z')),
                  sx: parseFloat(v('ef-sx')), sy: parseFloat(v('ef-sy')), sz: parseFloat(v('ef-sz')),
                  sh: parseFloat(v('ef-sh')) || 0, job: v('ef-job'),
                  fee: parseInt(v('ef-fee'), 10) || 0, blip: ck('ef-blip'), enabled: ck('ef-en') };
    } else if (edDomain === 'clothstores') {
      payload = { id: row.id, label: v('ef-label'), x: parseFloat(v('ef-x')), y: parseFloat(v('ef-y')),
                  z: parseFloat(v('ef-z')), h: parseFloat(v('ef-h')) || 0, ped: v('ef-ped'),
                  job: v('ef-job'), blip: ck('ef-blip'), enabled: ck('ef-en') };
    } else if (edDomain === 'clothcats') {
      payload = { key: v('ef-key'), isNew: !row.key, label: v('ef-label'), kind: v('ef-kind'),
                  slot: parseInt(v('ef-slot'), 10) || 0, item: v('ef-item'),
                  price: parseInt(v('ef-price'), 10) || 0, framing: v('ef-framing'),
                  sort: parseInt(v('ef-sort'), 10) || 0, enabled: ck('ef-en') };
    } else if (edDomain === 'recipes') {
      const inputs = [...byId('ef-ing').children].map(d => ({
        item: d.querySelector('.ing-name').value, qty: +d.querySelector('.ing-qty').value || 1,
      }));
      payload = { id: row.id, station: v('ef-station'), output: v('ef-output'),
                  count: parseInt(v('ef-count'), 10) || 1, time: parseInt(v('ef-time'), 10) || 3000,
                  inputs, enabled: ck('ef-en') };
    } else {
      const grades = [...byId('ef-grades').children].map(d => {
        const i = d.querySelectorAll('.gin');
        return { grade: +i[0].value || 0, name: i[1].value, salary: +i[2].value || 0 };
      });
      payload = { name: v('ef-name'), label: v('ef-label'), type: v('ef-type'),
                  whitelisted: ck('ef-wl'), grades };
    }
    const res = await post('worldSave', { domain: edDomain, row: payload });
    if (res && res.ok) { f.classList.add('hidden'); loadEditor(); }
    else flash(byId('ef-save'), false);
  };
}

// ── Resources ──
function renderResources(list) {
  const wrap = byId('rlist'); wrap.innerHTML = '';
  list.forEach(r => {
    const row = document.createElement('div'); row.className = 'rrow';
    const stateCls = r.state === 'started' ? 'ok' : (r.state === 'stopped' ? 'bad' : 'mid');
    row.innerHTML = `
      <span class="rname">${esc(r.name)}${r.protected ? ` <i class="rprot">${t('adm.protected')}</i>` : ''}</span>
      <span class="rstate ${stateCls}">${esc(r.state)}</span>
      <span class="racts">
        <button class="mini" data-v="restart" ${(!isSuper || r.protected) ? 'disabled' : ''}>${t('adm.res_restart')}</button>
        ${r.state === 'started'
          ? `<button class="mini danger" data-v="stop" ${(!isSuper || r.protected) ? 'disabled' : ''}>${t('adm.res_stop')}</button>`
          : `<button class="mini accent" data-v="ensure" ${!isSuper ? 'disabled' : ''}>${t('adm.res_start')}</button>`}
      </span>`;
    row.querySelectorAll('[data-v]').forEach(btn => {
      btn.onclick = async () => {
        const ok = await post('action', { type: 'resource', verb: btn.dataset.v, name: r.name });
        flash(btn, ok);
        setTimeout(loadTab, 700);
      };
    });
    wrap.appendChild(row);
  });
}

// ── Logs ──
function renderLogs(list) {
  const wrap = byId('loglist'); wrap.innerHTML = '';
  list.forEach(l => {
    const row = document.createElement('div'); row.className = 'lrow';
    row.innerHTML = `<span class="lcat">${esc(l.category)}</span>
      <span class="lmsg">${esc(l.message)}</span>
      <span class="lmeta">${esc(l.citizenid || '')} · ${esc(String(l.created_at || '').replace('T', ' ').slice(0, 19))}</span>`;
    wrap.appendChild(row);
  });
}

// ── World ──
function buildWeathers() {
  const wrap = byId('weathers'); wrap.innerHTML = '';
  weathers.forEach(w => {
    const b = document.createElement('button');
    b.className = 'wbtn'; b.textContent = w;
    b.onclick = async () => {
      const ok = await post('action', { type: 'weather', value: w });
      flash(b, ok);
      if (ok) wrap.querySelectorAll('.wbtn').forEach(x => x.classList.toggle('on', x === b));
    };
    wrap.appendChild(b);
  });
}

byId('hour').oninput = () => { byId('hourval').textContent = byId('hour').value; };
byId('applytime').onclick = async () => {
  flash(byId('applytime'), await post('action', { type: 'time', hour: parseInt(byId('hour').value, 10), freeze: byId('freezetime').checked }));
};
byId('spawncar').onclick = async () => {
  flash(byId('spawncar'), await post('action', { type: 'car', model: byId('carmodel').value.trim() }));
};
byId('sendannounce').onclick = async () => {
  const ok = await post('action', { type: 'announce', message: byId('announce').value.trim() });
  flash(byId('sendannounce'), ok);
  if (ok) byId('announce').value = '';
};

// ── Wiring ──
function flash(el, ok) {
  el.classList.remove('okflash', 'badflash');
  void el.offsetWidth;
  el.classList.add(ok ? 'okflash' : 'badflash');
}

document.querySelectorAll('[data-self]').forEach(b => b.onclick = async () => {
  flash(b, await post('self', { act: b.dataset.self }));
});
document.querySelectorAll('[data-copy]').forEach(b => b.onclick = () => {
  const el = byId(b.dataset.copy); if (!el) return;
  copyText(el.textContent.trim()); flash(b, true);
});
byId('c-refresh').onclick = () => renderCoords();
document.querySelectorAll('.sub[data-dom]').forEach(b => b.onclick = () => {
  edDomain = b.dataset.dom;
  document.querySelectorAll('.sub[data-dom]').forEach(x => x.classList.toggle('on', x === b));
  loadEditor();
});
byId('ed-new').onclick = () => openEdForm(null);
byId('ed-search').oninput = debounce(() => { edShown = ED_PAGE; renderEdList(); }, 140);
document.querySelectorAll('.rtab').forEach(b => b.onclick = () => setTab(b.dataset.tab));
byId('refresh').onclick = loadTab;
byId('psearch').oninput = renderPlayers;
byId('logfilter').onchange = loadTab;
byId('close').onclick = () => { byId('adm').classList.add('hidden'); post('close'); };
document.addEventListener('keydown', (e) => { if (e.key === 'Escape' && !byId('adm').classList.contains('hidden')) { byId('adm').classList.add('hidden'); post('close'); } });

window.addEventListener('message', (e) => {
  const d = e.data || {};
  if (d.action === 'open') {
    strings = d.strings || {}; isSuper = !!d.super; weathers = d.weathers || []; tools = d.tools || {};
    applyStrings(); buildWeathers();
    byId('adm').classList.remove('hidden');
    setTab('dash');
  } else if (d.action === 'close') {
    byId('adm').classList.add('hidden');
  }
});
