"""The breech modules (inside halves) of the G2 guns (docs/GUNS.md 3 and 7), one family of three sizes: 2x2, 4x2 and 2x4 cells.

A breech is the same machine in every gun: housing, the feed column up through the collar, the power coupling, a charge strip and
`windows` (the core). What changes is the core, by FAMILY (the family-coloured light is in its pixels), and the add-ons, by VERSION:
  laser   cell bank: vertical capacitor cells with a family band        pulse   ammo drum and a belt of rounds
  ion     coil windings between two posts, an arc across               flak    upright shells with brass cases
  missile a magazine of warheads (white nose, red band, fins)          beam    a focus crystal with conduits
  slug    a rack of heavy horizontal shells                            pd      a radar scope with a sweep
  versions: chain = a feed belt along the top; charge = a capacitor tower of 3 rings (lit by the charge frames); lance = coil rings between two tall cores;
  mk = copper coolant lines; heavy = armour corner plates and a thick band; burst / strip = one core per barrel (3).
Lines as everywhere: scrap rusts and gets hazard tape, neon gets cyan edges (the flange does that on its own). Race colours come from the Look (the Baron gold).
Frames (like the older inside halves): on (2), off, charge (6: frame i lights i of the 5 strip cells), fire (2: flash, then dark), damaged (2), disabled; glow: on, charge, damaged."""
import json, os
import gun_mod as gm
import gun_samples as gs
from gun_mod import Ctx, St, FLANGE, plate, tube, band, fam_ring, lamp_row, grille, bolt_row, stencil, round_disc, channel, rust_over, hurt_base, wreck_base, scrap_dress
from mach import recess, bev
from px import *
from wbase import hazard, weld

ANIMS = [('on', 'on', 2, 3), ('off', 'off', 1, 0), ('charge', 'charge', 6, 0), ('fire', 'fire', 2, 12), ('damaged', 'damaged', 2, 4), ('disabled', 'disabled', 1, 0)]
GANIMS = ('on', 'charge', 'damaged')

