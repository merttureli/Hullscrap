"""Preview for the shaped walls, ram plating and exterior hull skin: every shape cell at 4x, the orientations, and a mock ship
(about 20x12 cells: pointed bow of slope2 pieces with a ram-plated prow, round2 stern corners, slope45 sides) shown as an
interior and below it with the exterior hull skin over it, as in combat. It reads the DELIVERED PNG / JSON files back, so it
also proves the sheet layouts documented in the JSON.
Run:  python3 art/_src/preview_shapes.py <out.png> [components dir with engine_mk1.png, reactor_mk1.png ... (optional)]"""
import os, sys, json
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from px import *
from build import read_png, ART
import shapes as SH
from shapes import SHAPE_CELLS, row_of, oriented, piece_cells, edge_run, SIDE_DIR, OPP, N, E, S_, W_

NC = len(SHAPE_CELLS)
_cache = {}


def load(rel, base=None):
    key = (base or ART, rel)
    if key not in _cache:
        w, h, rows = read_png(os.path.join(base or ART, rel))
        o = Rgba(w, h)
        for y in range(h):
            for x in range(w): o.p[y][x] = list(rows[y][x * 4:x * 4 + 4])
        _cache[key] = o
    return _cache[key]


def crop(o, x, y, w, h):
    f = Rgba(w, h)
    for j in range(h):
        for i in range(w): f.p[j][i] = list(o.p[y + j][x + i])
    return f


def rot90(f):                                    # clockwise, lossless
    n = Rgba(f.h, f.w)
    for y in range(f.h):
        for x in range(f.w): n.p[x][f.h - 1 - y] = list(f.p[y][x])
    return n


def tint(f, mul):
    n = Rgba(f.w, f.h)
    for y in range(f.h):
        for x in range(f.w):
            p = f.p[y][x]
            n.p[y][x] = [min(255, int(p[0] * mul[0])), min(255, int(p[1] * mul[1])), min(255, int(p[2] * mul[2])), p[3]] if p[3] else [0, 0, 0, 0]
    return n


def add_glow(cv, g, x, y, k, col_mul=None):
    """additive glow blit."""
    for j in range(g.h):
        for i in range(g.w):
            p = g.p[j][i]
            if p[3] == 0: continue
            r, gg, b = (p[0] * col_mul[0], p[1] * col_mul[1], p[2] * col_mul[2]) if col_mul else p[:3]
            a = p[3] / 255.0
            for dy in range(k):
                for dx in range(k):
                    X, Y = x + i * k + dx, y + j * k + dy
                    if 0 <= X < cv.w and 0 <= Y < cv.h:
                        d = cv.p[Y][X]
                        d[0] = min(255, int(d[0] + r * a)); d[1] = min(255, int(d[1] + gg * a)); d[2] = min(255, int(d[2] + b * a))


# ---------------------------------------------------------------- frame access (the documented layouts)
class Sheets:
    def __init__(s):
        s.walls = {'std': load('tiles/walls.png'), 'armor': load('tiles/walls_armor.png'), 'ram': load('tiles/walls_ram.png')}
        s.shape = {'std': load('tiles/walls_shapes.png'), 'armor': load('tiles/walls_armor_shapes.png'), 'ram': load('tiles/walls_ram_shapes.png')}
        s.skin, s.skin_shape = load('tiles/hull_skin.png'), load('tiles/hull_skin_shapes.png')
        s.skin_glow, s.skin_shape_glow = load('tiles/hull_skin_glow.png'), load('tiles/hull_skin_shapes_glow.png')
        s.decals, s.decal_glow = load('tiles/hull_skin_decals.png'), load('tiles/hull_skin_decals_glow.png')
        s.dmeta = json.load(open(os.path.join(ART, 'tiles/hull_skin_decals.json')))['rects']
        s.floor = [crop(load('tiles/floor.png'), i * 16, 0, 16, 16) for i in range(3)]
        s.door = crop(load('tiles/door.png'), 0, 0, 32, 16)

    def wall(s, mat, mask): return crop(s.walls[mat], mask * 16, 0, 16, 16)
    def wall_shape(s, mat, name, o, mask): return crop(s.shape[mat], mask * 16, row_of(o, name) * 16, 16, 16)
    def skin_full(s, space, var=0): return crop(s.skin, space * 16, var * 16, 16, 16)
    def skin_cell(s, name, o, space): return crop(s.skin_shape, space * 16, row_of(o, name) * 16, 16, 16)
    def glow_full(s, space): return crop(s.skin_glow, space * 22, 0, 22, 22)
    def glow_cell(s, name, o, space): return crop(s.skin_shape_glow, space * 22, row_of(o, name) * 22, 22, 22)
    def decal(s, name):
        x, y, w, h = s.dmeta[name]
        return crop(s.decals, x, y, w, h), crop(s.decal_glow, x, y, w, h)


