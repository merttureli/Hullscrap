"""Shared drawing helpers for the three equipment lines + workshop (systems artist, wave 2)."""
import pal_lines                       # registers the extra palette letters first
from comp_base import *
from comp_base import stamp_on, DARK
import comp_base

# ---- palette helpers
RGBF = {k: v for k, v in RGB.items()}
GREEN, AMBER, BLUE, CYAN, ORANGE, YEL = (107, 211, 74), (225, 161, 54), (79, 163, 255), (60, 242, 255), (255, 138, 30), (255, 210, 58)
MAGENTA, VIOLET, RED = (255, 79, 216), (160, 110, 230), (224, 65, 59)

# dead-part tone maps: navy and crystal tones sink to dull grey-blue, not black
DARK.update({'N': 'N', 'I': 'N', 'J': 'I', 'j': 'J', 'C': 'W', 'B': 'E', 'P': 'N', 'V': 'E', 'X': 'W', 'Z': 'D'})

def circle(s, cx, cy, r, c):
    """integer disc: pixel centres inside radius r around (cx, cy) (cx, cy may be .5)."""
    for y in range(int(cy - r - 1), int(cy + r + 2)):
        for x in range(int(cx - r - 1), int(cx + r + 2)):
            if (x + .5 - cx) ** 2 + (y + .5 - cy) ** 2 <= r * r: s.put(x, y, c)

def ring(s, cx, cy, r0, r1, c):
    for y in range(int(cy - r1 - 1), int(cy + r1 + 2)):
        for x in range(int(cx - r1 - 1), int(cx + r1 + 2)):
            d = (x + .5 - cx) ** 2 + (y + .5 - cy) ** 2
            if r0 * r0 < d <= r1 * r1: s.put(x, y, c)

def line(s, x0, y0, x1, y1, c):
    dx, dy = abs(x1 - x0), -abs(y1 - y0); sx = 1 if x0 < x1 else -1; sy = 1 if y0 < y1 else -1
    err = dx + dy
    while True:
        s.put(x0, y0, c)
        if x0 == x1 and y0 == y1: break
        e2 = 2 * err
        if e2 >= dy: err += dy; x0 += sx
        if e2 <= dx: err += dx; y0 += sy

def thick(s, x0, y0, x1, y1, w, c, hi=None, lo=None):
    """w-wide bar along a line; hi on the up/left edge, lo on the down/right edge."""
    horiz = abs(x1 - x0) >= abs(y1 - y0)
    for k in range(w):
        o = k - w // 2
        col = c
        if hi and k == 0: col = hi
        if lo and k == w - 1: col = lo
        if horiz: line(s, x0, y0 + o, x1, y1 + o, col)
        else: line(s, x0 + o, y0, x1 + o, y1, col)

def edge(s, x, y, w, h, ch, c):
    """1px outline drawn just inside a chamfer_fill(x, y, w, h, ., ch) region (only on pixels that exist)."""
    m = Spr(s.w, s.h); chamfer_fill(m, x, y, w, h, 'X', ch)
    for j in range(s.h):
        for i in range(s.w):
            if m.g[j][i] == 'X' and any(m.get(i + a, j + b) != 'X' for a, b in ((1, 0), (-1, 0), (0, 1), (0, -1))):
                s.put(i, j, c)

def clip(s, x, y, w, h, ch):
    """erase everything outside a chamfer_fill region (keeps the standard silhouette on patched parts)."""
    m = Spr(s.w, s.h); chamfer_fill(m, x, y, w, h, 'X', ch)
    for j in range(s.h):
        for i in range(s.w):
            if m.g[j][i] != 'X': s.g[j][i] = '.'

