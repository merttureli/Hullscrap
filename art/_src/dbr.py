"""Debris renderer: a small object is a stack of layers (silhouette + height + colour ramp); each tumble frame turns the object and keeps the light
on the top-left, so every frame is lit right and nothing is ever rotated after shading. Every pixel is still a palette letter and the result
is cleaned up (no stray pixels) and outlined with the shared near-black 1 px line. Pure stdlib, no randomness (hash noise only): byte-identical rebuilds.

Coordinates: object-local (u, v), origin at the frame centre, +u right, +v down. `turn` degrees clockwise take local to world."""
import math
from px import *

LX, LY, LZ = -0.50, -0.62, 0.60                    # light from the top-left, up out of the page
_n = math.sqrt(LX * LX + LY * LY + LZ * LZ)
LX, LY, LZ = LX / _n, LY / _n, LZ / _n

# ------------------------------------------------------------------ signed distances (negative inside)
def sd_circle(u, v, cx, cy, r): return math.hypot(u - cx, v - cy) - r
def sd_ell(u, v, cx, cy, rx, ry): return (math.hypot((u - cx) / rx, (v - cy) / ry) - 1) * min(rx, ry)
def sd_box(u, v, cx, cy, hw, hh):
    dx, dy = abs(u - cx) - hw, abs(v - cy) - hh
    return math.hypot(max(dx, 0), max(dy, 0)) + min(max(dx, dy), 0)
def sd_rbox(u, v, cx, cy, hw, hh, r): return sd_box(u, v, cx, cy, hw - r, hh - r) - r
def sd_seg(u, v, ax, ay, bx, by, r=0.0):
    px_, py_ = u - ax, v - ay; dx, dy = bx - ax, by - ay
    t = max(0.0, min(1.0, (px_ * dx + py_ * dy) / (dx * dx + dy * dy or 1)))
    return math.hypot(px_ - dx * t, py_ - dy * t) - r
def sd_poly(u, v, pts):
    d = 1e9; inside = False; n = len(pts)
    for k in range(n):
        ax, ay = pts[k]; bx, by = pts[(k + 1) % n]
        d = min(d, sd_seg(u, v, ax, ay, bx, by))
        if (ay > v) != (by > v) and u < (bx - ax) * (v - ay) / (by - ay) + ax: inside = not inside
    return -d if inside else d
def sd_blob(u, v, cx, cy, R, harm):
    """a lumpy disc: radius R modulated by harmonics [(k, amp, phase_deg)]."""
    dx, dy = u - cx, v - cy
    a = math.atan2(dy, dx)
    r = R * (1 + sum(amp * math.cos(k * a + math.radians(ph)) for (k, amp, ph) in harm))
    return math.hypot(dx, dy) - r
def blob_h(d, depth):
    """dome height from a signed distance: round profile over `depth` px."""
    if d >= 0: return 0.0
    t = min(1.0, -d / depth)
    return depth * math.sqrt(1 - (1 - t) * (1 - t))
def bevel_h(d, bw, top=1.0):
    """flat slab with a bevel `bw` px wide: height rises linearly from the edge."""
    if d >= 0: return 0.0
    return top * min(1.0, -d / bw)
def smooth(t): return t * t * (3 - 2 * t)
def planes(spec):
    """a convex faceted solid: height = min over planes of (c - slope * distance along deg). deg 0 faces +u (right), 90 faces +v (down), 225 is up-left.
    spec: [(deg, slope, reach)] where reach is where that plane meets the ground (its silhouette edge). slope 0 = a flat cap at height `reach`."""
    P = [(math.cos(math.radians(a)), math.sin(math.radians(a)), sl, (sl * r if sl else r)) for (a, sl, r) in spec]
    def H(u, v):
        return min((c if sl == 0 else c - sl * (u * cx + v * cy)) for (cx, cy, sl, c) in P)
    return H
