"""Tiny pixel-art toolkit for Hullscrap: shared palette, ASCII sprites, RGBA surfaces, PNG writer.

Stdlib only. Hard-pixel sprites are grids of palette letters ('.' = transparent); the letters map to
the colours in art/palette.gpl. Soft glow layers (the one allowed exception to hard pixels) are built
with `halo()`: a few discrete alpha bands in palette hues, never a smooth gradient.
"""
import zlib, struct, json, os, textwrap

# letter -> (hex, name): identical to the approved pilot palette (art/palette.gpl).
PAL = {
 'K': ('13161b', 'near-black outline'), 'D': ('2a2f37', 'dark slate'), 'E': ('3d444e', 'steel dark'),
 'W': ('565e6a', 'steel mid-dark / floor shadow'), 'S': ('7a8491', 'steel mid'), 'M': ('a3acb8', 'steel light'),
 'L': ('d2d8e0', 'steel highlight'), 'H': ('f4f6f8', 'white (icons, hot cores)'),
 'F': ('6e7683', 'floor'), 'G': ('646c78', 'floor grid'),
 'n': ('3a2e28', 'brown dark'), 'q': ('6d5646', 'brown mid'), 'Q': ('93775f', 'brown light'), 'u': ('9c5a33', 'scrap rust'),
 'g': ('6bd34a', 'power green'), 'b': ('4fa3ff', 'shield blue'), 'p': ('e88aa0', 'low-o2 pink'),
 'o': ('ff8a1e', 'fire orange'), 'y': ('ffd23a', 'fire yellow'), 'r': ('e0413b', 'damage red'),
 'a': ('e1a136', 'hull / door amber'), 'c': ('3cf2ff', 'neon cyan'), 'm': ('ff4fd8', 'neon magenta'),
 's': ('e3ad82', 'skin'), 'v': ('b87a54', 'skin shade'),
}
RGB = {c: tuple(int(h[i:i + 2], 16) for i in (0, 2, 4)) for c, (h, _) in PAL.items()}
PALETTE_RGB = set(RGB.values())


def art(s):
    """ASCII block -> list of equal-length rows (blank edge lines dropped, short rows padded with '.')."""
    rows = [r.rstrip() for r in textwrap.dedent(s).strip('\n').split('\n')]
    w = max(len(r) for r in rows)
    return [r.ljust(w, '.') for r in rows]


def art_strict(s, w, h, name='?'):
    rows = textwrap.dedent(s).strip('\n').split('\n')
    assert len(rows) == h, '%s: %d rows, want %d' % (name, len(rows), h)
    for i, r in enumerate(rows):
        assert len(r) == w, '%s: row %d has %d cols, want %d' % (name, i, len(r), w)
        for ch in r:
            assert ch == '.' or ch in PAL, '%s: bad letter %r' % (name, ch)
    return rows


class Spr:
    """Grid of palette letters. put() ignores '.', so layers can be stamped over each other."""
    def __init__(s, w, h):
        s.w, s.h = w, h
        s.g = [['.'] * w for _ in range(h)]

    def copy(s):
        n = Spr(s.w, s.h); n.g = [r[:] for r in s.g]; return n

    def get(s, x, y):
        return s.g[y][x] if 0 <= x < s.w and 0 <= y < s.h else '.'

    def put(s, x, y, c):
        if c != '.' and 0 <= x < s.w and 0 <= y < s.h:
            s.g[y][x] = c

    def erase(s, x, y):
        if 0 <= x < s.w and 0 <= y < s.h: s.g[y][x] = '.'

    def stamp(s, x, y, rows, sub=None, flip=False):
        if isinstance(rows, str): rows = art(rows)
        if isinstance(rows, Spr): rows = rows.rows()
        for j, r in enumerate(rows):
            if flip: r = r[::-1]
            for i, c in enumerate(r):
                if sub and c in sub: c = sub[c]
                s.put(x + i, y + j, c)

    def rect(s, x, y, w, h, c):
        for j in range(h):
            for i in range(w): s.put(x + i, y + j, c)

    def hline(s, x, y, n, c):
        for i in range(n): s.put(x + i, y, c)

    def vline(s, x, y, n, c):
        for j in range(n): s.put(x, y + j, c)

    def rows(s): return [''.join(r) for r in s.g]

    def flipx(s):
        n = Spr(s.w, s.h); n.g = [r[::-1] for r in s.g]; return n

    def flipy(s):
        n = Spr(s.w, s.h); n.g = [r[:] for r in s.g[::-1]]; return n

    def rot90(s):
        """clockwise quarter turn (lossless)."""
        n = Spr(s.h, s.w)
        for y in range(s.h):
            for x in range(s.w): n.g[x][s.h - 1 - y] = s.g[y][x]
        return n

    def sub(s, m):
        n = s.copy(); n.g = [[m.get(c, c) for c in r] for r in n.g]; return n

    def count(s):
        return sum(1 for r in s.g for c in r if c != '.')

    def mask(s):
        return {(x, y) for y in range(s.h) for x in range(s.w) if s.g[y][x] != '.'}


