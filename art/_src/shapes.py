"""Shaped wall cells (slopes, ramps, curves), ram plating and the exterior hull skin. 1 cell = 16x16 source px.

Geometry (also written to art/tiles/shapes.json, so art and physics agree): cell-local 0..1, y down, rotation 0.
  tri       bottom-left half: (0,0),(1,1),(0,1)
  slope2    2 cells rising from (0,1) to (2,0), solid below: tri2_low (x=0) and tri2_high (x=1)
  round2    2x2 convex rounded corner: quarter disk centred at the piece's bottom-right corner (2,2), radius 2, 8 segments
Every sprite is rendered per ORIENTATION (mirror x first, then clockwise quarter turns): the geometry is transformed first and
the lighting (light from the top-left) is computed on the transformed edges, so rotated pieces are always lit right.

One shared engine (`Ana`) finds the exposed edge of a cell's solid pixels (the cut diagonal / arc, plus flat edges that are open),
measures every pixel's depth from it and the direction that edge faces; the styles then paint by depth and facing.
"""
import math
from px import *
import tiles as T

N, E, S_, W_ = 1, 2, 4, 8
SIDES = (N, E, S_, W_)
SIDE_DIR = {N: (0, -1), E: (1, 0), S_: (0, 1), W_: (-1, 0)}
OPP = {N: S_, S_: N, E: W_, W_: E}

# ======================================================================== GEOMETRY (cell-local, y down, rotation 0)
ARC_SEG = 8
ARC_C, ARC_R = (2.0, 2.0), 2.0


def arc_points():
    """8-segment arc of the quarter disk centred at (2,2): from (0,2) up to (2,0), bulging toward the top-left."""
    return [(ARC_C[0] - ARC_R * math.cos(math.radians(90.0 * k / ARC_SEG)), ARC_C[1] - ARC_R * math.sin(math.radians(90.0 * k / ARC_SEG)))
            for k in range(ARC_SEG + 1)]


def round2_poly():                       # whole 2x2 piece, clockwise on screen: centre, then the arc from (2,0) back round to (0,2)
    return [ARC_C] + arc_points()[::-1]


def area(poly):
    return abs(sum(poly[i][0] * poly[(i + 1) % len(poly)][1] - poly[(i + 1) % len(poly)][0] * poly[i][1] for i in range(len(poly)))) / 2


def clip_rect(poly, x0, y0, x1, y1):
    """Sutherland-Hodgman clip of a polygon to an axis-aligned rectangle."""
    def clip(pts, inside, inter):
        out = []
        for i, p in enumerate(pts):
            q = pts[(i + 1) % len(pts)]
            if inside(p):
                out.append(p)
                if not inside(q): out.append(inter(p, q))
            elif inside(q): out.append(inter(p, q))
        return out
    def ix(xc):  return lambda p, q: (xc, p[1] + (q[1] - p[1]) * (xc - p[0]) / (q[0] - p[0]))
    def iy(yc):  return lambda p, q: (p[0] + (q[0] - p[0]) * (yc - p[1]) / (q[1] - p[1]), yc)
    pts = poly
    for ins, it in ((lambda p: p[0] >= x0 - 1e-9, ix(x0)), (lambda p: p[0] <= x1 + 1e-9, ix(x1)),
                    (lambda p: p[1] >= y0 - 1e-9, iy(y0)), (lambda p: p[1] <= y1 + 1e-9, iy(y1))):
        if not pts: break
        pts = clip(pts, ins, it)
    return pts


def dedupe(poly):
    out = []
    for p in poly:
        if not out or abs(p[0] - out[-1][0]) > 1e-7 or abs(p[1] - out[-1][1]) > 1e-7: out.append(p)
    if len(out) > 1 and abs(out[0][0] - out[-1][0]) < 1e-7 and abs(out[0][1] - out[-1][1]) < 1e-7: out.pop()
    # drop collinear middle points
    res = []
    for i, p in enumerate(out):
        a, b = out[i - 1], out[(i + 1) % len(out)]
        if abs((p[0] - a[0]) * (b[1] - a[1]) - (p[1] - a[1]) * (b[0] - a[0])) > 1e-9: res.append(p)
    return res


def cell_polys():
    """name -> polygon (cell-local) for every shape cell."""
    P = {'full': [(0, 0), (1, 0), (1, 1), (0, 1)],
         'tri': [(0, 0), (1, 1), (0, 1)],
         'tri2_low': [(0, 1), (1, 0.5), (1, 1)],
         'tri2_high': [(0, 0.5), (1, 0), (1, 1), (0, 1)]}
    rp = round2_poly()
    for name, (cx, cy) in (('arc_tl', (0, 0)), ('arc_tr', (1, 0)), ('arc_bl', (0, 1)), ('arc_br', (1, 1))):
        c = dedupe(clip_rect(rp, cx, cy, cx + 1, cy + 1))
        P[name] = [(round(x - cx, 5), round(y - cy, 5)) for x, y in c]
    return P


SHAPE_CELLS = ['tri', 'tri2_low', 'tri2_high', 'arc_tl', 'arc_tr', 'arc_bl', 'arc_br']     # sheet row order
PIECES = {'full': {'size': [1, 1], 'cells': [{'at': [0, 0], 'shape': 'full'}]},
          'slope45': {'size': [1, 1], 'cells': [{'at': [0, 0], 'shape': 'tri'}]},
          'slope2': {'size': [2, 1], 'cells': [{'at': [0, 0], 'shape': 'tri2_low'}, {'at': [1, 0], 'shape': 'tri2_high'}]},
          'round2': {'size': [2, 2], 'cells': [{'at': [0, 0], 'shape': 'arc_tl'}, {'at': [1, 0], 'shape': 'arc_tr'},
                                               {'at': [0, 1], 'shape': 'arc_bl'}, {'at': [1, 1], 'shape': 'arc_br'}]}}


