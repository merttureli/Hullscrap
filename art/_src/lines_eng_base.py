"""Engine wave 1 framework (engines_1.md): every engine is two halves drawn separately, in their own coordinates.
 outside half  W x OUT_H (32 = 4x2 cells, 48 = 4x3 cells; strafe jets are 32 wide): nozzles pointing UP, the bottom 4px are the flange onto the wall
 inside half   W x 36, offset (0, -4): a W x 32 core with a 5px flange on top
An engine class (EngBase) draws out(o, on, i) and core(c, on, i), the damage (hurt_*, wreck_*) and the glow (glow_*); Half2 turns it into a component."""
from lines_kit import *
from lines_engine import ORIENT_OUT, ORIENT_IN, flange, _crop

def from_full(dst, full, y0):
    """copy rows y0.. of a bigger canvas into dst."""
    for y in range(dst.h):
        for x in range(dst.w): dst.g[y][x] = full.g[y0 + y][x]

def via_full(base, spr, y0, fn, *a):
    """run an existing damage routine of lines_engine (written for the 64x80 full engine) on a canvas that holds `spr` at row y0 and take the result back."""
    f = Spr(64, 80); f.stamp(0, y0, spr.rows()); getattr(base, fn)(f, *a); from_full(spr, f, y0)

ANIMS = [('on', 'on', 3, 8), ('off', 'off', 1, 0), ('damaged', 'damaged', 2, 8), ('disabled', 'disabled', 1, 0)]

