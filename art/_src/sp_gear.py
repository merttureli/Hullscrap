"""Gear overlays on the human rig (art/gear/). Same 33x33 frame as the crew layers, drawn over the torso/head:
  body  : after the torso, before the arms (an exosuit also replaces the legs and the arms)
  head  : after the head layer
Outfit symbols A/B/C = tinted (white in the _color mask); everything else is drawn as is."""
from sp_common import *
import sp_basalt
from sp_items import tube

def outline_outer(s):
    """1px outline on the OUTSIDE of the silhouette only (a see-through bubble keeps its inside clear)."""
    w, h = s.w, s.h
    out = [[False] * w for _ in range(h)]
    stack = [(x, y) for x in range(w) for y in (0, h - 1)] + [(x, y) for y in range(h) for x in (0, w - 1)]
    while stack:
        x, y = stack.pop()
        if not (0 <= x < w and 0 <= y < h) or out[y][x] or s.g[y][x] != '.': continue
        out[y][x] = True
        stack += [(x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)]
    n = s.copy()
    for y in range(h):
        for x in range(w):
            if s.g[y][x] == '.' and out[y][x]:
                if any(s.get(x + dx, y + dy) != '.' for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))): n.g[y][x] = 'K'
    return n

def disc_cells(cx, cy, r0, r1):
    return [(x, y) for y in range(N) for x in range(N)
            if r0 <= ((x - cx) ** 2 + (y - cy) ** 2) ** 0.5 <= r1]

# ================================================================== EVA suit: puffy shoulders, twin air tanks, a bubble helmet
def eva_body():
    s = Spr(N, N)
    # twin air tanks on the back
    for x0 in (10, 17):
        tube(s, x0, 21, 5, 9, 'L', 'M', 'S')
        s.hline(x0 + 1, 20, 3, 'D'); s.put(x0 + 2, 20, 'g')
        s.hline(x0, 25, 5, 'o')
        s.put(x0 + 4, 21, 'W'); s.hline(x0 + 1, 29, 3, 'E')
    s.vline(15, 22, 3, 'S'); s.vline(16, 22, 3, 'M'); s.put(15, 23, 'g'); s.put(16, 23, 'a')     # manifold with a green gauge
    s.vline(15, 26, 3, 'W'); s.vline(16, 26, 3, 'W')
    # puffy shoulder rings (suit fabric, tinted) with steel seals
    for sx in (5, 22):
        for j, (a, b) in enumerate([(1, 4), (0, 5), (0, 5), (0, 5), (0, 5), (0, 5), (0, 5), (1, 4)]):
            s.hline(sx + a, 11 + j, b - a + 1, 'B')
        s.hline(sx + 1, 11, 4, 'A'); s.vline(sx, 12, 6, 'A'); s.vline(sx + 5, 12, 6, 'C'); s.hline(sx + 1, 18, 4, 'C')
        s.hline(sx, 14, 6, 'M'); s.hline(sx, 15, 6, 'S')                                              # steel arm-seal ring
    # chest harness hose + neck seal
    s.vline(12, 12, 8, 'D'); s.vline(20, 12, 8, 'D')
    return s
def eva_head():
    s = Spr(N, N)
    for (x, y) in disc_cells(16, 14, 5.5, 6.9):
        ang_light = (x - 16) + (y - 14) < -1
        ang_dark = (x - 16) + (y - 14) > 3
        s.put(x, y, 'H' if (x - 16) + (y - 14) < -6 else 'L' if ang_light else 'W' if ang_dark else 'M')
    for (x, y) in ((11, 11), (12, 10), (11, 12), (13, 9)): s.put(x, y, 'H')                          # glints inside the bubble
    s.hline(12, 20, 9, 'M'); s.hline(12, 21, 9, 'S'); s.put(16, 21, 'g'); s.put(13, 20, 'L'); s.put(19, 21, 'W')   # neck seal ring + LED
    return s