# ======================================================================== RASTER (rot 0 pixel regions of 16x16)
def inside(poly, px, py):
    """point in polygon, boundary counts as inside."""
    n, c = len(poly), False
    for i in range(n):
        (x0, y0), (x1, y1) = poly[i], poly[(i + 1) % n]
        cr = (x1 - x0) * (py - y0) - (y1 - y0) * (px - x0)
        if abs(cr) < 1e-9 and min(x0, x1) - 1e-9 <= px <= max(x0, x1) + 1e-9 and min(y0, y1) - 1e-9 <= py <= max(y0, y1) + 1e-9: return True
        if (y0 > py) != (y1 > py) and px < (x1 - x0) * (py - y0) / (y1 - y0) + x0: c = not c
    return c


def base_region(name):
    """solid pixels of a shape cell at rotation 0. tri and slope2 follow hand-picked clean pixel lines (a 1:1 and a 2:1 staircase);
    the arcs rasterise the 8-gon at pixel centres."""
    if name == 'full': return {(x, y) for x in range(16) for y in range(16)}
    if name == 'tri': return {(x, y) for x in range(16) for y in range(16) if y >= x}
    if name == 'tri2_low': return {(x, y) for x in range(16) for y in range(16) if y >= 15 - x // 2}
    if name == 'tri2_high': return {(x, y) for x in range(16) for y in range(16) if y >= 7 - x // 2}
    cx, cy = {'arc_tl': (0, 0), 'arc_tr': (1, 0), 'arc_bl': (0, 1), 'arc_br': (1, 1)}[name]
    rp = round2_poly()
    return {(x, y) for x in range(16) for y in range(16) if inside(rp, (cx * 16 + x + 0.5) / 16.0, (cy * 16 + y + 0.5) / 16.0)}


def orient_px(p, o):
    """pixel (x,y) of a 16x16 cell under orientation o = mirror*4 + rot (mirror x first, then clockwise quarter turns)."""
    x, y = p
    if o >= 4: x = 15 - x
    for _ in range(o % 4): x, y = 15 - y, x
    return (x, y)


def oriented(name, o):
    return {orient_px(p, o) for p in base_region(name)}


def orient_poly(poly, o):
    out = []
    for (x, y) in poly:
        if o >= 4: x = 1 - x
        for _ in range(o % 4): x, y = 1 - y, x
        out.append((x, y))
    return out


# ======================================================================== ANALYSIS ENGINE
CORNERS = {(N, W_): [(0, 0), (1, 0), (0, 1)], (N, E): [(15, 0), (14, 0), (15, 1)],
           (S_, W_): [(0, 15), (1, 15), (0, 14)], (S_, E): [(15, 15), (14, 15), (15, 14)]}


def edge_run(reg, side):
    if side == N: return [(x, 0) for x in range(16) if (x, 0) in reg]
    if side == S_: return [(x, 15) for x in range(16) if (x, 15) in reg]
    if side == W_: return [(0, y) for y in range(16) if (0, y) in reg]
    return [(15, y) for y in range(16) if (15, y) in reg]


def norm(v):
    m = math.hypot(*v)
    return (v[0] / m, v[1] / m) if m > 1e-9 else (0.0, 0.0)


def lit_class(n):
    """light comes from the top-left: which way does a surface with outward normal n face?"""
    l = -0.7071 * (n[0] + n[1])
    return 'lit' if l > 0.3 else 'shade' if l < -0.3 else 'neu'


class Ana:
    """solid pixels `region`, `exposed[side]` = that flat edge is open to space / floor (the cut edge always is).
    After construction: reg (chamfered), edges, open (pixel -> open sides), depth, nrm (outward direction of the nearest open edge)."""
    def __init__(s, region, exposed):
        reg = set(region)
        raw = set(region)
        s.edges = {k: len(edge_run(reg, k)) >= 4 for k in SIDES}
        s.exposed = exposed
        for (a, b), pix in CORNERS.items():                      # convex corner where two open flat edges meet: chamfer
            if s.edges[a] and s.edges[b] and exposed[a] and exposed[b] and pix[0] in reg:
                for p in pix: reg.discard(p)
        s.reg = reg
        s.open = {}
        for (x, y) in reg:
            ds = []
            for k, (dx, dy) in SIDE_DIR.items():
                q = (x + dx, y + dy)
                if 0 <= q[0] < 16 and 0 <= q[1] < 16:
                    if q not in reg: ds.append(k)
                elif (not s.edges[k]) or exposed[k]: ds.append(k)
            if ds: s.open[(x, y)] = ds
        s.cut = {}                                                # pixels bordering the cut edge (diagonal / arc / a flat edge that does not exist)
        for (x, y) in reg:
            ds = []
            for k, (dx, dy) in SIDE_DIR.items():
                q = (x + dx, y + dy)
                if 0 <= q[0] < 16 and 0 <= q[1] < 16:
                    if q not in raw: ds.append(k)                 # empty in the shape itself (a chamfered corner does not count)
                elif not s.edges[k]: ds.append(k)
            if ds: s.cut[(x, y)] = ds
        s.depth, s.nrm = s._bfs(s.open)
        s.cdepth, s.cnrm = s._bfs(s.cut)

    def _bfs(s, src):
        depth, nrm, front = {}, {}, []
        for p, ds in src.items():
            depth[p] = 0
            nrm[p] = norm((sum(SIDE_DIR[k][0] for k in ds), sum(SIDE_DIR[k][1] for k in ds)))
            front.append(p)
        d = 0
        while front:
            d += 1
            acc = {}
            for (x, y) in front:
                for (dx, dy) in SIDE_DIR.values():
                    q = (x + dx, y + dy)
                    if q in s.reg and q not in depth:
                        a = acc.setdefault(q, [0.0, 0.0])
                        a[0] += nrm[(x, y)][0]; a[1] += nrm[(x, y)][1]
            for q, a in acc.items():
                depth[q] = d; nrm[q] = norm(a)
            front = list(acc)
        return depth, nrm

    def d(s, p): return s.depth.get(p, 99)                       # no exposed edge anywhere: very deep
    def cls(s, p): return lit_class(s.nrm.get(p, (0.0, 0.0)))
    def cd(s, p): return s.cdepth.get(p, 99)


def flat_runs(an, joined_sides):
    """(side, run pixels) for every flat edge that is joined."""
    return [(k, edge_run(an.reg, k)) for k in SIDES if an.edges[k] and joined_sides[k]]


def std_rivets(an, joined):
    """wall_standard's rule: a pair of rivets 2px beside the east / south joint, kept off the outline bands."""
    pts = []
    for k in (E, S_):
        if not (an.edges[k] and joined[k]): continue
        run = edge_run(an.reg, k)
        if k == E:
            ys = [p[1] for p in run]; ra, rb = min(ys), max(ys)
            y0 = ra + (2 if (ra > 0 or not joined[N]) else 0); y1 = rb + 1 - (2 if (rb < 15 or not joined[S_]) else 0)
            cand = [(13, y0 + 2), (13, y1 - 3)]
        else:
            xs = [p[0] for p in run]; ra, rb = min(xs), max(xs)
            x0 = ra + (2 if (ra > 0 or not joined[W_]) else 0); x1 = rb + 1 - (2 if (rb < 15 or not joined[E]) else 0)
            cand = [(x0 + 2, 13), (x1 - 3, 13)]
        keep = []
        for (x, y) in cand:
            for step in range(4):                                  # slide inward until clear of the outline bands
                q = (x, y + step) if k == E else (x + step, y)
                if q in an.reg and an.d(q) >= 2: keep.append(q); break
        pts += [q for q in keep if all(abs(q[0] - r[0]) + abs(q[1] - r[1]) >= 3 for r in pts)]
    return pts


# ======================================================================== STYLE: standard wall (matches walls.png)
def paint_standard(region, mask):
    joined = {k: bool(mask & k) for k in SIDES}
    an = Ana(region, {k: not joined[k] for k in SIDES})
    t = Spr(16, 16)
    for p in an.reg: t.put(p[0], p[1], 'D')
    for k in (E, W_, S_, N):                                      # joints with solid neighbours: dark seam south/east, lit lip north/west
        if an.edges[k] and joined[k]:
            for p in edge_run(an.reg, k): t.put(p[0], p[1], 'K' if k in (E, S_) else 'E')
    for p in std_rivets(an, joined): t.put(p[0], p[1], 'W')
    for p in an.reg:
        d = an.d(p)
        if d == 0: t.put(p[0], p[1], 'K'); t.g[p[1]][p[0]] = 'K'
        elif d == 1: t.g[p[1]][p[0]] = 'E' if an.cls(p) == 'lit' else 'K'
    return t, an


# ======================================================================== STYLE: armour plate (matches walls_armor.png, neutral greys, tinted by the game)
def paint_armor(region, mask):
    joined = {k: bool(mask & k) for k in SIDES}
    an = Ana(region, {k: not joined[k] for k in SIDES})
    t = Spr(16, 16)
    reg = an.reg
    for p in reg: t.put(p[0], p[1], 'S')
    # the plate's 2px bevel on every flat edge: lit L,M north/west, shaded E,W south/east (same order as walls_armor)
    for k in (N, W_, S_, E):
        if not an.edges[k]: continue
        for (x, y) in edge_run(reg, k):
            t.put(x, y, 'L' if k in (N, W_) else 'E')
    for (x, y) in list(reg):
        if y == 1 and x >= 1: t.put(x, y, 'M') if an.edges[N] else None
        if x == 1 and y >= 1: t.put(x, y, 'M') if an.edges[W_] else None
        if y == 14 and 1 <= x <= 14 and an.edges[S_]: t.put(x, y, 'W')
        if x == 14 and 1 <= y <= 14 and an.edges[E]: t.put(x, y, 'W')
    for p in reg:                                                 # open edges (cut diagonal / arc included): the lip one pixel in, by facing
        if an.d(p) == 1: t.put(p[0], p[1], 'K' if an.cls(p) == 'shade' else 'M'); t.g[p[1]][p[0]] = 'M' if an.cls(p) == 'lit' else 'K'
    # corrugated ribs and corner bolts, only where they sit clear of every bevel
    free = lambda p: p in reg and an.d(p) >= 3 and 2 <= p[0] <= 13 and 2 <= p[1] <= 13
    for ry in (4, 7, 10):
        for x in range(4, 12):
            if free((x, ry)) and free((x, ry + 1)): t.put(x, ry, 'M'); t.put(x, ry + 1, 'W')
        if free((3, ry)): t.put(3, ry, 'S')
        if free((12, ry)): t.put(12, ry, 'S')
    for (bx, by) in ((2, 2), (12, 2), (2, 12), (12, 12)):
        blk = [(bx + i, by + j) for i in (0, 1) for j in (0, 1)]
        if all(p in reg and an.d(p) >= 2 for p in blk):
            for p in blk: t.put(p[0], p[1], 'W')
            t.put(bx, by, 'H'); t.put(bx + 1, by + 1, 'E')
    for k in (E, S_, W_, N):                                      # joined seams: dark south/east, lit north/west
        if an.edges[k] and joined[k]:
            for p in edge_run(reg, k): t.put(p[0], p[1], 'K' if k in (E, S_) else 'M')
    for p in reg:                                                 # exposed edge: the near-black outline
        if an.d(p) == 0: t.g[p[1]][p[0]] = 'K'
    return t, an


# ======================================================================== STYLE: ram plating (thick bolted plates, hazard-striped leading edges, dents)
# Fixed colours (not tinted): gunmetal plate, amber and near-black hazard tape. On a shaped cell the tape runs along the CUT edge (the
# slanted / curved leading edge, which always faces out); on a full cell it runs along every open side.
BOLT4 = (".EE.", "EHSE", "ESWE", ".EE.")                     # big dome bolt for a small clear field
BOLT3 = ("EEE", "EHE", "EEE")                                 # corner bolt head (dark seat, white glint)
DENT = (".KK.", "KEEM", ".MM.")


def hazard_colour(x, y, nrm):
    """diagonal tape stripes, 2px wide, crossing the band at 45 degrees (so they cross a diagonal edge square-on)."""
    s = ((x - y) // 2 if nrm[0] * nrm[1] > 0.2 else (x + y) // 2) % 2
    return 'a' if s == 0 else 'K'


def stamp_free(t, tmpl, bx, by, an, used, depth_ok):
    pix = [(bx + i, by + j) for j, row in enumerate(tmpl) for i, c in enumerate(row) if c != '.']
    halo_ = {(x + dx, y + dy) for (x, y) in pix for dx in (-1, 0, 1) for dy in (-1, 0, 1)}
    if all(p in an.reg and depth_ok(p) for p in pix) and not (halo_ & used):
        for j, row in enumerate(tmpl):
            for i, c in enumerate(row):
                if c != '.': t.put(bx + i, by + j, c)
        used |= set(pix)
        return True
    return False


def paint_ram(region, mask):
    joined = {k: bool(mask & k) for k in SIDES}
    an = Ana(region, {k: not joined[k] for k in SIDES})
    t = Spr(16, 16)
    reg = an.reg
    cutmode = bool(an.cut)                                        # shaped cell: tape only on the cut edge
    tape = (lambda p: an.cd(p)) if cutmode else (lambda p: an.d(p))
    tnrm = (lambda p: an.cnrm.get(p, (0, -1))) if cutmode else (lambda p: an.nrm.get(p, (0, -1)))
    for p in reg: t.put(p[0], p[1], 'W')
    for p in reg:                                                 # the plate edge just inside the tape: lit light line / shaded dark line
        if tape(p) == 4: t.g[p[1]][p[0]] = 'E' if lit_class(tnrm(p)) == 'shade' else 'S'
    for k in (E, S_, W_, N):                                      # joined seams: thick, 2px (dark south/east, lit north/west)
        if not (an.edges[k] and joined[k]): continue
        for (x, y) in edge_run(reg, k):
            dx, dy = SIDE_DIR[OPP[k]]
            q = (x + dx, y + dy)
            if k in (E, S_): t.put(x, y, 'K'); t.put(q[0], q[1], 'E') if q in reg else None
            else: t.put(x, y, 'M'); t.put(q[0], q[1], 'S') if q in reg else None
    if cutmode:                                                   # open flat edges of a shaped cell: plain bevel (outline, then a lip by facing)
        for p in reg:
            if an.d(p) == 1: t.g[p[1]][p[0]] = 'S' if an.cls(p) != 'shade' else 'E'
    # bolts and dents in the clear field
    ins = {k: (5 if an.exposed[k] else 3) for k in SIDES}
    if cutmode:
        for k in SIDES:
            if an.edges[k] and an.exposed[k]: ins[k] = 3
    fx0, fx1, fy0, fy1 = ins[W_], 15 - ins[E], ins[N], 15 - ins[S_]
    fw, fh = fx1 - fx0 + 1, fy1 - fy0 + 1
    ok = lambda p: an.d(p) >= (3 if cutmode else 5) and tape(p) >= 5
    used = set()
    v = (mask + fw) % 4
    if fw >= 9 and fh >= 9:                                       # big field: four corner heads and a dent between them
        for (bx, by) in ((fx0, fy0), (fx1 - 2, fy0), (fx0, fy1 - 2), (fx1 - 2, fy1 - 2)): stamp_free(t, BOLT3, bx, by, an, used, ok)
        stamp_free(t, DENT, (fx0 + fx1) // 2 - 1, (fy0 + fy1) // 2 - 1, an, used, ok)
    elif fw >= 8 and fh >= 8:                                     # medium field: a dome bolt in one corner, a dent in the opposite one
        corners = [((fx0, fy0), (fx1 - 3, fy1 - 2)), ((fx1 - 3, fy0), (fx0, fy1 - 2)), ((fx0, fy1 - 3), (fx1 - 3, fy0)), ((fx1 - 3, fy1 - 3), (fx0, fy0))]
        (bx, by), (dx_, dy_) = corners[v]
        stamp_free(t, BOLT4, bx, by, an, used, ok); stamp_free(t, DENT, dx_, dy_, an, used, ok)
    elif fw >= 4 and fh >= 4:
        stamp_free(t, BOLT4, (fx0 + fx1) // 2 - 1, (fy0 + fy1) // 2 - 1, an, used, ok)
    for p in reg:                                                 # the leading edge: outline, then 3px of hazard tape
        d = tape(p)
        if 1 <= d <= 3: t.g[p[1]][p[0]] = hazard_colour(p[0], p[1], tnrm(p))
        elif an.d(p) == 0: t.g[p[1]][p[0]] = 'K'
        elif d == 0: t.g[p[1]][p[0]] = 'K'
    return t, an


# ======================================================================== STYLE: exterior hull skin
# Neutral greys only (the game multiplies a tint per culture line). Drawn over a wall cell; it covers the skin band (SKIN_T px deep)
# measured from every edge that faces SPACE and leaves the last 2px of the cell to the wall's own interior outline underneath.
# Mask bit set = that side of the cell faces open space (not "solid neighbour" as in walls.png).
SKIN_T = 14


def skin_rim(an, p):
    """colour of the rim / plate-edge pixels (None = panel body)."""
    d, c = an.d(p), an.cls(p)
    if d == 0: return 'K'
    if d == 1: return {'lit': 'L', 'neu': 'M', 'shade': 'E'}[c]
    if d == 2: return {'lit': 'M', 'neu': None, 'shade': 'W'}[c]
    if d == SKIN_T - 1: return 'L' if c == 'shade' else 'E'                    # the plate's far edge faces away from the space side
    if d == SKIN_T - 2: return 'M' if c == 'shade' else 'W'
    return None


def paint_skin(region, space, seam_left=True, seam_top=True, variant=0, inner='W'):
    """region = solid pixels, space = bitmask of flat sides facing space. Returns (sprite, analysis)."""
    ex = {k: bool(space & k) for k in SIDES}
    an = Ana(region, ex)
    reg = an.reg
    cover = {p for p in reg if an.d(p) < SKIN_T} if an.open else set(reg)       # no edge faces space: a plain interior panel, fully covered
    t = Spr(16, 16)
    for p in cover: t.put(p[0], p[1], 'S')
    # second plate line, 7px in: a long seam parallel to the hull edge, so the skin reads as two layers of plating
    for p in cover:
        d = an.d(p)
        if d == 7: t.g[p[1]][p[0]] = 'W'
        elif d == 8: t.g[p[1]][p[0]] = 'M' if an.cls(p) != 'shade' else 'S'
        elif d > 8 and d < SKIN_T: t.g[p[1]][p[0]] = inner
    # panel joints at the tile's top / left edge (one tile's seam = the next tile's panel start): dark gap, then a lit lip
    for p in cover:
        x, y = p
        if an.open and (an.d(p) < 3 or an.d(p) > SKIN_T - 3): continue
        if seam_top and y <= 1 and an.edges[N] and not ex[N]: t.g[y][x] = 'E' if y == 0 else 'M'
        if seam_left and x <= 1 and an.edges[W_] and not ex[W_]: t.g[y][x] = 'E' if x == 0 else 'M'
    for p in cover:
        c = skin_rim(an, p)
        if c: t.g[p[1]][p[0]] = c
    # rivets beside the seams
    riv = []
    if seam_top: riv += [(4, 3), (11, 3)]
    if seam_left: riv += [(3, 8), (3, 12)] if not seam_top else [(3, 11)]
    for (x, y) in riv:
        if (x, y) in cover and (not an.open or 4 <= an.d((x, y)) <= SKIN_T - 4) and (x + 1, y + 1) in cover:
            t.put(x, y, 'L'); t.put(x + 1, y + 1, 'W')
    return t, an


def skin_glow(an, pad=3):
    """soft edge glow for the neon line: neutral light, 3 bands outward from every space-facing edge, clipped so neighbouring tiles abut."""
    w = 16 + 2 * pad
    out = Rgba(w, w)
    src = [p for p, ds in an.open.items() if an.depth.get(p) == 0]
    bands = ((1.2, 120), (2.2, 64), (3.2, 30))
    for y in range(-pad, 16 + pad):
        for x in range(-pad, 16 + pad):
            if (x, y) in an.reg: continue
            # this tile owns the outside pixels in front of its own exposed flat edges / cut edge only
            if x < 0 and not (an.exposed[W_] and an.edges[W_]): continue
            if x > 15 and not (an.exposed[E] and an.edges[E]): continue
            if y < 0 and not (an.exposed[N] and an.edges[N]): continue
            if y > 15 and not (an.exposed[S_] and an.edges[S_]): continue
            dmin = min((math.hypot(x - sx, y - sy) for (sx, sy) in src), default=99)
            for (md, al) in bands:
                if dmin <= md:
                    out.p[y + pad][x + pad] = list(RGB['L']) + [al]; break
    return out


# ======================================================================== DECALS (greebles the game sprinkles on the skin)
# Neutral greys (tinted with the skin). Art stays inside x,y = 3..12 of each 16px cell, clear of the 3px rim on any side.
VENT = art_strict("""
................................
................................
................................
....KKKKKKKKKKKKKKKKKKKKKKKK....
....KLMMMMMMMMMMMMMMMMMMMMEK....
....KMKKKKKKKKKKKKKKKKKKKKWK....
....KMKMMMMMMMMMMMMMMMMMMKWK....
....KMKWWWWWWWWWWWWWWWWWWKWK....
....KMKKKKKKKKKKKKKKKKKKKKWK....
....KMKMMMMMMMMMMMMMMMMMMKWK....
....KMKWWWWWWWWWWWWWWWWWWKWK....
....KMKKKKKKKKKKKKKKKKKKKKWK....
....KWEEEEEEEEEEEEEEEEEEEEEK....
....KKKKKKKKKKKKKKKKKKKKKKKK....
................................
................................
""", 32, 16, 'vent')
ANTENNA = art_strict("""
................
................
................
.......HH.......
......KLMK......
......KLMK......
...KKKKLMKKKK...
...KLMMLMMMWK...
...KKKKLMKKKK...
......KLMK......
.....KKLMKK.....
....KLMMMMWK....
....KKKKKKKK....
................
................
................
""", 16, 16, 'antenna')
HATCH = art_strict("""
................
................
................
...KKKKKKKKKK...
...KLMMMMMMEK...
...KMSSSSSSWK...
...KMSKEEKSWK...
...KMSEWWESWK...
...KMSEWWESWK...
...KMSKEEKSWK...
...KMSSSSSSWK...
...KEWWWWWWEK...
...KKKKKKKKKK...
................
................
................
""", 16, 16, 'hatch')
LIGHT_ON = art_strict("""
................
................
................
................
................
................
......KKKK......
.....KMLLMK.....
....KMLHHLMK....
.....KMLLMK.....
......KKKK......
................
................
................
................
................
""", 16, 16, 'light_on')
LIGHT_OFF = [r.replace('H', 'S').replace('L', 'W').replace('M', 'E') for r in LIGHT_ON]
DECALS = [('vent', VENT), ('antenna', ANTENNA), ('hatch', HATCH), ('light_on', LIGHT_ON), ('light_off', LIGHT_OFF)]


def decal_atlas():
    """one 96x16 strip: vent 32 wide, then four 16px decals. Returns (Spr, rects, glow Rgba)."""
    spr = Spr(96, 16)
    rects, x = {}, 0
    for name, rows in DECALS:
        w = len(rows[0])
        spr.stamp(x, 0, rows)
        rects[name] = [x, 0, w, 16]
        x += w
    glow = Rgba(96, 16)
    lamp = Spr(96, 16)                                        # glow where lit: the lamp, the antenna tip
    lamp.stamp(rects['light_on'][0], 0, LIGHT_ON); lamp.stamp(rects['antenna'][0], 0, ANTENNA)
    g = halo(lamp, 96, 16, 0, 0, bands=((1.4, 110), (2.8, 60), (4.2, 28)), src='H', col='L')
    return spr, rects, g


# ======================================================================== SHEETS + JSON
ORIENTS = 8
# multiply colours (0..255) the game can use per culture line over the neutral skin / armour greys; glow colours for the glow layers
SUGGESTED_TINTS = {'standard': [237, 250, 255], 'scrap': [255, 184, 133], 'neon': [92, 112, 189], 'armor_plate': [148, 168, 230],
                   'edge_glow_neon': [64, 242, 255], 'lamp_glow': [255, 217, 140]}
MASK = {'N': 1, 'E': 2, 'S': 4, 'W': 8}


def row_of(o, name): return o * len(SHAPE_CELLS) + SHAPE_CELLS.index(name)


def wall_frame(style, name, o, mask):
    region = oriented(name, o)
    if name == 'arc_br':                                           # the full cell of round2: exactly the straight wall autotile
        if style == 'std': return T.wall_standard(mask)
        if style == 'armor': return T.wall_armor(mask)
    return {'std': paint_standard, 'armor': paint_armor, 'ram': paint_ram}[style](region, mask)[0]


def piece_cells(piece, o):
    """cells of a piece under orientation o: [(x, y, shape cell)] and the new size. Mirror x first, then clockwise quarter turns."""
    w, h = PIECES[piece]['size']
    cells = [(c['at'][0], c['at'][1], c['shape']) for c in PIECES[piece]['cells']]
    if o >= 4: cells = [(w - 1 - x, y, n) for x, y, n in cells]
    for _ in range(o % 4):
        cells = [(h - 1 - y, x, n) for x, y, n in cells]
        w, h = h, w
    return cells, (w, h)


def grid_sheet(frames_fn, rows, cols=16):
    sh = Spr(16 * cols, 16 * rows)
    for r in range(rows):
        for c in range(cols): sh.stamp(c * 16, r * 16, frames_fn(r, c).rows())
    return sh


def clean(v):
    v = round(v, 5)
    return int(v) if v == int(v) else v


def clockwise(poly):
    """screen-clockwise (y down): the shoelace sum is positive."""
    sm = sum(poly[i][0] * poly[(i + 1) % len(poly)][1] - poly[(i + 1) % len(poly)][0] * poly[i][1] for i in range(len(poly)))
    return poly if sm > 0 else poly[::-1]


def shapes_json():
    P = cell_polys()
    shapes = {}
    for n in ['full'] + SHAPE_CELLS:
        pts = [[clean(x), clean(y)] for x, y in clockwise(P[n])]
        shapes[n] = {'poly': pts, 'area': round(area(P[n]), 5), 'pixels': round(len(base_region(n)) / 256.0, 4)}
    arc = [[clean(x), clean(y)] for x, y in arc_points()]
    return {
        'version': 1,
        'units': 'cell-local 0..1, x to the right, y DOWN (screen), rotation 0, no mirror. Polygons wind clockwise on screen. A cell may be solid on only part of itself; the rest is open (space or floor).',
        'orientation': 'orient = mirror*4 + rot. Mirror flips x first (x -> 1-x); then the shape turns clockwise by rot quarter turns, (x, y) -> (1-y, x). For a multi-cell piece the same transform is applied about the PIECE (cell (cx,cy) of a w x h piece goes to (w-1-cx, cy) when mirrored, then (h-1-cy, cx) per quarter turn, and w,h swap).',
        'shapes': shapes,
        'pieces': PIECES,
        'round2': {
            'centre': list(ARC_C), 'radius': ARC_R, 'segments': ARC_SEG, 'arc': arc,
            'note': 'convex rounded corner, rotation 0: the solid region is the quarter disk centred at the piece bottom-right corner (2,2); solid toward the bottom-right, open at the top-left. The arc runs from (0,2) to (2,0) and is tangent to the left wall below it and to the top wall right of it. Cells: arc_br is full, arc_tr and arc_bl lose a corner, arc_tl keeps only a small triangle-like sliver at its bottom-right. Cell polygons are the 8-gon clipped to each cell.'},
        'art': {
            'pixels_per_cell': 16,
            'raster': 'tri is y >= x. tri2_low is y >= 15 - x//2, tri2_high is y >= 7 - x//2 (a clean 2:1 staircase, steps aligned to pixel pairs). The arcs rasterise the 8-gon at pixel centres. Art edges follow the polygons to within 1 px.',
            'light': 'from the top-left, computed per orientation on the real edge direction, so every orientation of every cell is lit correctly (sheets hold all 8).'}}


def build_shapes(art_dir, out_spr):
    """write every shaped-wall / ram / skin file. out_spr(rel, Spr|frames, meta) as in build.py; glow sheets land in GLOW_FILES."""
    nc = len(SHAPE_CELLS)
    rows = ORIENTS * nc
    save_json(os.path.join(art_dir, 'tiles/shapes.json'), shapes_json())
    note_mask = ('Autotile by 4-neighbour mask in SCREEN space (after rotating / mirroring the cell): column = N*1 + E*2 + S*4 + W*8, bit set when that neighbour is solid '
                 '(a neighbour counts as solid when it covers the shared edge). Flat edges with a solid neighbour get the joint seam and rivets of walls.png; open flat edges get the near-black outline and lip; '
                 'the cut edge (diagonal or arc) is always open and gets the same outline. The non-solid part is transparent: the game draws floor or space under it. '
                 'Bits for sides where the cell has no flat edge are ignored (the frames repeat).')
    rowdoc = {'cells': SHAPE_CELLS, 'count': rows, 'row': 'row = orient * 7 + cell index (orient = mirror*4 + rot, see shapes.json); rows 0-6 are rotation 0, the set asked for in the brief'}
    for style, rel, extra in (('std', 'tiles/walls_shapes', {}), ('armor', 'tiles/walls_armor_shapes', {'tint': 'multiply'})):
        sh = grid_sheet(lambda r, c: wall_frame(style, SHAPE_CELLS[r % nc], r // nc, c), rows)
        meta = {'frame': [16, 16], 'cells': [1, 1], 'autotile': 'mask4', 'mask': MASK, 'frames': 16, 'rows': rowdoc, 'layout': '16 columns (mask) x %d rows' % rows,
                'shapes': 'tiles/shapes.json'}
        meta.update(extra); meta['notes'] = note_mask + (' Neutral greys: multiply the material colour over it, like walls_armor.png.' if style == 'armor' else ' Same language as walls.png.')
        out_spr(rel, sh, meta)
    # ---- ram plating: the full cell (16 mask frames) and the shaped cells
    ram_note = ('Ram plating: thick gunmetal plates, big bolt heads, dents, and a 3px amber-and-black hazard tape on every open edge (the leading edge). '
                'Fixed colours: do NOT multiply a tint over it. ' + note_mask)
    out_spr('tiles/walls_ram', [paint_ram(base_region('full'), m)[0] for m in range(16)], {
        'frame': [16, 16], 'cells': [1, 1], 'autotile': 'mask4', 'mask': MASK, 'frames': 16, 'tint': 'none', 'notes': ram_note})
    sh = grid_sheet(lambda r, c: wall_frame('ram', SHAPE_CELLS[r % nc], r // nc, c), rows)
    out_spr('tiles/walls_ram_shapes', sh, {'frame': [16, 16], 'cells': [1, 1], 'autotile': 'mask4', 'mask': MASK, 'frames': 16, 'rows': rowdoc, 'tint': 'none',
                                           'layout': '16 columns (mask) x %d rows' % rows, 'shapes': 'tiles/shapes.json', 'notes': ram_note})
    # ---- exterior hull skin
    skin_mask = ('Mask bit set = that side of the cell faces open SPACE (not "solid neighbour" as in walls.png): column = N*1 + E*2 + S*4 + W*8. '
                 'The skin is drawn over a wall cell. It paints a rim (near-black outline, then a lit or shaded edge by facing) on every space-facing side and covers the cell up to 14px in from it, '
                 'so the last 2px on the far side stay the wall\'s own interior outline; with no space-facing side (column 0) it is one whole panel. Cells on a thin spar that face space on two sides are covered fully.')
    var_note = 'row = variant: bit0 = no panel joint on the left edge, bit1 = no joint on the top edge (the panel continues from the neighbour). Pick per cell by a position hash so panels read 1-3 cells long.'
    full_frames = [[paint_skin(base_region('full'), m, seam_left=not (v & 1), seam_top=not (v & 2))[0] for m in range(16)] for v in range(4)]
    sk = Spr(256, 64)
    for v in range(4):
        for m in range(16): sk.stamp(m * 16, v * 16, full_frames[v][m].rows())
    glow16 = [skin_glow(paint_skin(base_region('full'), m)[1]) for m in range(16)]
    _glow_sheet(art_dir, 'tiles/hull_skin_glow', glow16, 16, 1)
    sk_meta = {'frame': [16, 16], 'cells': [1, 1], 'autotile': 'mask4', 'mask': MASK, 'mask_means': 'neighbour faces open space', 'frames': 16, 'variants': 4, 'layout': '16 columns (mask) x 4 rows (variant)',
               'tint': 'multiply', 'suggested_tints': SUGGESTED_TINTS, 'coverage': {'depth_px': SKIN_T, 'rim': [0, 1, 2], 'left_to_wall_px': 2},
               'glow': {'image': 'hull_skin_glow.png', 'frame': [22, 22], 'offset': [-3, -3], 'blend': 'add (preferred) or alpha-over', 'layout': '16 frames, same mask columns',
                        'note': 'neutral edge glow, 3 soft bands outside every space-facing edge: tint it per line (cyan for neon) and draw it only for lines that glow'},
               'shapes': {'image': 'hull_skin_shapes.png', 'glow': 'hull_skin_shapes_glow.png'},
               'decals': {'image': 'hull_skin_decals.png', 'glow': 'hull_skin_decals_glow.png'},
               'notes': skin_mask + ' ' + var_note + ' Neutral greys only (K D E W S M L): multiply a tint per culture line (scrap rust, standard clean, neon dark navy).'}
    out_spr('tiles/hull_skin', sk, sk_meta)
    # skin pieces for the shaped cells: the same rim follows the diagonal / arc (the cut edge always faces space)
    skin_fr = [[paint_skin(oriented(SHAPE_CELLS[r % nc], r // nc), m) for m in range(16)] for r in range(rows)]
    out_spr('tiles/hull_skin_shapes', grid_sheet(lambda r, c: skin_fr[r][c][0], rows), {
        'frame': [16, 16], 'cells': [1, 1], 'autotile': 'mask4', 'mask': MASK, 'mask_means': 'neighbour faces open space', 'frames': 16, 'rows': rowdoc, 'tint': 'multiply',
        'layout': '16 columns (mask) x %d rows' % rows, 'shapes': 'tiles/shapes.json',
        'glow': {'image': 'hull_skin_shapes_glow.png', 'frame': [22, 22], 'offset': [-3, -3], 'layout': 'same grid as this sheet'},
        'notes': 'Skin for shaped cells (same sheet layout as walls_shapes.png). The cut edge (diagonal or arc) always faces space; mask bits say which FLAT edges also face space. '
                 'Joint lines run on the top and left edges. ' + skin_mask})
    _glow_sheet(art_dir, 'tiles/hull_skin_shapes_glow', [[skin_glow(skin_fr[r][c][1]) for c in range(16)] for r in range(rows)], 16, rows)
    # decals
    spr, rects, g = decal_atlas()
    out_spr('tiles/hull_skin_decals', spr, {
        'frame': [16, 16], 'cells': [1, 1], 'rects': rects, 'tint': 'multiply',
        'anims': {'lamp': [rects['light_on'][0] // 16, 2, 1]},
        'glow': {'image': 'hull_skin_decals_glow.png', 'frame': [96, 16], 'offset': [0, 0], 'blend': 'add (preferred) or alpha-over', 'note': 'same atlas size; lit pixels of light_on and the antenna tip glow (neutral white, tint it)'},
        'notes': 'Greeble decals, rects are [x, y, w, h] in this image: vent (32x16, spans two cells), antenna stub, panel hatch, light_on / light_off (blink between them). '
                 'Draw over a skin cell, centred. All art sits inside x,y = 3..12 of each 16px cell, so it never touches the 3px rim on any side. Sprinkle deterministically (position hash), a few per large run of skin.'})
    glow_img = Rgba(96, 16)
    glow_img.blit_rgba(g, 0, 0)
    save_png(os.path.join(art_dir, 'tiles/hull_skin_decals_glow.png'), 96, 16, glow_img.bytes())
    GLOW_FILES.append('tiles/hull_skin_decals_glow.png')
    return GLOW_FILES


def _glow_sheet(art_dir, rel, frames, cols, rows):
    """grid of 22x22 glow frames (frames: flat list of cols, or list of rows of cols)."""
    if rows == 1 and not isinstance(frames[0], list): frames = [frames]
    sh = Rgba(cols * 22, rows * 22)
    for r in range(rows):
        for c in range(cols): sh.blit_rgba(frames[r][c], c * 22, r * 22)
    save_png(os.path.join(art_dir, rel + '.png'), sh.w, sh.h, sh.bytes())
    GLOW_FILES.append(rel + '.png')


GLOW_FILES = []


# ======================================================================== CHECKS
def check_shapes():
    bad = 0
    P = cell_polys()
    for n in SHAPE_CELLS:                                          # art follows the polygon
        a, p = area(P[n]), len(base_region(n)) / 256.0
        if abs(a - p) > 0.04: print('AREA MISMATCH', n, round(a, 4), round(p, 4)); bad += 1
    for n in SHAPE_CELLS:                                          # orientations are rigid
        for o in range(ORIENTS):
            if len(oriented(n, o)) != len(base_region(n)): print('ORIENT LOSES PIXELS', n, o); bad += 1
    full = base_region('full')
    for fn, ref in ((paint_standard, T.wall_standard), (paint_armor, T.wall_armor)):   # same language as the straight walls
        for m in range(16):
            a, b = fn(full, m)[0], ref(m)
            nd = sum(1 for y in range(16) for x in range(16) if a.get(x, y) != b.get(x, y))
            if nd > 2: print('ENGINE DIFFERS FROM STRAIGHT WALL', fn.__name__, m, nd); bad += 1
    for piece in ('slope2', 'round2'):                             
        for o in range(ORIENTS):
            cells, _ = piece_cells(piece, o)
            at = {(x, y): n for x, y, n in cells}
            for (x, y), n in at.items():
                for side, (dx, dy) in SIDE_DIR.items():
                    q = (x + dx, y + dy)
                    if q not in at: continue
                    a = set(p[1] if side in (E, W_) else p[0] for p in edge_run(oriented(n, o), side))
                    b = set(p[1] if side in (E, W_) else p[0] for p in edge_run(oriented(at[q], o), OPP[side]))
                    if len(a ^ b) > 1: print('PIECE EDGES DO NOT MEET', piece, o, (x, y), side); bad += 1
    print('shapes:', 'OK' if not bad else '%d problems' % bad)
    return bad
