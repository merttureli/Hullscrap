"""Space backdrop layers (art/space/): three parallax star layers that tile (256x256: far, mid, near dust) and five faint nebula overlays (512x512, soft alpha, grey so the game tints them),
one per region mood. These are the only art with soft gradients (soft alpha, palette greys); everything is deterministic (integer hash noise, no random module).
The layers are transparent: the game draws the space colour behind them. Keep them dark and quiet so the ship stands out."""
import math, json, os
from px import *
import pal_sector
from dbr import vnoise, fbm, smooth
from sector_fx import write_json

# ------------------------------------------------------------------ stars (tile on both axes: everything wraps)
class Lcg:
    def __init__(s, seed): s.s = seed & 0x7fffffff
    def next(s):
        s.s = (s.s * 1103515245 + 12345) & 0x7fffffff
        return (s.s >> 8) & 0xffff
    def below(s, n): return s.next() % n
    def pick(s, items): return items[s.below(len(items))]

def put_wrap(img, x, y, ch, a):
    x %= img.w; y %= img.h
    img.p[y][x] = list(RGB[ch]) + [a]

def stars_far(seed=11):
    img = Rgba(256, 256); r = Lcg(seed)
    tones = ['W'] * 12 + ['S'] * 6 + ['M'] * 2 + ['k', 'c', 'a']
    for _ in range(300):
        put_wrap(img, r.below(256), r.below(256), r.pick(tones), 120 + r.below(136))
    return img

def stars_mid(seed=23):
    img = Rgba(256, 256); r = Lcg(seed)
    tones = ['M'] * 8 + ['L'] * 3 + ['S'] * 3 + ['k', 'c', 'a', 'H']
    for _ in range(90): put_wrap(img, r.below(256), r.below(256), r.pick(tones), 170 + r.below(86))
    for _ in range(14):                                                             # a few 2x2 stars
        x, y = r.below(256), r.below(256); c = r.pick(['L', 'M', 'k', 'H'])
        for (dx, dy) in ((0, 0), (1, 0), (0, 1), (1, 1)): put_wrap(img, x + dx, y + dy, c, 210 if (dx, dy) == (0, 0) else 120)
    for _ in range(6):                                                              # a few sparkles
        x, y = r.below(256), r.below(256); c = r.pick(['H', 'L', 'c', 'k'])
        put_wrap(img, x, y, 'H', 255)
        for (dx, dy) in ((1, 0), (-1, 0), (0, 1), (0, -1)): put_wrap(img, x + dx, y + dy, c, 170)
        for (dx, dy) in ((2, 0), (-2, 0), (0, 2), (0, -2)): put_wrap(img, x + dx, y + dy, c, 70)
    return img

def stars_near(seed=37):
    img = Rgba(256, 256); r = Lcg(seed)
    for _ in range(34):                                                             # dust motes: single pixels and short streaks (the near layer moves fastest)
        x, y = r.below(256), r.below(256); c = r.pick(['M', 'L', 'M', 'Q', 'S']); n = r.pick([1, 1, 2, 3])
        a = 90 + r.below(110)
        for k in range(n): put_wrap(img, x + k, y, c, max(40, a - k * 35))
    for _ in range(7):                                                              # soft out-of-focus motes
        x, y = r.below(256), r.below(256); c = r.pick(['L', 'M'])
        put_wrap(img, x, y, c, 120)
        for (dx, dy) in ((1, 0), (-1, 0), (0, 1), (0, -1)): put_wrap(img, x + dx, y + dy, c, 55)
        for (dx, dy) in ((1, 1), (-1, -1), (1, -1), (-1, 1)): put_wrap(img, x + dx, y + dy, c, 22)
    return img

# ------------------------------------------------------------------ nebulae
def ssm(a, b, x): return smooth(max(0.0, min(1.0, (x - a) / float(b - a))))
def gauss(x, y, cx, cy, s): return math.exp(-(((x - cx) ** 2 + (y - cy) ** 2) / (2 * s * s)))

def dens_clan(x, y, seed):
    w = fbm(x * 3, y * 3, seed + 1, 3) * 0.35
    n = fbm(x * 2.0 + w, y * 7.0 + w * 0.5, seed, 4)                                 # stretched: ragged horizontal dust lanes
    rd = 1 - abs(2 * n - 1)
    return ssm(0.50, 0.92, n * 0.6 + rd * 0.4)
def dens_concord(x, y, seed):
    n = fbm(x * 1.5, y * 2.3, seed, 2)
    band = 0.5 + 0.5 * math.sin((y * 3.5 + n * 1.5) * math.pi)                      # calm layered bands
    return 0.8 * ssm(0.30, 0.85, n * 0.55 + band * 0.45)
def dens_lumen(x, y, seed):
    w1, w2 = fbm(x * 2.4, y * 2.4, seed + 1, 3), fbm(x * 2.4 + 5, y * 2.4 + 3, seed + 2, 3)
    n = fbm(x * 3.2 + w1 * 1.3, y * 3.2 + w2 * 1.3, seed, 4)
    r = 1 - abs(2 * n - 1)                                                          # wispy glowing filaments
    d = ssm(0.58, 1.0, r) * 0.85
    for (cx, cy, s) in ((0.38, 0.42, 0.07), (0.64, 0.58, 0.05), (0.5, 0.3, 0.04)): d += 0.5 * gauss(x, y, cx, cy, s) * ssm(0.3, 0.7, r)
    return min(1.0, d)
