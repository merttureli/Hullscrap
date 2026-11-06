"""Drone modules (docs/DRONES.md section 8, on GUNS.md section 7): hand-drawn parts that a recipe composes into the drone bay, the drones, the limpets,
the boarder pod and the thruster trail. Built on the gun modules: gun_mod's Ctx / St / Look / finish / glow_layer, its helpers and its role letters,
so one recipe recolours by LINE (scrap, standard, neon) and FAMILY exactly as the guns do:
  '1' '2' '3' '4'  the family light (dark, mid, bright, hot);   '5' '6' the line lamp and accent;   '9' the line's edge highlight;
  steel L M S W E D follows the line (scrap duller, neon navy). No palette colour is added (the three effect families and the boarder
  reuse letters already in palette.gpl; see FAMILY_X).

A drone faces UP (its nose, the way it flies and shoots); its gun is part of the sprite and turns with it (it faces its target as it orbits).
One canvas of DN x DN px with the pivot at its centre. Frames: idle 0-1 (the running light blinks), fire 0-1 (a 1 px kick + the family muzzle
flash on the glow layer), hit (a white flash). A drone recipe is a family, a tier, a gun module and add-ons:
    D('laser_drone_mk2', 'laser', 2, ('twin', {}), ('fins',))
and every tier adds parts in one silhouette family (art bible rule 9): Mk I the round hull with its lens and two thruster pods, Mk II + swept
fins and a family lamp on each pod, Mk III + an armour collar, bigger finned pods, a rear engine block and a sensor mast.
Also here: the defence drones (a PD dome and radar scope in a hoop), the limpets, the boarder pod, the trail, the bay and the boarding robot rig."""
import math
import gun_mod as gm
from gun_mod import Ctx, St, Look, FLANGE, plate, tube, bolt_row, round_disc, rust_over, stencil, recess
from mach import bev, outline_all, glow
from wbase import hazard, weld, crack, spark, soot, dent, move
from lines_kit import ring as ringpx
from px import *

# ------------------------------------------------------------------ the drone families: the gun families, plus the limpets' effects and the boarder
#            light ramp: dark, mid, bright, hot      glow rgb          flash core rgb
FAMILY_X = {
 'fire':    (('u', 'o', 'y', 'H'), (255, 120, 20),  (255, 230, 150)),    # the fire limpet: flame orange, a yellow core
 'poison':  (('[', 'g', ']', ')'), (140, 230, 50),  (235, 255, 190)),    # the poison limpet: acid green with a pale straw core
 'heat':    (('e', '(', 'r', 'y'), (255, 52, 40),   (255, 200, 150)),    # the heat limpet: red-hot iron, crimson to red to yellow
 'boarder': (('n', 'u', 'a', 'y'), (232, 160, 48), (255, 236, 170)),    # the boarder pod and the drill robot: hazard amber
}
for _k, _v in FAMILY_X.items(): gm.FAMILY.setdefault(_k, _v)

# the thruster trail and the pods' exhaust glow by LINE (DRONES.md 8: "a thruster trail in the line's colour")
#            pixel ramp (core, body, fade)   glow rgb
TRAIL = {
 'standard': (('<', '>', 'W'), (150, 200, 255)),      # a clean pale blue burn
 'scrap':    (('y', 'a', 'W'), (255, 150, 40)),       # an amber sooty burn that ends in grey smoke
 'neon':     (('c', 'C', 'P'), (60, 242, 255)),       # cyan with a magenta fade
}
TRAIL_ALIAS = {'<': 'b4d0e2', '>': '6f8ba3'}           # private letters for the titanium sheen and cool grey of palette.gpl: no new colour
for _k, _h in TRAIL_ALIAS.items(): RGB[_k] = tuple(int(_h[i:i + 2], 16) for i in (0, 2, 4))

DN = 25; DC = 12                                      # the drone canvas and its pivot

# ------------------------------------------------------------------ small helpers
def px_(s, pts, c):
    for (x, y) in pts: s.put(x, y, c)

