// v-banking — Fleeca UI
const byId = (id) => document.getElementById(id);
const fmt = (n) => '$' + Math.floor(Number(n) || 0).toLocaleString('en-US');
let strings = {};
let currentTab = 'deposit';

const t = (k) => strings[k] || k;
const applyStrings = () => document.querySelectorAll('[data-i18n]').forEach(el => { el.textContent = t(el.getAttribute('data-i18n')); });

function post(name, body) {
  return fetch(`https://v-banking/${name}`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body || {}) })
    .then(r => r.json()).catch(() => false);
}

function showMsg(text, kind) {
  const m = byId('msg');
  m.textContent = text || '';
  m.className = 'msg' + (kind ? ' ' + kind : '');
}

function render(data) {
  byId('bank-amt').textContent = fmt(data.bank);
  byId('cash-amt').textContent = fmt(data.cash);
  const list = byId('tx-list');
  list.innerHTML = '';
  const txs = data.transactions || [];
  if (!txs.length) { list.innerHTML = `<div class="tx-empty">${t('bank.empty')}</div>`; return; }
  txs.forEach((tx, i) => {
    const positive = tx.type === 'deposit' || tx.type === 'transfer_in';
    const row = document.createElement('div');
    row.className = 'tx';
    row.style.setProperty('--i', i);
    const date = (tx.created_at || '').toString().replace('T', ' ').slice(0, 16);
    row.innerHTML =
      `<div class="l"><span class="k">${t('tx.' + tx.type)}</span><span class="d">${date}${tx.label ? ' · ' + escapeHtml(tx.label) : ''}</span></div>` +
      `<span class="a ${positive ? 'plus' : 'minus'}">${positive ? '+' : '−'}${fmt(tx.amount)}</span>`;
    list.appendChild(row);
  });
}

function escapeHtml(s) { const d = document.createElement('div'); d.textContent = String(s); return d.innerHTML; }

let cardData = null;

function renderCard() {
  const v = byId('cardview');
  if (cardData && cardData.card) {
    v.className = 'cardview';
    v.innerHTML =
      '<div class="brand"><span>FLEECA</span><span class="chip"></span></div>' +
      '<div class="num">' + escapeHtml(cardData.card) + '</div>' +
      '<div class="foot"><span>' + escapeHtml(cardData.holder || '') + '</span>' +
      '<span>' + fmt(cardData.bank) + '</span></div>';
    byId('ordercard').classList.add('hidden');
    byId('cardmsg').textContent = t('bank.card_have');
  } else {
    v.className = 'cardview none';
    v.textContent = t('bank.card_none');
    byId('ordercard').classList.remove('hidden');
    byId('ordercard').textContent = t('bank.order_card') +
      (cardData && cardData.fee ? '  ' + fmt(cardData.fee) : '');
    byId('cardmsg').textContent = '';
  }
}

byId('ordercard').onclick = async () => {
  const res = await post('requestCard', {});
  if (res && res.ok) {
    cardData = Object.assign(cardData || {}, { card: res.card, bank: res.bank });
    renderCard();
    showMsg(t('bank.card_ordered'), 'ok');
  } else {
    showMsg(t('bank.err_' + ((res && res.error) || 'x')), 'err');
  }
};


  currentTab = tab;
  document.querySelectorAll('.tab').forEach(b => b.classList.toggle('on', b.getAttribute('data-tab') === tab));
  const isCard = tab === 'card';
  document.querySelector('.form').classList.toggle('hidden', isCard);
  byId('cardpane').classList.toggle('hidden', !isCard);
  if (isCard) post('card', {}).then((d) => { cardData = d; renderCard(); });
  byId('target-field').classList.toggle('hidden', tab !== 'transfer');
  showMsg('');
}

function close() { byId('bank').classList.add('hidden'); post('close'); }

document.querySelectorAll('.tab').forEach(b => b.onclick = () => setTab(b.getAttribute('data-tab')));
byId('close').onclick = close;
byId('bank').addEventListener('mousedown', (e) => { if (e.target.id === 'bank') close(); });
document.addEventListener('keydown', (e) => { if (e.key === 'Escape' && !byId('bank').classList.contains('hidden')) close(); });

byId('confirm').onclick = async () => {
  const amount = parseInt(byId('amount').value, 10);
  if (!amount || amount <= 0) { showMsg(t('bank.amount'), 'err'); return; }
  let res;
  if (currentTab === 'transfer') res = await post('transfer', { amount, target: byId('target').value.trim() });
  else res = await post(currentTab, { amount });

  if (!res) { showMsg(t('bank.err_funds'), 'err'); return; }
  if (res.error) {
    // Map every server error code to its own string. Falling back to "insufficient
    // funds" for a limit rejection told the player the exact opposite of the truth.
    const key = 'bank.err_' + res.error;
    let msg = t(key);
    if (msg === key) msg = t('bank.err_funds');
    if (res.limit != null) msg = msg.replace('%s', Number(res.limit).toLocaleString());
    showMsg(msg, 'err');
    return;
  }
  render(res);
  byId('amount').value = '';
  showMsg((t('bank.ok_' + currentTab) || '').replace('%s', fmt(amount).slice(1)), 'ok');
};

window.addEventListener('message', (e) => {
  const d = e.data || {};
  if (d.action === 'open') {
    strings = d.strings || {};
    applyStrings();
    setTab('deposit');
    render(d.data || { bank: 0, cash: 0, transactions: [] });
    byId('bank').classList.remove('hidden');
    byId('amount').value = '';
    showMsg('');
  } else if (d.action === 'close') {
    byId('bank').classList.add('hidden');
  }
});
