"""HUD icons for sector points of interest: art/ui/poi_icons.png (+ _glow): 16x16 per icon in a horizontal strip, bold at 1x, drawn in the family colours:
distress red + amber, quest gold, Lumen cyan, Concord blue, pirate red. Code-drawn pixel by pixel with a 1 px near-black outline, like everything else."""
import math, json, os
from px import *
import pal_sector
from lines_kit import circle, ring, line
from mach import outline_all
from sector_fx import halo_px, save_strip_rgba, write_json

def ell(s, cx, cy, rx, ry, c):
    for y in range(16):
        for x in range(16):
            if ((x + .5 - cx) / rx) ** 2 + ((y + .5 - cy) / ry) ** 2 <= 1: s.put(x, y, c)

def lit_disc(s, cx, cy, r, tones):
    """a disc shaded from the top-left: tones = (light, mid, dark)."""
    for y in range(16):
        for x in range(16):
            dx, dy = x + .5 - cx, y + .5 - cy
            d = math.hypot(dx, dy)
            if d <= r:
                k = (dx + dy) / (2 * r) if r else 0
                s.put(x, y, tones[0] if k < -0.35 else tones[2] if k > 0.4 else tones[1])

def poly(s, pts, c):
    n = len(pts)
    for y in range(16):
        for x in range(16):
            inside = False
            for k in range(n):
                ax, ay = pts[k]; bx, by = pts[(k + 1) % n]
                if (ay > y + .5) != (by > y + .5) and x + .5 < (bx - ax) * (y + .5 - ay) / (by - ay) + ax: inside = not inside
            if inside: s.put(x, y, c)

def edge_light(s, base, hi, lo):
    """pixels of colour `base` take `hi` on up/left edges and `lo` on down/right edges."""
    n = s.copy()
    for y in range(s.h):
        for x in range(s.w):
            if s.g[y][x] != base: continue
            if s.get(x, y + 1) != base or s.get(x + 1, y) != base: n.g[y][x] = lo
            elif s.get(x, y - 1) != base or s.get(x - 1, y) != base: n.g[y][x] = hi
    s.g = n.g

# ------------------------------------------------------------------ the icons (each returns a Spr drawn inside x,y in 1..14, outlined after)
def i_station():
    s = Spr(16, 16)
    ring(s, 8, 8, 3.4, 6.2, 'M'); edge_light(s, 'M', 'L', 'S')
    circle(s, 8, 8, 2.4, 'a'); s.put(7, 7, 'y'); s.put(8, 8, 'o')
    for (x, y, w, h) in ((7, 1, 2, 2), (7, 13, 2, 2), (1, 7, 2, 2), (13, 7, 2, 2)): s.rect(x, y, w, h, 'S'); s.put(x, y, 'L')
    for (x, y) in ((4, 4), (11, 4), (4, 11), (11, 11)): s.put(x, y, 'y')
    return s

def i_store():
    s = Spr(16, 16)
    s.rect(2, 7, 12, 7, 'S'); s.hline(2, 7, 12, 'M'); s.vline(2, 7, 7, 'M'); s.hline(2, 13, 12, 'W'); s.vline(13, 7, 7, 'W')
    s.rect(6, 9, 4, 5, 'D'); s.put(9, 11, 'y')                                              # door
    for (x, y) in ((3, 9), (11, 9)): s.rect(x, y, 2, 2, 'c')
    for k in range(6):                                                                       # the awning: amber and white stripes with a scalloped edge
        s.rect(1 + k * 2, 3, 2, 4, 'a' if k % 2 == 0 else 'H')
    for k in range(6): s.put(1 + k * 2, 6, 'u' if k % 2 == 0 else 'M'); s.put(2 + k * 2, 7, 'a' if False else s.get(2 + k * 2, 7))
    circle(s, 8, 2.0, 1.3, 'y')
    return s

def i_trader():
    s = Spr(16, 16)
    poly(s, [(2, 5), (9, 5), (9, 3), (14, 6.5), (9, 10), (9, 8), (2, 8)], 'g'); edge_light(s, 'g', 'H', 'u') if False else None
    poly(s, [(14, 9), (7, 9), (7, 7), (2, 10.5), (7, 14), (7, 12), (14, 12)], 'y')
    s.hline(2, 5, 7, 'H'); s.hline(7, 9, 7, 'H')
    return s

