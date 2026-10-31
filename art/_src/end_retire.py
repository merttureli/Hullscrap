"""retire: Gantry Rusthold's berth at dusk. The player's ship is tied up for good, laundry on the line, a gas giant swallowing the sun, and in the foreground a mug on the rail and a helmet on its hook."""
import math
from ill import *
from scene_common import *
from ships_side import body, flame, lamp, hazard, container

HOR = 118          # where the sky meets the planet's limb at the middle

def sky(im, gl, f):
    SX, SY = 40, 124
    for y in range(0, 170):
        for x in range(320):
            vert = min(1.0, max(0.0, (y - 0) / 140.0))
            sunf = math.exp(-(((x - SX) / 210.0) ** 2 + ((y - SY) / 52.0) ** 2) * 1.0)
            v = vert ** 1.7 * 0.6 + sunf * 0.62
            im.put(x, y, pick(v, ['N', 'N', 'I', 'Z', 'd', 'P', 'w', 'o', 'Y'], x, y, 1.5))
    starfield(im, gl, f, 12, 190, 96, only=('N', 'I', 'Z'))
    # the setting sun, half behind the planet: a hot disc with a ragged halo
    im.rgrad(SX, SY, 34, ['H', 'y', 'Y', 'o', 'w', '.'], sharp=1.0)
    gl.blob(SX, SY, 70, 'o', 110, 1.5, squash=0.6)
    gl.blob(SX, SY - 4, 22, 'y', 130, 1.5)

def planet(im, gl, f):
    cx, cy, rx, ry = 170, 322, 300, 222
    cells = ellipse_cells(cx, cy, rx, ry)
    for (x, y) in cells:
        dy = (y - 100) / 72.0
        band = 0.5 + 0.5 * math.sin(dy * 9.0 + math.sin(x / 40.0) * 0.6)
        lit_ = max(0.0, 1.0 - (x - 20) / 360.0)
        v = 0.3 + band * 0.25 + lit_ * 0.35 - (y - 100) / 300.0 * 0.3
        im.put(x, y, pick(v, ['N', 'I', 'Z', 'd', 'P'], x, y, 1.8))
    # the thin bright atmosphere along the limb, strongest toward the sun
    for rr in range(1, 5):
        ring = ellipse_cells(cx, cy, rx + rr, ry + rr) - ellipse_cells(cx, cy, rx + rr - 1, ry + rr - 1)
        for (x, y) in ring:
            if y > 150: continue
            lit_ = math.exp(-(((x - 44) / 140.0) ** 2)) * (1.0 - (rr - 1) * 0.28) + 0.1
            if lit_ > bay(x, y): im.put(x, y, ['Y', 'o', 'w', 'P'][rr - 1] if x < 200 else ['i', 'k', 'j', 'J'][rr - 1])
    # the cloud bands catch the last light: a few bright streaks along the limb on the lit side
    r = Lcg(33)
    for k in range(26):
        x = r.rng(0, 150); y0 = int(322 - 222 * math.sqrt(max(0, 1 - ((x - 170) / 300.0) ** 2)))
        y = y0 + r.rng(4, 36)
        for i in range(r.rng(5, 16)): 
            if im.get(x + i, y) in ('d', 'P', 'Z'): im.put(x + i, y, 'w' if i < 8 else 'P')
    gl.blob(60, 142, 90, 'w', 40, 1.3, squash=0.35)

