"""Component framework: interior drawing per state -> damaged / disabled variants -> outline, shadow, strips, JSON."""
import json, os
from px import *
from mach import bev, hollow, recess, outline_all, drop_shadow, glow
import compact

# ---------------- hand-drawn damage decals
SCORCH_L = art("""
...DD....
.DDKDD.D.
DDKKKDDD.
.DKKKKDD.
..DDKDD.D
.D.DDD...
....D....
""")
SCORCH_S = art("""
.DD..
DKKD.
.DKDD
..D..
""")
CRACK_A = art("""
K.......
.K......
.KK.....
...K....
...KK.K.
....LKK.
.......K
""")
CRACK_B = art("""
....K..
...K...
..KK...
.K...K.
KK..KK.
......K
""")
LOOSE = art("""
KKKKKKK....
KDDDDDK....
KDrDDuK....
KDuyKKKKKKK
KDDDKLLLLLK
KKKKKLMMMSK
....KLMDMSK
....KLMMMSK
....KSSSSSK
....KKKKKKK
""")
DARK = {'H': 'M', 'L': 'S', 'M': 'S', 'S': 'W', 'W': 'E', 'E': 'D', 'D': 'D', 'Q': 'q', 'q': 'n', 'u': 'n',
        'a': 'u', 'y': 'u', 'o': 'u', 'g': 'E', 'c': 'E', 'r': 'n', 'b': 'E', 'p': 'q', 'm': 'E', 'F': 'W'}

def stamp_on(s, x, y, rows):
    """decal: only lands on pixels that already exist."""
    for j, r in enumerate(rows):
        for i, c in enumerate(r):
            if c != '.' and s.get(x + i, y + j) != '.': s.put(x + i, y + j, c)

class Comp:
    id = '?'; cells = (1, 1)
    glow_pad = (8, 8, 8, 8)              # left, top, right, bottom overhang of the glow layer
    anims = []                           # (name, state, frames, fps)
    anchors = {}
    notes = ''
    scorch = []                          # [(x, y, 'L'|'S')]
    loose = None                         # (x, y)
    cracks = []                          # [(x, y, 'A'|'B')]
    @property
    def w(self): return self.cells[0] * 16
    @property
    def h(self): return self.cells[1] * 16
    def interior(self, state, i): raise NotImplementedError
    def after(self, state, i, s): return s      # overlays drawn after the outline (flashes)
    def glow(self, state, i, g, ox, oy): pass   # paint soft glow into g; sprite top-left is at (ox, oy)
    def frame(self, state, i):
        base = {'damaged': 'on', 'disabled': 'off'}.get(state, state)
        s = self.interior(base, i)
        if state == 'damaged':
            for (x, y, k) in self.scorch: stamp_on(s, x, y, SCORCH_L if k == 'L' else SCORCH_S)
            if self.loose: s.stamp(self.loose[0], self.loose[1], LOOSE)
        if state == 'disabled':
            s = s.sub(DARK)
            for (x, y, k) in self.scorch: stamp_on(s, x, y, SCORCH_L if k == 'L' else SCORCH_S)
            for (x, y, k) in self.cracks: stamp_on(s, x, y, CRACK_A if k == 'A' else CRACK_B)
        s = s.copy(); outline_all(s); s = drop_shadow(s)
        return self.after(base, i, s)
    def glow_frame(self, state, i):
        l, t, r, b = self.glow_pad
        g = Rgba(self.w + l + r, self.h + t + b)
        if state == 'disabled': return g
        self.glow(state, i, g, l, t)
        if state == 'damaged':                        # weaker, uneven light on a damaged part
            for row in g.p:
                for p in row: p[3] = int(p[3] * (0.55 if i % 2 else 0.8))
        return g

def export(c, outdir=None):
    outdir = outdir or ART + '/components'
    os.makedirs(outdir, exist_ok=True)
    frames, gframes, anims, ganims = [], [], {}, {}
    cp = compact.plan_for(c.id)         # a tier 1-2 part that takes less room inside now: its frames are cut to the new width (compact.py)
    for (name, state, n, fps) in c.anims:
        anims[name] = [len(frames), n, fps]
        for i in range(n): frames.append(cp.frame(c, state, i) if cp else c.frame(state, i))
        if state not in ('off', 'disabled'):
            gl = [c.glow_frame(state, i) for i in range(n)]
            if cp: gl = [cp.glow(g, c.glow_pad[0]) for g in gl]
            if any(p[3] for g in gl for row in g.p for p in row):
                ganims[name] = [len(gframes), n, fps]; gframes += gl
    fw = frames[0].w if cp else c.w
    save(sheet(frames, len(frames), fw, c.h), '%s/%s.png' % (outdir, c.id))
    J = {'frame': [fw, c.h], 'cells': list(cp.cells if cp else c.cells), 'anims': anims}
    if gframes:
        l, t, r, b = c.glow_pad
        gw, gh = (gframes[0].w, gframes[0].h) if cp else (c.w + l + r, c.h + t + b)
        strip = Rgba(gw * len(gframes), gh)
        for k, g in enumerate(gframes): strip.blit_rgba(g, k * gw, 0)
        strip.save('%s/%s_glow.png' % (outdir, c.id))
        J['glow'] = {'image': c.id + '_glow.png', 'frame': [gw, gh], 'offset': [-l, -t], 'anims': ganims}
    if c.anchors: J['anchors'] = {k: (cp.anchor(v) if cp else list(v)) for k, v in c.anchors.items()}
    if getattr(c, 'orientation', None): J['orientation'] = c.orientation
    if getattr(c, 'offset', None): J['offset'] = list(c.offset)
    if getattr(c, 'extra', None): J.update(c.extra)
    J['notes'] = c.notes + (' COMPACT (tier 1-2 parts take less room inside): this inside half is the centre of the original art between its own edge columns, re-outlined (art/_src/compact.py).' if cp else '')
    if hasattr(c, 'finish_json'): c.finish_json(J, outdir)     # two-layer weapons add their barrel
    with open('%s/%s.json' % (outdir, c.id), 'w') as f: json.dump(J, f, indent=1); f.write('\n')
    return frames, gframes, J

def chamfer_fill(s, x, y, w, h, c, ch):
    for j in range(h):
        inset = max(0, ch - j, ch - (h - 1 - j))
        for i in range(w):
            if inset <= i < w - inset: s.put(x + i, y + j, c)

def rim(s, base, hi, lo, box=None):
    """pixels of colour `base` get `hi` where the edge faces up/left and `lo` where it faces down/right."""
    x0, y0, x1, y1 = box or (0, 0, s.w - 1, s.h - 1)
    n = s.copy()
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            if s.g[y][x] != base: continue
            if s.get(x, y + 1) != base or s.get(x + 1, y) != base: n.g[y][x] = lo
            elif s.get(x, y - 1) != base or s.get(x - 1, y) != base: n.g[y][x] = hi
    s.g = n.g
