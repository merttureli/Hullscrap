"""quick contact sheet for debris classes (dev tool): every frame at 6x on dark space, plus a 1x strip."""
import sys
from px import *
import pal_sector
from sheet_v2 import text

SPACE = (11, 14, 24)
def show(classes, path, K=6):
    rows = []
    for C in classes:
        o = C(); fr = [o.render(t) for t in o.turns]
        rows.append((o.id, fr))
    cw = max(f[0].w for _, f in rows) * K + 12
    W = max(len(f) for _, f in rows) * cw + 40
    H = sum(f[0].h * K + 34 for _, f in rows) + 60
    img = Rgba(W, H, SPACE + (255,))
    y = 10
    for name, fr in rows:
        text(img, 10, y, name, 'H', 3); y += 22
        for i, f in enumerate(fr):
            img.blit_spr(f, 10 + i * cw, y, K)
        y += fr[0].h * K + 12
    img.save(path)
    print(W, H)

def grid(classes, path, K=4, cols=3, extra=True):
    """compact dev sheet: objects in a grid, each with its tumble frames (and extras) in a row."""
    items = []
    for C in classes:
        o = C(); fr = [o.render(t) for t in o.turns]
        if extra:
            for n, l in o.extra_frames().items(): fr += l
        items.append((o.id, fr))
    cw = max(len(f) * (f[0].w * K + 8) for _, f in items) + 20
    rh = max(f[0].h * K for _, f in items) + 34
    rows = (len(items) + cols - 1) // cols
    img = Rgba(cols * cw + 10, rows * rh + 10, SPACE + (255,))
    for n, (name, fr) in enumerate(items):
        x0, y0 = 10 + (n % cols) * cw, 10 + (n // cols) * rh
        text(img, x0, y0, name, 'H', 2)
        for i, f in enumerate(fr): img.blit_spr(f, x0 + i * (f.w * K + 8), y0 + 18, K)
    img.save(path)
    print(img.w, img.h)
