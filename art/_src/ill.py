"""Illustration toolkit for the ending art (320x180, palette letters from pal_endings). Stdlib only, deterministic, no `random`.
Everything is hard pixels: shapes are cell sets (polygons, ellipses), shaded with a hand-picked ramp and a 4x4 ordered dither, outlined 1 px.
Light always comes from the top-left. The glow layer is a separate soft-alpha RGBA (Glow), added over the picture by the game."""
import math
from px import png_bytes, save_rgba
import pal_endings as PE

W, H = 320, 180
RGB = PE.RGB
BAYER = [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]

def bay(x, y): return (BAYER[y & 3][x & 3] + 0.5) / 16.0

class Lcg:
    """tiny deterministic generator (same one the space art uses)."""
    def __init__(s, seed): s.s = seed & 0x7fffffff
    def next(s):
        s.s = (s.s * 1103515245 + 12345) & 0x7fffffff
        return (s.s >> 8) & 0xffff
    def below(s, n): return s.next() % n
    def pick(s, items): return items[s.below(len(items))]
    def rng(s, a, b): return a + s.below(b - a + 1)
    def f(s): return s.next() / 65536.0

# ------------------------------------------------------------------ cell sets
def rect_cells(x, y, w, h): return {(i, j) for j in range(y, y + h) for i in range(x, x + w)}

def ellipse_cells(cx, cy, rx, ry):
    out = set()
    for j in range(int(cy - ry - 1), int(cy + ry + 2)):
        for i in range(int(cx - rx - 1), int(cx + rx + 2)):
            if ((i + 0.5 - cx) / rx) ** 2 + ((j + 0.5 - cy) / ry) ** 2 <= 1.0: out.add((i, j))
    return out

def poly_cells(pts):
    """even-odd scanline fill of a polygon given as float/int vertices (pixel centres at +0.5)."""
    ys = [p[1] for p in pts]
    out = set()
    n = len(pts)
    for j in range(int(math.floor(min(ys))), int(math.ceil(max(ys))) + 1):
        yc = j + 0.5
        xs = []
        for k in range(n):
            (x0, y0), (x1, y1) = pts[k], pts[(k + 1) % n]
            if (y0 <= yc < y1) or (y1 <= yc < y0):
                xs.append(x0 + (yc - y0) * (x1 - x0) / float(y1 - y0))
        xs.sort()
        for a, b in zip(xs[0::2], xs[1::2]):
            for i in range(int(math.ceil(a - 0.5)), int(math.ceil(b - 0.5))): out.add((i, j))
    return out

def line_cells(x0, y0, x1, y1):
    x0, y0, x1, y1 = int(round(x0)), int(round(y0)), int(round(x1)), int(round(y1))
    cells = []
    dx, dy = abs(x1 - x0), -abs(y1 - y0)
    sx, sy = (1 if x0 < x1 else -1), (1 if y0 < y1 else -1)
    err = dx + dy
    while True:
        cells.append((x0, y0))
        if x0 == x1 and y0 == y1: break
        e2 = 2 * err
        if e2 >= dy: err += dy; x0 += sx
        if e2 <= dx: err += dx; y0 += sy
    return cells

def grow(cells, n=1, diag=False):
    cur = set(cells)
    for _ in range(n):
        nxt = set(cur)
        for (x, y) in cur:
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)) + (((1, 1), (-1, -1), (1, -1), (-1, 1)) if diag else ()):
                nxt.add((x + dx, y + dy))
        cur = nxt
    return cur

def shrink(cells, n=1):
    cur = set(cells)
    for _ in range(n):
        cur = {(x, y) for (x, y) in cur if all(((x + dx, y + dy) in cur) for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)))}
    return cur

def shift(cells, dx, dy): return {(x + dx, y + dy) for (x, y) in cells}

def ring_cells(cx, cy, rx, ry, th): return ellipse_cells(cx, cy, rx, ry) - ellipse_cells(cx, cy, rx - th, ry - th * ry / float(rx))

