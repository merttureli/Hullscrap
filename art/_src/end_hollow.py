"""hollow_truth: inside the Scrapper Gate. An empty bridge, a window onto the tunnel of the gate, a pale light at the end of it, and eleven chairs
set in a horseshoe, each turned a little, as if everyone had just stood up. One lamp left on. Cold, still, backlit."""
import math
from ill import *
from scene_common import *

VX, VY = 160, 88         # the vanishing point, at the foot of the window
K, CAMH = 80.0, 1.4      # focal length in px per world unit, camera height

def fl(xw, z): return VX + xw * K / z, VY + CAMH * K / z          # floor point -> screen

def room(im, gl, f):
    # ceiling, walls, floor as flat planes in perspective
    im.rect(0, 0, 320, 180, 'N')
    # floor
    horizon = VY + 10
    for y in range(horizon, 180):
        t = (y - horizon) / float(180 - horizon)
        for x in range(320):
            z = CAMH * K / max(1.0, (y - VY))
            xw = (x - VX) * z / K
            seam = abs(xw / 1.2 - round(xw / 1.2)) < 0.025 * max(1.0, z / 3.0) or abs(z / 1.2 - round(z / 1.2)) < 0.035
            c = 'D' if (int(xw / 1.2 + 50) + int(z / 1.2)) % 2 else 'E'
            if seam: c = 'N'
            im.put(x, y, c)
    # the floor in front of the window picks up its light: a long pale streak that fades toward us
    for y in range(horizon, 180):
        t = (y - horizon) / float(180 - horizon)
        for x in range(112, 208):
            dx = abs(x - VX) / 48.0
            a = (1 - dx) * (1 - t) ** 1.3 * 0.9
            if a > 0.05 and a * 0.8 > bay(x, y):
                c = im.get(x, y)
                im.put(x, y, 'W' if c in ('D', 'E') else 'S' if c == 'W' else c)
    # side walls and ceiling as shaded trapezoids, with seams that run toward the window
    lw = poly_cells([(0, 0), (30, 20), (30, 98), (0, 128)])
    rw = poly_cells([(320, 0), (290, 20), (290, 98), (320, 128)])
    ce = poly_cells([(0, 0), (320, 0), (290, 20), (30, 20)])
    for (x, y) in ce: im.put(x, y, pick(y / 20.0 * 0.6, ['N', 'N', 'I'], x, y, 1.4))
    for (x, y) in lw | rw: im.put(x, y, pick(0.25 + (abs(x - 160) - 130) / 180.0 * 0.5, ['N', 'I', 'N'], x, y, 1.5))
    for k in range(0, 21):
        xt = k * 16
        im.line(xt, 0, int(30 + xt / 320.0 * 260), 20, 'D')
    for t in (0.25, 0.5, 0.75):
        im.line(0, int(128 * t), 30, int(20 + 78 * t), 'D'); im.line(320, int(128 * t), 290, int(20 + 78 * t), 'D')
    for sg in (-1, 1):
        for xs in (6, 13, 21):
            x = 160 + sg * (160 - xs)
            im.line(x, int(xs * 0.66), x, int(128 - xs * 1.0), 'E')
    for (x, y) in lw | rw:
        if (x * 7 + y * 3) % 61 == 0: im.put(x, y, 'W')

