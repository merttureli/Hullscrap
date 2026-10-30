"""Preview sheet: reads the delivered PNG/JSON files back and lays everything out at 3x, with a composed mini interior.
Run: python3 art/_src/preview.py <out.png>"""
import os, sys, json
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from px_structure import *
from build import read_png, ART
import tiles as T
from scene import solid_mask

K3 = 3


def load(rel):
    w, h, rows = read_png(os.path.join(ART, rel))
    o = Rgba(w, h)
    for y in range(h):
        for x in range(w): o.p[y][x] = list(rows[y][x * 4:x * 4 + 4])
    return o


def meta(rel): return json.load(open(os.path.join(ART, rel[:-4] + '.json')))


def split(o, fw, fh):
    out = []
    for i in range(o.w // fw):
        f = Rgba(fw, fh)
        for y in range(fh):
            for x in range(fw): f.p[y][x] = list(o.p[y][i * fw + x])
        out.append(f)
    return out


def frames(rel):
    fw, fh = meta(rel)['frame']
    return split(load(rel), fw, fh)


def glow_frames(rel):
    g = meta(rel)['glow']
    return split(load('/'.join(rel.split('/')[:-1]) + '/' + g['image']), *g['frame']), g['offset']


STARS = [(3, 5), (17, 40), (33, 9), (50, 70), (71, 22), (90, 51), (112, 8), (130, 66), (150, 30), (170, 77), (188, 14), (205, 55), (226, 36), (250, 6), (268, 62), (290, 24), (305, 80), (320, 44),
         (350, 12), (372, 58), (395, 28), (420, 72), (445, 10), (470, 48), (493, 20), (515, 64), (540, 34), (560, 8), (585, 52), (610, 26), (630, 70), (650, 14), (680, 40), (700, 66)]


def space(cv, x, y, w, h, k=1):
    cv.fill(x, y, w, h, RGB['K'] + (255,))
    for (sx, sy) in STARS:
        if sx * 2 < w and sy * 2 < h:
            cv.over(x + sx * 2, y + sy * 2, RGB['W'] + (255,))
            if (sx + sy) % 3 == 0: cv.over(x + sx * 2 + 1, y + sy * 2, RGB['W'] + (255,))


def panel(cv, x, y, w, h):
    for j in range(h):
        for i in range(w):
            edge = i < 2 or j < 2 or i >= w - 2 or j >= h - 2
            cv.over(x + i, y + j, RGB['W' if edge else 'D'] + (255,))


def label(cv, x, y, s): text(cv, x, y, s, 'M', 2)


def put(cv, f, x, y, k=K3): cv.blit_rgba(f, x, y, k)


def build_interior():
    lay = [
        "####################",
        "#..................#",
        "#..................#",
        "#..................#",
        "#..................#",
        "########dd##########",
        "#........#.........#",
        "#........#.........#",
        "#..................#",
        "#........#.........#",
        "####################",
    ]
    gh, gw = len(lay), len(lay[0])
    cv = Rgba(gw * 16, gh * 16)
    floors = frames('tiles/floor.png')
    walls = frames('tiles/walls.png')
    door = frames('tiles/door.png')
    breach = frames('tiles/breach.png')
    cab_off, cab_on = frames('tiles/cable.png'), frames('tiles/cable_on.png')
    cab_glow = split(load('tiles/cable_glow.png'), 16, 16)
    fire = frames('fx/fire.png'); smoke = frames('fx/smoke.png'); sparks = frames('fx/sparks.png')
    fire_g, fo = glow_frames('fx/fire.png')
    solid = '#d'
    for y, row in enumerate(lay):
        for x, ch in enumerate(row):
            if ch in '.d': cv.blit_rgba(floors[(x * 5 + y * 3) % 7 % 3 if (x + y) % 4 == 0 else 0], x * 16, y * 16)
    for y, row in enumerate(lay):
        for x, ch in enumerate(row):
            if ch == '#': cv.blit_rgba(walls[solid_mask(lay, x, y, solid)], x * 16, y * 16)
    cv.blit_rgba(door[2], 8 * 16, 5 * 16)                                         # a door caught mid-open
    # cables: a powered run in the top room (green), a dull unpowered one in the bottom room
    def run(cells, on):
        s = set(cells)
        for (x, y) in cells:
            m = 0
            for bit, (dx, dy) in ((1, (0, -1)), (2, (1, 0)), (4, (0, 1)), (8, (-1, 0))):
                if (x + dx, y + dy) in s: m |= bit
            cv.blit_rgba((cab_on if on else cab_off)[m], x * 16, y * 16)
            if on: cv.blit_rgba(cab_glow[m], x * 16, y * 16)
    run([(2, 1), (2, 2), (2, 3), (3, 3), (4, 3), (5, 3), (6, 3), (7, 3), (8, 3), (8, 4)], True)
    run([(12, 6), (12, 7), (12, 8), (13, 8), (14, 8), (15, 8), (15, 7)], False)
    # breaches in the hull (over wall cells) and one on the floor
    cv.blit_rgba(breach[1], 14 * 16, 0 * 16)
    cv.blit_rgba(breach[0], 19 * 16, 6 * 16)
    cv.blit_rgba(breach[2], 16 * 16, 9 * 16 - 8)
    # a fire with smoke, sparks on a cut cable
    for (fx_, fy_, i) in ((4, 8, 0), (5, 8, 2), (4, 7, 1)):
        cv.blit_rgba(fire[i], fx_ * 16, fy_ * 16)
    for (fx_, fy_, i) in ((4, 8, 0), (5, 8, 2), (4, 7, 1)):
        cv.blit_rgba(fire_g[i], fx_ * 16 + fo[0], fy_ * 16 + fo[1])
    cv.blit_rgba(smoke[1], 4 * 16, 6 * 16 - 2); cv.blit_rgba(smoke[2], 5 * 16 - 4, 6 * 16 - 14)
    cv.blit_rgba(sparks[0], 12 * 16, 8 * 16 - 8)
    return cv


def build():
    W = 1600
    cv = Rgba(W, 1500, RGB['K'] + (255,))
    y = 8
    label(cv, 8, y, 'HULLSCRAP STRUCTURE ART  3X  FLOOR WALLS DOOR BREACH CABLE FX PROJECTILES'); y += 22
    # ---- interior
    inter = build_interior()
    ix, iy = 8, y
    panel(cv, ix, iy, inter.w * K3 + 24, inter.h * K3 + 24)
    space(cv, ix + 12 - 0, iy + 12, 0, 0)
    cv.blit_rgba(inter, ix + 12, iy + 12, K3)
    label(cv, ix + 12, iy + inter.h * K3 + 26 - 12, '')
    # ---- right column: floor variants, breaches, doors
    rx = ix + inter.w * K3 + 24 + 16
    ry = iy
    label(cv, rx, ry, 'FLOOR X3 VARIANTS'); ry += 14
    fr = frames('tiles/floor.png')
    for i, f in enumerate(fr): put(cv, f, rx + i * 56, ry)
    for i, f in enumerate(frames('tiles/breach.png')):
        fl = frames('tiles/floor.png')[0]; put(cv, fl, rx + 184 + i * 56, ry); put(cv, f, rx + 184 + i * 56, ry)
    label(cv, rx + 184, ry - 14, 'BREACH X3'); ry += 64
    label(cv, rx, ry, 'DOOR  CLOSED TO OPEN 5F  LOCKED  BROKEN'); ry += 14
    dg, doff = glow_frames('tiles/door.png')
    for i, f in enumerate(frames('tiles/door.png')):
        bx = rx + (i % 4) * 104; by = ry + (i // 4) * 60
        for xx in range(0, 32, 16): put(cv, fr[0], bx + xx * K3, by)
        put(cv, f, bx, by); put(cv, dg[i], bx + doff[0] * K3, by + doff[1] * K3)
    ry += 124
    label(cv, rx, ry, 'FIRE 4F + SMOKE 4F'); ry += 14
    fire, smoke = frames('fx/fire.png'), frames('fx/smoke.png')
    fg, fo = glow_frames('fx/fire.png')
    for i in range(4):
        put(cv, fr[0], rx + i * 52, ry); put(cv, fire[i], rx + i * 52, ry); put(cv, fg[i], rx + i * 52 + fo[0] * K3, ry + fo[1] * K3)
    for i in range(4):
        put(cv, fr[0], rx + 220 + i * 52, ry); put(cv, smoke[i], rx + 220 + i * 52, ry)
    ry += 56
    y = iy + inter.h * K3 + 24 + 14
    # ---- wall autotiles
    label(cv, 8, y, 'WALLS  MASK N1 E2 S4 W8  16F'); label(cv, 8 + 788, y, 'WALLS ARMOR 16F  FRAMES 0-7 PLAIN  8-15 TINTED');  y += 14
    for i, f in enumerate(frames('tiles/walls.png')):
        put(cv, fr[0], 8 + i * 49, y); put(cv, f, 8 + i * 49, y)
    ar = frames('tiles/walls_armor.png')
    for i, f in enumerate(ar[:8]): put(cv, fr[0], 8 + 788 + i * 49, y); put(cv, f, 8 + 788 + i * 49, y)
    tint = (110, 150, 230)
    for i, f in enumerate(ar[8:]):
        g = Rgba(16, 16)
        for yy in range(16):
            for xx in range(16):
                p = f.p[yy][xx]
                g.p[yy][xx] = [p[0] * tint[0] // 255, p[1] * tint[1] // 255, p[2] * tint[2] // 255, p[3]] if p[3] else [0, 0, 0, 0]
        put(cv, fr[0], 8 + 788 + i * 49, y + 52); put(cv, g, 8 + 788 + i * 49, y + 52)
    y += 112
    label(cv, 8, y, 'CABLE OFF  FLOOR UNDERNEATH  AND ON WITH GLOW  16F'); y += 14
    co, cn = frames('tiles/cable.png'), frames('tiles/cable_on.png')
    cg = split(load('tiles/cable_glow.png'), 16, 16)
    for i in range(8):
        pass
    for i, f in enumerate(co):
        put(cv, fr[0], 8 + i * 49, y); put(cv, f, 8 + i * 49, y)
    for i, f in enumerate(cn):
        put(cv, fr[0], 8 + 788 + i * 49, y); put(cv, f, 8 + 788 + i * 49, y); put(cv, cg[i], 8 + 788 + i * 49, y)
    y += 58
    # ---- fx row on space
    label(cv, 8, y, 'SPARKS 3F   MUZZLE 3F UP   HEAT SHIMMER 3F   SHIELD RIPPLE 4F'); y += 14
    space(cv, 8, y, W - 16, 112)
    x = 20
    sp = frames('fx/sparks.png')
    for i, f in enumerate(sp): put(cv, f, x + i * 52, y + 30)
    x += 170
    mz = frames('fx/muzzle.png'); mg, mo = glow_frames('fx/muzzle.png')
    for i, f in enumerate(mz): put(cv, f, x + i * 56, y + 30); put(cv, mg[i], x + i * 56 + mo[0] * K3, y + 30 + mo[1] * K3)
    x += 190
    hs = frames('fx/heat_shimmer.png')
    for i, f in enumerate(hs):
        put(cv, fr[0], x + i * 52, y + 30); put(cv, f, x + i * 52, y + 30)
    x += 180
    sr = frames('fx/shield_ripple.png'); sg, so = glow_frames('fx/shield_ripple.png')
    for i, f in enumerate(sr): put(cv, sg[i], x + i * 104, y + 8); put(cv, f, x + i * 104, y + 8)
    y += 120
    # ---- explosion strip
    label(cv, 8, y, 'EXPLOSION 10F 32X32 WITH GLOW'); y += 14
    space(cv, 8, y, W - 16, 104)
    ex = frames('fx/explosion.png'); eg, eo = glow_frames('fx/explosion.png')
    for i, f in enumerate(ex):
        put(cv, eg[i], 16 + i * 156 + eo[0] * K3, y + 4 + eo[1] * K3)
        put(cv, f, 16 + i * 156, y + 4)
    y += 112
    # ---- projectiles
    label(cv, 8, y, 'PROJECTILES  LASER TILED + IMPACT   BOLT 4F   FLAK 2F   MISSILE 3F   BEAM TILED 3F + IMPACT'); y += 14
    space(cv, 8, y, W - 16, 190)
    x, py = 28, y + 8
    lg, lo = glow_frames('projectiles/laser.png'); ls = frames('projectiles/laser.png')[0]
    for t in range(3):
        put(cv, lg[0], x + lo[0] * K3, py + t * 48 + lo[1] * K3); 
    for t in range(3): put(cv, ls, x, py + t * 48)
    x += 56
    li = frames('projectiles/laser_impact.png'); lig, lio = glow_frames('projectiles/laser_impact.png') if False else (split(load('projectiles/laser_impact_glow.png'), 24, 24), (-4, -4))
    for i, f in enumerate(li):
        put(cv, lig[i], x + i * 56 + lio[0] * K3, py + 20 + lio[1] * K3); put(cv, f, x + i * 56, py + 20)
    x += 190
    bf = frames('projectiles/bolt.png'); bg, bo = glow_frames('projectiles/bolt.png')
    for i, f in enumerate(bf): put(cv, bg[i], x + i * 44 + bo[0] * K3, py + 20 + bo[1] * K3); put(cv, f, x + i * 44, py + 20)
    x += 190
    fk = frames('projectiles/flak.png'); fkg, fko = glow_frames('projectiles/flak.png')
    for i, f in enumerate(fk): put(cv, fkg[i], x + i * 44 + fko[0] * K3, py + 20 + fko[1] * K3); put(cv, f, x + i * 44, py + 20)
    x += 120
    ms = frames('projectiles/missile.png'); mg2, mo2 = glow_frames('projectiles/missile.png')
    for i, f in enumerate(ms): put(cv, mg2[i], x + i * 56 + mo2[0] * K3, py + 10 + mo2[1] * K3); put(cv, f, x + i * 56, py + 10)
    x += 190
    bm = frames('projectiles/beam.png'); bgl, bgo = glow_frames('projectiles/beam.png')
    for i, f in enumerate(bm):
        for t in range(3): put(cv, bgl[i], x + i * 64 + bgo[0] * K3, py + t * 48 + bgo[1] * K3)
        for t in range(3): put(cv, f, x + i * 64, py + t * 48)
    x += 230
    bi = frames('projectiles/beam_impact.png'); big = split(load('projectiles/beam_impact_glow.png'), 24, 24)
    for i, f in enumerate(bi): put(cv, big[i], x + i * 56 - 12, py + 20 - 12); put(cv, f, x + i * 56, py + 20)
    y += 200
    return cv, y


if __name__ == '__main__':
    out = sys.argv[1]
    cv, h = build()
    cv.p = cv.p[:h]; cv.h = h
    cv.save(out)
    print('wrote', out, cv.w, cv.h)
