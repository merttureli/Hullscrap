"""Structure tiles: floor, walls (+armour), door, breach, cable. 1 cell = 16x16 source px."""
from px_structure import *

N, E, S_, W_ = 1, 2, 4, 8          # autotile mask bits: neighbour is also solid


# ======================================================================== FLOOR (3 variants, seamless)
def floor_variants():
    base = Spr(16, 16)
    base.rect(0, 0, 16, 16, 'F')
    base.hline(0, 0, 16, 'G'); base.vline(0, 0, 16, 'G')                 # 1px tile seam on top + left
    v0 = base.copy()
    v1 = base.copy()                                                      # scuffed: a catch-light fleck and a dark scrape
    v1.put(5, 4, 'S'); v1.put(6, 4, 'S')
    v1.put(11, 10, 'G'); v1.put(12, 10, 'G'); v1.put(12, 11, 'G')
    v2 = base.copy()                                                      # bolted plate: two rivets on the diagonal
    for (x, y) in ((3, 3), (12, 12)):
        v2.put(x, y, 'S'); v2.put(x + 1, y + 1, 'G')
    return [v0, v1, v2]


# ======================================================================== WALLS
# Convex-corner patches, 4x4, drawn where two neighbouring sides are both open (chamfered outer corner).
CORNER = {
 'NW': ("..KK", ".KEE", "KEDD", "KEDD"),
 'NE': ("KK..", "EEK.", "DDKK", "DDKK"),
 'SW': ("KEDD", "KEDD", ".KKK", "..KK"),
 'SE': ("DDKK", "DDKK", "KKK.", "KK.."),
}
CORNER_POS = {'NW': (0, 0), 'NE': (12, 0), 'SW': (0, 12), 'SE': (12, 12)}


def wall_standard(mask):
    n, e, s, w = [bool(mask & b) for b in (N, E, S_, W_)]      # neighbour solid?
    t = Spr(16, 16)
    t.rect(0, 0, 16, 16, 'D')
    # panel joints with solid neighbours: lit lip on the north/west, dark seam on the south/east
    y0 = 2 if not n else 0
    y1 = 14 if not s else 16
    x0 = 2 if not w else 0
    x1 = 14 if not e else 16
    if e: t.vline(15, y0, y1 - y0, 'K')
    if w: t.vline(0, y0, y1 - y0, 'E')
    if s: t.hline(x0, 15, x1 - x0, 'K')
    if n: t.hline(x0, 0, x1 - x0, 'E')
    # rivets beside the joints only (a pair on the east joint, a pair on the south joint)
    if e:
        for ry in (y0 + 2, y1 - 3): t.put(13, ry, 'W')
    if s:
        for rx in (x0 + 2, x1 - 3): t.put(rx, 13, 'W')
    # open edges: dark outline, lighter lip facing the light (north / west), 2px shadow (south / east)
    if not n: t.hline(0, 0, 16, 'K'); t.hline(0, 1, 16, 'E')
    if not w: t.vline(0, 0, 16, 'K'); t.vline(1, 0, 16, 'E')
    if not s: t.hline(0, 14, 16, 'K'); t.hline(0, 15, 16, 'K')
    if not e: t.vline(14, 0, 16, 'K'); t.vline(15, 0, 16, 'K')
    for key, (a, b) in (('NW', (n, w)), ('NE', (n, e)), ('SW', (s, w)), ('SE', (s, e))):
        if not a and not b:
            cx, cy = CORNER_POS[key]
            for j, row in enumerate(CORNER[key]):
                for i, c in enumerate(row):
                    if c == '.': t.erase(cx + i, cy + j)
                    else: t.g[cy + j][cx + i] = c
    return t


