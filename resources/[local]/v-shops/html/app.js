// v-shops — store UI
const byId = (id) => document.getElementById(id);
const post = (n, b) => fetch(`https://v-shops/${n}`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(b || {}) }).then(r => r.json()).catch(() => false);
// Muted/earthy category rings — orange stays the only saturated hue on screen.
const CAT = { food: '#4E8C5A', drinks: '#2F6F9E', medical: '#C2362F', weapon: '#6B6156', tool: '#C98A2B',
  gadget: '#2F6F9E', tech: '#2F6F9E', smokes: '#6B6156', money: '#5FA36A', misc: '#FF6A1A' };
const fmt = (n) => '$' + Math.floor(Number(n) || 0).toLocaleString('en-US');

let strings = {}, shop = null, account = 'cash';
const t = (k) => strings[k] || k;
const applyStrings = () => document.querySelectorAll('[data-i18n]').forEach(el => { el.textContent = t(el.getAttribute('data-i18n')); });

function setAccount(acc) {
  account = acc;
  byId('pay-cash').classList.toggle('sel', acc === 'cash');
  byId('pay-bank').classList.toggle('sel', acc === 'bank');
}
function setBalances(cash, bank) { byId('w-cash').textContent = fmt(cash); byId('w-bank').textContent = fmt(bank); }
function close() { byId('shop').classList.add('hidden'); post('close'); }

byId('pay-cash').onclick = () => setAccount('cash');
byId('pay-bank').onclick = () => setAccount('bank');
byId('close').onclick = close;
document.addEventListener('keydown', (e) => { if (e.key === 'Escape' && !byId('shop').classList.contains('hidden')) close(); });

function render() {
  byId('shop-label').textContent = shop.label;
  setBalances(shop.cash, shop.bank);
  const list = byId('list'); list.innerHTML = '';
  shop.items.forEach((it, i) => {
    const cat = CAT[it.category] || CAT.misc;
    const row = document.createElement('div');
    row.className = 'row';
    row.style.setProperty('--cat', cat);
    row.style.setProperty('--i', i);
    row.innerHTML =
      `<div class="info"><div class="name">${it.label}</div><div class="price"><b>${fmt(it.price)}</b> ${t('shop.each')}</div></div>` +
      `<div class="stepper"><button class="step dec" aria-label="Decrease quantity">−</button><span class="qty">1</span><button class="step inc" aria-label="Increase quantity">+</button></div>` +
      `<button class="buy" data-i18n="shop.buy">Buy</button>`;
    const qty = row.querySelector('.qty');
    row.querySelector('.dec').onclick = () => { qty.textContent = Math.max(1, (+qty.textContent) - 1); };
    row.querySelector('.inc').onclick = () => { qty.textContent = Math.min(99, (+qty.textContent) + 1); };
    row.querySelector('.buy').onclick = async () => {
      const res = await post('buy', { shopId: shop.id, item: it.name, amount: +qty.textContent, account });
      if (res && res.cash !== undefined) { shop.cash = res.cash; shop.bank = res.bank; setBalances(res.cash, res.bank); }
    };
    list.appendChild(row);
  });
  applyStrings();
}

window.addEventListener('message', (e) => {
  const d = e.data || {};
  if (d.action === 'open') {
    strings = d.strings || {}; shop = d.shop; setAccount('cash');
    render();
    byId('shop').classList.remove('hidden');
  } else if (d.action === 'close') {
    byId('shop').classList.add('hidden');
  }
});
