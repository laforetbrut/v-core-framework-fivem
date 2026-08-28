#!/usr/bin/env python3
"""Original royalty-free ambient loops for the doc-loading screen.

Everything is synthesised from oscillators and noise - no samples, no borrowed
melody. The reverb tail past the loop point is folded back to the head so each
track loops without a seam.

usage: python gen_music.py <outdir> [preset ...]
"""
import math
import os
import subprocess
import sys

import numpy as np

SR = 44100
TAIL = 4.0


def hz(midi):
    return 440.0 * 2.0 ** ((midi - 69) / 12.0)


# Each preset is one chord loop in a different key, at a different tempo, with a
# different pad colour. They are all meant to sit under the screen rather than
# be listened to, so nothing here moves fast or gets loud.
PRESETS = {
    'neon-horizon': dict(
        title='Neon Horizon', bpm=76.0, cycles=12, seed=20260730,
        harmonics=22, tilt=1.45, pad=0.085, arp=0.055, bass=0.30,
        rest=0.45, reverb=0.34, octave=12,
        prog=[(45, [57, 60, 64, 71]), (41, [53, 57, 60, 64]),
              (48, [60, 64, 67, 74]), (43, [55, 59, 62, 69])],
    ),
    'sunset-boulevard': dict(
        title='Sunset Boulevard', bpm=68.0, cycles=8, seed=515101,
        harmonics=18, tilt=1.62, pad=0.092, arp=0.046, bass=0.30,
        rest=0.55, reverb=0.40, octave=12,
        prog=[(42, [54, 57, 61, 68]), (38, [50, 54, 57, 61]),
              (45, [57, 61, 64, 71]), (40, [52, 56, 59, 66])],
    ),
    'ocean-drive': dict(
        title='Ocean Drive', bpm=72.0, cycles=8, seed=717202,
        harmonics=24, tilt=1.38, pad=0.082, arp=0.062, bass=0.28,
        rest=0.35, reverb=0.32, octave=12,
        prog=[(38, [50, 53, 57, 64]), (34, [46, 50, 53, 57]),
              (41, [53, 57, 60, 67]), (36, [48, 52, 55, 62])],
    ),
    'midnight-palms': dict(
        title='Midnight Palms', bpm=64.0, cycles=8, seed=313303,
        harmonics=16, tilt=1.75, pad=0.098, arp=0.038, bass=0.33,
        rest=0.62, reverb=0.44, octave=12,
        prog=[(36, [48, 51, 55, 62]), (32, [44, 48, 51, 55]),
              (39, [51, 55, 58, 65]), (34, [46, 50, 53, 60])],
    ),
    'vice-nights': dict(
        title='Vice Nights', bpm=80.0, cycles=9, seed=919404,
        harmonics=26, tilt=1.32, pad=0.078, arp=0.066, bass=0.29,
        rest=0.30, reverb=0.30, octave=12,
        prog=[(40, [52, 55, 59, 66]), (36, [48, 52, 55, 59]),
              (43, [55, 59, 62, 69]), (38, [50, 54, 57, 64])],
    ),
    'afterglow': dict(
        title='Afterglow', bpm=70.0, cycles=8, seed=121505,
        harmonics=20, tilt=1.55, pad=0.088, arp=0.050, bass=0.27,
        rest=0.50, reverb=0.42, octave=12,
        prog=[(43, [55, 58, 62, 69]), (39, [51, 55, 58, 62]),
              (46, [58, 62, 65, 72]), (41, [53, 57, 60, 67])],
    ),
}


