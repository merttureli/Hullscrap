"""Round-2 demo helper. A piece is composed once on one Song; EXPLORE and BATTLE are two mixes of the same parts,
so the two files have the same length and every shared note lands on the same sample. The transition demo plays
EXPLORE, crossfades to BATTLE mid-bar, plays BATTLE, and crossfades back."""
import os
import tempfile
import numpy as np
import synth as S
from synth import SR, db
from common import Song


def once(fx):
    """Memoise a part effect on its input buffer, so a part mixed into both versions is processed once."""
    memo = {}

    def run(x):
        if id(x) not in memo:
            memo[id(x)] = (x, fx(x))
        return memo[id(x)][1]
    return run


class Demo(Song):
    def __init__(self, bpm, bars, seed, bpb=4):
        super().__init__(bpm, bars, seed, bpb)
        self.hits = {}

    def hit(self, part, sig, beat, gain=1.0, pan=0.0, ms=0.0):
        """put(), recording the sample position (the sidechain key)."""
        at = self.at(beat, ms)
        self.part(part).put(sig, at, gain, pan)
        self.hits.setdefault(part, []).append(at)
        return at

    def mix(self, spec, ir, rv_db=0.0, air=4.0, env=None, bus_fx=None):
        """Like Song.mix, over the parts named in spec only. Parts flagged bus=True are summed (dry and send) and run
        through bus_fx first: the glitch edits."""
        dry, send = np.zeros((2, self.L), np.float32), np.zeros((2, self.L), np.float32)
        gdry, gsend = np.zeros_like(dry), np.zeros_like(dry)
        for name, p in spec.items():
            if name not in self.parts:
                continue
            x = self.parts[name].buf
            if p.get("fx"):
                x = p["fx"](x)
            x = S.filt(x, p.get("hp"), p.get("lp"), p.get("order", 2), p.get("eq", ()))
            x = x * np.float32(db(p.get("g", 0.0)))
            d, sn = (gdry, gsend) if p.get("bus") else (dry, send)
            d += x
            if p.get("send", 0.2):
                sn += x * np.float32(p.get("send", 0.2))
        if bus_fx:
            gdry, gsend = bus_fx(gdry), bus_fx(gsend)
        out = dry + gdry + S.reverb(send + gsend, ir) * np.float32(db(rv_db))
        if air:
            out = S.filt(out, bells=((4500, air, 1.3), (11000, air * 0.8, 1.0)))
        return out * env[None, :] if env is not None else out

    def master(self, mix, rms_db, ceil_db=-2.4):
        """synth.master, then a trial Vorbis encode: the codec adds up to 2 dB of inter-sample overshoot on the busier
        battle mixes, so the ceiling comes down until the encoded file stays under -1 dBTP."""
        import build_music as B
        for _ in range(4):
            y = S.master(mix, rms_db, ceil_db)
            path = os.path.join(tempfile.gettempdir(), "hullscrap_tp_%d.ogg" % os.getpid())
            B.encode(y, path)
            tp = 20 * np.log10(S.true_peak(B.decode(path)))
            os.remove(path)
            if tp <= -1.1:
                break
            ceil_db -= tp + 1.25
        return y

    def xfade_points(self, near_s=30.0, play_s=30.0, fade_s=4.0, off1=2.5, off2=1.5):
        """Crossfade starts: off1 beats into the bar that holds near_s, and off2 beats into the bar that holds the end
        of play_s seconds of BATTLE. Both are mid-bar on purpose."""
        bar_s = self.sec(4)
        a = (int(near_s / bar_s) * 4 + off1) * self.spb
        b = (int((a / SR + fade_s + play_s) / bar_s) * 4 + off2) * self.spb
        return int(a), int(b)

    def transition(self, x, b, fade_s=4.0, after_s=6.0, out_s=2.5):
        """EXPLORE until a, equal-gain crossfade to BATTLE over fade_s, BATTLE until c, crossfade back, EXPLORE for
        after_s more seconds, fade out over the last out_s. Reads past the loop end by wrapping."""
        a, c = self.xfade_points(fade_s=fade_s)
        f = int(fade_s * SR)
        n = c + f + int(after_s * SR)
        i = np.arange(n)
        r = lambda k: 0.5 - 0.5 * np.cos(np.pi * np.clip(k / f, 0, 1))
        w = (r(i - a) - r(i - c)).astype(np.float32)
        y = x[:, i % self.L] * (1 - w)[None, :] + b[:, i % self.L] * w[None, :]
        k = int(out_s * SR)
        y[:, -k:] *= (0.5 + 0.5 * np.cos(np.pi * np.arange(k) / k)).astype(np.float32)[None, :]
        return y.astype(np.float32), (round(a / SR, 2), round(c / SR, 2))
