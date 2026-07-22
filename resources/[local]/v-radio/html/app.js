// v-radio - the handheld. Every action posts and the whole state is re-read from the
// answer, so the device can never show a channel v-voice has already taken away.
(() => {
  const $ = id => document.getElementById(id);
  const root = $('radio');
  let S = {}, D = {}, P = {};

  const t = k => S[k] || k;
  const ENT = { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' };
  const esc = s => String(s === null || s === undefined ? '' : s).replace(/[&<>"']/g, c => ENT[c]);

  function post(name, body) {
    const res = location.hostname.replace(/^cfx-nui-/, '');
    return fetch('https://' + res + '/' + name, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json; charset=UTF-8' },
      body: JSON.stringify(body || {}),
    }).catch(() => {});
  }

  function close() { root.classList.add('hidden'); post('close'); }

  const listening = id => (D.listening || []).indexOf(id) !== -1;
  const labelOf = id => {
    const c = (D.channels || []).find(x => x.id === id);
    return c ? c.label : String(id);
  };

  // ── Presets ────────────────────────────────────────────────────────────────
  function renderPresets() {
    const slots = Number(D.presetSlots) || 6;
    const frag = document.createDocumentFragment();
    for (let i = 1; i <= slots; i++) {
      const ch = P[String(i)];
      const el = document.createElement('div');
      el.className = 'preset' + (ch ? (listening(ch) ? ' on' : '') : ' empty');
      el.innerHTML =
        `<div class="preset__slot">${i}</div>` +
        `<div class="preset__ch">${ch ? esc(ch) : esc(t('radio.empty'))}</div>`;
      // Click tunes it in; right-click stores whatever you are transmitting on, which is
      // the only sane thing to save without a second dialog.
      el.addEventListener('click', () => { if (ch) post('usePreset', { slot: i }); });
      el.addEventListener('contextmenu', ev => {
        ev.preventDefault();
        post('savePreset', { slot: i, channel: ch ? 0 : (D.transmit || 0) });
      });
      frag.appendChild(el);
    }
    $('r-presets').replaceChildren(frag);
  }

  // ── Channels ───────────────────────────────────────────────────────────────
  function renderList() {
    const list = D.channels || [];
    const box = $('r-list');
    if (!list.length) {
      box.innerHTML = `<div class="empty-note">${esc(t('radio.none'))}</div>`;
      return;
    }

    const frag = document.createDocumentFragment();
    for (const c of list) {
      const on = listening(c.id);
      const tx = D.transmit === c.id;
      const el = document.createElement('div');
      el.className = 'chan' + (on ? ' listening' : '') + (tx ? ' transmit' : '');

      // Hiding the padlock is a real choice: a player then has to know a channel
      // exists to go looking for it.
      const gate = (D.showGate === false) ? '' : (c.job || c.gang || '');
      el.innerHTML =
        `<span class="chan__num">${esc(c.id)}</span>` +
        `<div class="chan__main">` +
          `<div class="chan__label">${esc(c.label)}</div>` +
          `<div class="chan__meta">${gate ? '🔒 ' + esc(gate) : ''}` +
            `${on ? (gate ? ' · ' : '') + esc(t('radio.listening')) : ''}` +
            `${tx ? ' · ' + esc(t('radio.talking')) : ''}</div>` +
        `</div>` +
        `<span class="chan__acts">` +
          `<button class="mini${on ? ' on' : ''}" data-a="toggle">${esc(on ? t('radio.leave') : t('radio.listening'))}</button>` +
          // Only a channel you already monitor can become the transmit target, which is
          // exactly what the server enforces.
          (on && !tx ? `<button class="mini" data-a="tx">${esc(t('radio.talkon'))}</button>` : '') +
        `</span>`;

      el.querySelector('[data-a="toggle"]').addEventListener('click', () =>
        post('toggle', { channel: c.id }));
      const txBtn = el.querySelector('[data-a="tx"]');
      if (txBtn) txBtn.addEventListener('click', () => post('transmit', { channel: c.id }));
      frag.appendChild(el);
    }
    box.replaceChildren(frag);
  }

  function render() {
    $('r-title').textContent = t('radio.title');
    $('r-lbl-presets').textContent = t('radio.presets');
    $('r-lbl-avail').textContent = t('radio.available');
    $('r-off').textContent = t('radio.leaveall');

    const n = (D.listening || []).length;
    $('r-sub').textContent = n
      ? `${t('radio.sub')}: ${(D.listening || []).map(labelOf).join(', ')}`
      : t('radio.sub') + ': -';

    renderPresets();
    renderList();
  }

  window.addEventListener('message', ev => {
    const d = ev.data || {};
    if (d.action === 'open' || d.action === 'data') {
      S = d.strings || S;
      D = d.data || D;
      P = d.presets || {};
      render();
      if (d.action === 'open') root.classList.remove('hidden');
    } else if (d.action === 'close') {
      root.classList.add('hidden');
    }
  });

  $('r-close').addEventListener('click', close);
  $('r-off').addEventListener('click', () => post('leaveAll'));
  document.addEventListener('keyup', e => {
    if (e.key === 'Escape' && !root.classList.contains('hidden')) close();
  });
})();