def wall_armor(mask):
    """Heavier plate: neutral greys (the game multiplies a material tint over them). Corrugated ribs between four
    corner bolts, a 2px bevel (lit north/west, shaded south/east). Outline and chamfer only where a side is open."""
    n, e, s, w = [bool(mask & b) for b in (N, E, S_, W_)]
    t = Spr(16, 16)
    t.rect(0, 0, 16, 16, 'S')
    t.hline(0, 0, 16, 'L'); t.vline(0, 0, 16, 'L'); t.hline(1, 1, 15, 'M'); t.vline(1, 1, 15, 'M')
    t.hline(0, 15, 16, 'E'); t.vline(15, 0, 16, 'E'); t.hline(1, 14, 14, 'W'); t.vline(14, 1, 14, 'W')
    for ry in (4, 7, 10):                                          # corrugation: lit rib over a shaded groove
        t.hline(4, ry, 8, 'M'); t.hline(4, ry + 1, 8, 'W')
        t.put(3, ry, 'S'); t.put(12, ry, 'S')
    for (bx, by) in ((2, 2), (12, 2), (2, 12), (12, 12)):          # corner bolts: bright dome, dark seat
        t.rect(bx, by, 2, 2, 'W'); t.put(bx, by, 'H'); t.put(bx + 1, by + 1, 'E')
    # plates next door: a dark seam on the south/east, a lit seam on the north/west
    if e: t.vline(15, 0, 16, 'K')
    if s: t.hline(0, 15, 16, 'K')
    if w: t.vline(0, 0, 16, 'M')
    if n: t.hline(0, 0, 16, 'M')
    # open sides get the near-black outline of the pilot room border
    if not n: t.hline(0, 0, 16, 'K')
    if not w: t.vline(0, 0, 16, 'K')
    if not s: t.hline(0, 14, 16, 'K'); t.hline(0, 15, 16, 'K')
    if not e: t.vline(14, 0, 16, 'K'); t.vline(15, 0, 16, 'K')
    for key, (a, b) in (('NW', (n, w)), ('NE', (n, e)), ('SW', (s, w)), ('SE', (s, e))):
        if not a and not b:
            cx, cy = CORNER_POS[key]
            for j, row in enumerate(CORNER[key]):
                for i, c in enumerate(row):
                    if c == '.': t.erase(cx + i, cy + j)
                    elif c == 'K': t.g[cy + j][cx + i] = 'K'
    return t


def autotile(fn):
    return [fn(m) for m in range(16)]


# ======================================================================== DOOR (2 cells, 32x16, horizontal)
# The door fills the wall band exactly like the wall tiles do: row 0 near-black, row 1 lit lip, body, rows 14-15 shadow.
POST_L = art_strict("""
KKKKK
yyyyK
yaauK
yaauK
yaauK
yaauK
yaauK
yKKuK
yKKuK
yaauK
yaauK
yaauK
yaauK
yaauK
KKKKK
KKKKK
""", 5, 16, 'post_l')
POST_R = art_strict("""
KKKKK
Kyyyy
KyaaU
KyaaU
KyaaU
KyaaU
KyaaU
KyKKU
KyKKU
KyaaU
KyaaU
KyaaU
KyaaU
KyaaU
KKKKK
KKKKK
""".replace('U', 'u'), 5, 16, 'post_r')
LEAF_L = art_strict("""
KKKKKKKKKKK
MMMMMMMMMME
SWWWWWWWWWE
SWEWWWWWWWE
SWEWWWWWWWE
SWEWWWWWWWE
SWEWWWWWWWE
SWEWWWaaWWE
SWEWWWWWWWE
SWEWWWWWWWE
SWEWWWWWWWE
SWEWWWWWWWE
SWWWWWWWWWE
EEEEEEEEEEE
KKKKKKKKKKK
KKKKKKKKKKK
""", 11, 16, 'leaf_l')


def door_frame(d, lights='a', leaf_l=LEAF_L):
    """leaves slid apart by d px (0 = closed)."""
    f = Spr(32, 16)
    sub = {'a': lights} if lights != 'a' else None
    f.stamp(5 - d, 0, leaf_l, sub)
    f.stamp(16 + d, 0, leaf_l, sub, flip=True)
    # hide whatever slid under the posts / past the piece
    for x in range(0, 5):
        for y in range(16): f.erase(x, y)
    for x in range(27, 32):
        for y in range(16): f.erase(x, y)
    f.stamp(0, 0, POST_L)
    f.stamp(27, 0, POST_R)
    return f