# ------------------------------------------------------------------ the canvas
class Ill:
    def __init__(s, w=W, h=H, fill='K'):
        s.w, s.h = w, h
        s.g = [[fill] * w for _ in range(h)]
    def copy(s):
        n = Ill(s.w, s.h); n.g = [r[:] for r in s.g]; return n
    def get(s, x, y): return s.g[y][x] if 0 <= x < s.w and 0 <= y < s.h else None
    def put(s, x, y, c):
        if c and c != '.' and 0 <= x < s.w and 0 <= y < s.h: s.g[y][x] = c
    def rect(s, x, y, w, h, c):
        for j in range(y, y + h):
            for i in range(x, x + w): s.put(i, j, c)
    def hline(s, x, y, n, c):
        for i in range(n): s.put(x + i, y, c)
    def vline(s, x, y, n, c):
        for j in range(n): s.put(x, y + j, c)
    def line(s, x0, y0, x1, y1, c):
        for (x, y) in line_cells(x0, y0, x1, y1): s.put(x, y, c)
    def tline(s, x0, y0, x1, y1, c, t=2):
        """t px thick line (thickness across the shorter axis)."""
        for (x, y) in line_cells(x0, y0, x1, y1):
            if abs(x1 - x0) >= abs(y1 - y0):
                for k in range(t): s.put(x, y + k - t // 2, c)
            else:
                for k in range(t): s.put(x + k - t // 2, y, c)
    def fill(s, cells, c):
        for (x, y) in cells: s.put(x, y, c)
    def fillf(s, cells, fn):
        for (x, y) in cells:
            c = fn(x, y)
            if c: s.put(x, y, c)
    def outline(s, cells, c, diag=False, empty_only=False):
        """1 px ring just outside `cells`."""
        for (x, y) in grow(cells, 1, diag) - set(cells):
            if empty_only and s.get(x, y) not in (None, '.', empty_only if isinstance(empty_only, str) else ''): continue
            s.put(x, y, c)
    def poly(s, pts, c): s.fill(poly_cells(pts), c)
    def ellipse(s, cx, cy, rx, ry, c): s.fill(ellipse_cells(cx, cy, rx, ry), c)
    def disc(s, cx, cy, r, c): s.fill(ellipse_cells(cx, cy, r, r), c)
    def stamp(s, x, y, rows, sub=None, flip=False):
        """ASCII sprite ('.' transparent); `sub` maps letters."""
        if isinstance(rows, str): rows = [r for r in rows.strip('\n').split('\n')]
        for j, r in enumerate(rows):
            if flip: r = r[::-1]
            for i, c in enumerate(r):
                if sub and c in sub: c = sub[c]
                s.put(x + i, y + j, c)
    # --- shading
    def shade(s, cells, ramp, cx, cy, rx, ry, light=(-0.55, -0.62), sharp=1.0, bias=0.0):
        """volume shading of an ellipsoid: ramp is dark -> light, ordered dither between neighbours. light is the direction the light comes FROM (x, y)."""
        lx, ly = light
        lz = math.sqrt(max(0.0, 1 - lx * lx - ly * ly))
        n = len(ramp)
        for (x, y) in cells:
            nx, ny = (x + 0.5 - cx) / rx, (y + 0.5 - cy) / ry
            nz = math.sqrt(max(0.0, 1 - nx * nx - ny * ny))
            v = max(0.0, min(1.0, (nx * lx + ny * ly + nz * lz) * 0.5 + 0.5 + bias))
            f = v * (n - 1)
            i0 = int(math.floor(f)); fr = f - i0
            fr = max(0.0, min(1.0, (fr - 0.5) * sharp + 0.5))
            k = i0 + (1 if fr > bay(x, y) else 0)
            s.put(x, y, ramp[max(0, min(n - 1, k))])
    def vgrad(s, x0, y0, x1, y1, ramp, t0=0.0, t1=1.0, sharp=1.0, cells=None):
        """vertical dithered gradient (ramp[0] at the top). t0/t1 pick the part of the ramp used."""
        n = len(ramp)
        for y in range(y0, y1):
            for x in range(x0, x1):
                if cells is not None and (x, y) not in cells: continue
                t = t0 + (t1 - t0) * (y - y0) / float(max(1, y1 - y0 - 1))
                f = max(0.0, min(1.0, t)) * (n - 1)
                i0 = int(math.floor(f)); fr = f - i0
                fr = max(0.0, min(1.0, (fr - 0.5) * sharp + 0.5))
                k = i0 + (1 if fr > bay(x, y) else 0)
                s.put(x, y, ramp[min(n - 1, k)])
    def rgrad(s, cx, cy, r, ramp, cells=None, sharp=1.0, squash=1.0, inner=0.0):
        """radial dithered gradient: ramp[0] at the centre, ramp[-1] at radius r."""
        n = len(ramp)
        rr = int(r) + 1
        for y in range(int(cy - rr * squash) - 1, int(cy + rr * squash) + 2):
            for x in range(int(cx - rr) - 1, int(cx + rr) + 2):
                d = math.hypot(x + 0.5 - cx, (y + 0.5 - cy) / squash) / r
                if d > 1: continue
                if cells is not None and (x, y) not in cells: continue
                t = max(0.0, (d - inner) / (1 - inner)) if inner < 1 else 0
                f = t * (n - 1)
                i0 = int(math.floor(f)); fr = f - i0
                fr = max(0.0, min(1.0, (fr - 0.5) * sharp + 0.5))
                k = i0 + (1 if fr > bay(x, y) else 0)
                s.put(x, y, ramp[min(n - 1, k)])
    def dither(s, cells, c1, c2, t):
        """mix two letters at fraction t of c2 (ordered dither); c1 None leaves what is there."""
        for (x, y) in cells:
            if t > bay(x, y): s.put(x, y, c2)
            elif c1: s.put(x, y, c1)
    def tintcells(s, cells, mp):
        for (x, y) in cells:
            c = s.get(x, y)
            if c in mp: s.put(x, y, mp[c])
    def remap(s, mp):
        for y in range(s.h):
            for x in range(s.w):
                c = s.g[y][x]
                if c in mp: s.g[y][x] = mp[c]
    def rgba(s):
        out = bytearray()
        for r in s.g:
            for c in r: out += bytes(RGB[c] + (255,))
        return bytes(out)
    def rows(s): return [''.join(r) for r in s.g]
    def rgba_alpha(s):
        """RGBA bytes with '.' fully transparent (for sprites that are not full-bleed pictures)."""
        out = bytearray()
        for r in s.g:
            for c in r: out += (bytes(RGB[c] + (255,)) if c != '.' else b'\x00\x00\x00\x00')
        return bytes(out)
    def save_alpha(s, path): save_rgba(path, s.w, s.h, s.rgba_alpha())

# ------------------------------------------------------------------ the glow layer
class Glow:
    """soft-alpha RGBA layer in palette hues. Composited additively by the game (so keep alpha modest)."""
    def __init__(s, w=W, h=H):
        s.w, s.h = w, h
        s.p = [[[0, 0, 0, 0] for _ in range(w)] for _ in range(h)]
    def px(s, x, y, ch, a):
        if not (0 <= x < s.w and 0 <= y < s.h) or a <= 0: return
        d = s.p[y][x]
        a = int(min(255, a))
        if a >= d[3]:
            # a stronger light takes the pixel; a weaker one in a different hue is blended in by weight
            d[0], d[1], d[2], d[3] = RGB[ch][0], RGB[ch][1], RGB[ch][2], max(a, d[3])
    def blob(s, cx, cy, r, ch, a, power=2.0, squash=1.0, quant=0):
        """radial falloff: alpha a at the centre -> 0 at r. quant>0 rounds alpha to that many bands (a crisper, more pixel-art halo)."""
        ry = r * squash
        for y in range(int(cy - ry) - 1, int(cy + ry) + 2):
            for x in range(int(cx - r) - 1, int(cx + r) + 2):
                d = math.hypot(x + 0.5 - cx, (y + 0.5 - cy) / squash) / r
                if d >= 1: continue
                v = (1 - d) ** power
                if quant: v = math.ceil(v * quant) / float(quant)
                s.px(x, y, ch, a * v)
    def rect(s, x, y, w, h, ch, a):
        for j in range(y, y + h):
            for i in range(x, x + w): s.px(i, j, ch, a)
    def line(s, x0, y0, x1, y1, ch, a, r=2, power=1.5):
        for (x, y) in line_cells(x0, y0, x1, y1): s.blob(x, y, r, ch, a, power)
    def cells(s, cells, ch, a):
        for (x, y) in cells: s.px(x, y, ch, a)
    def rgba(s):
        out = bytearray()
        for r in s.p:
            for p in r: out += bytes(p)
        return bytes(out)

def composite(img, glow=None, gain=1.0):
    """picture + additive glow -> list of rows of (r,g,b) (what the game shows)."""
    rows = []
    for y in range(img.h):
        row = []
        for x in range(img.w):
            r, g, b = RGB[img.g[y][x]]
            if glow is not None:
                p = glow.p[y][x]
                if p[3]:
                    t = p[3] / 255.0 * gain
                    r, g, b = min(255, int(r + p[0] * t)), min(255, int(g + p[1] * t)), min(255, int(b + p[2] * t))
            row.append((r, g, b))
        rows.append(row)
    return rows

def save_strip(frames, path):
    """frames: list of Ill, side by side -> one RGBA PNG."""
    w, h = frames[0].w, frames[0].h
    out = bytearray()
    for y in range(h):
        for f in frames:
            for c in f.g[y]: out += bytes(RGB[c] + (255,))
    save_rgba(path, w * len(frames), h, bytes(out))

def save_glow_strip(glows, path):
    w, h = glows[0].w, glows[0].h
    out = bytearray()
    for y in range(h):
        for g in glows:
            for p in g.p[y]: out += bytes(p)
    save_rgba(path, w * len(glows), h, bytes(out))

# ------------------------------------------------------------------ preview font (3x5)
F35 = {
 'A':'010101111101101','B':'110101110101110','C':'011100100100011','D':'110101101101110','E':'111100110100111',
 'F':'111100110100100','G':'011100101101011','H':'101101111101101','I':'111010010010111','J':'001001001101010',
 'K':'101101110101101','L':'100100100100111','M':'101111111101101','N':'110101101101101','O':'010101101101010',
 'P':'110101110100100','Q':'010101101111011','R':'110101110101101','S':'011100010001110','T':'111010010010010',
 'U':'101101101101111','V':'101101101101010','W':'101101111111101','X':'101101010101101','Y':'101101010010010',
 'Z':'111001010100111','0':'111101101101111','1':'010110010010111','2':'110001010100111','3':'110001010001110',
 '4':'101101111001001','5':'111100110001110','6':'011100111101111','7':'111001010010010','8':'111101111101111',
 '9':'111101111001110','+':'000010111010000','-':'000000111000000','/':'001001010100100','.':'000000000000010',
 ' ':'000000000000000',',':'000000000010100','_':'000000000000111','(':'010100100100010',')':'010001001001010',
 ':':'000010000010000','=':'000111000111000','*':'000010111010000','x':'101101010101101',
}

# ------------------------------------------------------------------ helpers shared by the scenes
def pick(v, ramp, x, y, sharp=1.0):
    """ramp letter for a value v in 0..1 with ordered dither between neighbours ('.' in a ramp = leave what is under it)."""
    n = len(ramp)
    f = max(0.0, min(1.0, v)) * (n - 1)
    i0 = int(math.floor(f)); fr = f - i0
    fr = max(0.0, min(1.0, (fr - 0.5) * sharp + 0.5))
    return ramp[min(n - 1, i0 + (1 if fr > bay(x, y) else 0))]

# one step lighter / darker along each material ramp (for light shafts, bleed and shadows)
_RAMPS = ['KDEWSMLH', 'NIJj', 'ZVX', 'dPwm', 'nqQ', 'uTY', 'aoy', 'cC', 'BCiz', 'AORUg', 'vsY', 'xtz', 'Jjbk']
UP, DOWN = {}, {}
for _r in _RAMPS:
    for _i, _c in enumerate(_r):
        if _i + 1 < len(_r): UP.setdefault(_c, _r[_i + 1])
        if _i > 0: DOWN.setdefault(_c, _r[_i - 1])
def lighten(c, n=1):
    for _ in range(n): c = UP.get(c, c)
    return c
def darken(c, n=1):
    for _ in range(n): c = DOWN.get(c, c)
    return c

def fbm01(x, y, seed=1, octaves=4):
    from dbr import fbm
    return fbm(x, y, seed, octaves)