def flange_n(s, y, h, kind, W=64):
    """a plate where the half meets the wall (same look as lines_engine.flange; narrower for the 2-cell strafe jets)."""
    if W == 64: return flange(s, y, h, kind)
    if kind == 'std':
        bev(s, 1, y, W - 2, h, 'L', 'M', 'S')
        for x in (4, W // 2 - 1, W - 6): s.put(x, y + h // 2, 'L')
    elif kind == 'scrap':
        hw = (W - 2) // 2
        s.rect(1, y, hw, h, 'S'); s.hline(1, y, hw, 'M'); s.rect(1 + hw, y, hw, h, 'u'); s.hline(1 + hw, y, hw, 'Q'); s.hline(1, y + h - 1, W - 2, 'n')
        bolts(s, [(3, y + 1), (W - 6, y + 1)]); s.vline(1 + hw, y, h, 'K')
    else:
        s.rect(1, y, W - 2, h, 'J'); s.hline(1, y, W - 2, 'j'); s.hline(1, y + h - 1, W - 2, 'I'); s.hline(3, y + h // 2, W - 6, 'c')
        for x in (5, W // 2 - 1, W - 6): s.put(x, y + h // 2, 'm')

def bell_gen(s, x0, w0, secs, y_end, on, i, neck_tones='LMSSSWWE', mouth_y=None, bands=(26, 30), lip=True, hot=('o', 'y', 'H'), neck=None):
    """bell_up (lines_engine) for any width: stepped cone, seams, a neck tube down to y_end. secs = [(y0, y1, inset)], first section is at the mouth.
    w0 = 15 and secs of bell_up with y_end 32 reproduce bell_up exactly (bands at 26 and 30)."""
    m = secs[0][0] if mouth_y is None else mouth_y
    for k, (y0, y1, inset) in enumerate(secs):
        wd = w0 - 2 * inset
        T = col_tones(wd)
        for y in range(y0, y1 + 1):
            for q in range(wd): s.put(x0 + inset + q, y, T[q])
        if k: s.hline(x0 + inset, y0, wd, 'E')
        if k and y1 - y0 >= 4: s.put(x0 + w0 // 2, y0 + 3, 'E')
        if k == 1: s.put(x0 + 2, y0 + 2, 'L'); s.put(x0 + w0 - 3, y0 + 2, 'L')
    nw = w0 - 6 if neck is None else neck
    T = col_tones(nw, neck_tones)
    for y in range(secs[-1][1] + 1, y_end):
        for q in range(nw): s.put(x0 + (w0 - nw) // 2 + q, y, T[q])
    for y in bands:
        if y + 1 < y_end: s.hline(x0 + 2, y, w0 - 4, 'M'); s.hline(x0 + 2, y + 1, w0 - 4, 'W')
    s.hline(x0 + 2, m, w0 - 4, 'D'); s.hline(x0 + 2, m + 1, w0 - 4, 'D')
    s.put(x0 + 1, m, 'M'); s.put(x0 + 1, m + 1, 'L'); s.put(x0 + w0 - 2, m, 'W'); s.put(x0 + w0 - 2, m + 1, 'M')
    o, yl, H = hot
    if on:
        fl = [0, 1, 0][i % 3]
        s.hline(x0 + 2 + fl, m, w0 - 4 - 2 * fl, o)
        s.hline(x0 + 2, m + 1, w0 - 4, o); s.hline(x0 + 4 + fl, m + 1, w0 - 8 - 2 * fl, yl)
        c = x0 + w0 // 2
        s.put(c, m + 1, H); s.put(c - 1 + (i % 2), m + 1, H)
    else:
        s.hline(x0 + 4, m + 1, w0 - 8, 'E'); s.put(x0 + w0 // 2, m, 'W')

class EngBase:
    id = '?'; W = 64; OUT_H = 32; KIND = 'std'
    DMG = (0, 2)
    anims = ANIMS
    notes = ''
    dark = None
    pad_out = (10, 32, 10, 4)           # glow overhang of the outside half: left, top, right, bottom
    pad_in = (10, 6, 10, 8)
    anchors_out = {}
    anchors_in = {}
    def out(self, o, on, i): pass
    def core(self, c, on, i): pass
    def hurt_out(self, o, i): pass
    def hurt_core(self, c, i): pass
    def wreck_out(self, o): pass
    def wreck_core(self, c): pass
    def glow_out(self, g, ox, oy, i, flick=None): pass     # (ox, oy) = where the half's top-left sits in g
    def glow_core(self, g, ox, oy, i, flick=None): pass
    def flange_out(self, o): pass                          # extras drawn after the flange (e.g. a registry band)
    def flange_in(self, c): pass

class Half2(LComp):
    def __init__(self, full, part):
        self.full, self.part = full, part
        self.id = full.id + ('_out' if part == 'out' else '')
        W = full.W
        self.cells = (W // 16, full.OUT_H // 16) if part == 'out' else (W // 16, 2)
        self.DMG = full.DMG
        self.anims = list(full.anims)
        self.orientation = ORIENT_OUT if part == 'out' else ORIENT_IN
        self.notes = full.notes + (' THIS FILE: the OUTSIDE half (nozzles, in space against the outer wall face; its bottom 4px are the flange onto the wall). It is never destroyed, only disabled (bent, dead, fixable).' if part == 'out'
                                    else ' THIS FILE: the INSIDE half (core, power coupling, repair hatch; its top 4px overhang the inner wall face as a flange).')
        self.glow_pad = full.pad_out if part == 'out' else full.pad_in
        self._h = full.OUT_H if part == 'out' else 36
        self.offset = None if part == 'out' else (0, -4)
        self.anchors = dict(full.anchors_out if part == 'out' else full.anchors_in)
        self.extra = {'mount': {'part': 'outside' if part == 'out' else 'inside', 'faces': 'rotation 0: outward is up'}}
    @property
    def w(self): return self.full.W
    @property
    def h(self): return self._h
    def build(self, state, i):
        f = self.full; W = f.W
        dm = dict(DARK); dm.update(f.dark or {})
        if self.part == 'out':
            o = Spr(W, f.OUT_H)
            if state == 'damaged': f.out(o, True, f.DMG[i]); f.hurt_out(o, i)
            elif state == 'disabled': f.out(o, False, 0); o = o.sub(dm); f.wreck_out(o)
            else: f.out(o, state == 'on', i)
            flange_n(o, f.OUT_H - 4, 4, f.KIND, W); f.flange_out(o)
            return o
        c = Spr(W, 32)
        if state == 'damaged': f.core(c, True, f.DMG[i]); f.hurt_core(c, i)
        elif state == 'disabled': f.core(c, False, 0); c = c.sub(dm); f.wreck_core(c)
        else: f.core(c, state == 'on', i)
        o = Spr(W, 36); o.stamp(0, 4, c.rows())
        flange_n(o, 0, 5, f.KIND, W); f.flange_in(o)
        return o
    def frame(self, state, i):
        s = self.build(state, i); outline_all(s); return drop_shadow(s)
    def glow_frame(self, state, i):
        l, t, r, b = self.glow_pad
        g = Rgba(self.w + l + r, self.h + t + b)
        if state == 'disabled': return g
        fn = self.full.glow_out if self.part == 'out' else self.full.glow_core
        if state == 'damaged': fn(g, l, t, self.DMG[i], flick=i)
        else: fn(g, l, t, i)
        return g