def door_frames():
    fr = [door_frame(d) for d in (0, 3, 6, 9, 11)]
    # frame 5: locked, a red light at the seam and red leaf lights
    lk = door_frame(0, lights='r')
    lk.stamp(14, 6, art_strict("""
KKKK
KrrK
KrrK
KKKK
""", 4, 4, 'lamp'))
    lk.put(15, 7, 'H')
    for (x, y) in ((1, 7), (2, 7), (1, 8), (2, 8), (29, 7), (30, 7), (29, 8), (30, 8)):
        lk.g[y][x] = 'K'
    for (x, y) in ((2, 7), (29, 7)): lk.g[y][x] = 'r'
    fr.append(lk)
    # frame 6: broken. Left leaf cracked and dented, right leaf sheared off on a diagonal and jammed half open,
    # scorched posts, debris in the gap
    br = Spr(32, 16)
    br.stamp(5, 0, LEAF_L)
    for (x, y) in line(8, 2, 6, 6) + line(6, 6, 9, 9) + line(9, 9, 7, 13):         # crack through the left leaf
        br.put(x, y, 'K')
    br.put(10, 6, 'M'); br.put(10, 7, 'M')                                         # dent catching the light
    br.put(11, 7, 'W'); br.put(12, 7, 'W')                                         # light knocked out
    shear = [5, 5, 4, 4, 4, 3, 3, 2, 2, 2, 1, 1, 1, 0, 0, 0]                       # right leaf bent: its inner edge runs on a slant
    for y in range(16):
        row = LEAF_L[y][::-1]
        for i, c in enumerate(row):
            br.put(16 + shear[y] + i, y, c)
        if 1 <= y <= 13:                                                           # dark gap line + bent lip along the slanted edge
            x = 16 + shear[y]
            br.g[y][x] = 'K'
            if y % 2 == 0: br.put(x + 1, y, 'S')
    for x in range(27, 32):
        for y in range(16): br.erase(x, y)
    br.stamp(0, 0, POST_L); br.stamp(27, 0, POST_R)
    for (x, y) in ((1, 3), (2, 3), (1, 4), (3, 12), (2, 12), (28, 4), (29, 4), (29, 5), (30, 11), (29, 11)):
        br.put(x, y, 'n')
    for (x, y) in ((17, 4), (18, 10)): br.put(x, y, 'W')                              # debris in the gap
    fr.append(br)
    return fr


# ======================================================================== BREACH (3 variants, 16x16)
# The jagged hole is drawn by hand ('#'). A 1px torn rim follows it (lit top-left, shaded bottom-right), and the bent
# hull flaps, scorch marks, debris specks and a star seen through the hole are hand placed.
HOLES = [
 ("""
................
................
........#.......
........#..#....
.....#..##.#....
....########....
...##########...
.############.#.
..############..
...###########..
....#########...
....##.###.##...
......#..#......
......#.........
................
................
""", {
  'flaps': [(4, 3, 'M'), (4, 4, 'L'), (3, 5, 'L'), (2, 6, 'M'), (9, 2, 'M'), (10, 2, 'S'), (12, 4, 'S'), (13, 5, 'W'), (14, 6, 'S'),
            (1, 8, 'M'), (1, 9, 'S'), (13, 10, 'E'), (12, 11, 'E'), (11, 12, 'E'), (8, 13, 'E'), (7, 13, 'W')],
  'soot': [(2, 10, 'n'), (3, 11, 'n'), (14, 8, 'n'), (6, 14, 'n'), (10, 3, 'n')],
  'debris': [(1, 4, 'M'), (14, 3, 'S'), (14, 12, 'W'), (3, 13, 'E'), (11, 14, 'W')],
  'star': [(8, 7, 'W')]}),
 ("""
................
................
.............#..
...........###..
..........####..
.........######.
........#######.
.......########.
......#########.
.....#########..
....#########...
...#########....
..#######.#.....
..####..........
..#.............
................
""", {
  'flaps': [(10, 2, 'M'), (11, 2, 'L'), (12, 2, 'M'), (9, 4, 'M'), (8, 5, 'S'), (7, 6, 'M'), (6, 7, 'S'), (5, 8, 'M'), (4, 9, 'S'), (3, 10, 'M'), (2, 11, 'M'),
            (1, 12, 'S'), (1, 13, 'W'), (14, 3, 'W'), (15, 5, 'W'), (14, 9, 'E'), (12, 10, 'E'), (11, 11, 'E'), (10, 12, 'E'), (7, 12, 'E'), (6, 13, 'E')],
  'soot': [(11, 5, 'n'), (10, 7, 'n'), (9, 9, 'n'), (6, 10, 'n'), (12, 8, 'n')],
  'debris': [(5, 3, 'M'), (2, 7, 'S'), (14, 13, 'W'), (13, 14, 'E'), (1, 15, 'W')],
  'star': [(11, 6, 'W'), (6, 11, 'W')]}),
 ("""
................
................
......#...#.....
.....##..##.....
...#.######.#...
..###########...
..############..
.##############.
..#############.
..############..
...#########....
....#######.....
....##.###..#...
.....#...#......
................
................
""", {
  'flaps': [(5, 3, 'M'), (5, 2, 'L'), (4, 3, 'M'), (2, 4, 'M'), (1, 5, 'L'), (1, 6, 'M'), (9, 1, 'M'), (11, 3, 'S'), (11, 2, 'S'), (13, 4, 'W'), (14, 5, 'W'), (15, 8, 'W'),
            (14, 9, 'E'), (12, 10, 'E'), (11, 11, 'E'), (13, 12, 'E'), (9, 13, 'E'), (5, 12, 'W'), (4, 13, 'S'), (3, 11, 'M'), (2, 10, 'M')],
  'soot': [(3, 12, 'n'), (12, 6, 'n'), (13, 7, 'n'), (6, 14, 'n'), (10, 14, 'n')],
  'debris': [(0, 3, 'M'), (13, 2, 'S'), (15, 12, 'W'), (2, 14, 'E')],
  'star': [(7, 5, 'M'), (9, 8, 'W')]}),
]