def wheel(im, gl, f):
    # a slow spoked wheel on the station, far back (6 spokes: 4 frames of 15 degrees loop exactly)
    cx, cy, R = 78, 66, 38
    ring = ring_cells(cx, cy, R, R, 3)
    im.fill(ring, 'I'); im.fill({(x, y) for (x, y) in ring if (x - cx) + (y - cy) < -8}, 'j')
    im.outline(ring, 'N'); im.outline(ellipse_cells(cx, cy, R - 3, R - 3), 'N')
    for k in range(6):
        a = math.radians(k * 60 + f * 15)
        for t in range(6, R - 2):
            x, y = cx + t * math.cos(a), cy + t * math.sin(a)
            im.put(int(round(x)), int(round(y)), 'I'); im.put(int(round(x)) + 1, int(round(y)), 'N')
        for t in (R - 2, ):
            pass
    im.fill(ellipse_cells(cx, cy, 7, 7), 'J'); im.fill(ellipse_cells(cx, cy, 4, 4), 'I'); im.put(cx - 2, cy - 2, 'j')
    for k in range(18):
        a = math.radians(k * 20 + f * 15)
        x, y = cx + (R - 1.5) * math.cos(a), cy + (R - 1.5) * math.sin(a)
        on = (k + f) % 3 != 0
        im.put(int(round(x)), int(round(y)), 'y' if on else 'a')
        if on: gl.blob(x, y, 4, 'y', 70, 1.8)

