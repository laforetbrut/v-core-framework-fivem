// v-appearance — dominant colour extraction (CEF-103 safe, no external libs).
// Given an isolated garment's pixels (RGBA), returns up to two NAMED colours by
// nearest CIELAB ΔE. Used by the catalogue scanner to auto-tag colours — there
// is no GTA native that exposes a garment's colour, so we compute it from the
// rendered thumbnail.

(function (global) {
  // sRGB -> CIELAB
  function rgbToLab(r, g, b) {
    r /= 255; g /= 255; b /= 255;
    r = r > 0.04045 ? Math.pow((r + 0.055) / 1.055, 2.4) : r / 12.92;
    g = g > 0.04045 ? Math.pow((g + 0.055) / 1.055, 2.4) : g / 12.92;
    b = b > 0.04045 ? Math.pow((b + 0.055) / 1.055, 2.4) : b / 12.92;
    let x = (r * 0.4124 + g * 0.3576 + b * 0.1805) / 0.95047;
    let y = (r * 0.2126 + g * 0.7152 + b * 0.0722) / 1.0;
    let z = (r * 0.0193 + g * 0.1192 + b * 0.9505) / 1.08883;
    const f = (t) => t > 0.008856 ? Math.cbrt(t) : (7.787 * t + 16 / 116);
    x = f(x); y = f(y); z = f(z);
    return [116 * y - 16, 500 * (x - y), 200 * (y - z)];
  }
  const de = (a, b) => Math.sqrt((a[0] - b[0]) ** 2 + (a[1] - b[1]) ** 2 + (a[2] - b[2]) ** 2);

  // Named palette (label -> representative RGB), precomputed to LAB.
  const NAMED = {
    black: [22, 22, 22], white: [240, 240, 240], grey: [128, 128, 128],
    red: [200, 40, 40], orange: [220, 120, 30], yellow: [225, 205, 55],
    green: [70, 150, 70], blue: [55, 95, 190], purple: [130, 70, 180],
    pink: [220, 120, 170], brown: [110, 75, 45], beige: [205, 190, 160],
  };
  const NAMED_LAB = Object.keys(NAMED).map((k) => ({ name: k, lab: rgbToLab(NAMED[k][0], NAMED[k][1], NAMED[k][2]) }));
  function nearestName(r, g, b) {
    const lab = rgbToLab(r, g, b);
    let best = NAMED_LAB[0], bd = 1e9;
    for (const c of NAMED_LAB) { const d = de(lab, c.lab); if (d < bd) { bd = d; best = c; } }
    return best.name;
  }

  // pixels: Uint8ClampedArray RGBA (from getImageData). Returns {primary, secondary|null}.
  function extractColors(pixels, alphaThreshold) {
    const at = alphaThreshold == null ? 128 : alphaThreshold;
    const bins = {};   // 4-bit/channel key -> { r,g,b,w }
    for (let i = 0; i < pixels.length; i += 4) {
      if (pixels[i + 3] < at) continue;
      const r = pixels[i], g = pixels[i + 1], b = pixels[i + 2];
      // weight by saturation so a grey jacket with a red logo still surfaces red
      const mx = Math.max(r, g, b), mn = Math.min(r, g, b);
      const sat = mx === 0 ? 0 : (mx - mn) / mx;
      const w = 0.35 + sat;                       // floor so neutrals still count
      const key = (r >> 4) * 256 + (g >> 4) * 16 + (b >> 4);
      const bin = bins[key] || (bins[key] = { r: 0, g: 0, b: 0, w: 0 });
      bin.r += r * w; bin.g += g * w; bin.b += b * w; bin.w += w;
    }
    const arr = Object.values(bins).filter((x) => x.w > 0).sort((a, b) => b.w - a.w);
    if (!arr.length) return { primary: null, secondary: null };
    const nameOf = (x) => nearestName(x.r / x.w, x.g / x.w, x.b / x.w);
    const primary = nameOf(arr[0]);
    let secondary = null;
    for (let i = 1; i < arr.length; i++) { const n = nameOf(arr[i]); if (n !== primary) { secondary = n; break; } }
    return { primary, secondary };
  }

  global.AppearanceColor = { extractColors, nearestName, rgbToLab };
})(typeof window !== 'undefined' ? window : this);
