// v-loadscreen — Projet R
const tips = [
  { fr: 'Utilise ton téléphone (iFruit) pour gérer ta banque.', en: 'Use your phone (iFruit) to manage your bank.' },
  { fr: 'Mange et bois pour rester en forme.', en: 'Eat and drink to stay healthy.' },
  { fr: 'Ouvre les réglages du HUD avec la touche F7.', en: 'Open your HUD settings with F7.' },
  { fr: "Reste dans ton personnage : c'est du roleplay.", en: 'Stay in character — this is roleplay.' },
  { fr: 'Un distributeur (ATM) permet de retirer du liquide.', en: 'Use an ATM to withdraw cash.' },
  { fr: 'Un menu radial remplace les commandes tapées.', en: 'A radial menu replaces typed commands.' },
];

const tipEl = document.getElementById('tip');
let ti = 0;
function showTip() {
  const tip = tips[Math.floor(ti / 2) % tips.length];
  const text = (ti % 2 === 0) ? tip.fr : tip.en;
  tipEl.classList.add('fade');
  setTimeout(() => { tipEl.textContent = text; tipEl.classList.remove('fade'); }, 400);
  ti++;
}
showTip();
setInterval(showTip, 5000);

// ── Progress ──
const fill = document.getElementById('fill');
const pctEl = document.getElementById('pct');
const statusEl = document.getElementById('status');
let shown = 0;

function setProgress(frac) {
  const p = Math.max(shown, Math.min(100, Math.round((frac || 0) * 100)));
  shown = p;
  fill.style.width = p + '%';
  pctEl.innerHTML = '<b>' + p + '</b>%';
}
function setStatus(text) { statusEl.textContent = text; }

window.addEventListener('message', (e) => {
  const d = e.data || {};
  switch (d.eventName) {
    case 'loadProgress': setProgress(d.loadFraction); break;
    case 'startInitFunctionOrder': setStatus('Initialisation…'); break;
    case 'startDataFileEntries': setStatus('Chargement des données…'); break;
    case 'performMapLoadFunction': setStatus('Chargement de la carte…'); break;
    case 'startInitFunction': setStatus('Démarrage…'); break;
    case 'initFunctionInvoking':
      if (typeof d.idx === 'number' && d.count) setProgress(0.1 + 0.8 * (d.idx / d.count));
      break;
  }
});

// Gentle idle creep so the bar never looks frozen if events are sparse.
setInterval(() => { if (shown < 92) setProgress((shown + 1) / 100); }, 900);
