"""Top-down (plan view) ships for the gate scenes: polygons in local coordinates (u along the nose, v across, in units of L) turned to any heading,
shaded from the top-left in screen space (so a ship pointing any way is lit the same), with a bevel rim and a 1 px outline. Deterministic."""
import math
from ill import *

def T(cx, cy, ang):
    a = math.radians(ang); c, s = math.cos(a), math.sin(a)
    return lambda u, v: (cx + u * c - v * s, cy + u * s + v * c)

def tcells(tr, L, pts): return poly_cells([tr(u * L, v * L) for (u, v) in pts])

def lit(im, cells, ramp, cx, cy, L, rim=True, outline='K', sharp=2.4, bevel=True):
    """flat panels shaded by their position along the light (top-left = ramp[-1]); rim light on the top-left edge, shadow on the bottom-right."""
    n = len(ramp)
    for (x, y) in cells:
        t = 0.5 - ((x - cx) + (y - cy)) / (1.6 * L)
        f = max(0.0, min(1.0, t)) * (n - 1)
        i0 = int(math.floor(f)); fr = max(0.0, min(1.0, (f - i0 - 0.5) * sharp + 0.5))
        im.put(x, y, ramp[min(n - 1, i0 + (1 if fr > bay(x, y) else 0))])
    if bevel and L >= 9:
        for (x, y) in cells:
            if (x - 1, y - 1) not in cells or (x, y - 1) not in cells and (x - 1, y) not in cells: im.put(x, y, ramp[-1])
            elif (x + 1, y + 1) not in cells: im.put(x, y, ramp[0])
    if outline: im.outline(cells, outline, diag=True)

def exhaust(im, gl, tr, L, u, v, ln, f, col=('H', 'y', 'o'), a=90):
    for k in range(int(ln)):
        w = 0.5 * (1 - k / float(ln))
        x, y = tr(u - k, v)
        c = col[0] if k < ln * 0.3 else col[1] if k < ln * 0.65 else col[2]
        im.put(int(round(x)), int(round(y)), c)
    x, y = tr(u - ln * 0.5, v)
    gl.blob(x, y, ln + 2, col[2] if col[2] != 'o' else 'o', a, 1.6)

# ------------------------------------------------------------------ the Concord escort: symmetrical, clean, a blue spine
def concord(im, gl, cx, cy, ang, L, f, ph=0, blue='b'):
    tr = T(cx, cy, ang)
    wing = [(0.1, 0.14), (-0.3, 0.42), (-0.46, 0.36), (-0.32, 0.14)]
    for sg in (1, -1):
        cs = tcells(tr, L, [(u, v * sg) for (u, v) in wing])
        lit(im, cs, ['E', 'W', 'S', 'M'], cx, cy, L)
    hull = [(0.5, 0), (0.36, 0.09), (0.05, 0.16), (-0.3, 0.17), (-0.5, 0.13), (-0.5, -0.13), (-0.3, -0.17), (0.05, -0.16), (0.36, -0.09)]
    hc = tcells(tr, L, hull)
    lit(im, hc, ['W', 'S', 'M', 'L', 'H'], cx, cy, L)
    # the blue spine and the bridge light
    for k in range(int(L * 0.6)):
        x, y = tr(L * 0.32 - k, 0); xi, yi = int(round(x)), int(round(y))
        if (xi, yi) in hc and L >= 10: im.put(xi, yi, blue)
    x, y = tr(L * 0.2, 0)
    if L >= 10: im.put(int(round(x)), int(round(y)), 'y')
    for sg in (1, -1):
        x, y = tr(-L * 0.5 - 1, sg * L * 0.07)
        im.put(int(round(x)), int(round(y)), 'W')
        exhaust(im, gl, tr, L, -L * 0.5 - 2, sg * L * 0.07, max(2, L * 0.25) + (f + ph) % 2, f, ('H', 'z', 'b'), 70)
    # nav lights on the wing tips: red on the left, green on the right (they blink in step across the whole fleet)
    for sg, c in ((1, 'g'), (-1, 'r')):
        x, y = tr(-L * 0.4, sg * L * 0.36)
        if (f + ph) % 2 == 0 and L >= 9: im.put(int(round(x)), int(round(y)), c); gl.blob(x, y, 3, c, 90, 1.6)

