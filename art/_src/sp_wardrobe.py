"""Gear for every rig, made from the rig's own sprites (art/gear/<art id>/<rig>.png + <art id>/gear.json).

The suit is the rig's torso / head / arms / legs silhouettes re-coloured in the item's palette with the item's pattern laid over
(plates, seams, straps, scales, a visor or helmet ring round the head, lit strips). One strip PNG per (item, rig); frames are the rig's
frame size, left to right: body (1), head (one per head frame of the rig, drawn over that head frame), sleeves (6 arm poses, drawn over the arms),
legs (7, drawn over the same legs frame). `gear.json` of the item says which of them an item has and the rig frames.
The hand-made art of the human and gauntling rigs (art/gear/<id>.json) is kept: only the new items are made for those two.
Run: python3 art/_src/sp_wardrobe.py  (writes art/gear/*, and art/gear/_sheet.png, the contact sheet, with --sheet)
numpy + PIL only; no randomness except a fixed seed per (item, rig)."""
import json, os, sys, zlib
import numpy as np
from PIL import Image

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), '..'))
CREW = ROOT + '/crew'
GEAR = ROOT + '/gear'
HAND_RIGS = ('human', 'gauntling')          # these keep the hand-made art of the five old items
OLD = ['combat_vest', 'eva_suit', 'exosuit', 'salamander_suit', 'heat_suit']


def hexc(h):
    h = h.lstrip('#'); return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16), 255)

def pal(main, dark, light, acc, acc2=None, edge=None):
    return dict(mid=hexc(main), lo=hexc(dark), hi=hexc(light), acc=hexc(acc), acc2=hexc(acc2 or acc), edge=hexc(edge or dark))

# ---------------------------------------------------------------- the items: palette + what each part of the body gets
# body: ordered ops; head: style; sleeves/legs: style or None; every op is read by Rig.body()
ITEMS = {
 'combat_vest': dict(pal=pal('#8d96a3', '#474e59', '#b9c1cc', '#e8892a', '#f2c14e'),
     body=[('fill', 0.92), ('bands', 2), ('seamv',), ('belt', 0.74, 'acc'), ('pads', 'plate', 3.4)], head=None, sleeves=None, legs=None),
 'eva_suit': dict(pal=pal('#e6eaee', '#8a939e', '#ffffff', '#6bd34a', '#bfe6ff'),
     body=[('fill', 1.0), ('seamv',), ('belt', 0.68, 'lo'), ('pads', 'round', 3.6), ('back', 'tanks'), ('led', 'acc')], head='bubble', sleeves='full', legs='full'),
 'exosuit': dict(pal=pal('#454c57', '#1d2128', '#7d8796', '#ff8a1e', '#3cf2ff'),
     body=[('fill', 1.0), ('plates', 3), ('seamv',), ('pads', 'plate', 4.4), ('back', 'power'), ('glowline', 'acc', 0.45)], head='helm_visor', sleeves='full', legs='full'),
 'salamander_suit': dict(pal=pal('#c4411f', '#5e1a0c', '#ee7a3c', '#e8c43a', '#ff8a1e'),
     body=[('fill', 1.0), ('pleats',), ('hem', 'acc'), ('pads', 'round', 4.0), ('studs', 'acc2', 3)], head='hood_ember', sleeves='full', legs='full'),
 'heat_suit': dict(pal=pal('#c7ced6', '#6f7a86', '#f0f4f8', '#e8c43a', '#e8892a'),
     body=[('fill', 1.0), ('bands', 1, 'acc'), ('seamv',), ('pads', 'dome', 3.8), ('back', 'fins')], head='visor_gold', sleeves='full', legs='full'),
 'rigger_harness': dict(pal=pal('#c9772a', '#5a3410', '#f2a24a', '#e8c43a', '#d9dde2'),
     body=[('straps', 'mid'), ('belt', 0.72, 'mid'), ('buckles', 'acc'), ('back', 'tools')], head=None, sleeves=None, legs=None),
 'firefighter_coat': dict(pal=pal('#d9b23a', '#8a6a14', '#f2d36a', '#dfe6ee', '#c4411f'),
     body=[('fill', 1.0), ('seamv',), ('stripes', 'acc', 2), ('hem', 'acc'), ('buttons', 'lo'), ('pads', 'round', 3.2)], head='hardhat', sleeves='full', legs='boots'),
 'medic_sash': dict(pal=pal('#f1f4f6', '#9aa5b0', '#ffffff', '#d6362f', '#d6362f'),
     body=[('sash', 'mid'), ('cross', 'acc'), ('belt', 0.76, 'lo'), ('back', 'satchel')], head=None, sleeves=None, legs=None),
 'jump_pack': dict(pal=pal('#7c8591', '#363c45', '#aab3bf', '#ff8a1e', '#ffd36a'),
     body=[('straps', 'lo'), ('belt', 0.7, 'lo'), ('back', 'jets')], head=None, sleeves=None, legs=None),
 'chitin_plate': dict(pal=pal('#8a5a1e', '#3a210a', '#d89a3c', '#f2c14e', '#d89a3c'),
     body=[('fill', 1.0), ('segments', 5), ('seamv',), ('pads', 'spike', 3.6), ('back', 'shell')], head='crest', sleeves='pads', legs=None),
 'spore_mantle': dict(pal=pal('#5f8a3c', '#2c4a1a', '#9acb5a', '#e8ff7a', '#e07ab8'),
     body=[('fill', 1.0, 1), ('fringe',), ('spores', 'acc', 'acc2', 11), ('pads', 'cap', 3.8)], head='spore_head', sleeves=None, legs=None),
 'prism_cloak': dict(pal=pal('#8f7ae0', '#3b2f7a', '#e8f0ff', '#ffffff', '#6ee7ff'),
     body=[('cloak', 2), ('seamv',), ('gem', 'acc')], head='diadem', sleeves=None, legs=None),
 'ballast_rig': dict(pal=pal('#5b6068', '#2a2d33', '#8a9099', '#e8c43a', '#e8892a'),
     body=[('fill', 1.0), ('plates', 2), ('hazard', 'acc'), ('pads', 'plate', 5.0), ('back', 'weights')], head=None, sleeves='pads', legs='boots'),
 'tank_harness': dict(pal=pal('#2f9d8f', '#145149', '#7fe0d0', '#d9f2ee', '#e8892a'),
     body=[('straps', 'mid'), ('belt', 0.7, 'lo'), ('back', 'tank'), ('led', 'acc2')], head='mask', sleeves=None, legs=None),
 'forge_apron': dict(pal=pal('#4a2f22', '#1c0f08', '#7a5238', '#ff6a1a', '#ffb347'),
     body=[('fill', 0.96), ('apron',), ('studs', 'acc', 5), ('pads', 'cap', 3.4)], head=None, sleeves='gauntlet', legs=None),
 'traders_coat': dict(pal=pal('#2e6f73', '#143a3e', '#5fb0b4', '#d4a63a', '#e8dcc0'),
     body=[('fill', 1.0), ('seamv',), ('buttons', 'acc'), ('collar', 'acc2'), ('hem', 'acc')], head=None, sleeves='full', legs='boots'),
 'stone_plates': dict(pal=pal('#8b8f94', '#3e4146', '#c1c5c9', '#6f7a60', '#d9dde2'),
     body=[('fill', 1.0), ('stone',), ('cracks',), ('pads', 'rock', 5.2)], head=None, sleeves='gauntlet', legs=None),
 'scrap_gauntlets': dict(pal=pal('#a0a6ad', '#4d5258', '#d4d9de', '#a85a2a', '#e8892a'),
     body=[('pads', 'scrap', 3.6), ('rivets', 'acc', 5)], head=None, sleeves='gauntlet', legs=None),
 'marine_plate': dict(pal=pal('#5e6b48', '#2c3322', '#8f9d70', '#e8ecee', '#e8c43a'),
     body=[('fill', 0.94), ('plates', 3), ('seamv',), ('stripe', 'acc'), ('pads', 'plate', 4.2), ('belt', 0.78, 'lo')], head='helm_dome', sleeves=None, legs='boots'),
}