# ---------------------------------------------------------------- the mock ship
class Ship:
    """cells[(x, y)] = dict(t='wall'|'shape'|'door'|'floor', mat, name, o). Pieces are placed with the documented transform."""
    def __init__(s):
        s.c = {}

    def wall(s, x, y, mat='std'): s.c[(x, y)] = dict(t='wall', mat=mat)
    def floor(s, x, y): s.c.setdefault((x, y), dict(t='floor'))
    def door(s, x, y, vertical=False): s.c[(x, y)] = dict(t='door', vertical=vertical)

    def shape(s, name, x, y, o, mat='std'): s.c[(x, y)] = dict(t='shape', mat=mat, name=name, o=o)

    def piece(s, piece, x, y, o, mat='std'):
        cells, _ = piece_cells(piece, o)
        for (cx, cy, name) in cells: s.shape(name, x + cx, y + cy, o, mat)

    def region(s, p):
        c = s.c.get(p)
        if not c: return None
        if c['t'] in ('wall', 'door'): return SH.base_region('full')
        if c['t'] == 'shape': return oriented(c['name'], c['o'])
        return None

    def cover(s, p, side):
        """fraction of my flat edge (cell p, side) that the neighbour's solid covers; kind of neighbour."""
        reg = s.region(p)
        mine = edge_run(reg, side)
        q = (p[0] + SIDE_DIR[side][0], p[1] + SIDE_DIR[side][1])
        nb = s.c.get(q)
        if not mine: return 0.0, nb
        nr = s.region(q)
        if nr is None: return 0.0, nb
        theirs = {(x, y) for (x, y) in edge_run(nr, OPP[side])}
        sx = {E: 0, W_: 15}.get(side)
        m = 0
        for (x, y) in mine:
            tp = ((0 if side == E else 15), y) if side in (E, W_) else (x, (0 if side == S_ else 15))
            if tp in theirs: m += 1
        return m / float(len(mine)), nb

    def solid_mask(s, p):
        m = 0
        for bit, side in ((N, N), (E, E), (S_, S_), (W_, W_)):
            f, nb = s.cover(p, side)
            if f >= 0.6: m |= bit
        return m

    def space_mask(s, p):
        m = 0
        for side in (N, E, S_, W_):
            f, nb = s.cover(p, side)
            if f >= 0.6: continue
            if nb is not None and nb['t'] in ('floor',): continue
            m |= side
        return m

    def hull_cells(s): return [p for p, c in s.c.items() if c['t'] in ('wall', 'shape')]