def window(im, gl, f):
    # a wide curved window; through it, the tunnel of the gate and the pale light at its end
    x0, x1, y0, y1 = 30, 290, 20, 98
    win = ellipse_cells(160, 98, 130, 80) & rect_cells(x0, y0, x1 - x0, y1 - y0)
    im.fill(win, 'N')
    cx, cy = 160, 60
    # the rings of the gate receding to the end of the tunnel (each ring is a dark steel hoop with a rim light on its upper-left)
    rings = []
    r = 118.0
    k = 0
    while r > 3:
        rings.append((r, k)); r *= 0.78; k += 1
    for (r, k) in rings:
        sq = 0.72
        cells = ring_cells(cx, cy, r, r * sq, max(1.2, r * 0.07)) & win
        for (x, y) in cells:
            dx, dy = x - cx, y - cy
            lit_ = (dx + dy) < 0
            im.put(x, y, 'W' if lit_ else 'E')
        for (x, y) in cells:
            if (x - 1, y - 1) not in cells and (x, y) in cells and r > 10: im.put(x, y, 'M' if (x + y) % 3 else 'S')
        # dead running lights on each hoop, a few still lit pale
        for a in range(0, 360, 30):
            x = cx + r * math.cos(math.radians(a)); y = cy + r * sq * math.sin(math.radians(a))
            if (int(x), int(y)) in win and r > 6:
                on = ((a // 30 + k + f) % 5 == 0)
                im.put(int(x), int(y), 'z' if on else 'J')
                if on and r > 14: gl.blob(int(x), int(y), 4, 'i', 60, 1.8)
    # scaffold girders left across the tunnel by the people who built it
    for (a, b, c, d) in ((60, 30, 120, 70), (260, 80, 205, 52), (90, 90, 128, 62)):
        for (x, y) in line_cells(a, b, c, d):
            if (x, y) in win: im.put(x, y, 'E'); im.put(x, y - 1, 'W') if (x, y - 1) in win else None
    # the light at the end: pale, cold, a ring of it
    for (x, y) in ellipse_cells(cx, cy, 24, 24):
        d = math.hypot(x - cx, y - cy) / 24.0
        im.put(x, y, pick(1 - d ** 0.8 * 1.0, ['N', 'B', 'C', 'i', 'z', 'H'], x, y, 1.5))
    im.disc(cx, cy, 3, 'H')
    pulse = [0, 1, 2, 1][f % 4]
    gl.blob(cx, cy, 58 + pulse * 3, 'i', 120, 1.5)
    gl.blob(cx, cy, 22, 'z', 120, 1.4)
    # stars at the edges of the window, where the tunnel is wide and open
    r_ = Lcg(8)
    for k in range(34):
        x, y = r_.rng(34, 286), r_.rng(22, 94)
        if (x, y) in win and im.get(x, y) == 'N' and math.hypot((x - cx) / 130.0, (y - cy) / 70.0) > 0.7: im.put(x, y, 'S' if (k + f) % 4 else 'M')
    # frame: heavy dark mullions that radiate from the vanishing point, and a lip
    edge = grow(win, 2) - win
    for (x, y) in edge: im.put(x, y, 'K')
    for (x, y) in grow(win, 1) - win: im.put(x, y, 'W' if (x < 160 and y < 60) else 'E')
    # vertical mullions
    for mx in (70, 115, 205, 250):
        for y in range(y0 + 2, y1):
            if (mx, y) in win:
                im.put(mx, y, 'D'); im.put(mx + 1, y, 'E'); im.put(mx - 1, y, 'K')
    # the sill
    im.hline(x0 + 6, y1 - 1, x1 - x0 - 12, 'M'); im.hline(x0 + 8, y1, x1 - x0 - 16, 'S'); im.hline(x0 + 10, y1 + 1, x1 - x0 - 20, 'E')

def chair(im, gl, f, sx, sy, s, yaw, tone=0, ph=0):
    """a bridge chair seen from behind, backlit by the window; (sx, sy) is the floor under it, s px per world unit; yaw in -1..1 turns it a little."""
    sh = int(round(yaw * 0.12 * s))
    # shadow thrown toward us: the light is behind
    sp = [(sx - 0.3 * s, sy), (sx + 0.3 * s, sy), (sx + 0.4 * s + yaw * 0.3 * s, sy + 0.8 * s), (sx - 0.4 * s + yaw * 0.3 * s, sy + 0.8 * s)]
    sc = poly_cells(sp)
    for (x, y) in sc:
        if im.get(x, y) in ('D', 'E', 'W', 'S', 'N'): im.put(x, y, 'K' if ((y - sy) < 0.5 * s and (x + y) % 3) else 'N')
    # star base and pedestal
    for k in (-2, -1, 0, 1, 2):
        im.line(sx, sy - 0.05 * s, sx + k * 0.24 * s, sy + (0.02 + abs(k) * 0.01) * s, 'W')
        im.put(int(sx + k * 0.24 * s), int(sy + 0.05 * s), 'E')
    pw = max(1, int(0.1 * s))
    im.rect(int(sx - pw / 2.0), int(sy - 0.42 * s), pw + 1, int(0.4 * s), 'W'); im.vline(int(sx - pw / 2.0), int(sy - 0.42 * s), int(0.4 * s), 'S')
    # seat (edge visible under the backrest)
    seat = ellipse_cells(sx + sh * 0.5, sy - 0.44 * s, 0.46 * s, 0.1 * s)
    im.fill(seat, 'n'); im.outline(seat, 'K')
    # the backrest: rounded slab, worn leather in a different colour for each chair
    cols = (('n', 'q', 'Q'), ('E', 'W', 'S'), ('n', 'q', 'Q'), ('D', 'E', 'W'), ('n', 'u', 'q'), ('E', 'W', 'S'))[tone % 6]
    bw = 0.84 * s * (1 - abs(yaw) * 0.12)
    bx, by, bh = sx + sh, sy - 1.12 * s, 0.74 * s
    back = ellipse_cells(bx, by + 0.2 * s, bw * 0.5, 0.2 * s) | rect_cells(int(bx - bw / 2), int(by + 0.2 * s), int(bw), int(bh - 0.2 * s))
    head = ellipse_cells(bx, by - 0.04 * s, bw * 0.3, 0.14 * s)
    im.fill(back, cols[0]); im.fill(head, cols[0])
    for (x, y) in back:
        t = (x - (bx - bw / 2)) / float(max(1.0, bw))
        if 0.32 < t < 0.68: im.put(x, y, cols[1])
    for (x, y) in back | head:
        if (x, y - 1) not in (back | head): im.put(x, y, 'z' if s > 18 else 't')                         # rim light from the window along the top
        elif (x - 1, y) not in (back | head) or (x + 1, y) not in (back | head): im.put(x, y, 't' if (x + y) % 2 else 'i')
    im.vline(int(bx), int(by + 0.3 * s), int(bh - 0.35 * s), 'K')                                         # the stitched seam
    im.outline(back | head, 'K') if s > 16 else None
    # armrests
    for sg in (-1, 1):
        ax = int(bx + sg * (bw * 0.5 + 0.06 * s))
        im.rect(ax - (0 if sg > 0 else 1), int(sy - 0.66 * s), 2, max(2, int(0.22 * s)), 'W')
        im.put(ax, int(sy - 0.66 * s), 'S')

def consoles(im, gl, f):
    # dead consoles along both walls, one with its amber lamp still on
    specs = [(-1, 3.2, 0), (-1, 4.6, 1), (-1, 6.4, 2), (1, 3.2, 3), (1, 4.6, 4), (1, 6.4, 5)]
    for (sg, z, k) in specs:
        xw = sg * 6.2
        sx, sy = fl(xw, z)
        sc = K / z
        w, h = int(1.6 * sc), int(0.8 * sc)
        x0 = int(sx - w / 2)
        box = rect_cells(x0, int(sy - h), w, h)
        im.fill(box, 'E'); im.hline(x0, int(sy - h), w, 'W'); im.hline(x0, int(sy - 1), w, 'D')
        scr = rect_cells(x0 + 2, int(sy - h + 2), w - 4, max(2, h // 2))
        im.fill(scr, 'N')
        for (x, y) in scr:
            if (x * 5 + y * 3 + k) % 17 == 0: im.put(x, y, 'B')
        im.outline(box, 'K')
        if k == 0:
            lampx, lampy = x0 + w - 4, int(sy - h) - 1
            lampx = x0 + w - 12
            im.rect(lampx, lampy - 6, 2, 6, 'S'); im.put(lampx, lampy - 6, 'M'); im.rect(lampx - 3, lampy - 1, 8, 1, 'E')
            im.poly([(lampx - 4, lampy - 8), (lampx + 5, lampy - 8), (lampx + 3, lampy - 12), (lampx - 2, lampy - 12)], 'a')
            im.hline(lampx - 4, lampy - 8, 9, 'y'); im.hline(lampx - 2, lampy - 12, 5, 'Y')
            im.hline(lampx - 4, lampy - 7, 9, 'u')
            gl.blob(lampx, lampy - 6, 26 if f % 4 != 3 else 22, 'a', 150, 1.7)
            gl.blob(lampx + 4, lampy + 10, 34, 'a', 45, 1.4, squash=0.6)

def ceiling_lamps(im, gl, f):
    for sg in (-1, 1):
        for z in (2.4, 3.2, 4.4, 6.0, 8.0, 10.5):
            x = VX + sg * 2.4 * K / z
            y = VY - 3.6 * K / z * 0.5 - 4
            on = (sg > 0 and z == 4.4 and f % 4 in (0, 1)) or (sg < 0 and z == 8.0 and f % 2 == 0)
            w = max(2, int(2.0 * K / z / 2))
            im.hline(int(x - w / 2), int(y), w, 'z' if on else 'W')
            if on: gl.blob(x, y + 2, 7, 'i', 70, 1.8)

def render(f=0):
    im, gl = Ill(), Glow()
    room(im, gl, f)
    window(im, gl, f)
    ceiling_lamps(im, gl, f)
    consoles(im, gl, f)
    # a ring inlaid in the floor, eleven notches on it, one per chair (a faint cold light)
    for a in range(0, 720):
        ph = math.radians(a / 2.0)
        x, y = fl(6.6 * math.cos(ph), 5.0 + 2.9 * math.sin(ph) + 0.4)
        x, y = int(round(x)), int(round(y))
        if 0 <= x < 320 and 0 <= y < 180 and y > VY + 12 and im.get(x, y) in ('D', 'E', 'W', 'N', 'S'):
            im.put(x, y, 'B' if (a // 6) % 2 == 0 else 'J')
    # the horseshoe: eleven chairs, far to near, each turned a little
    chairs = []
    for i in range(11):
        t = -1 + i * 0.2
        xw = 5.1 * t
        z = 3.4 + 2.5 * (1 - t * t)
        yaw = -t * 0.9 + [0.2, -0.3, 0.5, -0.1, 0.35, 0.0, -0.4, 0.25, -0.2, 0.4, -0.35][i]
        chairs.append((z, xw, yaw, i))
    for (z, xw, yaw, i) in sorted(chairs, reverse=True):
        sx, sy = fl(xw, z)
        chair(im, gl, f, int(round(sx)), int(round(sy)), K / z * 1.05, max(-1, min(1, yaw)), tone=[0, 1, 2, 5, 0, 3, 1, 4, 2, 5, 0][i], ph=i)
    # motes in the window light
    motes(im, gl, f, 31, 34, (96, 70, 224, 150), ('z', 'i', 't'), 0, -1, 'i', 50)
    # a cold vignette
    for y in range(180):
        for x in range(320):
            v = ((x - 160) / 175.0) ** 2 + ((y - 95) / 110.0) ** 2
            if v > 0.62 and (v - 0.62) * 1.5 > bay(x, y): im.put(x, y, darken(im.get(x, y)))
    return im, gl

REG = {'hollow_truth': (render, 4, "Inside the Scrapper Gate: an empty bridge, a window onto the tunnel of the gate and the pale light at its end, eleven chairs in a horseshoe each turned a little, one amber lamp left on. Frames: the light at the end breathes, a dead lamp flickers, dust drifts in the window light.")}
