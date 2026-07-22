// v-rentals — hire counter. Server-authoritative: the card only carries a model name,
// and the server re-derives the price, the licence gate and the proximity.
(() => {
  const $ = id => document.getElementById(id);
  const root = $('rent');
  let S = {};

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

  function render(d) {
    $('r-title').textContent = t('rent.title');
    $('r-sub').textContent = d.point ? d.point.label : t('rent.sub');
    $('r-dur').textContent = t('rent.duration') + ': ' + d.minutes + ' ' + t('rent.minutes');

    // An active hire blocks a second one — say so, instead of leaving the player to
    // click a button that can only ever fail.
    const banner = $('r-active');
    banner.classList.toggle('hidden', !d.active);
    if (d.active) banner.textContent = t('rent.active') + ' — ' + d.active.plate;

    const cars = d.cars || [];
    const empty = $('r-empty');
    empty.textContent = t('rent.none');
    empty.classList.toggle('hidden', cars.length > 0);

    const frag = document.createDocumentFragment();
    for (const c of cars) {
      const total = (c.deposit || 0) + (c.fee || 0);
      const afford = (d.bank || 0) >= total && !d.active;
      const el = document.createElement('div');
      el.className = 'card';
      el.innerHTML =
        '<div class="card__name">' + esc(c.label) + '</div>' +
        '<div class="card__cat">' + esc(c.cat) + '</div>' +
        '<div class="card__rows">' +
          '<div class="row"><span>' + esc(t('rent.deposit')) + '</span><b>' + money(c.deposit) + '</b></div>' +
          '<div class="row"><span>' + esc(t('rent.fee')) + '</span><b>' + money(c.fee) + '</b></div>' +
          '<div class="row total"><span>' + esc(t('rent.total')) + '</span><b>' + money(total) + '</b></div>' +
        '</div>' +
        '<button class="btn"' + (afford ? '' : ' disabled') + '>' + esc(t('rent.hire')) + '</button>';
      el.querySelector('.btn').addEventListener('click', () => {
        root.classList.add('hidden');
        post('hire', { model: c.model });
      });
      frag.appendChild(el);
    }
    $('r-grid').replaceChildren(frag);
  }

  window.addEventListener('message', ev => {
    const d = ev.data || {};
    if (d.action === 'open') {
      S = d.strings || {};
      render(d.data || {});
      root.classList.remove('hidden');
    } else if (d.action === 'close') {
      root.classList.add('hidden');
    }
  });

  $('r-close').addEventListener('click', close);
  document.addEventListener('keyup', e => {
    if (e.key === 'Escape' && !root.classList.contains('hidden')) close();
  });
})();
