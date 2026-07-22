// v-bossmenu — three panes over one server payload. Nothing is decided here: every
// action posts and the whole state is re-read from the answer, so the panel can never
// drift from what the server actually did.
(() => {
  const $ = id => document.getElementById(id);
  const root = $('boss');
  let S = {}, D = {}, tab = 'members';

  const t = k => S[k] || k;
  const ENT = { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' };
  const esc = s => String(s === null || s === undefined ? '' : s).replace(/[&<>"']/g, c => ENT[c]);
  const money = n => '$' + Number(n || 0).toLocaleString();

  function post(name, body) {
    const res = location.hostname.replace(/^cfx-nui-/, '');
    return fetch('https://' + res + '/' + name, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json; charset=UTF-8' },
      body: JSON.stringify(body || {}),
    }).catch(() => {});
  }

  function close() { root.classList.add('hidden'); post('close'); }

  function gradeOptions(selected) {
    return (D.grades || [])
      // A boss cannot promote above their own rank — the server enforces it, and
      // offering the option anyway would just be a button that always fails.
      .filter(g => g.grade <= (D.myGrade || 0))
      .map(g => `<option value="${g.grade}"${g.grade === selected ? ' selected' : ''}>` +
                `${esc(g.name)}</option>`).join('');
  }

  // ── Members ────────────────────────────────────────────────────────────────
  function renderMembers() {
    const pane = $('pane-members');
    const list = D.members || [];
    if (!list.length) { pane.innerHTML = `<div class="empty">${esc(t('boss.no_members'))}</div>`; return; }

    const frag = document.createDocumentFragment();
    for (const m of list) {
      const el = document.createElement('div');
      el.className = 'rowitem';
      const dot = m.duty ? 'dot duty' : (m.online ? 'dot on' : 'dot');
      const state = m.duty ? t('boss.on_duty') : (m.online ? t('boss.online') : t('boss.offline'));
      el.innerHTML =
        `<span class="${dot}" title="${esc(state)}"></span>` +
        `<div class="rowitem__main">` +
          `<div class="rowitem__name">${esc(m.firstname || '')} ${esc(m.lastname || '')}` +
            `${m.isboss ? ' · ' + esc(t('boss.is_boss')) : ''}</div>` +
          `<div class="rowitem__meta">${esc(m.citizenid)} · ${esc(m.gradeLabel)} · ${esc(state)}</div>` +
        `</div>` +
        (D.can && D.can.promote ? `<select data-act="grade">${gradeOptions(m.grade)}</select>` : '') +
        (D.can && D.can.fire ? `<button class="btn danger" data-act="fire">${esc(t('boss.fire'))}</button>` : '');

      const sel = el.querySelector('[data-act="grade"]');
      if (sel) sel.addEventListener('change', () => post('setGrade', { cid: m.citizenid, grade: Number(sel.value) }));
      const fire = el.querySelector('[data-act="fire"]');
      if (fire) fire.addEventListener('click', () => post('fire', { cid: m.citizenid }));
      frag.appendChild(el);
    }
    pane.replaceChildren(frag);
  }

  // ── Hire ───────────────────────────────────────────────────────────────────
  function renderHire() {
    const pane = $('pane-hire');
    if (!(D.can && D.can.hire)) { pane.innerHTML = `<div class="empty">${esc(t('boss.err_off'))}</div>`; return; }

    const list = (D.nearby || []).filter(n => !n.already);
    if (!list.length) { pane.innerHTML = `<div class="empty">${esc(t('boss.nobody_near'))}</div>`; return; }

    const frag = document.createDocumentFragment();
    const head = document.createElement('div');
    head.className = 'section-ttl';
    head.textContent = t('boss.nearby');
    frag.appendChild(head);

    for (const n of list) {
      const el = document.createElement('div');
      el.className = 'rowitem';
      el.innerHTML =
        `<div class="rowitem__main">` +
          `<div class="rowitem__name">${esc(n.name)}</div>` +
          `<div class="rowitem__meta">${esc(n.citizenid)}</div>` +
        `</div>` +
        `<select data-act="grade">${gradeOptions(0)}</select>` +
        `<button class="btn" data-act="hire">${esc(t('boss.hire'))}</button>`;
      const sel = el.querySelector('[data-act="grade"]');
      el.querySelector('[data-act="hire"]').addEventListener('click', () =>
        post('hire', { cid: n.citizenid, grade: Number(sel.value) }));
      frag.appendChild(el);
    }
    pane.replaceChildren(frag);
  }

  // ── Treasury ───────────────────────────────────────────────────────────────
  function renderTreasury() {
    const pane = $('pane-treasury');
    if (!(D.can && D.can.treasury)) { pane.innerHTML = `<div class="empty">${esc(t('boss.err_off'))}</div>`; return; }

    const hist = (D.history || []).map(h => {
      const pos = Number(h.amount) > 0;
      return `<div class="hist__row">` +
        `<span>${esc(h.reason || '')}${h.by_cid ? ' · ' + esc(h.by_cid) : ''}</span>` +
        `<span class="hist__amt ${pos ? 'pos' : 'neg'}">${pos ? '+' : ''}${money(h.amount)}</span>` +
      `</div>`;
    }).join('') || `<div class="empty">${esc(t('boss.no_history'))}</div>`;

    pane.innerHTML =
      `<div class="money-row">` +
        `<input id="b-amount" type="number" min="1" step="1" placeholder="${esc(t('boss.amount'))}" />` +
        `<button class="btn" id="b-dep">${esc(t('boss.deposit'))}</button>` +
        `<button class="btn ghost" id="b-wd">${esc(t('boss.withdraw'))}</button>` +
        (D.can.salaries ? `<button class="btn ghost" id="b-pay">${esc(t('boss.pay'))}</button>` : '') +
      `</div>` +
      `<div class="section-ttl">${esc(t('boss.history'))}</div>` +
      `<div class="hist">${hist}</div>`;

    const amount = () => parseInt($('b-amount').value, 10) || 0;
    $('b-dep').addEventListener('click', () => post('deposit', { amount: amount() }));
    $('b-wd').addEventListener('click', () => post('withdraw', { amount: amount() }));
    const pay = $('b-pay');
    if (pay) pay.addEventListener('click', () => post('paySalaries'));
  }

  function showTab(name) {
    tab = name;
    for (const n of ['members', 'hire', 'treasury']) {
      $('pane-' + n).classList.toggle('hidden', n !== name);
      $('tb-' + n).classList.toggle('on', n === name);
    }
  }

  function render(d) {
    D = d || {};
    $('b-title').textContent = t('boss.title');
    $('b-sub').textContent = (D.faction && D.faction.label) || '';
    $('b-balance').textContent = `${t('boss.balance')}: ${money(D.balance)}`;
    $('tb-members').textContent = t('boss.members');
    $('tb-hire').textContent = t('boss.hire');
    $('tb-treasury').textContent = t('boss.treasury');
    renderMembers(); renderHire(); renderTreasury();
    showTab(tab);
  }

  window.addEventListener('message', ev => {
    const d = ev.data || {};
    if (d.action === 'open') {
      S = d.strings || S;
      tab = 'members';
      render(d.data);
      root.classList.remove('hidden');
    } else if (d.action === 'data') {
      S = d.strings || S;
      render(d.data);
    } else if (d.action === 'close') {
      root.classList.add('hidden');
    }
  });

  for (const n of ['members', 'hire', 'treasury']) {
    $('tb-' + n).addEventListener('click', () => showTab(n));
  }
  $('b-close').addEventListener('click', close);
  document.addEventListener('keyup', e => {
    if (e.key === 'Escape' && !root.classList.contains('hidden')) close();
  });
})();