# ------------------------------------------------------------------ the Clan ship: lopsided, patched, hazard tape, loud
def scrap(im, gl, cx, cy, ang, L, f, seed=1, ph=0):
    r = Lcg(seed)
    tr = T(cx, cy, ang)
    side = 1 if seed % 2 else -1
    hull = [(0.5, 0.02 * side), (0.38, 0.13), (0.2, 0.17), (-0.1, 0.18), (-0.3, 0.21), (-0.5, 0.16), (-0.5, -0.14), (-0.3, -0.19), (-0.1, -0.16), (0.2, -0.17), (0.38, -0.12)]
    pod = [(0.12, 0.16 * side), (-0.25, 0.2 * side), (-0.3, 0.42 * side), (-0.05, 0.4 * side)]
    pc = tcells(tr, L, pod)
    lit(im, pc, ['n', 'q', 'u', 'T'], cx, cy, L)
    hc = tcells(tr, L, hull)
    lit(im, hc, ['E', 'W', 'S', 'M', 'L'] if seed % 3 else ['n', 'q', 'u', 'T', 'Y'], cx, cy, L)
    # patches and hazard tape
    patch = tcells(tr, L, [(0.0, -0.1), (-0.2, -0.1), (-0.2, 0.08), (0.0, 0.08)])
    for (x, y) in patch & hc: im.put(x, y, 'u' if (x + y) % 5 else 'T')
    for k in range(3):
        x, y = tr(-L * 0.38 + k, L * 0.0 + r.rng(-1, 1))
        im.put(int(round(x)), int(round(y)), 'a' if (k + seed) % 2 else 'K')
    x, y = tr(L * 0.28, 0)
    if L >= 10: im.put(int(round(x)), int(round(y)), 'y')
    x, y = tr(-L * 0.5 - 1, 0)
    for k in (-1, 1) if L >= 14 else (0,):
        x, y = tr(-L * 0.5 - 1, k * L * 0.05)
        im.put(int(round(x)), int(round(y)), 'W')
        exhaust(im, gl, tr, L, -L * 0.5 - 2, k * L * 0.05, max(2, L * 0.3) + (f + ph + seed) % 3, f, ('H', 'y', 'o'), 90)
    # a lamp that blinks out of step
    x, y = tr(L * 0.1, 0.11 * L * side)
    if (f + seed) % 2 == 0 and L >= 9: im.put(int(round(x)), int(round(y)), 'r'); gl.blob(x, y, 3, 'r', 90, 1.6)

# ------------------------------------------------------------------ a Lumen skiff, plan view: a crystal dart
def lumen_td(im, gl, cx, cy, ang, L, f, ph=0):
    """a Lumen skiff in plan view: a crystal dart, two lit facets, a cyan keel line and a trail of shed dust."""
    tr = T(cx, cy, ang)
    body_ = [(0.5, 0), (0.12, 0.2), (-0.28, 0.42), (-0.5, 0.16), (-0.42, 0), (-0.5, -0.16), (-0.28, -0.42), (0.12, -0.2)]
    cs = tcells(tr, L, body_)
    lit(im, cs, ['I', 'J', 'j', 'C', 'c'], cx, cy, L, outline='N', sharp=3.0)
    up = tcells(tr, L, [(0.5, 0), (0.12, -0.2), (-0.28, -0.42), (-0.3, -0.05)])
    for (x, y) in up & cs: im.put(x, y, 'j' if (x + y) % 3 else 'C')
    for k in range(int(L * 0.9)):
        x, y = tr(L * 0.5 - k, 0)
        xi, yi = int(round(x)), int(round(y))
        if (xi, yi) in cs: im.put(xi, yi, 'z' if k % 4 else 'H')
    x, y = tr(L * 0.1, 0); im.put(int(round(x)), int(round(y)), 'H')
    gl.blob(x, y, L * 0.9, 'c', 80, 1.7)
    for k in range(5):
        x, y = tr(-L * 0.5 - 2 - k * 3 - (f + ph) % 2 * 2, ((k % 2) * 2 - 1) * (1 + k * 0.4))
        im.put(int(round(x)), int(round(y)), 'c' if k < 2 else 'C')
