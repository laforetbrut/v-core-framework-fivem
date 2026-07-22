// v-police — three panes. Nothing is decided here: the charge sheet is server data, the
// total is only ever a preview, and the server re-derives the sentence from the codes.
(() => {
  const $ = id => document.getElementById(id);
  const root = $('pol');
  let S = {}, CHARGES = [], picked = new Set(), tab = 'street';

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

  // ── Street ─────────────────────────────────────────────────────────────────
  function renderStreet() {
    const pane = $('pane-street');
    pane.innerHTML =
      `<div class="actions">` +
        `<button class="btn" data-a="cuff">${esc(t('pol.cuff'))}</button>` +
        `<button class="btn ghost" data-a="escort">${esc(t('pol.escort'))}</button>` +
        `<button class="btn ghost" data-a="search">${esc(t('pol.search'))}</button>` +
        `<button class="btn danger" data-a="impound">${esc(t('pol.impound'))}</button>` +
      `</div>` +
      `<div class="section-ttl">${esc(t('pol.searched'))}</div>` +
      `<div id="p-searchout"><div class="empty">${esc(t('pol.no_search'))}</div></div>`;
    pane.querySelectorAll('[data-a]').forEach(b =>
      b.addEventListener('click', () => post(b.dataset.a)));
  }

  function renderSearch(d) {
    const out = $('p-searchout');
    if (!out) return;
    const items = d.items || [];
    if (!items.length) { out.innerHTML = `<div class="empty">${esc(t('pol.nothing'))}</div>`; return; }

    const frag = document.createDocumentFragment();
    const head = document.createElement('div');
    head.className = 'section-ttl';
    head.textContent = `${d.name || ''} ${d.citizenid ? '· ' + d.citizenid : ''}`;
    frag.appendChild(head);

    for (const it of items) {
      if (!it || !it.name) continue;
      const el = document.createElement('div');
      el.className = 'rowitem';
      el.innerHTML =
        `<div class="rowitem__main">` +
          `<div class="rowitem__name">${esc(it.label || it.name)}</div>` +
          `<div class="rowitem__meta">${esc(it.name)} · ×${Number(it.amount || it.count || 1)}</div>` +
        `</div>` +
        `<button class="btn danger">${esc(t('pol.seize'))}</button>`;
      el.querySelector('button').addEventListener('click', () =>
        post('seize', { item: it.name, count: it.amount || it.count || 1 }));
      frag.appendChild(el);
    }
    out.replaceChildren(frag);
  }

  // ── Charges ────────────────────────────────────────────────────────────────
  function totals() {
    let fine = 0, jail = 0;
    for (const c of CHARGES) {
      if (picked.has(c.code)) { fine += Number(c.fine) || 0; jail += Number(c.jail) || 0; }
    }
    return { fine, jail };
  }

  function paintTotal() {
    const el = $('p-total');
    if (!el) return;
    const s = totals();
    // A preview only: the server re-derives this from the codes, so a tampered total
    // changes nothing.
    el.innerHTML = `<span>${esc(t('pol.total'))}</span>` +
      `<b>${money(s.fine)} · ${s.jail} ${esc(t('pol.min'))}</b>`;
  }

  function renderBook() {
    const pane = $('pane-book');
    const byCat = {};
    for (const c of CHARGES) (byCat[c.cat || 'misc'] = byCat[c.cat || 'misc'] || []).push(c);

    let html = '';
    for (const cat of Object.keys(byCat).sort()) {
      html += `<div class="section-ttl">${esc(cat)}</div><div class="charges">`;
      for (const c of byCat[cat]) {
        html +=
          `<div class="charge${picked.has(c.code) ? ' on' : ''}" data-code="${esc(c.code)}">` +
            `<span class="charge__code">${esc(c.code)}</span>` +
            `<span class="charge__label">${esc(c.label)}</span>` +
            `<span class="charge__cost">${money(c.fine)} · ${Number(c.jail) || 0}m</span>` +
          `</div>`;
      }
      html += `</div>`;
    }
    html +=
      `<div class="section-ttl">${esc(t('pol.notes'))}</div>` +
      `<textarea id="p-notes" rows="3"></textarea>` +
      `<div class="total" id="p-total"></div>` +
      `<div class="actions" style="margin-top:.8rem">` +
        `<button class="btn" id="p-book">${esc(t('pol.book'))}</button>` +
        `<button class="btn ghost" id="p-clear">${esc(t('pol.clear'))}</button>` +
      `</div>`;
    pane.innerHTML = html;

    pane.querySelectorAll('.charge').forEach(el => el.addEventListener('click', () => {
      const code = el.dataset.code;
      if (picked.has(code)) picked.delete(code); else picked.add(code);
      el.classList.toggle('on');
      paintTotal();
    }));
    $('p-book').addEventListener('click', () => {
      if (!picked.size) return;
      post('book', { codes: Array.from(picked), notes: ($('p-notes').value || '').slice(0, 240) });
      picked.clear();
    });
    $('p-clear').addEventListener('click', () => { picked.clear(); renderBook(); });
    paintTotal();
  }

  // ── MDT ────────────────────────────────────────────────────────────────────
  function renderMdt() {
    $('pane-mdt').innerHTML =
      `<div class="search-row">` +
        `<input id="p-q" type="text" placeholder="${esc(t('pol.lookup_ph'))}" />` +
        `<button class="btn" id="p-go">${esc(t('pol.lookup'))}</button>` +
        `<button class="btn ghost" id="p-wl">${esc(t('pol.warrants'))}</button>` +
      `</div>` +
      `<div id="p-mdtout"><div class="empty">${esc(t('pol.mdt_hint'))}</div></div>`;

    const go = () => post('lookup', { query: $('p-q').value || '' });
    $('p-go').addEventListener('click', go);
    $('p-q').addEventListener('keyup', e => { if (e.key === 'Enter') go(); });
    $('p-wl').addEventListener('click', () => post('warrants'));
  }

  function renderLookup(d) {
    const out = $('p-mdtout');
    if (!out) return;
    const p = d.person || {};
    const recs = (d.records || []).map(r =>
      `<div class="rowitem"><div class="rowitem__main">` +
        `<div class="rowitem__name">${esc((r.charges || []).join(', '))}</div>` +
        `<div class="rowitem__meta">${money(r.fine)} · ${Number(r.jail) || 0}m · ${esc(String(r.at || '').slice(0, 16))}` +
          `${r.paid ? '' : ' · ' + esc(t('pol.unpaid'))}${r.notes ? ' · ' + esc(r.notes) : ''}</div>` +
      `</div></div>`).join('') || `<div class="empty">${esc(t('pol.no_record'))}</div>`;

    const warr = (d.warrants || []).map(w =>
      `<div class="rowitem"><div class="rowitem__main">` +
        `<div class="rowitem__name">${esc(w.reason)}</div>` +
        `<div class="rowitem__meta">${esc(String(w.at || '').slice(0, 16))}</div>` +
      `</div><span class="badge warn">${esc(t('pol.active'))}</span></div>`).join('')
      || `<div class="empty">${esc(t('pol.no_warrant'))}</div>`;

    const lics = (d.licenses || []).map(l =>
      `<span class="badge ${l.status === 'valid' ? 'ok' : 'warn'}">${esc(l.type)}` +
      `${Number(l.points) ? ' ' + l.points + 'p' : ''}</span>`).join(' ')
      || `<span class="badge">${esc(t('pol.none'))}</span>`;

    const vehs = (d.vehicles || []).map(v =>
      `<span class="badge">${esc(v.plate)} · ${esc(v.model)}${Number(v.state) === 2 ? ' · ' + esc(t('pol.impounded_b')) : ''}</span>`)
      .join(' ') || `<span class="badge">${esc(t('pol.none'))}</span>`;

    out.innerHTML =
      `<div class="section-ttl">${esc(p.firstname || '')} ${esc(p.lastname || '')} · ${esc(p.citizenid || '')}` +
        `${d.jail > 0 ? ' · ' + esc(t('pol.in_jail')) + ' ' + d.jail + 'm' : ''}</div>` +
      `<div style="display:flex;gap:.35rem;flex-wrap:wrap;margin-bottom:.6rem">${lics}</div>` +
      `<div style="display:flex;gap:.35rem;flex-wrap:wrap">${vehs}</div>` +
      `<div class="section-ttl">${esc(t('pol.warrants'))}</div>${warr}` +
      `<div class="search-row" style="margin-top:.6rem">` +
        `<input id="p-wr" type="text" placeholder="${esc(t('pol.warrant_ph'))}" />` +
        `<button class="btn" id="p-wadd">${esc(t('pol.warrant_add'))}</button>` +
        `<button class="btn ghost" id="p-wclr">${esc(t('pol.warrant_clear'))}</button>` +
      `</div>` +
      `<div class="section-ttl">${esc(t('pol.record'))}</div>${recs}`;

    $('p-wadd').addEventListener('click', () =>
      post('warrant', { citizenid: p.citizenid, reason: $('p-wr').value || '' }));
    $('p-wclr').addEventListener('click', () =>
      post('warrant', { citizenid: p.citizenid, clear: true }));
  }

  function renderWarrants(rows) {
    const out = $('p-mdtout');
    if (!out) return;
    out.innerHTML = `<div class="section-ttl">${esc(t('pol.warrants'))}</div>` +
      ((rows || []).map(w =>
        `<div class="rowitem"><div class="rowitem__main">` +
          `<div class="rowitem__name">${esc(w.firstname || '')} ${esc(w.lastname || '')} · ${esc(w.citizenid)}</div>` +
          `<div class="rowitem__meta">${esc(w.reason)} · ${esc(String(w.at || '').slice(0, 16))}</div>` +
        `</div></div>`).join('') || `<div class="empty">${esc(t('pol.no_warrant'))}</div>`);
  }

  function showTab(name) {
    tab = name;
    for (const n of ['street', 'book', 'mdt']) {
      $('pane-' + n).classList.toggle('hidden', n !== name);
      $('tb-' + n).classList.toggle('on', n === name);
    }
  }

  window.addEventListener('message', ev => {
    const d = ev.data || {};
    if (d.action === 'open') {
      S = d.strings || S;
      CHARGES = d.charges || [];
      picked = new Set();
      $('p-title').textContent = t('pol.title');
      $('p-sub').textContent = d.target ? t('pol.nearest') + ' #' + d.target : t('pol.nobody_near');
      $('tb-street').textContent = t('pol.street');
      $('tb-book').textContent = t('pol.charges');
      $('tb-mdt').textContent = t('pol.mdt');
      renderStreet(); renderBook(); renderMdt();
      showTab('street');
      root.classList.remove('hidden');
    } else if (d.action === 'search') {
      renderSearch(d.data || {});
    } else if (d.action === 'lookup') {
      renderLookup(d.data || {});
    } else if (d.action === 'warrants') {
      renderWarrants(d.rows);
    } else if (d.action === 'close') {
      root.classList.add('hidden');
    }
  });

  for (const n of ['street', 'book', 'mdt']) {
    $('tb-' + n).addEventListener('click', () => showTab(n));
  }
  $('p-close').addEventListener('click', close);
  document.addEventListener('keyup', e => {
    if (e.key === 'Escape' && !root.classList.contains('hidden')) close();
  });
})();
