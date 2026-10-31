"""Shared bits for the ending scenes: star fields that twinkle, nebula clouds, motes that drift in a perfect 4-frame loop, glow helpers."""
import math
from ill import *

def space_gradient(im, y0=0, y1=None, ramp=('N', 'N', 'I', 'J'), t0=0.0, t1=1.0):
    im.vgrad(0, y0, im.w, y1 or im.h, list(ramp), t0, t1, sharp=0.8)

def nebula(im, seed, cx, cy, rx, ry, ramp, thr=0.34, gain=2.4, scale=(46.0, 38.0), tilt=0.0, only=None, soft=1.0):
    """a nebula cloud: fbm noise under an elliptical envelope, mapped through `ramp` ('.' = leave the sky). `only`: letters it may paint over."""
    for y in range(max(0, int(cy - ry)), min(im.h, int(cy + ry) + 1)):
        for x in range(max(0, int(cx - rx)), min(im.w, int(cx + rx) + 1)):
            dx, dy = (x - cx) / float(rx), (y - cy) / float(ry)
            d = dx * dx + dy * dy
            if d >= 1: continue
            if only is not None and im.get(x, y) not in only: continue
            n = fbm01(x / scale[0] + tilt * y / 90.0, y / scale[1], seed, 4)
            v = (n - thr) * gain * (1 - d) ** soft
            if v > 0.04: im.put(x, y, pick(min(1.0, v), list(ramp), x, y))

def starfield(im, gl, f, seed, n, ymax=None, region=None, wrong=False, flare=True, only=('N', 'I', 'J', 'K', 'Z', 'V', 'd', 'P', 'w', 'B', 'C')):
    r = Lcg(seed)
    ymax = ymax or im.h
    for k in range(n):
        x, y = r.below(im.w), r.below(ymax)
        t = r.below(12); ph = r.below(4)
        c = 'W' if t < 4 else 'S' if t < 7 else 'M' if t < 9 else r.pick(['k', 'i', 'y', 'a', 'z', 'p', 'X'])
        if im.get(x, y) not in only: continue
        if t >= 8 and (f + ph) % 4 == 0: c = lighten(c) if c in UP else c
        im.put(x, y, c)
        if t == 11 and flare:
            on = (f + ph) % 4 in (0, 1)
            for (dx, dy) in ((1, 0), (-1, 0), (0, 1), (0, -1)): im.put(x + dx, y + dy, 'x' if on else 'W')
            if on:
                for (dx, dy) in ((2, 0), (-2, 0), (0, 2), (0, -2)): im.put(x + dx, y + dy, 'W')
                gl.blob(x, y, 5, 'z', 45, 1.5)

def motes(im, gl, f, seed, n, box, col=('H', 'L', 'z'), dx=1, dy=0, glow=None, ga=60):
    """dust motes that drift `dx, dy` px per frame and live 3 of the 4 frames (the 4th they are 'reborn' elsewhere), so the loop has no jump."""
    r = Lcg(seed)
    (x0, y0, x1, y1) = box
    for k in range(n):
        x, y = r.rng(x0, x1), r.rng(y0, y1)
        ph = r.below(4); t = (f + ph) % 4
        if t == 3: continue
        mx, my = x + t * dx, y + t * dy
        c = col[k % len(col)]
        im.put(mx, my, c)
        if glow: gl.blob(mx, my, 3, glow, ga, 1.2)

def dim_stars_behind(im, cells):
    pass

def lights_row(im, gl, pts, f, col='y', period=4, blink='chase', r=4, a=110):
    """a row of lamps; 'chase' lights one in `period` and the lit one walks along each frame."""
    for k, (x, y) in enumerate(pts):
        on = ((k - f) % period == 0) if blink == 'chase' else ((k + f) % 2 == 0)
        im.put(x, y, col if on else 'W')
        if on: gl.blob(x, y, r, col, a, 1.8)
