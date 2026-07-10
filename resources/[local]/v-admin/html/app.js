// v-admin — panel logic
const byId = (id) => document.getElementById(id);
const post = (n, b) => fetch(`https://v-admin/${n}`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(b || {}) }).then(r => r.json()).catch(() => false);
const fmt = (n) => '$' + Math.floor(Number(n) || 0).toLocaleString('en-US');
const esc = (s) => String(s ?? '').replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));

let strings = {}, isSuper = false, weathers = [], curTab = 'dash';
let players = [], frozen = new Set();
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

document.querySelectorAll('.rtab').forEach(b => b.onclick = () => setTab(b.dataset.tab));
byId('refresh').onclick = loadTab;
byId('psearch').oninput = renderPlayers;
byId('logfilter').onchange = loadTab;
byId('close').onclick = () => { byId('adm').classList.add('hidden'); post('close'); };
document.addEventListener('keydown', (e) => { if (e.key === 'Escape' && !byId('adm').classList.contains('hidden')) { byId('adm').classList.add('hidden'); post('close'); } });

window.addEventListener('message', (e) => {
  const d = e.data || {};
  if (d.action === 'open') {
    strings = d.strings || {}; isSuper = !!d.super; weathers = d.weathers || [];
    applyStrings(); buildWeathers();
    byId('adm').classList.remove('hidden');
    setTab('dash');
  } else if (d.action === 'close') {
    byId('adm').classList.add('hidden');
  }
});