def i_distress():
    s = Spr(16, 16)
    for r, c in ((4.6, 'r'), (6.6, 'r')):
        for t in range(0, 360, 2):
            if abs(((t + 90) % 360) - 180) < 55 or abs(((t + 270) % 360) - 180) < 55 and False: pass
            a = math.radians(t)
            if abs(math.cos(a)) > 0.58:                                                       # arcs left and right of the beacon
                x, y = 8 + r * math.cos(a), 6.5 + r * math.sin(a) * 0.95
                s.put(int(x), int(y), c)
    s.rect(6, 10, 4, 4, 'W'); s.hline(6, 10, 4, 'S'); s.hline(6, 13, 4, 'E')
    circle(s, 8, 6.5, 2.9, 'a'); circle(s, 7.6, 6.1, 1.9, 'y'); s.put(7, 5, 'H')
    return s

def i_wreck():
    s = Spr(16, 16)
    poly(s, [(2, 13), (3, 6), (6, 2), (8, 1.5), (8, 6), (6, 8), (6, 10), (4, 13)], 'S'); edge_light(s, 'S', 'M', 'W')
    poly(s, [(9, 4), (10.5, 3), (13, 7), (14, 13), (11, 13), (10, 9), (9, 8)], 'W'); edge_light(s, 'W', 'S', 'E')
    s.put(4, 8, 'u'); s.put(5, 9, 'u'); s.put(12, 9, 'u'); s.put(11, 6, 'n')
    s.put(7, 11, 'o'); s.put(8, 12, 'y'); s.put(9, 12, 'o'); s.put(8, 13, 'r')            # an ember in the break
    s.put(9, 2, 'M'); s.put(1, 4, 'W')
    return s

def i_abandoned():
    s = Spr(16, 16)
    for y in range(16):
        for x in range(16):
            d = math.hypot(x + .5 - 8, y + .5 - 8); a = math.degrees(math.atan2(y + .5 - 8, x + .5 - 8)) % 360
            if 3.4 < d <= 6.2 and not (300 < a < 340): s.put(x, y, 'W')                       # the ring is broken open
    edge_light(s, 'W', 'S', 'E')
    circle(s, 8, 8, 2.4, 'E'); s.put(7, 7, 'W'); s.put(9, 9, 'D')
    for (x, y, w, h) in ((7, 1, 2, 2), (1, 7, 2, 2), (13, 7, 2, 2)): s.rect(x, y, w, h, 'E'); s.put(x, y, 'S')
    s.rect(7, 13, 2, 1, 'E'); s.put(7, 14, 'E')
    for (x, y) in ((4, 4), (11, 11)): s.put(x, y, 'K')
    s.put(11, 4, 'a'); s.put(4, 11, 'u'); s.put(12, 3, 'n')
    s.put(12, 5, 'u'); s.put(13, 4, 'u')
    return s

def i_mining():
    s = Spr(16, 16)
    lit_disc(s, 6.5, 8.5, 5.6, ('Q', 'q', 'n'))
    lit_disc(s, 12, 4, 2.6, ('Q', 'q', 'n')); lit_disc(s, 12.5, 12, 2.3, ('q', 'n', 'n'))
    for (x, y, c) in ((4, 7, 'Y'), (5, 8, 'T'), (7, 6, 'Y'), (8, 10, 'T'), (6, 11, 'y'), (3, 10, 'T'), (12, 4, 'Y'), (9, 8, 'y')): s.put(x, y, c)
    s.put(5, 5, 'M'); s.put(4, 6, 'M')
    return s

def i_unknown():
    s = Spr(16, 16)
    lit_disc(s, 8, 8, 6.4, ('V', 'Z', 'Z')); ring(s, 8, 8, 5.4, 6.4, 'V')
    q = art("""
.HHH.
HH.HH
...HH
..HH.
.HH..
.HH..
.....
.HH..
.HH..
""")
    s.stamp(5, 3, q)
    s.put(5, 4, 'X'); s.put(9, 4, 'X')
    return s

def i_pirate():
    s = Spr(16, 16)
    poly(s, [(8, 1), (14, 4), (14, 11), (8, 15), (2, 11), (2, 4)], 'r'); edge_light(s, 'r', 'o', 'e')
    sk = art("""
.HHHHH.
HHHHHHH
HKKHKKH
HKKHKKH
HHHKHHH
.HHHHH.
.HKHKH.
.HHHHH.
""")
    s.stamp(4, 3, sk)
    s.put(4, 10, 'L'); s.put(11, 10, 'L')
    return s

def i_concord():
    s = Spr(16, 16)
    poly(s, [(2, 2), (14, 2), (14, 9), (8, 15), (2, 9)], 'b'); edge_light(s, 'b', 'H', 'J')
    s.hline(3, 7, 10, 'H'); s.hline(3, 8, 10, 'L')                                          # the barrier bar of the checkpoint
    for k in range(5): s.put(3 + k * 2, 7, 'r'); s.put(4 + k * 2, 8, 'r') if False else None
    s.put(8, 4, 'H'); s.put(7, 5, 'H'); s.put(9, 5, 'H')
    s.vline(8, 10, 3, 'k'); s.put(8, 13, 'k')
    return s

