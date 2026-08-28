/* ==========================================================================
   v-loadscreen - runtime
   author: doc, vyrriox

   Reads config.js, paints the screen, listens to the game's loading events and
   exposes the music and effect controls to the player. No framework, no CDN:
   everything the screen needs ships with the resource.
   ========================================================================== */
(function () {
  'use strict';

  /* ------------------------------------------------------------ defaults -- */
  const DEFAULTS = {
    locale: 'fr',
    identity: { logo: null, logoMaxWidth: 32, name: '', showTitle: true, tagline: '', showServerPill: true, showPlayerCount: true },
    theme: {
      cyan: '#17e8ff', teal: '#00d9b2', violet: '#a855f7', magenta: '#ff2d95',
      pink: '#ff5fa2', coral: '#ff6b4a', orange: '#ff9f2e', gold: '#ffd166',
      ink: '#170424', text: '#fff2ea', textMuted: '#d7a6c6',
      panelOpacity: 0.3, panelBlur: 24, cornerRadius: 18,
      gradient: ['#17e8ff', '#a855f7', '#ff2d95', '#ff9f2e'],
    },
    background: { mode: 'slideshow', interval: 20, fade: 1.8, kenBurns: true, shuffle: false, sources: [], scrim: 0.5, tint: 0.24 },
    effects: { particles: true, particleDensity: 1, aurora: true, grain: true, scanlines: false, vignette: true, parallax: true, cursorGlow: true, intro: true, frame: true, beam: true, glitch: true, performanceMode: false },
    music: { enabled: true, volume: 0.35, fadeIn: 3, shuffle: true, loop: true, showPlayer: true, playerExpanded: true, rememberChoice: true, debug: false, tracks: [] },
    settings: { enabled: true, allowMusic: true, allowBackground: true, allowEffects: true },
    tips: { enabled: true, interval: 9, shuffle: true },
    keybinds: { enabled: true, items: [] },
    links: { enabled: true, items: [] },
    progress: { showPercent: true, showStage: true, showLogLine: true, showStageDots: true },
    runtime: { manualShutdown: false, shutdownDelay: 1.5, minimumDisplayTime: 6, enterButton: false, failsafeTimeout: 180 },
    locales: {},
  };

  function merge(base, over) {
    if (over === undefined || over === null) return base;
    // `typeof null` is 'object', so the null default has to be caught first or
    // every key that defaults to null silently keeps the default.
    if (base === undefined || base === null) return over;
    if (typeof base !== 'object' || typeof over !== 'object') return over;
    if (Array.isArray(base) || Array.isArray(over)) return over;
    const out = Object.assign({}, base);
    for (const k of Object.keys(over)) out[k] = merge(base[k], over[k]);
    return out;
  }

  const CFG = merge(DEFAULTS, window.DocLoadingConfig || {});
  const L = (CFG.locales && (CFG.locales[CFG.locale] || CFG.locales.fr || CFG.locales.en)) || {};
  const UI = L.ui || {};
  const STAGES = UI.stages || {};

  const $ = (id) => document.getElementById(id);
  const app = $('app');
  // Loading screens are served from nui://<resource>/ or https://cfx-nui-<resource>/
  // depending on the build, so try every route to the resource name.
  const RES = (function () {
    if (typeof window.GetParentResourceName === 'function') {
      try { return window.GetParentResourceName(); } catch (e) { /* not in game */ }
    }
    const host = location.hostname || (/^[a-z]+:\/\/([^/]+)/i.exec(location.href || '') || [])[1] || '';
    return host.replace(/^cfx-nui-/, '') || 'v-loadscreen';
  })();

  const reduceMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;

  /* -------------------------------------------------------------- store -- */
  const STORE_KEY = 'v-loadscreen.prefs';
  const prefs = (function () {
    if (!CFG.music.rememberChoice) return {};
    try { return JSON.parse(localStorage.getItem(STORE_KEY)) || {}; } catch (e) { return {}; }
  })();
  function savePrefs() {
    if (!CFG.music.rememberChoice) return;
    try { localStorage.setItem(STORE_KEY, JSON.stringify(prefs)); } catch (e) { /* private mode */ }
  }

  /* --------------------------------------------------------- nui bridge -- */
  // A loading screen cannot call back into Lua on every build. Where it cannot,
  // every one of these fails, so stop after a handful rather than firing a
  // doomed request once a second for the life of the screen.
  let postFailures = 0;
  let postDead = false;
  function post(name, data) {
    if (postDead) return Promise.resolve();
    return fetch('https://' + RES + '/' + name, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json; charset=UTF-8' },
      body: JSON.stringify(data || {}),
    }).then(
      function () { postFailures = 0; },
      function () { if (++postFailures >= 5) postDead = true; }
    );
  }

  /* --------------------------------------------------------- frame driver -- */
  // One requestAnimationFrame for the whole screen. Four independent loops used
  // to run side by side, each paying the callback and timing overhead.
  const Loop = (function () {
    const fns = [];
    let raf = 0;
    function tick(now) {
      raf = requestAnimationFrame(tick);
      // iterate a copy: a callback is allowed to remove itself mid frame
      const list = fns.slice();
      for (let i = 0; i < list.length; i++) {
        try { list[i](now); } catch (e) { /* one bad frame must not stop the rest */ }
      }
    }
    return {
      add: function (fn) {
        if (fns.indexOf(fn) === -1) fns.push(fn);
        if (!raf) raf = requestAnimationFrame(tick);
      },
      remove: function (fn) {
        const i = fns.indexOf(fn);
        if (i !== -1) fns.splice(i, 1);
        if (!fns.length && raf) { cancelAnimationFrame(raf); raf = 0; }
      },
    };
  })();

  /* --------------------------------------------------------------- theme -- */
  function applyTheme() {
    const t = CFG.theme;
    const r = document.documentElement.style;
    r.setProperty('--c-cyan', t.cyan);
    r.setProperty('--c-teal', t.teal);
    r.setProperty('--c-violet', t.violet);
    r.setProperty('--c-magenta', t.magenta);
    r.setProperty('--c-pink', t.pink);
    r.setProperty('--c-coral', t.coral);
    r.setProperty('--c-orange', t.orange);
    r.setProperty('--c-gold', t.gold);
    r.setProperty('--ink', t.ink);
    r.setProperty('--text', t.text);
    r.setProperty('--muted', t.textMuted);
    r.setProperty('--radius', t.cornerRadius + 'px');
    r.setProperty('--panel-blur', t.panelBlur + 'px');

    const rgb = hexToRgb(t.ink) || { r: 24, g: 5, b: 36 };
    r.setProperty('--panel-bg', 'rgba(' + (rgb.r + 12) + ',' + (rgb.g + 4) + ',' + (rgb.b + 16) + ',' + t.panelOpacity + ')');

    const stops = (t.gradient && t.gradient.length > 1) ? t.gradient : [t.cyan, t.magenta];
    r.setProperty('--grad', 'linear-gradient(90deg,' + stops.join(',') + ')');
    r.setProperty('--edge-hot', hexToRgba(t.pink, 0.38));
    r.setProperty('--scrim', String(CFG.background.scrim));
    r.setProperty('--tint', String(CFG.background.tint));
    r.setProperty('--fade', CFG.background.fade + 's');
    r.setProperty('--logo-w', CFG.identity.logoMaxWidth + 'vw');
  }

  function hexToRgb(hex) {
    const m = /^#?([a-f\d]{2})([a-f\d]{2})([a-f\d]{2})$/i.exec(String(hex).trim());
    return m ? { r: parseInt(m[1], 16), g: parseInt(m[2], 16), b: parseInt(m[3], 16) } : null;
  }
  function hexToRgba(hex, a) {
    const c = hexToRgb(hex);
    return c ? 'rgba(' + c.r + ',' + c.g + ',' + c.b + ',' + a + ')' : 'rgba(255,95,162,' + a + ')';
  }

  /* --------------------------------------------------------------- perf -- */
  let perfMode = CFG.effects.performanceMode;
  if (prefs.perf !== undefined) perfMode = !!prefs.perf;

  function applyEffectFlags() {
    app.classList.toggle('perf', perfMode);
    const e = CFG.effects;
    $('aurora').hidden = perfMode || !e.aurora;
    $('grain').hidden = perfMode || !(prefs.grain !== undefined ? prefs.grain : e.grain);
    $('scanlines').hidden = perfMode || !(prefs.scanlines !== undefined ? prefs.scanlines : e.scanlines);
    $('vignette').hidden = !e.vignette;
    $('fx').hidden = perfMode || !(prefs.particles !== undefined ? prefs.particles : e.particles);
    $('cursorGlow').hidden = perfMode || !e.cursorGlow;
    $('frame').hidden = perfMode || !e.frame;
    $('beam').hidden = perfMode || !e.beam;
    $('flash').hidden = perfMode || !e.glitch;
  }

  /* ==================================================== background layer == */
  const Background = (function () {
    const host = $('bg');
    const cfg = CFG.background;
    let order = [];
    let idx = -1;
    let current = null;
    let timer = null;
    let paused = false;

    function buildOrder() {
      order = (cfg.sources || []).slice();
      if (!order.length) order = [{ type: 'generated' }];
      if (cfg.shuffle) {
        for (let i = order.length - 1; i > 0; i--) {
          const j = Math.floor(Math.random() * (i + 1));
          const t = order[i]; order[i] = order[j]; order[j] = t;
        }
      }
    }

    function makeSlide(src) {
      const slide = document.createElement('div');
      slide.className = 'slide' + (cfg.kenBurns && !perfMode && !reduceMotion ? ' kb' : '');
      if (src.focus) slide.style.setProperty('--focus', src.focus);

      if (src.type === 'video') {
        const v = document.createElement('video');
        v.muted = true; v.loop = true; v.autoplay = true; v.playsInline = true;
        v.preload = 'auto';
        if (src.poster) v.poster = src.poster;
        v.src = src.src;
        const kick = function () { const p = v.play(); if (p && p.catch) p.catch(function () {}); };
        v.addEventListener('canplay', kick, { once: true });
        kick();
        slide.appendChild(v);
        slide.__video = v;
      } else if (src.type === 'image') {
        const img = document.createElement('img');
        img.decoding = 'async';
        img.src = src.src;
        slide.appendChild(img);
      } else {
        slide.appendChild(Generated.create());
        slide.__generated = true;
      }
      return slide;
    }

    function show(slide) {
      host.appendChild(slide);
      // force a frame so the opacity transition actually runs
      void slide.offsetWidth;
      slide.classList.add('on');
      if (current && !$('flash').hidden && !reduceMotion) {
        app.classList.remove('glitch');
        void app.offsetWidth;
        app.classList.add('glitch');
        setTimeout(function () { app.classList.remove('glitch'); }, 520);
      }
      const old = current;
      current = slide;
      if (old) {
        old.classList.remove('on');
        setTimeout(function () {
          if (old.__video) { try { old.__video.pause(); old.__video.removeAttribute('src'); old.__video.load(); } catch (e) {} }
          if (old.__generated) Generated.destroy(old.firstChild);
          old.remove();
        }, cfg.fade * 1000 + 120);
      }
    }

    function preload(src) {
      if (!src || src.type !== 'image') return;
      const i = new Image();
      i.src = src.src;
    }

    function next() {
      if (!order.length) return;
      idx = (idx + 1) % order.length;
      show(makeSlide(order[idx]));
      preload(order[(idx + 1) % order.length]);
      schedule();
    }

    function schedule() {
      clearTimeout(timer);
      if (paused || cfg.mode !== 'slideshow' || order.length < 2) return;
      timer = setTimeout(next, Math.max(4, cfg.interval) * 1000);
    }

    return {
      start: function () { buildOrder(); next(); },
      next: next,
      setPaused: function (v) { paused = v; schedule(); },
      isPaused: function () { return paused; },
      count: function () { return order.length; },
    };
  })();

  /* ------------------------------------------- generated canvas backdrop -- */
  const Generated = (function () {
    const live = new Set();

    function create() {
      const c = document.createElement('canvas');
      const ctx = c.getContext('2d');
      const state = { c: c, ctx: ctx, t: Math.random() * 1000 };

      function size() {
        const dpr = Math.min(window.devicePixelRatio || 1, 1.5);
        c.width = Math.max(2, Math.round(window.innerWidth * dpr * 0.5));
        c.height = Math.max(2, Math.round(window.innerHeight * dpr * 0.5));
      }
      size();
      state.onResize = size;
      window.addEventListener('resize', size);

      const cols = [CFG.theme.cyan, CFG.theme.violet, CFG.theme.magenta, CFG.theme.orange];

      function frame() {
        state.t += 0.0016;
        const w = c.width, h = c.height, t = state.t;
        ctx.globalCompositeOperation = 'source-over';
        ctx.fillStyle = CFG.theme.ink;
        ctx.fillRect(0, 0, w, h);
        ctx.globalCompositeOperation = 'lighter';
        for (let i = 0; i < cols.length; i++) {
          const a = t * (0.6 + i * 0.21) + i * 1.7;
          const x = w * (0.5 + 0.36 * Math.sin(a) * Math.cos(a * 0.53 + i));
          const y = h * (0.5 + 0.34 * Math.cos(a * 0.81 + i * 2.1));
          const r = Math.max(w, h) * (0.34 + 0.1 * Math.sin(a * 1.3));
          const g = ctx.createRadialGradient(x, y, 0, x, y, r);
          g.addColorStop(0, hexToRgba(cols[i], 0.5));
          g.addColorStop(1, hexToRgba(cols[i], 0));
          ctx.fillStyle = g;
          ctx.fillRect(0, 0, w, h);
        }
      }
      state.frame = frame;
      frame();
      Loop.add(frame);
      live.add(state);
      c.__state = state;
      return c;
    }

    function destroy(c) {
      const s = c && c.__state;
      if (!s) return;
      Loop.remove(s.frame);
      window.removeEventListener('resize', s.onResize);
      live.delete(s);
    }

    return { create: create, destroy: destroy };
  })();

  /* ======================================================== particle field == */
  const Particles = (function () {
    const c = $('fx');
    const ctx = c.getContext('2d');
    let parts = [], streaks = [], dpr = 1, running = false, speed = 1;
    let cols = [], sprites = [];

    // A 4K canvas is 8.3 million pixels to clear and fill every frame. The motes
    // are soft glows, so painting at up to ~2.1 Mpx and letting CSS stretch the
    // canvas is invisible and up to four times cheaper.
    const PIXEL_BUDGET = 2100000;

    // One pre-rendered glow per colour, drawn once. Building a radial gradient
    // per particle per frame was the most expensive thing on the screen.
    const SPRITE = 64;
    function buildSprites() {
      sprites = cols.map(function (col) {
        const s = document.createElement('canvas');
        s.width = s.height = SPRITE;
        const sc = s.getContext('2d');
        const g = sc.createRadialGradient(SPRITE / 2, SPRITE / 2, 0, SPRITE / 2, SPRITE / 2, SPRITE / 2);
        g.addColorStop(0, hexToRgba(col, 1));
        g.addColorStop(1, hexToRgba(col, 0));
        sc.fillStyle = g;
        sc.fillRect(0, 0, SPRITE, SPRITE);
        return s;
      });
    }

    function resize() {
      const vw = window.innerWidth, vh = window.innerHeight;
      const native = Math.min(window.devicePixelRatio || 1, 2);
      dpr = Math.min(native, Math.sqrt(PIXEL_BUDGET / Math.max(1, vw * vh)));
      c.width = Math.max(2, Math.round(vw * dpr));
      c.height = Math.max(2, Math.round(vh * dpr));
      seed();
    }

    function seed() {
      const area = (c.width * c.height) / (dpr * dpr);
      const n = Math.round(Math.min(260, area / 11000) * (CFG.effects.particleDensity || 1));
      parts = [];
      for (let i = 0; i < n; i++) parts.push(spawn(true));
    }

    function spawn(anywhere) {
      return {
        x: Math.random() * c.width,
        y: anywhere ? Math.random() * c.height : c.height + Math.random() * 60 * dpr,
        r: (0.6 + Math.random() * 2.1) * dpr,
        vy: -(0.10 + Math.random() * 0.42) * dpr,
        vx: (Math.random() - 0.5) * 0.16 * dpr,
        a: 0.16 + Math.random() * 0.5,
        sp: (Math.random() * sprites.length) | 0,
        ph: Math.random() * Math.PI * 2,
        sw: 0.4 + Math.random() * 1.3,
      };
    }

    function addStreak() {
      streaks.push({
        x: Math.random() * c.width,
        y: Math.random() * c.height * 0.55,
        len: (90 + Math.random() * 190) * dpr,
        vx: (2.6 + Math.random() * 3.4) * dpr * (Math.random() < 0.5 ? -1 : 1),
        vy: (0.9 + Math.random() * 1.5) * dpr,
        life: 1,
      });
    }

    function frame() {
      ctx.clearRect(0, 0, c.width, c.height);
      ctx.globalCompositeOperation = 'lighter';

      for (let i = 0; i < parts.length; i++) {
        const p = parts[i];
        p.ph += 0.014;
        p.y += p.vy * speed;
        p.x += p.vx * speed + Math.sin(p.ph) * p.sw * 0.16 * dpr;
        if (p.y < -20 * dpr) { parts[i] = spawn(false); continue; }
        const tw = 0.55 + 0.45 * Math.sin(p.ph * 1.7);
        const d = p.r * 9;
        ctx.globalAlpha = p.a * tw;
        ctx.drawImage(sprites[p.sp], p.x - d / 2, p.y - d / 2, d, d);
      }
      ctx.globalAlpha = 1;

      for (let i = streaks.length - 1; i >= 0; i--) {
        const s = streaks[i];
        s.x += s.vx; s.y += s.vy; s.life -= 0.012;
        if (s.life <= 0) { streaks.splice(i, 1); continue; }
        const g = ctx.createLinearGradient(s.x, s.y, s.x - s.vx * 9, s.y - s.vy * 9);
        g.addColorStop(0, hexToRgba(CFG.theme.gold, 0.85 * s.life));
        g.addColorStop(1, hexToRgba(CFG.theme.magenta, 0));
        ctx.strokeStyle = g;
        ctx.lineWidth = 1.7 * dpr;
        ctx.beginPath();
        ctx.moveTo(s.x, s.y);
        ctx.lineTo(s.x - s.vx * 9, s.y - s.vy * 9);
        ctx.stroke();
      }
      if (Math.random() < 0.0035 * speed) addStreak();
    }

    return {
      start: function () {
        if (running) return;
        cols = [CFG.theme.cyan, CFG.theme.violet, CFG.theme.pink, CFG.theme.orange, CFG.theme.gold];
        buildSprites();
        running = true;
        resize();
        window.addEventListener('resize', resize);
        Loop.add(frame);
      },
      stop: function () {
        running = false;
        Loop.remove(frame);
        window.removeEventListener('resize', resize);
        ctx.clearRect(0, 0, c.width, c.height);
      },
      setSpeed: function (v) { speed = v; },
      burst: function () { for (let i = 0; i < 14; i++) addStreak(); },
    };
  })();

  /* ============================================================== music == */
  const Music = (function () {
    const audio = $('audio');
    const el = {
      player: $('player'), body: $('playerBody'), toggle: $('playerToggle'),
      title: $('trackTitle'), artist: $('trackArtist'), spectrum: $('spectrum'),
      play: $('btnPlay'), prev: $('btnPrev'), next: $('btnNext'), mute: $('btnMute'),
      volFill: $('volFill'), volKnob: $('volKnob'), volValue: $('volValue'), volSlider: $('volSlider'),
    };
    let list = [], cur = 0, ready = false;
    let volume = CFG.music.volume, muted = false, fading = 0;
    let bars = [], wantPlay = false, failStreak = 0;

    function iconOf(btn, id) { btn.querySelector('use').setAttribute('href', '#' + id); }

    function buildList() {
      list = (CFG.music.tracks || []).filter(function (t) { return t && t.src; });
      if (CFG.music.shuffle) {
        for (let i = list.length - 1; i > 0; i--) {
          const j = Math.floor(Math.random() * (i + 1));
          const t = list[i]; list[i] = list[j]; list[j] = t;
        }
      }
    }

    function paint() {
      const t = list[cur] || {};
      el.title.textContent = t.title || '--';
      el.artist.textContent = t.artist || '';
      el.volFill.style.width = (volume * 100) + '%';
      el.volKnob.style.left = (volume * 100) + '%';
      el.volValue.textContent = Math.round(volume * 100);
      iconOf(el.mute, muted || volume === 0 ? 'i-mute' : 'i-volume');
      el.mute.title = muted ? (UI.unmute || 'Unmute') : (UI.mute || 'Mute');
      iconOf(el.play, audio.paused ? 'i-play' : 'i-pause');
      el.play.title = audio.paused ? (UI.play || 'Play') : (UI.pause || 'Pause');
      iconOf(el.toggle, muted || volume === 0 ? 'i-mute' : 'i-volume');
      applyVolume();
    }

    function clamp01(v) { return v < 0 ? 0 : (v > 1 ? 1 : v); }
    function applyVolume() {
      // clamped on the way out: a requestAnimationFrame timestamp can land a
      // hair before the performance.now() the fade started from, and the
      // audio element rejects anything outside [0, 1] with a hard throw.
      audio.volume = muted ? 0 : clamp01(clamp01(volume) * clamp01(fading));
    }

    // Reports go to the server console through client.lua, because that is the
    // console a server owner actually has open. A problem is always reported,
    // once; per track detail only when music.debug is on.
    function tell(kind, detail) {
      const a = audio;
      const payload = {
        kind: kind,
        detail: String(detail),
        src: (list[cur] || {}).src || '',
        state: 'paused=' + a.paused + ' t=' + a.currentTime.toFixed(1)
          + ' ready=' + a.readyState + ' net=' + a.networkState
          + ' err=' + (a.error ? a.error.code : 0)
          + ' vol=' + a.volume.toFixed(2) + ' muted=' + a.muted,
        support: 'ogg=' + (a.canPlayType('audio/ogg; codecs="vorbis"') || 'no')
          + ' mp3=' + (a.canPlayType('audio/mpeg') || 'no'),
      };
      try { console.warn('[v-loadscreen] music ' + kind + ': ' + detail); } catch (e) {}
      post('musicIssue', payload);
    }

    let reported = false;
    function report(detail) {
      if (reported) return;
      reported = true;
      tell('problem', detail);
    }

    function debugTell(kind, detail) {
      if (CFG.music.debug) tell(kind, detail);
    }

    function load(i, autoplay) {
      if (!list.length) return;
      cur = ((i % list.length) + list.length) % list.length;
      if (autoplay) wantPlay = true;
      // pause first so the outgoing resource does not reject the new play(),
      // then the full sequence: src, load, play. Dropping the explicit load()
      // was a mistake: it runs before play() here, so it never aborted anything,
      // and without it a build that waits for it never selects the resource.
      try { audio.pause(); } catch (e) { /* nothing playing yet */ }
      audio.src = list[cur].src;
      audio.load();
      if (wantPlay) play();
      paint();
      armWatchdog();
      debugTell('load', (list[cur].title || '?') + ' -> ' + list[cur].src);
      // report what actually happened once the element has had time to settle
      setTimeout(function () { debugTell('after 3s', (list[cur] || {}).title || '?'); }, 3000);
    }

    function play() {
      wantPlay = true;
      const p = audio.play();
      if (p && p.catch) p.catch(function () { waitForGesture(); });
      setTimeout(paint, 60);
    }

    // If the track is still not playing a moment later, ask again. Covers the
    // builds that refuse a play() issued before the resource is ready.
    let watchdog = 0, retries = 0;
    function armWatchdog() {
      clearTimeout(watchdog);
      retries = 0;
      watchdog = setTimeout(poke, 1500);
    }
    function poke() {
      if (!wantPlay || !audio.paused) return;
      if (retries++ >= 4) { report('still paused after ' + retries + ' attempts'); return; }
      const p = audio.play();
      if (p && p.catch) p.catch(function () { waitForGesture(); });
      watchdog = setTimeout(poke, 1500);
    }

    // A track that will not load must not take the rest of the playlist with
    // it. Only a real media error gets here, and the walk is capped and slow
    // enough that it cannot burn the whole list before anyone notices.
    function skipBroken() {
      const code = audio.error ? audio.error.code : 0;
      report('media error ' + code + ' on ' + ((list[cur] || {}).src || '?'));
      failStreak++;
      if (failStreak >= list.length || list.length < 2) return;
      clearTimeout(watchdog);
      setTimeout(function () { load(cur + 1, wantPlay); }, 800);
    }

    let gestureBound = false;
    function waitForGesture() {
      if (gestureBound || !wantPlay) return;
      gestureBound = true;
      const events = ['pointerdown', 'keydown', 'mousemove', 'wheel'];
      const go = function () {
        events.forEach(function (ev) { window.removeEventListener(ev, go); });
        gestureBound = false;
        const p = audio.play();
        // re-arm rather than swallow: one refusal should not end the music
        if (p && p.catch) p.catch(function () { waitForGesture(); });
        setTimeout(paint, 80);
      };
      events.forEach(function (ev) { window.addEventListener(ev, go, { once: true }); });
    }

    function fadeIn() {
      const dur = Math.max(0.1, CFG.music.fadeIn) * 1000;
      const t0 = performance.now();
      (function step(now) {
        fading = clamp01((now - t0) / dur);
        applyVolume();
        if (fading < 1) requestAnimationFrame(step);
      })(t0);
    }

    /* The bars used to be driven by a real AnalyserNode. Routing the element
       through a MediaElementAudioSourceNode is what made a skipped track load
       and then play silently on some CEF builds: the graph is bound to the
       element once and does not always follow a new src. Seven bars are not
       worth that, so the element now plays straight to the output and the bars
       are driven by a shaped oscillation instead. Scaled rather than resized:
       scaleY runs on the compositor, height is a relayout. */
    function spectrum() {
      const n = 7;
      const last = new Array(n).fill(-1);
      for (let i = 0; i < n; i++) { const b = document.createElement('i'); el.spectrum.appendChild(b); bars.push(b); }
      let t = 0, nextAt = 0;

      function step(now) {
        if (now < nextAt) return;  // ~30 fps is plenty for seven bars
        nextAt = now + 33;
        t += 0.16;
        const on = !audio.paused && !muted && volume > 0;
        for (let i = 0; i < n; i++) {
          const wobble = on
            ? 0.5 + 0.34 * Math.sin(t * (1 + i * 0.31) + i) + 0.16 * Math.sin(t * (2.3 + i * 0.17) + i * 2)
            : 0;
          const q = Math.round((0.08 + wobble * 0.7) * 100);
          if (q !== last[i]) {
            last[i] = q;
            bars[i].style.transform = 'scaleY(' + (q / 100) + ')';
          }
        }
      }
      Loop.add(step);
    }

    function bindSlider(node, get, set) {
      let dragging = false;
      function value(e) {
        const r = node.getBoundingClientRect();
        return Math.max(0, Math.min(1, (e.clientX - r.left) / Math.max(1, r.width)));
      }
      node.addEventListener('pointerdown', function (e) {
        dragging = true; node.setPointerCapture(e.pointerId); set(value(e));
      });
      node.addEventListener('pointermove', function (e) { if (dragging) set(value(e)); });
      node.addEventListener('pointerup', function (e) { dragging = false; try { node.releasePointerCapture(e.pointerId); } catch (err) {} });
      node.addEventListener('wheel', function (e) {
        e.preventDefault();
        set(Math.max(0, Math.min(1, get() + (e.deltaY < 0 ? 0.05 : -0.05))));
      }, { passive: false });
    }

    const api = {
      setVolume: function (v) {
        volume = Math.max(0, Math.min(1, v));
        if (volume > 0) muted = false;
        prefs.volume = volume; prefs.muted = muted; savePrefs();
        paint();
        if (typeof api.onchange === 'function') api.onchange();
      },
      getVolume: function () { return volume; },
      isMuted: function () { return muted; },
      toggleMute: function () {
        muted = !muted;
        prefs.muted = muted; savePrefs();
        paint();
        if (typeof api.onchange === 'function') api.onchange();
      },
      togglePlay: function () {
        if (audio.paused) { play(); armWatchdog(); }
        else { wantPlay = false; clearTimeout(watchdog); audio.pause(); paint(); }
      },
      next: function () { load(cur + 1, true); },
      prev: function () { load(cur - 1, true); },
      hasTracks: function () { return list.length > 0; },
      onchange: null,
    };

    api.init = function () {
      if (!CFG.music.enabled) { el.player.hidden = true; return; }
      buildList();
      if (!list.length) { el.player.hidden = true; return; }

      if (prefs.volume !== undefined) volume = prefs.volume;
      if (prefs.muted !== undefined) muted = !!prefs.muted;

      audio.loop = list.length === 1 && CFG.music.loop;
      audio.addEventListener('ended', function () { if (list.length > 1) load(cur + 1, true); });
      audio.addEventListener('playing', function () {
        failStreak = 0;
        clearTimeout(watchdog);
        debugTell('playing', (list[cur] || {}).title || '?');
        paint();
      });
      audio.addEventListener('stalled', function () { debugTell('stalled', (list[cur] || {}).src || '?'); });
      audio.addEventListener('pause', paint);
      audio.addEventListener('error', skipBroken);
      // some builds refuse the play() fired the instant src changes but accept
      // it once the first frames are in
      audio.addEventListener('canplay', function () {
        if (wantPlay && audio.paused) {
          const p = audio.play();
          if (p && p.catch) p.catch(function () { waitForGesture(); });
        }
      });

      el.player.hidden = !CFG.music.showPlayer;
      if (!CFG.music.playerExpanded) el.player.classList.add('collapsed');

      el.play.addEventListener('click', api.togglePlay);
      el.next.addEventListener('click', api.next);
      el.prev.addEventListener('click', api.prev);
      el.mute.addEventListener('click', api.toggleMute);
      el.toggle.addEventListener('click', function () { el.player.classList.remove('collapsed'); });
      el.prev.title = UI.previous || 'Previous';
      el.next.title = UI.next || 'Next';
      el.volSlider.title = UI.volume || 'Volume';
      bindSlider(el.volSlider, api.getVolume, api.setVolume);

      spectrum();
      load(0, true);
      fadeIn();
      ready = true;
    };

    api.bindExternalSlider = function (node, fill, knob, out) {
      bindSlider(node, api.getVolume, function (v) {
        api.setVolume(v);
        fill.style.width = (v * 100) + '%';
        knob.style.left = (v * 100) + '%';
        if (out) out.textContent = Math.round(v * 100);
      });
    };

    api.isReady = function () { return ready; };
    return api;
  })();

  /* =============================================================== tips == */
  const Tips = (function () {
    const card = $('tipCard');
    const icon = $('tipIcon');
    const cat = $('tipCat');
    const text = $('tipText');
    const timer = $('tipTimer');
    const CIRC = 2 * Math.PI * 15.5;
    let items = [], i = -1, dur = 9000, paused = false;
    let handle = 0, startedAt = 0, remaining = 0, flip = false;

    // The countdown ring is a CSS animation rather than a per-frame stroke
    // rewrite, so the whole card costs nothing between two tips.
    function next() {
      if (!items.length) return;
      i = (i + 1) % items.length;
      const tip = items[i];
      icon.querySelector('use').setAttribute('href', '#i-' + (tip.icon || 'bulb'));
      cat.textContent = tip.category || '';
      cat.hidden = !tip.category;
      text.textContent = tip.text || '';
      flip = !flip;
      card.classList.toggle('swap-a', flip);
      card.classList.toggle('swap-b', !flip);
      schedule(dur);
    }

    function schedule(ms) {
      clearTimeout(handle);
      startedAt = Date.now();
      remaining = ms;
      handle = setTimeout(next, ms);
    }

    return {
      init: function () {
        if (!CFG.tips.enabled) return;
        items = (L.tips || []).slice();
        if (!items.length) return;
        if (CFG.tips.shuffle) {
          for (let k = items.length - 1; k > 0; k--) {
            const j = Math.floor(Math.random() * (k + 1));
            const tmp = items[k]; items[k] = items[j]; items[j] = tmp;
          }
        }
        dur = Math.max(3, CFG.tips.interval) * 1000;
        timer.style.strokeDasharray = String(CIRC);
        card.style.setProperty('--tip-dur', (dur / 1000) + 's');
        $('tipLabel').textContent = UI.tipLabel || 'Tip';
        card.hidden = false;
        next();
        card.addEventListener('click', next);
      },
      setPaused: function (v) {
        if (v === paused) return;
        paused = v;
        card.classList.toggle('frozen', v);
        if (v) {
          clearTimeout(handle);
          remaining = Math.max(400, remaining - (Date.now() - startedAt));
        } else {
          schedule(remaining);
        }
      },
    };
  })();

  /* ============================================================ progress == */
  const Progress = (function () {
    const fill = $('fill');
    const pctValue = $('percentValue');
    const stageLabel = $('stageLabel');
    const logline = $('logline');
    const dotsHost = $('stageDots');
    const ORDER = ['core', 'map', 'resources', 'session'];

    let target = 0, shown = 0, stage = 'core', lastBump = performance.now();
    let dots = [];
    let done = false;
    let lastWhole = -1, lastWidth = -1;
    let pendingLog = null, lastLogAt = 0;

    function build() {
      if (!CFG.progress.showStageDots) return;
      dotsHost.hidden = false;
      ORDER.forEach(function () {
        const d = document.createElement('div');
        d.className = 'sd';
        dotsHost.appendChild(d);
        dots.push(d);
      });
    }

    function setStage(s) {
      if (done || stage === s) return;
      if (ORDER.indexOf(s) < ORDER.indexOf(stage)) return; // never walk backwards
      stage = s;
      paintStage();
    }

    function paintStage() {
      if (CFG.progress.showStage) {
        stageLabel.innerHTML = (STAGES[stage] || '') + (done ? '' : '<span class="dotdot"></span>');
      }
      const at = ORDER.indexOf(stage);
      dots.forEach(function (d, k) {
        d.classList.toggle('done', done || k < at);
        d.classList.toggle('now', !done && k === at);
      });
    }

    function bump(v) {
      if (done) return;
      v = Math.max(0, Math.min(0.995, v));
      if (v > target) { target = v; lastBump = performance.now(); }
    }

    function frame(now) {
      // creep a little when the game goes quiet, so the bar never looks frozen
      if (!done && now - lastBump > 1600) {
        target = Math.min(0.97, target + 0.00006 * (now - lastBump > 6000 ? 2 : 1));
      }
      shown += (target - shown) * 0.075;
      if (Math.abs(target - shown) < 0.0004) shown = target;

      // Writing the width every frame relayouts the bar even when the value has
      // not visibly moved. A hundredth of a percent is well under a pixel.
      const width = Math.round(shown * 10000) / 100;
      if (width !== lastWidth) {
        lastWidth = width;
        fill.style.width = width + '%';
      }

      // The engine can fire hundreds of file events a second; repainting the
      // log line for each one is wasted work nobody can read.
      if (pendingLog !== null && now - lastLogAt > 90) {
        lastLogAt = now;
        logline.textContent = pendingLog;
        pendingLog = null;
        // two identical keyframes under different names: swapping the class
        // restarts the animation without forcing a synchronous layout
        const a = logline.classList.toggle('tick-a');
        logline.classList.toggle('tick-b', !a);
      }

      const whole = Math.round(shown * 100);
      if (CFG.progress.showPercent && whole !== lastWhole) {
        lastWhole = whole;
        pctValue.textContent = String(whole);
        const b = pctValue.classList.toggle('tick-a');
        pctValue.classList.toggle('tick-b', !b);
      }
      Particles.setSpeed(1 + shown * 1.6);

      // nothing left to interpolate: stop asking for frames
      if (done && shown >= 0.9999 && pendingLog === null) Loop.remove(frame);
    }

    return {
      init: function () {
        build();
        paintStage();
        $('percent').hidden = !CFG.progress.showPercent;
        Loop.add(frame);
      },
      bump: bump,
      setStage: setStage,
      log: function (msg) {
        if (!CFG.progress.showLogLine || !msg) return;
        pendingLog = String(msg).slice(0, 160);
      },
      complete: function () {
        if (done) return;
        done = true;
        target = 1;
        stage = 'session';
        stageLabel.textContent = STAGES.done || UI.ready || '';
        dots.forEach(function (d) { d.classList.add('done'); d.classList.remove('now'); });
        Particles.burst();
      },
      isDone: function () { return done; },
    };
  })();

  /* ============================================================ settings == */
  function buildSettings() {
    const body = $('settingsBody');
    const btn = $('settingsBtn');
    if (!CFG.settings.enabled) return;
    btn.hidden = false;
    btn.title = UI.settings || 'Settings';
    $('settingsTitle').textContent = UI.settings || 'Settings';
    $('settingsClose').title = UI.close || 'Close';

    function group(title) {
      const g = document.createElement('div');
      g.className = 'set-group';
      const h = document.createElement('h3');
      h.textContent = title;
      g.appendChild(h);
      body.appendChild(g);
      return g;
    }
    function row(g, label) {
      const r = document.createElement('div');
      r.className = 'set-row';
      const l = document.createElement('label');
      l.textContent = label;
      r.appendChild(l);
      g.appendChild(r);
      return r;
    }
    function toggle(r, initial, onchange) {
      const s = document.createElement('div');
      s.className = 'switch' + (initial ? ' on' : '');
      s.addEventListener('click', function () {
        const on = !s.classList.contains('on');
        s.classList.toggle('on', on);
        onchange(on);
      });
      r.appendChild(s);
      return s;
    }
    function action(r, label, onclick) {
      const b = document.createElement('button');
      b.className = 'icon-btn sm';
      b.type = 'button';
      b.innerHTML = '<svg class="ico"><use href="#i-' + label + '"></use></svg>';
      b.addEventListener('click', onclick);
      r.appendChild(b);
      return b;
    }

    if (CFG.settings.allowMusic && Music.hasTracks()) {
      const g = group(UI.music || 'Music');
      const rv = row(g, UI.volume || 'Volume');
      const sl = document.createElement('div');
      sl.className = 'slider';
      sl.innerHTML = '<div class="slider-rail"><div class="slider-fill"></div><div class="slider-knob"></div></div>';
      rv.appendChild(sl);
      const f = sl.querySelector('.slider-fill');
      const k = sl.querySelector('.slider-knob');
      f.style.width = (Music.getVolume() * 100) + '%';
      k.style.left = (Music.getVolume() * 100) + '%';
      Music.bindExternalSlider(sl, f, k, null);
      Music.onchange = function () {
        f.style.width = (Music.getVolume() * 100) + '%';
        k.style.left = (Music.getVolume() * 100) + '%';
        muteSwitch.classList.toggle('on', !Music.isMuted());
      };

      const rm = row(g, UI.music || 'Music');
      const muteSwitch = toggle(rm, !Music.isMuted(), function () { Music.toggleMute(); });

      const rn = row(g, UI.next || 'Next track');
      action(rn, 'next', function () { Music.next(); });
    }

    if (CFG.settings.allowBackground) {
      const g = group(UI.background || 'Background');
      const rs = row(g, UI.slideshow || 'Slideshow');
      toggle(rs, !Background.isPaused(), function (on) { Background.setPaused(!on); });
      const rn = row(g, UI.nextBackground || 'Next background');
      action(rn, 'image', function () { Background.next(); });
    }

    if (CFG.settings.allowEffects) {
      const g = group(UI.visuals || 'Effects');
      const rp = row(g, UI.particles || 'Particles');
      toggle(rp, !$('fx').hidden, function (on) { prefs.particles = on; savePrefs(); applyEffectFlags(); on ? Particles.start() : Particles.stop(); });
      const rg = row(g, UI.grain || 'Grain');
      toggle(rg, !$('grain').hidden, function (on) { prefs.grain = on; savePrefs(); applyEffectFlags(); });
      const rc = row(g, UI.scanlines || 'CRT lines');
      toggle(rc, !$('scanlines').hidden, function (on) { prefs.scanlines = on; savePrefs(); applyEffectFlags(); });
      const rf = row(g, UI.performance || 'Performance mode');
      toggle(rf, perfMode, function (on) {
        perfMode = on; prefs.perf = on; savePrefs();
        applyEffectFlags();
        if (on) Particles.stop(); else if (!$('fx').hidden) Particles.start();
      });
    }

    function open(v) {
      $('settings').hidden = !v;
      $('settingsScrim').hidden = !v;
      Tips.setPaused(v);
    }
    btn.addEventListener('click', function () { open($('settings').hidden); });
    $('settingsClose').addEventListener('click', function () { open(false); });
    $('settingsScrim').addEventListener('click', function () { open(false); });
  }

  /* ============================================================== chrome == */
  function buildChrome() {
    const id = CFG.identity;

    if (id.logo) {
      const img = $('logo');
      img.src = id.logo;
      img.hidden = false;
      const sheen = document.querySelector('.logo-sheen');
      // The mask alone is enough: the wrapper is a grid sized by the image, so
      // inset:0 already tracks it. Pinning a pixel size here went stale the
      // moment the window resized.
      sheen.style.webkitMaskImage = 'url("' + id.logo + '")';
      sheen.style.maskImage = 'url("' + id.logo + '")';
    }

    const nameEl = $('serverName');
    // A wordmark logo already carries the name; printing it again just doubles up.
    const wantTitle = id.showTitle === undefined ? !id.logo : !!id.showTitle;
    if (id.name && wantTitle) {
      const chars = Array.from(id.name);
      nameEl.innerHTML = '';
      chars.forEach(function (ch, i) {
        const s = document.createElement('span');
        s.className = 'ch';
        s.textContent = ch;
        s.style.setProperty('--d', (0.9 + i * 0.032).toFixed(3) + 's');
        nameEl.appendChild(s);
      });
    }
    nameEl.hidden = !(id.name && wantTitle);
    $('tagline').textContent = id.tagline || '';
    $('tagline').hidden = !id.tagline;

    if (id.showServerPill) {
      $('serverPill').hidden = false;
      $('pillName').textContent = id.name || 'Serveur';
    }

    if (CFG.keybinds.enabled && (CFG.keybinds.items || []).length) {
      const host = $('keys');
      const dict = L.keybinds || {};
      CFG.keybinds.items.forEach(function (k) {
        const w = document.createElement('span');
        w.className = 'keybind';
        const cap = document.createElement('kbd');
        cap.className = 'keycap';
        cap.textContent = k.key;
        const lab = document.createElement('span');
        lab.textContent = dict[k.label] || k.label;
        w.appendChild(cap);
        w.appendChild(lab);
        host.appendChild(w);
      });
      $('keysTitle').textContent = UI.keybindsTitle || 'Keybinds';
      $('keysCard').hidden = false;
    }

    if (CFG.links.enabled) {
      const host = $('links');
      (CFG.links.items || []).forEach(function (l) {
        const a = document.createElement('span');
        a.className = 'link';
        a.innerHTML = '<svg class="ico"><use href="#i-' + (l.icon || 'globe') + '"></use></svg>';
        const b = document.createElement('b');
        b.textContent = l.value || l.label || '';
        a.appendChild(b);
        a.title = (l.label ? l.label + ' - ' : '') + (l.value || '');
        host.appendChild(a);
      });
    }

    $('enterLabel').textContent = UI.enter || 'Enter';
    $('stageLabel').textContent = UI.connecting || '';
  }

  /* ============================================================ pointer == */
  function bindPointer() {
    const glow = $('cursorGlow');
    const stage = $('stage');
    const bg = $('bg');
    let raf = 0, tx = 0, ty = 0, cx = 0, cy = 0;

    window.addEventListener('mousemove', function (e) {
      app.classList.add('has-cursor');
      if (!$('cursorGlow').hidden) {
        glow.style.transform = 'translate3d(' + e.clientX + 'px,' + e.clientY + 'px,0)';
      }
      tx = (e.clientX / window.innerWidth - 0.5);
      ty = (e.clientY / window.innerHeight - 0.5);
      if (!raf && CFG.effects.parallax && !perfMode && !reduceMotion) raf = requestAnimationFrame(step);
    });

    function step() {
      raf = 0;
      cx += (tx - cx) * 0.08;
      cy += (ty - cy) * 0.08;
      bg.style.transform = 'translate3d(' + (-cx * 18) + 'px,' + (-cy * 14) + 'px,0) scale(1.045)';
      stage.style.transform = 'translate3d(' + (cx * 12) + 'px,' + (cy * 9) + 'px,0)';
      if (Math.abs(tx - cx) > 0.001 || Math.abs(ty - cy) > 0.001) raf = requestAnimationFrame(step);
    }

    document.addEventListener('contextmenu', function (e) { e.preventDefault(); });
    document.addEventListener('dragstart', function (e) { e.preventDefault(); });

    window.addEventListener('keydown', function (e) {
      const k = e.key.toLowerCase();
      if (k === 'm') Music.toggleMute();
      else if (k === 'n') Music.next();
      else if (k === 'escape') { $('settings').hidden = true; $('settingsScrim').hidden = true; Tips.setPaused(false); }
    });
  }

  /* ====================================================== game messages == */
  const Game = (function () {
    let initCount = 0, initType = 0, dataCount = 0, dataSeen = 0;

    const STAGE_BY_TYPE = { 0: 'core', 1: 'map', 2: 'resources', 3: 'session' };

    const handlers = {
      startInitFunctionOrder: function (d) { initCount = d.count || 0; },
      startInitFunction: function (d) { if (STAGE_BY_TYPE[d.type]) Progress.setStage(STAGE_BY_TYPE[d.type]); },
      initFunctionInvoking: function (d) {
        initType = d.type || 0;
        if (STAGE_BY_TYPE[initType]) Progress.setStage(STAGE_BY_TYPE[initType]);
        const total = d.count || initCount || 1;
        const local = Math.min(1, (d.idx || 0) / total);
        const base = { 0: 0.02, 1: 0.12, 2: 0.30, 3: 0.80 }[initType] || 0.02;
        const span = { 0: 0.10, 1: 0.18, 2: 0.14, 3: 0.15 }[initType] || 0.10;
        Progress.bump(base + local * span);
      },
      initFunctionInvoked: function (d) { if (d && d.name) Progress.log(d.name); },
      startDataFileEntries: function (d) { dataCount = d.count || 0; dataSeen = 0; Progress.setStage('resources'); },
      // Both of these also set the stage: some builds skip startDataFileEntries
      // and go straight to the entries, which would leave the label stuck on
      // the first phase for the rest of the load.
      performMapLoadFunction: function (d) {
        Progress.setStage('resources');
        dataSeen = Math.max(dataSeen, d.idx || dataSeen + 1);
        if (dataCount) Progress.bump(0.44 + Math.min(1, dataSeen / dataCount) * 0.34);
      },
      onDataFileEntry: function (d) {
        Progress.setStage('resources');
        dataSeen++;
        if (d && d.name) Progress.log(d.name);
        const total = d && d.count ? d.count : dataCount;
        if (total) Progress.bump(0.44 + Math.min(1, dataSeen / total) * 0.34);
      },
      endDataFileEntries: function () { Progress.bump(0.80); Progress.setStage('session'); },
      onLogLine: function (d) { if (d && d.message) Progress.log(d.message); },
      loadProgress: function (d) {
        const f = typeof d.loadFraction === 'number' ? d.loadFraction : 0;
        Progress.bump(Math.min(0.985, f * 0.98));
      },
    };

    return {
      listen: function () {
        window.addEventListener('message', function (e) {
          const d = e.data || {};
          if (d.eventName && handlers[d.eventName]) {
            try { handlers[d.eventName](d); } catch (err) { /* keep the screen alive */ }
            return;
          }
          if (!d.action) return;
          switch (d.action) {
            case 'serverInfo': App.serverInfo(d); break;
            case 'gameReady': App.gameReady(); break;
            case 'fadeOut': App.fadeOut(); break;
            case 'progress': if (typeof d.value === 'number') Progress.bump(d.value); break;
          }
        });
      },
    };
  })();

  /* ================================================================ app == */
  const App = {
    serverInfo: function (d) {
      if (!CFG.identity.showPlayerCount) return;
      if (typeof d.players === 'number') {
        $('playerCount').textContent = String(d.players);
        $('playerMax').textContent = d.maxPlayers ? ' / ' + d.maxPlayers : '';
        $('playersLabel').textContent = UI.playersLabel || '';
        $('pillPlayers').hidden = false;
        $('pillSep').hidden = false;
      }
    },

    gameReady: function () {
      Progress.complete();
      if (CFG.runtime.enterButton && CFG.runtime.manualShutdown) {
        const r = $('ready');
        r.hidden = false;
        $('enterBtn').addEventListener('click', function () {
          App.fadeOut();
          post('enter', {});
        }, { once: true });
      }
    },

    fadeOut: function () {
      app.classList.add('leaving');
    },

    boot: function () {
      applyTheme();
      applyEffectFlags();

      if (!CFG.effects.intro || reduceMotion) $('curtain').hidden = true;

      buildChrome();
      Progress.init();
      Tips.init();
      Music.init();
      buildSettings();
      Background.start();
      if (!$('fx').hidden) Particles.start();
      bindPointer();
      Game.listen();

      app.classList.remove('is-booting');

      // Heartbeat. When these stop, the page has been destroyed, which is how
      // client.lua learns that another resource closed the loading screen; it
      // has no native to ask.
      setInterval(function () { post('alive', {}); }, 1000);

      // hand the runtime settings to client.lua and ask for the server info
      post('uiReady', {
        manualShutdown: !!CFG.runtime.manualShutdown,
        shutdownDelay: Number(CFG.runtime.shutdownDelay) || 0,
        minimumDisplayTime: Number(CFG.runtime.minimumDisplayTime) || 0,
        enterButton: !!CFG.runtime.enterButton,
        failsafeTimeout: Number(CFG.runtime.failsafeTimeout) || 0,
        wantsServerInfo: !!CFG.identity.showPlayerCount,
      });
    },
  };

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', App.boot);
  else App.boot();
})();