def dens_boneyard(x, y, seed):
    n1, n2 = fbm(x * 3.0, y * 3.0, seed, 4), fbm(x * 9.0, y * 9.0, seed + 3, 3)
    d = ssm(0.30, 0.72, n1) * (0.55 + 0.45 * n2)                                     # murky and mottled, with dark holes
    if fbm(x * 5, y * 5, seed + 9, 3) > 0.62: d *= 0.35
    return d
def dens_gate(x, y, seed):
    r = math.hypot(x - 0.5, y - 0.5)
    ringv = math.exp(-((r - 0.31) / 0.045) ** 2) * (0.55 + 0.45 * fbm(x * 6, y * 6, seed, 3))
    inner = 0.45 * math.exp(-((r - 0.17) / 0.02) ** 2)
    wisp = 0.55 * ssm(0.55, 0.9, fbm(x * 4, y * 4, seed + 4, 4))
    return min(1.0, ringv + inner + wisp * 0.6)

NEB = {  # id: (density fn, max alpha, light letters for the dense cores, seed, suggested tint, mood)
    'clan': (dens_clan, 100, 'WSML', 5, '#b5683a', 'Clan space: rust-red dust, ragged horizontal lanes'),
    'concord': (dens_concord, 72, 'WSML', 7, '#6f8bb0', 'Concord space: a calm blue-grey haze in orderly bands'),
    'lumen': (dens_lumen, 58, 'WSML', 9, '#8f9cff', 'Lumen space: glowing cyan-violet filaments with bright cores'),
    'boneyard': (dens_boneyard, 92, 'WSML', 13, '#6e7a4e', 'the Boneyard: murky, mottled and thick, with dark holes'),
    'gate': (dens_gate, 52, 'WMLH', 17, '#dfe9f5', 'Gate approaches: a pale, thin ring and wisps'),
}

def nebula(key, N=256):
    fn, amax, letters, seed, tint, mood = NEB[key]
    grid = []
    for j in range(N + 1):
        row = []
        for i in range(N + 1):
            x, y = i / float(N), j / float(N)
            r = math.hypot(x - 0.5, y - 0.5) * (0.78 + 0.5 * fbm(x * 1.7 + 3, y * 1.7 + 1, seed + 30, 2))     # an irregular edge, not a disc
            v = 1 - ssm(0.30, 0.50, r)                                                # fades to nothing at the edge: the overlay has no visible border
            row.append(min(1.0, fn(x, y, seed)) * v)
        grid.append(row)
    img = Rgba(512, 512)
    for j in range(512):
        gy = j / 2.0; j0 = min(N - 1, int(gy)); fy = gy - j0
        for i in range(512):
            gx = i / 2.0; i0 = min(N - 1, int(gx)); fx = gx - i0
            d = (grid[j0][i0] * (1 - fx) + grid[j0][i0 + 1] * fx) * (1 - fy) + (grid[j0 + 1][i0] * (1 - fx) + grid[j0 + 1][i0 + 1] * fx) * fy
            a = int(round(d * amax))
            if a <= 0: continue
            k = letters[0] if d < 0.30 else letters[1] if d < 0.55 else letters[2] if d < 0.85 else letters[3]
            img.p[j][i] = list(RGB[k]) + [a]
    return img

def export(art_dir=None):
    art_dir = art_dir or ART
    d = art_dir + '/space'
    os.makedirs(d, exist_ok=True)
    for name, fn, speed, note in (('stars_far', stars_far, 0.04, 'far stars: many, tiny, dim, a few faint tints'),
                                  ('stars_mid', stars_mid, 0.12, 'mid stars: fewer and brighter, some 2x2 stars and a few sparkles'),
                                  ('stars_near', stars_near, 0.35, 'near dust: sparse motes and short streaks, soft out-of-focus dots; it moves fastest')):
        fn().save('%s/%s.png' % (d, name))
        write_json('%s/%s.json' % (d, name), {'frame': [256, 256], 'tile': 'xy', 'alpha': True, 'parallax': speed,
                                              'notes': 'Parallax star layer, %s. Transparent, tiles seamlessly on both axes (every star wraps round the edge): draw it repeated, offset by the camera times `parallax` (far 0.04, mid 0.12, near 0.35), over the space colour the game draws behind. '
                                                       'Soft alpha on palette letters (the one place alpha stars are allowed).' % note})
    for key in NEB:
        nebula(key).save('%s/nebula_%s.png' % (d, key))
        write_json('%s/nebula_%s.json' % (d, key), {'frame': [512, 512], 'alpha': True, 'tint': 'multiply', 'suggested_tints': {'region': NEB[key][4]}, 'parallax': 0.06,
                                                    'notes': 'Nebula overlay, %s. Soft alpha (at most %d/255) in palette greys, fading to nothing at the edge so it can be placed anywhere with no border. '
                                                             'Multiply the suggested tint over it and draw it big, behind everything, over the star layers; it must stay faint, the ship stands out.' % (NEB[key][5], NEB[key][1])})
        print('nebula', key)

if __name__ == '__main__':
    export()
