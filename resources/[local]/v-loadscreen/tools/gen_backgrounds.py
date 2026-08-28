#!/usr/bin/env python3
"""Procedural seamless-loop backgrounds for the doc-loading screen.

Renders at RW x RH, upscales to 3840x2160 during encoding. Everything is a
periodic function of the loop phase, so frame N-1 -> frame 0 is seamless.

usage:
    python gen_backgrounds.py preview            # one PNG per scene
    python gen_backgrounds.py render <outdir>    # webm + poster jpg per scene
"""
import math
import os
import subprocess
import sys

import numpy as np

RW, RH = 1920, 1080
OUT_W, OUT_H = 3840, 2160
FPS = 30
DURATION = 12.0
NFRAMES = int(FPS * DURATION)
ASPECT = RW / RH

U = np.linspace(0.0, 1.0, RW, endpoint=False, dtype=np.float32)[None, :]
V = np.linspace(0.0, 1.0, RH, endpoint=False, dtype=np.float32)[:, None]
UU = np.broadcast_to(U, (RH, RW))
VV = np.broadcast_to(V, (RH, RW))
TAU = np.float32(2.0 * math.pi)


# ---------------------------------------------------------------- helpers ---
def ramp(x, stops):
    """Map a scalar field through a colour ramp. stops = [(pos, (r, g, b))]."""
    pos = np.array([s[0] for s in stops], dtype=np.float32)
    cols = np.array([s[1] for s in stops], dtype=np.float32) / 255.0
    out = np.empty(x.shape + (3,), dtype=np.float32)
    for c in range(3):
        out[..., c] = np.interp(x, pos, cols[:, c]).astype(np.float32)
    return out


