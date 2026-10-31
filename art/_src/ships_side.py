"""Side-view ships for the ending art, all facing RIGHT (engines on the left), lit from the top-left. Polygon hulls shaded in bands,
a 1 px outline, panel seams, lamps and engine flames; every one takes a length L so the same design reads at any size. Deterministic (Lcg seeds)."""
import math
from ill import *

def body(im, cells, ramp, y0, y1, outline='K', sharp=2.8, tl=0.0, x0=None, x1=None):
    """shade `cells` top (ramp[-1], lit) to bottom (ramp[0]); a touch of left-light via tl."""
    n = len(ramp)
    for (x, y) in cells:
        t = (y - y0) / float(max(1, y1 - y0))
        if x0 is not None: t += tl * ((x - x0) / float(max(1, x1 - x0)))
        v = 1.0 - max(0.0, min(1.0, t))
        f = v * (n - 1)
        i0 = int(math.floor(f)); fr = max(0.0, min(1.0, (f - i0 - 0.5) * sharp + 0.5))
        im.put(x, y, ramp[min(n - 1, i0 + (1 if fr > bay(x, y) else 0))])
    # rim light on the top-left edge, shadow on the bottom-right
    for (x, y) in cells:
        if (x, y - 1) not in cells: im.put(x, y, ramp[-1])
    if outline: im.outline(cells, outline)