# ------------------------------------------------------------------ the cores (drawn inside a recess; (x, y, w, h) is the inner box)
def core_laser(c, x, y, w, h, hot):
    s = c.s
    for k in range(w // 4):
        cx = x + k * 4 + (w % 4) // 2
        tube(s, cx, y, 3, h, 'LSW')
        m = y + h // 2
        s.hline(cx, m - 1, 3, 'E'); s.hline(cx, m, 3, '4' if hot else '2'); s.hline(cx, m + 1, 3, '1')
        c.lightglow(cx + 1, m, 2.5, 0.3)

def core_pulse(c, x, y, w, h, hot):
    s = c.s
    d = min(h, 11); r = d / 2.0
    cx, cy = x + r, y + h / 2.0
    round_disc(s, cx, cy, r, ('L', 'M', 'S', 'W', 'E'))
    ix, iy = int(cx), int(cy)
    s.rect(ix - 1, iy - 1, 2, 2, '2'); s.put(ix - 1, iy - 1, '4' if hot else '3')
    for (dx, dy) in ((0, -3), (0, 3), (-3, 0), (3, 0)): s.put(ix + dx - (1 if dx > 0 else 0), iy + dy - (1 if dy > 0 else 0), 'D')
    c.lightglow(cx, cy, 3.5, 0.35)
    bx = x + d + 1; by = y + h // 2 - 2
    while bx + 3 <= x + w:                                                     # the belt of rounds, links between
        s.rect(bx, by, 3, 5, '2'); s.hline(bx, by, 3, '3'); s.put(bx, by, '4'); s.hline(bx, by + 4, 3, 'E'); s.put(bx + 2, by + 1, '1')
        s.put(bx + 3, by + 2, 'S')
        bx += 4

def core_ion(c, x, y, w, h, hot):
    s = c.s
    for yy in range(y + 1, y + h - 2, 3):
        s.hline(x + 2, yy, w - 4, '3'); s.hline(x + 2, yy + 1, w - 4, '2'); s.hline(x + 2, yy + 2, w - 4, 'E')
    for px_ in (x, x + w - 1):                                                 # the posts
        s.vline(px_, y, h, 'L'); s.put(px_, y, '3')
    s.vline(x + 1, y, h, 'W'); s.vline(x + w - 2, y, h, 'W')
    ay = y + 2 + (c.st.i % 2) * 3
    s.hline(x + 2, ay, w - 4, '4'); c.lightglow(x + w / 2.0, y + h / 2.0, 5, 0.4, sx=1.5)

def core_flak(c, x, y, w, h, hot):
    s = c.s
    for k in range(w // 4):
        cx = x + k * 4 + (w % 4) // 2
        s.put(cx + 1, y, '4' if hot else '3')                                  # the nose
        s.rect(cx, y + 1, 3, h - 6, '2'); s.vline(cx, y + 1, h - 6, '3'); s.vline(cx + 2, y + 1, h - 6, '1')
        s.hline(cx, y + h - 5, 3, 'E')
        tube(s, cx, y + h - 4, 3, 4, 'MSW')                                    # the brass-grey case
        c.lightglow(cx + 1, y + 3, 2.2, 0.25)

def core_missile(c, x, y, w, h, hot):
    s = c.s
    for k in range(w // 5):
        cx = x + k * 5 + (w % 5) // 2
        s.hline(cx + 1, y, 2, '4' if hot else '3'); s.hline(cx, y + 1, 4, '3')
        s.rect(cx, y + 2, 4, h - 6, '2'); s.vline(cx, y + 2, h - 6, '3'); s.vline(cx + 3, y + 2, h - 6, '1')
        s.hline(cx, y + 5, 4, '1')                                             # the red band
        s.hline(cx - 0, y + h - 4, 4, 'S'); s.hline(cx, y + h - 3, 4, 'W'); s.put(cx - 1, y + h - 3, 'S'); s.put(cx + 4, y + h - 3, 'S')
        c.lightglow(cx + 2, y + 1, 2.2, 0.25)

def core_beam(c, x, y, w, h, hot):
    s = c.s
    cx, cy = x + w // 2, y + h // 2
    half = min(w // 2, h // 2) - 1
    for yy in range(-half, half + 1):
        k = half - abs(yy)
        for xx in range(-k, k + 1):
            ch = '3' if xx < 0 and yy <= 0 else ('2' if xx >= 0 and yy <= 0 else ('2' if xx < 0 else '1'))
            s.put(cx + xx, cy + yy, ch)
        s.put(cx - k, cy + yy, '1'); s.put(cx + k, cy + yy, '1')
    s.put(cx - 1, cy - 1, '4'); s.put(cx, cy - 1, '4' if hot else '3')
    for xx in list(range(x, cx - half)) + list(range(cx + half + 1, x + w)):  # the conduits to the edges
        s.put(xx, cy, '1'); s.put(xx, cy - 1, 'E')
        if (xx + c.st.i) % 3 == 0: s.put(xx, cy, '3')
    c.lightglow(cx, cy, 6, 0.5, sx=1.3)

def core_slug(c, x, y, w, h, hot):
    s = c.s
    n = max(1, h // 5)
    gap = (h - n * 4) // (n + 1) if n > 1 else (h - 4) // 2
    for k in range(n):
        yy = y + gap + k * (4 + gap)
        s.rect(x + 1, yy, w - 4, 4, 'S'); s.hline(x + 1, yy, w - 4, 'L'); s.hline(x + 1, yy + 3, w - 4, 'W')
        s.vline(x + w - 5, yy, 4, '2'); s.vline(x + w - 6, yy, 4, 'E'); s.vline(x + 4, yy, 4, '2'); s.vline(x + 5, yy, 4, 'E')   # the yellow bands
        s.rect(x + w - 3, yy + 1, 2, 2, '3'); s.put(x + w - 3, yy + 1, '4' if hot else '3'); s.put(x + w - 2, yy, '1'); s.put(x + w - 2, yy + 3, '1')   # the nose
        s.vline(x, yy + 1, 2, 'M')
        c.lightglow(x + w - 3, yy + 2, 2.2, 0.25)

def core_pd(c, x, y, w, h, hot):
    s = c.s
    r = min(w, h) / 2.0 - 0.5
    cx, cy = x + w / 2.0, y + h / 2.0
    for yy in range(h):
        for xx in range(w):
            dx, dy = x + xx + .5 - cx, y + yy + .5 - cy
            d2 = dx * dx + dy * dy
            if d2 <= r * r: s.put(x + xx, y + yy, 'K' if d2 > (r - 1.3) ** 2 and False else 'D')
            if (r - 1.2) ** 2 < d2 <= r * r: s.put(x + xx, y + yy, 'W')
    ix, iy = int(cx), int(cy)
    sweep = [(1, -1), (1, 0), (1, 1), (0, 1)][c.st.i % 4] if c.st.state in ('on', 'idle') else (1, -1)
    for k in range(1, int(r)): s.put(ix + sweep[0] * k - (1 if sweep[0] < 0 else 0), iy + sweep[1] * k, '2' if k < r - 2 else '3')
    s.put(ix, iy, '3')
    s.put(ix - 2, iy + 2, '4' if hot else '3'); s.put(ix + 2, iy - 1, '2')
    c.lightglow(cx, cy, 5, 0.4)

CORES = {'laser': core_laser, 'pulse': core_pulse, 'ion': core_ion, 'flak': core_flak, 'missile': core_missile, 'beam': core_beam, 'slug': core_slug, 'pd': core_pd}

# ------------------------------------------------------------------ the module
def _windows(W, Hb, y0, ver):
    if W == 32 and Hb <= 32: return [(11, y0 + 7, 17, Hb - 17)]
    if W == 32: return [(11, y0 + 7, 17, 20), (11, y0 + 7 + 33, 17, 20)]
    n = 3 if ver in ('burst', 'strip', 'heavy_burst') else 2
    gap = 2; tot = 38
    wd = (tot - gap * (n - 1)) // n
    return [(11 + k * (wd + gap), y0 + 7, wd, Hb - 17) for k in range(n)]

def breech_fam(c, cells, fam, ver=None, tier=0):
    s = c.s; W = c.w; y0 = FLANGE; Hb = c.h - FLANGE; st = c.st
    hot = st.state == 'fire' and st.i == 0
    plate(s, 2, y0 + 1, W - 4, Hb - 2, True, 'M', 'S', 'W')
    cols = [W // 4, W // 2, 3 * W // 4] if (W > 40 and ver in ('burst', 'strip', 'heavy_burst')) else [W // 2]
    for x in cols:
        tube(s, x - (6 if ver in ('heavy', 'heavy_burst') else 4), y0 + 1, 12 if ver in ('heavy', 'heavy_burst') else 8, 5, 'LMSSSSWE')
    s.rect(0, y0 + 10, 4, 4, 'q'); s.hline(0, y0 + 10, 4, 'Q'); s.hline(0, y0 + 13, 4, 'n')      # the cable stub
    bev(s, 3, y0 + 7, 6, 10, 'M', 'S', 'W', cham=False); s.put(5, y0 + 9, '5')
    wins = _windows(W, Hb, y0, ver)
    tower = ver == 'charge'
    for k, (x, y, w, h) in enumerate(wins):
        if tower: w -= 7
        recess(s, x, y, w, h, 'D', 'K')
        CORES[fam](c, x + 1, y + 1, w - 2, h - 2, hot)
    x, y, w, h = wins[0]
    if tower:                                                                  # the capacitor tower: 3 rings, lit by the charge frames
        lit = {'charge': (st.i * 3 + 2) // 5, 'on': 3, 'fire': 0 if st.i else 3}.get(st.state, 3 if st.powered else 0) if st.powered else 0
        tx = x + w + 2
        tube(s, tx + 1, y, 3, h, 'LSW')
        for k in range(3):
            ry = y + h - 5 - k * 5
            plate(s, tx - 1, ry, 7, 4, True, 'M', 'S', 'W')
            if st.powered and k < lit:
                s.hline(tx, ry + 1, 5, '3'); s.hline(tx, ry + 2, 5, '2'); c.lightglow(tx + 2, ry + 1.5, 4, 0.5, sx=1.4)
            else: s.hline(tx, ry + 1, 5, 'E')
    if ver == 'chain':                                                         # the feed belt along the top
        for k in range(11, W // 2 - 5, 3):
            s.rect(k, y0 + 2, 2, 3, 'a' if (k // 3) % 2 == 0 else 'M'); s.put(k, y0 + 2, 'L')
            if (k // 3 + st.i) % 4 == 0: s.put(k + 1, y0 + 3, '3')
    if ver == 'mk':                                                            # copper coolant lines from the core to the column
        for k in range(8):
            s.put(W // 2 - 6 - k // 2, y0 + 6 - k // 3, 'Q'); s.put(W // 2 - 6 - k // 2, y0 + 7 - k // 3, 'q')
    if ver in ('heavy', 'heavy_burst'):                                        # armour: corner plates and a thick band
        for (px_, py_) in ((3, y0 + 2), (W - 7, y0 + 2), (3, y0 + Hb - 7), (W - 7, y0 + Hb - 7)): bev(s, px_, py_, 4, 4, 'L', 'M', 'S', cham=False)
        band(s, 2, y0 + Hb - 11, W - 4, 3)
    if ver == 'lance':                                                         # coil rings between the two tall cores, family-lit
        ry = wins[0][1] + wins[0][3] + 1
        plate(s, 4, ry, W - 8, 5, True, 'M', 'S', 'W')
        if st.powered: s.hline(6, ry + 2, W - 12, '2'); s.hline(6, ry + 1, W - 12, '3'); c.lightglow(W // 2, ry + 2, 7, 0.4, sx=2.0)
        else: s.hline(6, ry + 2, W - 12, 'E')
        plate(s, 4, y0 + 1 + 40, 4, 3, cham=False)
    if W > 40:                                                                 # the wide breech: the repair hatch at the right
        hx = W - 14
        bev(s, hx, y0 + 7, 10, Hb - 17, 'L', 'M', 'S', cham=False)
        s.rect(hx + 2, y0 + 7 + (Hb - 17) // 2 - 1, 6, 2, 'W'); s.put(hx + 7, y0 + 7 + (Hb - 17) // 2 - 1, 'a')
        bolt_row(s, [(hx + 1, y0 + 8), (hx + 8, y0 + 8), (hx + 1, y0 + Hb - 12), (hx + 8, y0 + Hb - 12)], 'W')
    n = 5
    pitch = 5 if W <= 32 else 10; cw = 4 if W <= 32 else 8
    sx = (W - (n * pitch - (pitch - cw))) // 2 + 1
    sy = y0 + Hb - 7
    recess(s, sx - 2, sy, n * pitch - (pitch - cw) + 3, 4, 'D', 'K')
    for k in range(n):
        if st.state == 'charge': lit = k < st.i
        elif st.state == 'fire': lit = st.i == 0
        elif st.state == 'damaged': lit = k < n - 1
        else: lit = st.powered
        col = 'E'
        if st.powered and lit: col = 'H' if st.state == 'fire' else 'g'
        s.hline(sx + k * pitch, sy + 1, cw, col); s.hline(sx + k * pitch, sy + 2, cw, col if col != 'H' else 'L')
        if col == 'g': s.put(sx + k * pitch, sy + 1, 'H'); c.lightglow(sx + k * pitch + cw / 2.0, sy + 1.5, 4, 0.4, (107, 211, 74), 1.5)
    if st.powered and st.state == 'on' and st.i == 1: s.put(5, y0 + 9, 'H')
    # the line's language
    if c.line == 'neon':
        s.hline(4, y0 + 2, W - 8, 'c')
        for (x, y, w, h) in wins: s.hline(x, y - 1, w, 'c')
    elif c.line == 'scrap':
        (rust_over(s, W - 14, y0 + 2, 10, Hb - 12) if W > 40 else rust_over(s, 3, y0 + 18, 6, 8))
        hazard(s, 4, y0 + Hb - 3, 8, 2)
        weld(s, 12, y0 + Hb - 9, 8, False)
    if c.look.livery:                                                          # a race's own breech: livery trim lines and a stencil
        s.hline(3, y0 + 2, W - 6, '8'); s.hline(3, y0 + 3, W - 6, '7')
        stencil(s, 12, y0 + Hb - 11, (3, 2, 3))
    cx0, cy0 = x + 3, y + 1
    c.hurts.append(hurt_base(cracks=[[(cx0, cy0), (cx0 + 2, cy0 + 4), (cx0 + 1, cy0 + 8)]], sparks=[(cx0 + 2, cy0 + 3), (W - 6, y0 + 12)]))
    c.wrecks.append(wreck_base(cracks=[[(cx0, cy0), (cx0 + 2, cy0 + 5), (cx0, cy0 + 9), (cx0 + 3, cy0 + 12)]], dents=[(W - 12, y0 + 10, 6, 5)],
                               soots=[(x + 2, y0 + 3, 0)], wires=[[(4, y0 + 18), (7, y0 + 21), (10, y0 + 22)]]))

def frame(g, state, i):
    """(sprite, glow) of the breech of gun `g` (a gun_recipes_g2 / gun_recipes Gun with .breech_ver)."""
    W, H = g.in_cells[0] * 16, g.in_cells[1] * 16 + FLANGE
    c = Ctx(W, H, g.look, St(state, i))
    breech_fam(c, g.in_cells, g.fam, getattr(g, 'breech_ver', None))
    gm.flange(c, 0, W, up=False)
    return gm.finish(c), gm.glow_layer(c, gs.OPAD)

def export(g, outdir):
    """writes <id>.png/.json/_glow.png: the inside half in the format of the older ones (sheet of frames, offset [0, -4])."""
    W, H = g.in_cells[0] * 16, g.in_cells[1] * 16 + FLANGE
    fr, gl, anims, ganims = [], [], {}, {}
    for (nm, st, n, fps) in ANIMS:
        anims[nm] = [len(fr), n, fps]
        res = [frame(g, st, i) for i in range(n)]
        fr += [r[0] for r in res]
        if nm in GANIMS: ganims[nm] = [len(gl), n, fps]; gl += [r[1] for r in res]
    save(sheet(fr, len(fr), W, H), '%s/%s.png' % (outdir, g.name))
    gs_ = Rgba(gl[0].w * len(gl), gl[0].h)
    for k, f in enumerate(gl): gs_.blit_rgba(f, k * gl[0].w, 0)
    gs_.save('%s/%s_glow.png' % (outdir, g.name))
    J = {'frame': [W, H], 'cells': list(g.in_cells), 'anims': anims,
         'glow': {'image': g.name + '_glow.png', 'frame': [gl[0].w, gl[0].h], 'offset': [-gs.OPAD, -gs.OPAD], 'anims': ganims},
         'notes': 'INSIDE half of the %s (breech, outward = up; the top flange overhangs the inner wall face, see offset): a %s core%s, the feed column, power coupling, repair hatch on the wide ones, 5-cell charge strip. '
                  'charge: frame i lights i of the 5 cells (5 = ready); fire: the strip flashes, then goes dark. damaged: a dead cell, a crack, sparks; disabled: dark, cracked. '
                  'Module family gun_breech.py (2x2, 4x2, 2x4), in the line of the gun%s. The rotating head is %s_barrel.'
                  % (g.label.title(), g.fam, (' with the ' + g.breech_ver + ' add-on') if getattr(g, 'breech_ver', None) else '', ' and the race colours of its guns' if g.race else '', g.name),
         'offset': [0, -FLANGE]}
    with open('%s/%s.json' % (outdir, g.name), 'w') as f: json.dump(J, f, indent=1); f.write('\n')
    return J