def smoothstep(a, b, x):
    t = np.clip((x - a) / (b - a), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def fractal_noise(h, w, beta, seed, lowcut=2):
    """Periodic fractal noise through spectral synthesis (tileable by design)."""
    rng = np.random.default_rng(seed)
    fy = np.fft.fftfreq(h)[:, None]
    fx = np.fft.fftfreq(w)[None, :]
    f = np.sqrt(fy * fy + fx * fx)
    f[0, 0] = 1.0
    amp = f ** (-beta)
    amp[f < lowcut / max(h, w)] = 0.0
    amp[0, 0] = 0.0
    spec = amp * np.exp(1j * rng.uniform(0.0, 2.0 * math.pi, (h, w)))
    img = np.real(np.fft.ifft2(spec)).astype(np.float32)
    img -= img.min()
    img /= img.max() + 1e-9
    return img


def morph(fields, phase):
    """Cyclic crossfade across N fields -> a perfectly looping evolving field."""
    n = len(fields)
    w = np.array(
        [((1.0 + math.cos(2.0 * math.pi * (phase - k / n))) * 0.5) ** 3 for k in range(n)],
        dtype=np.float32,
    )
    w /= w.sum()
    out = fields[0] * w[0]
    for k in range(1, n):
        out += fields[k] * w[k]
    return out


def subpixel_roll(field, shift_x):
    i0 = int(math.floor(shift_x))
    fr = np.float32(shift_x - i0)
    return np.roll(field, i0, axis=1) * (1.0 - fr) + np.roll(field, i0 + 1, axis=1) * fr


def make_stars(count, seed, top_bias=2.0, vmax=1.0):
    rng = np.random.default_rng(seed)
    sx = (rng.random(count) * RW).astype(np.int32)
    sy = ((rng.random(count) ** top_bias) * vmax * RH).astype(np.int32)
    mag = (rng.random(count) ** 2.4).astype(np.float32)
    phase = rng.random(count).astype(np.float32)
    freq = rng.integers(1, 5, count).astype(np.float32)
    tint = rng.random(count).astype(np.float32)
    return sx, sy, mag, phase, freq, tint


def draw_stars(img, stars, phase, gain=1.0):
    sx, sy, mag, ph, fr, tint = stars
    twinkle = 0.55 + 0.45 * np.sin(TAU * (fr * phase + ph))
    bright = (0.18 + 1.25 * mag) * twinkle * gain
    col = np.stack(
        [0.62 + 0.38 * tint, 0.72 + 0.22 * tint, np.ones_like(tint)], axis=1
    ) * bright[:, None]
    for dy in (-1, 0, 1):
        for dx in (-1, 0, 1):
            falloff = 1.0 if (dx == 0 and dy == 0) else (0.34 if dx * dy == 0 else 0.16)
            yy = np.clip(sy + dy, 0, RH - 1)
            xx = np.clip(sx + dx, 0, RW - 1)
            np.add.at(img, (yy, xx), col * falloff)


def vignette(strength=0.55, power=1.6):
    dx = (UU - 0.5) * ASPECT
    dy = VV - 0.5
    r = np.sqrt(dx * dx + dy * dy) / 0.86
    return (1.0 - strength * np.clip(r, 0.0, 1.0) ** power).astype(np.float32)


VIGNETTE = vignette()
DITHER_RNG = np.random.default_rng(1234)


def to_bytes(rgb):
    """Tone map, dither, quantise. Dither kills the banding VP9 would amplify."""
    rgb = rgb / (1.0 + rgb * 0.22)          # soft shoulder, keeps neons from clipping
    rgb = np.clip(rgb, 0.0, 1.0) ** (1 / 1.04)
    rgb = rgb * 255.0 + DITHER_RNG.uniform(-0.6, 0.6, rgb.shape).astype(np.float32)
    return np.clip(rgb, 0.0, 255.0).astype(np.uint8)


# ----------------------------------------------------------------- scenes ---
class Aurora:
    """Polar curtains over a deep navy sky. Cyan -> violet -> pink."""

    name = "aurora"
    label = "Aurora"

    def __init__(self):
        self.sky = ramp(
            VV,
            [
                (0.00, (3, 4, 14)),
                (0.40, (6, 7, 26)),
                (0.70, (12, 8, 36)),
                (0.90, (24, 9, 46)),
                (1.00, (7, 4, 18)),
            ],
        )
        self.stars = make_stars(1400, 11, top_bias=1.5, vmax=0.86)
        self.ribbons = [
            dict(yc=0.34, amp=0.085, f1=1.0, f2=2.0, s1=1.0, s2=-1.0, p1=0.10, p2=0.60,
                 sigma=0.105, col=(0.16, 0.92, 0.86), gain=0.90,
                 st=((6, 1, .10), (14, -0.7, .55), (27, 0.4, .30))),
            dict(yc=0.47, amp=0.100, f1=1.0, f2=3.0, s1=-1.0, s2=1.0, p1=0.45, p2=0.15,
                 sigma=0.125, col=(0.55, 0.32, 1.00), gain=1.00,
                 st=((5, -1, .40), (11, 0.8, .10), (21, -0.5, .70))),
            dict(yc=0.60, amp=0.075, f1=2.0, f2=1.0, s1=1.0, s2=2.0, p1=0.80, p2=0.35,
                 sigma=0.140, col=(1.00, 0.30, 0.68), gain=0.80,
                 st=((8, 1, .80), (17, -0.6, .25), (31, 0.3, .95))),
            dict(yc=0.24, amp=0.060, f1=3.0, f2=1.0, s1=-2.0, s2=1.0, p1=0.25, p2=0.90,
                 sigma=0.075, col=(0.32, 0.68, 1.00), gain=0.50,
                 st=((9, -1.4, .15), (19, 0.9, .60), (37, -0.4, .35))),
        ]

    def frame(self, phase):
        img = self.sky.copy()
        draw_stars(img, self.stars, phase, gain=1.0)

        for rb in self.ribbons:
            line = (
                rb["yc"]
                + rb["amp"] * np.sin(TAU * (rb["f1"] * U + rb["s1"] * phase + rb["p1"]))
                + rb["amp"] * 0.55 * np.sin(TAU * (rb["f2"] * U + rb["s2"] * phase + rb["p2"]))
            )
            # curtain striations: cheap 1-D field, broadcast over the column
            acc = np.zeros_like(U)
            for f, s, p in rb["st"]:
                acc = acc + np.sin(TAU * (f * U + s * phase + p))
            striate = 0.5 + 0.5 * np.tanh(acc * 0.68)

            d = (VV - line) / rb["sigma"]
            # bright hard bottom edge, long soft tail upwards, like the real thing
            body = np.exp(-np.where(d > 0, d * d * 2.6, d * d * 0.42))
            glow = np.exp(-np.abs(d) * 1.15) * 0.22
            amt = (body * (0.28 + 0.95 * striate) + glow) * rb["gain"]
            amt *= smoothstep(-0.10, 0.30, VV) * smoothstep(1.20, 0.72, VV)
            img += np.stack(rb["col"], axis=-1) * amt[..., None] * 1.05

        # horizon bloom breathing under the curtains
        hb = np.exp(-((VV - 0.90) ** 2) / 0.010) * (0.50 + 0.50 * math.sin(TAU * phase))
        img += np.array([0.62, 0.16, 0.58], dtype=np.float32) * hb[..., None] * 0.30

        # slow sweeping light shafts
        shaft = 0.5 + 0.5 * np.sin(TAU * (1.5 * UU - 0.6 * VV + phase))
        img += np.array([0.28, 0.42, 0.95], dtype=np.float32) * (shaft ** 8)[..., None] * 0.08

        return img * VIGNETTE[..., None] * 0.86


class Nebula:
    """Fractal cosmic clouds drifting through violet and magenta."""

    name = "nebula"
    label = "Nebula"

    def __init__(self):
        self.fields = [fractal_noise(RH, RW, 2.75, 200 + i, lowcut=2) for i in range(4)]
        self.detail = [fractal_noise(RH, RW, 2.20, 300 + i, lowcut=6) for i in range(4)]
        self.stars = make_stars(1900, 77, top_bias=1.0, vmax=1.0)
        self.base = ramp(
            VV,
            [
                (0.00, (3, 3, 12)),
                (0.45, (6, 5, 22)),
                (1.00, (11, 4, 26)),
            ],
        )

    def frame(self, phase):
        big = morph(self.fields, phase)
        big = subpixel_roll(big, phase * RW * 0.35)
        fine = morph(self.detail, (phase + 0.37) % 1.0)
        fine = subpixel_roll(fine, -phase * RW * 0.60)

        density = np.clip(big * 1.70 + fine * 0.34 - 0.58, 0.0, 1.0)
        density = density ** 1.45

        col = ramp(
            np.clip(density * 1.45, 0.0, 1.0),
            [
                (0.00, (10, 14, 44)),
                (0.30, (46, 34, 128)),
                (0.55, (112, 52, 196)),
                (0.78, (196, 72, 200)),
                (0.92, (236, 108, 188)),
                (1.00, (255, 164, 216)),
            ],
        )
        img = self.base + col * (density[..., None] * 0.95)

        # cyan rim where the cloud thins out
        rim = smoothstep(0.06, 0.20, density) * smoothstep(0.42, 0.18, density)
        img += np.array([0.16, 0.78, 1.0], dtype=np.float32) * rim[..., None] * 0.22

        # two slow pulsing cores
        for cx, cy, r, c, sp in (
            (0.28, 0.38, 0.40, (0.48, 0.30, 1.0), 1.0),
            (0.74, 0.62, 0.34, (1.0, 0.28, 0.62), -1.0),
        ):
            dx = (UU - cx) * ASPECT
            dy = VV - cy
            g = np.exp(-(dx * dx + dy * dy) / (r * r))
            pulse = 0.60 + 0.40 * math.sin(TAU * (phase * sp))
            img += np.array(c, dtype=np.float32) * (g * pulse)[..., None] * 0.26

        starmask = np.clip(1.0 - density * 2.6, 0.0, 1.0)
        layer = np.zeros_like(img)
        draw_stars(layer, self.stars, phase, gain=1.25)
        img += layer * starmask[..., None]

        return img * VIGNETTE[..., None] * 0.92


def palm_layer(horizon):
    """Static palm silhouettes, drawn once with PIL and reused every frame."""
    from PIL import Image, ImageDraw, ImageFilter

    ss = 3  # supersample for clean edges
    w, h = RW * ss, RH * ss
    canvas = Image.new("L", (w, h), 0)
    d = ImageDraw.Draw(canvas)

    def blade(ox, oy, angle, length, width, droop, flip):
        pts_a, pts_b = [], []
        steps = 30
        for i in range(steps + 1):
            t = i / steps
            a = angle + droop * t * t * flip
            x = ox + math.cos(a) * length * t
            y = oy - math.sin(a) * length * t
            # fat in the first third, tapering to a point
            half = width * math.sin(math.pi * min(t * 1.15, 1.0) ** 0.72) * (1.0 - t * 0.35)
            nx, ny = -math.sin(a), -math.cos(a)
            pts_a.append((x + nx * half, y + ny * half))
            pts_b.append((x - nx * half, y - ny * half))
        d.polygon(pts_a + pts_b[::-1], fill=255)

    # x, base y, height, lean, frond count, scale
    trees = [
        (0.055, 1.06, 0.86, -0.10, 11, 1.00),
        (0.135, 1.02, 0.60, 0.08, 10, 0.72),
        (0.945, 1.06, 0.90, 0.11, 11, 1.05),
        (0.862, 1.01, 0.56, -0.07, 9, 0.68),
        (0.245, 0.985, 0.34, 0.05, 8, 0.42),
        (0.762, 0.985, 0.30, -0.06, 8, 0.38),
    ]
    for tx, by, th, lean, fronds, sc in trees:
        bx, byy = tx * w, by * h
        top_x = bx + lean * th * h * ss / ss
        top_y = byy - th * h
        left, right = [], []
        steps = 20
        for i in range(steps + 1):
            t = i / steps
            x = bx + (top_x - bx) * (t ** 1.55)
            y = byy + (top_y - byy) * t
            half = (0.0105 * w * sc) * (1.0 - 0.52 * t)
            left.append((x - half, y))
            right.append((x + half, y))
        d.polygon(left + right[::-1], fill=255)

        wobble = [0.92, 1.08, 0.84, 1.14, 0.96, 1.05, 0.88, 1.10, 0.98, 1.02, 0.90]
        for k in range(fronds):
            a = math.pi * (0.04 + 0.92 * k / max(1, fronds - 1))
            flip = 1.0 if math.cos(a) < 0 else -1.0
            jitter = wobble[k % len(wobble)]
            blade(top_x, top_y, a,
                  0.165 * h * sc * jitter,
                  0.036 * h * sc * (0.85 + 0.3 * jitter),
                  1.75, flip)
        d.ellipse(
            [top_x - 0.014 * w * sc, top_y - 0.014 * w * sc,
             top_x + 0.014 * w * sc, top_y + 0.014 * w * sc],
            fill=255,
        )

    small = canvas.resize((RW, RH), Image.LANCZOS)
    mask = np.asarray(small, dtype=np.float32)[:, :] / 255.0
    glow = np.asarray(small.filter(ImageFilter.GaussianBlur(9)), dtype=np.float32) / 255.0
    rim = np.clip(glow * 2.1 - mask * 2.0, 0.0, 1.0)
    return mask, rim


class Synthwave:
    """Vice City horizon: striped sun, neon grid, palms, warm sunset sky."""

    name = "synthwave"
    label = "Vice"

    HORIZON = 0.615

    def __init__(self):
        self.stars = make_stars(900, 404, top_bias=1.4, vmax=self.HORIZON - 0.02)
        self.sky = ramp(
            np.clip(VV / self.HORIZON, 0.0, 1.0),
            [
                (0.00, (16, 6, 44)),
                (0.26, (52, 12, 84)),
                (0.50, (120, 22, 116)),
                (0.70, (196, 40, 122)),
                (0.86, (250, 96, 104)),
                (0.96, (255, 152, 76)),
                (1.00, (255, 206, 122)),
            ],
        )
        self.palm_mask, self.palm_rim = palm_layer(self.HORIZON)
        ridge = fractal_noise(1, RW * 2, 2.1, 909, lowcut=3)[0][:RW]
        ridge = (ridge - ridge.min()) / (ridge.max() - ridge.min() + 1e-9)
        self.ridge = (self.HORIZON - 0.015 - ridge * 0.085).astype(np.float32)[None, :]
        ridge2 = fractal_noise(1, RW * 2, 2.4, 1313, lowcut=2)[0][:RW]
        ridge2 = (ridge2 - ridge2.min()) / (ridge2.max() - ridge2.min() + 1e-9)
        self.ridge2 = (self.HORIZON - 0.010 - ridge2 * 0.140).astype(np.float32)[None, :]

    def frame(self, phase):
        img = self.sky.copy()
        skymask = (VV < self.HORIZON).astype(np.float32)
        layer = np.zeros_like(img)
        draw_stars(layer, self.stars, phase, gain=0.85)
        img += layer * skymask[..., None] * smoothstep(self.HORIZON, 0.18, VV)[..., None]

        # --- sun -------------------------------------------------------------
        cx, cy, r = 0.5, self.HORIZON - 0.105, 0.180
        dx = (UU - cx) * ASPECT
        dy = VV - cy
        dist = np.sqrt(dx * dx + dy * dy)
        disc = smoothstep(r, r - 0.004, dist)
        stripe_pos = np.clip((VV - cy) / r, -1.0, 1.0)
        sun_col = ramp(
            (stripe_pos + 1.0) * 0.5,
            [
                (0.00, (255, 62, 158)),
                (0.26, (255, 92, 122)),
                (0.46, (255, 136, 74)),
                (0.68, (255, 182, 62)),
                (1.00, (255, 232, 148)),
            ],
        )
        stripes = 0.5 + 0.5 * np.sin(TAU * (stripe_pos * 4.5 - phase * 1.0))
        stripe_mask = np.clip(
            1.0 - smoothstep(-0.85, 0.35, stripe_pos) * (1.0 - stripes ** 1.6) * 0.92, 0.0, 1.0
        )
        img = img * (1.0 - disc[..., None]) + sun_col * (disc * stripe_mask)[..., None] * 0.95
        halo = np.exp(-np.clip(dist - r, 0.0, None) / 0.11)
        img += np.array([1.0, 0.34, 0.62], dtype=np.float32) * halo[..., None] * 0.34

        # --- mountains -------------------------------------------------------
        for ridge, fill, tint in (
            (self.ridge2, (0.045, 0.020, 0.085), (0.42, 0.22, 0.90)),
            (self.ridge, (0.020, 0.008, 0.040), (1.00, 0.26, 0.70)),
        ):
            below = smoothstep(0.0, 0.0035, VV - ridge)
            img = img * (1.0 - below[..., None]) + np.array(fill, dtype=np.float32) * below[..., None]
            edge = np.exp(-((VV - ridge) ** 2) / 2.2e-5)
            img += np.array(tint, dtype=np.float32) * edge[..., None] * 1.05

        # --- grid ------------------------------------------------------------
        d = np.clip(VV - self.HORIZON, 1e-4, None)
        depth = 0.055 / d
        ground = (VV > self.HORIZON).astype(np.float32)

        zp = depth * 3.2 + phase * 2.0
        zfw = np.clip(3.2 * 0.055 / (d * d * RH), 1e-4, 0.45)
        zd = np.minimum(zp % 1.0, 1.0 - zp % 1.0)
        zlines = np.clip(1.0 - zd / (zfw * 1.6), 0.0, 1.0) ** 1.5

        xp = (UU - 0.5) * depth * 14.0
        xfw = np.clip(depth * 14.0 / RW, 1e-4, 0.45)
        xd = np.minimum(xp % 1.0, 1.0 - xp % 1.0)
        xlines = np.clip(1.0 - xd / (xfw * 1.6), 0.0, 1.0) ** 1.5

        fade = smoothstep(0.0, 0.06, VV - self.HORIZON) * smoothstep(1.06, 0.72, VV)
        gridmix = np.clip(zlines * 0.9 + xlines * 0.75, 0.0, 1.6) * fade * ground
        gcol = ramp(
            np.clip((VV - self.HORIZON) / (1.0 - self.HORIZON), 0.0, 1.0),
            [(0.0, (255, 78, 190)), (0.5, (176, 92, 255)), (1.0, (86, 226, 255))],
        )
        ground_col = ramp(
            np.clip((VV - self.HORIZON) / (1.0 - self.HORIZON), 0.0, 1.0),
            [(0.0, (32, 8, 54)), (1.0, (8, 4, 22))],
        )
        img = img * (1.0 - ground[..., None]) + ground_col * ground[..., None]
        img += gcol * gridmix[..., None] * 1.45

        # ground haze plus the sun's reflection running down the grid
        haze = np.exp(-np.clip(VV - self.HORIZON, 0.0, None) / 0.10) * ground
        img += np.array([0.85, 0.25, 0.85], dtype=np.float32) * haze[..., None] * 0.34
        refl = np.exp(-((UU - 0.5) ** 2) / 0.010) * np.exp(
            -np.clip(VV - self.HORIZON, 0.0, None) / 0.16
        ) * ground
        img += np.array([1.0, 0.42, 0.72], dtype=np.float32) * refl[..., None] * 0.40

        # the horizon itself: a hot neon seam
        seam = np.exp(-((VV - self.HORIZON) ** 2) / 6.0e-6)
        img += np.array([1.0, 0.78, 0.60], dtype=np.float32) * seam[..., None] * 0.55

        # --- palms, lit from behind ------------------------------------------
        sway = 0.30 + 0.20 * math.sin(TAU * phase)
        img += np.array([1.0, 0.34, 0.70], dtype=np.float32) * self.palm_rim[..., None] * sway
        img *= 1.0 - self.palm_mask[..., None] * 0.97
        img += np.array([0.10, 0.02, 0.09], dtype=np.float32) * self.palm_mask[..., None]

        return img * VIGNETTE[..., None] * 0.94


SCENES = [Aurora, Nebula, Synthwave]


# ------------------------------------------------------------------ output ---
def preview(outdir):
    from PIL import Image

    os.makedirs(outdir, exist_ok=True)
    for cls in SCENES:
        sc = cls()
        for ph in (0.0, 0.33):
            arr = to_bytes(sc.frame(ph))
            path = os.path.join(outdir, f"{sc.name}-{int(ph * 100):02d}.png")
            Image.fromarray(arr).resize((1280, 720), Image.LANCZOS).save(path)
            print("wrote", path, flush=True)


def render(outdir):
    os.makedirs(outdir, exist_ok=True)
    for cls in SCENES:
        sc = cls()
        webm = os.path.join(outdir, f"{sc.name}.webm")
        poster = os.path.join(outdir, f"{sc.name}.jpg")
        cmd = [
            "ffmpeg", "-y", "-hide_banner", "-loglevel", "error",
            "-f", "rawvideo", "-pix_fmt", "rgb24",
            "-s", f"{RW}x{RH}", "-r", str(FPS), "-i", "-",
            "-vf", f"scale={OUT_W}:{OUT_H}:flags=lanczos,format=yuv420p",
            "-c:v", "libvpx-vp9", "-b:v", "0", "-crf", "34",
            "-row-mt", "1", "-cpu-used", "4", "-g", "300", "-tile-columns", "2",
            "-an", webm,
        ]
        proc = subprocess.Popen(cmd, stdin=subprocess.PIPE)
        for i in range(NFRAMES):
            arr = to_bytes(sc.frame(i / NFRAMES))
            if i == 0:
                from PIL import Image

                Image.fromarray(arr).resize((OUT_W, OUT_H), Image.LANCZOS).save(
                    poster, quality=88, subsampling=1, optimize=True
                )
            proc.stdin.write(arr.tobytes())
            if i % 30 == 0:
                print(f"{sc.name} {i}/{NFRAMES}", flush=True)
        proc.stdin.close()
        proc.wait()
        print(f"done {webm} ({os.path.getsize(webm) / 1e6:.2f} MB)", flush=True)


if __name__ == "__main__":
    mode = sys.argv[1] if len(sys.argv) > 1 else "preview"
    target = sys.argv[2] if len(sys.argv) > 2 else "."
    (preview if mode == "preview" else render)(target)
