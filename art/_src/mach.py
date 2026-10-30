"""Machine-sprite helpers: bevelled panels, seams, global outline, soft glow layers."""
from px import *

def bev(s, x, y, w, h, hi='M', mid='S', lo='W', cham=True):
    """interior-only bevelled box: light top/left, dark bottom/right (top-left light)."""
    s.rect(x, y, w, h, mid)
    s.hline(x, y, w, hi); s.vline(x, y, h, hi)
    s.hline(x, y + h - 1, w, lo); s.vline(x + w - 1, y, h, lo)
    s.put(x + w - 1, y, mid if w > 2 else lo); s.put(x, y + h - 1, mid if h > 2 else lo)
    if cham:
        for cx, cy in ((x, y), (x + w - 1, y), (x, y + h - 1), (x + w - 1, y + h - 1)):
            s.erase(cx, cy)

def hollow(s, x, y, w, h, c='K'):
    s.hline(x, y, w, c); s.hline(x, y + h - 1, w, c)
    s.vline(x, y, h, c); s.vline(x + w - 1, y, h, c)

def recess(s, x, y, w, h, fill='D', edge='K'):
    """sunken slot: dark seam on top/left, light lip on bottom/right."""
    s.rect(x, y, w, h, fill)
    s.hline(x, y, w, edge); s.vline(x, y, h, edge)
    s.hline(x, y + h - 1, w, 'M'); s.vline(x + w - 1, y, h, 'M')

def outline_all(s, keep=''):
    mask = {(x, y) for y in range(s.h) for x in range(s.w) if s.g[y][x] != '.'}
    for (x, y) in mask:
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            q = (x + dx, y + dy)
            if q not in mask and 0 <= q[0] < s.w and 0 <= q[1] < s.h:
                s.g[q[1]][q[0]] = 'K'

def drop_shadow(s):
    """1px floor shadow down-right (only onto empty pixels)."""
    n = s.copy()
    for y in range(s.h):
        for x in range(s.w):
            if s.g[y][x] != '.':
                for dx, dy in ((1, 1), (1, 0), (0, 1)):
                    xx, yy = x + dx, y + dy
                    if 0 <= xx < s.w and 0 <= yy < s.h and s.g[yy][xx] == '.' and n.g[yy][xx] == '.':
                        n.g[yy][xx] = 'W'
    return n

# ---- soft glow (the one allowed non-pixel effect), written to its own RGBA layer ----
def glow(layer, cx, cy, r, rgb, strength=0.8, power=2.0, sx=1.0):
    """additive-looking soft disc: alpha falls off with distance. sx stretches horizontally."""
    x0, x1 = int(cx - r * sx - 1), int(cx + r * sx + 2)
    y0, y1 = int(cy - r - 1), int(cy + r + 2)
    for y in range(y0, y1):
        for x in range(x0, x1):
            d = (((x + 0.5 - cx) / sx) ** 2 + (y + 0.5 - cy) ** 2) ** 0.5
            if d >= r: continue
            a = strength * (1 - d / r) ** power
            if a > 0.02: layer.over(x, y, rgb + (int(255 * a),))

def save_strip(frames, path, pad=0):
    w, h = frames[0].w, frames[0].h
    out = Rgba(w * len(frames), h)
    for i, f in enumerate(frames): out.blit_rgba(f, i * w, 0)
    out.save(path)
    return out