# ---------------------------------------------------------------- pixel helpers
def alpha(a): return a[..., 3] > 0

def shift(m, dx, dy):
    out = np.zeros_like(m)
    h, w = m.shape
    ys, yd = (slice(max(dy, 0), h), slice(0, h - max(dy, 0))) if dy >= 0 else (slice(0, h + dy), slice(-dy, h))
    xs, xd = (slice(max(dx, 0), w), slice(0, w - max(dx, 0))) if dx >= 0 else (slice(0, w + dx), slice(-dx, w))
    out[ys, xs] = m[yd, xd]
    return out

def dilate(m, n=1):
    for _ in range(n):
        m = m | shift(m, 1, 0) | shift(m, -1, 0) | shift(m, 0, 1) | shift(m, 0, -1)
    return m

def erode(m, n=1):
    return ~dilate(~m, n)

def edge_of(m):
    return m & ~erode(m, 1)

def disc(shape, cx, cy, r):
    h, w = shape
    y, x = np.mgrid[0:h, 0:w]
    return (x - cx) ** 2 + (y - cy) ** 2 <= r * r

def rect(shape, x0, y0, x1, y1):
    h, w = shape
    y, x = np.mgrid[0:h, 0:w]
    return (x >= x0) & (x <= x1) & (y >= y0) & (y <= y1)

def line(shape, x0, y0, x1, y1, th=0.7):
    h, w = shape
    y, x = np.mgrid[0:h, 0:w]
    dx, dy = x1 - x0, y1 - y0
    L2 = dx * dx + dy * dy or 1.0
    t = np.clip(((x - x0) * dx + (y - y0) * dy) / L2, 0, 1)
    return (x - (x0 + t * dx)) ** 2 + (y - (y0 + t * dy)) ** 2 <= th * th

def components(m):
    """connected components (4-neighbour) of mask m -> list of boolean masks."""
    h, w = m.shape
    seen = np.zeros_like(m); out = []
    for y in range(h):
        for x in range(w):
            if m[y, x] and not seen[y, x]:
                comp = np.zeros_like(m); st = [(x, y)]; seen[y, x] = True
                while st:
                    cx, cy = st.pop(); comp[cy, cx] = True
                    for nx, ny in ((cx + 1, cy), (cx - 1, cy), (cx, cy + 1), (cx, cy - 1)):
                        if 0 <= nx < w and 0 <= ny < h and m[ny, nx] and not seen[ny, nx]:
                            seen[ny, nx] = True; st.append((nx, ny))
                out.append(comp)
    return out

