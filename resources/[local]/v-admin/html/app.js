// v-admin — panel logic
const byId = (id) => document.getElementById(id);
const post = (n, b) => fetch(`https://v-admin/${n}`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(b || {}) }).then(r => r.json()).catch(() => false);
const fmt = (n) => '$' + Math.floor(Number(n) || 0).toLocaleString('en-US');
const esc = (s) => String(s ?? '').replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));

let strings = {}, isSuper = false, weathers = [], curTab = 'dash';
let players = [], frozen = new Set(), tools = {};
const t = (k) => strings[k] || k;

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

function renderEdList() {
  const wrap = byId('ed-list'); wrap.innerHTML = '';
  const rows = edFilter(edData.rows || []);
  if (!rows.length) { wrap.innerHTML = `<div class="empty-ed">${esc(t('adm.ed_empty'))}</div>`; return; }
  rows.slice(0, 300).forEach((r, i) => {
    const el = document.createElement('div'); el.className = 'edrow'; el.style.setProperty('--i', i);
    const off = (r.enabled === 0 || r.enabled === false);
    el.innerHTML = `<span class="edname${off ? ' off' : ''}">${edRowTitle(r)}</span>
      <span class="edacts">
        <button class="mini" data-act="edit">${esc(t('adm.ed_edit'))}</button>
        <button class="mini danger" data-act="del">${esc(t('adm.ed_del'))}</button>
      </span>`;
    el.querySelector('[data-act="edit"]').onclick = () => openEdForm(r);
    el.querySelector('[data-act="del"]').onclick = async () => {
      const id = (edDomain === 'jobs' || edDomain === 'items') ? r.name : r.id;
      const ok = await post('worldDelete', { domain: edDomain, id });
      if (ok && ok.ok) loadEditor();
    };
    wrap.appendChild(el);
  });
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
      ${(edDomain === 'blips' || edDomain === 'shops') ? `<button class="mini" id="ef-here">${esc(t('adm.ed_here'))}</button>` : ''}
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
byId('ed-search').oninput = () => renderEdList();
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