def flame(im, gl, x, y, L, f, col=('H', 'y', 'o'), r=2):
    """an exhaust trailing LEFT from (x, y): L px long, flickering with the frame."""
    ln = L + (f % 2) * 2 - (1 if f == 3 else 0)
    for k in range(ln):
        w = max(0, r - k * r // max(1, ln - 1)) if False else int(round(r * (1 - k / float(ln))))
        for dy in range(-w, w + 1):
            c = col[0] if (abs(dy) == 0 and k < ln * 0.4) else col[1] if abs(dy) <= max(0, w - 1) or k < ln * 0.5 else col[2]
            im.put(x - k, y + dy, c)
    gl.blob(x - ln // 2, y, ln + 3, col[2] if col[2] != 'o' else 'o', 110, 1.6, squash=0.55)

def lamp(im, gl, x, y, c, f, ph=0, blink=True, r=4):
    on = (not blink) or ((f + ph) % 2 == 0)
    im.put(x, y, c if on else 'W')
    if on: gl.blob(x, y, r, c if c != 'y' else 'y', 100, 1.8)

def windows(im, gl, x, y, n, step, f, col='y', ph=0, w=1, h=1, glow=True):
    for k in range(n):
        on = (k * 7 + ph) % 5 != 0 or f % 2 == 0
        c = col if on else 'W'
        for i in range(w):
            for j in range(h): im.put(x + k * step + i, y + j, c)
        if on and glow and k % 2 == 0: gl.blob(x + k * step, y, 4, col, 60, 1.8)

def hazard(im, x, y, w, h, flip=False):
    for j in range(h):
        for i in range(w):
            im.put(x + i, y + j, 'a' if ((i + j) // 2) % 2 == 0 else 'K')

def container(im, x, y, w, h, c, seed):
    r = Lcg(seed)
    im.rect(x, y, w, h, c)
    for i in range(2, w - 1, 3): im.vline(x + i, y + 1, h - 2, darken(c))
    im.hline(x, y, w, lighten(c)); im.vline(x, y, h, lighten(c)); im.hline(x, y + h - 1, w, 'K'); im.vline(x + w - 1, y, h, 'K')

# ------------------------------------------------------------------ the Clan hauler: boxy, patched, loaded
def hauler(im, gl, x, y, L, f, seed=1, cargo=('u', 'W', 'a', 'E'), tag=None):
    r = Lcg(seed)
    H = int(L * 0.30)
    x0, x1 = x - L // 2, x + L // 2
    hull = poly_cells([(x0 + 3, y - H // 2), (x1 - 14, y - H // 2), (x1, y - H // 6), (x1, y + H // 2 - 2), (x1 - 6, y + H // 2), (x0 + 6, y + H // 2), (x0, y + H // 2 - 3)])
    body(im, hull, ['E', 'W', 'S', 'M'], y - H // 2, y + H // 2)
    # cargo on the back
    cw = max(8, L // 6)
    cx = x0 + 8
    k = 0
    while cx + cw < x1 - 22:
        ch = r.rng(int(L * 0.10), int(L * 0.17))
        container(im, cx, y - H // 2 - ch, cw, ch, cargo[k % len(cargo)], seed + k); 
        if r.below(2): container(im, cx + 1, y - H // 2 - ch - int(L * 0.09), cw - 2, int(L * 0.09), cargo[(k + 1) % len(cargo)], seed + 20 + k)
        cx += cw + 1; k += 1
    # the cab: a tall block with a lit window strip
    cab = rect_cells(x1 - 20, y - H // 2 - int(L * 0.13), 14, int(L * 0.13))
    body(im, cab, ['W', 'S', 'M', 'L'], y - H // 2 - int(L * 0.13), y - H // 2)
    im.hline(x1 - 18, y - H // 2 - int(L * 0.09), 10, 'y'); im.hline(x1 - 18, y - H // 2 - int(L * 0.09) + 1, 10, 'a')
    gl.blob(x1 - 13, y - H // 2 - int(L * 0.09), 10, 'y', 90, 1.6)
    # plating: rust patches, a hazard band, rivet rows, a long seam
    for (px_, py_, pw, ph) in ((x0 + 12, y - H // 2 + 2, L // 5, H // 3), (x + 4, y, L // 6, H // 3), (x1 - 30, y - H // 2 + 2, 8, H // 3)):
        for j in range(ph):
            for i in range(pw):
                if (px_ + i, py_ + j) in hull: im.put(px_ + i, py_ + j, 'T' if j == 0 else 'u' if j < ph - 1 else 'n')
        for (bx, by) in ((px_ + 1, py_ + 1), (px_ + pw - 2, py_ + 1)): im.put(bx, by, 'M')
    hazard(im, x0 + 2, y + H // 2 - 5, max(6, L // 10), 3)
    im.hline(x0 + 4, y + 1, L - 14, 'E')
    for i in range(x0 + 8, x1 - 8, 6): im.put(i, y + H // 2 - 3, 'M')
    # engine block at the back: three bells
    for k in range(3):
        ey = y - H // 2 + 3 + k * (H // 3)
        im.rect(x0 - 3, ey, 4, max(3, H // 4), 'W'); im.vline(x0 - 3, ey, max(3, H // 4), 'S'); im.hline(x0 - 3, ey, 4, 'M'); im.hline(x0 - 3, ey + max(3, H // 4) - 1, 4, 'K')
        flame(im, gl, x0 - 4, ey + max(3, H // 4) // 2, int(L * 0.2) - k * 2, f + k, r=1 if L < 70 else 2)
    # lamps and a mast
    im.vline(x + 2, y - H // 2 - int(L * 0.2), int(L * 0.2) - 2, 'M')
    lamp(im, gl, x + 2, y - H // 2 - int(L * 0.2) - 1, 'r', f, 0, True, 5)
    lamp(im, gl, x1 - 2, y + 1, 'a', f, 1, False, 4)
    return hull

# ------------------------------------------------------------------ the Concord frigate: clean, symmetrical, long and slim
def frigate(im, gl, x, y, L, f, seed=1):
    H = int(L * 0.2)
    x0, x1 = x - L // 2, x + L // 2
    hull = poly_cells([(x0 + 2, y - H // 2), (x + L * 0.18, y - H // 2), (x1, y - 1), (x1, y + 1), (x + L * 0.18, y + H // 2), (x0 + 2, y + H // 2), (x0, y + H // 2 - 2), (x0, y - H // 2 + 2)])
    body(im, hull, ['W', 'S', 'M', 'L'], y - H // 2, y + H // 2, sharp=3.2)
    # blue band, panel seams, registry marks
    for i in range(x0 + 6, int(x + L * 0.24)):
        im.put(i, y, 'b' if i % 7 else 'j'); im.put(i, y + 1, 'j')
    for sx in range(x0 + 10, int(x + L * 0.2), 9): im.vline(sx, y - H // 2 + 1, H - 2, 'S')
    for i in range(x0 + 8, x0 + 8 + 9, 2): im.put(i, y - H // 2 + 3, 'j')           # registry stencil
    # bridge tower
    tw = max(6, L // 7)
    tower = poly_cells([(x - 4, y - H // 2), (x - 2, y - H // 2 - int(L * 0.1)), (x - 2 + tw, y - H // 2 - int(L * 0.1)), (x + tw, y - H // 2)])
    body(im, tower, ['S', 'M', 'L', 'H'], y - H // 2 - int(L * 0.1), y - H // 2)
    im.hline(x - 1, y - H // 2 - int(L * 0.1) + 2, tw - 1, 'b'); 
    im.hline(x - 1, y - H // 2 - int(L * 0.1) + 3, tw - 1, 'y')
    gl.blob(x + tw // 2, y - H // 2 - int(L * 0.1) + 3, 8, 'y', 70, 1.6)
    # keel fin and dorsal fin (symmetry)
    fin = poly_cells([(x0 + 2, y - H // 2), (x0 - 3, y - H // 2 - int(L * 0.14)), (x0 + 8, y - H // 2 - int(L * 0.14)), (x0 + 12, y - H // 2)])
    body(im, fin, ['S', 'M', 'L'], y - H // 2 - int(L * 0.14), y - H // 2)
    im.hline(x0 - 1, y - H // 2 - int(L * 0.14) + 1, 8, 'b')
    fin2 = poly_cells([(x0 + 2, y + H // 2), (x0 - 3, y + H // 2 + int(L * 0.1)), (x0 + 8, y + H // 2 + int(L * 0.1)), (x0 + 12, y + H // 2)])
    body(im, fin2, ['W', 'S', 'M'], y + H // 2, y + H // 2 + int(L * 0.1), outline='K')
    # two engine nacelles with blue-white flames
    for ey in (y - H // 4, y + H // 4):
        im.rect(x0 - 3, ey - 1, 4, 3, 'W'); im.hline(x0 - 3, ey - 1, 4, 'M')
        flame(im, gl, x0 - 4, ey, int(L * 0.2), f, col=('H', 'z', 'b'), r=1)
    lamp(im, gl, x1 - 3, y, 'r', f, 0, True, 4)
    lamp(im, gl, x + 6, y + H // 2 - 1, 'g', f, 1, True, 4)
    return hull

# ------------------------------------------------------------------ a Lumen skiff: a crystal kite, navy facets with cyan edges
def lumen(im, gl, x, y, L, f, seed=1):
    H = int(L * 0.56)
    x0, x1 = x - L // 2, x + L // 2
    P = [(x0, y), (x0 + L * 0.34, y - H // 2), (x1, y), (x0 + L * 0.34, y + H // 2)]
    cells = poly_cells(P)
    top = poly_cells([P[0], P[1], P[2], (x0 + L * 0.34, y)])
    bot = poly_cells([P[0], (x0 + L * 0.34, y), P[2], P[3]])
    im.fill(top, 'J'); im.fill(bot, 'I')
    mid = poly_cells([P[0], P[1], (x0 + L * 0.34, y)])
    im.fill(mid, 'j')
    im.outline(cells, 'N')
    for (a, b) in zip(P, P[1:] + P[:1]): im.line(a[0], a[1], b[0], b[1], 'c')
    im.line(P[0][0], P[0][1], P[2][0], P[2][1], 'C')
    im.line(P[1][0], P[1][1], x0 + L * 0.34, y, 'c')
    im.put(int(x0 + L * 0.34), y, 'H'); im.put(int(x0 + L * 0.34) - 1, y, 'z')
    gl.blob(x0 + L * 0.34, y, L * 0.7, 'c', 70 if f % 2 == 0 else 55, 1.7, squash=0.8)
    for k in range(3):                                                # a trail of shed crystal dust
        im.put(x0 - 2 - k * 3 - (f % 2), y + (k % 2) * 2 - 1, 'c' if k == 0 else 'C')
    return cells

# ------------------------------------------------------------------ a tug with a funnel, towing a barge by a cable
def tug(im, gl, x, y, L, f, seed=1, tow=True):
    H = int(L * 0.42)
    x0, x1 = x - L // 2, x + L // 2
    hull = poly_cells([(x0 + 3, y - H // 2), (x1 - 8, y - H // 2), (x1, y), (x1 - 4, y + H // 2), (x0 + 4, y + H // 2), (x0, y + H // 2 - 3), (x0, y - H // 2 + 3)])
    body(im, hull, ['n', 'q', 'u', 'T'], y - H // 2, y + H // 2)
    hazard(im, x0 + 2, y + H // 2 - 4, L // 3, 2)
    cab = rect_cells(x + 2, y - H // 2 - 6, L // 3, 6)
    body(im, cab, ['W', 'S', 'M', 'L'], y - H // 2 - 6, y - H // 2)
    im.hline(x + 4, y - H // 2 - 4, L // 3 - 4, 'y')
    gl.blob(x + L // 6 + 4, y - H // 2 - 4, 8, 'y', 80, 1.6)
    fun = rect_cells(x - L // 4, y - H // 2 - 8, 5, 8)
    body(im, fun, ['E', 'W', 'S', 'M'], y - H // 2 - 8, y - H // 2)
    for k in range(3):                                                # smoke
        im.put(x - L // 4 + 1 - k - (f % 2), y - H // 2 - 10 - k * 3, 'W' if k < 2 else 'E')
    im.rect(x0 - 3, y - 3, 4, 7, 'W'); im.vline(x0 - 3, y - 3, 7, 'S')
    flame(im, gl, x0 - 4, y, int(L * 0.28), f, r=2)
    lamp(im, gl, x1 - 6, y - H // 2 - 1, 'a', f, 0, False, 4)
    return hull

def barge(im, gl, x, y, L, f, seed=1):
    r = Lcg(seed)
    H = int(L * 0.28)
    x0, x1 = x - L // 2, x + L // 2
    hull = poly_cells([(x0, y - H // 2), (x1, y - H // 2), (x1 - 3, y + H // 2), (x0 + 3, y + H // 2)])
    body(im, hull, ['n', 'q', 'u', 'u'], y - H // 2, y + H // 2)
    im.hline(x0 + 2, y, L - 4, 'n')
    cx = x0 + 3
    k = 0
    while cx + 8 < x1 - 3:
        ch = r.rng(6, 11)
        container(im, cx, y - H // 2 - ch, 8, ch, ['W', 'a', 'u', 'E', 'b'][k % 5], seed + k); cx += 9; k += 1
    lamp(im, gl, x1 - 1, y - H // 2 - 2, 'g', f, 1, True, 4)

# ------------------------------------------------------------------ the liner: two welded hulls, rows of lit windows, scaffolding between
def liner(im, gl, x, y, L, f, seed=1):
    H = int(L * 0.22)
    x0, x1 = x - L // 2, x + L // 2
    h1 = poly_cells([(x0 + 2, y - H), (x + L * 0.1, y - H), (x + L * 0.1, y + 1), (x0, y + 1), (x0, y - H + 2)])
    h2 = poly_cells([(x + L * 0.12, y - H + 3), (x1 - 6, y - H + 3), (x1, y - 2), (x1, y + H // 3), (x + L * 0.12, y + H // 3)])
    body(im, h1, ['W', 'S', 'M', 'L'], y - H, y + 1)
    body(im, h2, ['n', 'q', 'u', 'T'], y - H + 3, y + H // 3)
    for k in range(3):                                                # the weld: a scaffold of struts
        sx = int(x + L * 0.1) - 2 + k * 2
        im.line(sx, y - H + 3, sx + 3, y + H // 3 - 1, 'M'); im.line(sx + 3, y - H + 3, sx, y + H // 3 - 1, 'S')
    for ry in (y - H + 4, y - H + 8, y - H + 12):
        windows(im, gl, x0 + 4, ry, int((L * 0.38) / 3), 3, f, 'y', ph=ry)
    windows(im, gl, int(x + L * 0.16), y - H + 8, 6, 3, f, 'a', ph=3)
    hazard(im, x0 + 2, y - 4, 10, 3)
    for ey in (y - H // 2, y - H // 2 + 6):
        im.rect(x0 - 3, ey - 1, 4, 4, 'W'); im.vline(x0 - 3, ey - 1, 4, 'S')
        flame(im, gl, x0 - 4, ey + 1, int(L * 0.16), f + ey, r=1)
    lamp(im, gl, x1 - 2, y - H + 4, 'r', f, 0, True, 4)
    lamp(im, gl, x0 + 12, y - H - 1, 'g', f, 1, True, 4)
    return h1 | h2

def raft(im, gl, x, y, L, f, seed=1):
    r = Lcg(seed)
    x0, x1 = x - L // 2, x + L // 2
    deck = rect_cells(x0, y, L, 4)
    body(im, deck, ['n', 'q', 'Q', 'Q'], y, y + 4)
    for i in range(x0 + 3, x1, 5): im.vline(i, y + 1, 3, 'n')
    for k in range(3):                                                # barrels and crates
        container(im, x0 + 4 + k * 7, y - 5, 6, 5, ['u', 'W', 'a'][k], seed + k)
    tent = poly_cells([(x + 2, y), (x + 8, y - 9), (x + 14, y)])
    body(im, tent, ['Z', 'V', 'X'], y - 9, y)
    # a string of lamps along the deck
    for k in range(5):
        lamp(im, gl, x0 + 2 + k * (L // 5), y - 2 - (k % 2), 'y', f, k, True, 4)
    im.rect(x0 - 3, y, 4, 3, 'W')
    flame(im, gl, x0 - 4, y + 1, 7, f, r=1)

def dart(im, gl, x, y, L, f, seed=1, c=('S', 'M', 'L')):
    H = max(3, L // 3)
    cells = poly_cells([(x - L // 2, y - H // 2), (x + L // 4, y - H // 2), (x + L // 2, y), (x + L // 4, y + H // 2), (x - L // 2, y + H // 2)])
    body(im, cells, ['W', c[0], c[1], c[2]], y - H // 2, y + H // 2)
    im.put(x + L // 6, y - 1, 'y')
    flame(im, gl, x - L // 2 - 1, y, max(3, L // 3), f + seed, r=1)