class Canvas:
    def __init__(self, n):
        self.n = n; self.a = np.zeros((n, n, 4), np.uint8)
    def put(self, m, col, a=255):
        c = np.array([col[0], col[1], col[2], a], np.uint8)
        self.a[m] = c
    def mix(self, m, col, k):
        """blend colour col into the pixels of m that already have colour, by k."""
        m = m & alpha(self.a)
        for i in range(3): self.a[..., i][m] = (self.a[..., i][m] * (1 - k) + col[i] * k).astype(np.uint8)
    def shade(self, m, p, light=(-1, -1)):
        """fill m with the item's three-tone ramp: lit on the upper-left, shadowed on the lower-right, an outline of the dark edge."""
        ys, xs = np.nonzero(m)
        if len(xs) == 0: return
        h, w = m.shape
        yy, xx = np.mgrid[0:h, 0:w]
        d = (xx - xs.mean()) * light[0] + (yy - ys.mean()) * light[1]
        span = max(1.0, np.abs(d[m]).max())
        t = d / span
        self.put(m & (t > 0.28), p['hi']); self.put(m & (t <= 0.28) & (t >= -0.28), p['mid']); self.put(m & (t < -0.28), p['lo'])
        mid2 = m & (t < -0.28) & (t >= -0.62)
        self.put(mid2, tuple(int((a + b) / 2) for a, b in zip(p['mid'], p['lo'])) + (255,))
        self.put(edge_of(m) , p['edge'])
    def clip(self, m): self.a[~m] = 0

