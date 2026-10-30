"""Tiny pixel-art toolkit: palette, ASCII sprites, PNG writer (stdlib only)."""
import zlib, struct, json, os, textwrap

ART = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))   # repo art/
OUT = ART
PREVIEW = os.environ.get('HS_PREVIEW', '/tmp/claude-0/-home-user-earth-sim/2fe481dc-7c04-5e24-b286-37a000ee4cff/scratchpad/pixel')

# One shared palette. char -> (hex, name). '.' is transparent.
PAL = {
 # near-black + cool steel ramp (machines, walls, outfit greys for the tint mask)
 'K': ('13161b', 'near-black outline'),
 'D': ('2a2f37', 'dark slate'),
 'E': ('3d444e', 'steel dark'),
 'W': ('565e6a', 'steel mid-dark / floor shadow'),
 'S': ('7a8491', 'steel mid'),
 'M': ('a3acb8', 'steel light'),
 'L': ('d2d8e0', 'steel highlight'),
 'H': ('f4f6f8', 'white (icons, hot cores)'),
 # flat cool-grey interior
 'F': ('6e7683', 'floor'),
 'G': ('646c78', 'floor grid'),
 # muted browns (machines, hair, scrap)
 'n': ('3a2e28', 'brown dark'),
 'q': ('6d5646', 'brown mid'),
 'Q': ('93775f', 'brown light'),
 'u': ('9c5a33', 'scrap rust'),
 # state / function colours
 'g': ('6bd34a', 'power green'),
 'b': ('4fa3ff', 'shield blue'),
 'p': ('e88aa0', 'low-o2 pink'),
 'o': ('ff8a1e', 'fire orange'),
 'y': ('ffd23a', 'fire yellow'),
 'r': ('e0413b', 'damage red'),
 'a': ('e1a136', 'hull / door amber'),
 'c': ('3cf2ff', 'neon cyan'),
 'm': ('ff4fd8', 'neon magenta'),
 # skin
 's': ('e3ad82', 'skin'),
 'v': ('b87a54', 'skin shade'),
}
RGB = {c: tuple(int(h[i:i+2], 16) for i in (0, 2, 4)) for c, (h, _) in PAL.items()}

def write_palette_gpl(path):
    lines = ['GIMP Palette', 'Name: Hullscrap', 'Columns: 5', '#']
    for c, (h, name) in PAL.items():
        r, g, b = RGB[c]
        lines.append('%3d %3d %3d\t#%s %s' % (r, g, b, h, name))
    open(path, 'w').write('\n'.join(lines) + '\n')

def art(s):
    """ASCII block -> list of equal-length strings (leading/trailing blank lines dropped)."""
    rows = textwrap.dedent(s).strip('\n').split('\n')
    rows = [r.rstrip() for r in rows]
    w = max(len(r) for r in rows)
    rows = [r.ljust(w, '.') for r in rows]
    return rows

def art_strict(s, w=None, h=None, name='?'):
    rows = textwrap.dedent(s).strip('\n').split('\n')
    ws = {len(r) for r in rows}
    assert len(ws) == 1, '%s: ragged rows %s' % (name, sorted(ws))
    if w: assert ws == {w}, '%s: width %s != %d' % (name, ws, w)
    if h: assert len(rows) == h, '%s: height %d != %d' % (name, len(rows), h)
    return rows

class Spr:
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
    def box(s, x, y, w, h, hi, mid, lo, line):
        """bevelled panel: 1px outline, light top-left, dark bottom-right."""
        s.rect(x, y, w, h, line)
        s.rect(x + 1, y + 1, w - 2, h - 2, mid)
        s.hline(x + 1, y + 1, w - 2, hi); s.vline(x + 1, y + 1, h - 2, hi)
        s.hline(x + 1, y + h - 2, w - 2, lo); s.vline(x + w - 2, y + 1, h - 2, lo)
        s.put(x + 1, y + h - 2, lo); s.put(x + w - 2, y + 1, hi if w > 3 and False else mid)
    def flipx(s):
        n = Spr(s.w, s.h); n.g = [r[::-1] for r in s.g]; return n
    def transpose(s):
        n = Spr(s.h, s.w)
        for y in range(s.h):
            for x in range(s.w): n.g[x][y] = s.g[y][x]
        return n
    def sub(s, m):
        n = s.copy(); n.g = [[m.get(c, c) for c in r] for r in n.g]; return n
    def rows(s): return [''.join(r) for r in s.g]
    def shadow(s, c='R', dx=1, dy=1):
        """1px floor drop shadow down-right of the silhouette (only on empty pixels)."""
        n = s.copy()
        for y in range(s.h):
            for x in range(s.w):
                if s.g[y][x] != '.':
                    xx, yy = x + dx, y + dy
                    if 0 <= xx < s.w and 0 <= yy < s.h and n.g[yy][xx] == '.' and s.g[yy][xx] == '.':
                        n.g[yy][xx] = c
        return n

def from_art(rows, sub=None):
    if isinstance(rows, str): rows = art(rows)
    s = Spr(len(rows[0]), len(rows)); s.stamp(0, 0, rows, sub); return s

def to_rgba(spr, bg=None):
    out = bytearray()
    for r in spr.g:
        for c in r:
            if c == '.':
                out += bytes((0, 0, 0, 0)) if bg is None else bytes(bg + (255,))
            else:
                out += bytes(RGB[c] + (255,))
    return bytes(out)