class Track:
    def __init__(self, cfg):
        self.cfg = cfg
        self.beat = 60.0 / cfg['bpm']
        self.bar = self.beat * 4.0
        self.bars = cfg['cycles'] * 4
        self.total = self.bar * self.bars
        self.n = int(self.total * SR)
        self.nt = int((self.total + TAIL) * SR)
        self.rng = np.random.default_rng(cfg['seed'])

    # ---------------------------------------------------------------- parts --
    def adsr(self, length, attack, decay, sustain, release):
        n = int(length * SR)
        env = np.zeros(n, dtype=np.float32)
        a = max(1, int(attack * SR))
        d = max(1, int(decay * SR))
        r = max(1, int(release * SR))
        s = max(1, n - a - d - r)
        env[:a] = np.linspace(0.0, 1.0, a) ** 1.6
        env[a:a + d] = np.linspace(1.0, sustain, d)
        env[a + d:a + d + s] = sustain
        env[a + d + s:a + d + s + r] = np.linspace(sustain, 0.0, r) ** 1.4
        return env[:n]

    def add(self, buf, start, chunk):
        i = int(start * SR)
        j = min(len(buf), i + len(chunk))
        if j > i:
            buf[i:j] += chunk[: j - i]

    def pad_voice(self, freq, dur):
        """Warm additive voice with a slow filter sweep across the harmonics."""
        c = self.cfg
        n = int(dur * SR)
        t = np.arange(n, dtype=np.float32) / SR
        out = np.zeros(n, dtype=np.float32)
        sweep = 0.55 + 0.45 * np.sin(2 * math.pi * t / (self.bar * 4.0))
        for k in range(1, c['harmonics'] + 1):
            f = freq * k
            if f > 15000.0:
                break
            weight = (1.0 / k ** c['tilt']) * np.exp(-(k - 1) / (2.5 + 9.0 * sweep))
            out += weight * np.sin(2 * math.pi * f * t + self.rng.random() * 6.283).astype(np.float32)
        return out

    def build(self):
        c = self.cfg
        left = np.zeros(self.nt, dtype=np.float32)
        right = np.zeros(self.nt, dtype=np.float32)
        prog = c['prog']

        for bar in range(self.bars):
            t0 = bar * self.bar
            bass_m, voicing = prog[bar % len(prog)]
            cycle = bar // 4
            # the arrangement opens up through the loop, then eases back
            swell = 0.55 + 0.45 * math.sin(math.pi * (cycle + 0.5) / c['cycles'])

            env = self.adsr(self.bar + 1.6, 0.85, 0.7, 0.72, 1.0)
            for vi, m in enumerate(voicing):
                base = hz(m)
                for detune, pan in ((-7.0, -1.0), (0.0, 0.0), (7.0, 1.0)):
                    f = base * 2.0 ** (detune / 1200.0)
                    sig = self.pad_voice(f, self.bar + 1.6) * env * (c['pad'] * swell / (1.0 + 0.28 * vi))
                    self.add(left, t0, sig * (0.5 - 0.34 * pan))
                    self.add(right, t0, sig * (0.5 + 0.34 * pan))

            bf = hz(bass_m)
            bn = int((self.bar + 0.5) * SR)
            bt = np.arange(bn, dtype=np.float32) / SR
            benv = self.adsr(self.bar + 0.5, 0.06, 0.35, 0.55, 0.5)
            bass = (np.sin(2 * math.pi * bf * bt) * 0.9
                    + np.sin(2 * math.pi * bf * 2 * bt) * 0.20
                    + np.sin(2 * math.pi * bf * 3 * bt) * 0.06).astype(np.float32)
            bass = np.tanh(bass * 1.4) * benv * c['bass']
            self.add(left, t0, bass * 0.5)
            self.add(right, t0, bass * 0.5)

            pattern = [0, 1, 2, 3, 2, 1, 2, 3, 0, 2, 1, 3, 2, 3, 1, 2]
            for step, idx in enumerate(pattern):
                if (step % 2) and self.rng.random() < c['rest']:
                    continue                     # let the pattern breathe
                when = t0 + step * self.beat / 4.0
                oct_up = c['octave'] if step % 8 >= 4 else 0
                f = hz(voicing[idx] + oct_up)
                an = int(0.9 * SR)
                at = np.arange(an, dtype=np.float32) / SR
                decay = np.exp(-at * 5.5).astype(np.float32)
                pluck = (np.sin(2 * math.pi * f * at)
                         + 0.34 * np.sin(2 * math.pi * f * 2 * at)
                         + 0.13 * np.sin(2 * math.pi * f * 3 * at)
                         + 0.05 * np.sin(2 * math.pi * f * 5 * at)).astype(np.float32)
                pluck *= decay * c['arp'] * swell
                pan = -0.55 if step % 2 == 0 else 0.55
                self.add(left, when, pluck * (0.5 - 0.36 * pan))
                self.add(right, when, pluck * (0.5 + 0.36 * pan))
                for k, (dly, gain) in enumerate(((self.beat * 0.75, 0.40), (self.beat * 1.5, 0.17))):
                    self.add(left, when + dly, pluck * gain * (0.5 + 0.36 * pan * (-1) ** k))
                    self.add(right, when + dly, pluck * gain * (0.5 - 0.36 * pan * (-1) ** k))

        # airy noise swells, one per cycle
        for cycle in range(c['cycles']):
            t0 = cycle * self.bar * 4.0
            n = int(self.bar * 4.0 * SR)
            noise = self.rng.normal(0.0, 1.0, n).astype(np.float32)
            env = np.sin(np.linspace(0.0, math.pi, n)).astype(np.float32) ** 2.2
            spec = np.fft.rfft(noise)
            freqs = np.fft.rfftfreq(n, 1.0 / SR)
            spec *= np.exp(-((freqs / 2400.0) ** 2)) * (freqs > 220.0)
            filt = np.fft.irfft(spec, n).astype(np.float32)
            filt = filt / (np.abs(filt).max() + 1e-9) * env * 0.055
            self.add(left, t0, filt)
            self.add(right, t0, np.roll(filt, 311))

        return left, right

    def reverb(self, sig, seed, seconds=2.6):
        r = np.random.default_rng(seed)
        n = int(seconds * SR)
        t = np.arange(n, dtype=np.float32) / SR
        ir = r.normal(0.0, 1.0, n).astype(np.float32) * np.exp(-t * 2.4)
        ir[: int(0.012 * SR)] *= 0.15
        kern = np.ones(24, dtype=np.float32) / 24.0
        ir = np.convolve(ir, kern, mode="same").astype(np.float32)
        ir /= np.abs(ir).sum() / 12.0
        size = 1
        while size < len(sig) + n:
            size <<= 1
        wet = np.fft.irfft(np.fft.rfft(sig, size) * np.fft.rfft(ir, size))[: len(sig)]
        mix = self.cfg['reverb']
        return (sig * (1.0 - mix) + wet.astype(np.float32) * mix).astype(np.float32)

    def render(self, path):
        left, right = self.build()
        left = self.reverb(left, self.cfg['seed'] + 1)
        right = self.reverb(right, self.cfg['seed'] + 2)

        # fold the tail back over the head so the loop point is inaudible
        for ch in (left, right):
            ch[: self.nt - self.n] += ch[self.n:]
        left, right = left[:self.n], right[:self.n]

        stereo = np.stack([left, right], axis=1)
        stereo = np.tanh(stereo * 1.25) * 0.86
        stereo /= np.abs(stereo).max() + 1e-9
        stereo *= 0.89

        # Codec follows the extension. mp3 is the safest bet inside FiveM's CEF:
        # it is the format the stock loading screen ships and the one every
        # build is guaranteed to decode.
        if path.lower().endswith(".ogg"):
            codec = ["-c:a", "libvorbis", "-q:a", "2"]
        else:
            codec = ["-c:a", "libmp3lame", "-q:a", "7", "-joint_stereo", "1"]
        cmd = [
            "ffmpeg", "-y", "-hide_banner", "-loglevel", "error",
            "-f", "f32le", "-ar", str(SR), "-ac", "2", "-i", "-",
        ] + codec + [path]
        p = subprocess.Popen(cmd, stdin=subprocess.PIPE)
        p.stdin.write(stereo.astype(np.float32).tobytes())
        p.stdin.close()
        p.wait()
        size = os.path.getsize(path) / 1e6
        print(f"{os.path.basename(path)}  {self.total:6.1f}s  {size:5.2f} MB", flush=True)


if __name__ == "__main__":
    outdir = sys.argv[1] if len(sys.argv) > 1 else "."
    ext = os.environ.get("DOC_MUSIC_EXT", "mp3").lstrip(".")
    names = sys.argv[2:] or list(PRESETS)
    os.makedirs(outdir, exist_ok=True)
    for name in names:
        Track(PRESETS[name]).render(os.path.join(outdir, name + "." + ext))