# ================================================================== combat vest: shoulder plates, back plate, pouch belt
def vest_body():
    s = Spr(N, N)
    # back plate (visible below the head) + webbing
    bev(s, 11, 15, 11, 7, 'M', 'S', 'W', cham=False)
    s.hline(13, 18, 7, 'E'); s.put(16, 17, 'a'); s.hline(14, 16, 5, 'L')
    for (x, y) in ((12, 16), (20, 16), (12, 20), (20, 20)): s.put(x, y, 'L')            # rivets
    # shoulder plates
    for sx in (4, 22):
        bev(s, sx, 10, 7, 8, 'M', 'S', 'W', cham=True)
        s.hline(sx + 1, 13, 5, 'E'); s.hline(sx + 1, 14, 5, 'W')                        # plate seam
        s.put(sx + 2, 11, 'L'); s.put(sx + 4, 16, 'L')
    s.put(6, 11, 'H'); s.put(5, 11, 'H')                                                  # edge glint
    # webbing straps (outfit-coloured) from the plates to the back plate
    for x in (11, 21): s.vline(x, 12, 4, 'B'); s.vline(x - 1 if x < 16 else x + 1, 12, 4, 'C')
    # belt with pouches and an orange tag
    s.hline(8, 22, 17, 'q'); s.hline(8, 21, 17, 'Q')
    for x in (8, 11, 20, 23): s.stamp(x, 21, art("""
QQQ
qaq
qqq
nnn
"""))
    s.put(16, 22, 'o'); s.put(15, 22, 'a'); s.put(17, 22, 'a')
    return s
def vest_head(): return Spr(N, N)

# ================================================================== exosuit: armoured shell, power pack with a glowing core, closed helm
def exo_body():
    s = Spr(N, N)
    # back power unit with glowing coils and vents
    bev(s, 10, 19, 13, 11, 'M', 'S', 'W', cham=True)
    for y in (21, 24, 27): s.hline(11, y, 11, 'D')
    for y in (21, 24, 27):
        for x in (13, 15, 17, 19): s.put(x, y, 'o')
    s.rect(15, 22, 3, 2, 'E'); s.put(16, 22, 'y'); s.put(15, 23, 'o'); s.put(17, 23, 'o')
    s.hline(11, 29, 11, 'E'); s.put(12, 29, 'D'); s.put(20, 29, 'D')
    # spine plates between the pauldrons
    bev(s, 10, 9, 13, 10, 'M', 'S', 'W', cham=True)
    for y in (12, 15): s.hline(11, y, 11, 'E')
    # pauldrons: stacked armour plates in outfit colour with steel trim
    for (sx, flip) in ((2, 1), (22, 0)):
        for (y, w, h) in ((7, 9, 5), (12, 9, 4), (16, 8, 4)):
            x0 = sx if (w == 9 or not flip) else sx + 1
            bev(s, x0, y, w, h, 'A', 'B', 'C', cham=True)
        for y in (11, 15): s.hline(sx + 1, y, 7, 'E')
        s.put(sx + 2, 9, 'H'); s.put(sx + 1 + (1 if flip else 5), 18, 'a')
        s.put(sx + (3 if flip else 5), 13, 'o')                                             # hazard stripe light
    return s
def exo_head():
    s = Spr(N, N)
    bev(s, 11, 8, 11, 12, 'A', 'B', 'C', cham=True)
    s.hline(12, 11, 9, 'D'); s.hline(12, 12, 9, 'D')
    for x in range(13, 20): s.put(x, 11, 'c'); s.put(x, 12, 'b')                           # visor slit
    s.put(12, 11, 'K'); s.put(20, 11, 'K')
    s.vline(16, 8, 3, 'M'); s.vline(16, 13, 5, 'M'); s.vline(15, 13, 5, 'L'); s.vline(17, 13, 5, 'W')   # crest ridge
    s.hline(13, 18, 7, 'S'); s.put(21, 14, 'a'); s.put(11, 14, 'a')
    s.put(22, 8, 'S'); s.put(22, 7, 'M'); s.put(22, 6, 'r')                                 # antenna
    return s
def _steelify(sp_fn):
    m = {'S': 'M', 'W': 'S', 'E': 'W', 'D': 'E', 'c': 'S', 'b': 'W', 'H': 'L'}
    return lambda *a: sp_fn(*a).sub(m)