def from_art(rows, sub=None):
    if isinstance(rows, str): rows = art(rows)
    s = Spr(len(rows[0]), len(rows)); s.stamp(0, 0, rows, sub); return s


def from_mask(w, h, cells, c):
    s = Spr(w, h)
    for (x, y) in cells: s.put(x, y, c)
    return s


def strip(frames):
    """horizontal strip of equal-size Spr frames."""
    fw, fh = frames[0].w, frames[0].h
    out = Spr(fw * len(frames), fh)
    for i, f in enumerate(frames):
        assert (f.w, f.h) == (fw, fh), 'frame %d is %dx%d, want %dx%d' % (i, f.w, f.h, fw, fh)
        out.stamp(i * fw, 0, f.rows())
    return out


# ---------------------------------------------------------------- RGBA surfaces (glow layers, previews)
class Rgba:
    def __init__(s, w, h, fill=(0, 0, 0, 0)):
        s.w, s.h = w, h
        s.p = [[list(fill) for _ in range(w)] for _ in range(h)]

    def over(s, x, y, rgba):
        if not (0 <= x < s.w and 0 <= y < s.h): return
        r, g, b, a = rgba
        if a <= 0: return
        d = s.p[y][x]
        da, sa = d[3] / 255.0, a / 255.0
        oa = sa + da * (1 - sa)
        for i, (sc, dc) in enumerate(zip((r, g, b), d[:3])):
            d[i] = int(round((sc * sa + dc * da * (1 - sa)) / oa))
        d[3] = int(round(oa * 255))

    def set(s, x, y, rgba):
        if 0 <= x < s.w and 0 <= y < s.h: s.p[y][x] = list(rgba)

    def blit_spr(s, spr, x, y, k=1, tint=None):
        for j, row in enumerate(spr.g):
            for i, c in enumerate(row):
                if c == '.': continue
                rgb = RGB[c]
                if tint: rgb = tint(rgb, c)
                for dy in range(k):
                    for dx in range(k): s.over(x + i * k + dx, y + j * k + dy, rgb + (255,))

    def blit_rgba(s, o, x, y, k=1):
        for j in range(o.h):
            for i in range(o.w):
                p = o.p[j][i]
                if p[3] == 0: continue
                for dy in range(k):
                    for dx in range(k): s.over(x + i * k + dx, y + j * k + dy, tuple(p))

    def fill(s, x, y, w, h, rgba):
        for j in range(h):
            for i in range(w): s.over(x + i, y + j, rgba)

    def bytes(s):
        return b''.join(bytes(v for p in row for v in p) for row in s.p)

    def save(s, path, k=1):
        """write a PNG, optionally enlarged k times with nearest-neighbour (fast row repeat)."""
        b, w, h = s.bytes(), s.w, s.h
        if k != 1:
            rows = []
            for y in range(h):
                row = b[y * w * 4:(y + 1) * w * 4]
                rows += [b''.join(row[i:i + 4] * k for i in range(0, len(row), 4))] * k
            b, w, h = b''.join(rows), w * k, h * k
        save_png(path, w, h, b)


def spr_to_rgba(spr):
    o = Rgba(spr.w, spr.h)
    for j, row in enumerate(spr.g):
        for i, c in enumerate(row):
            if c != '.': o.p[j][i] = list(RGB[c]) + [255]
    return o


def strip_rgba(frames):
    fw, fh = frames[0].w, frames[0].h
    out = Rgba(fw * len(frames), fh)
    for i, f in enumerate(frames):
        assert (f.w, f.h) == (fw, fh)
        out.blit_rgba(f, i * fw, 0)
    return out


# ---------------------------------------------------------------- PNG
def png_bytes(w, h, rgba):
    raw = b''.join(b'\x00' + rgba[y * w * 4:(y + 1) * w * 4] for y in range(h))
    def chunk(t, d):
        c = struct.pack('>I', len(d)) + t + d
        return c + struct.pack('>I', zlib.crc32(t + d) & 0xffffffff)
    return (b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 6, 0, 0, 0))
            + chunk(b'IDAT', zlib.compress(raw, 9)) + chunk(b'IEND', b''))


