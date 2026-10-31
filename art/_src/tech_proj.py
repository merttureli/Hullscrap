"""Projectiles and impacts of the racial tech, group b (docs/waves/racial_tech_1.md, "Projectile and impact art per race"):
 Mire: steam jets, water bursts.  Sporeling: spore clouds, rot pods.  Gauntling: electric arcs, scrap pellets.  Prismatic: refracted beams, split shards.  Grundl: heavy slugs, harpoon chains.
One `art/projectiles/<weapon id>.png` (+ json + `_glow`) and one `<weapon id>_impact.png` (+ json + `_glow`) per weapon. Hard pixels use the base palette only (the projectile validator's palette); glow layers are palette hues with alpha.
Bolts face UP (head at the top); `tile: y` sprites (beams) repeat along y."""
import os, math
from px_structure import *

ART = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PROJ = ART + '/projectiles'
BANDS = ((1.4, 100), (2.8, 52), (4.2, 22))

def D(s, cx, cy, r, c):
    for y in range(int(cy - r - 1), int(cy + r + 2)):
        for x in range(int(cx - r - 1), int(cx + r + 2)):
            if (x + .5 - cx) ** 2 + (y + .5 - cy) ** 2 <= r * r: s.put(x, y, c)

def pts(s, lst, c):
    for (x, y) in lst: s.put(x, y, c)

def ln(s, x0, y0, x1, y1, c):
    n = max(abs(x1 - x0), abs(y1 - y0), 1)
    for t in range(n + 1): s.put(x0 + round((x1 - x0) * t / n), y0 + round((y1 - y0) * t / n), c)

def kinks(x0, y0, x1, y1, n, amp, seed=0):
    out = [(x0, y0)]
    dx, dy = x1 - x0, y1 - y0; L = max(1.0, math.hypot(dx, dy)); nx, ny = -dy / L, dx / L
    for k in range(1, n):
        t = k / n; o = amp * (1 if (k + seed) % 2 else -1)
        out.append((int(round(x0 + dx * t + nx * o)), int(round(y0 + dy * t + ny * o))))
    out.append((x1, y1)); return out

def poly_ln(s, p, c):
    for a, b in zip(p, p[1:]): ln(s, a[0], a[1], b[0], b[1], c)

# ------------------------------------------------------------------ writers
def _glow_tile_y(spr, pad, bands, src, col):
    st = Spr(spr.w, spr.h * 3)
    for k in range(3): st.stamp(0, k * spr.h, spr.rows())
    g = halo(st, spr.w + 2 * pad, spr.h * 3, pad, 0, bands=bands, src=src, col=col)
    o = Rgba(spr.w + 2 * pad, spr.h)
    for y in range(spr.h):
        for x in range(spr.w + 2 * pad): o.p[y][x] = list(g.p[spr.h + y][x])
    return o

def _glow_file(name, glows):
    gs = strip_rgba(glows)
    save_png('%s/%s.png' % (PROJ, name), gs.w, gs.h, gs.bytes())