def station(im, gl, f):
    """Gantry Rusthold: a pile of welded wrecks rising from the right, rim-lit warm on the side facing the sun."""
    r = Lcg(404)
    def tower(x0, ybase, w, tones, windows=True, depth=0):
        h_total = 0
        y = ybase
        n = r.rng(3, 6)
        for k in range(n):
            mw = r.rng(int(w * 0.5), w)
            mh = r.rng(12, 26)
            mx = x0 + r.rng(0, w - mw)
            tone = tones[r.below(len(tones))]
            cells = rect_cells(mx, y - mh, mw, mh)
            ramp = {'u': ['n', 'q', 'u', 'T'], 'g': ['D', 'E', 'W', 'S'], 'b': ['N', 'I', 'J', 'j'], 'q': ['n', 'n', 'q', 'Q']}[tone]
            if depth: ramp = ['N', 'I', 'I', 'J']
            body(im, cells, ramp, y - mh, y, outline='K' if not depth else 'N', sharp=2.2)
            for sx in range(mx + 4, mx + mw - 2, 7): im.vline(sx, y - mh + 2, mh - 3, ramp[0])
            if windows and not depth:
                for wy in range(y - mh + 4, y - 4, 6):
                    for wx in range(mx + 3, mx + mw - 3, 6):
                        on = (wx * 7 + wy * 3 + f) % 5 not in (0, 1) or (wx + wy) % 4 == 0
                        if (wx * 3 + wy) % 4 != 1:
                            im.put(wx, wy, 'y' if on else ramp[0]); im.put(wx + 1, wy, 'a' if on else ramp[0])
                            if on and (wx + wy) % 3 == 0: gl.blob(wx, wy, 4, 'y', 60, 1.8)
            if r.below(3) == 0:                                      # a tank or a dome on top
                im.fill(ellipse_cells(mx + mw // 2, y - mh, mw // 3, 4) & rect_cells(0, 0, 400, y - mh), ramp[2])
            if r.below(2) == 0:
                ax = mx + r.rng(2, mw - 3)
                im.vline(ax, y - mh - r.rng(5, 14), 12, ramp[1]); 
            y -= mh
            h_total += mh
        return y
    # far, hazy pieces
    # the main pile on the right
    tower(228, 150, 52, ['u', 'g', 'q'])
    tower(270, 152, 52, ['g', 'u', 'q'])
    tower(206, 152, 34, ['q', 'g'])
    # a big ship hull welded on sideways (a rust-red cylinder with a dome), the clan sigil painted on
    hull = poly_cells([(286, 40), (318, 36), (324, 60), (322, 98), (292, 100), (284, 70)])
    body(im, hull, ['n', 'q', 'u', 'T'], 36, 100, sharp=2.4)
    for wy in range(46, 96, 8):
        for wx in range(292, 318, 6): im.put(wx, wy, 'y' if (wx + wy + f) % 3 else 'a'); gl.blob(wx, wy, 4, 'y', 50, 1.8)
    for sy in (58, 80): im.hline(286, sy, 36, 'n')
    # lit signs: GANTRY on a plate bolted to the wall, in the 3x5 font at 2x
    tx, ty = 232, 106
    im.rect(228, ty - 4, 56, 16, 'n'); im.hline(228, ty - 4, 56, 'u'); im.outline(rect_cells(228, ty - 4, 56, 16), 'K')
    for (qx, qy) in ((230, ty - 2), (281, ty - 2), (230, ty + 9), (281, ty + 9)): im.put(qx, qy, 'M')
    for ch in 'GANTRY':
        g = F35[ch]
        for i, b in enumerate(g):
            if b == '1':
                for dy in range(2):
                    for dx in range(2): im.put(tx + (i % 3) * 2 + dx, ty + (i // 3) * 2 + dy, 'a')
        tx += 8
    gl.rect(232, 106, 48, 10, 'a', 40)
    # cranes: a gantry arm swinging out over the berth with a hook light
    im.line(270, 70, 224, 80, 'E'); im.line(270, 71, 224, 81, 'W'); im.line(270, 70, 270, 44, 'W'); im.line(224, 80, 224, 100 + (f % 2), 'M')
    im.rect(222, 100 + (f % 2), 5, 3, 'a'); gl.blob(224, 102, 10, 'y', 130, 1.6)
    # silhouetted beacons: red lamps that blink on the high points
    for (x, y, ph) in ((270, 43, 0), (322, 34, 1), (246, 62, 2)):
        on = (f + ph) % 2 == 0
        im.put(x, y, 'r' if on else 'n')
        if on: gl.blob(x, y, 6, 'r', 130, 1.8)

def berth(im, gl, f):
    # the berth: a long steel deck, bollards, crates, lamp posts, a ladder, a painted number
    y0 = 148
    im.rect(0, y0, 320, 32, 'E')
    for x in range(0, 320, 20): im.vline(x, y0, 32, 'D')
    for y in range(y0 + 6, 180, 8): im.hline(0, y, 320, 'D')
    im.hline(0, y0, 320, 'M'); im.hline(0, y0 + 1, 320, 'S'); im.hline(0, y0 + 2, 320, 'W')
    im.hline(0, y0 + 3, 320, 'E')
    for x in range(0, 320, 20):                              # rivets
        for y in range(y0 + 4, 180, 8): im.put(x + 2, y, 'W'); im.put(x + 17, y, 'D')
    # long warm light of the sun along the deck (it comes from the left)
    for y in range(y0, 180):
        for x in range(0, 200):
            t = (1 - (x / 200.0)) * (1 - (y - y0) / 32.0) * 0.55
            if t > bay(x, y): im.put(x, y, lighten(im.get(x, y)))
    # bollards and crates
    for bx in (34, 118, 212):
        body(im, rect_cells(bx, y0 - 8, 8, 8), ['n', 'q', 'u', 'T'], y0 - 8, y0, sharp=2.0)
        im.fill(ellipse_cells(bx + 4, y0 - 8, 5, 2), 'T'); im.hline(bx + 1, y0 - 9, 6, 'Y')
    container(im, 258, y0 - 14, 20, 14, 'u', 3); container(im, 262, y0 - 26, 14, 12, 'W', 4); container(im, 282, y0 - 10, 12, 10, 'a', 5)
    # lamp posts that have just come on
    for lx in (14, 196, 304):
        im.vline(lx, y0 - 30, 30, 'W'); im.vline(lx + 1, y0 - 30, 30, 'E'); im.hline(lx - 1, y0 - 31, 5, 'S')
        im.rect(lx - 2, y0 - 36, 6, 5, 'y'); im.hline(lx - 2, y0 - 37, 6, 'W'); im.hline(lx - 2, y0 - 31, 6, 'W')
        gl.blob(lx + 1, y0 - 34, 16, 'y', 150, 1.7); gl.blob(lx + 1, y0 - 8, 30, 'y', 40, 1.4, squash=0.4)

def hero(im, gl, f, x, y, L=118):
    """the player's ship, tied up: a scrap-built long-hauler with a lit canopy, a radar dish that turns, laundry on the line. (x, y) = centre; faces right."""
    H = 30
    x0, x1 = x - L // 2, x + L // 2
    hull = poly_cells([(x0 + 4, y - H // 2 + 2), (x1 - 34, y - H // 2 + 2), (x1 - 10, y - H // 2 + 8), (x1, y + 2), (x1 - 6, y + H // 2), (x0 + 8, y + H // 2), (x0, y + H // 2 - 4), (x0 - 1, y - H // 2 + 6)])
    body(im, hull, ['n', 'E', 'W', 'S', 'M'], y - H // 2 + 2, y + H // 2, sharp=2.6, tl=0.2, x0=x0, x1=x1)
    # panels: steel plates and rust patches, rivets, a hazard band, a long weld
    for (px_, py_, pw, ph, c1) in ((x0 + 10, y - 8, 22, 12, 'u'), (x0 + 44, y - 2, 18, 12, 'u'), (x0 + 70, y - 10, 14, 10, 'T'), (x0 + 30, y + 4, 12, 7, 'q')):
        for j in range(ph):
            for i in range(pw):
                if (px_ + i, py_ + j) in hull: im.put(px_ + i, py_ + j, 'T' if (j == 0 and c1 == 'u') else c1 if j < ph - 1 else 'n')
        for (bx, by) in ((px_ + 1, py_ + 1), (px_ + pw - 2, py_ + 1), (px_ + 1, py_ + ph - 2), (px_ + pw - 2, py_ + ph - 2)):
            if (bx, by) in hull: im.put(bx, by, 'M')
    for sx in (x0 + 36, x0 + 66, x0 + 94): im.vline(sx, y - H // 2 + 3, H - 5, 'E')
    im.hline(x0 + 4, y + 7, L - 18, 'E')
    hazard(im, x0 + 2, y + H // 2 - 6, 18, 4)
    # a scorch above the engines, a dent near the nose
    for k in range(10): im.put(x0 + 14 + k, y - H // 2 + 3 + (k * 7) % 3, 'K')
    # the superstructure: bridge block with a big canopy lit warm (someone left the light on)
    bridge = poly_cells([(x + 14, y - H // 2 + 2), (x + 20, y - H // 2 - 12), (x + 46, y - H // 2 - 12), (x + 52, y - H // 2 + 2)])
    body(im, bridge, ['E', 'W', 'S', 'M'], y - H // 2 - 12, y - H // 2 + 2, sharp=2.4)
    can = poly_cells([(x + 22, y - H // 2 - 2), (x + 25, y - H // 2 - 9), (x + 44, y - H // 2 - 9), (x + 47, y - H // 2 - 2)])
    for (cx_, cy_) in can: im.put(cx_, cy_, pick(1 - (cy_ - (y - H // 2 - 9)) / 8.0, ['a', 'y', 'y', 'Y'], cx_, cy_, 1.6))
    for mx in (x + 31, x + 38): im.vline(mx, y - H // 2 - 9, 7, 'E')
    im.hline(x + 23, y - H // 2 - 9, 22, 'L')
    gl.blob(x + 35, y - H // 2 - 5, 30, 'y', 130, 1.6); gl.blob(x + 35, y - H // 2 + 14, 44, 'y', 40, 1.4, squash=0.5)
    # radar dish on a mast, turning (4 frames)
    mx, my = x + 18, y - H // 2 - 12
    im.vline(mx, my - 12, 12, 'M'); im.vline(mx + 1, my - 12, 12, 'E')
    ang = f * math.pi / 8
    ex, ey = math.cos(ang) * 6, math.sin(ang) * 2.4
    im.line(mx - ex, my - 13 - ey, mx + ex, my - 13 + ey, 'L'); im.line(mx - ex, my - 12 - ey, mx + ex, my - 12 + ey, 'S')
    im.put(mx, my - 14, 'r' if f % 2 == 0 else 'n'); gl.blob(mx, my - 14, 5, 'r', 110 if f % 2 == 0 else 20, 1.8)
    # engines at the stern, idling
    for k, ey in enumerate((y - 9, y + 1, y + 9)):
        im.rect(x0 - 5, ey - 3, 6, 6, 'W'); im.vline(x0 - 5, ey - 3, 6, 'S'); im.hline(x0 - 5, ey - 3, 6, 'M'); im.hline(x0 - 5, ey + 2, 6, 'K')
        im.put(x0 - 6, ey, 'o' if (f + k) % 2 == 0 else 'a'); im.put(x0 - 7, ey, 'a')
        gl.blob(x0 - 7, ey, 9, 'o', 80, 1.6)
    # nav lamps, a lit hatch with a gangway to the deck
    lamp(im, gl, x1 - 4, y - 2, 'g', f, 0, False, 6)
    lamp(im, gl, x0 + 4, y - H // 2 + 4, 'r', f, 1, False, 6)
    hx = x - 10
    im.rect(hx, y + 2, 12, 14, 'n'); im.rect(hx + 1, y + 3, 10, 12, 'a'); im.rect(hx + 3, y + 5, 6, 10, 'y')
    gl.blob(hx + 6, y + 10, 18, 'y', 90, 1.6)
    ramp = [(hx + 4, y + 16), (hx + 12, y + 16), (hx + 30, 148), (hx + 20, 148)]
    im.fill(poly_cells(ramp), 'W'); im.line(hx + 4, y + 16, hx + 20, 148, 'M'); im.line(hx + 12, y + 16, hx + 30, 148, 'E')
    for k in range(1, 4):
        t = k / 4.0; im.hline(int(hx + 4 + 16 * t - 1), int(y + 16 + (148 - y - 16) * t), 9, 'S')
    # landing struts into the deck
    for lx in (x0 + 18, x + 4, x1 - 22):
        im.vline(lx, y + H // 2, 148 - (y + H // 2), 'W'); im.vline(lx - 1, y + H // 2, 148 - (y + H // 2), 'M'); im.hline(lx - 3, 148, 7, 'S')
    # mooring lines to the bollards
    for (bx, ax, ay) in ((38, x0 + 8, y + H // 2 - 4), (122, x0 + 30, y + H // 2), (212, x1 - 10, y + H // 2 - 2)):
        pts = []
        for t in range(0, 31):
            u = t / 30.0
            pts.append((ax + (bx - ax) * u, ay + (140 - ay) * u + 6 * math.sin(math.pi * u)))
        for (p, q) in zip(pts, pts[1:]): im.line(p[0], p[1], q[0], q[1], 'Q')
    # the laundry line: from a short mast on the stern to the lamp post, shirts against the sunset that sway (4 frames)
    sx_, sy_ = x0 + 6, y - H // 2 - 12
    im.vline(sx_, sy_, 12, 'M'); im.put(sx_, sy_ - 1, 'S')
    ax, ay = sx_, sy_
    bx, by = 15, 148 - 34
    pts = []
    for t in range(0, 41):
        u = t / 40.0
        pts.append((ax + (bx - ax) * u, ay + (by - ay) * u + 8 * math.sin(math.pi * u)))
    for (p, q) in zip(pts, pts[1:]): im.line(p[0], p[1], q[0], q[1], 'M')
    for k, (t, c, c2) in enumerate(((6, 'w', 'p'), (13, 'z', 'L'), (20, 'a', 'y'), (27, 'k', 'b'), (34, 'r', 'w'))):
        px_, py_ = pts[t]
        sw = [0, 1, 1, 0][(f + k) % 4] - (1 if (f + k) % 4 == 3 else 0)
        px_, py_ = int(px_), int(py_)
        body_ = poly_cells([(px_ - 2, py_ + 1), (px_ + 3, py_ + 1), (px_ + 3 + sw, py_ + 8), (px_ - 2 + sw, py_ + 8)])
        sl = poly_cells([(px_ - 4, py_ + 1), (px_ - 2, py_ + 1), (px_ - 2, py_ + 4), (px_ - 4 + sw, py_ + 4)]) | poly_cells([(px_ + 3, py_ + 1), (px_ + 5, py_ + 1), (px_ + 5 + sw, py_ + 4), (px_ + 3, py_ + 4)])
        im.fill(body_ | sl, c)
        for (qx, qy) in body_ | sl:
            if qx > px_ + 1: im.put(qx, qy, c2)
        im.outline(body_ | sl, 'K')
        im.put(px_, py_, 'M')
    return hull

def foreground(im, gl, f):
    # the rail: a pipe on posts, dark against the dusk, warm rim on the sunward edge
    y = 160
    for x in range(0, 320, 40):
        im.rect(x + 6, y - 2, 4, 22, 'D'); im.vline(x + 6, y - 2, 22, 'W'); im.vline(x + 9, y - 2, 22, 'K'); im.put(x + 7, y - 3, 'S')
    for i, c in enumerate(['M', 'S', 'W', 'E', 'D', 'K']): im.hline(0, y - 4 + i, 320, c)
    for i in range(0, 320, 5): im.put(i, y - 4, 'L') if (i // 5) % 3 == 0 else None
    im.hline(0, y + 5, 320, 'W'); im.hline(0, y + 6, 320, 'D'); im.hline(0, y + 7, 320, 'K')
    # the cheap deck under our feet
    im.rect(0, y + 8, 320, 12, 'K')
    for x in range(0, 320, 16): im.vline(x, y + 8, 12, 'N')
    # the mug: big, chipped, with coffee that has gone cold-ish and steam that has not
    mx, my = 62, y - 5
    cup = poly_cells([(mx - 8, my - 14), (mx + 8, my - 14), (mx + 7, my), (mx - 7, my)])
    for (x, yy) in cup:
        t = (x - (mx - 8)) / 16.0
        im.put(x, yy, 'Y' if t < 0.2 else 'L' if t < 0.45 else 'M' if t < 0.7 else 'S' if t < 0.9 else 'W')
    im.hline(mx - 8, my - 14, 16, 'H'); im.hline(mx - 7, my - 1, 14, 'W')
    im.outline(cup, 'K')
    im.fill(rect_cells(mx - 6, my - 14, 12, 2), 'n'); im.hline(mx - 5, my - 14, 10, 'q')             # coffee
    handle = ring_cells(mx + 9, my - 8, 5, 5, 2) & rect_cells(mx + 8, my - 14, 8, 12)
    im.fill(handle, 'L'); im.outline(handle, 'K')
    for (px_, py_) in ((mx - 3, my - 8), (mx - 2, my - 8), (mx - 2, my - 7), (mx - 3, my - 7)): im.put(px_, py_, 'a')   # a stripe: Gantry amber
    for k in range(5): im.put(mx - 6 + k * 3, my - 5, 'a')
    im.put(mx + 5, my - 13, 'K'); im.put(mx + 6, my - 12, 'K')                                          # a chip
    # steam, 4 frames of wisps that curl and thin
    for k in range(3):
        for t in range(0, 14):
            sx = mx - 3 + k * 3 + int(math.sin((t + f * 3.5 + k * 2) * 0.55) * 2.0)
            sy = my - 16 - t
            if (t + k + f) % 5 != 4: im.put(sx, sy, 'L' if t < 7 else 'M' if t < 11 else 'S')
    gl.blob(mx, my - 22, 14, 'z', 30, 1.6)
    gl.blob(mx - 2, my - 6, 20, 'y', 40, 1.5, squash=0.7)
    # the helmet on its hook: a dome, a dark visor with the last of the sun in it, a strap
    hx, hy = 100, y - 44
    im.vline(hx, y - 4, -(hy - 4 - y + 4), 'W') if False else None
    im.rect(hx - 2, hy - 10, 4, 12, 'E'); im.vline(hx - 2, hy - 10, 12, 'S'); im.rect(hx - 1, hy - 14, 3, 5, 'W')
    im.hline(hx - 6, hy - 11, 18, 'S') if False else None
    im.line(hx + 1, hy + 2, hx + 9, hy + 2, 'W'); im.line(hx + 9, hy + 2, hx + 9, hy + 6, 'W')                  # the hook arm
    hx2, hy2 = hx + 9, hy + 6
    dome = ellipse_cells(hx2, hy2 + 10, 11, 11)
    body(im, dome & rect_cells(0, 0, 400, hy2 + 21), ['E', 'W', 'S', 'M', 'L'], hy2, hy2 + 20, sharp=2.0)
    for (x, yy) in dome:
        if (x - 1, yy - 1) not in dome: im.put(x, yy, 'H')
    im.outline(dome, 'K')
    visor = ellipse_cells(hx2 + 1, hy2 + 12, 8, 5)
    im.fill(visor, 'N')
    for (x, yy) in visor:
        if yy < hy2 + 11 and x < hx2 - 1: im.put(x, yy, 'Y' if (x + yy) % 2 else 'o')
        elif yy < hy2 + 12 and x < hx2 + 1: im.put(x, yy, 'j')
    im.outline(visor, 'K')
    im.rect(hx2 + 7, hy2 + 14, 3, 8, 'E')
    im.hline(hx2 - 8, hy2 + 20, 16, 'D')
    gl.blob(hx2 - 4, hy2 + 6, 14, 'y', 60, 1.6)
    # a sign bolted to the next post: BERTH 7, painted by a hurried hand
    sx0, sy0 = 262, 134
    im.rect(sx0, sy0, 36, 16, 'n'); im.hline(sx0, sy0, 36, 'u'); im.rect(sx0 + 1, sy0 + 1, 34, 14, 'a'); im.hline(sx0 + 1, sy0 + 1, 34, 'y')
    im.outline(rect_cells(sx0, sy0, 36, 16), 'K')
    tx = sx0 + 4
    for ch in 'BERTH 7':
        g = F35[ch]
        for i, b in enumerate(g):
            if b == '1': im.put(tx + (i % 3), sy0 + 5 + (i // 3) * 2, 'K'); im.put(tx + (i % 3), sy0 + 6 + (i // 3) * 2, 'K')
        tx += 4
    im.put(sx0 + 2, sy0 + 2, 'K'); im.put(sx0 + 33, sy0 + 2, 'K'); im.put(sx0 + 2, sy0 + 13, 'K'); im.put(sx0 + 33, sy0 + 13, 'K')
    im.vline(sx0 + 4, sy0 + 16, 12, 'W'); im.vline(sx0 + 30, sy0 + 16, 12, 'W')

def render(f=0):
    im, gl = Ill(), Glow()
    sky(im, gl, f)
    wheel(im, gl, f)
    planet(im, gl, f)
    station(im, gl, f)
    berth(im, gl, f)
    hero(im, gl, f, 138, 113, 118)
    foreground(im, gl, f)
    motes(im, gl, f, 55, 18, (10, 60, 300, 138), ('y', 'Y'), 1, -1, 'y', 40)
    # vignette
    for y in range(180):
        for x in range(320):
            v = ((x - 160) / 190.0) ** 2 + ((y - 90) / 120.0) ** 2
            if v > 0.8 and (v - 0.8) * 1.4 > bay(x, y): im.put(x, y, darken(im.get(x, y)))
    return im, gl

REG = {'retire': (render, 4, "Gantry Rusthold's berth at dusk: the player's ship tied up for good, laundry on the line, a gas giant swallowing the sun, a mug steaming on the rail and a helmet on its hook. Frames: steam, the radar dish, the swaying laundry, blinking beacons, windows.")}