def build_ship():
    sh = Ship()
    # stern: rounded corners (round2: rot 0 is the rounded TOP-LEFT corner, rot 3 the BOTTOM-LEFT one)
    sh.piece('round2', 0, 2, 0); sh.piece('round2', 0, 8, 3)
    for y in range(4, 8): sh.wall(0, y)
    for x in range(2, 12): sh.wall(x, 2); sh.wall(x, 9)
    # dorsal bridge tower: slope45 sides, a roof, a hollow floor reached by a door in the top wall
    sh.shape('tri', 7, 0, 3); sh.shape('tri', 10, 0, 0); sh.wall(8, 0); sh.wall(9, 0)
    sh.shape('tri', 6, 1, 3); sh.shape('tri', 11, 1, 0)
    sh.door(8, 2); sh.door(9, 2)
    # ventral keel in armour plate: a trapezoid with two slope45 sides
    sh.shape('tri', 3, 10, 2, 'armor'); sh.shape('tri', 7, 10, 1, 'armor')
    for x in (4, 5, 6): sh.wall(x, 10, 'armor')
    # bow: slope2 ramps, two in standard plate, the third in ram plating, then a ram prow with 45 degree chamfers
    for k in range(2):
        sh.piece('slope2', 12 + 2 * k, 2 + k, 4)             # upper ramp: mirrored (descends to the right)
        sh.piece('slope2', 12 + 2 * k, 9 - k, 2)             # lower ramp: turned 180 (rises to the right)
    sh.piece('slope2', 16, 4, 4, 'ram'); sh.piece('slope2', 16, 7, 2, 'ram')
    sh.wall(18, 5, 'ram'); sh.wall(18, 6, 'ram'); sh.shape('tri', 19, 5, 0, 'ram'); sh.shape('tri', 19, 6, 1, 'ram')
    # interior
    spans = {1: (7, 10), 3: (2, 13), 4: (1, 15), 5: (1, 17), 6: (1, 17), 7: (1, 15), 8: (2, 13)}
    for y, (a, b) in spans.items():
        for x in range(a, b + 1): sh.floor(x, y)
    for x in (6, 12):                                        # bulkheads with a door each
        for y in range(3, 9): sh.wall(x, y)
        sh.door(x, 5, True); sh.door(x, 6, True)
    return sh


COMPONENTS = [('engine_mk1', -4, 4, 4, 2), ('engine_mk1', -4, 6, 4, 2), ('reactor_mk1', 7, 4, 4, 4), ('oxygen_gen', 4, 4, 2, 4), ('helm', 16, 5, 2, 2), ('radiator', 13, 6, 2, 2)]
_ST = SH.SUGGESTED_TINTS
TINTS = {k: tuple(c / 255.0 for c in _ST[k]) for k in ('standard', 'scrap', 'neon')}
ARMOR_TINT = tuple(c / 255.0 for c in _ST['armor_plate'])
NEON_GLOW = tuple(c / 255.0 for c in _ST['edge_glow_neon'])
LAMP_GLOW = tuple(c / 255.0 for c in _ST['lamp_glow'])
DECAL_SPOTS = [('vent', (3, 2)), ('hatch', (6, 9)), ('light_on', (11, 9)), ('vent', (8, 9)), ('antenna', (9, 0)), ('light_on', (12, 2)), ('hatch', (11, 2)), ('light_on', (2, 9)), ('light_on', (14, 3))]


def comp_frame(comp_dir, name, w, h):
    sp = load(name + '.png', comp_dir)
    return crop(sp, 0, 0, w * 16, h * 16)