def stamp_at(s, cx, cy, rows, sub=None):
    """stamp an ASCII map centred on (cx, cy) (its middle column and row)."""
    if isinstance(rows, str): rows = art(rows)
    s.stamp(cx - len(rows[0]) // 2, cy - len(rows) // 2, rows, sub)

def disc(s, cx, cy, r, ramp=('L', 'M', 'S', 'W', 'E')):
    round_disc(s, cx + .5, cy + .5, r, ramp)

class DSt(St):
    """a drone frame: idle, fire, hit (plus the gun states the modules read)."""
    def __init__(s, state='idle', i=0):
        St.__init__(s, 'fire' if state == 'fire' else ('on' if state in ('idle', 'hit') else state), i)
        s.dstate = state
        s.rc = (1, 0)[i] if state == 'fire' else 0          # the gun kicks back 1 px, then home
        s.blink = state == 'idle' and i == 1
        s.hit = state == 'hit'

# ================================================================== COMBAT DRONE modules (canvas DN x DN, pivot (DC, DC), nose up)
# Hand-drawn maps in role letters, stamped about the pivot; '.' is empty. The outline pass closes the 1 px gaps between parts in near-black,
# so hull, pods and gun read as separate pieces even at 1x.
HULL = """
...LMMS...
..LMMMMS..
.LMMDDDSS.
LMMD432DSW
MMMD321DSW
MSSD211DWW
.SSSDDDWW.
..SSWWWE..
...WWEE...
"""     # the round hull of the service-drone lineage with ONE lens in the family light (the repair drone's eye) in a dark socket; 9 px, the lens centred on the pivot
PODMAP = {    # a thruster pod: a lit front cap, the body, a dark nozzle (the left pod; the right is its mirror, one tone darker). Mk III's has its fin built in.
 1: """
LM
MS
MS
MS
SW
EE
""",
 3: """
.LMS
.MMS
.MSW
.MSW
MMSW
SSWW
6EDE
""",
}
FIN = """
.M
MS
SW
6.
"""     # a swept stabiliser blade on a pod's outer side, the line's accent at its tip
def stamp_rel(c, dx, dy, rows, flip=False, sub=None):
    """stamp a map with its top-left at (pivot + (dx, dy)); flip mirrors it (the right side), shading it one tone darker."""
    rows = art(rows) if isinstance(rows, str) else rows
    if flip:
        dk = {'L': 'M', 'M': 'S', 'S': 'W', 'W': 'E'}
        rows = [''.join(dk.get(ch, ch) for ch in r[::-1]) for r in rows]
    c.s.stamp(c.px + dx, c.py + dy, rows, sub)

def pods(c, tier):
    """the two thruster pods at the rear sides (the repair drone's two pods), hung on a spar, a 1 px gap from the hull."""
    m = PODMAP[1 if tier < 3 else 3]; w = len(art(m)[0]); h = len(art(m))
    gx = 5 if tier < 3 else 6                                                  # the pod's inner edge, from the pivot
    top = -1 if tier < 3 else -2
    stamp_rel(c, -gx - w, top, m); stamp_rel(c, gx + 1, top, m, flip=True)
    c.s.hline(c.px - gx, c.py + 2, 2 * gx + 1, 'W')                           # the spar (under the hull)
    for side in (-1, 1):
        x = c.px - gx - w if side < 0 else c.px + gx + 1
        if tier == 3: x += 1 if side < 0 else 0
        nx = x + ((3 if tier == 3 else w) - 1) / 2.0
        c.lightglow(nx, c.py + top + h, 2.8, 0.6, TRAIL[c.line][1])           # the exhaust, in the line's colour
        c.nozzles.append((int(nx + .5), c.py + top + h))
        if tier >= 2:                                                          # Mk II: the second accent, a family lamp on each pod cap
            lx = int(nx); c.s.put(lx, c.py + top + 1, '2'); c.lightglow(lx, c.py + top + 1, 2.0, 0.3)
    if c.line == 'scrap':                                                     # a mismatched replacement pod, rusted, with a hazard tick
        w0 = 2 if tier < 3 else 3; x0 = c.px - gx - w0
        rust_over(c.s, x0, c.py + top + 1, w0, h - 2); c.s.put(x0, c.py + top + 1, 'a'); c.s.put(x0 + 1, c.py + top + 1, 'D')
    elif c.line == 'neon':
        for side in (-1, 1):
            x = c.px - gx - w if side < 0 else c.px + gx + w
            c.s.vline(x, c.py + top + 1, h - 3, 'c')

def hull(c, tier):
    """the round hull and its lens (the family eye, a soft glow on it)."""
    if tier == 3:                                                              # Mk III: the octagonal armour collar round the hull, bolted at its corners
        gm.oct_disc(c.s, c.px, c.py, 11, 'S', 'M', 'W')
        bolt_row(c.s, [(c.px - 4, c.py - 3), (c.px + 4, c.py - 3), (c.px - 4, c.py + 4), (c.px + 4, c.py + 4)], 'L')
    stamp_rel(c, -4, -4, art(HULL))
    s = c.s
    if not c.st.powered:
        for y in range(s.h):
            for x in range(s.w):
                if s.g[y][x] in '1234': s.g[y][x] = 'E'
    c.lightglow(c.px, c.py, 3.4, 0.55)
    if c.line == 'scrap': rust_over(s, c.px + 1, c.py + 2, 3, 2); s.put(c.px - 3, c.py - 2, 'u'); s.put(c.px - 2, c.py + 3, 'u')
    elif c.line == 'neon':
        for (x, y) in ((c.px - 3, c.py - 2), (c.px - 2, c.py - 3), (c.px - 1, c.py - 3), (c.px, c.py - 4), (c.px + 1, c.py - 4)): s.put(x, y, 'c')

def running_light(c, tier):
    """the running light at the tail, in the family light: it blinks (idle 0 lit, idle 1 dark)."""
    s = c.s; cx = c.px; y = c.py + (5 if tier < 3 else 6)
    on = c.st.powered and not c.st.blink
    s.put(cx, y - 1, 'W'); s.put(cx, y, '3' if on else '1')
    if on: c.lightglow(cx, y, 3.0, 0.75)

def fins(c, tier):
    """Mk II: swept fins on the pods' outer sides, the line's accent at their tips: the silhouette widens to a delta."""
    if tier == 3: return                                                       # Mk III's pods carry their fins
    stamp_rel(c, -9, 2, FIN); stamp_rel(c, 8, 2, FIN, flip=True)

def armour(c, tier):
    """Mk III: the collar is drawn by hull(); this adds its brow: the line's edge across the front and a hazard tick or a cyan edge by line."""
    s = c.s
    if c.line == 'neon': s.hline(c.px - 2, c.py - 5, 5, 'c')
    elif c.line == 'scrap': s.put(c.px + 3, c.py - 4, 'a'); s.put(c.px + 4, c.py - 3, 'D'); s.put(c.px - 5, c.py + 1, 'u'); s.put(c.px - 5, c.py + 2, 'u')

def engine(c, tier):
    """Mk III: a rear engine block on the hull's tail, a third nozzle."""
    stamp_rel(c, -2, 5, """
LMMSW
MSSWE
E.D.E
""")
    c.lightglow(c.px - 2, c.py + 8, 2.4, 0.5, TRAIL[c.line][1]); c.lightglow(c.px + 2, c.py + 8, 2.4, 0.5, TRAIL[c.line][1])
    c.nozzles += [(c.px - 2, c.py + 8), (c.px + 2, c.py + 8)]

def mast(c, tier):
    """Mk III: a sensor mast off the right shoulder, its tip in the line's lamp colour."""
    s = c.s
    s.put(c.px + 4, c.py - 5, 'W'); s.put(c.px + 5, c.py - 6, 'S'); s.put(c.px + 6, c.py - 7, '5')
    c.lightglow(c.px + 6, c.py - 7, 2.0, 0.45, gm.RGB_LAMP[c.line])

# ---- the guns (nose up; c.st.rc kicks them back 1 px): one per family, the silhouette of its gun family (GUNS.md 7)
def gun_root(c, w, y=-5):
    stamp_rel(c, -(w // 2) - 1, y, ['L' + 'M' * w + 'S', 'M' + 'S' * w + 'W'])   # the mount block on the hull's nose

def lens(c, x, y, w):
    """the muzzle lens in the family light, hot when firing; dead steel with no power."""
    s = c.s
    if not c.st.powered: s.hline(x, y, w, 'E'); return
    s.hline(x, y, w, '2'); s.put(x + w // 2, y, '4' if c.st.fire else '3')
    c.muzzles.append((x + w // 2, y)); c.lightglow(x + w // 2, y, 2.4, 0.45)

def gun_stub(c, top=-10):
    """pulse: one short fat barrel with a band, a lens (the pulse cannon, small)."""
    s = c.s; cx, cy = c.px, c.py; o = c.st.rc
    tube(s, cx - 1, cy + top + 1 + o, 3, -top - 5, 'MSW')
    s.hline(cx - 2, cy + top + 3 + o, 5, 'M'); s.put(cx - 2, cy + top + 3 + o, 'L'); s.put(cx + 2, cy + top + 3 + o, 'W')
    lens(c, cx - 1, cy + top + o, 3)
    gun_root(c, 3)

def gun_twin(c, top=-10):
    """laser Mk II: twin rails on a bridge, a lens each (the Laser Mk II's twin)."""
    s = c.s; cx, cy = c.px, c.py; o = c.st.rc
    for x in (cx - 2, cx + 2):
        s.vline(x, cy + top + 1 + o, -top - 5, 'M' if x < cx else 'S')
        lens(c, x, cy + top + o, 1)
    s.hline(cx - 2, cy - 7 + o, 5, 'M'); s.put(cx + 2, cy - 7 + o, 'S'); s.put(cx, cy - 7 + o, '2' if c.st.powered else 'E')
    gun_root(c, 5)

def gun_coil(c, top=-10):
    """ion Mk II: a barrel wound with two coil rings lit in the family colour."""
    s = c.s; cx, cy = c.px, c.py; o = c.st.rc
    tube(s, cx - 1, cy + top + 1 + o, 3, -top - 5, 'MSW')
    for y in (cy + top + 2, cy + top + 4):
        s.hline(cx - 2, y + o, 5, '2' if c.st.powered else 'E'); s.put(cx - 2, y + o, '3' if c.st.powered else 'W'); s.put(cx + 2, y + o, '1' if c.st.powered else 'D')
        if c.st.powered: c.lightglow(cx, y + o, 2.2, 0.3, sx=1.4)
    lens(c, cx - 1, cy + top + o, 3)
    gun_root(c, 3)

def gun_prism(c, top=-11):
    """beam Mk III: two prongs and the focus crystal between them (the lance's emitter, small)."""
    s = c.s; cx, cy = c.px, c.py; o = c.st.rc
    for x in (cx - 2, cx + 2):
        s.vline(x, cy + top + o, 5, 'M' if x < cx else 'S'); s.put(x, cy + top + o, '9')
    on = c.st.powered
    gem = ['.4.', '343', '232', '.1.'] if c.st.fire else ['.3.', '342', '221', '.1.']
    if not on: gem = ['.W.', 'WEE', 'EED', '.D.']
    stamp_rel(c, -1, top + 1 + o, gem)
    if on: c.muzzles.append((cx, cy + top + 1 + o)); c.lightglow(cx, cy + top + 2 + o, 3.0, 0.55)
    gun_root(c, 5, -6)

def gun_triple(c, top=-10):
    """flak Mk III: three short barrels in a cluster (the flak turret's triple)."""
    s = c.s; cx, cy = c.px, c.py; o = c.st.rc
    for k, x in enumerate((cx - 2, cx, cx + 2)):
        t = cy + top + (0 if k == 1 else 1) + o
        s.vline(x, t + 1, cy - 6 - t + o, 'M' if k == 0 else ('S' if k == 1 else 'W'))
        lens(c, x, t, 1)
    s.hline(cx - 3, cy - 7 + o, 7, 'M'); s.put(cx - 3, cy - 7 + o, 'L'); s.put(cx + 3, cy - 7 + o, 'W')
    gun_root(c, 5, -6)

GUNS = {'stub': gun_stub, 'twin': gun_twin, 'coil': gun_coil, 'prism': gun_prism, 'triple': gun_triple}
ADDS = {'fins': fins, 'armour': armour, 'engine': engine, 'mast': mast}

# ================================================================== DEFENCE DRONE modules (PD green): a radar ring round a small dome, twin small barrels
def radar_ring(c, tier):
    """the radar hoop: a flat 2 px ring round the dome on two rear struts, lit top-left; its PD emitters turn round it (idle 0 / 1), Mk II has four and a doubled hoop."""
    s = c.s; cx, cy = c.px, c.py
    r0, r1 = (6.0, 7.2) if tier == 1 else (6.0, 8.2)
    for y in range(cy - 9, cy + 10):
        for x in range(cx - 9, cx + 10):
            dx, dy = x - cx, y - cy
            d = (dx * dx + dy * dy) ** 0.5
            if not (r0 <= d <= r1): continue
            a = math.degrees(math.atan2(dx, -dy)) % 360                         # 0 = up, clockwise
            lit = math.cos(math.radians(a - 315))                               # facing the top-left light
            s.put(x, y, 'M' if lit > 0.55 else ('S' if lit > -0.35 else 'W'))
            if tier == 2 and r0 + 1.0 < d < r0 + 1.7: s.put(x, y, 'E')          # Mk II: a doubled hoop, a dark groove between the two
    for sd in (-1, 1):                                                          # the two rear struts
        for k in range(3, 6): s.put(cx + sd * k, cy + k, 'S' if sd < 0 else 'W')
    n = 3 if tier == 1 else 4
    turn = (c.st.i * (60 if n == 3 else 45)) if c.st.dstate == 'idle' else 0
    for k in range(n):                                                          # the emitters on the hoop, in the family light
        a = math.radians(turn + 360.0 * k / n + 30)
        rr = 6.6 if tier == 1 else 7.4
        x, y = int(round(cx + rr * math.sin(a))), int(round(cy - rr * math.cos(a)))
        s.put(x, y, '3' if c.st.powered else 'E')
        if c.st.powered: c.lightglow(x, y, 2.2, 0.45)
    if c.line == 'neon':
        for y in range(cy - 9, cy + 10):
            for x in range(cx - 9, cx + 10):
                d = ((x - cx) ** 2 + (y - cy) ** 2) ** 0.5
                if r1 - 0.8 <= d <= r1 and (math.degrees(math.atan2(x - cx, cy - y)) % 360) > 230: s.put(x, y, 'c')
    elif c.line == 'scrap': s.put(cx + 4, cy - 5, 'u'); s.put(cx + 5, cy - 4, 'u'); s.put(cx - 6, cy + 1, 'a'); s.put(cx - 6, cy + 2, 'D')

PD_DOME = """
..LMMS..
.LMDDDS.
LMD...DW
MMD...DW
MSD...DW
.SWDDDW.
..SWWE..
"""   # the defence drone's hull: the PD dome round a radar scope (the PD breech's scope, its sweep turns in idle)

def pd_dome(c, tier):
    s = c.s; cx, cy = c.px, c.py
    stamp_rel(c, -4, -3, PD_DOME)
    for (x, y) in ((cx - 1, cy - 1), (cx, cy - 1), (cx + 1, cy - 1), (cx - 1, cy), (cx, cy), (cx + 1, cy), (cx - 1, cy + 1), (cx, cy + 1), (cx + 1, cy + 1)):
        s.put(x, y, 'D')
    if c.st.powered:
        sw = [((1, -1), (0, -1)), ((1, 0), (1, -1)), ((1, 1), (1, 0)), ((0, 1), (1, 1))][(c.st.i * 2 if c.st.dstate == 'idle' else 0) % 4]
        s.put(cx + sw[0][0], cy + sw[0][1], '3'); s.put(cx + sw[1][0], cy + sw[1][1], '1'); s.put(cx, cy, '2')
        c.lightglow(cx + .5, cy + .5, 3.2, 0.5)
    if c.line == 'scrap': rust_over(s, cx - 3, cy + 1, 2, 2); s.put(cx + 2, cy - 3, 'u')
    elif c.line == 'neon': s.put(cx - 3, cy - 1, 'c'); s.put(cx - 2, cy - 2, 'c'); s.put(cx - 1, cy - 3, 'c')

def backing(c, tier):
    """a dark backing disc inside the hoop (a defence drone must not read as a grey ring over a grey hull)."""
    s = c.s; cx, cy = c.px, c.py
    r = 6.0
    for y in range(cy - 7, cy + 8):
        for x in range(cx - 7, cx + 8):
            if (x - cx) ** 2 + (y - cy) ** 2 < r * r: s.put(x, y, 'E')

def pd_barrels(c, tier):
    """twin small barrels (the PD twin) over the hoop."""
    s = c.s; cx, cy = c.px, c.py; o = c.st.rc
    L = 4 if tier == 1 else 5
    for x in (cx - 2, cx + 2):
        s.vline(x, cy - 3 - L + o, L, 'M' if x < cx else 'S')
        lens(c, x, cy - 4 - L + o, 1)
    s.hline(cx - 3, cy - 4 + o, 7, 'M'); s.put(cx - 3, cy - 4 + o, 'L'); s.put(cx + 3, cy - 4 + o, 'W')
    if tier == 2: s.hline(cx - 2, cy - 6 + o, 5, 'S'); s.put(cx - 2, cy - 6 + o, 'M')

# ================================================================== the drone recipe
class Drone:
    """one drone from a recipe: kind 'combat' or 'defence', a family, a tier (1-3), a gun module and add-ons. Line by variant()."""
    def __init__(s, name, fam, tier, gun=None, add=(), kind='combat', label=None, line='standard'):
        s.name, s.fam, s.tier, s.gun, s.add, s.kind, s.line = name, fam, tier, gun, list(add), kind, line
        s.label = label or name.replace('_', ' ').upper()
        s.look = Look(line, fam)
    def variant(s, **kw):
        d = dict(name=s.name, fam=s.fam, tier=s.tier, gun=s.gun, add=s.add, kind=s.kind, label=s.label, line=s.line)
        d.update(kw); return Drone(**d)
    def frame(s, state='idle', i=0, raw=False, part=None):
        """-> (sprite, glow, anchors): the sprite on a DN x DN canvas (pivot (DC, DC)), its glow (pad GP), the muzzle and nozzle points.
        raw: the sprite without its outline (to turn it first and outline after, as the crew compositor does)."""
        st = DSt(state, i)
        c = Ctx(DN, DN, s.look, st); c.px, c.py = DC, DC; c.nozzles = []
        if s.kind == 'defence':
            if part != 'barrel': backing(c, s.tier)
            if part != 'barrel': radar_ring(c, s.tier)
            if part != 'base': pd_barrels(c, s.tier)
            if part != 'barrel': pd_dome(c, s.tier)
        else:
            pods(c, s.tier)
            if 'fins' in s.add: fins(c, s.tier)
            if 'engine' in s.add: engine(c, s.tier)
            GUNS[s.gun[0]](c, **s.gun[1])
            hull(c, s.tier)
            if 'armour' in s.add: armour(c, s.tier)
            if 'mast' in s.add: mast(c, s.tier)
            running_light(c, s.tier)
        spr = c.s.sub(c.look.sub(st))
        if not raw: spr = spr.copy(); outline_all(spr)
        if st.hit: spr = hit_flash(spr)
        g = gm.glow_layer(c, GP, (lambda g, p: flash_glow(c, g, p)) if st.fire else None)
        if st.hit: g = Rgba(g.w, g.h); glow(g, GP + DC + .5, GP + DC + .5, 9, (255, 255, 255), 0.35, 1.6)
        return spr, g, dict(muzzle=c.muzzles[:], nozzles=c.nozzles[:])

GP = 10                                                                            # drone glow padding
HIT = {'K': 'S', 'D': 'M', 'E': 'M', 'W': 'L', 'S': 'L', 'M': 'H', 'L': 'H', 'N': 'j', 'I': 'L', 'J': 'L', 'j': 'H'}
def hit_flash(spr):
    """the hit frame: the drone flashes white, the outline stays dark so the shape holds."""
    n = spr.copy()
    for y in range(n.h):
        for x in range(n.w):
            ch = n.g[y][x]
            if ch == '.' or ch == 'K': continue
            n.g[y][x] = HIT.get(ch, 'H')
    return n

def flash_glow(c, g, p):
    """the muzzle flash of a drone on the glow layer: a small hard flash in the family colour with a white core, frame 0 big, 1 small."""
    i = c.st.i
    rgb, core = c.look.rgb, c.look.core
    for (mx, my) in c.muzzles:
        glow(g, p + mx + .5, p + my - 1 + .5, (5.5, 3.5)[i], rgb, (0.75, 0.5)[i], 1.6)
        for k in range((3, 2)[i]):
            g.over(p + mx, p + my - 1 - k, (core if k < 2 else rgb) + ((250, 220, 160)[k],))
        if i == 0:
            g.over(p + mx - 1, p + my - 1, rgb + (190,)); g.over(p + mx + 1, p + my - 1, rgb + (190,))

# the first list (DRONES.md 3)
D = Drone
COMBAT = [
 D('pulse_drone_mk1', 'pulse', 1, ('stub', {}), (), label='PULSE DRONE MK I'),
 D('laser_drone_mk2', 'laser', 2, ('twin', {}), ('fins',), label='LASER DRONE MK II'),
 D('ion_drone_mk2', 'ion', 2, ('coil', {}), ('fins',), label='ION DRONE MK II'),
 D('beam_drone_mk3', 'beam', 3, ('prism', {}), ('fins', 'engine', 'armour', 'mast'), label='BEAM DRONE MK III'),
 D('flak_drone_mk3', 'flak', 3, ('triple', {}), ('fins', 'engine', 'armour', 'mast'), label='FLAK DRONE MK III'),
]
DEFENCE = [
 D('defence_drone_mk1', 'pd', 1, kind='defence', label='DEFENCE DRONE MK I'),
 D('defence_drone_mk2', 'pd', 2, kind='defence', label='DEFENCE DRONE MK II'),
]

# ================================================================== LIMPETS (DRONES.md 5): a spiked magnetic disc with a glow core in its effect's colour
# One canvas of DN x DN, the core on the pivot. The clamp spikes are folded while it flies and splay out when it sticks (stuck 0-3: the core
# pulses), the husk is the dead disc with bent spikes that falls off. The effect shows in the core and one detail: fire = three burner vents,
# poison = two toxin bulbs, heat = a radiator ring lit round the core.
SPIKES = [(0, -1), (1, -1), (1, 0), (1, 1), (0, 1), (-1, 1), (-1, 0), (-1, -1)]      # N NE E SE S SW W NW

class LSt(DSt):
    def __init__(s, state='flying', i=0):
        St.__init__(s, 'off' if state == 'husk' else 'on', i)
        s.dstate = state; s.rc = 0; s.blink = False; s.hit = False
        s.dmg = 2 if state == 'husk' else 0

def limpet_spikes(c, out):
    """the clamp spikes: 3 px long (2 on the diagonals) when splayed, a 1 px stub when folded; lit on the top-left ones."""
    s = c.s; cx, cy = c.px, c.py
    for k, (dx, dy) in enumerate(SPIKES):
        diag = dx and dy
        n = (2 if diag else 3) if out else 1
        start = 4 if diag else 5
        lit = k in (0, 6, 7)
        for j in range(n):
            x, y = cx + dx * (start + j), cy + dy * (start + j)
            s.put(x, y, ('L' if j == n - 1 else 'M') if lit else ('S' if j == n - 1 else 'W'))
        if out and not diag:                                                     # a wider foot where an orthogonal spike meets the disc
            s.put(cx + dx * 5 + dy, cy + dy * 5 + dx, 'S' if lit else 'W'); s.put(cx + dx * 5 - dy, cy + dy * 5 - dx, 'S' if lit else 'W')

LIMPET_DISC = """
..LMMMS..
.LMSSSSW.
LMSDDDSWW
MSD...DWW
MSD...DWE
SSD...DWE
SSWDDDWWE
.SWWWWWE.
..WWEEE..
"""   # the magnet disc (9 px), darker than a drone's hull (a mine, not a craft), the socket round the core

def limpet(c, fam):
    st = c.st; s = c.s; cx, cy = c.px, c.py
    out = st.dstate != 'flying'
    limpet_spikes(c, out)
    stamp_rel(c, -4, -4, LIMPET_DISC)
    for (x, y) in ((cx - 3, cy - 3), (cx + 3, cy + 3)): s.put(x, y, 'L' if x < cx else 'E')                   # two bolts on the plate
    lvl = {'flying': (2, 1)[st.i % 2], 'stuck': (3, 2, 1, 2)[st.i % 4], 'husk': -1}[st.dstate]   # the core's brightness (3 = brightest)
    core = {3: ('4', '3', '2'), 2: ('3', '2', '1'), 1: ('2', '1', '1'), -1: ('E', 'D', 'D')}[lvl]
    s.put(cx, cy, core[0])
    for (x, y) in ((cx, cy - 1), (cx - 1, cy), (cx + 1, cy), (cx, cy + 1)): s.put(x, y, core[1])
    for (x, y) in ((cx - 1, cy - 1), (cx + 1, cy - 1), (cx - 1, cy + 1), (cx + 1, cy + 1)): s.put(x, y, core[2])
    on = lvl > 0
    if fam == 'fire':                                                            # three burner vents round the rim, each a dark nozzle with a lit throat
        for (x, y) in ((cx, cy - 3), (cx - 3, cy + 2), (cx + 3, cy + 2)):
            s.put(x, y, '2' if on else 'D')
        for (x, y) in ((cx - 1, cy - 3), (cx + 1, cy - 3), (cx - 3, cy + 3), (cx + 3, cy + 3)): s.put(x, y, 'E')
    elif fam == 'poison':                                                        # two toxin bulbs on the flanks: a lit glass bulb in a dark cap
        for sd in (-1, 1):
            bx = cx + sd * 3
            s.put(bx, cy - 1, '3' if on else 'E'); s.put(bx, cy, '2' if on else 'E'); s.put(bx, cy + 1, '1' if on else 'D')
            s.put(bx, cy - 2, 'E'); s.put(bx, cy + 2, 'E')
    elif fam == 'heat':                                                          # the radiator: the socket ring itself glows, with dark fins across it
        for y in range(cy - 2, cy + 3):
            for x in range(cx - 2, cx + 3):
                if max(abs(x - cx), abs(y - cy)) == 2 and abs(x - cx) + abs(y - cy) < 4:
                    s.put(x, y, ('1' if (x + y) % 2 else '2') if on else 'D')
    if lvl > 0:
        c.lightglow(cx, cy, (3.2, 4.0, 5.2)[lvl - 1], (0.45, 0.6, 0.8)[lvl - 1])
        if fam == 'heat': c.lightglow(cx, cy, 6.5, 0.18 * lvl)
    if c.line == 'scrap': s.put(cx - 2, cy + 3, 'u'); s.put(cx + 3, cy - 1, 'u')
    elif c.line == 'neon': s.put(cx - 2, cy - 3, 'c'); s.put(cx - 3, cy - 2, 'c')

def limpet_husk(s, c):
    """the husk: two spikes bent, a crack through the dead core, soot."""
    cx, cy = c.px, c.py
    for (x, y) in ((cx + 4, cy - 4), (cx + 5, cy - 5), (cx - 6, cy), (cx - 7, cy)): s.erase(x, y)
    s.put(cx + 5, cy - 3, 'W'); s.put(cx + 6, cy - 3, 'E'); s.put(cx - 6, cy + 1, 'W')
    crack(s, [(cx - 1, cy - 4), (cx, cy - 1), (cx + 1, cy + 1), (cx + 1, cy + 4)], 'K', 'S')

class Limpet:
    """a limpet recipe: its family (fire, poison, heat) and a line. Frames: flying 0-1, stuck 0-3, husk."""
    def __init__(s, name, fam, line='standard', label=None):
        s.name, s.fam, s.line = name, fam, line
        s.label = label or name.replace('_', ' ').upper()
        s.look = Look(line, fam)
    def variant(s, **kw):
        d = dict(name=s.name, fam=s.fam, line=s.line, label=s.label); d.update(kw); return Limpet(**d)
    def frame(s, state='flying', i=0):
        st = LSt(state, i)
        c = Ctx(DN, DN, s.look, st); c.px, c.py = DC, DC; c.nozzles = []
        limpet(c, s.fam)
        spr = c.s.sub(s.look.sub(St('on')))
        if state == 'husk':
            spr = spr.sub(gm.DARKX); limpet_husk(spr, c); soot(spr, DC - 3, DC - 4, 2)
        spr = spr.copy(); outline_all(spr)
        g = Rgba(DN + 2 * GP, DN + 2 * GP)
        if state != 'husk':
            for (x, y, r, a, rgb, sx) in c.glows: glow(g, GP + x + .5, GP + y + .5, r, rgb or s.look.rgb, a, 2.0, sx=sx)
        return spr, g, {}

LIMPETS = [Limpet('fire_limpet', 'fire', label='FIRE LIMPET'), Limpet('poison_limpet', 'poison', label='POISON LIMPET'), Limpet('heat_limpet', 'heat', label='HEAT LIMPET')]

# ================================================================== THE BOARDER POD (DRONES.md 6): a 1x2 drill-nosed capsule, nose up
PW, PH = 21, 37; PCX = 10                                                  # the pod canvas: 1x2 cells (16 x 32) plus room for the outline and sparks
POD_BODY = """
..LLMMMMS..
.LMMMMMMSS.
LMMMSSSSSSW
MMSWWWWWWSW
MMSW.....SW
MMSW.....SW
MMSW.....SW
MMSW.....SW
MMSW.....SW
MMSW.....SW
MSSWWWWWWSW
MSSSSSSSSWE
MSSSSSSSWWE
SSSWWWWWWWE
.SWWEEEEWE.
..E.EDE.E..
"""   # the capsule (11 x 16): a lit shoulder, the boarding hatch (its frame; the panel is drawn by state), the rear deck and three nozzles

def drill(c, phase, dead=False):
    """the drill cone, 9 px wide at the collar to a point 11 px ahead: spiral flutes, light and dark, that move with the phase."""
    s = c.s; cx = c.px; top = 3
    for j in range(11):                                                       # j = 0 at the tip
        hw = (j * 9 // 11) // 2 + (1 if j >= 2 else 0) if j else 0
        y = top + j
        for x in range(cx - hw, cx + hw + 1):
            k = (x - cx) + (y + phase) * 1                                    # the flutes run diagonally; the phase turns them
            band_ = (k // 2) % 2
            lit = x < cx or (x == cx and j < 4)
            if dead: ch = 'W' if band_ else 'E'
            else: ch = ('L' if lit else 'S') if band_ else ('S' if lit else 'W')
            s.put(x, y, ch)
    s.put(cx, top, 'L' if not dead else 'S')

CLAW = {'folded': ["M", "S", "S", "W"], 'grip': [".L", "M.", "S.", "S.", "S.", "W.", "E."]}
def pod(c, state, i):
    s = c.s; cx = c.px
    grip = state != 'flying'
    for sd in (-1, 1):                                                          # the clamp claws on the flanks: folded in flight, swung forward to grip the hull
        m = CLAW['grip' if grip else 'folded']
        if sd > 0: m = [r[::-1].replace('L', 'S').replace('M', 'S') for r in m]
        w = len(m[0])
        x = cx - 6 if sd < 0 else cx + 6 - (w - 1)
        s.stamp(x, 9 if grip else 16, m)
    stamp_rel(c, -5, 14 - c.py, POD_BODY)
    phase = {'drilling': i, 'flying': 0, 'husk': 0}[state]
    drill(c, phase * 1, dead=state == 'husk')
    s.hline(cx - 5, 14, 11, 'M'); s.hline(cx - 5, 15, 11, 'W'); s.put(cx - 5, 14, 'L')         # the drill collar
    for x in range(cx - 4, cx + 5, 2): s.put(x, 15, '2' if state != 'husk' else 'E')           # family lights round the collar
    if state != 'husk': c.lightglow(cx, 15, 4.5, 0.45, sx=1.6)
    hx0, hy0 = cx - 2, 18                                                       # the hatch panel inside its frame
    if state == 'husk':                                                         # empty: the hatch is open and the bay inside is dark and bare
        s.rect(hx0, hy0, 5, 6, 'K'); s.hline(hx0, hy0 + 6, 5, 'D')
        s.put(hx0 + 4, hy0 + 1, 'E'); s.put(hx0, hy0 + 5, 'E')
    else:
        bev(s, hx0, hy0, 5, 7, 'M', 'S', 'W', cham=False)
        s.put(hx0 + 2, hy0 + 3, '6'); s.put(hx0 + 2, hy0 + 2, 'W')
        hazard(s, hx0, hy0 + 5, 5, 1)
    on = state != 'husk' and not (state == 'flying' and i % 2)
    for sd in (-1, 1):                                                          # the side lamps (they blink in flight)
        x = cx + sd * 4
        s.put(x, 20, '3' if on else ('1' if state != 'husk' else 'E'))
        if on: c.lightglow(x, 20, 2.6, 0.55)
    stencil(s, cx - 3, 26, (2, 3))
    if state != 'husk':                                                         # the nozzles burn (a hard push while it drills)
        for x in (cx - 3, cx, cx + 3):
            c.lightglow(x, 30, 3.0 if state == 'flying' else 4.0, 0.55 if state == 'flying' else 0.8, TRAIL[c.line][1])
        c.nozzles += [(cx - 3, 30), (cx, 30), (cx + 3, 30)]
    if c.line == 'scrap': rust_over(s, cx + 1, 25, 4, 3); weld(s, cx - 4, 22, 4, True)
    elif c.line == 'neon': s.vline(cx - 5, 18, 8, 'c'); s.hline(cx - 3, 14, 7, 'c')

class Pod:
    """the boarder pod: its family (boarder amber, or ion for the shock robot's pod) and line. Frames: flying 0-1, drilling 0-2, husk."""
    def __init__(s, name='boarder_pod', fam='boarder', line='standard', label='BOARDER POD'):
        s.name, s.fam, s.line, s.label = name, fam, line, label
        s.look = Look(line, fam)
    def variant(s, **kw):
        d = dict(name=s.name, fam=s.fam, line=s.line, label=s.label); d.update(kw); return Pod(**d)
    def frame(s, state='flying', i=0):
        st = LSt('stuck' if state == 'drilling' else ('husk' if state == 'husk' else 'flying'), i)
        c = Ctx(PW, PH, s.look, st); c.px, c.py = PCX, 18; c.nozzles = []
        pod(c, state, i)
        spr = c.s.sub(s.look.sub(St('on')))
        if state == 'husk':
            spr = spr.sub(gm.DARKX); soot(spr, PCX - 4, 4, 1); soot(spr, PCX + 1, 27, 2); dent(spr, PCX + 2, 22, 3, 3)
        if state == 'drilling':                                                 # sparks spray off the tip
            sp = [(PCX - 2, 2), (PCX + 2, 1), (PCX + 1, 3)][i % 3]; spark(spr, sp[0], sp[1], i % 3 != 1)
        spr = spr.copy(); outline_all(spr)
        g = Rgba(PW + 2 * GP, PH + 2 * GP)
        if state != 'husk':
            for (x, y, r, a, rgb, sx) in c.glows: glow(g, GP + x + .5, GP + y + .5, r, rgb or s.look.rgb, a, 2.0, sx=sx)
        if state == 'drilling': glow(g, GP + PCX + .5, GP + 2.5, 5, (255, 220, 120), 0.6, 1.8)
        return spr, g, dict(nozzles=c.nozzles)

BOARDER = Pod()

# ================================================================== THE THRUSTER TRAIL (an fx strip, 4 frames of 5 x 5, played once per puff, in the line's colour)
TRAIL_FRAMES = [
"""
.....
..b..
.bcb.
..b..
.....
""", """
.....
..b..
.bbb.
..b..
.....
""", """
.....
..f..
.f.f.
.....
.....
""", """
.....
.....
..f..
.....
.....
"""]
def trail_frames(line):
    """-> [(sprite, glow)] for the trail puff of a line: a hot core, the line's body colour, then its fade colour as it thins."""
    core, body, fade = TRAIL[line][0]
    out = []
    for k, a in enumerate(TRAIL_FRAMES):
        sp = from_art(a, {'c': core, 'b': body, 'f': fade})
        g = Rgba(5 + 2 * 4, 5 + 2 * 4)
        glow(g, 4 + 2.5, 4 + 2.5, (3.5, 4.0, 3.5, 2.5)[k], TRAIL[line][1], (0.45, 0.3, 0.15, 0.06)[k], 1.8)
        out.append((sp, g))
    return out

# ================================================================== THE DRONE BAY (DRONES.md 2 and 8): a hull mount, inside half 3x3, outside half 3x1
# Inside (48 x 52, the flange on top over the inner wall face, outward up): the hangar pit with the launch rail running up into the wall,
# the cradle on the rail holding the loaded drone, a parts rack each side, the power coupling and the family status strip at the foot.
# Outside (48 x 20, the flange at the bottom over the outer wall face): a low hatch, two door leaves that slide apart over the launch well.
# Frames, inside: on 0-1, off, damaged 0-1, disabled, launch 0-3 (the cradle runs up the rail and the drone goes into the wall), out 0-1 (the cradle
# home and empty while the drone is out; the strip counts the re-arm); outside: on 0-1, off, damaged 0-1, disabled, open 0-2 (closed is `on`).
BW, BH = 48, 48 + FLANGE; OW, OH = 48, 16 + FLANGE
RX = 24                                                                     # the rail's centre line (between the two rails)
REST = 34                                                                   # the drone's pivot on the cradle at rest (y in the inside half)
LAUNCH = [0, 9, 19, 27]                                                     # how far up the rail the cradle is, launch frame 0..3

class BSt(St):
    def __init__(s, state='on', i=0):
        St.__init__(s, {'launch': 'on', 'out': 'on', 'open': 'on'}.get(state, state), i)
        s.bstate = state
        s.blink = state == 'on' and i % 2 == 1

def crate(s, x, y, w=4, h=4, c='S'):
    """a parts crate on a shelf: a lit lid, a dark strap across it, a shaded side."""
    s.rect(x, y, w, h, c); s.hline(x, y, w, 'L' if c == 'M' else 'M'); s.vline(x + w - 1, y, h, 'W'); s.hline(x, y + h - 1, w, 'W')
    s.vline(x + w // 2, y + 1, h - 2, 'E')

def rack(c, x, y0, n=3, right=False):
    """a parts rack: n shelves of crates and spare pods on a frame (left rack: crates; right rack: spare pods and a charge cell)."""
    s = c.s; w = 10
    plate(s, x, y0, w, 36, True, 'M', 'S', 'W')
    for k in range(n):
        sy = y0 + 2 + k * 11
        recess(s, x + 1, sy, w - 2, 10, 'E', 'D')
        s.hline(x + 1, sy + 9, w - 2, 'M')                                   # the shelf lip
        if not right:
            crate(s, x + 1, sy + 4, 4, 5); crate(s, x + 5, sy + 5 - (k % 2), 3, 4 + (k % 2), 'M' if k != 1 else 'S')
            if k == 1: s.put(x + 2, sy + 6, '2')                              # a crate of drone parts, its tag lit in the family colour
        else:
            for px_ in (x + 2, x + 5):                                        # spare pods hung on the bar
                if k == 2 and px_ == x + 5:
                    bev(s, px_, sy + 2, 3, 7, 'M', 'S', 'W', cham=True); s.hline(px_ + 1, sy + 4, 1, '5'); s.put(px_ + 1, sy + 4, '5')   # a charge cell
                    continue
                tube(s, px_, sy + 2, 2, 6, 'MS'); s.hline(px_, sy + 7, 2, 'E'); s.put(px_, sy + 2, 'L')
            s.hline(x + 1, sy + 1, w - 2, 'W')
    bolt_row(s, [(x + 1, y0 + 1), (x + w - 2, y0 + 1), (x + 1, y0 + 34), (x + w - 2, y0 + 34)], 'L')

def pit(c, y0):
    """the hangar pit: a sunken deck between the racks, the launch mouth at its head with family guide lamps."""
    s = c.s
    recess(s, 13, y0 + 1, 22, 41, 'D', 'K')
    for y in range(y0 + 6, y0 + 41, 6): s.hline(14, y, 20, 'E')            # deck seams
    s.rect(15, y0 + 1, 18, 3, 'K'); s.hline(15, y0 + 4, 18, 'E')            # the launch mouth into the wall
    for x in (14, 33):
        s.put(x, y0 + 2, '3' if c.st.powered and not (c.st.bstate == 'launch' and (c.st.i + x) % 2) else ('1' if c.st.powered else 'E'))
        if c.st.powered: c.lightglow(x, y0 + 2, 3.0, 0.55)

def rails(c, y0):
    """the launch rail: two lit rails on sleepers from the cradle's rest up into the mouth."""
    s = c.s
    for y in range(y0 + 5, y0 + 41, 3): s.hline(RX - 3, y, 6, 'W')         # sleepers
    for x, t in ((RX - 4, 'M'), (RX + 3, 'S')):
        s.vline(x, y0 + 4, 37, t); s.vline(x + (1 if x < RX else -1), y0 + 4, 37, 'W')
        s.put(x, y0 + 4, 'L')
    if c.line == 'scrap': hazard(s, RX - 3, y0 + 39, 6, 2)
    elif c.line == 'neon':
        s.vline(RX - 4, y0 + 6, 33, 'c')

def cradle(c, cy):
    """the cradle at pivot height cy: a sled across the rails, two arms up the sides, clamp jaws on the drone's pods (open while launching)."""
    s = c.s
    bev(s, RX - 10, cy + 6, 20, 4, 'L', 'M', 'S', cham=True)                 # the sled
    s.hline(RX - 8, cy + 8, 16, 'W'); s.put(RX - 9, cy + 7, '5'); c.lightglow(RX - 9, cy + 7, 2.2, 0.35, gm.RGB_LAMP[c.line])
    for sd in (-1, 1):
        x = RX - 11 if sd < 0 else RX + 9
        bev(s, x, cy - 3, 2, 11, 'M' if sd < 0 else 'S', 'S' if sd < 0 else 'W', 'W', cham=False)
    return [(RX - 11, cy - 3), (RX + 9, cy - 3)]

def jaws(c, cy, closed):
    """the clamp hooks at the top of the cradle's arms, over the pods' front caps: shut on a loaded drone, swung out to launch."""
    s = c.s
    for sd in (-1, 1):
        x = RX - 11 if sd < 0 else RX + 9
        s.rect(x, cy - 5, 2, 3, 'M' if sd < 0 else 'S'); s.put(x, cy - 5, 'L' if sd < 0 else 'M')
        if closed: s.hline(x + 2 if sd < 0 else x - 2, cy - 4, 2, 'M' if sd < 0 else 'S'); s.hline(x + 2 if sd < 0 else x - 2, cy - 3, 2, 'W')
        else: s.put(x - 1 if sd < 0 else x + 2, cy - 6, 'M')

def status_strip(c, y, n=5):
    """the family status strip at the foot: on = lit, launch = a chase, out = the re-arm counting up, damaged = a dead cell."""
    s = c.s; st = c.st
    x0 = RX - (n * 4) // 2
    recess(s, x0 - 2, y - 1, n * 4 + 3, 4, 'D', 'K')
    for k in range(n):
        if not st.powered: lit = False
        elif st.bstate == 'launch': lit = k == (n - 1 - st.i) or k == (n - 1 - st.i - 1)
        elif st.bstate == 'out': lit = k < 1 + st.i * 2
        elif st.state == 'damaged': lit = k != 3
        else: lit = True
        s.hline(x0 + k * 4, y, 3, '3' if lit else 'E'); s.hline(x0 + k * 4, y + 1, 3, '2' if lit else 'D')
        if lit: s.put(x0 + k * 4, y, '4'); c.lightglow(x0 + k * 4 + 1.5, y + 1, 3.0, 0.45, sx=1.4)

class Bay:
    """the drone bay in a line, its strip and lamps in the family of the loaded kit."""
    def __init__(s, line='standard', fam='pulse'):
        s.line, s.fam = line, fam
        s.look = Look(line, fam)
    def inside(s, state='on', i=0, drone=None):
        """-> (sprite, glow, cradle pivot or None). drone: a Drone drawn in the cradle (the loaded kit), its own glow added."""
        st = BSt(state, i)
        c = Ctx(BW, BH, s.look, st); y0 = FLANGE
        sp = c.s
        plate(sp, 1, y0, BW - 2, BH - y0 - 1, True, 'M', 'S', 'W')
        rack(c, 2, y0 + 3); rack(c, BW - 12, y0 + 3, right=True)
        pit(c, y0); rails(c, y0)
        up = LAUNCH[i] if state == 'launch' else 0
        cy = y0 + REST - FLANGE - up
        holding = drone is not None and not (state == 'out' or (state == 'launch' and i == 3))
        cradle(c, cy)
        sp.rect(0, y0 + 41, 4, 4, 'q'); sp.hline(0, y0 + 41, 4, 'Q'); sp.hline(0, y0 + 44, 4, 'n')     # the cable stub (power in) at the left edge
        bev(sp, 3, y0 + 39, 6, 8, 'M', 'S', 'W', cham=False); sp.put(5, y0 + 41, '5')
        status_strip(c, y0 + 43)
        stencil(sp, BW - 12, y0 + 44, (2, 3, 2))
        if s.line == 'scrap':
            rust_over(sp, BW - 12, y0 + 25, 10, 12); hazard(sp, 3, y0 + 1, 8, 2); weld(sp, 14, y0 + 44, 7)
            bev(sp, 4, y0 + 15, 6, 5, 'S', 'W', 'E', cham=False); sp.put(5, y0 + 16, 'M'); sp.put(8, y0 + 18, 'M')     # a mismatched patch on the left rack
        elif s.line == 'neon':
            sp.hline(3, y0 + 1, BW - 6, 'c'); sp.vline(13, y0 + 6, 34, 'c'); sp.vline(34, y0 + 6, 34, 'c')
        gm.flange(c, 0, BW, up=False)
        # damage, by place: a shelf down and its crates spilled, a crack across the deck, a spark from the mouth; disabled: dark, the cradle knocked askew
        c.hurts.append(gm.hurt_base(cracks=[[(16, y0 + 12), (19, y0 + 16), (17, y0 + 21), (20, y0 + 25)]], sparks=[(15, y0 + 4), (BW - 6, y0 + 20)],
                                    wires=[[(BW - 11, y0 + 14), (BW - 9, y0 + 17), (BW - 8, y0 + 18)]]))
        c.hurts.append(lambda s_, c_: move(s_, 3, y0 + 16, 8, 7, 1, 3))
        c.wrecks.append(gm.wreck_base(cracks=[[(15, y0 + 8), (19, y0 + 15), (16, y0 + 22), (21, y0 + 30), (18, y0 + 38)], [(BW - 10, y0 + 6), (BW - 8, y0 + 12)]],
                                      dents=[(4, y0 + 26, 6, 5), (BW - 10, y0 + 30, 5, 5)], soots=[(26, y0 + 10, 0), (6, y0 + 4, 2), (BW - 14, y0 + 38, 1)],
                                      wires=[[(BW - 11, y0 + 14), (BW - 9, y0 + 18), (BW - 7, y0 + 21)]], sparks=[(16, y0 + 5), (30, y0 + 40)]))
        c.wrecks.append(lambda s_, c_: move(s_, RX - 11, cy - 4, 23, 15, 2, 1))
        out = gm.finish(c, shadow=False)
        g = gm.glow_layer(c, GP)
        piv = None
        if holding:
            d_spr, d_g, _ = drone.frame('idle', i if state == 'on' else 0)
            if not st.powered: d_spr = d_spr.sub(gm.DARKX); d_g = None
            if st.dmg == 2: d_spr = d_spr.sub(gm.DARKX)                          # disabled: the kit sits dark in the cradle, knocked askew with it
            sx, sy = (2, 1) if st.dmg == 2 else (0, 0)
            piv = (RX, cy)
            clip = y0 + 4 if state == 'launch' else -99                       # the part already in the wall is hidden
            for yy in range(d_spr.h):
                for xx in range(d_spr.w):
                    ch = d_spr.g[yy][xx]
                    if ch == '.': continue
                    X, Y = RX - DC + xx + sx, cy - DC + yy + sy
                    if Y < clip: continue
                    out.put(X, Y, ch)
            if d_g is not None:
                for yy in range(d_g.h):
                    for xx in range(d_g.w):
                        p = d_g.p[yy][xx]
                        if p[3] and cy - DC + yy - GP >= clip: g.over(RX - DC + xx, cy - DC + yy, tuple(p))     # both glows are padded by GP
        if drone is not None:                                                  # the clamp jaws over the drone's pods
            j = Ctx(BW, BH, s.look, st); jaws(j, cy, holding and not (state == 'launch' and i > 0))
            js = j.s.sub(s.look.sub(st)); outline_all(js)
            if st.dmg == 2: js = js.sub(gm.DARKX)
            for yy in range(BH):
                for xx in range(BW):
                    if js.g[yy][xx] != '.' and st.dmg < 2: out.g[yy][xx] = js.g[yy][xx]
        return out, g, piv
    def outside(s, state='on', i=0):
        """the hatch: two door leaves over the launch well, sliding into the side housings when it opens (open 0-2)."""
        st = BSt(state, i)
        c = Ctx(OW, OH, s.look, st); sp = c.s; H = 16
        plate(sp, 1, 1, OW - 2, H, True, 'M', 'S', 'W')
        for x in (2, OW - 12): bev(sp, x, 2, 10, H - 3, 'L', 'M', 'S', cham=False)         # the door housings
        recess(sp, 12, 2, 24, H - 3, 'K', 'K')                                # the well
        sp.hline(13, H - 2, 22, 'E')
        for x in range(14, 35, 4): sp.put(x, H - 3, 'D')                      # the rail mouth deep in the well
        sp.vline(RX - 4, 4, H - 7, 'W'); sp.vline(RX + 3, 4, H - 7, 'W')
        openf = {0: 0.25, 1: 0.6, 2: 1.0}[i] if state == 'open' else 0.0
        leaf = int(round(12 * (1 - openf)))                                   # each leaf's width over the well
        for sd in (-1, 1):
            if leaf <= 0: continue
            x = 12 if sd < 0 else 36 - leaf
            bev(sp, x, 3, leaf, H - 5, 'M' if sd < 0 else 'S', 'S', 'W', cham=False)
            for k in range(min(3, leaf)):                                     # amber chevrons on the leading edges
                xx = x + leaf - 1 - k if sd < 0 else x + k
                for yy in range(4, H - 3): sp.put(xx, yy, 'a' if ((yy + (k if sd < 0 else -k)) // 2) % 2 == 0 else 'D')
            if leaf > 5:
                bx = x + 1 if sd < 0 else x + 3
                sp.hline(bx, 7, leaf - 4, 'W'); sp.hline(bx, 8, leaf - 4, 'M')    # a stiffener rib across the leaf
                sp.put(x + (1 if sd < 0 else leaf - 2), 4, 'L'); sp.put(x + (1 if sd < 0 else leaf - 2), H - 5, 'L')
        if state != 'open': sp.vline(RX - 0, 3, H - 5, 'K')                  # the seam where the leaves meet
        lamp = st.powered and not st.blink
        for x in (11, 36):                                                    # the family guide lamps at the well's sides
            sp.put(x, 4, '3' if lamp else ('1' if st.powered else 'E')); sp.put(x, H - 4, '3' if (lamp or state == 'open') else ('1' if st.powered else 'E'))
            if st.powered: c.lightglow(x, 4, 3.0, 0.5 if lamp else 0.2); c.lightglow(x, H - 4, 3.0, 0.5)
        if state == 'open' and st.powered:                                    # the well lit from below while it opens
            c.lightglow(RX, H - 4, 8 * openf + 2, 0.35 * openf, sx=1.6)
        for (bx, by) in ((4, 4), (OW - 5, 4), (4, H - 4), (OW - 5, H - 4)): sp.put(bx, by, 'L')
        sp.put(7, 9, '5'); c.lightglow(7, 9, 2.4, 0.35, gm.RGB_LAMP[s.line])
        stencil(sp, OW - 10, 9, (2, 2))
        if s.line == 'scrap': rust_over(sp, OW - 12, 2, 10, 6); weld(sp, 3, H - 2, 8)
        elif s.line == 'neon': sp.hline(3, 1, OW - 6, 'c')
        gm.flange(c, OH - FLANGE - 1, OW)
        c.hurts.append(gm.hurt_base(cracks=[[(OW - 9, 3), (OW - 8, 7), (OW - 10, 11)]], sparks=[(9, 6), (OW - 6, 10)], flap=(OW - 11, 2)))
        c.hurts.append(lambda s_, c_: soot(s_, 14, 4, 1))
        c.wrecks.append(gm.wreck_base(dents=[(4, 5, 5, 5), (OW - 9, 6, 5, 5), (16, 6, 5, 4)], soots=[(20, 3, 0), (6, 2, 2), (OW - 14, 8, 1)],
                                      cracks=[[(7, 3), (8, 8), (6, 12)]], sparks=[(OW - 7, 6), (14, 11)]))
        return gm.finish(c, shadow=False), gm.glow_layer(c, GP), None

BAYS = {ln: Bay(ln) for ln in ('scrap', 'standard', 'neon')}

# ================================================================== THE BOARDING ROBOT (DRONES.md 6 and 8): a crew rig (art/README.md "Crew"), the normal kind
# 33 x 33, pivot (16, 16), every layer faces UP. It is the repair drone (PersonDrawer.draw_drone: a round body, two side pods, one arm with a claw,
# one lens) grown heavy for boarding: the round body armoured, the two side pods turned into TREADS (the legs layer: the links run with the walk
# frames), the claw arm kept on the left and a tool arm on the right, the lens in the family colour. Mk I is the drill robot (amber), Mk II the
# shock robot (two prong arms with blue arcs between them), Mk III the drill robot under heavier plating. Outfit letters A/B/C on the shoulder plates
# take the owner's colour (the tint mask), so a robot reads as ours or theirs. Arms: `unarmed` (the tool held back), `melee` (the strike) and
# `melee_2` (the strike's second frame: the drill turned, the arc moved); no item is ever held, so the item mounts are the human's, unused.
from sp_common import Species, shade_gen, glow_px_max, spr_pts, pose_anchors
from sp_races2 import poly, merge, line as sline, ng, limb
import crew_v2 as cv2
RN, RC = 33, 16

def fam_sub(fam):
    """the role letters 1-4 -> the family's palette letters (a rig has no Look pass)."""
    return dict(zip('1234', gm.FAMILY[fam][0]))

def tread_unit(s, x, y, w, h, k, heavy=False):
    """one tread seen from above: a dark track with link plates that run back as the frames advance (k), rounded ends, a lit outer edge."""
    for j in range(h):
        for i in range(w):
            end = (j == 0 or j == h - 1) and (i == 0 or i == w - 1)
            if end: continue
            link = (j + k) % 3 == 0
            s.put(x + i, y + j, 'W' if link else 'E')
    s.vline(x, y + 1, h - 2, 'S'); s.vline(x + w - 1, y + 1, h - 2, 'D')
    for j in range(1, h - 1):
        if (j + k) % 3 == 0: s.put(x, y + j, 'M')
    s.hline(x + 1, y, w - 2, 'S'); s.hline(x + 1, y + h - 1, w - 2, 'D')
    if heavy:                                                                 # Mk III: an armour skirt over the track's outer half, bolted (the links show inside)
        sx = x if x < RC else x + w - 4
        bev(s, sx, y + 1, 4, h - 2, 'L' if x < RC else 'M', 'M' if x < RC else 'S', 'W', cham=True)
        for j in range(y + 3, y + h - 2, 4): s.put(sx + (1 if x < RC else 2), j, 'W')

def robot_legs(k, heavy=False):
    s = Spr(RN, RN)
    w = 5 if not heavy else 6
    for x in ((6, 22) if not heavy else (5, 22)):
        tread_unit(s, x, 7, w, 19, k, heavy)
    return s

def robot_torso(fam, mk):
    s = Spr(RN, RN)
    t = Spr(RN, RN)
    if mk == 3:                                                               # Mk III: an octagonal armour collar under the dome
        gm.oct_disc(t, RC, RC + 1, 19, 'S', 'M', 'W')
        merge(s, t)
        for (x, y) in ((RC - 7, RC - 5), (RC + 7, RC - 5), (RC - 7, RC + 7), (RC + 7, RC + 7)): s.put(x, y, 'L')
    disc(s, RC, RC + 1, 7.6, ('L', 'M', 'M', 'S', 'S', 'S', 'W', 'E'))      # the round body (the repair drone's, armoured)
    ringpx(s, RC + .5, RC + 1.5, 5.6, 6.5, 'W')                              # the seam ring
    for (x, y) in ((RC - 5, RC - 2), (RC + 5, RC - 2), (RC - 5, RC + 5), (RC + 5, RC + 5)): s.put(x, y, 'L' if x < RC else 'M')
    bev(s, RC - 4, RC + 6, 9, 4, 'M', 'S', 'W', cham=True)                    # the power pack at the back, two lamps
    s.hline(RC - 2, RC + 7, 5, 'D'); s.put(RC - 2, RC + 7, '2'); s.put(RC + 2, RC + 7, '2')
    for x in range(RC - 3, RC + 4, 2): s.put(x, RC + 9, 'E')                 # the vent at the back (the repair drone's)
    if mk == 3:                                                               # Mk III: bolted armour plates over the flanks and the rear
        for sd in (-1, 1):
            p = Spr(RN, RN); poly(p, [(RC + sd * 4, RC - 5), (RC + sd * 7, RC - 3), (RC + sd * 7, RC + 4), (RC + sd * 4, RC + 6)], 'S')
            merge(s, shade_gen(p, 'S', 'L' if sd < 0 else 'M', 'W'))
            for y in (RC - 2, RC + 3): s.put(RC + sd * 6, y, 'L' if sd < 0 else 'M')
        bev(s, RC - 5, RC + 8, 11, 3, 'M', 'S', 'W', cham=True)
    for sd in (-1, 1):                                                        # the shoulder plates: the owner's colour (tint mask)
        x0 = RC - 9 if sd < 0 else RC + 6
        p = Spr(RN, RN); p.rect(x0, RC - 3, 4, 7, 'B'); merge(s, cv2.shade_edges(p))
        s.put(x0 + (1 if sd < 0 else 2), RC - 2, 'L' if sd < 0 else 'M'); s.put(x0 + (1 if sd < 0 else 2), RC + 2, 'W')
    if fam != 'ion':                                                          # the drill robot: a bolted bumper bar across the back with hazard tape
        for x in range(RC - 6, RC + 7): s.put(x, RC + 6, 'a' if ((x - RC) // 2) % 2 == 0 else 'D')
    else:                                                                     # the shock robot: insulator ribs and a coil band
        for x in range(RC - 4, RC + 5, 2): s.put(x, RC - 6, 'C'); s.put(x + 1, RC - 6, 'B')
        sline(s, (RC - 6, RC + 3), (RC - 3, RC + 6), 'b')
    return s.sub(fam_sub(fam))

def robot_head(fam, mk):
    """the sensor head on the body's front: a low armoured dome round ONE big lens in the family colour (the repair drone's eye)."""
    s = Spr(RN, RN)
    disc(s, RC, RC - 2, 3.6, ('L', 'M', 'S', 'S', 'W', 'E'))
    stamp_ = ['.DDD.', 'D432D', 'D321D', 'D211D', '.DDD.']
    s.stamp(RC - 2, RC - 4, stamp_)
    s.put(RC + 3, RC - 5, 'W'); s.put(RC + 4, RC - 6, 'S'); s.put(RC + 4, RC - 7, '5')      # an antenna stub
    if mk == 3:                                                               # Mk III: a visor brow over the lens
        s.hline(RC - 3, RC - 6, 7, 'M'); s.hline(RC - 2, RC - 7, 5, 'L'); s.put(RC + 3, RC - 6, 'S')
    return s.sub(dict(fam_sub(fam), **{'5': 'g'}))

def drill_cone(s, cx, tip, w, k, heavy=False):
    """a drill pointing up: a cone from `w` px at its collar to a point, its flutes turned by k."""
    L = w + 3
    for j in range(L):
        hw = (j * w) // (2 * L)
        y = tip + j
        for x in range(cx - hw, cx + hw + 1):
            b = ((x - cx) + y + k) // 2 % 2
            lit = x <= cx
            s.put(x, y, ('L' if lit else 'S') if b else ('S' if lit else 'W'))
    s.put(cx, tip, 'L')
    s.hline(cx - w // 2 - 1, tip + L, w + 2, 'M'); s.hline(cx - w // 2 - 1, tip + L + 1, w + 2, 'W')     # the chuck
    if heavy: s.hline(cx - w // 2 - 1, tip + L + 2, w + 2, 'a'); s.put(cx - w // 2 - 1, tip + L + 2, 'D')

def clamp_arm(s, sh, hand, heavy=False):
    """the repair drone's arm and claw, heavier: a piston from the shoulder to a three-finger claw."""
    limb(s, sh, hand, 2 if not heavy else 3, 'W', 'S', 'E')
    x, y = hand
    s.rect(x - 1, y - 1, 3, 3, 'M'); s.put(x - 1, y - 1, 'L'); s.put(x + 1, y + 1, 'W')            # the wrist
    for dx in (-2, 0, 2): s.put(x + dx, y - 2, 'M'); s.put(x + dx, y - 3, 'S' if dx else 'M')
    s.put(x - 2, y - 4, 'S'); s.put(x + 2, y - 4, 'W')

def prong_arm(s, sh, hand, fwd):
    """the shock arm: an insulated arm ending in a two-tine prong, the tines' tips lit."""
    limb(s, sh, hand, 2, 'W', 'S', 'E')
    x, y = hand
    s.rect(x - 1, y - 1, 3, 3, 'B'); s.put(x - 1, y - 1, 'C'); s.put(x, y, 'N')                    # the insulator ring
    for dx in (-1, 1):
        s.vline(x + dx, y - 2 - fwd, fwd + 1, 'M' if dx < 0 else 'S')
        s.put(x + dx, y - 3 - fwd, 'c')

def arc(s, a, b, k):
    """a jagged arc between two prong tips (pixel art: white core, cyan, blue at its kinks); k moves the kinks."""
    n = max(abs(b[0] - a[0]), abs(b[1] - a[1]), 1)
    for i in range(n + 1):
        t = i / n
        x = a[0] + round((b[0] - a[0]) * t)
        y = a[1] + round((b[1] - a[1]) * t) + (((i + k) % 4) - 1 if 0 < i < n else 0) // 1 * (1 if (i + k) % 2 else -1)
        s.put(x, y, 'H' if (i + k) % 3 else 'c')
        if (i + k) % 4 == 0 and 0 < i < n: s.put(x, y + 1, 'b')

def robot_arms(fam, mk, pose):
    s = Spr(RN, RN)
    strike = pose in ('melee', 'melee_2'); k = 1 if pose == 'melee_2' else 0
    if fam == 'ion':                                                          # Mk II: two prong arms, an arc between the tips on the strike
        fwd = 3 if strike else 1
        hy = RC - 8 if strike else RC - 6
        for sd in (-1, 1):
            prong_arm(s, (RC + sd * 8, RC - 1), (RC + sd * (5 if strike else 7), hy), fwd)
        if strike: arc(s, (RC - 4, hy - 3 - fwd), (RC + 4, hy - 3 - fwd), k)
        return s
    heavy = mk == 3
    ch = (RC - 7, RC - 7) if not strike else (RC - 5, RC - 9)                 # the claw (the repair drone's, on the left): it reaches in to hold on the strike
    clamp_arm(s, (RC - 8, RC - 1), ch, heavy)
    hx, hy = (RC + 7, RC - 5 + (1 if heavy else 0)) if not strike else (RC + 4, RC - 6 + (2 if heavy else 0))   # the drill (right): held up at rest, swung in to the front on the strike
    limb(s, (RC + 8, RC), (hx, hy), 3 if heavy else 2, 'W', 'S', 'E')
    mw = 7 if heavy else 5
    x0 = hx - mw // 2                                                         # the drill motor: steel with a band of hazard amber
    s.hline(x0, hy - 1, mw, 'M'); s.put(x0, hy - 1, 'L'); s.hline(x0, hy, mw, 'a'); s.put(x0 + mw - 1, hy, 'u')
    s.hline(x0, hy + 1, mw, 'S'); s.hline(x0, hy + 2, mw, 'W'); s.put(x0, hy + 1, 'M')
    w = 6 if heavy else 4
    drill_cone(s, hx, hy - (w + 3) - 3, w, k, heavy)
    if pose == 'melee_2': spark(s, hx + 1, hy - w - 5, False)
    return s

def robot_glow(fam, mk, layer, pose=None):
    rgb = gm.FAMILY[fam][1]
    if layer == 'head':
        out = []
        for f in (0, 1):
            g = ng(RN); glow_px_max(g, [(RC, RC - 2), (RC - 1, RC - 3)], rgb, (0.85, 0.55)[f], (4.6, 3.6)[f], 1.4)
            glow_px_max(g, [(RC - 1, RC - 3)], (244, 246, 248), (0.45, 0.3)[f], 2.0, 1.2); out.append(g)
        return out
    if layer == 'torso':
        g = ng(RN); glow_px_max(g, [(RC - 2, RC + 7), (RC + 2, RC + 7)], rgb, 0.55, 2.4, 1.4); return [g]
    if layer == 'arms' and fam == 'ion' and pose in ('melee', 'melee_2'):
        g = ng(RN); a = robot_arms(fam, mk, pose)
        glow_px_max(g, spr_pts(a, 'Hc'), (110, 220, 255), 0.75, 3.2, 1.4); return [g]
    if layer == 'arms' and fam == 'ion':
        g = ng(RN); glow_px_max(g, [(RC - 5, RC - 9), (RC + 5, RC - 9)], (110, 220, 255), 0.5, 2.4, 1.4); return [g]
    return None

class Robot(Species):
    """the boarding robot rig, Mk I / II / III (see above)."""
    N = RN; C = RC
    walk_fps = 8
    head_names = ['lens']
    POSES = ['unarmed', 'melee', 'melee_2']
    def __init__(self, mk=1):
        self.mk = mk; self.fam = 'ion' if mk == 2 else 'boarder'
        self.id = 'boarding_robot_mk%d' % mk
        self.notes = ['', 'Boarding robot Mk I: the drill robot.', 'Boarding robot Mk II: the shock robot.', 'Boarding robot Mk III: the drill robot, heavier plating.'][mk]
    def legs(self): return [cv2.outlined(robot_legs(k, self.mk == 3)) for k in range(6)] + [cv2.outlined(robot_legs(0, self.mk == 3))]
    def torso(self): return cv2.outlined(robot_torso(self.fam, self.mk))
    def arms(self, pose): return cv2.outlined(robot_arms(self.fam, self.mk, pose))
    def head(self, name): return cv2.outlined(robot_head(self.fam, self.mk))
    def torso_anchors(self): return {'head': [RC, RC - 2], 'back': [RC, RC + 8], 'shoulder_l': [RC - 8, RC - 1], 'shoulder_r': [RC + 8, RC - 1]}
    def arm_anchors(self):
        a = pose_anchors((RC - 8, RC - 7), (RC + 7, RC - 6))
        return {p: a['melee' if p != 'unarmed' else 'unarmed'] for p in self.POSES}
    def torso_glow(self): return robot_glow(self.fam, self.mk, 'torso')
    def head_glow(self): return robot_glow(self.fam, self.mk, 'head')
    def arms_glow(self, pose): return robot_glow(self.fam, self.mk, 'arms', pose)

ROBOTS = [Robot(1), Robot(2), Robot(3)]