def png_bytes(w, h, rgba):
    raw = b''.join(b'\x00' + rgba[y * w * 4:(y + 1) * w * 4] for y in range(h))
    def chunk(t, d):
        c = struct.pack('>I', len(d)) + t + d
        return c + struct.pack('>I', zlib.crc32(t + d) & 0xffffffff)
    return (b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 6, 0, 0, 0))
            + chunk(b'IDAT', zlib.compress(raw, 9)) + chunk(b'IEND', b''))

def save_rgba(path, w, h, rgba):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    open(path, 'wb').write(png_bytes(w, h, rgba))

def save(spr, path, scale=1, bg=None):
    rgba = to_rgba(spr, bg)
    w, h = spr.w, spr.h
    if scale != 1: rgba, w, h = scale_rgba(rgba, w, h, scale)
    save_rgba(path, w, h, rgba)

def scale_rgba(rgba, w, h, k):
    rows = []
    for y in range(h):
        row = rgba[y * w * 4:(y + 1) * w * 4]
        big = b''.join(row[i:i + 4] * k for i in range(0, len(row), 4))
        rows += [big] * k
    return b''.join(rows), w * k, h * k

def sheet(frames, cols, fw, fh):
    rows = (len(frames) + cols - 1) // cols
    sh = Spr(cols * fw, rows * fh)
    for i, f in enumerate(frames):
        assert f.w == fw and f.h == fh, (i, f.w, f.h)
        sh.stamp((i % cols) * fw, (i // cols) * fh, f.rows())
    return sh

def blit(dst, src, x, y):
    dst.stamp(x, y, src.rows())

# ---- RGBA canvas for the final scene (nearest-neighbour blits, 2x) ----
class Canvas:
    def __init__(s, w, h, fill=(0, 0, 0, 255)):
        s.w, s.h = w, h
        s.px = [bytearray(bytes(fill) * w) for _ in range(h)]
    def blit(s, spr, x, y, k=1, tint=None, mask=None):
        for j, r in enumerate(spr.g):
            for i, c in enumerate(r):
                if c == '.': continue
                rgb = RGB[c]
                if tint: rgb = tint(rgb, c)
                for dy in range(k):
                    yy = y + j * k + dy
                    if not (0 <= yy < s.h): continue
                    for dx in range(k):
                        xx = x + i * k + dx
                        if 0 <= xx < s.w:
                            s.px[yy][xx*4:xx*4+4] = bytes(rgb + (255,))
    def save(s, path):
        save_rgba(path, s.w, s.h, b''.join(bytes(r) for r in s.px))

def mix(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3))

# ---- helpers added for the pilot ----
def tint_mul(rgb, tint):
    return tuple(int(rgb[i] * tint[i] / 255) for i in range(3))

def save_rgba_img(path, w, h, px_rows):
    save_rgba(path, w, h, b''.join(bytes(r) for r in px_rows))

class Rgba:
    """plain RGBA surface (alpha allowed) for glow layers, previews and the scene."""
    def __init__(s, w, h, fill=(0, 0, 0, 0)):
        s.w, s.h = w, h
        s.p = [[list(fill) for _ in range(w)] for _ in range(h)]
    def over(s, x, y, rgba):
        if not (0 <= x < s.w and 0 <= y < s.h): return
        r, g, b, a = rgba
        if a <= 0: return
        d = s.p[y][x]
        da = d[3] / 255.0; sa = a / 255.0
        oa = sa + da * (1 - sa)
        if oa <= 0: return
        for i, (sc, dc) in enumerate(zip((r, g, b), d[:3])):
            d[i] = int(round((sc * sa + dc * da * (1 - sa)) / oa))
        d[3] = int(round(oa * 255))
    def blit_spr(s, spr, x, y, k=1, tint=None):
        for j, row in enumerate(spr.g):
            for i, c in enumerate(row):
                if c == '.': continue
                rgb = RGB[c]
                if tint: rgb = tint(rgb, c)
                for dy in range(k):
                    for dx in range(k):
                        s.over(x + i * k + dx, y + j * k + dy, rgb + (255,))
    def blit_rgba(s, o, x, y, k=1, add=False):
        for j in range(o.h):
            for i in range(o.w):
                p = o.p[j][i]
                if p[3] == 0: continue
                for dy in range(k):
                    for dx in range(k):
                        if add: s.add(x + i * k + dx, y + j * k + dy, p)
                        else: s.over(x + i * k + dx, y + j * k + dy, tuple(p))
    def add(s, x, y, rgba):
        """additive light (glow layer composited onto the scene)."""
        if not (0 <= x < s.w and 0 <= y < s.h): return
        r, g, b, a = rgba
        d = s.p[y][x]
        t = a / 255.0
        for i, c in enumerate((r, g, b)):
            d[i] = min(255, int(d[i] + c * t))
        if d[3] == 0: d[3] = 255
    def save(s, path):
        save_rgba(path, s.w, s.h, b''.join(bytes(v for p in row for v in p) for row in s.p))
    def scaled(s, k):
        n = Rgba(s.w * k, s.h * k)
        for j in range(s.h):
            for i in range(s.w):
                p = s.p[j][i]
                for dy in range(k):
                    for dx in range(k): n.p[j * k + dy][i * k + dx] = list(p)
        return n

def spr_to_rgba(spr):
    o = Rgba(spr.w, spr.h)
    for j, row in enumerate(spr.g):
        for i, c in enumerate(row):
            if c != '.': o.p[j][i] = list(RGB[c]) + [255]
    return o
