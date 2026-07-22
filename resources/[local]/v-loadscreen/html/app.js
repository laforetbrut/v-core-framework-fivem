// v-loadscreen — driven entirely by config.js.
//
// Nothing here is hardcoded: the layout class, the palette, the background, the copy and
// the tips all come from window.LOADSCREEN_CONFIG. Editing that file is how a server owner
// restyles this screen — no markup or CSS change required.
//
// A loading screen runs before any resource has started, so it cannot read a Lua config or
// ask v-core for settings. config.js IS its configuration file.
(function () {
  var C = window.LOADSCREEN_CONFIG || {};
  var T = (C.text && (C.text[C.lang] || C.text.fr || C.text.en)) || {};
  var TH = C.theme || {};
  var FX = C.effects || {};
  var BG = C.background || {};

  // ── Palette ────────────────────────────────────────────────
  // An explicit accent/bg/text beats the preset; anything unset falls back to `ember`.
  function palette() {
    var presets = TH.presets || {};
    var p = presets[TH.preset] || presets.ember || {};
    return {
      accent: TH.accent || p.accent || '#ff7a1a',
      accent2: p.accent2 || '#f04e00',
      bg: TH.bg || p.bg || '#0b0a08',
      panel: p.panel || '#16130f',
      text: TH.text || p.text || '#f4efe8'
    };
  }

  function hexToRgb(hex) {
    hex = String(hex || '').replace('#', '');
    if (hex.length !== 6) return [255, 122, 26];
    return [parseInt(hex.slice(0, 2), 16), parseInt(hex.slice(2, 4), 16), parseInt(hex.slice(4, 6), 16)];
  }
  function rgba(hex, a) { var c = hexToRgb(hex); return 'rgba(' + c[0] + ',' + c[1] + ',' + c[2] + ',' + a + ')'; }
  // mix toward white (t>0) or black (t<0) — one accent yields the whole family
  function shade(hex, t) {
    var c = hexToRgb(hex), target = t >= 0 ? 255 : 0, k = Math.abs(t);
    return '#' + c.map(function (v) {
      var n = Math.round(v + (target - v) * k).toString(16);
      return n.length < 2 ? '0' + n : n;
    }).join('');
  }

  function applyTheme() {
    var p = palette();
    var r = TH.radius === undefined ? 1 : TH.radius;
    var a = TH.panelAlpha === undefined ? 0.94 : TH.panelAlpha;
    var m = FX.motion === undefined ? 1 : FX.motion;
    var s = document.documentElement.style;

    s.setProperty('--v-accent', p.accent);
    s.setProperty('--v-accent-300', shade(p.accent, 0.28));
    s.setProperty('--v-accent-600', p.accent2);
    s.setProperty('--v-accent-700', shade(p.accent2, -0.25));
    s.setProperty('--v-accent-soft', rgba(p.accent, 0.12));
    s.setProperty('--v-accent-line', rgba(p.accent, 0.42));
    s.setProperty('--v-accent-glow', rgba(p.accent, 0.5));
    s.setProperty('--v-grad-accent', 'linear-gradient(135deg,' + p.accent + ' 0%,' + p.accent2 + ' 100%)');

    s.setProperty('--v-bg-900', p.bg);
    s.setProperty('--v-bg-800', shade(p.bg, 0.03));
    s.setProperty('--v-bg-700', shade(p.bg, 0.06));
    s.setProperty('--v-bg-sunk', shade(p.bg, -0.35));
    s.setProperty('--v-panel', rgba(p.panel, a));
    s.setProperty('--v-panel-2', rgba(shade(p.panel, 0.05), a));
    s.setProperty('--v-panel-3', rgba(shade(p.panel, 0.10), a));
    s.setProperty('--v-text', p.text);
    s.setProperty('--v-text-dim', rgba(p.text, 0.72));
    s.setProperty('--v-text-faint', rgba(p.text, 0.46));

    s.setProperty('--v-r-sm', (8 * r) + 'px');
    s.setProperty('--v-r-md', (12 * r) + 'px');
    s.setProperty('--v-r-lg', (16 * r) + 'px');
    s.setProperty('--v-r-xl', (22 * r) + 'px');

    // motion 0 disables every transition and animation outright
    var scale = m <= 0 ? 0 : 1 / m;
    s.setProperty('--v-t-fast', (120 * scale) + 'ms');
    s.setProperty('--v-t-base', (200 * scale) + 'ms');
    s.setProperty('--v-t-slow', (360 * scale) + 'ms');
    document.body.classList.toggle('no-motion', m <= 0);

    s.setProperty('--bg-dim', BG.dim === undefined ? 0.55 : BG.dim);
  }

  // ── Layout + effects ───────────────────────────────────────
  function applyLayout() {
    document.body.className = 'lay-' + (C.layout || 'centre');
    document.body.classList.toggle('fx-grain', FX.grain !== false);
    document.body.classList.toggle('fx-vignette', FX.vignette !== false);
    document.body.classList.toggle('fx-scan', FX.scanline !== false);
    document.body.classList.toggle('fx-brackets', FX.brackets !== false);
    document.body.classList.toggle('fx-kenburns', BG.kenBurns !== false);
  }

  function applyBackground() {
    var kind = BG.kind || 'video';
    var vid = document.querySelector('.bg-video');
    var img = document.querySelector('.bg-image');
    if (vid) vid.style.display = (kind === 'video') ? '' : 'none';
    if (img) img.style.display = (kind === 'image') ? '' : 'none';

    if (kind === 'video' && vid) {
      var src = vid.querySelector('source');
      if (src && BG.video) { src.src = BG.video; vid.load(); }
      if (BG.poster) vid.poster = BG.poster;
    } else if (kind === 'image' && img) {
      img.style.backgroundImage = 'url("' + (BG.image || 'poster.jpg') + '")';
    } else if (kind === 'gradient') {
      document.body.style.background = BG.gradient || '#0b0a08';
    } else if (kind === 'solid') {
      document.body.style.background = BG.solid || '#0b0a08';
    }
  }

  function applyCopy() {
    var set = function (id, v) { var e = document.getElementById(id); if (e && v !== undefined) e.textContent = v; };
    set('ls-kicker', T.kicker);
    set('ls-title', T.title);
    set('ls-title-accent', T.titleAccent);
    set('ls-panel', T.panel);
    set('ls-sig', T.signature);
    set('ls-tiptag', T.tipTag);
    var st = (T.stages || [])[0];
    if (st) set('status', st);
  }

  // ── Tips ───────────────────────────────────────────────────
  var tipEl = document.getElementById('tip');
  var tips = (C.tips && (C.tips[C.lang] || C.tips.fr || C.tips.en)) || [];
  var ti = 0;
  function showTip() {
    if (!tipEl || !tips.length) return;
    tipEl.classList.add('fade');
    setTimeout(function () {
      tipEl.textContent = tips[ti % tips.length];
      tipEl.classList.remove('fade');
    }, 400);
    ti++;
  }

  // ── Progress ───────────────────────────────────────────────
  var fill = document.getElementById('fill');
  var pctEl = document.getElementById('pct');
  var statusEl = document.getElementById('status');
  var shown = 0;

  function setProgress(frac) {
    var p = Math.max(shown, Math.min(100, Math.round((frac || 0) * 100)));
    shown = p;
    if (fill) fill.style.width = p + '%';
    if (pctEl) pctEl.innerHTML = '<b>' + p + '</b>%';
    // the status line follows progress through the configured stages
    var stages = T.stages || [];
    if (stages.length && statusEl) {
      var idx = Math.min(stages.length - 1, Math.floor((p / 100) * stages.length));
      if (statusEl.textContent !== stages[idx]) statusEl.textContent = stages[idx];
    }
  }

  window.addEventListener('message', function (e) {
    var d = e.data || {};
    switch (d.eventName) {
      case 'loadProgress': setProgress(d.loadFraction); break;
      case 'initFunctionInvoking':
        if (typeof d.idx === 'number' && d.count) setProgress(0.1 + 0.8 * (d.idx / d.count));
        break;
    }
  });

  // ── Boot ───────────────────────────────────────────────────
  applyTheme();
  applyLayout();
  applyBackground();
  applyCopy();
  showTip();
  setInterval(showTip, Math.max(2, C.tipInterval || 6) * 1000);
  // gentle creep so the bar never looks frozen when events are sparse
  setInterval(function () { if (shown < 92) setProgress((shown + 1) / 100); }, 900);
})();
