"""Song helper (timing, humanising, part canvases, the mix) shared by every track."""
import numpy as np
import synth as S
from synth import SR, db


class Song:
    def __init__(self, bpm, bars, seed, bpb=4, tail=0.0):
        """tail > 0 makes a one-shot: that many seconds of room are added so the reverb never wraps."""
        self.beats = bars * bpb
        n = self.beats * 60 / bpm * SR
        if tail:   # a one-shot: exact tempo, room for the reverb tail after the last beat
            self.L = S.smooth_len(round(n + tail * SR))
            self.spb = n / self.beats
        else:      # a loop: the length snaps to a fast FFT size and the beat grid stretches by under 0.5%
            self.L = S.smooth_len(round(n))
            self.spb = self.L / self.beats
        self.bpm = 60 * SR / self.spb
        self.rng = np.random.default_rng(seed)
        self.parts = {}

    def sec(self, beats):
        return beats * self.spb / SR

    def at(self, beat, ms=0.0):
        j = float(np.clip(self.rng.normal(0, ms / 2), -ms, ms)) if ms else 0.0
        return int(round(beat * self.spb + j * SR / 1000.0))

    def v(self, base, spread=0.1):
        return base * (1 + self.rng.uniform(-spread, spread))

    def part(self, name):
        if name not in self.parts:
            self.parts[name] = S.Canvas(self.L)
        return self.parts[name]

    def put(self, part, sig, beat, gain=1.0, pan=0.0, ms=0.0):
        self.part(part).put(sig, self.at(beat, ms), gain, pan)

    def mix(self, spec, ir, rv_db=0.0, air=4.0, env=None):
        """spec[part] = dict(g=dB, hp=Hz, lp=Hz, send=reverb send (linear), fx=callable on the stereo part)."""
        dry = np.zeros((2, self.L), np.float32)
        send = np.zeros((2, self.L), np.float32)
        for name, cv in self.parts.items():
            p = spec[name]
            x = cv.buf
            if p.get("fx"):
                x = p["fx"](x)
            x = S.filt(x, p.get("hp"), p.get("lp"), p.get("order", 2), p.get("eq", ()))
            x = x * np.float32(db(p.get("g", 0.0)))
            dry += x
            if p.get("send", 0.2):
                send += x * np.float32(p.get("send", 0.2))
        out = dry + S.reverb(send, ir) * np.float32(db(rv_db))
        if air:   # a little air: these parts are dark, so lift the top gently
            out = S.filt(out, bells=((4500, air, 1.3), (11000, air * 0.8, 1.0)))
        return out * env[None, :] if env is not None else out

    def auto(self, points, tau=1.2):
        """Automation curve over the loop: points = [(beat, value)] held until the next point, smoothed over tau seconds."""
        pts = sorted(points)
        pos = np.arange(self.L) / self.spb
        idx = np.clip(np.searchsorted([b for b, _ in pts], pos, side="right") - 1, 0, len(pts) - 1)
        step = np.array([v for _, v in pts], np.float64)[idx]
        return S._conv_smooth(step, tau, False).astype(np.float32)

    def levels(self, spec):
        """Dev aid: each part's RMS (dB) after its filter and gain."""
        out = {}
        for name, cv in self.parts.items():
            p = spec[name]
            x = S.filt(cv.buf, p.get("hp"), p.get("lp"), p.get("order", 2)) * db(p.get("g", 0.0))
            out[name] = round(S.rms_db(x), 1)
        return out