# ---- Scrap vocabulary
def hazard(s, x, y, w, h):
    """amber/black hazard tape, 2px diagonal bands, slightly lighter lip on the top row."""
    for j in range(h):
        for i in range(w):
            s.put(x + i, y + j, 'a' if ((i + j) // 2) % 2 == 0 else 'K')
    for i in range(w):
        if s.get(x + i, y) == 'a': s.put(x + i, y, 'y')

def bolt(s, x, y):
    s.put(x, y, 'L'); s.put(x + 1, y, 'M'); s.put(x, y + 1, 'S'); s.put(x + 1, y + 1, 'E')

def bolts(s, pts):
    for (x, y) in pts: bolt(s, x, y)

def weld(s, x, y, n, vert=False):
    """weld bead: lumpy light run with a dark shadow pixel under/right of it."""
    for k in range(n):
        c = 'L' if k % 4 == 1 else ('M' if k % 3 else 'S')
        if vert: s.put(x, y + k, c); s.put(x + 1, y + k, 'D' if k % 2 == 0 else 'E')
        else: s.put(x + k, y, c); s.put(x + k, y + 1, 'D' if k % 2 == 0 else 'E')

def plate(s, x, y, w, h, tone='S', bolted=True):
    """salvaged plate: bevelled, 2 greys or rust, with corner bolts."""
    hi, mid, lo = {'S': ('M', 'S', 'W'), 'M': ('L', 'M', 'S'), 'W': ('S', 'W', 'E'), 'u': ('Q', 'u', 'n')}[tone]
    bev(s, x, y, w, h, hi, mid, lo)
    if bolted:
        for (bx, by) in ((x + 2, y + 2), (x + w - 4, y + 2), (x + 2, y + h - 4), (x + w - 4, y + h - 4)): bolt(s, bx, by)

def wire(s, pts, c='r', c2='n'):
    """exposed wire run through points (1px, dark under-edge where it crosses a lit pixel)."""
    for (a, b) in zip(pts, pts[1:]): line(s, a[0], a[1], b[0], b[1], c)

# ---- Concord vocabulary
def stencil(s, x, y, c='L', kind=0):
    """registry stencil: 2-3 px marks."""
    marks = [[(0, 0), (1, 0), (3, 0)], [(0, 0), (2, 0), (3, 0)], [(0, 0), (1, 0), (2, 0), (4, 0)], [(0, 0), (1, 0), (1, 1)]][kind % 4]
    for (dx, dy) in marks: s.put(x + dx, y + dy, c)

# ---- Neon vocabulary
def navy_panel(s, x, y, w, h, cham=True):
    bev(s, x, y, w, h, 'j', 'J', 'I', cham=cham)

def crystal(s, x, y, rows, tones):
    """small faceted crystal from an ascii map: digits pick a tone from `tones`."""
    for j, r in enumerate(art(rows) if isinstance(rows, str) else rows):
        for i, ch in enumerate(r):
            if ch == '.': continue
            s.put(x + i, y + j, tones[int(ch)] if ch.isdigit() else ch)

class LComp(Comp):
    """Comp with per-object damage: subclasses implement hurt(s, i) / wreck(s) and set DMG (on-frame indices for the damaged loop)."""
    DMG = (0, 1)
    dark = None
    def hurt(self, s, i): pass
    def wreck(self, s): pass
    def frame(self, state, i):
        if state == 'damaged': s = self.interior('on', self.DMG[i]).copy(); self.hurt(s, i)
        elif state == 'disabled':
            s = self.interior('off', 0).copy()
            dm = dict(DARK); dm.update(self.dark or {})
            s = s.sub(dm); self.wreck(s)
        else: s = self.interior(state, i)
        s = s.copy(); outline_all(s); s = drop_shadow(s)
        return self.after(state, i, s)
    def glow_frame(self, state, i):
        l, t, r, b = self.glow_pad
        g = Rgba(self.w + l + r, self.h + t + b)
        if state == 'disabled': return g
        if state == 'damaged': self.glow('damaged', self.DMG[i], g, l, t, flick=i)
        else: self.glow(state, i, g, l, t)
        return g

def shear(s, x0, x1, dy, y0=0, y1=None, fill='K'):
    """slide columns x0..x1-1 (rows y0..y1-1) down by dy: a casing split in two, the gap left dark."""
    y1 = s.h if y1 is None else y1
    for x in range(x0, x1):
        col = [s.get(x, y) for y in range(y0, y1)]
        for k, y in enumerate(range(y0, y1)):
            src = k - dy
            s.g[y][x] = col[src] if 0 <= src < len(col) else '.'
        if dy > 0 and any(c != '.' for c in col): s.g[y0 + dy - 1][x] = fill if s.g[y0 + dy][x] != '.' else '.'

def crack(s, pts, hi='L'):
    for (a, b) in zip(pts, pts[1:]): line(s, a[0], a[1], b[0], b[1], 'K')
    for (x, y) in pts[1:-1:2]:
        if s.get(x + 1, y) not in ('.', 'K'): s.put(x + 1, y, hi)

def chamfer_tones(s, x, y, w, h, ch, tones):
    """chamfered block with one tone per row (a cylinder seen from above)."""
    for j in range(h):
        inset = max(0, ch - j, ch - (h - 1 - j))
        s.hline(x + inset, y + j, w - 2 * inset, tones[j])

def octant(dx, dy):
    ax, ay = abs(dx), abs(dy)
    if dy < 0: return (0 if ax < ay else 1) if dx >= 0 else (7 if ax < ay else 6)
    return (3 if ax < ay else 2) if dx >= 0 else (4 if ax < ay else 5)

def glow_xy(layer, cx, cy, rx, ry, rgb, strength=0.8, power=2.0):
    """elliptical soft glow (exhaust plumes that run out of the frame)."""
    for y in range(int(cy - ry - 1), int(cy + ry + 2)):
        for x in range(int(cx - rx - 1), int(cx + rx + 2)):
            d = (((x + .5 - cx) / rx) ** 2 + ((y + .5 - cy) / ry) ** 2) ** 0.5
            if d >= 1: continue
            a = strength * (1 - d) ** power
            if a > 0.02: layer.over(x, y, rgb + (int(255 * a),))

def col_tones(wd, T='LLMMSSSSWWWEE'):
    return [T[min(len(T) - 1, k * len(T) // wd)] for k in range(wd)]

def shift_rect(s, xa, xb, y0, y1, dx, dy=0):
    """move the pixels in a rectangle (x xa..xb-1, y y0..y1-1) by (dx, dy): a bent or snapped part."""
    cells = [(x, y, s.g[y][x]) for y in range(max(0, y0), min(s.h, y1)) for x in range(max(0, xa), min(s.w, xb)) if s.g[y][x] != '.']
    for (x, y, c) in cells: s.g[y][x] = '.'
    for (x, y, c) in cells: s.put(x + dx, y + dy, c)

def wall_band(s, y0=32, h=16, w=64):
    """the hull wall where a mount passes through: dark slate cells with a light top-left edge, seams and corner rivets (matches art/tiles/walls)."""
    for c in range(w // 16):
        x = c * 16
        s.rect(x, y0, 16, h, 'D'); s.hline(x, y0, 16, 'E'); s.vline(x, y0, h, 'E')
        s.hline(x, y0 + h - 1, 16, 'K'); s.vline(x + 15, y0, h, 'K')
        for (rx, ry) in ((x + 3, y0 + 3), (x + 12, y0 + 3), (x + 3, y0 + h - 4), (x + 12, y0 + h - 4)): s.put(rx, ry, 'W')