def i_anomaly():
    s = Spr(16, 16)
    for arm in range(2):
        for t in range(0, 300):
            th = math.radians(t * 1.25 + arm * 180); r = 1.2 + t / 300.0 * 5.2
            x, y = 7.5 + r * math.cos(th), 7.5 + r * math.sin(th)
            s.put(int(x), int(y), 'c' if arm == 0 else 'm')
            if t > 120: s.put(int(x + 0.6), int(y + 0.4), 'C' if arm == 0 else 'P')
    circle(s, 8, 8, 1.8, 'H')
    for (x, y) in ((1, 3), (14, 12), (2, 13)): s.put(x, y, 'c')
    return s

def i_quest():
    s = Spr(16, 16)
    poly(s, [(8, 0.5), (15.5, 8), (8, 15.5), (0.5, 8)], 'y'); edge_light(s, 'y', 'H', 'a')
    s.rect(7, 3, 2, 6, 'K'); s.rect(7, 10, 2, 2, 'K')                                     # the "!"
    return s

def i_contact():
    s = Spr(16, 16)
    ring(s, 8, 8, 3.0, 4.6, 'M'); edge_light(s, 'M', 'L', 'S')
    s.rect(7, 7, 2, 2, 'H')
    for (x, y, w, h) in ((7, 1, 2, 2), (7, 13, 2, 2), (1, 7, 2, 2), (13, 7, 2, 2)): s.rect(x, y, w, h, 'S'); s.put(x, y, 'M')
    return s

def i_course():
    s = Spr(16, 16)
    ring(s, 8, 8, 4.0, 5.4, 'c')
    for (x, y, w, h) in ((7, 1, 2, 4), (7, 11, 2, 4), (1, 7, 4, 2), (11, 7, 4, 2)): s.rect(x, y, w, h, 'H')
    poly(s, [(8, 5.5), (10.5, 8), (8, 10.5), (5.5, 8)], 'y'); s.put(7, 7, 'H')
    return s

# id, drawing, glow source letters, glow colour override
ICONS = [('station', i_station, 'ya', None), ('store', i_store, 'ya', None), ('trader', i_trader, 'gy', None), ('distress', i_distress, 'ray', None),
         ('wreck', i_wreck, 'oyr', None), ('abandoned_station', i_abandoned, 'a', None), ('mining_field', i_mining, 'YTy', None), ('unknown', i_unknown, 'XHV', None),
         ('pirate_nest', i_pirate, 'ro', None), ('concord_checkpoint', i_concord, 'bH', None), ('anomaly', i_anomaly, 'cmH', None), ('quest', i_quest, 'yH', None),
         ('contact', i_contact, 'H', None), ('course', i_course, 'cHy', None)]

def frames():
    out = []
    for (name, fn, src, col) in ICONS:
        s = fn()
        outline_all(s)
        assert not any(s.g[y][x] not in '.K' for y in range(16) for x in (0, 15)) and not any(s.g[y][x] not in '.K' for x in range(16) for y in (0, 15)), name
        out.append(s)
    return out

def export(art_dir=None):
    art_dir = art_dir or ART
    fr = frames()
    save(sheet(fr, len(fr), 16, 16), art_dir + '/ui/poi_icons.png')
    gl = [halo_px(f, 24, 24, 4, 4, ((1.4, 105), (2.8, 55), (4.0, 24)), ICONS[i][2], col=ICONS[i][3]) for i, f in enumerate(fr)]
    save_strip_rgba(gl, art_dir + '/ui/poi_icons_glow.png')
    names = [n for (n, *_ ) in ICONS]
    write_json(art_dir + '/ui/poi_icons.json', {
        'frame': [16, 16], 'cells': [1, 1], 'anims': {n: [i, 1, 0] for i, n in enumerate(names)}, 'anchors': {'center': [8, 8]},
        'glow': {'image': 'poi_icons_glow.png', 'frame': [24, 24], 'offset': [-4, -4], 'anims': {n: [i, 1, 0] for i, n in enumerate(names)}, 'blend': 'add (preferred) or alpha-over'},
        'notes': 'HUD icons for sector points of interest, one 16x16 frame per type (anim name = POI type): station, store, trader, distress, wreck, abandoned_station, mining_field, unknown, pirate_nest, '
                 'concord_checkpoint, anomaly, quest, plus `contact` (an unidentified radar contact) and `course` (the set-course marker). Family colours: distress red + amber, quest gold, Lumen cyan (anomaly, course), '
                 'Concord blue, pirate red. Draw them at 2x or more on the compass ring and edge markers; the glow layer is additive and may be pulsed (distress, quest, course) or left out.'})
    return fr

if __name__ == '__main__':
    export()
