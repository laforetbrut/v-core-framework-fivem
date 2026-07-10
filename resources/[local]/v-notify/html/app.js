// v-notify — toast renderer
const ICONS = {
  success: '<path d="M20 6 9 17l-5-5"/>',
  error:   '<circle cx="12" cy="12" r="9"/><path d="M15 9l-6 6M9 9l6 6"/>',
  warning: '<path d="M10.3 3.9 1.8 18a2 2 0 0 0 1.7 3h17a2 2 0 0 0 1.7-3L13.7 3.9a2 2 0 0 0-3.4 0Z"/><path d="M12 9v4M12 17h.01"/>',
  info:    '<circle cx="12" cy="12" r="9"/><path d="M12 11v5M12 8h.01"/>',
};
const container = document.getElementById('toasts');

const esc = (s) => { const d = document.createElement('div'); d.textContent = String(s == null ? '' : s); return d.innerHTML; };

function addToast(data) {
  const type = ['success', 'error', 'warning', 'info'].includes(data.type) ? data.type : 'info';
  const duration = Math.max(1200, Number(data.duration) || 4000);
  const el = document.createElement('div');
  el.className = 'toast ' + type;
  el.innerHTML =
    `<div class="icon"><svg aria-hidden="true" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">${ICONS[type]}</svg></div>` +
    `<div class="body">${data.title ? `<div class="title">${esc(data.title)}</div>` : ''}<div class="msg">${esc(data.message)}</div></div>` +
    `<div class="bar" style="animation-duration:${duration}ms"></div>` +
    `<i class="v-brk v-brk--tr" aria-hidden="true"></i><i class="v-brk v-brk--bl" aria-hidden="true"></i>`;
  container.appendChild(el);

  // Collapse exactly this row's height + the 10px stack gap so the stack never nudges on exit.
  const remove = () => {
    el.style.setProperty('--collapse', -(el.offsetHeight + 10) + 'px');
    el.classList.add('out');
    setTimeout(() => el.remove(), 300);
  };
  const timer = setTimeout(remove, duration);
  el.addEventListener('click', () => { clearTimeout(timer); remove(); });
}

window.addEventListener('message', (e) => {
  const d = e.data || {};
  if (d.action === 'notify') addToast(d);
});