def breach_variant(ascii_hole, det):
    hole = from_art(ascii_hole.replace('#', 'K'))
    cells = hole.mask()
    out = Spr(16, 16)
    ring = dilate(cells, 1) - cells                              # 1px torn rim, stepped (4-neighbour)
    cx = sum(x for x, _ in cells) / len(cells); cy = sum(y for _, y in cells) / len(cells)
    for (x, y) in ring:
        lit = (x - cx) + (y - cy)                                # top-left is lit
        out.put(x, y, 'L' if lit < -7 else 'M' if lit < -2 else 'S' if lit < 3 else 'E')
    for (x, y) in cells: out.put(x, y, 'K')
    for (x, y, c) in det['flaps']: out.put(x, y, c)              # bent flaps of hull plate
    for (x, y, c) in det['soot']: out.put(x, y, c)
    for (x, y, c) in det['debris']: out.put(x, y, c)
    for (x, y, c) in det['star']: out.put(x, y, c)               # a star seen through the hole
    return out


def breach_frames():
    return [breach_variant(a, d) for a, d in HOLES]


# ======================================================================== CABLE (autotile, thin run on the floor)
# Arms are 2px cores centred on the cell; a 1px near-black outline follows the shape, the lit core pixel faces the top-left.
def cable_core(mask):
    cells = {(7, 7), (8, 7), (7, 8), (8, 8)}
    if mask & N: cells |= {(x, y) for x in (7, 8) for y in range(0, 7)}
    if mask & E: cells |= {(x, y) for x in range(9, 16) for y in (7, 8)}
    if mask & S_: cells |= {(x, y) for x in (7, 8) for y in range(9, 16)}
    if mask & W_: cells |= {(x, y) for x in range(0, 7) for y in (7, 8)}
    return cells


JUNCTION = art_strict("""
KKKKKK
KMMMSK
KMWWEK
KMWWEK
KSEEEK
KKKKKK
""", 6, 6, 'junction')


def cable_tile(mask, powered):
    core = cable_core(mask)
    arms = bin(mask).count('1')
    t = Spr(16, 16)
    outline = {(x, y) for (x, y) in dilate(core, 1) - core if 0 <= x < 16 and 0 <= y < 16}
    for (x, y) in outline: t.put(x, y, 'K')
    lit_c, dark_c = ('g', 'E') if powered else ('W', 'E')
    for (x, y) in core:
        lit = (x - 1, y) in outline or (x, y - 1) in outline
        t.put(x, y, lit_c if lit else dark_c)
    if arms in (0, 1, 3, 4):                                  # dead ends, tees and crosses get a junction plate
        t.stamp(5, 5, JUNCTION)
        if powered: t.put(7, 7, 'g'); t.put(8, 8, 'g'); t.put(7, 8, 'H')
        else: t.put(7, 7, 'W'); t.put(8, 8, 'W')
    elif arms == 2:
        t.put(7, 7, 'H' if powered else 'S')                  # clamp glint at the hub
    return t


def cable_frames(powered):
    return [cable_tile(m, powered) for m in range(16)]