def exo_legs_frame(*a):
    s = _steelify(sp_basalt.leg_frame)(*a)
    return s
def exo_legs(): return [outlined(exo_legs_frame(*w)) for w in sp_basalt.WALK] + [outlined(exo_legs_frame(1, -1))]
def exo_arms(pose):
    return outlined(_steelify(sp_basalt.arms_spr)(pose))

# ================================================================== salamander suit: reflective foil mantle and a hood with an ember visor
def sal_body():
    s = Spr(N, N)
    spans = [(6, 26), (5, 27), (5, 27), (5, 27), (5, 27), (5, 27), (6, 26), (6, 26), (7, 25), (7, 25), (8, 24), (8, 24), (9, 23), (10, 22), (11, 21), (12, 20)]
    for j, (a, b) in enumerate(spans): s.hline(a, 10 + j, b - a + 1, 'M')
    s = shade_gen(s, 'M', 'L', 'S')
    for y in range(11, 25):                                                                  # foil pleats
        for x in (9, 13, 19, 23):
            if s.g[y][x] != '.' and (x + y) % 3 != 0: s.put(x, y, 'S' if x < 16 else 'W')
    for x in range(9, 24, 2): s.put(x, 14, 'L')
    for (x, y) in ((7, 12), (25, 12), (6, 15), (26, 15)): s.put(x, y, 'H')
    # gold trim along the lower edge, heat-sink studs
    for j, (a, b) in enumerate(spans):
        if j >= 11: s.put(a, 10 + j, 'y'); s.put(b, 10 + j, 'a')
    s.hline(12, 25, 9, 'y')
    for (x, y) in ((11, 18), (21, 18), (16, 21)): s.put(x, y, 'o')
    return s
def sal_head():
    s = Spr(N, N)
    spans = [(13, 19), (11, 21), (10, 22), (10, 22), (10, 22), (10, 22), (10, 22), (10, 22), (11, 21), (11, 21), (12, 20), (13, 19), (14, 18), (15, 17), (15, 17), (16, 16)]
    for j, (a, b) in enumerate(spans): s.hline(a, 7 + j, b - a + 1, 'M')
    s = shade_gen(s, 'M', 'L', 'S')
    s.hline(12, 9, 9, 'y')                                                                    # gold face-opening rim
    s.put(11, 10, 'y'); s.put(21, 10, 'y')
    for x in range(13, 20): s.put(x, 10, 'D')
    for x in range(14, 19): s.put(x, 10, 'o')                                                 # ember visor slit
    s.put(16, 10, 'y')
    for y in range(11, 21): s.put(16, y, 'S')                                                 # hood seam
    for (x, y) in ((12, 12), (13, 11), (12, 13)): s.put(x, y, 'H')
    return s


# ================================================================== heat suit: reflective silver mantle, tinted bands, a gold-visored hood
def heat_body():
    s = Spr(N, N)
    # back cooling pack with fins
    bev(s, 11, 19, 10, 9, 'M', 'S', 'W', cham=True)
    for y in (21, 23, 25): s.hline(12, y, 8, 'W')
    s.put(16, 27, 'g'); s.hline(12, 28, 8, 'D')
    # silver shoulder domes with tinted bands
    for sx in (4, 22):
        for j, (a, b) in enumerate([(1, 5), (0, 6), (0, 6), (0, 6), (0, 6), (0, 6), (0, 6), (1, 5)]):
            s.hline(sx + a, 10 + j, b - a + 1, 'M')
        s.hline(sx, 13, 7, 'A'); s.hline(sx, 14, 7, 'B'); s.hline(sx, 15, 7, 'C')
        s.put(sx + 1, 11, 'H'); s.put(sx + 2, 11, 'H')
    # reflective yoke across the shoulders, tinted collar band
    for j, (a, b) in enumerate([(9, 23), (9, 23), (10, 22), (11, 21)]): s.hline(a, 12 + j, b - a + 1, 'M')
    s.hline(11, 15, 11, 'B'); s.hline(11, 16, 11, 'C')
    s = shade_gen(s, 'M', 'L', 'S')
    for (x, y) in ((8, 12), (24, 12), (6, 11), (26, 11)): s.put(x, y, 'H')
    return s