def solid_planes(spec, ramp, lo=-0.1, hi=1.05, paint=None, mode='add'):
    H = planes(spec)
    return Layer(lambda u, v: -H(u, v), lambda u, v, d: -d if mode == 'set' else -d, ramp, paint=paint, lo=lo, hi=hi, mode=mode)
def rot(u, v, deg, cx=0.0, cy=0.0):
    """a point seen from a part turned by deg about (cx, cy): for sub-shapes at an angle."""
    t = math.radians(-deg); c, s_ = math.cos(t), math.sin(t); x, y = u - cx, v - cy
    return x * c - y * s_, x * s_ + y * c
def polyline_sd(u, v, pts, r=0.5):
    return min(sd_seg(u, v, a[0], a[1], b[0], b[1], r) for a, b in zip(pts, pts[1:]))

# ------------------------------------------------------------------ hash noise (integer based, deterministic)
def _hash(ix, iy, seed):
    n = (ix * 374761393 + iy * 668265263 + seed * 2147483647) & 0xFFFFFFFF
    n = ((n ^ (n >> 13)) * 1274126177) & 0xFFFFFFFF
    return ((n ^ (n >> 16)) & 0xFFFF) / 65535.0
def vnoise(x, y, seed=1):
    ix, iy = math.floor(x), math.floor(y); fx, fy = smooth(x - ix), smooth(y - iy)
    a, b = _hash(ix, iy, seed), _hash(ix + 1, iy, seed); c, d = _hash(ix, iy + 1, seed), _hash(ix + 1, iy + 1, seed)
    return (a + (b - a) * fx) * (1 - fy) + (c + (d - c) * fx) * fy
def fbm(x, y, seed=1, oct=3):
    s, amp, tot, f = 0.0, 1.0, 0.0, 1.0
    for o in range(oct):
        s += amp * vnoise(x * f, y * f, seed + o * 17); tot += amp; amp *= 0.5; f *= 2.0
    return s / tot

# ------------------------------------------------------------------ the layer stack
class Layer:
    """sdf: (u, v) -> signed distance. h: (u, v, d) -> height added where d < 0. ramp: letters dark -> light, picked by the light on the surface.
    paint: (u, v, I, c) -> letter or None, for stripes and fixed colours (overrides the ramp where it returns a letter).
    solid False = a decal: only paints (and shapes the height) where a solid layer is already there."""
    def __init__(s, sdf, h=None, ramp=None, paint=None, solid=True, lo=-0.15, hi=0.95, mode='add'):
        s.sdf, s.h, s.ramp, s.paint, s.solid, s.lo, s.hi, s.mode = sdf, h, ramp, paint, solid, lo, hi, mode

def pick(ramp, I, lo=-0.15, hi=0.95):
    k = int((I - lo) / (hi - lo) * len(ramp))
    return ramp[max(0, min(len(ramp) - 1, k))]

class Ctx:
    """one sample: object coords (u, v), world offset from the frame centre (x, y) and the turn."""
    __slots__ = ('u', 'v', 'x', 'y', 'cs', 'sn')