class Rig:
    """One rig's stencils: torso / head frames / arm poses / legs frames (alpha masks), its anchors, and a deterministic RNG per (item, rig)."""
    def __init__(self, rid):
        self.id = rid
        d = CREW + '/' + rid
        j = json.load(open(d + '/crew.json'))
        self.n = j['frame'][0]; self.c = j['pivot'][0]; self.kind = j.get('kind') or 'normal'
        self.s = self.n / 33.0
        def strip(name):
            im = np.array(Image.open('%s/%s.png' % (d, name)).convert('RGBA'))
            return [im[:, i * self.n:(i + 1) * self.n] for i in range(im.shape[1] // self.n)]
        self.torso = strip('torso')[0]; self.heads = strip('head'); self.arms = strip('arms'); self.legs = strip('legs')
        self.T = alpha(self.torso)
        an = j['layers']['torso'].get('anchors', {})
        self.anchor = {k: tuple(v) for k, v in an.items()}
        ys, xs = np.nonzero(self.T)
        self.bb = (xs.min(), ys.min(), xs.max(), ys.max())
        self.cx = (self.bb[0] + self.bb[2]) / 2.0; self.cy = (self.bb[1] + self.bb[3]) / 2.0

    def sh(self, name, dflt):
        return self.anchor.get(name, dflt)

class Maker:
    def __init__(self, rig, item):
        self.r = rig; self.it = ITEMS[item]; self.p = self.it['pal']; self.id = item
        self.rng = np.random.default_rng(zlib.crc32(('%s/%s' % (item, rig.id)).encode()))

    def col(self, name): return self.p[name]

    # ------------------------------------------------------------ body
    def body(self):
        r = self.r; n = r.n; cv = Canvas(n); T = r.T; shape = T.shape; p = self.p; s = r.s
        x0, y0, x1, y1 = r.bb; cx, cy = r.cx, r.cy
        covered = np.zeros(shape, bool)
        sl = r.sh('shoulder_l', (x0 + 1, cy)); sr = r.sh('shoulder_r', (x1 - 1, cy))
        for op in self.it['body']:
            k = op[0]
            if k == 'fill':
                m = dilate(T, op[2]) if len(op) > 2 else T.copy()
                if op[1] < 1.0:
                    m = m & rect(shape, x0, y0 + (1 - op[1]) * (y1 - y0) * 0.5, x1, y1)
                cv.shade(m, p); covered |= m
            elif k == 'cloak':
                m = dilate(T, int(op[1] * max(1, round(s)))); covered |= m
                yy, xx = np.mgrid[0:n, 0:n]
                hue = ((xx + yy) / (2.0 * n) * 1.6) % 1.0
                for cc in (0, 1, 2):
                    v = 0.5 + 0.5 * np.sin(2 * np.pi * (hue + cc / 3.0))
                    ch = (p['mid'][cc] * 0.45 + 255 * v * 0.55)
                    cv.a[..., cc][m] = ch[m].astype(np.uint8)
                cv.a[..., 3][m] = 215
                cv.put(edge_of(m), p['lo'], 230)
                inner = m & ~erode(m, 2) & erode(m, 1)
                cv.put(inner, p['hi'], 200)
            elif k == 'bands':
                col = p[op[2]] if len(op) > 2 else p['lo']
                for i in range(1, op[1] + 1):
                    y = int(y0 + (y1 - y0) * i / (op[1] + 1)); cv.put(covered_row(T, y), col)
            elif k == 'segments':
                for i in range(1, op[1] + 1):
                    y = int(y0 + (y1 - y0) * i / (op[1] + 1)); cv.put(covered_row(T, y), p['lo']); cv.put(covered_row(T, y - 1) & covered, p['hi'])
            elif k == 'seamv':
                cv.put(rect(shape, int(cx), y0 + 1, int(cx), y1 - 1) & T, p['lo'])
            elif k == 'plates':
                for i in range(1, op[1] + 1):
                    y = int(y0 + (y1 - y0) * i / (op[1] + 1)); cv.put(covered_row(T, y) & covered, p['lo'])
                    xs = [int(x0 + (x1 - x0) * (0.3 if i % 2 else 0.7))]
                    for x in xs: cv.put(rect(shape, x, y, x, int(y + (y1 - y0) / (op[1] + 1))) & T & covered, p['lo'])
                    for x in range(x0 + 2, x1 - 1, 4): cv.put(rect(shape, x, y - 1, x, y - 1) & T, p['hi'])
            elif k == 'stone':
                for i in range(6):
                    px, py = self.rng.integers(x0, x1 + 1), self.rng.integers(y0, y1 + 1)
                    cv.put(disc(shape, px, py, 1.5 * s + self.rng.random()) & T & covered, p['hi'] if i % 2 else p['lo'])
            elif k == 'cracks':
                for i in range(3):
                    px, py = int(self.rng.integers(x0 + 2, x1 - 2)), int(self.rng.integers(y0 + 1, y1 - 3))
                    cv.put(line(shape, px, py, px + int(self.rng.integers(-3, 4)), py + int(3 * s), 0.5) & T, p['lo'])
            elif k == 'pleats':
                for x in range(x0 + 2, x1, 3): cv.put(rect(shape, x, y0 + 1, x, y1 - 1) & T & covered, p['lo'])
                for x in range(x0 + 3, x1, 6): cv.put(rect(shape, x, y0 + 1, x, y0 + 1) & T, p['hi'])
            elif k == 'belt':
                y = int(y0 + (y1 - y0) * op[1]); col = p[op[2]]
                cv.put(rect(shape, x0, y, x1, y) & T, col); cv.put(rect(shape, x0, y + 1, x1, y + 1) & T, p['edge'])
                cv.put(rect(shape, int(cx) - 1, y, int(cx) + 1, y + 1) & T, p['acc'])
            elif k == 'hem':
                y = y1 - max(1, int(s)) + 1; cv.put(rect(shape, x0, y, x1, y1) & T & covered, p[op[1]] if len(op) > 1 else p['acc'])
            elif k == 'stripes':
                for dy in (0.30, 0.52):
                    y = int(y0 + (y1 - y0) * dy); cv.put(rect(shape, x0, y, x1, y + int(s) - 1) & T, p[op[1]])
            elif k == 'stripe':
                cv.put(rect(shape, int(cx) - 1, y0, int(cx) - 1, y0 + int(0.5 * (y1 - y0))) & T, p[op[1]])
            elif k == 'hazard':
                y = int(y0 + (y1 - y0) * 0.62)
                for x in range(x0, x1 + 1):
                    if (x // 2) % 2 == 0: cv.put(rect(shape, x, y, x, y + 1) & T, p['acc'])
            elif k == 'buttons':
                for i in range(3):
                    y = int(y0 + (y1 - y0) * (0.30 + 0.2 * i)); cv.put(rect(shape, int(cx) + 1, y, int(cx) + 1, y) & T, p[op[1]])
            elif k == 'collar':
                hx, hy = r.sh('head', (cx, cy))
                cv.put(disc(shape, hx, hy, 5.2 * s) & ~disc(shape, hx, hy, 3.2 * s) & T, p[op[1]])
            elif k == 'straps':
                col = p[op[1]]
                for (a, b) in ((sl, (x1 - 3 * s, y1 - 3)), (sr, (x0 + 3 * s, y1 - 3))):
                    cv.put(line(shape, a[0], a[1], b[0], b[1], 0.9) & T, col); cv.put(line(shape, a[0] + 1, a[1], b[0] + 1, b[1], 0.5) & T, p['edge'])
            elif k == 'buckles':
                cv.put(disc(shape, cx, cy + 1, 1.2) & T, p[op[1]])
            elif k == 'sash':
                a = (x0 + 1, y0 + 2 * s); b = (x1 - 1, y1 - 2)
                m = line(shape, a[0], a[1], b[0], b[1], 2.3 * s) & T
                cv.put(m, p['mid']); cv.put(edge_of(m), p['lo']); cv.put(line(shape, a[0], a[1] - 1, b[0], b[1] - 1, 0.4) & m, p['hi'])
            elif k == 'cross':
                px, py = cx, cy; q = max(1, int(s * 1.5))
                cv.put(rect(shape, px - q, py, px + q, py) & T | rect(shape, px, py - q, px, py + q) & T, p[op[1]])
            elif k == 'apron':
                cv.put(rect(shape, int(cx - 2 * s), y0 + 2, int(cx + 2 * s), y1 - 1) & T, p['hi'])
                cv.put(edge_of(rect(shape, int(cx - 2 * s), y0 + 2, int(cx + 2 * s), y1 - 1) & T), p['lo'])
                cv.put(line(shape, sl[0], sl[1], cx - 2 * s, y0 + 3, 0.6) & T, p['lo']); cv.put(line(shape, sr[0], sr[1], cx + 2 * s, y0 + 3, 0.6) & T, p['lo'])
            elif k == 'studs':
                for i in range(op[2]):
                    px, py = int(self.rng.integers(x0 + 2, x1 - 1)), int(self.rng.integers(y0 + 2, y1 - 1))
                    if T[py, px]: cv.put(rect(shape, px, py, px, py), p[op[1]])
            elif k == 'rivets':
                for i in range(op[2]):
                    px, py = int(self.rng.integers(x0 + 2, x1 - 1)), int(self.rng.integers(y0 + 2, y1 - 1))
                    if T[py, px]: cv.put(rect(shape, px, py, px, py), p[op[1]])
            elif k == 'led':
                cv.put(rect(shape, int(cx) + 2, y0 + 3, int(cx) + 2, y0 + 3), p[op[1]])
            elif k == 'glowline':
                cv.put(rect(shape, x0 + 2, int(y0 + (y1 - y0) * op[2]), x1 - 2, int(y0 + (y1 - y0) * op[2])) & T, p[op[1]])
            elif k == 'fringe':
                m = dilate(T, 1) & ~T
                for (px, py) in zip(*np.nonzero(m)[::-1]):
                    if (px + py) % 3 == 0: cv.put(rect(shape, px, py, px, py), p['hi'])
            elif k == 'spores':
                for i in range(op[3]):
                    px, py = int(self.rng.integers(x0 - 1, x1 + 2)), int(self.rng.integers(y0, y1 + 2))
                    if 0 <= px < n and 0 <= py < n and (T[py, px] or i % 2):
                        cv.put(rect(shape, px, py, px, py), p[op[1 + i % 2]])
            elif k == 'gem':
                hx, hy = r.sh('head', (cx, cy))
                cv.put(disc(shape, cx, y1 - 2, 1.4 * s), p['acc2']); cv.put(rect(shape, int(cx), y1 - 3, int(cx), y1 - 3), p['acc'])
            elif k == 'pads':
                self.pads(cv, op[1], op[2] * s, sl, sr)
            elif k == 'back':
                self.back(cv, op[1])
        return cv.a

    def pads(self, cv, kind, rad, sl, sr):
        p = self.p; shape = (self.r.n, self.r.n); n = self.r.n
        for (sx, sy), sgn in ((sl, -1), (sr, 1)):
            if kind == 'plate':
                m = rect(shape, sx - rad * (0.2 if sgn > 0 else 1.0), sy - rad, sx + rad * (1.0 if sgn > 0 else 0.2), sy + rad * 0.9)
                cv.shade(m, p); cv.put(rect(shape, sx - rad * 0.6, sy, sx + rad * 0.6, sy), p['lo']);
            elif kind in ('round', 'cap', 'dome'):
                m = disc(shape, sx, sy, rad); cv.shade(m, p)
                if kind == 'dome': cv.put(rect(shape, sx - rad, sy, sx + rad, sy) & m, p['acc'])
                if kind == 'cap': cv.put(disc(shape, sx - 1, sy - 1, 1.0) & m, p['acc'])
            elif kind == 'spike':
                m = disc(shape, sx, sy, rad * 0.8); cv.shade(m, p)
                tip = (sx + sgn * rad * 1.5, sy - rad * 0.5)
                sp = line(shape, sx, sy, tip[0], tip[1], 1.1); cv.put(sp, p['mid']); cv.put(line(shape, sx, sy - 1, tip[0], tip[1], 0.4), p['hi'])
            elif kind == 'rock':
                m = disc(shape, sx, sy, rad) & ~disc(shape, sx + sgn * rad, sy - rad, rad * 0.7); cv.shade(m, p)
                cv.put(line(shape, sx - 1, sy - 2, sx + 1, sy + 2, 0.4) & m, p['lo'])
            elif kind == 'scrap':
                m = rect(shape, sx - rad, sy - rad * 0.8, sx + rad, sy + rad * 0.8) & ~disc(shape, sx - sgn * rad, sy - rad, rad * 0.8)
                cv.shade(m, p); cv.put(disc(shape, sx, sy, 0.8), p['acc'])
                cv.put(rect(shape, sx - rad, sy + 1, sx + rad, sy + 1) & m, p['acc'])

    def back(self, cv, kind):
        r = self.r; p = self.p; shape = (r.n, r.n); s = r.s
        bx, by = r.sh('back', (r.cx, r.bb[3] - 2)); bx = r.cx if abs(bx - r.cx) < 3 else bx
        by = min(by, r.n - 7)
        lim = rect(shape, 1, 1, r.n - 2, r.n - 2)
        if kind == 'tanks':
            for dx in (-3.2, 3.2):
                m = rect(shape, bx + dx * s - 1.5 * s, by - 1, bx + dx * s + 1.5 * s, by + 6 * s) & lim
                cv.shade(m, p); cv.put(rect(shape, bx + dx * s - 1.5 * s, by + 1, bx + dx * s + 1.5 * s, by + 1) & m, p['lo'])
                cv.put(rect(shape, bx + dx * s, by - 1, bx + dx * s, by - 1) & lim, p['acc'])
        elif kind == 'tank':
            m = rect(shape, bx - 2 * s, by - 1, bx + 2 * s, by + 7 * s) & lim
            cv.shade(m, dict(p, mid=p['hi'], hi=p['acc'], lo=p['mid'], edge=p['lo'])); cv.put(rect(shape, bx - 2 * s, by + 2 * s, bx + 2 * s, by + 2 * s) & m, p['lo'])
            cv.put(rect(shape, bx, by - 1, bx, by - 1) & lim, p['acc2'])
        elif kind == 'power':
            m = rect(shape, bx - 5 * s, by - 2, bx + 5 * s, by + 5 * s) & lim; cv.shade(m, p)
            for i in range(3):
                cv.put(rect(shape, bx - 4 * s + i * 4 * s, by + 1, bx - 3 * s + i * 4 * s, by + 3 * s) & lim, p['acc'])
            cv.put(rect(shape, bx - 5 * s, by + 5 * s - 1, bx + 5 * s, by + 5 * s - 1) & lim, p['acc2'])
        elif kind == 'fins':
            m = rect(shape, bx - 4 * s, by - 1, bx + 4 * s, by + 5 * s) & lim; cv.shade(m, p)
            for i in range(1, 4): cv.put(rect(shape, bx - 4 * s, by - 1 + i * 1.3 * s, bx + 4 * s, by - 1 + i * 1.3 * s) & m, p['lo'])
            cv.put(rect(shape, bx, by + 5 * s - 1, bx, by + 5 * s - 1) & lim, hexc('#6bd34a'))
        elif kind == 'tools':
            for i, (dx, col) in enumerate(((-4, 'hi'), (0, 'acc'), (4, 'acc2'))):
                m = rect(shape, bx + dx * s - 1, by, bx + dx * s + 1, by + 5 * s) & lim; cv.put(m, p[col]); cv.put(edge_of(m), p['lo'])
        elif kind == 'satchel':
            m = rect(shape, bx - 3.5 * s, by, bx + 3.5 * s, by + 4.5 * s) & lim; cv.shade(m, p)
            cv.put(rect(shape, bx - 1, by + 1, bx + 1, by + 1) & m, p['acc']); cv.put(rect(shape, bx, by, bx, by + 2) & m, p['acc'])
        elif kind == 'jets':
            m = rect(shape, bx - 5 * s, by - 2, bx + 5 * s, by + 5 * s) & lim; cv.shade(m, p)
            for dx in (-3, 3):
                cv.put(disc(shape, bx + dx * s, by + 5 * s - 1, 1.8 * s) & lim, p['lo'])
                cv.put(disc(shape, bx + dx * s, by + 5 * s, 1.1 * s) & lim, p['acc']); cv.put(disc(shape, bx + dx * s, by + 5 * s + 1, 0.6) & lim, p['acc2'])
        elif kind == 'shell':
            m = disc(shape, bx, by + 2 * s, 5.2 * s) & lim; cv.shade(m, p)
            for i in range(-1, 2): cv.put(line(shape, bx + i * 3 * s, by - 2, bx + i * 2 * s, by + 6 * s, 0.4) & m, p['lo'])
        elif kind == 'weights':
            for i, dx in enumerate((-4.5, 0, 4.5)):
                m = rect(shape, bx + dx * s - 2 * s, by, bx + dx * s + 2 * s, by + 4 * s) & lim; cv.shade(m, p)
                cv.put(rect(shape, bx + dx * s - 2 * s, by + 2 * s, bx + dx * s + 2 * s, by + 2 * s) & m, p['acc'])

    # ------------------------------------------------------------ head
    def head_geom(self, H):
        ys, xs = np.nonzero(H)
        if len(xs) == 0: return None
        return xs.mean(), ys.mean(), max(2.0, (len(xs) / np.pi) ** 0.5), (xs.min(), ys.min(), xs.max(), ys.max())

    def head(self, H):
        style = self.it['head']; n = self.r.n; cv = Canvas(n); p = self.p; shape = H.shape; g = self.head_geom(H)
        if style is None or g is None: return cv.a
        hx, hy, rad, bb = g; s = self.r.s
        front = lambda lo, hi: rect(shape, bb[0], hy - rad * lo, bb[2], hy - rad * hi)
        if style == 'bubble':
            ring = dilate(H | disc(shape, hx, hy, rad), 2) & ~dilate(H | disc(shape, hx, hy, rad), 1)
            fill = dilate(H | disc(shape, hx, hy, rad), 1)
            cv.put(fill, p['acc2'], 70); cv.put(ring, p['mid']); cv.put(ring & (rect(shape, 0, 0, hx, hy)), p['hi'])
            cv.put(disc(shape, hx - rad * 0.5, hy - rad * 0.5, 1.0), p['hi'], 255)
            cv.put(rect(shape, hx - rad, hy + rad + 1, hx + rad, hy + rad + 1) & rect(shape, 0, 0, n - 1, n - 1), p['lo'])
        elif style in ('helm_visor', 'helm_dome'):
            m = H.copy(); cv.shade(m, p)
            v = H & front(0.75, 0.15)
            if style == 'helm_visor': cv.put(v, p['acc2']); cv.put(v & rect(shape, 0, 0, hx, 999), p['hi'], 255); cv.put(edge_of(v), p['lo'])
            else:
                cv.put(v, p['lo']); cv.put(rect(shape, hx - 1, bb[1], hx, bb[3]) & H, p['hi'])
            cv.put(rect(shape, hx - 1, bb[1], hx - 1, hy - rad * 0.8) & H, p['hi'])
        elif style in ('hood_ember', 'visor_gold'):
            cv.shade(H & ~front(0.75, 0.15) if style == 'hood_ember' else H, p)
            v = H & front(0.8, 0.2)
            cv.put(v, p['acc2'] if style == 'hood_ember' else p['acc']); cv.put(v & (rect(shape, 0, 0, hx, 999)), p['acc'] if style == 'hood_ember' else p['hi'])
            cv.put(edge_of(v), p['lo'])
        elif style == 'hardhat':
            m = disc(shape, hx, hy, rad * 0.95) & dilate(H, 1); cv.shade(m, dict(p, mid=p['acc2'], hi=hexc('#e86a4a'), lo=hexc('#7a2418'), edge=hexc('#4a1208')))
            cv.put(rect(shape, hx - 1, bb[1] - 1, hx, hy) & m, p['acc']); cv.put(rect(shape, bb[0] - 1, hy - rad * 0.55, bb[2] + 1, hy - rad * 0.55) & dilate(H, 1), hexc('#4a1208'))
        elif style == 'crest':
            m = H & rect(shape, bb[0], hy - rad * 0.1, bb[2], bb[3]); cv.shade(m, p)
            for dx in (-0.55, 0, 0.55): cv.put(line(shape, hx + dx * rad, hy - rad * 0.2, hx + dx * rad * 1.15, hy - rad * 1.25, 0.55), p['acc'])
        elif style == 'spore_head':
            for i in range(6):
                a = self.rng.random() * 6.28; rr = rad * (0.4 + 0.7 * self.rng.random())
                cv.put(disc(shape, hx + rr * np.cos(a), hy + rr * np.sin(a), 0.9), p['acc' if i % 2 else 'acc2'])
        elif style == 'diadem':
            cv.put(edge_of(disc(shape, hx, hy, rad + 0.6)), p['hi'], 220); cv.put(disc(shape, hx, hy - rad - 0.4, 1.3), p['acc2'])
            cv.put(rect(shape, hx, hy - rad - 0.4, hx, hy - rad - 0.4), p['acc'])
        elif style == 'mask':
            v = H & front(0.5, 0.0) & ~front(0.0, 0.0)
            v = H & rect(shape, bb[0], bb[1], bb[2], hy - rad * 0.2)
            cv.put(v, p['mid']); cv.put(edge_of(v), p['lo']); cv.put(rect(shape, hx - 1, bb[1], hx + 1, bb[1] + 1) & H, p['hi'])
            cv.put(line(shape, hx - rad, hy, hx - rad - 1, hy + rad, 0.4), p['lo'])
        # a slight ring so the gear still reads on a head with little stencil
        return cv.a

    # ------------------------------------------------------------ sleeves / legs
    def sleeves(self, A):
        style = self.it['sleeves']; cv = Canvas(self.r.n); p = self.p
        if style is None: return cv.a
        for comp in components(alpha(A)):
            ys, xs = np.nonzero(comp)
            if len(ys) < 5: continue
            lo, hi = ys.min(), ys.max()
            span = max(1, hi - lo)
            if style == 'full':
                m = comp & (np.mgrid[0:comp.shape[0], 0:comp.shape[1]][0] >= lo + 0.30 * span)
            elif style == 'gauntlet':
                m = comp & (np.mgrid[0:comp.shape[0], 0:comp.shape[1]][0] <= lo + 0.55 * span)
            else:   # pads: a cuff and an elbow pad
                yy = np.mgrid[0:comp.shape[0], 0:comp.shape[1]][0]
                m = comp & (yy >= lo + 0.35 * span) & (yy <= lo + 0.65 * span)
            cv.shade(m, p)
            if style == 'gauntlet': cv.put(m & (np.mgrid[0:comp.shape[0], 0:comp.shape[1]][0] == int(lo + 0.5 * span)), p['acc'])
            if style == 'full': cv.put(m & (np.mgrid[0:comp.shape[0], 0:comp.shape[1]][0] == int(lo + 0.5 * span)), p['lo'])
        return cv.a

    def legs(self, L):
        style = self.it['legs']; cv = Canvas(self.r.n); p = self.p
        if style is None or self.r.kind == 'floating': return cv.a
        A = alpha(L)
        for comp in components(A):
            ys, xs = np.nonzero(comp)
            if len(ys) < 4: continue
            lo, hi = ys.min(), ys.max(); span = max(1, hi - lo)
            yy = np.mgrid[0:comp.shape[0], 0:comp.shape[1]][0]
            m = comp if style == 'full' else comp & ((yy <= lo + 0.30 * span) | (yy >= hi - 0.30 * span))
            if style == 'boots': m = comp & ((yy <= lo + 0.45 * span) | (yy >= hi - 0.45 * span))
            cv.shade(m, dict(p, mid=p['lo'], hi=p['mid'], lo=tuple(max(0, c - 30) for c in p['lo'][:3]) + (255,)) if style == 'boots' else p)
        return cv.a


def covered_row(T, y):
    m = np.zeros_like(T); m[y] = T[y]; return m


# ---------------------------------------------------------------- export
def strip(frames):
    return np.concatenate(frames, axis=1)

def make(item, rig):
    mk = Maker(rig, item); it = ITEMS[item]
    frames = [mk.body()]
    layout = {'body': [0, 1]}
    if it['head']:
        layout['head'] = [len(frames), len(rig.heads)]
        frames += [mk.head(alpha(h)) for h in rig.heads]
    if it['sleeves']:
        layout['sleeves'] = [len(frames), len(rig.arms)]
        frames += [mk.sleeves(a) for a in rig.arms]
    if it['legs'] and rig.kind != 'floating':
        layout['legs'] = [len(frames), len(rig.legs)]
        frames += [mk.legs(l) for l in rig.legs]
    # keep every drawn pixel inside the frame, and give each a 1px dark rim where it reaches past the silhouette
    return strip(frames), layout

def rigs():
    return sorted(d for d in os.listdir(CREW) if os.path.exists('%s/%s/crew.json' % (CREW, d)))

def targets(item, rid):
    """is gear `item` generated for rig `rid`? (the hand-made art covers the old items on the human rig and the gauntling)"""
    return not (item in OLD and rid in HAND_RIGS)

def export():
    for item in ITEMS:
        d = '%s/%s' % (GEAR, item); os.makedirs(d, exist_ok=True)
        meta = {'id': item, 'about': 'generated by art/_src/sp_wardrobe.py from each rig\'s own sprites: <rig>.png is a strip of rig-frame cells: body (1), head (per head frame), sleeves (per arm pose), legs (per legs frame); see "layers" for [first, count] by rig. Overlays: body after the torso, sleeves after the arms, head after the head frame of the same index, legs after the legs frame of the same index.',
                'rigs': {}}
        for rid in rigs():
            if not targets(item, rid): continue
            rig = Rig(rid)
            im, layout = make(item, rig)
            Image.fromarray(im).save('%s/%s.png' % (d, rid))
            meta['rigs'][rid] = {'frame': rig.n, 'pivot': rig.c, 'layers': layout}
        with open(d + '/gear.json', 'w') as f: json.dump(meta, f, indent=1); f.write('\n')

# ---------------------------------------------------------------- contact sheet (QA): every item on every rig, standing / walking / down
def compose(rid, item, pose):
    rig = Rig(rid); n = rig.n
    out = np.zeros((n, n, 4), np.uint8)
    def over(dst, src):
        a = src[..., 3:4].astype(float) / 255.0
        dst[..., :3] = (dst[..., :3] * (1 - a) + src[..., :3] * a).astype(np.uint8)
        dst[..., 3] = np.maximum(dst[..., 3], src[..., 3])
    path = '%s/%s/%s.png' % (GEAR, item, rid)
    g = meta = None
    if os.path.exists(path):
        g = np.array(Image.open(path).convert('RGBA')); meta = json.load(open('%s/%s/gear.json' % (GEAR, item)))['rigs'][rid]['layers']
    def gf(layer, i):
        a, c = meta[layer]; return g[:, (a + i) * n:(a + i + 1) * n]
    li = 1 if pose == 'walk' else 6
    over(out, rig.legs[li])
    if g is not None and 'legs' in meta: over(out, gf('legs', li))
    over(out, rig.torso)
    if g is not None: over(out, gf('body', 0))
    over(out, rig.arms[0])
    if g is not None and 'sleeves' in meta: over(out, gf('sleeves', 0))
    over(out, rig.heads[0])
    if g is not None and 'head' in meta: over(out, gf('head', 0))
    im = Image.fromarray(out)
    if pose == 'down':
        im = im.rotate(90); a = np.array(im); a[..., :3] = (a[..., :3] * 0.5).astype(np.uint8); im = Image.fromarray(a)
    return im

def sheet(path, scale=3):
    ids = list(ITEMS); rr = rigs(); cell = 49 * scale
    W = cell * 3 * len(rr) // 3
    bg = (24, 28, 36, 255)
    # rows = items (+ "bare"), columns = rigs x 3 poses
    cols = len(rr) * 3
    sheetim = Image.new('RGBA', (cols * 49 * scale // 2 + 8, (len(ids) + 1) * 49 * scale // 2 + 8), bg)
    cw = 49 * scale // 2
    for ri, item in enumerate([None] + ids):
        for ci, rid in enumerate(rr):
            for pi, pose in enumerate(('stand', 'walk', 'down')):
                im = compose(rid, item or '_none', pose)
                im = im.resize((im.width * scale // 2, im.height * scale // 2), Image.NEAREST)
                sheetim.alpha_composite(im, (4 + (ci * 3 + pi) * cw + (cw - im.width) // 2, 4 + ri * cw + (cw - im.height) // 2))
    sheetim.save(path)

if __name__ == '__main__':
    if '--clean' in sys.argv:
        import shutil
        for item in ITEMS: shutil.rmtree('%s/%s' % (GEAR, item), ignore_errors=True)
    export()
    if '--sheet' in sys.argv:
        sheet(sys.argv[sys.argv.index('--sheet') + 1])
    print('ok')