def emit_impact(id_, frames, fps, src, col=None, bands=((1.8, 95), (3.4, 48), (4.8, 20)), notes=''):
    W, H = frames[0].w, frames[0].h
    save_spr(strip(frames), '%s/%s_impact.png' % (PROJ, id_))
    pad = 4
    _glow_file(id_ + '_impact_glow', [halo(f, W + 2 * pad, H + 2 * pad, pad, pad, bands=bands, src=src, col=col) for f in frames])
    gl = {'image': id_ + '_impact_glow.png', 'frame': [W + 2 * pad, H + 2 * pad], 'offset': [-pad, -pad], 'anims': {'play': [0, len(frames), fps]}, 'blend': 'add (preferred) or alpha-over'}
    anims = {'play': [0, len(frames), fps]}
    save_json('%s/%s_impact.json' % (PROJ, id_), {'frame': [W, H], 'anims': anims, 'mode': 'once', 'anchors': {'center': [W // 2, H // 2]}, 'glow': gl, 'notes': notes})
    return {'image': id_ + '_impact.png', 'frame': [W, H], 'anims': anims, 'anchor': [W // 2, H // 2], 'glow': gl}

def emit_bolt(id_, frames, fps, head, tail, notes, src, col=None, bands=BANDS, impact=None):
    W, H = frames[0].w, frames[0].h
    save_spr(strip(frames), '%s/%s.png' % (PROJ, id_))
    pad = 4
    _glow_file(id_ + '_glow', [halo(f, W + 2 * pad, H + 2 * pad, pad, pad, bands=bands, src=src, col=col) for f in frames])
    J = {'frame': [W, H], 'orientation': 'up', 'anims': {'fly': [0, len(frames), fps]}, 'anchors': {'head': head, 'tail': tail},
         'glow': {'image': id_ + '_glow.png', 'frame': [W + 2 * pad, H + 2 * pad], 'offset': [-pad, -pad], 'anims': {'fly': [0, len(frames), fps]}, 'blend': 'add (preferred) or alpha-over'}, 'notes': notes}
    if impact: J['impact'] = impact
    save_json('%s/%s.json' % (PROJ, id_), J)

def emit_tile(id_, frames, fps, notes, src, col=None, bands=((1.3, 100), (2.6, 52), (4.0, 22)), pad=4, impact=None, anim='flicker'):
    W, H = frames[0].w, frames[0].h
    save_spr(strip(frames), '%s/%s.png' % (PROJ, id_))
    _glow_file(id_ + '_glow', [_glow_tile_y(f, pad, bands, src, col) for f in frames])
    J = {'frame': [W, H], 'length': H, 'width': W, 'orientation': 'up: travels towards the top of the image at rotation 0', 'tile': 'y', 'anims': {anim: [0, len(frames), fps]},
         'anchors': {'head': [W // 2, 0], 'tail': [W // 2, H - 1]},
         'glow': {'image': id_ + '_glow.png', 'frame': [W + 2 * pad, H], 'offset': [-pad, 0], 'anims': {anim: [0, len(frames), fps]}, 'blend': 'add (preferred) or alpha-over', 'tile': 'y'}, 'notes': notes}
    if impact: J['impact'] = impact
    save_json('%s/%s.json' % (PROJ, id_), J)

def burst(n, size, cols, spokes, grow, specks=None, core_r=(5, 3, 1, 0)):
    """generic impact burst: a core disc shrinking, `spokes` rays growing, and specks (c) flying outwards; cols = (core, mid, edge, speck)."""
    out = []
    for i in range(n):
        s = Spr(size, size); c = size // 2
        r = core_r[min(i, len(core_r) - 1)]
        if r: D(s, c, c, r + 1, cols[2]); D(s, c, c, r, cols[1]); D(s, c, c, max(0, r - 2), cols[0]) if r > 2 else s.put(c, c, cols[0])
        for k in range(spokes):
            a = 2 * math.pi * k / spokes + 0.3; d0, d1 = 2 + i * grow, 4 + i * grow * 1.6 + 2
            ln(s, int(round(c + math.cos(a) * d0)), int(round(c + math.sin(a) * d0)), int(round(c + math.cos(a) * d1)), int(round(c + math.sin(a) * d1)), cols[2 if i > 1 else 1])
            s.put(int(round(c + math.cos(a) * (d1 + 1))), int(round(c + math.sin(a) * (d1 + 1))), cols[3])
        out.append(s)
    return out

# ============================================================ MIRE
def steam_lance():
    W = [4, 6, 6, 4, 4, 6, 8, 6, 4, 4, 6, 6, 4, 4, 4, 4]
    out = []
    for f in range(3):
        s = Spr(8, 16)
        for y in range(16):
            w = W[(y + f * 5) % 16]; x0 = 4 - w // 2
            s.hline(x0, y, w, 'M'); s.hline(x0 + 1, y, w - 2, 'L')
            if w >= 6: s.hline(x0 + 2, y, w - 4, 'H')
            s.put(3, y, 'H'); s.put(4, y, 'H')
            if w == 8 and f % 2 == 0: s.put(x0, y, 'c'); s.put(x0 + 7, y, 'c')
        for (x, y) in (((1, (3 + f * 5) % 16), (6, (9 + f * 5) % 16))): s.put(x, y, 'c')
        out.append(s)
    return out

def mist_bolt():
    out = []
    for f in range(4):
        s = Spr(10, 12)
        D(s, 5, 4, 3.6, 'M'); D(s, 5, 4, 2.6, 'H'); s.put(4, 3, 'H')
        for k, (dx, dy) in enumerate(((-3, 3), (3, 2), (-2, 6), (2, 7), (0, 9), (-4, 8), (4, 5))):
            if (k + f) % 4 != 3: s.put(5 + dx, dy + (f % 2), 'c' if k % 2 else 'H')
        for (dx, dy) in ((-3, 1), (3, 0), (0, -1)): s.put(5 + dx, 3 + dy, 'c')
        out.append(s)
    return out

def bog_bolt():
    out = []
    for f in range(4):
        s = Spr(8, 12); w = (3.4, 3.0, 3.4, 3.8)[f]; h = (3.8, 4.2, 3.8, 3.4)[f]
        for y in range(12):
            for x in range(8):
                if ((x + .5 - 4) / w) ** 2 + ((y + .5 - 4.5) / h) ** 2 <= 1: s.put(x, y, 'g')
        pts(s, [(3, 2), (4, 2)], 'H'); pts(s, [(2, 3)], 'H')
        for (x, y) in ((2, 6), (5, 6), (3, 7)): s.put(x, y, 'D')
        for k, (x, y) in enumerate(((3, 9), (4, 11), (5, 8))): s.put(x, y + (f + k) % 2, 'g')
        s.put(4 + (f % 2), 10, 'y')
        out.append(s)
    return out

def water_impact():
    """a splash of slime / water: a flat blob and droplets flying outward; used for the bog (green) and mist (cyan) alike through its colour argument."""
    pass

def splat(cols, n=4, size=16):
    out = []
    for i in range(n):
        s = Spr(size, size); c = size // 2
        rx = (3, 5, 6, 6)[i]; ry = (3, 3, 2, 1)[i]
        for y in range(size):
            for x in range(size):
                if ((x + .5 - c) / rx) ** 2 + ((y + .5 - c) / ry) ** 2 <= 1: s.put(x, y, cols[0])
        if i < 3: pts(s, [(c - 2, c - 1), (c - 1, c - 1)], cols[1])
        for k in range(6):
            a = math.pi * (0.1 + 0.16 * k) + 0.2; d = 4 + i * 2 + (k % 2) * 2
            s.put(int(round(c + math.cos(a) * d)), int(round(c - math.sin(a) * d * (0.8 if k % 2 else 1.1))), cols[2] if i < 3 else cols[0])
        out.append(s)
    return out

def frost_impact():
    out = []
    for i in range(4):
        s = Spr(16, 16); c = 8
        r = (2, 4, 5, 6)[i]
        for a in range(0, 360, 45):
            x1 = c + int(round(math.cos(math.radians(a)) * r)); y1 = c + int(round(math.sin(math.radians(a)) * r))
            ln(s, c, c, x1, y1, 'c' if a % 90 == 0 else 'b')
            if i > 1 and a % 90 == 0:
                for sgn in (-1, 1):
                    mx, my = c + int(round(math.cos(math.radians(a)) * (r - 2))), c + int(round(math.sin(math.radians(a)) * (r - 2)))
                    s.put(mx + int(round(math.cos(math.radians(a + 90 * sgn)))), my + int(round(math.sin(math.radians(a + 90 * sgn)))), 'H')
        D(s, c, c, max(1, 2 - i // 2), 'H')
        for k in range(4 + i): s.put(c + int(round(math.cos(k * 1.9) * (r + 2))), c + int(round(math.sin(k * 1.9) * (r + 2))), 'c' if i < 3 else 'b')
        out.append(s)
    return out

def steam_impact():
    out = []
    for i in range(4):
        s = Spr(16, 16); c = 8
        for k in range(7):
            a = 2 * math.pi * k / 7; d = 2 + i * 1.8
            D(s, c + math.cos(a) * d, c + math.sin(a) * d, max(1, 3 - i * 0.6), 'M' if i > 1 else 'L')
        D(s, c, c, max(1, 3 - i * 0.7), 'H')
        for k in range(5): s.put(c + int(round(math.cos(k * 2.2 + 0.5) * (5 + i * 1.5))), c + int(round(math.sin(k * 2.2 + 0.5) * (5 + i * 1.5))), 'c')
        out.append(s)
    return out

# ============================================================ SPORELING
def spore_bolt():
    out = []
    for f in range(4):
        s = Spr(10, 12)
        D(s, 5, 4, 3.4, 'g'); D(s, 5, 4, 2.2, 'y'); s.put(4, 3, 'H')
        for (x, y) in ((2, 1), (8, 2), (1, 5), (8, 5), (5, 0)): s.put(x, y + (f % 2), 'g')
        for k, (x, y) in enumerate(((3, 8), (6, 9), (4, 11), (7, 7), (2, 10))):
            if (k + f) % 5 != 4: s.put(x, y, 'g' if k % 2 else 'y')
        out.append(s)
    return out

def spore_impact():
    out = []
    for i in range(4):
        s = Spr(16, 16); c = 8
        for k in range(8):
            a = 2 * math.pi * k / 8 + 0.4; d = 1.5 + i * 1.6
            D(s, c + math.cos(a) * d, c + math.sin(a) * d - i * 0.6, max(1, 3.2 - i * 0.6), 'g' if k % 2 else 'y')
        D(s, c, c - i * 0.5, max(1, 3 - i * 0.7), 'y'); s.put(c - 1, c - 1 - i // 2, 'H')
        for k in range(4): s.put(c + int(round(math.cos(k * 2.4) * (4 + i * 1.8))), c - int(round(2 + i * 1.5 + k)), 'g')
        out.append(s)
    return out

def rot_pod():
    out = []
    for f in range(3):
        s = Spr(8, 16)
        D(s, 4, 4, 3.6, 'q'); D(s, 4, 4, 2.8, 'Q'); pts(s, [(3, 2), (4, 2), (2, 3)], 'H'); pts(s, [(5, 5), (3, 6)], 'p'); pts(s, [(5, 3)], 'g')
        pts(s, [(3, 7), (4, 7), (5, 7)], 'n')
        for k, (x, y) in enumerate(((3, 9), (5, 10), (4, 12), (2, 11), (6, 13), (4, 15))):
            if (k + f) % 4 != 3: s.put(x, y, 'g' if k % 2 else 'y')
        out.append(s)
    return out

def rot_impact():
    out = []
    for i in range(4):
        s = Spr(16, 16); c = 8
        rx, ry = (3, 5, 6, 5)[i], (3, 4, 3, 2)[i]
        for y in range(16):
            for x in range(16):
                if ((x + .5 - c) / rx) ** 2 + ((y + .5 - c) / ry) ** 2 <= 1: s.put(x, y, 'q' if i < 3 else 'n')
        pts(s, [(c - 2, c - 1), (c - 1, c - 2)], 'Q'); pts(s, [(c + 2, c)], 'p')
        for k in range(8):
            a = 2 * math.pi * k / 8 + 0.2; d = 3 + i * 1.8
            s.put(int(round(c + math.cos(a) * d)), int(round(c + math.sin(a) * d)), 'g' if k % 2 else ('p' if i < 3 else 'y'))
        out.append(s)
    return out

def pollen_bolt():
    out = []
    for f in range(4):
        s = Spr(6, 8)
        for k, (x, y) in enumerate(((2, 1), (3, 2), (1, 3), (4, 3), (2, 4), (3, 5), (2, 7), (4, 6))):
            if (k + f) % 5 != 4: s.put(x, y, 'y' if k % 3 else 'H')
        s.put(2 + f % 2, 2, 'a'); s.put(3, 4 + f % 2, 'a')
        out.append(s)
    return out

def pollen_impact():
    out = []
    for i in range(3):
        s = Spr(16, 16); c = 8
        for k in range(10):
            a = 2 * math.pi * k / 10 + 0.3; d = 1 + i * 2.4 + (k % 3)
            s.put(int(round(c + math.cos(a) * d)), int(round(c + math.sin(a) * d - i)), 'y' if k % 2 else 'a')
        D(s, c, c, max(1, 3 - i), 'H' if i == 0 else 'y')
        for k in range(4): s.put(c + (k - 2) * 2, c - 3 - i * 2 - k % 2, 'H')
        out.append(s)
    return out

# ============================================================ GAUNTLING
def arc_bolt():
    out = []
    for f in range(4):
        s = Spr(10, 14)
        D(s, 5, 6, 2.6, 'W'); D(s, 5, 6, 1.8, 'S'); pts(s, [(4, 5), (5, 5)], 'M'); s.put(4, 4, 'L')
        for k in range(4):
            a = f * 0.9 + k * 1.57; p = kinks(5, 6, 5 + int(round(math.cos(a) * 5)), 6 + int(round(math.sin(a) * 5)), 3, 1, k + f)
            poly_ln(s, p, 'c' if k % 2 else 'H')
        pts(s, [(4, 10), (5, 11), (4, 12), (5, 13)][: 2 + f % 3], 'b')
        out.append(s)
    return out

def arc_impact():
    out = []
    for i in range(4):
        s = Spr(16, 16); c = 8
        for k in range(6):
            a = 2 * math.pi * k / 6 + 0.5; L = 3 + i * 1.5 + (k % 2) * 2
            poly_ln(s, kinks(c, c, int(round(c + math.cos(a) * L)), int(round(c + math.sin(a) * L)), 3, 1, k), 'c' if i < 3 else 'b')
        D(s, c, c, max(1, 3 - i), 'H')
        for k in range(5): s.put(c + int(round(math.cos(k * 1.7) * (3 + i * 1.5))), c + int(round(math.sin(k * 1.7) * (3 + i * 1.5))), 'o' if k % 2 else 'y')
        out.append(s)
    return out

def scrap_bolt():
    out = []
    for f in range(4):
        s = Spr(12, 10)
        for k, (x, y, c) in enumerate(((5, 0, 'M'), (2, 3, 'S'), (8, 3, 'u'), (4, 5, 'L'), (7, 6, 'Q'), (5, 8, 'S'))):
            xx, yy = x + (f + k) % 2 - (1 if k % 2 else 0), y
            s.put(xx, yy, c); s.put(xx + 1, yy, c) if k % 2 == 0 else s.put(xx, yy + 1, 'W')
        for (x, y) in ((1, 5), (10, 5), (4, 9), (7, 9)): s.put(x, y, 'o')
        out.append(s)
    return out

def scrap_impact():
    out = []
    for i in range(3):
        s = Spr(16, 16); c = 8
        for k in range(8):
            a = 2 * math.pi * k / 8 + 0.2; d = 2 + i * 2.2
            s.put(int(round(c + math.cos(a) * d)), int(round(c + math.sin(a) * d)), 'y' if k % 2 else 'o')
            if k % 2 == 0: s.put(int(round(c + math.cos(a) * (d + 2))), int(round(c + math.sin(a) * (d + 2))), 'M' if k % 4 == 0 else 'u')
        D(s, c, c, max(1, 2 - i // 2), 'H')
        out.append(s)
    return out

def tesla_bolt():
    out = []
    for f in range(3):
        s = Spr(8, 16); per = (8, 4, 8)[f]; ph = f * 3
        offs = [(0, 1, 2, 1, 0, -1, -2, -1), (0, 2, 0, -2, 0, 2, 0, -2), (0, -1, -2, -1, 0, 1, 2, 1)][f]
        for y in range(16):
            x = 4 + offs[(y + ph) % 8] // (1 if f != 1 else 1)
            s.put(x - 1, y, 'b'); s.put(x + 1, y, 'b'); s.put(x, y, 'c'); s.put(x if y % 2 else x - 1 + 0, y, 'H') if y % 3 == 0 else None
            s.put(x, y, 'H' if y % 3 != 1 else 'c')
        for (x, y) in (((0, (2 + f * 5) % 16), (7, (10 + f * 5) % 16))): s.put(x, y, 'c')
        out.append(s)
    return out

# ============================================================ PRISMATIC
def prism_beam():
    out = []
    for f in range(3):
        s = Spr(8, 16)
        for y in range(16):
            s.put(3, y, 'H'); s.put(4, y, 'H'); s.put(2, y, 'c'); s.put(5, y, 'c')
            s.put(1, y, 'm' if (y + f) % 3 else 'b'); s.put(6, y, 'y' if (y + f) % 4 == 0 else 'b')
            if (y + f * 2) % 5 == 0: s.put(0, y, 'm'); s.put(7, y, 'c')
        for y in ((1 + f * 5) % 16, (8 + f * 5) % 16): pts(s, [(2, y), (5, y)], 'H'); s.put(1, y, 'c'); s.put(6, y, 'c')
        out.append(s)
    return out

def prism_impact():
    out = []
    for i in range(3):
        s = Spr(16, 16); c = 8
        cols = ('m', 'c', 'y', 'b', 'p', 'c')
        for k in range(6):
            a = 2 * math.pi * k / 6 + 0.2 * i; L = 3 + i * 2 + (k % 2)
            ln(s, int(round(c + math.cos(a) * 2)), int(round(c + math.sin(a) * 2)), int(round(c + math.cos(a) * L)), int(round(c + math.sin(a) * L)), cols[k])
        D(s, c, c, max(1, 3 - i), 'H')
        out.append(s)
    return out

def shard_bolt():
    out = []
    for f in range(4):
        s = Spr(6, 14)
        for y, w in enumerate((1, 2, 4, 4, 4, 4, 2, 1)):
            x0 = 3 - w // 2
            s.hline(x0, y, w, 'c')
            if w > 1: s.put(x0 + w - 1, y, 'b')
        s.put(2, 3, 'H'); s.put(2, 4, 'H'); s.put(3, 2, 'H')
        s.put(1 + (f % 2) * 3, 3 + f % 3, 'm')
        for k in range(3): s.put(2 + (k + f) % 2, 9 + k * 2, 'b' if k % 2 else 'c')
        out.append(s)
    return out

def shard_impact():
    out = []
    for i in range(4):
        s = Spr(16, 16); c = 8
        for k, (ang, col) in enumerate(((-90, 'c'), (30, 'm'), (150, 'y'))):
            a = math.radians(ang); d = 1 + i * 2.2
            x, y = c + math.cos(a) * d, c + math.sin(a) * d
            for (dx, dy) in ((0, 0), (1, 0), (0, 1), (-1, 0), (0, -1)) if i < 3 else ((0, 0),):
                s.put(int(round(x)) + dx, int(round(y)) + dy, col)
            s.put(int(round(x)), int(round(y)), 'H')
        if i == 0: D(s, c, c, 3, 'H')
        out.append(s)
    return out

def glimmer_bolt():
    out = []
    for f in range(4):
        s = Spr(5, 10)
        pts(s, [(2, 0), (2, 1), (1, 2), (2, 2), (3, 2), (1, 3), (2, 3), (3, 3), (2, 4), (2, 5)], 'c'); pts(s, [(2, 1), (2, 2), (2, 3)], 'H')
        s.put(2, 6 + f % 2, 'b'); s.put(2, 8 - f % 2, 'b'); s.put(f % 2 * 2 + 1 if f % 2 else 0, 2 + f, 'm')
        out.append(s)
    return out

def sparkle_impact():
    out = []
    for i in range(3):
        s = Spr(16, 16); c = 8
        r = (3, 6, 4)[i]
        for d in range(1, r + 1):
            for (dx, dy) in ((d, 0), (-d, 0), (0, d), (0, -d)): s.put(c + dx, c + dy, 'c' if d > 1 else 'H')
        if i == 1:
            for d in (2, 3): [s.put(c + dx * d, c + dy * d, 'm') for dx, dy in ((1, 1), (-1, 1), (1, -1), (-1, -1))]
        s.put(c, c, 'H'); D(s, c, c, 1, 'H') if i < 2 else None
        out.append(s)
    return out

# ============================================================ GRUNDL
SLUG = art_strict("""
...KK...
..KMMK..
.KLMSSK.
.KLMSSK.
KuuuuuuK
KaaaaaaK
KuuuuuuK
KLMSSWEK
KLMSSWEK
.KSSWEK.
.KWWEEK.
..KKKK..
""", 8, 12, 'slug')
def slug_bolt():
    out = []
    for f in range(3):
        s = Spr(10, 16)
        s.stamp(1, 0, SLUG)
        for k, (x, y, c) in enumerate(((3, 12, 'D'), (6, 13, 'E'), (4, 14, 'D'), (5, 12, 'o'), (3, 15, 'W'), (6, 15, 'D'))):
            if (k + f) % 3 != 2: s.put(x + f % 2 - (1 if k % 2 else 0), y, c)
        out.append(s)
    return out

def slug_impact():
    out = []
    for i in range(5):
        s = Spr(24, 24); c = 12
        r = (4, 7, 9, 8, 6)[i]
        if i < 4:
            D(s, c, c, r, 'r' if i > 1 else 'o'); D(s, c, c, r - 2, 'o' if i > 1 else 'y'); D(s, c, c, max(1, r - 5), 'H' if i < 3 else 'y')
        if i >= 1:
            for k in range(12):
                a = 2 * math.pi * k / 12 + 0.2; d = 5 + i * 2.2
                col = ('M', 'u', 'S')[k % 3] if i < 4 else 'W'
                s.put(int(round(c + math.cos(a) * d)), int(round(c + math.sin(a) * d)), col); s.put(int(round(c + math.cos(a) * d)) + 1, int(round(c + math.sin(a) * d)), col)
        if i >= 2:
            for a in range(0, 360, 20):
                d = 6 + i * 1.8; s.put(int(round(c + math.cos(math.radians(a)) * d)), int(round(c + math.sin(math.radians(a)) * d)), 'W' if i < 4 else 'E')
        out.append(s)
    return out

HARPOON_HEAD = art_strict("""
...KK...
..KMMK..
.KLMSSK.
KLLMSSWK
.KLMSWK.
KK.KSK.K
K.KKSKK.K
..KKWK..
...KWK..
""", 8, 9, 'harpoon') if False else None
def harpoon_bolt():
    out = []
    for f in range(2):
        s = Spr(8, 18)
        rows = ("...KK...", "..KLMK..", "..KLMSK.", ".KLLMSWK", "KKLMSWKK", "K.KMSWK.K", "..KKSKK..", "...KWK...")
        for j, r in enumerate(rows):
            for i, ch in enumerate(r):
                if ch != '.': s.put(i, j, ch)
        for k in range(10):                                                              # the chain trailing back: links alternate, swaying a pixel
            x = 3 + (1 if (k + f) % 4 in (1, 2) else 0)
            if k % 2 == 0: s.put(x, 8 + k, 'M'); s.put(x + 1, 8 + k, 'W')
            else: s.put(x, 8 + k, 'S')
        out.append(s)
    return out

def chain_tile():
    out = []
    for f in range(2):
        s = Spr(6, 16)
        for k in range(8):
            y = k * 2 + f
            if k % 2 == 0:
                for yy in range(y, y + 3): s.put(1, yy % 16, 'M'); s.put(4, yy % 16, 'W')
                s.put(2, y % 16, 'L'); s.put(3, y % 16, 'M'); s.put(2, (y + 2) % 16, 'W'); s.put(3, (y + 2) % 16, 'E')
            else:
                s.put(2, y % 16, 'S'); s.put(3, y % 16, 'W'); s.put(2, (y + 1) % 16, 'S'); s.put(3, (y + 1) % 16, 'E')
        out.append(s)
    return out

def clang_impact():
    out = []
    for i in range(4):
        s = Spr(16, 16); c = 8
        r = (2, 4, 6, 7)[i]
        if i < 3:
            for a in range(0, 360, 30): s.put(c + int(round(math.cos(math.radians(a)) * r)), c + int(round(math.sin(math.radians(a)) * r)), 'H' if i == 0 else ('L' if i == 1 else 'M'))
        for k in range(8):
            a = 2 * math.pi * k / 8 + 0.3; d = 2 + i * 1.8
            s.put(int(round(c + math.cos(a) * d)), int(round(c + math.sin(a) * d)), 'y' if k % 2 else 'o')
            if k % 3 == 0: s.put(int(round(c + math.cos(a) * (d + 2))), int(round(c + math.sin(a) * (d + 2))), 'M')
        D(s, c, c, max(1, 3 - i), 'H') if i < 3 else None
        out.append(s)
    return out

def flak_bolt():
    out = []
    for f in range(2):
        s = Spr(8, 10)
        for y, (x0, x1) in enumerate(((3, 4), (2, 5), (1, 6), (1, 6), (1, 6), (1, 6), (2, 5))):
            s.hline(x0, y, x1 - x0 + 1, 'S'); s.put(x0, y, 'M'); s.put(x1, y, 'W')
        s.hline(1, 3, 6, 'a'); s.hline(1, 4, 6, 'u'); s.put(2, 1, 'L'); s.put(2, 2, 'L')
        s.put(3, 7, 'o' if f else 'y'); s.put(4, 7, 'y' if f else 'o'); s.put(3, 8, 'r'); s.put(4, 8 + f, 'o'); s.put(3 + f * 2 - 1, 9, 'r')
        out.append(s)
    return out

def flak_impact():
    out = []
    for i in range(4):
        s = Spr(20, 20); c = 10
        r = (3, 6, 7, 6)[i]
        D(s, c, c, r, 'E' if i > 1 else 'W'); D(s, c, c, max(1, r - 2), 'o' if i < 3 else 'W'); D(s, c, c, max(1, r - 4), 'y' if i < 2 else 'D') if r > 2 else None
        if i == 0: D(s, c, c, 2, 'H')
        for k in range(10):
            a = 2 * math.pi * k / 10 + 0.15; d = 3 + i * 2
            s.put(int(round(c + math.cos(a) * d)), int(round(c + math.sin(a) * d)), 'M' if k % 2 else 'o'); s.put(int(round(c + math.cos(a) * (d + 2))), int(round(c + math.sin(a) * (d + 2))), 'S')
        out.append(s)
    return out

# ============================================================ export
def export_all():
    I = {}
    # ---- Mire
    imp = emit_impact('mire_steam_lance', steam_impact(), 14, 'LHc', 'c', notes='Mire Steam Lance hit: a ring of white steam puffs spreading and thinning, cyan droplets flying out (4 frames).')
    emit_tile('mire_steam_lance', steam_lance(), 12, 'Mire Steam Lance jet (a beam, tile along y): a white-hot core in a puffing column of steam that swells and thins along its length, cyan droplets in the swells (3 flicker frames). Repeat along y to the target.', 'LHc', 'c', impact=imp)
    imp = emit_impact('mire_bog_mortar', splat(('g', 'H', 'y')), 12, 'gy', 'g', notes='Mire Bog Mortar hit: a green slime splat that flattens and flings drops, acid-yellow flecks (4 frames).')
    emit_bolt('mire_bog_mortar', bog_bolt(), 12, [4, 4], [4, 11], 'Mire Bog Mortar glob: a green blob of bog slime that wobbles as it flies, dripping (4 frames). Head anchor is the glob centre.', 'g', 'g', impact=imp)
    imp = emit_impact('mire_mist_projector', frost_impact(), 14, 'cbH', 'c', notes='Mire Mist Projector hit: a frost starburst growing from a white point, cyan flakes (4 frames).')
    emit_bolt('mire_mist_projector', mist_bolt(), 12, [5, 4], [5, 10], 'Mire Mist Projector cloud: a puff of white mist trailing cyan droplets (4 frames). Head anchor is the cloud centre.', 'Hc', 'c', impact=imp)
    # ---- Sporeling
    imp = emit_impact('sporeling_spore_cannon', spore_impact(), 10, 'gy', 'g', notes='Sporeling Spore Cannon hit: a cloud of green and yellow spores puffing up and drifting (4 frames).')
    emit_bolt('sporeling_spore_cannon', spore_bolt(), 12, [5, 4], [5, 11], 'Sporeling Spore Cannon shot: a ball of green-yellow spores trailing loose spores (4 frames). Head anchor is the cloud centre.', 'gy', 'g', impact=imp)
    imp = emit_impact('sporeling_rot_pod', rot_impact(), 10, 'gp', 'g', notes='Sporeling Rot Pod hit: the pod bursts into a brown splat and green and pink spores spread out of it (4 frames).')
    emit_bolt('sporeling_rot_pod', rot_pod(), 12, [4, 4], [4, 15], 'Sporeling Rot Pod: a brown, pink-spotted pod with a green sprout trailing a thread of spores (3 frames). Head anchor is the pod centre.', 'gy', 'g', impact=imp)
    imp = emit_impact('sporeling_pollen_turret', pollen_impact(), 10, 'yaH', 'y', notes='Sporeling Pollen Turret hit: a puff of yellow pollen drifting up with pale motes (3 frames).')
    emit_bolt('sporeling_pollen_turret', pollen_bolt(), 12, [3, 3], [3, 7], 'Sporeling Pollen Turret shot: a loose bunch of yellow pollen grains that sparkle (4 frames).', 'yH', 'y', impact=imp)
    # ---- Gauntling
    imp = emit_impact('gauntling_arc_hammer', arc_impact(), 14, 'cHoy', 'c', notes='Gauntling Arc Hammer hit: a white flash with cyan arcs forking out and orange kinetic sparks (4 frames).')
    emit_bolt('gauntling_arc_hammer', arc_bolt(), 14, [5, 6], [5, 13], 'Gauntling Arc Hammer shot (ion plus kinetic): a dull steel slug wrapped in crackling cyan arcs that jump to new places every frame (4 frames).', 'cb', 'c', impact=imp)
    imp = emit_impact('gauntling_scrap_shotgun', scrap_impact(), 16, 'oy', 'o', notes='Gauntling Scrap Shotgun hit: orange sparks and bits of scrap ricocheting off (3 frames).')
    emit_bolt('gauntling_scrap_shotgun', scrap_bolt(), 14, [6, 3], [6, 9], 'Gauntling Scrap Shotgun load: a spray of six mismatched scrap pellets (steel, rust) tumbling with a few orange sparks (4 frames). Head anchor is the middle of the spread.', 'o', 'o', impact=imp)
    imp = emit_impact('gauntling_tesla_picket', arc_impact(), 14, 'cHb', 'c', notes='Gauntling Tesla Picket hit: an arc flare, cyan forks leaving a white point (4 frames).')
    emit_tile('gauntling_tesla_picket', tesla_bolt(), 14, 'Gauntling Tesla Picket arc (a beam, tile along y): a jagged cyan-white lightning thread with a blue halo that kinks differently each frame (3 frames; the kink pattern repeats every 8 rows so the tiles join).', 'cb', 'c', impact=imp)
    # ---- Prismatic
    imp = emit_impact('prismatic_prism_lens', prism_impact(), 14, 'cmyH', None, notes='Prismatic Prism Lens hit: a white point with six rays in cyan, magenta, yellow and blue, like light through a prism (3 frames).')
    emit_tile('prismatic_prism_lens', prism_beam(), 12, 'Prismatic Prism Lens beam (tile along y): a white core between cyan edges and a magenta and blue fringe that shimmers like split light, a bright bead running along it (3 flicker frames).', 'cmb', 'c', impact=imp)
    imp = emit_impact('prismatic_refractor', shard_impact(), 14, 'cmy', 'c', notes='Prismatic Refractor hit: the shard splits into three (cyan, magenta, yellow) that fly apart (4 frames).')
    emit_bolt('prismatic_refractor', shard_bolt(), 14, [3, 3], [3, 13], 'Prismatic Refractor shard: a cyan crystal shard with a white ridge and a magenta glint that moves, a thin trail (4 frames). Splits into three on a shield.', 'cH', 'c', impact=imp)
    imp = emit_impact('prismatic_glimmer_turret', sparkle_impact(), 14, 'cH', 'c', notes='Prismatic Glimmer Turret hit: a twinkling cross of light (3 frames).')
    emit_bolt('prismatic_glimmer_turret', glimmer_bolt(), 16, [2, 2], [2, 9], 'Prismatic Glimmer Turret dart: a small bright crystal dart with a white core and a twinkling magenta spark (4 frames).', 'cH', 'c', impact=imp)
    # ---- Grundl
    imp = emit_impact('grundl_slug_mortar', slug_impact(), 12, 'oyr', 'o', bands=((2.0, 100), (4.0, 55), (6.5, 24)), notes='Grundl Slug Mortar hit: a heavy fireball with a ring of dust and flying chunks of steel and rust (5 frames, 24x24).')
    emit_bolt('grundl_slug_mortar', slug_bolt(), 12, [5, 5], [5, 15], 'Grundl Slug Mortar slug: a fat steel shell with a rust band and an amber stripe, a tail of dark smoke and one ember (3 frames).', 'o', 'o', impact=imp)
    imp = emit_impact('grundl_grapple_harpoon', clang_impact(), 14, 'yoH', 'y', notes='Grundl Grapple Harpoon hit: a metal clang, a pale ring and orange sparks with flying steel chips (4 frames).')
    emit_bolt('grundl_grapple_harpoon', harpoon_bolt(), 12, [4, 3], [4, 17], 'Grundl Grapple Harpoon head: a barbed steel harpoon with its chain trailing behind (2 frames, the chain sways). The tether to the ship is `grundl_grapple_harpoon_chain.png`.', 'L', 'c', bands=((1.2, 60), (2.4, 28)), impact=imp)
    emit_tile('grundl_grapple_harpoon_chain', chain_tile(), 6, 'Grundl harpoon chain (tile along y): a chain of alternating flat and edge-on links, drawn from the ship (tail) to the harpoon (head); the 2 frames shift the links by a pixel for a clank. Repeat along y.', 'L', 'c', bands=((1.2, 40),), anim='clank')
    imp = emit_impact('grundl_barge_flak', flak_impact(), 14, 'oyH', 'o', notes='Grundl Barge Flak burst: a dark smoke puff with an orange flash and steel shards flying out (4 frames, 20x20).')
    emit_bolt('grundl_barge_flak', flak_bolt(), 12, [4, 3], [4, 9], 'Grundl Barge Flak shell: a fat steel shell with an amber band and a ragged orange spark behind it (2 frames).', 'o', 'o', impact=imp)

IDS = ['mire_steam_lance', 'mire_bog_mortar', 'mire_mist_projector', 'sporeling_spore_cannon', 'sporeling_rot_pod', 'sporeling_pollen_turret',
       'gauntling_arc_hammer', 'gauntling_scrap_shotgun', 'gauntling_tesla_picket', 'prismatic_prism_lens', 'prismatic_refractor', 'prismatic_glimmer_turret',
       'grundl_slug_mortar', 'grundl_grapple_harpoon', 'grundl_barge_flak']
if __name__ == '__main__':
    export_all()