class Obj:
    """subclass: set W, H, turns (degrees per tumble frame) and layers(); optionally specks(turn) and after(spr, turn)."""
    W = H = 16
    turns = (0, 90, 180, 270)
    ss = 4                                   # supersampling per axis
    def layers(s): raise NotImplementedError
    def specks(s, turn): return []           # [(u, v, letter)] placed at pixel level after cleanup (sparkles, bright ore dots)
    def after(s, spr, turn): pass            # hand touches on the final pixel grid (before the outline)

    def render(s, turn, outline=True):
        W, H, ss = s.W, s.H, s.ss
        t = math.radians(turn); cs, sn = math.cos(t), math.sin(t)
        L = s.layers()
        solid = [l for l in L if l.solid]
        order = list(reversed(L))             # topmost first
        spr = Spr(W, H)
        e = 0.5
        def world(u, v): return u * cs - v * sn, u * sn + v * cs      # local -> world offset
        def height(u, v):
            tot = 0.0
            for l in L:
                if l.h is None: continue
                d = l.sdf(u, v)
                if d < 0:
                    if not l.solid and not any(q.sdf(u, v) < 0 for q in solid): continue
                    tot = l.h(u, v, d) if l.mode == 'set' else tot + l.h(u, v, d)
            return tot
        for j in range(H):
            for i in range(W):
                votes = {}; n = 0
                for sj in range(ss):
                    for si in range(ss):
                        wx = i + (si + .5) / ss - W / 2; wy = j + (sj + .5) / ss - H / 2
                        u = wx * cs + wy * sn; v = -wx * sn + wy * cs
                        if not any(q.sdf(u, v) < 0 for q in solid): continue
                        h0 = height(u, v); hu = height(u + e, v); hv = height(u, v + e)
                        gu, gv = (hu - h0) / e, (hv - h0) / e                # local gradient
                        nx, ny, nz = -gu, -gv, 1.0
                        nn = math.sqrt(nx * nx + ny * ny + nz * nz); nx, ny, nz = nx / nn, ny / nn, nz / nn
                        wnx, wny = nx * cs - ny * sn, nx * sn + ny * cs      # normal to world
                        I = wnx * LX + wny * LY + nz * LZ
                        c = Ctx(); c.u, c.v, c.x, c.y, c.cs, c.sn = u, v, wx, wy, cs, sn
                        ch = None
                        for l in order:
                            if l.sdf(u, v) >= 0: continue
                            if not l.solid and not any(q.sdf(u, v) < 0 for q in solid): continue
                            if l.paint:
                                ch = l.paint(u, v, I, c)
                                if ch: break
                            if l.ramp:
                                ch = pick(l.ramp, I, l.lo, l.hi); break
                        if ch is None: continue
                        votes[ch] = votes.get(ch, 0) + 1; n += 1
                if n * 2 >= ss * ss:
                    spr.g[j][i] = max(sorted(votes), key=lambda k: votes[k])
        clean(spr)
        for (u, v, ch) in s.specks(turn):
            wx, wy = world(u, v)
            x, y = int(math.floor(wx + W / 2)), int(math.floor(wy + H / 2))
            if spr.get(x, y) != '.': spr.put(x, y, ch)
        s.after(spr, turn)
        if outline: add_outline(spr)
        return spr

def clean(spr):
    """drop lone pixels: a letter with no neighbour of its own (8-way) takes the letter of the neighbours around it; solid spurs with one neighbour are trimmed."""
    for _ in range(2):
        out = [r[:] for r in spr.g]
        for y in range(spr.h):
            for x in range(spr.w):
                c = spr.g[y][x]
                if c == '.': continue
                nb = [spr.get(x + dx, y + dy) for dx in (-1, 0, 1) for dy in (-1, 0, 1) if dx or dy]
                if c in nb: continue
                solid4 = [spr.get(x + dx, y + dy) for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)) if spr.get(x + dx, y + dy) != '.']
                if len(solid4) <= 1: out[y][x] = '.'
                else:
                    cnt = {}
                    for q in solid4: cnt[q] = cnt.get(q, 0) + 1
                    out[y][x] = max(sorted(cnt), key=lambda k: cnt[k])
        spr.g = out

def add_outline(spr, c='K'):
    mask = {(x, y) for y in range(spr.h) for x in range(spr.w) if spr.g[y][x] != '.'}
    for (x, y) in mask:
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            q = (x + dx, y + dy)
            if q not in mask and 0 <= q[0] < spr.w and 0 <= q[1] < spr.h: spr.g[q[1]][q[0]] = c
    return spr

def touches_border(spr):
    """a lit pixel on the frame edge means the 1 px outline was clipped (the outline itself may sit on the edge)."""
    return any(spr.g[y][x] not in '.K' for y in range(spr.h) for x in range(spr.w) if x in (0, spr.w - 1) or y in (0, spr.h - 1))