def heat_head():
    s = Spr(N, N)
    spans = [(13, 19), (11, 21), (10, 22), (10, 22), (10, 22), (10, 22), (10, 22), (10, 22), (11, 21), (11, 21), (12, 20), (13, 19), (14, 18)]
    for j, (a, b) in enumerate(spans): s.hline(a, 7 + j, b - a + 1, 'M')
    s = shade_gen(s, 'M', 'L', 'S')
    for y in range(9, 14):                                                                    # gold-tinted visor
        for x in range(12, 21):
            if abs(x - 16) + (y - 9) * 0.6 <= 5.2: s.put(x, y, 'y' if (x + y) % 5 else 'a')
    s.hline(13, 9, 7, 'o'); s.put(14, 10, 'H'); s.put(13, 10, 'H')
    s.hline(11, 14, 11, 'B'); s.hline(12, 15, 9, 'C')                                        # tinted chin band
    s.put(16, 18, 'S'); s.put(16, 17, 'S')
    return s

GEAR = ['eva_suit', 'combat_vest', 'exosuit', 'salamander_suit', 'heat_suit']
def parts(gid):
    """-> dict(body=Spr|None, head=Spr|None, legs=[7 Spr]|None, arms={pose: Spr}|None, head_outer=bool), interior (no outline)."""
    if gid == 'eva_suit':        return dict(body=eva_body(), head=eva_head(), head_outer=True)
    if gid == 'combat_vest':     return dict(body=vest_body(), head=None)
    if gid == 'exosuit':         return dict(body=exo_body(), head=exo_head(), legs=True, arms=True)
    if gid == 'salamander_suit': return dict(body=sal_body(), head=sal_head())
    if gid == 'heat_suit':       return dict(body=heat_body(), head=heat_head())
def glow_for(gid):
    """-> (body_glow Rgba|None, head_glow Rgba|None)"""
    b = new_glow(); h = new_glow()
    if gid == 'eva_suit':
        glow_px(b, spr_pts(eva_body(), 'g'), (107, 211, 74), 0.7, 2.6)
        glow_px(h, spr_pts(eva_head(), 'g'), (107, 211, 74), 0.7, 2.6)
    elif gid == 'exosuit':
        glow_px(b, spr_pts(exo_body(), 'oy'), (255, 138, 30), 0.6, 2.8)
        glow_px(h, spr_pts(exo_head(), 'c'), (60, 242, 255), 0.6, 2.6)
    elif gid == 'salamander_suit':
        glow_px(b, spr_pts(sal_body(), 'o'), (255, 138, 30), 0.5, 2.4)
        glow_px(h, spr_pts(sal_head(), 'oy'), (255, 138, 30), 0.7, 2.8)
    elif gid == 'heat_suit':
        glow_px(b, spr_pts(heat_body(), 'g'), (107, 211, 74), 0.5, 2.2)
        glow_px(h, spr_pts(heat_head(), 'y'), (255, 200, 80), 0.4, 2.4)
    elif gid == 'combat_vest':
        glow_px(b, spr_pts(vest_body(), 'o'), (255, 138, 30), 0.35, 2.0)
    return b, h
def gear_kit(gid, outlined_layers=False):
    """compose-ready dict: body/head/legs/arms entries (interior, the compositor outlines after rotation)."""
    p = parts(gid)
    cv2.OUTLINE = False
    g = dict(body=p['body'], head=p.get('head'), head_outer=p.get('head_outer', False))
    if p.get('legs'): g['legs'] = [exo_legs_frame(*w) for w in sp_basalt.WALK] + [exo_legs_frame(1, -1)]
    if p.get('arms'): g['arms'] = {pose: _steelify(sp_basalt.arms_spr)(pose) for pose in POSES}
    cv2.OUTLINE = True
    bg, hg = glow_for(gid)
    g['body_glow'] = bg; g['head_glow'] = hg
    return g
