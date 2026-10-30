"""Effects: fire, smoke, sparks, explosion, muzzle flash, shield ripple, heat shimmer."""
from px import *


# ======================================================================== FIRE (4 frames, 16x16, base at the bottom)
# Flat bold shapes: the silhouette is drawn by hand (tongues + a base), then filled in flat bands:
# red tips on the outer edge, orange body, yellow core.
def tongue(cells, cx, tip_y, widths, lean, base_y=15):
    for i, y in enumerate(range(tip_y, base_y + 1)):
        w = widths[min(i, len(widths) - 1)]
        l = lean[min(i, len(lean) - 1)]
        x0 = cx - (w - 1) // 2 + l
        for x in range(x0, x0 + w): cells.add((x, y))


def fire_cells(f):
    c = set()
    for y, (a, b) in {10: (3, 12), 11: (2, 13), 12: (2, 13), 13: (3, 12), 14: (4, 11), 15: (6, 9)}.items():
        a2, b2 = a + f['wob'][y - 10][0], b + f['wob'][y - 10][1]
        for x in range(a2, b2 + 1): c.add((x, y))
    for (cx, ty, widths, lean) in f['t']: tongue(c, cx, ty, widths, lean, base_y=11)
    return c


TALL = [1, 1, 2, 2, 3, 3, 4, 5, 5, 6, 7]
MID = [1, 2, 2, 3, 3, 4, 4, 5, 6]
SMALL = [1, 1, 2, 2, 3, 3, 4, 5]
FIRE = [
 {'wob': [(0, 0), (0, 0), (0, 0), (0, 0), (0, 0), (0, 0)],
  't': [(8, 1, TALL, [0, 0, 0, 0, 1, 1, 1, 1]), (4, 5, SMALL, [0, 0, -1, -1, 0, 0]), (12, 4, MID, [0, 0, 0, 1, 1, 1])]},
 {'wob': [(0, -1), (0, 0), (1, 0), (0, 0), (0, 0), (0, 0)],
  't': [(7, 2, TALL, [0, 0, 0, -1, -1, -1, 0, 0]), (3, 4, MID, [0, 0, 0, 0, 1, 1]), (11, 6, SMALL, [0, 0, 0, 1, 1])]},
 {'wob': [(0, 0), (-1, 0), (0, 0), (0, 0), (0, 0), (0, 0)],
  't': [(9, 0, TALL, [0, 0, 0, 0, -1, -1, -1, -1]), (5, 6, SMALL, [0, 0, 1, 1, 1]), (12, 3, MID, [0, 0, 0, -1, -1, -1, 0])]},
 {'wob': [(1, 0), (0, 0), (0, 1), (0, 0), (0, 0), (0, 0)],
  't': [(8, 3, TALL, [0, 0, 1, 1, 1, 1, 0, 0]), (4, 3, MID, [0, 0, 0, -1, -1, 0, 0]), (12, 5, SMALL, [0, 0, 0, 0, 1, 1])]},
]


def fire_frame(f):
    cells = fire_cells(f)
    body = erode(cells, 1)
    core = {(x, y) for (x, y) in erode(body, 1) if y >= 10}
    spr = Spr(16, 16)
    for (x, y) in cells: spr.put(x, y, 'r' if y < 11 else 'o')       # red tips, orange at the foot
    for (x, y) in body: spr.put(x, y, 'o')
    for (x, y) in core: spr.put(x, y, 'y')
    return spr


def fire_frames():
    return [fire_frame(f) for f in FIRE]


# ======================================================================== SMOKE (4 frames, 16x16, grey puffs rising)
# A cluster of small round puffs (x, y, radius), drawn back to front so the outline scallops like a cloud. Each puff:
# lit crescent on the top-left, shaded crescent on the bottom-right. Later frames go lighter and break up (hand-placed holes).
def puff(discs, tones, holes=()):
    spr = Spr(16, 16)
    hi, mid, lo = tones
    for (cx, cy, r) in discs:
        for (x, y) in disc(cx, cy, r, 16, 16):
            t = (x - cx) + (y - cy)
            spr.g[y][x] = hi if t < -r * 0.9 else lo if t > r * 0.8 else mid
    for (x, y) in holes: spr.erase(x, y)
    return spr