def save_png(path, w, h, rgba):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    open(path, 'wb').write(png_bytes(w, h, rgba))


def save_spr(spr, path):
    save_png(path, spr.w, spr.h, spr_to_rgba(spr).bytes())


def _jdump(v, ind=0):
    """JSON with one key per line but lists of plain numbers/strings kept on one line."""
    pad = ' ' * (ind + 1)
    if isinstance(v, dict):
        if not v: return '{}'
        return '{\n' + ',\n'.join('%s%s: %s' % (pad, json.dumps(k), _jdump(x, ind + 1)) for k, x in v.items()) + '\n' + ' ' * ind + '}'
    return json.dumps(v)


def save_json(path, d):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    open(path, 'w').write(_jdump(d) + '\n')


# ---------------------------------------------------------------- soft glow: discrete alpha bands
GLOW_COL = {'o': 'o', 'y': 'y', 'H': 'y', 'r': 'r', 'g': 'g', 'b': 'b', 'c': 'c', 'm': 'm', 'a': 'a', 'L': 'c'}


def halo(spr, w, h, ox=0, oy=0, bands=((1.5, 110), (2.8, 60), (4.2, 28)), src=None, col=None, core=True):
    """Soft glow layer of size w x h for `spr` placed at (ox, oy). Each lit pixel (letters in `src`)
    spreads colour in discrete alpha bands: (max distance in px, alpha 0..255). `col` forces one palette
    letter; otherwise the glow takes the hue of its source letter (white and yellow glow yellow)."""
    src = src if src is not None else 'oyHrgbcma'
    lit = [(x + ox, y + oy, spr.g[y][x]) for y in range(spr.h) for x in range(spr.w) if spr.g[y][x] in src]
    out = Rgba(w, h)
    rad = bands[-1][0]
    for (lx, ly, ch) in lit:
        c = RGB[col or GLOW_COL.get(ch, ch)]
        for y in range(int(ly - rad - 1), int(ly + rad + 2)):
            for x in range(int(lx - rad - 1), int(lx + rad + 2)):
                if not (0 <= x < w and 0 <= y < h): continue
                d = ((x - lx) ** 2 + (y - ly) ** 2) ** 0.5
                for (md, al) in bands:
                    if d <= md:
                        if al > out.p[y][x][3]: out.p[y][x] = list(c) + [al]
                        break
    if not core:  # keep the glow off the lit pixels themselves
        for (lx, ly, ch) in lit: out.p[ly][lx] = [0, 0, 0, 0]
    return out


# ---------------------------------------------------------------- shapes (hand-placed spans, then banded fills)
def spans(rows_spec, w, h):
    """rows_spec: {y: [(x0, x1), ...]} inclusive spans -> set of cells."""
    cells = set()
    for y, sp in rows_spec.items():
        for (a, b) in sp:
            for x in range(a, b + 1):
                if 0 <= x < w and 0 <= y < h: cells.add((x, y))
    return cells


def erode(cells, n=1):
    for _ in range(n):
        cells = {(x, y) for (x, y) in cells if all((x + dx, y + dy) in cells for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)))}
    return cells


def dilate(cells, n=1, diag=False):
    nb = ((1, 0), (-1, 0), (0, 1), (0, -1)) + (((1, 1), (-1, 1), (1, -1), (-1, -1)) if diag else ())
    for _ in range(n):
        cells = cells | {(x + dx, y + dy) for (x, y) in cells for dx, dy in nb}
    return cells


def disc(cx, cy, r, w, h):
    """filled pixel circle (centre may be on a half pixel: pass x.5)."""
    return {(x, y) for y in range(h) for x in range(w) if (x - cx) ** 2 + (y - cy) ** 2 <= r * r + r * 0.8}


def line(x0, y0, x1, y1):
    """Bresenham cells."""
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


# ---------------------------------------------------------------- tiny 3x5 font for the preview sheet captions
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


def text(cv, x, y, s, col='L', k=2):
    for ch in s.upper():
        g = F35.get(ch, F35[' '])
        for i, b in enumerate(g):
            if b == '1':
                for dy in range(k):
                    for dx in range(k): cv.over(x + (i % 3) * k + dx, y + (i // 3) * k + dy, RGB[col] + (255,))
        x += 4 * k
    return x