def render_ship(sh, S, view, k, line='standard', comp_dir=None, frame=0, ox=4, oy=1, W=25, H=14):
    """view = 'interior' or 'combat'. Returns an Rgba of W x H cells at k x."""
    cv = Rgba(W * 16 * k, H * 16 * k, RGB['K'] + (255,))
    for (sx, sy) in SPACE_STARS:                                    # fixed star field
        if sx < cv.w - 2 and sy < cv.h - 2:
            cv.fill(sx, sy, k, k, RGB['W'] + (255,) if (sx + sy) % 3 else RGB['S'] + (255,))
    def at(p): return ((p[0] + ox) * 16 * k, (p[1] + oy) * 16 * k)
    for p, c in sh.c.items():
        if c['t'] in ('floor', 'door'):
            x, y = at(p)
            cv.blit_rgba(S.floor[(p[0] * 7 + p[1] * 13) % 5 % 3 if (p[0] + p[1]) % 4 == 0 else 0], x, y, k)
    mul = ARMOR_TINT
    for p in sorted(sh.hull_cells()):
        c = sh.c[p]; x, y = at(p)
        mask = sh.solid_mask(p)
        f = S.wall(c['mat'], mask) if c['t'] == 'wall' else S.wall_shape(c['mat'], c['name'], c['o'], mask)
        if c['mat'] == 'armor': f = tint(f, mul)
        cv.blit_rgba(f, x, y, k)
    for p, c in sh.c.items():
        if c['t'] != 'door': continue
        if c.get('vertical'):
            if (p[0], p[1] - 1) in sh.c and sh.c[(p[0], p[1] - 1)].get('vertical'): continue
            x, y = at(p); cv.blit_rgba(rot90(S.door), x, y, k)
        else:
            if (p[0] - 1, p[1]) in sh.c and sh.c[(p[0] - 1, p[1])]['t'] == 'door' and not sh.c[(p[0] - 1, p[1])].get('vertical'): continue
            x, y = at(p); cv.blit_rgba(S.door, x, y, k)
    if comp_dir:
        for (name, cx, cy, w, h) in COMPONENTS:
            try: f = comp_frame(comp_dir, name, w, h)
            except Exception: continue
            x, y = at((cx, cy)); cv.blit_rgba(f, x, y, k)
    if view == 'combat':
        if comp_dir:                                               # engine exhaust, hot orange
            try:
                g = load('engine_mk1_glow.png', comp_dir); gm = json.load(open(os.path.join(comp_dir, 'engine_mk1.json')))['glow']
                gw, gh = gm['frame']
                for (name, cx, cy, w, h) in COMPONENTS[:2]:
                    x, y = at((cx, cy)); add_glow(cv, crop(g, (frame % 3) * gw, 0, gw, gh), x + gm['offset'][0] * k, y + gm['offset'][1] * k, k)
            except Exception: pass
        mul = TINTS[line]
        tint_f = lambda f: tint(f, mul)
        for p in sorted(sh.hull_cells()):
            c = sh.c[p]; x, y = at(p)
            sp = sh.space_mask(p)
            if c['mat'] == 'ram':                                 # ram plating is already an exterior look: no skin over the hazard tape
                continue
            if c['t'] == 'shape' and len(sh.region(p)) == 256: c = dict(c, t='wall')    # round2's full cell is a plain wall cell
            if c['t'] == 'wall':
                if not sp: continue
                v = ((p[0] * 3 + p[1] * 5) % 4)
                cv.blit_rgba(tint_f(S.skin_full(sp, v)), x, y, k)
                if line == 'neon': add_glow(cv, S.glow_full(sp), x - 3 * k, y - 3 * k, k, NEON_GLOW)
            else:
                cv.blit_rgba(tint_f(S.skin_cell(c['name'], c['o'], sp)), x, y, k)
                if line == 'neon': add_glow(cv, S.glow_cell(c['name'], c['o'], sp), x - 3 * k, y - 3 * k, k, NEON_GLOW)
        for name, p in DECAL_SPOTS:                                # a few greebles, deterministic
            if p not in sh.c or sh.c[p]['mat'] == 'ram' or sh.c[p]['t'] != 'wall' or not sh.space_mask(p): continue
            d, dg = S.decal(name)
            if d.w == 32 and (p[0] + 1, p[1]) not in sh.c: continue
            x, y = at(p)
            cv.blit_rgba(tint_f(d), x, y, k)
            if name in ('light_on', 'antenna'): add_glow(cv, dg, x, y, k, LAMP_GLOW if line != 'neon' else NEON_GLOW)
    return cv


SPACE_STARS = [(37, 29), (91, 211), (143, 57), (203, 301), (257, 33), (311, 119), (389, 257), (433, 17), (479, 181), (541, 91), (599, 331), (647, 47), (701, 233), (757, 143), (811, 25),
               (863, 289), (919, 71), (977, 197), (1031, 337), (1087, 53), (1129, 241), (1181, 109), (23, 389), (61, 521), (127, 457), (199, 613), (271, 487), (347, 571), (421, 433), (503, 641),
               (577, 503), (653, 587), (727, 449), (787, 617), (853, 529), (907, 421), (971, 599), (1049, 479), (1103, 563), (1171, 431), (97, 349), (317, 211), (547, 263), (769, 359), (1013, 131)]


def label(cv, x, y, s, col='M', k=2): text(cv, x, y, s, col, k)


BG = (66, 72, 88, 255)