def smoke_frames():
    return [
        puff([(4, 12, 2), (8, 13, 2), (11, 12, 2), (6, 10, 2.2), (9, 10, 2.2)], ('M', 'S', 'W')),
        puff([(4, 11, 2), (11, 11, 2.3), (7, 8, 2.6), (6, 12, 2.2), (10, 8.5, 2)], ('M', 'S', 'W')),
        puff([(4, 8, 2.2), (11, 7.5, 2.4), (7, 5, 2.6), (5, 11, 2), (10, 11, 1.8), (8.5, 8.5, 2)], ('L', 'M', 'S')),
        puff([(4, 4, 1.8), (10, 3, 2.2), (7, 7, 1.8), (12, 8, 1.5), (3, 9, 1.4)], ('L', 'L', 'M'), holes=[(10, 4), (7, 7)]),
    ]


# ======================================================================== SPARKS (3 frames, 16x16)
def rays(ends, cx=8, cy=8, cols='Hyo'):
    spr = Spr(16, 16)
    for (ex, ey) in ends:
        pts = line(cx, cy, ex, ey)
        n = len(pts)
        for i, (x, y) in enumerate(pts):
            spr.put(x, y, cols[min(len(cols) - 1, i * len(cols) // max(1, n))])
    return spr


def sparks_frames():
    f0 = rays([(12, 4), (4, 11), (11, 12), (3, 4), (8, 3), (13, 9)], cols='Hyy')
    f0.rect(7, 7, 2, 2, 'H')
    f1 = rays([(14, 2), (2, 9), (12, 14), (2, 3), (9, 0), (15, 9), (5, 14)], cols='yyo')
    f1.rect(7, 7, 2, 2, 'y')
    f2 = Spr(16, 16)
    for (x, y, c) in ((15, 1, 'o'), (14, 1, 'o'), (0, 10, 'o'), (1, 10, 'r'), (13, 15, 'o'), (0, 1, 'r'), (9, 0, 'y'), (10, 0, 'o'), (15, 11, 'r'),
                      (4, 15, 'r'), (3, 4, 'o'), (12, 5, 'y'), (11, 12, 'o'), (5, 12, 'r'), (13, 6, 'o')):
        f2.put(x, y, c)
    return [f0, f1, f2]


# ======================================================================== MUZZLE FLASH (3 frames, 16x16, faces UP, muzzle at (8,15))
# A hand-drawn star: a long forward spike, short diagonal spikes, a hot splash around the muzzle.
MUZZLE = [
 art_strict("""
................
................
................
................
................
................
.......oo.......
.......yy.......
.......yy.......
....o.oyyo.o....
.....oyyyyo.....
......yHHy......
....oyyHHyyo....
...o.yHHHHy.o...
.....oyHHyo.....
......oooo......
""", 16, 16, 'muzzle0'),
 art_strict("""
................
.......oo.......
.......oo.......
.......yy.......
.......yy.......
..o....yy....o..
...o...yy...o...
....o.oyyo.o....
.....oyyyyo.....
.o...yyHHyy...o.
..oo.yHHHHy.oo..
...oyyHHHHyyo...
....yHHHHHHy....
..ooyyHHHHyyoo..
.o..oyyHHyyo..o.
.....oooooo.....
""", 16, 16, 'muzzle1'),
 art_strict("""
................
................
................
................
................
................
................
................
.......rr.......
.......oo.......
.......oo.......
...r...oo...r...
....r.oyyo.r....
.....ooyyoo.....
..r..oyyyyo..r..
....rrooooorr...
""".replace("....rrooooorr...", "....rroooorr...."), 16, 16, 'muzzle2'),
]


def muzzle_frames():
    return [from_art(rows) for rows in MUZZLE]


# ======================================================================== EXPLOSION (10 frames, 32x32)
# Flat 2-3 colour shapes, bold and graphic: white core -> yellow -> orange body with red rim -> lobes that crack open ->
# fragments flying out. Every disc is hand placed as (dx, dy, r) from the centre (16, 16).
C = 16


def blob(spec, c=C):
    cells = set()
    for (dx, dy, r) in spec: cells |= disc(c + dx, c + dy, r, 32, 32)
    return cells


def layers(*ls):
    spr = Spr(32, 32)
    for (col, cells) in ls:
        for (x, y) in cells: spr.put(x, y, col)
    return spr


def explosion_frames():
    f = []
    f.append(layers(('y', blob([(0, 0, 3)])), ('H', blob([(0, 0, 1.5)]))))
    f.append(layers(('o', blob([(0, 0, 5.5)])), ('y', blob([(0, 0, 4)])), ('H', blob([(0, 0, 2.5)]))))
    lobes2 = [(0, 0, 6), (-5, -3, 4), (5, -4, 4), (1, 6, 4)]
    f.append(layers(('r', blob(lobes2 + [(-7, 1, 2), (7, 2, 2.5)])), ('o', blob([(dx, dy, r - 1.2) for dx, dy, r in lobes2])),
                    ('y', blob([(0, 0, 4.5)])), ('H', blob([(0, 0, 3)]))))
    lobes3 = [(0, 0, 7), (-8, -4, 5), (8, -6, 5.5), (2, 8, 5), (-6, 7, 4), (9, 5, 4)]
    f.append(layers(('r', blob(lobes3)), ('o', blob([(dx, dy, r - 1.5) for dx, dy, r in lobes3])),
                    ('y', blob([(0, 0, 5), (-4, -2, 2.5), (4, -3, 2.5)])), ('H', blob([(0, 0, 3.5)]))))
    lobes4 = [(-9, -5, 5), (9, -7, 6), (2, 10, 5.5), (-8, 8, 4.5), (11, 6, 4.5), (-1, -11, 4)]
    hollow = [(dx, dy, r - 2.4) for dx, dy, r in lobes4]
    s4 = layers(('r', blob(lobes4 + [(0, 0, 6)])), ('o', blob([(dx, dy, r - 1.4) for dx, dy, r in lobes4] + [(0, 0, 5)])),
                ('y', blob([(0, 0, 3.5)])), ('H', blob([(0, 0, 2)])))
    for (x, y) in blob(hollow): s4.erase(x, y)            # the lobes open up: their centres are cut out
    f.append(s4)
    # 5-8: the shell has cracked; hand-drawn shards fly out along fixed rays while the core shrinks
    SHARDS = {
     'A': ("...rrr..", "..rooor.", ".rooyyor", "rooyyoor", ".rooooor", "..rrroor", "....rrr."),
     'B': ("rrr....", "rooor..", ".rooyr.", "..roooy", "...rooo", "....rrr"),
     'C': ("..rr..", ".roor.", "rooyor", "roooor", ".rooor", "..rrr."),
     'D': ("rrr.", "rooor", ".rooo", "..rrr"),
     'E': ("rrr", "roo", ".rr"),
     'F': ("rr", "ro"),
     'G': ("r",),
    }
    RAYS = [(-1.0, -0.55, 'A'), (0.95, -0.75, 'B'), (0.3, 1.0, 'C'), (-0.8, 0.8, 'D'), (1.0, 0.5, 'C'), (-0.15, -1.0, 'D'), (0.62, -0.1, 'E'), (-0.95, 0.05, 'E')]
    plan = [(10.0, 0), (12.5, 1), (14.0, 2), (15.0, 3)]                  # (distance from centre, shard size step down)
    DOWN = {'A': 'C', 'B': 'D', 'C': 'D', 'D': 'E', 'E': 'F', 'F': 'G', 'G': 'G'}
    cores = [(('r', 6), ('o', 4.5), ('y', 3), ('H', 1.5)), (('r', 4), ('o', 3), ('y', 1.5)), (('r', 2.5), ('o', 1.2)), ()]
    for k, (dist, step) in enumerate(plan):
        spr = layers(*[(c, blob([(0, 0, r)])) for (c, r) in cores[k]]) if cores[k] else Spr(32, 32)
        for (dx, dy, kind) in RAYS:
            for _ in range(step): kind = DOWN[kind]
            rows = SHARDS[kind]
            if k == 3 and kind == 'G' and (dx + dy) < 0: continue
            n = (dx * dx + dy * dy) ** 0.5
            px_, py_ = int(round(C + dx / n * dist - len(rows[0]) / 2)), int(round(C + dy / n * dist - len(rows) / 2))
            spr.stamp(px_, py_, list(rows))
        f.append(spr)
    # 9: two embers left, cooling to scorched brown
    s9 = Spr(32, 32)
    for (x, y, c) in ((2, 3, 'n'), (29, 5, 'n'), (28, 26, 'u'), (5, 28, 'n'), (1, 16, 'n'), (17, 1, 'u'), (24, 8, 'n')): s9.put(x, y, c)
    f.append(s9)
    return f


# ======================================================================== SHIELD RIPPLE (4 frames, 32x32, impact at the top centre)
# The shield is a big circle seen from outside (centre (16, 40), radius 34 => apex (16, 6)). A hit throws ripple
# rings along the shield skin: bright head 'H', then 'c', then 'b'. A soft glow layer fills the skin near the impact.
SC = (16.0, 40.0)
SR = 34.0


def skin(thick_in, thick_out=0.0):
    """cells within [-thick_in, +thick_out] of the shield circle."""
    cells = set()
    for y in range(32):
        for x in range(32):
            d = ((x + 0.5 - SC[0]) ** 2 + (y + 0.5 - SC[1]) ** 2) ** 0.5 - SR
            if -thick_in <= d <= thick_out: cells.add((x, y))
    return cells


def near(px, py, r_lo, r_hi):
    cells = set()
    for y in range(32):
        for x in range(32):
            d = ((x + 0.5 - px) ** 2 + (y + 0.5 - py) ** 2) ** 0.5
            if r_lo <= d <= r_hi: cells.add((x, y))
    return cells


IMPACT = (16, 6)


FLASH = [
 ("..cHc..", ".cHHHc.", "cHHHHHc", ".cHHHc.", "..cHc.."),
 (".cHc.", "cHHHc", ".cHc."),
 ("..c..", ".cHc.", "..c.."),
]


def shield_frames():
    out = []
    lead = skin(1.7, 0.4)          # bright leading edge of the ripple, a ~2px skin
    wake = skin(3.2, 0.4)          # the lit shield skin behind it
    for i, r in enumerate((5, 10, 15, 20)):
        spr = Spr(32, 32)
        inside = near(*IMPACT, 0, r - 2)
        for (x, y) in wake & inside: spr.put(x, y, 'b')
        for (x, y) in lead & near(*IMPACT, 0, r - 3): spr.put(x, y, 'c')
        for (x, y) in lead & near(*IMPACT, r - 3, r): spr.put(x, y, 'H' if i < 3 else 'c')       # bright leading edge
        if i >= 2:                                                                               # a second, fainter ring trails the first
            for (x, y) in lead & near(*IMPACT, r - 9, r - 7.2): spr.put(x, y, 'b')
        if i == 3:                                                                               # broken up: dashes only
            for (x, y) in list(spr.mask()):
                if (x // 2 + y) % 3 == 0 and spr.get(x, y) == 'b': spr.erase(x, y)
        if i < 3:
            fl = FLASH[i]
            spr.stamp(IMPACT[0] - len(fl[0]) // 2, IMPACT[1] - len(fl) // 2 + 1, list(fl))
        out.append(spr)
    return out


# ======================================================================== HEAT SHIMMER (3 frames, 16x16, translucent overlay)
# Rising dashes of pale heat that wobble sideways. Alpha layer, palette hues only: steel highlight with a little amber low down.
WAVE = (0, 1, 1, 0, -1, -1)


def shimmer_frames():
    frames = []
    for f in range(3):
        o = Rgba(16, 16)
        for ci, cx in enumerate((3, 7, 11)):
            for y in range(1, 15):
                ph = (y + f * 2 + ci * 2) % 6
                if ph < 3:                                                     # 3 on, 3 off: dashes that climb frame by frame
                    x = cx + WAVE[(y + ci + f) % 6]
                    a = 60 if ph == 0 or ph == 2 else 110
                    col = RGB['y'] if y > 10 else RGB['L']
                    o.set(x, y, col + (a,))
        frames.append(o)
    return frames


# ======================================================================== GLOW LAYERS for the effects
def tile_glow(frames, **kw):
    return [halo(f, f.w + 8, f.h + 8, 4, 4, **kw) for f in frames]