def panel(cv, x, y, w, h):
    cv.fill(x, y, w, h, RGB['D'] + (255,))
    for i in range(w): cv.over(x + i, y, RGB['W'] + (255,)); cv.over(x + i, y + h - 1, RGB['W'] + (255,))
    for j in range(h): cv.over(x, y + j, RGB['W'] + (255,)); cv.over(x + w - 1, y + j, RGB['W'] + (255,))


def box(cv, f, x, y, k, tint_mul=None):
    """a frame on a lit backdrop so dark plates read, with a 1px border."""
    if tint_mul: f = tint(f, tint_mul)
    cv.fill(x - 1, y - 1, f.w * k + 2, f.h * k + 2, RGB['W'] + (255,)); cv.fill(x, y, f.w * k, f.h * k, BG)
    cv.blit_rgba(f, x, y, k)


def piece_img(S, kind, mat, piece, o=0, mask=0b1111):
    cells, (w, h) = piece_cells(piece, o)
    f = Rgba(w * 16, h * 16)
    for (cx, cy, name) in cells:
        t = S.wall_shape(mat, name, o, mask) if kind == 'wall' else tint(S.skin_cell(name, o, 0), TINTS['standard'])
        f.blit_rgba(t, cx * 16, cy * 16)
    return f


def build(out, comp_dir=None):
    S = Sheets()
    k3 = 3
    sh = build_ship()
    inter = render_ship(sh, S, 'interior', k3, comp_dir=comp_dir)
    combat = render_ship(sh, S, 'combat', k3, 'standard', comp_dir=comp_dir)
    lw = inter.w + 24
    RW = 660
    Wt = max(lw + RW + 24, 2100)
    cv = Rgba(Wt, 3300, RGB['K'] + (255,))
    y = 8
    label(cv, 8, y, 'HULLSCRAP SHAPED WALLS, RAM PLATING AND EXTERIOR HULL SKIN   MOCK SHIP 20X12 CELLS AT 3X'); y += 26
    label(cv, 8, y, 'INTERIOR: ROUND2 STERN CORNERS, SLOPE2 BOW, SLOPE45 TOWER AND KEEL, RAM PRAW'); y += 18
    panel(cv, 8, y, inter.w + 8, inter.h + 8); cv.blit_rgba(inter, 12, y + 4, 1); y += inter.h + 18
    label(cv, 8, y, 'SAME SHIP IN COMBAT: EXTERIOR HULL SKIN, STANDARD LINE (THE RAM PRAW KEEPS ITS HAZARD TAPE)'); y += 18
    panel(cv, 8, y, combat.w + 8, combat.h + 8); cv.blit_rgba(combat, 12, y + 4, 1); y += combat.h + 18
    y_left = y
    # ---------------- right column
    rx, ry = lw + 8, 8
    names = SHAPE_CELLS
    short = {'tri': 'TRI', 'tri2_low': 'LOW', 'tri2_high': 'HIGH', 'arc_tl': 'ARC TL', 'arc_tr': 'ARC TR', 'arc_bl': 'ARC BL', 'arc_br': 'ARC BR'}
    label(cv, rx, ry, 'EVERY SHAPE CELL AT 4X, ROTATION 0'); ry += 16
    for i, n in enumerate(names): label(cv, rx + 8 + i * 68, ry, short[n], 'M', 1)
    ry += 10
    for (lbl, kind, mat) in (('WALLS', 'wall', 'std'), ('ARMOR (TINTED)', 'wall', 'armor'), ('RAM', 'wall', 'ram'), ('HULL SKIN (TINTED)', 'skin', None)):
        label(cv, rx + 8, ry, lbl, 'S', 1); ry += 9
        for i, n in enumerate(names):
            f = S.wall_shape(mat, n, 0, 0b1111) if kind == 'wall' else S.skin_cell(n, 0, 0)
            box(cv, f, rx + 8 + i * 68, ry, 4, ARMOR_TINT if mat == 'armor' else TINTS['standard'] if kind == 'skin' else None)
        ry += 68
    ry += 4
    label(cv, rx, ry, 'PIECES AT 4X: SLOPE45, SLOPE2, ROUND2'); ry += 16
    for (lbl, kind, mat) in (('WALLS', 'wall', 'std'), ('RAM', 'wall', 'ram'), ('HULL SKIN', 'skin', None)):
        label(cv, rx + 8, ry, lbl, 'S', 1); ry += 9
        bx = rx + 8
        for piece in ('slope45', 'slope2', 'round2'):
            f = piece_img(S, kind, mat, piece)
            box(cv, f, bx, ry, 4); bx += f.w * 4 + 12
        ry += 32 * 4 + 6
    ry += 2
    label(cv, rx, ry, 'ALL 8 ORIENTATIONS (MIRROR*4+ROT), LIT PER ORIENTATION, 2X'); ry += 16
    for piece in ('slope45', 'slope2', 'round2'):
        bx = rx + 8
        for o in range(8):
            f = piece_img(S, 'wall', 'std', piece, o)
            box(cv, f, bx, ry, 2); bx += 66 if piece != 'slope45' else 40
        ry += 70 if piece != 'slope45' else 38
    ry += 6
    label(cv, rx, ry, 'HULL SKIN AUTOTILE: 16 MASK FRAMES (BIT = FACES SPACE) X 4 PANEL VARIANTS, 2X'); ry += 16
    for v in range(4):
        for m in range(16):
            f = tint(S.skin_full(m, v), TINTS['standard'])
            box(cv, f, rx + 8 + m * 38, ry, 2)
        ry += 36
    ry += 6
    label(cv, rx, ry, 'GREEBLE DECALS 4X: VENT, ANTENNA, HATCH, LIGHT ON AND OFF'); ry += 16
    bx = rx + 8
    for name in ('vent', 'antenna', 'hatch', 'light_on', 'light_off'):
        d, dg = S.decal(name)
        cv.fill(bx, ry, d.w * 4, 64, (120, 128, 142, 255))
        cv.blit_rgba(tint(d, TINTS['standard']), bx, ry, 4)
        if name in ('light_on', 'antenna'): add_glow(cv, dg, bx, ry, 4, LAMP_GLOW)
        bx += d.w * 4 + 8
    ry += 72
    y = max(y_left, ry) + 6
    # ---------------- close-ups and culture lines, full width
    r4 = render_ship(sh, S, 'combat', 4, 'standard', comp_dir=comp_dir)
    label(cv, 8, y, 'CLOSE-UPS IN COMBAT, 4X: ROUND2 STERN WITH ENGINES, SLOPE45 KEEL AND TOWER, SLOPE2 BOW, RAM PRAW'); y += 18
    st = crop(r4, 0, 1 * 64, 13 * 64, 11 * 64)
    panel(cv, 8, y, st.w + 8, st.h + 8); cv.blit_rgba(st, 12, y + 4, 1)
    bw = crop(r4, (4 + 10) * 64, 1 * 64, 11 * 64, 11 * 64)
    panel(cv, 8 + st.w + 24, y, bw.w + 8, bw.h + 8); cv.blit_rgba(bw, 12 + st.w + 24, y + 4, 1)
    y += st.h + 24
    label(cv, 8, y, 'ONE SKIN, THREE CULTURE LINES (MULTIPLY TINT; NEON ADDS THE EDGE GLOW LAYER), 2X'); y += 18
    xs = 8
    for line, nm in (('scrap', 'SCRAP'), ('standard', 'STANDARD'), ('neon', 'NEON')):
        r = render_ship(sh, S, 'combat', 2, line, comp_dir=comp_dir)
        c2 = crop(r, 3 * 32, 0, 22 * 32, 14 * 32)
        panel(cv, xs, y, c2.w + 8, c2.h + 8); cv.blit_rgba(c2, xs + 4, y + 4, 1)
        label(cv, xs + 12, y + c2.h - 8, nm, 'M', 2)
        xs += c2.w + 14
    y += 14 * 32 + 24
    cv.p = cv.p[:y]; cv.h = y
    cv.save(out)
    print('wrote', out, Wt, y)


if __name__ == '__main__':
    out = sys.argv[1] if len(sys.argv) > 1 else 'shapes_sheet.png'
    comp = sys.argv[2] if len(sys.argv) > 2 else (os.path.join(ART, 'components') if os.path.isdir(os.path.join(ART, 'components')) else None)
    build(out, comp)
