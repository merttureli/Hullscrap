"""Gun modules (docs/GUNS.md sections 3 and 7): hand-drawn bases, barrels and breeches that a recipe composes into a gun.

A module paints neutral STANDARD steel (L M S W E D) plus role letters, and the gun's Look recolours the result in one pass:
  '1' '2' '3' '4'  the family light (dark, mid, bright, hot): lenses, rings, lamps (GUNS.md section 4);
  '5' '6'          the line accents (lamp, second accent): standard green / amber, scrap amber / rust, neon cyan / magenta;
  '7' '8'          the race livery accents (dark, light): steel until a race version gives them colours;
  '9'              the line's edge highlight on rings and caps: standard steel light, scrap steel, neon cyan.
The steel itself follows the line: standard as drawn, scrap duller, neon navy. Line trims that need a place of their own
(rust plates, hazard tape, cyan edges) are drawn by each module through `trim_*`, so the same recipe reads in all three lines.

Outward is UP everywhere. Bases (`_out` halves) are W x (cells*16 + FLANGE): the bottom 4 px are the flange over the wall face.
Barrels are their own sprites drawn pointing up, with `pivot` and `muzzle` anchors; a base lists one pivot per barrel.
Breeches (inside halves) are W x (cells*16 + FLANGE) with the flange on top. Damage is drawn per module, never one stamp:
damaged = cracks, a loose part, a spark; disabled = dark, scorched and dented (outside halves are never shattered)."""
import math, os, re
import pal_lines                                          # navy panels and the neon letters (N I J j C B P), registered on import
from px import *
from px import ART
from mach import bev, recess, outline_all, drop_shadow, glow
from comp_base import chamfer_fill, rim, DARK
from wbase import cylv, ramp_rows, hazard, weld, crack, spark, wire, move, soot, dent, FLANGE
from lines_kit import circle, ring as ringpx

# ------------------------------------------------------------------ palette: no new colours, two private letters for hexes already in palette.gpl
ALIAS = {'%': '3a9a7e', '&': '8cf0c4'}                     # PD green shade (the mire teal-green), PD green bright (the tractor mint)
def _gpl_hexes():
    try: return {l.split('#')[1].split()[0] for l in open(os.path.join(ART, 'palette.gpl')) if re.match(r'\s*\d+\s+\d+\s+\d+\s+#', l)}
    except OSError: return set()
_HEX = _gpl_hexes()
for k, h in ALIAS.items():
    assert not _HEX or h in _HEX, (k, h)                  # an alias never adds a colour
    RGB[k] = tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))

# ------------------------------------------------------------------ families (GUNS.md section 4): the light pixels and the glow
#            light ramp: dark, mid, bright, hot     glow rgb          flash core rgb
FAMILY = {
 'laser':   (('e', 'r', 'o', 'H'), (240, 62, 40),  (255, 200, 160)),
 'pulse':   (('u', 'o', 'y', 'H'), (255, 124, 16), (255, 226, 140)),
 'ion':     (('B', 'C', 'c', 'H'), (60, 230, 255), (210, 250, 255)),
 'flak':    (('n', 'a', 'y', 'H'), (226, 168, 54), (255, 236, 170)),
 'missile': (('r', 'L', 'H', 'H'), (255, 214, 200), (255, 250, 245)),
 'beam':    (('n', 'P', 'r', 'H'), (214, 22, 72),  (255, 170, 190)),
 'slug':    (('W', 'y', 'H', 'H'), (255, 238, 140), (255, 252, 230)),
 'pd':      (('%', 'g', '&', 'H'), (110, 220, 90), (220, 255, 210)),
}
FAMILIES = list(FAMILY)
#            steel remap                                                   lamp  accent  edge
LINE = {
 'standard': ({},                                                          'g', 'a', 'L'),
 'scrap':    ({'L': 'M'},                                                  'a', 'u', 'M'),
 'neon':     ({'L': 'j', 'M': 'j', 'S': 'J', 'W': 'I', 'E': 'I', 'D': 'N'}, 'c', 'm', 'c'),
}
LINES = ['scrap', 'standard', 'neon']
DARKX = dict(DARK, **{'j': 'J', 'J': 'I', 'I': 'N', 'N': 'N', 'C': 'B', 'B': 'N', 'P': 'n', 'e': 'n', '%': 'E', '&': 'E', 'n': 'n'})

class St:
    """what one frame shows. state: on, off, damaged, disabled (bases); idle, fire, spin, charge, damaged, disabled (barrels)."""
    def __init__(s, state='on', i=0, lit=None):
        s.state, s.i = state, i
        s.dmg = {'damaged': 1, 'disabled': 2}.get(state, 0)
        s.powered = state not in ('off', 'disabled')
        s.fire = state == 'fire'
        s.rc = (2, 1, 0)[i] if s.fire else 0              # recoil: the barrel slides back 2 px, then 1, then home
        s.lit = lit                                        # charge rings lit (0..3), chain step (0..3)
        s.blink = state in ('on', 'idle', 'spin', 'charge') and i % 2 == 1

class Look:
    """line + family (+ livery later): the one-pass recolour of a module's role letters."""
    def __init__(s, line='standard', fam='laser', livery=None):
        s.line, s.fam, s.livery = line, fam, livery
        s.steel, s.lamp, s.acc, s.edge = LINE[line]
        s.cols, s.rgb, s.core = FAMILY[fam]
    def hi(s): return s.steel.get('M', 'M')
    def sub(s, st):
        m = dict(s.steel)
        lit = st.powered
        dead = (s.steel.get('D', 'D'), s.steel.get('E', 'E'), s.steel.get('E', 'E'), s.steel.get('W', 'W'))
        for k, c in zip('1234', s.cols if lit else dead): m[k] = c
        m['5'] = s.lamp if lit else s.steel.get('E', 'E')
        m['6'] = s.acc
        m['9'] = s.edge
        liv = s.livery or (s.steel.get('W', 'W'), s.steel.get('M', 'M'))
        m['7'], m['8'] = liv
        return m

class Ctx:
    """a canvas a recipe's modules paint into, plus what they register: glow points, damage hooks, barrel pivots."""
    def __init__(s, w, h, look, st):
        s.s = Spr(w, h); s.w, s.h = w, h; s.look, s.st = look, st
        s.glows = []          # (x, y, r, strength, rgb or None = family)
        s.hurts = []          # fn(spr, ctx) for damaged
        s.wrecks = []         # fn(spr, ctx) for disabled (after the dark pass)
        s.pivots = []         # barrel pivots on a base
        s.muzzles = []        # muzzle points on a barrel
        s.tip = None          # (x, top, width) of the last tube, for add-ons at the muzzle
        s.g = None
    @property
    def line(s): return s.look.line
    def lightglow(s, x, y, r=3.5, a=0.45, rgb=None, sx=1.0): s.glows.append((x, y, r, a, rgb, sx))

def finish(c, shadow=True):
    """recolour, damage, outline, shadow: the end of every module stack."""
    st = c.st
    s = c.s.sub(c.look.sub(st))
    if st.dmg == 1:
        for f in c.hurts: f(s, c)
    elif st.dmg == 2:
        s = s.sub(DARKX)
        for f in c.wrecks: f(s, c)
    s = s.copy(); outline_all(s)
    return drop_shadow(s) if shadow else s

def glow_layer(c, pad, extra=None):
    """the soft glow strip frame of a canvas: its registered lights (none when off or disabled), damaged flickers."""
    g = Rgba(c.w + 2 * pad, c.h + 2 * pad)
    st = c.st
    if not st.powered: return g
    for (x, y, r, a, rgb, sx) in c.glows:
        glow(g, pad + x + 0.5, pad + y + 0.5, r, rgb or c.look.rgb, a, 2.0, sx=sx)
    if extra: extra(g, pad)
    if st.dmg == 1:
        for row in g.p:
            for q in row: q[3] = int(q[3] * (0.5 if st.i % 2 else 0.8))
    return g

# ------------------------------------------------------------------ drawing helpers (outward is up, light from the top-left)
def plate(s, x, y, w, h, cham=True, hi='M', mid='S', lo='W'):
    bev(s, x, y, w, h, hi, mid, lo, cham=cham)

def tube(s, x, y, w, h, ramp='LMMSSSSWWE'):
    """a vertical cylinder lit from the left."""
    cylv(s, x, y, w, h, ramp)

def band(s, x, y, w, h=3):
    """a clamp ring across a vertical tube (wider than it): lit top and left, dark bottom and right."""
    s.rect(x, y, w, h, 'M'); s.hline(x, y, w, '9'); s.vline(x, y, h, 'L')
    s.hline(x, y + h - 1, w, 'W'); s.vline(x + w - 1, y, h, 'S'); s.put(x, y + h - 1, 'S')

def fam_ring(s, x, y, w, h=3, on=True):
    """a ring in the family light: bright top row, mid, dark bottom row (dead steel when not lit)."""
    if on:
        s.rect(x, y, w, h, '2'); s.hline(x, y, w, '3'); s.hline(x, y + h - 1, w, '1')
        s.put(x + 1, y, '4'); s.vline(x + w - 1, y, h, '1')
    else:
        s.rect(x, y, w, h, 'E'); s.hline(x, y, w, 'W'); s.vline(x + w - 1, y, h, 'D')

def lens_up(s, x, y, w, h, mode):
    """the emitter at a muzzle, pointing up. mode: 'fire' (white hot), 'idle' (lit, ready), 'dead'."""
    if mode == 'dead':
        s.rect(x, y, w, h, 'E'); s.put(x, y, 'W'); return
    s.rect(x, y, w, h, '1'); s.rect(x, y, w, h - 1, '2'); s.hline(x + 1, y, w - 2, '3')
    if mode == 'fire':
        s.rect(x, y, w, h - 1, '3'); s.hline(x + 1, y, w - 2, '4')
    else: s.hline(x + w // 2 - (1 if w > 5 else 0), y, 2 if w > 5 else 1, '4')

def lamp_row(s, x, y, n, pitch=3, c='3', w=2):
    for k in range(n): s.hline(x + k * pitch, y, w, c)

def ready_strip(c, x, y, n, cw=3, pitch=5):
    """the family ready strip: n lit segments in a dark recess (the light pixels that carry the family on the base)."""
    s = c.s
    recess(s, x - 1, y - 1, n * pitch + 1, 4, 'D', 'K')
    for k in range(n):
        s.hline(x + k * pitch, y, cw, '3'); s.hline(x + k * pitch, y + 1, cw, '2'); s.put(x + k * pitch, y, '4')
        c.lightglow(x + k * pitch + cw / 2.0, y + 1, 3, 0.4)

RUST = {'L': 'Q', 'M': 'Q', 'S': 'u', 'W': 'n', 'E': 'n', 'D': 'n'}
def rust_over(s, x, y, w, h):
    """scrap: the steel of a panel turns to rust (its bevel, bolts and seams keep their place)."""
    for j in range(h):
        for i in range(w):
            ch = s.get(x + i, y + j)
            if ch in RUST: s.g[y + j][x + i] = RUST[ch]

def scrap_dress(c, rust=(), tape=(), patch=(), welds=()):
    """the scrap line on a base: rusted panels, hazard tape, a mismatched patch plate, weld seams."""
    if c.line != 'scrap': return
    s = c.s
    for r in rust: rust_over(s, *r)
    for (x, y, w, h) in tape: hazard(s, x, y, w, h)
    for (x, y, w, h) in patch:
        bev(s, x, y, w, h, 'S', 'W', 'E', cham=False)
        for (bx, by) in ((x + 1, y + 1), (x + w - 2, y + 1), (x + 1, y + h - 2), (x + w - 2, y + h - 2)): s.put(bx, by, 'M')
    for (x, y, n, v) in welds: weld(s, x, y, n, v)

def grille(s, x, y, w, h, step=2):
    """vent slots."""
    for j in range(0, h, step): s.hline(x, y + j, w, 'D'); s.hline(x, y + j + 1, w, 'W') if j + 1 < h else None

def box(s, x0, y0, x1, y1):
    return (max(0, x0), max(0, y0), min(s.w - 1, x1), min(s.h - 1, y1))

def oct_disc(s, cx, cy, d, mid='S', hi='M', lo='W'):
    """an octagon (chamfered square) disc lit from the top-left, centre (cx, cy) on a pixel."""
    r = d // 2
    chamfer_fill(s, cx - r, cy - r, d, d, mid, max(2, d // 3)); rim(s, mid, hi, lo, box(s, cx - r, cy - r, cx + r, cy + r))

def round_disc(s, cx, cy, r, ramp=('L', 'M', 'S', 'W', 'E')):
    """a shaded dome seen from above: concentric light falling to the bottom-right (cx, cy may be .5)."""
    for y in range(int(cy - r - 1), int(cy + r + 2)):
        for x in range(int(cx - r - 1), int(cx + r + 2)):
            dx, dy = x + .5 - cx, y + .5 - cy
            if dx * dx + dy * dy > r * r: continue
            lx, ly = dx + r * 0.45, dy + r * 0.45                     # distance from the highlight spot (top-left)
            t = (lx * lx + ly * ly) ** 0.5 / (r * 1.45)
            s.put(x, y, ramp[min(len(ramp) - 1, int(t * len(ramp)))])

def bolt_row(s, pts, c='L'):
    for (x, y) in pts: s.put(x, y, c)

def stencil(s, x, y, marks=(2, 3, 1, 2)):
    """the registry stencil: short dashes (livery dark, steel until a race version colours it)."""
    for m in marks:
        s.hline(x, y, m, '7'); x += m + 1

def channel(s, x, y, w, h):
    """the dark slot a barrel lies in."""
    s.rect(x, y, w, h, 'D'); s.hline(x, y, w, 'K')

# ------------------------------------------------------------------ line trims (drawn in final letters where a line needs its own pixels)
def trim_edge(c, x, y, w):
    """a long top edge: neon cyan line, scrap hazard tape, standard seams."""
    s = c.s
    if c.line == 'neon': s.hline(x, y, w, 'c')
    elif c.line == 'scrap': hazard(s, x, y, w, 2)

# ------------------------------------------------------------------ the flange (all bases and breeches): 4 px over the wall face
def flange(c, y, W, up=True):
    s = c.s
    bev(s, 1, y, W - 2, FLANGE + 1, 'M', 'S', 'W')
    xs = (4, W - 5) if W <= 40 else ((4, 13, W - 14, W - 5) if W <= 72 else tuple(range(4, W - 4, 16)) + (W - 5,))
    for x in xs: s.put(x, y + 2, 'L')
    if c.line == 'neon':
        s.hline(3, y + (1 if up else 3), W - 6, 'c')
    elif c.line == 'scrap':
        n = max(8, W // 3)
        for x in range(W // 2 - n // 2, W // 2 + n // 2): s.put(x, y + 2, 'a' if ((x - W // 2) // 2) % 2 == 0 else 'D')

# ------------------------------------------------------------------ damage vocabulary for bases (positions come from each module)
def hurt_base(cracks=(), sparks=(), flap=None, wires=()):
    def f(s, c):
        for pts in cracks: crack(s, pts, 'K', c.look.hi())
        for pts in wires: wire(s, pts)
        if flap: s.stamp(flap[0], flap[1], FLAP, {'S': c.look.steel.get('S', 'S'), 'M': c.look.hi()})
        if sparks: x, y = sparks[c.st.i % len(sparks)]; spark(s, x, y, False)
    return f

def wreck_base(cracks=(), dents=(), soots=(), wires=(), sparks=()):
    def f(s, c):
        for (x, y, k) in soots: soot(s, x, y, k)
        for (x, y, w, h) in dents: dent(s, x, y, w, h)
        for pts in cracks: crack(s, pts)
        for pts in wires: wire(s, pts)
        if sparks: x, y = sparks[c.st.i % len(sparks)]; spark(s, x, y, False)
    return f

FLAP = art("""
....SSM.
..SSMMS.
SSMMSS..
""")

# ================================================================== BASES (outside halves). Each takes (c, ...) and paints c.s; the flange is the gun's.
# ---- wing parts: what rides in a casemate's side slots (x, y, w, h). Tiers add parts (art bible rule 9).
def part_cells(c, x, y, w, h):
    """copper power cells and the line's power lamp."""
    s = c.s; plate(s, x, y, w, h)
    n = max(2, (w - 4) // 3)
    for k in range(n):
        cx = x + 2 + k * 3
        s.rect(cx, y + 2, 2, h - 4, 'q'); s.vline(cx, y + 2, h - 4, 'Q'); s.vline(cx + 1, y + 2, h - 4, 'n')
    s.rect(x, y + h // 2 - 2, 1, 4, 'D'); s.put(x, y + h // 2 - 1, '5'); s.put(x, y + h // 2, '5')
    c.lightglow(x, y + h // 2, 3, 0.4, RGB_LAMP[c.line])

def part_sensor(c, x, y, w, h, mast=True):
    """the sensor dome with the family eye, hazard ticks and an antenna mast."""
    s = c.s; plate(s, x, y, w, h)
    ex = x + w // 2 - 3
    s.stamp(ex, y + 3, art("""
.KKKK.
KDDDDK
KD3DDK
KD2DDK
KDDDDK
.KKKK.
"""))
    if c.st.powered and not c.st.blink: s.put(ex + 3, y + 5, '4')
    c.lightglow(ex + 2, y + 5, 4, 0.4)
    for hx in range(x + 3, x + w - 3, 4):
        for k in range(3): s.put(hx + k, y + h - 5 + k, '6'); s.put(hx + k + 1, y + h - 5 + k, 'D')
    if mast:
        s.rect(x + w - 6, y - 4, 3, 4, 'W'); s.vline(x + w - 6, y - 4, 4, 'M'); s.put(x + w - 5, y - 5, '3')
        c.lightglow(x + w - 5, y - 5, 2.5, 0.5)
    bolt_row(s, [(x + 2, y + 2), (x + w - 3, y + 2), (x + 2, y + h - 3)])

def part_caps(c, x, y, w, h):
    """steel capacitors with family bands (the Mk II accent)."""
    s = c.s; plate(s, x, y, w, h)
    for k in range(max(2, (w - 4) // 4)):
        cx = x + 3 + k * 4
        tube(s, cx, y + 2, 3, h - 4, 'LSW')
        s.hline(cx, y + h // 2 - 1, 3, 'E'); s.hline(cx, y + h // 2, 3, '2'); s.hline(cx, y + h // 2 + 1, 3, 'E')
        c.lightglow(cx + 1, y + h // 2, 2.5, 0.3)
    s.put(x, y + h // 2, '5')

def part_vent(c, x, y, w, h):
    """vents and the registry stencil, two masts."""
    s = c.s; plate(s, x, y, w, h)
    grille(s, x + 3, y + 4, w - 6, 6)
    s.rect(x + 3, y + h - 7, w - 6, 1, 'D')
    stencil(s, x + 3, y + h - 4, (3, 2, 3))
    for k, mx in enumerate((x + 3, x + w - 6)):
        s.rect(mx, y - 4, 3, 4, 'W'); s.vline(mx, y - 4, 4, 'M'); s.put(mx + 1, y - 5, '3' if k == 0 else '5')
    bolt_row(s, [(x + 1, y + 2), (x + w - 2, y + 2), (x + 1, y + h - 2), (x + w - 2, y + h - 2)])

def part_coolant(c, x, y, w, h):
    """Mk III machinery: a coolant tank with a gauge and a pipe loop."""
    s = c.s; plate(s, x, y, w, h)
    tube(s, x + 2, y + 2, w - 4, h - 7, 'LMSSWE')
    s.hline(x + 2, y + 2, w - 4, 'L'); s.hline(x + 2, y + h - 6, w - 4, 'W')
    s.rect(x + w // 2 - 2, y + 5, 4, 3, 'D'); s.hline(x + w // 2 - 1, y + 6, 2, '3'); c.lightglow(x + w // 2, y + 6, 3, 0.35)
    s.hline(x + 2, y + h - 4, w - 4, 'q'); s.hline(x + 2, y + h - 3, w - 4, 'n')

def part_drum(c, x, y, w, h):
    """an ammo drum (kinetic guns): a round drum in a cradle with the feed lamp."""
    s = c.s; plate(s, x, y, w, h)
    r = min(w, h) // 2 - 2
    round_disc(s, x + w / 2.0, y + h / 2.0, r + 0.5, ('M', 'S', 'S', 'W', 'E'))
    ringpx(s, x + w / 2.0, y + h / 2.0, r - 2.5, r - 1.5, 'W')
    s.put(int(x + w / 2.0), int(y + h / 2.0), 'L')
    s.put(x + 1, y + h - 3, '3'); c.lightglow(x + 1, y + h - 3, 2.5, 0.4)

PARTS = {'cells': part_cells, 'sensor': part_sensor, 'caps': part_caps, 'vent': part_vent, 'coolant': part_coolant, 'drum': part_drum}
RGB_LAMP = {'standard': (107, 211, 74), 'scrap': (225, 161, 54), 'neon': (60, 242, 255)}

def neon_edges(c, rects):
    if c.line != 'neon': return
    for (x, y, w, h) in rects:
        c.s.hline(x + 2, y, w - 4, 'c'); c.s.vline(x, y + 2, h - 4, 'c')

# ---- CASEMATE housings (fixed): 2, 4 and 6 cells wide. Rectangular, braced, the barrel in a sleeve.
def sleeve(c, cx, top, sw=22, sh=8, cw=14):
    """the sleeve at the outward end of a casemate block, with the barrel channel."""
    s = c.s
    plate(s, cx - sw // 2, top, sw, sh)
    channel(s, cx - cw // 2, top + 1, cw, sh - 2)
    s.put(cx - sw // 2 + 1, top + sh - 2, 'L'); s.put(cx + sw // 2 - 2, top + sh - 2, 'L')

def collar(c, cx, cy, w):
    """the gimbal collar across the block, with the pin."""
    s = c.s
    bev(s, cx - w // 2, cy - 3, w, 5, 'L', 'M', 'S', cham=False)
    s.put(cx, cy, 'L'); s.put(cx + 1, cy + 1, 'W'); s.put(cx - 1, cy, 'M')
    bolt_row(s, [(cx - w // 2 + 2, cy - 1), (cx + w // 2 - 3, cy - 1)])
    if c.line == 'neon': s.hline(cx - w // 2 + 1, cy - 3, w - 2, 'c')

def gusset(c, x, y, n, right=False):
    """a triangular brace between a wing and the block: the casemate's sloped armour."""
    s = c.s
    for k in range(n):
        for j in range(k + 1):
            xx = x + j if right else x - j
            s.put(xx, y - n + 1 + k, 'S' if j < k else ('M' if not right else 'W'))
    for k in range(n): s.put((x + k) if right else (x - k), y - n + 1 + k, 'W' if right else 'M')

def casemate4(c, parts=('cells', 'sensor'), cy=12, block=26, mk3=False):
    """the standard casemate (4x2): base pad into the flange, central block + sleeve + gimbal collar, gussets, two wings."""
    s = c.s; W = c.w
    plate(s, 6, cy + 8, W - 12, c.h - FLANGE - cy - 8)                       # base pad
    if c.line == 'neon': trim_edge(c, 8, cy + 8, W - 16)
    x0 = 32 - block // 2
    plate(s, x0, cy - 10, block, block)                                       # the block
    for k, (side, px) in enumerate(((0, 3), (1, W - 19))):
        PARTS[parts[k]](c, px, 6, 16, 18) if parts[k] else plate(s, px, 6, 16, 18)
        s.hline(px + 2, 6, 12, '8')                                           # the livery edge (steel light until a race version colours it)
    gusset(c, x0 - 1, 5, 4); gusset(c, x0 + block, 5, 4, True)
    sleeve(c, 32, cy - 11)
    collar(c, 32, cy, block + 2)
    s.rect(x0 + 4, cy + 6, block - 8, 1, 'D'); s.rect(x0 + 4, cy + 9, block - 8, 1, 'D')    # block seams
    stencil(s, x0 + 4, cy + 12, (3, 2))
    ready_strip(c, x0 + 4, cy + 14, 4)                                        # the family ready lights on the block foot
    if mk3:                                                                   # Mk III machinery: coolant lines into the block, sleeve cheeks
        for (px_, side) in ((x0 - 1, -1), (x0 + block, 1)):
            for k in range(6):
                x = px_ + side * (k // 2 + 1); y = 7 - k
                s.put(x, y + 2, 'Q'); s.put(x, y + 3, 'q'); s.put(x + side, y + 3, 'n')
        for sx in (32 - 14, 32 + 11): plate(s, sx, cy - 12, 3, 9, cham=False); s.put(sx + 1, cy - 10, 'L')
        lamp_row(s, x0 + 5, cy + 2, 4, 4, '3', 2)
    scrap_dress(c, rust=[(W - 19, 6, 16, 18)], tape=[(5, 20, 12, 3)], patch=[(x0 + 15, cy + 5, 8, 6)], welds=[(x0 + 2, cy + 4, 8, True), (10, cy + 10, 10, False)])
    neon_edges(c, [(3, 6, 16, 18), (W - 19, 6, 16, 18), (x0, cy - 10, block, 8)])
    c.pivots.append((32, cy))
    c.hurts.append(hurt_base(cracks=[[(W - 10, 6), (W - 11, 9), (W - 9, 11), (W - 12, 14), (W - 11, 17)], [(x0 + 5, cy - 3), (x0 + 7, cy), (x0 + 6, cy + 4), (x0 + 9, cy + 7)]],
                             sparks=[(10, 4), (W - 12, 13)], flap=(2, 5), wires=[[(10, 6), (12, 7), (14, 7)]]))
    c.wrecks.append(wreck_base(cracks=[[(x0 + 5, cy - 4), (x0 + 7, cy - 1), (x0 + 6, cy + 3), (x0 + 9, cy + 6), (x0 + 8, cy + 10)], [(W - 12, 7), (W - 11, 10), (W - 13, 14), (W - 10, 18)]],
                               dents=[(6, 16, 5, 6), (W - 15, 17, 6, 4)], soots=[(20, 3, 0), (W - 18, 5, 1), (8, 7, 2)],
                               wires=[[(10, 6), (12, 8), (13, 11)]], sparks=[(30, 6), (12, 12)]))

# ---- RING bases (turrets): a full ring, an octagon at 16 px a cell, on a chamfered seat.
def ring_well(c, cx, cy, d):
    """the turret ring: a raised octagon round a dark well, swivel ticks round it."""
    s = c.s; r = d // 2
    oct_disc(s, cx, cy, d, 'S', 'M', 'W')
    w = d - 4; q = w // 2
    chamfer_fill(s, cx - q, cy - q, w, w, 'E', max(2, w // 3)); rim(s, 'E', 'D', 'M', (cx - q, cy - q, cx + q, cy + q))
    for (x, y) in ((cx, cy - r + 1), (cx, cy + r - 1), (cx - r + 1, cy), (cx + r - 1, cy)): s.put(x, y, 'L')

def ring_base(c, cells=2, parts=None):
    """ring base, 2 or 3 cells: a chamfered seat with the octagon ring, swivel ticks, bolts and the family ring lights."""
    s = c.s; W = c.w; H = c.h - FLANGE
    cx, cy = W // 2, H // 2 - (1 if cells == 2 else 2)
    m = 2 if cells == 2 else 3
    chamfer_fill(s, m, m + 1, W - 2 * m, H - m - 1, 'S', 6 if cells == 2 else 9)               # the seat
    rim(s, 'S', 'M', 'W', (m, m + 1, W - m - 1, H - 1))
    d = 23 if cells == 2 else 37
    r = d // 2
    if cells == 3:                                                                          # the big seat: four corner pads with bolts and lamps
        for (px, py) in ((5, 6), (W - 11, 6), (5, H - 12), (W - 11, H - 12)):
            bev(s, px, py, 6, 6, 'M', 'S', 'W', cham=False); s.put(px + 2, py + 2, 'L')
        s.put(6, H // 2, '5'); c.lightglow(6, H // 2, 3, 0.4, RGB_LAMP[c.line])
        stencil(s, W - 12, H - 4, (2, 3))
    scrap_dress(c, rust=[(cx + 2, m + 1, W - m - cx - 2, H - m - 1)], patch=[(m + 1, m + 3, 7, 6)] if cells == 2 else [(m + 8, H - 12, 9, 7)])
    ring_well(c, cx, cy, d)
    k = r + 2                                                                              # the family ticks round the ring
    for (x, y) in ((cx - k + 2, cy - k + 2), (cx + k - 2, cy - k + 2), (cx - k + 2, cy + k - 2), (cx + k - 2, cy + k - 2)):
        s.put(x, y, '2'); c.lightglow(x, y, 2.5, 0.35)
    if c.line == 'neon':
        s.hline(m + 6, m + 1, W - 2 * m - 12, 'c')
    elif c.line == 'scrap':
        hazard(s, m + 4, H - 3, 9, 2); weld(s, cx + r - 1, m + 4, 6, True)
    c.pivots.append((cx, cy))
    c.hurts.append(hurt_base(cracks=[[(cx - r + 2, cy - 4), (cx - r + 4, cy - 1), (cx - r + 3, cy + 3)], [(W - m - 4, H - 8), (W - m - 6, H - 5)]],
                             sparks=[(cx - r + 3, cy - 3), (W - m - 4, H - 6)]))
    c.wrecks.append(wreck_base(cracks=[[(cx - r + 1, cy - 6), (cx - r + 4, cy - 2), (cx - r + 3, cy + 3), (cx - r + 6, cy + 6)]],
                               dents=[(W - m - 9, H - 9, 6, 5)], soots=[(cx - 4, cy + r - 3, 2), (m + 2, m + 2, 1)], sparks=[(cx + r - 2, cy), (m + 4, H - 6)]))


def strut(s, x0, y0, x1, y1, w=3):
    """a diagonal brace w px thick: lit on its upper-left edge, dark on its lower-right edge."""
    n = max(abs(x1 - x0), abs(y1 - y0), 1)
    for t in range(n + 1):
        x = x0 + round((x1 - x0) * t / n); y = y0 + round((y1 - y0) * t / n)
        for k in range(w): s.put(x + k, y, 'M' if k == 0 else ('W' if k == w - 1 else 'S'))

def casemate6(c, n=3, parts=('drum', 'cells'), cy=13):
    """the broadside battery housing (6x2): a long low casemate, 2-3 sleeves on one gimbal rail, end wings, sloped ends."""
    s = c.s; W = c.w; H = c.h - FLANGE
    plate(s, 4, cy + 7, W - 8, H - cy - 7)                                     # base pad
    plate(s, 15, cy - 7, W - 30, 21)                                           # the long block
    PARTS[parts[0]](c, 2, 8, 14, 15); PARTS[parts[1]](c, W - 16, 8, 14, 15)
    gusset(c, 14, 7, 3); gusset(c, W - 15, 7, 3, True)
    xs = [W // 2 - 26, W // 2, W // 2 + 26] if n == 3 else [W // 2 - 15, W // 2 + 15]
    bev(s, 14, cy - 3, W - 28, 5, 'L', 'M', 'S', cham=False)                   # one gimbal rail for every barrel
    for x in xs:
        sleeve(c, x, cy - 11, 14, 7, 8)
        s.put(x, cy, 'L'); s.put(x + 1, cy + 1, 'W'); s.put(x - 1, cy, 'M')
        c.pivots.append((x, cy))
    for k in range(len(xs) - 1):                                               # between the sleeves: vents, then the ready lights
        mx = (xs[k] + xs[k + 1]) // 2
        grille(s, mx - 4, cy + 4, 8, 4)
    for x in xs:
        lamp_row(s, x - 5, cy + 7, 3, 4, '2', 2)
        for k in range(3): c.lightglow(x - 4 + 4 * k, cy + 7, 2.5, 0.3)
    s.rect(18, cy + 11, W - 36, 1, 'D'); stencil(s, 19, cy + 13, (3, 2, 3)); stencil(s, W - 31, cy + 13, (3, 2, 3))
    if c.line == 'neon': s.hline(16, cy - 7, W - 32, 'c'); neon_edges(c, [(2, 8, 14, 15), (W - 16, 8, 14, 15)])
    scrap_dress(c, rust=[(W - 16, 8, 14, 15), (W // 2 + 5, cy + 8, 30, 6)], tape=[(6, cy + 8, 12, 3)], patch=[(xs[0] - 12, cy - 6, 8, 7)], welds=[(W // 2 - 14, cy + 11, 9, False)])
    c.hurts.append(hurt_base(cracks=[[(xs[0] - 6, cy + 1), (xs[0] - 4, cy + 4), (xs[0] - 5, cy + 8)], [(W - 10, 9), (W - 11, 13), (W - 9, 16)]],
                             sparks=[(xs[-1] + 6, cy + 4), (8, 10)], wires=[[(W - 13, 22), (W - 11, 24), (W - 9, 24)]]))
    c.wrecks.append(wreck_base(cracks=[[(xs[1] - 7, cy - 2), (xs[1] - 5, cy + 2), (xs[1] - 6, cy + 6), (xs[1] - 3, cy + 10)]],
                               dents=[(6, 15, 5, 5), (W - 30, cy + 4, 6, 5)], soots=[(xs[0] - 4, cy - 6, 0), (xs[-1] + 2, cy + 2, 1)], sparks=[(xs[0] + 6, cy + 2), (W - 10, 12)]))

def heavy4(c, parts=('drum', 'vent'), cy=21):
    """the heavy housing (4x3): a wide base, a tall armoured block with a doubled sleeve, side struts, armoured wings."""
    s = c.s; W = c.w; H = c.h - FLANGE
    plate(s, 3, H - 15, W - 6, 15)                                             # base pad
    for side in (0, 1):                                                        # the side struts from the base corners up to the block
        if side == 0: strut(s, 4, H - 16, 15, 9, 4)
        else: strut(s, W - 8, H - 16, W - 19, 9, 4)
    PARTS[parts[0]](c, 2, 24, 15, 17); PARTS[parts[1]](c, W - 17, 24, 15, 17)
    plate(s, 16, 4, 32, 39)                                                    # the armoured block
    for y in (cy + 8, cy + 14): s.rect(20, y, 24, 1, 'D')
    bolt_row(s, [(18, 7), (45, 7), (18, 40), (45, 40), (18, 24), (45, 24)])
    sleeve(c, 32, 5, 26, 7, 16); sleeve(c, 32, 0, 20, 6, 14)                   # the doubled sleeve
    collar(c, 32, cy, 36)
    lamp_row(s, 23, cy + 18, 5, 4, '2', 2)
    for k in range(5): c.lightglow(24 + 4 * k, cy + 18, 2.5, 0.35)
    stencil(s, 21, cy + 11, (3, 2, 3, 2))
    if c.line == 'neon': neon_edges(c, [(16, 4, 32, 39), (2, 24, 15, 17), (W - 17, 24, 15, 17)]); s.hline(5, H - 15, W - 10, 'c')
    scrap_dress(c, rust=[(W - 17, 24, 15, 17), (17, cy + 12, 12, 10)], tape=[(5, H - 14, 12, 3), (34, 5, 12, 2)], patch=[(36, cy + 10, 9, 8)], welds=[(30, cy + 6, 10, True)])
    c.pivots.append((32, cy))
    c.hurts.append(hurt_base(cracks=[[(20, cy - 12), (22, cy - 8), (21, cy - 4)], [(W - 9, 26), (W - 10, 30), (W - 8, 33)]],
                             sparks=[(21, cy - 10), (W - 9, 30)], flap=(1, 23)))
    c.wrecks.append(wreck_base(cracks=[[(20, cy - 13), (23, cy - 8), (21, cy - 3), (24, cy + 3), (22, cy + 9)], [(W - 9, 26), (W - 11, 31), (W - 8, 36)]],
                               dents=[(6, 30, 6, 6), (38, cy + 10, 6, 5)], soots=[(26, 6, 0), (4, 26, 1), (W - 14, H - 12, 2)], sparks=[(28, 8), (10, 30)]))

def casemate2(c, parts=('cells', 'sensor'), cy=50):
    """the long-barrel housing (2x4): a narrow cradle, two rails either side of the barrel channel, cross braces, a braced foot."""
    s = c.s; W = c.w; H = c.h - FLANGE
    plate(s, 2, cy - 6, W - 4, H - cy + 6)                                     # the foot
    for x in (6, 20):
        plate(s, x, 4, 6, cy - 2)                                              # the rails
        s.vline(x + 2, 8, cy - 10, 'W'); s.put(x + 1, 6, 'L')
    channel(s, 12, 6, 8, cy - 6)
    for y in (12, 30):                                                         # cross braces (under the barrel; they show past it)
        bev(s, 4, y, W - 8, 4, 'L', 'M', 'S', cham=False)
        bolt_row(s, [(5, y + 1), (W - 6, y + 1)], 'L')
    for k, y in enumerate(range(18, cy - 6, 8)):                              # the family lights along the rails
        s.put(7, y, '2'); s.put(W - 8, y, '2'); c.lightglow(7, y, 2.2, 0.3); c.lightglow(W - 8, y, 2.2, 0.3)
    gusset(c, 5, cy - 7, 3); gusset(c, W - 6, cy - 7, 3, True)
    PARTS[parts[0]](c, 2, cy + 1, 9, 10) if parts[0] else None
    PARTS[parts[1]](c, W - 11, cy + 1, 9, 10) if parts[1] else None
    collar(c, 16, cy, 18)
    if c.line == 'neon': s.vline(6, 8, cy - 12, 'c'); s.vline(W - 7, 8, cy - 12, 'c'); s.hline(4, cy - 6, W - 8, 'c')
    scrap_dress(c, rust=[(20, 4, 6, 26), (2, cy - 6, 12, 8)], tape=[(W - 14, cy - 5, 10, 2), (6, 4, 6, 2)], welds=[(8, 34, 10, True)])
    c.pivots.append((16, cy))
    c.hurts.append(hurt_base(cracks=[[(7, 20), (9, 24), (8, 28)], [(W - 8, 40), (W - 9, 44)]], sparks=[(8, 22), (W - 6, 42)]))
    c.wrecks.append(wreck_base(cracks=[[(7, 18), (9, 23), (8, 28), (10, 33)]], dents=[(20, 20, 5, 6), (3, cy + 2, 5, 5)],
                               soots=[(4, 8, 2), (20, cy - 4, 1)], sparks=[(9, 26), (23, 10)]))

def spinal(c, cy=86):
    """the spinal sleeve (2x6): two armoured plates tapering to the prow, segmented and riveted, family conduits along the channel."""
    s = c.s; W = c.w; H = c.h - FLANGE
    plate(s, 1, cy - 8, W - 2, H - cy + 8)                                     # the foot
    for side in (0, 1):
        x = 2 if side == 0 else W - 11
        plate(s, x, 8, 9, cy - 10)
        for k in range(6):                                                    # the taper toward the prow
            for j in range(6 - k): s.erase(x + j if side == 0 else x + 8 - j, 8 + k)
        for y in range(22, cy - 10, 14):                                       # segments and rivets
            s.hline(x + 1, y, 7, 'W'); s.hline(x + 1, y + 1, 7, 'L')
            s.put(x + 2, y + 4, 'L'); s.put(x + 6, y + 4, 'L')
        ix = x + 8 if side == 0 else x                                         # the conduit on the channel side
        s.vline(ix, 12, cy - 22, '1')
        for y in range(16, cy - 12, 7): s.put(ix, y, '3'); c.lightglow(ix, y, 2.5, 0.35)
    channel(s, 11, 4, 10, cy - 4)
    plate(s, 7, 2, 18, 7)                                                      # the armoured muzzle collar (under the lance)
    collar(c, 16, cy, 26)
    lamp_row(s, 6, cy + 4, 6, 4, '2', 2)
    if c.line == 'neon': s.vline(3, 14, cy - 24, 'c'); s.vline(W - 4, 14, cy - 24, 'c')
    scrap_dress(c, rust=[(2, 36, 9, 28), (W - 11, 64, 9, 14)], tape=[(3, cy - 7, 10, 2), (W - 10, 20, 8, 2)], patch=[(W - 11, 30, 8, 9)], welds=[(4, 66, 8, True)])
    c.pivots.append((16, cy))
    c.hurts.append(hurt_base(cracks=[[(4, 30), (6, 35), (5, 40)], [(W - 6, 56), (W - 7, 61), (W - 5, 65)]], sparks=[(5, 34), (W - 5, 60)], flap=(0, 44)))
    c.wrecks.append(wreck_base(cracks=[[(4, 28), (7, 35), (5, 42), (8, 48)], [(W - 6, 56), (W - 8, 62), (W - 5, 68)]],
                               dents=[(3, 60, 6, 6), (W - 10, 24, 6, 5)], soots=[(2, 12, 2), (W - 10, 40, 1), (4, cy - 6, 0)], sparks=[(6, 36), (W - 6, 62)]))

def half_dome(s, cx, wy, r, hx=-0.45, hy=-0.75):
    """a half-round bulge standing on the wall face (centre (cx, wy) on the face), lit from the top-left."""
    for y in range(int(wy - r - 1), wy):
        for x in range(int(cx - r - 1), int(cx + r + 2)):
            dx, dy = x + .5 - cx, y + .5 - wy
            if dx * dx + dy * dy > r * r: continue
            lx, ly = dx - hx * r, dy - hy * r
            t = (lx * lx + ly * ly) ** 0.5 / (r * 1.5)
            edge = dx * dx + dy * dy > (r - 1.2) ** 2
            s.put(x, y, ('W' if dx > -r * 0.3 else 'S') if edge else 'LLMMMSSWE'[min(8, int(t * 9))])

def sponson(c, cy=26, r=19):
    """the sponson (3x2): a half-round bulge on a yoke bar bolted to the wall face, the rail track painted round its foot."""
    s = c.s; W = c.w; H = c.h - FLANGE
    cx, wy = W // 2, H
    plate(s, 1, H - 7, W - 2, 7)                                               # the yoke bar along the wall face
    for x in (1, W - 7): bev(s, x, H - 11, 6, 11, 'M', 'S', 'W', cham=False); s.put(x + 2, H - 9, 'L'); s.put(x + 2, H - 3, 'L')   # its lugs
    half_dome(s, cx, wy, r)
    for k in range(-84, 85, 3):                                                # the rail track: a groove round the bulge's foot ...
        a = math.radians(k)
        s.put(int(cx + (r - 3.5) * math.sin(a)), int(wy - (r - 3.5) * math.cos(a)), 'E')
    for k in range(-60, 61, 30):                                               # ... with painted traverse marks and end stops
        a = math.radians(k)
        for rr in (r - 2.4, r - 1.6): s.put(int(cx + rr * math.sin(a)), int(wy - rr * math.cos(a)), '6')
    for side in (-1, 1): s.rect(cx + side * (r - 3) - (1 if side > 0 else 0), wy - 3, 2, 3, '6')
    ringpx(s, cx, wy, 6.5, 7.5, 'W')                                           # the traverse ring the head turns in
    s.put(cx - r + 5, wy - 6, '2'); s.put(cx + r - 6, wy - 6, '2'); c.lightglow(cx - r + 5, wy - 6, 2.5, 0.35); c.lightglow(cx + r - 6, wy - 6, 2.5, 0.35)
    if c.line == 'neon':
        for k in range(-88, 89, 2):
            a = math.radians(k); s.put(int(cx + (r - 1.6) * math.sin(a)), int(wy - (r - 1.6) * math.cos(a)), 'c')
    scrap_dress(c, rust=[(W - 7, H - 11, 6, 11), (cx + 4, H - 14, 15, 14)], tape=[(2, H - 5, 10, 2)], patch=[(cx - 15, H - 13, 7, 6)], welds=[(cx + 6, H - 17, 6, False)])
    c.pivots.append((cx, cy))
    c.hurts.append(hurt_base(cracks=[[(cx - 12, wy - 9), (cx - 10, wy - 6), (cx - 11, wy - 3)], [(W - 5, H - 11), (W - 4, H - 7)]], sparks=[(cx - 11, wy - 7), (W - 4, H - 9)]))
    c.wrecks.append(wreck_base(cracks=[[(cx - 13, wy - 10), (cx - 10, wy - 6), (cx - 12, wy - 1)], [(cx + 7, wy - 13), (cx + 10, wy - 9)]],
                               dents=[(W - 8, H - 11, 5, 5)], soots=[(cx - 3, wy - 16, 0), (2, H - 9, 2)], sparks=[(cx + 12, wy - 6), (3, H - 10)]))

def strip8(c, n=5):
    """the gun strip housing (8x1): a long low bar with n small sleeved ports, vents and bolts between."""
    s = c.s; W = c.w; H = c.h - FLANGE
    plate(s, 2, 3, W - 4, H - 3)
    xs = [round(16 + k * (W - 32) / (n - 1)) for k in range(n)]
    for k, x in enumerate(xs):
        plate(s, x - 5, 1, 10, 7); channel(s, x - 2, 2, 4, 4)
        c.pivots.append((x, 6))
        s.put(x - 1, 10, '2'); s.put(x + 1, 10, '2'); c.lightglow(x, 10, 2.5, 0.3)
        if k < n - 1:
            mx = (x + xs[k + 1]) // 2
            grille(s, mx - 4, 5, 8, 4); bolt_row(s, [(mx - 6, 12), (mx + 5, 12)])
    for x in (4, W - 6): s.put(x, 8, '5')
    stencil(s, xs[0] + 8, 12, (2, 3)); stencil(s, xs[-1] - 15, 12, (3, 2))
    if c.line == 'neon': s.hline(4, 3, W - 8, 'c')
    scrap_dress(c, rust=[(xs[3] + 4, 3, 15, 13), (2, 3, 10, 13)], tape=[(xs[1] + 6, 12, 10, 2)], patch=[(xs[2] + 5, 4, 8, 7)])
    c.hurts.append(hurt_base(cracks=[[(xs[1] + 4, 4), (xs[1] + 6, 8), (xs[1] + 5, 12)]], sparks=[(xs[1] + 6, 6), (xs[3] + 6, 9)]))
    c.wrecks.append(wreck_base(cracks=[[(xs[2] + 5, 3), (xs[2] + 7, 8), (xs[2] + 5, 13)]], dents=[(xs[0] + 6, 6, 5, 5)],
                               soots=[(xs[3] + 4, 3, 2), (xs[1] - 2, 5, 1)], sparks=[(xs[2] + 7, 6), (xs[0] + 8, 8)]))

def pod_plate(c, n=4):
    """the flush pod (4x1): a low plate with n tube wells (the hatch lids are the pod's `barrel` sprite: they open as it fires)."""
    s = c.s; W = c.w; H = c.h - FLANGE
    plate(s, 2, 1, W - 4, H - 1)
    pitch = (W - 8) // n
    for k in range(n):
        x = 4 + k * pitch
        recess(s, x + 1, 2, pitch - 2, H - 5, 'K', 'K')                        # the tube well under the lid
    s.put(3, H // 2, '5'); s.put(W - 4, H // 2, '5')
    if c.line == 'neon': s.hline(4, 1, W - 8, 'c')
    scrap_dress(c, rust=[(2, 1, 6, H - 1), (W - 18, 1, 16, H - 1)], tape=[(4, H - 3, 12, 2)])
    c.pivots.append((W // 2, H // 2))
    c.hurts.append(hurt_base(cracks=[[(W - 6, 3), (W - 5, 7), (W - 6, 11)]], sparks=[(W - 5, 5), (4, 10)]))
    c.wrecks.append(wreck_base(dents=[(W - 9, 4, 5, 5)], soots=[(2, 2, 2)], sparks=[(W - 5, 5), (5, 9)]))

# ================================================================== BARRELS: their own sprites, pointing up. A barrel canvas has the pivot at (c.px, c.py)
# and the tip near y = 0; the tube slides back by the recoil (st.rc) when firing, the head stays. Heads say the aim class.
TUBE_RAMP = 'LMMSSSSWWE'

def lens_mode(c):
    if not c.st.powered or c.st.dmg == 2: return 'dead'
    return 'fire' if c.st.fire else 'idle'

def tone(c, ch): return c.look.steel.get(ch, ch)

def snap(s, ycut, dx, dy):
    """a snapped barrel: everything above ycut moves by (dx, dy), so the break opens (the outline pass closes both pieces)."""
    n = Spr(s.w, s.h)
    for y in range(s.h):
        for x in range(s.w):
            ch = s.g[y][x]
            if ch == '.': continue
            if y < ycut: n.put(x + dx, y + dy, ch)
            else: n.put(x, y, ch)
    s.g = n.g

def hurt_tube(x0, w, band_y, cap_y, band=True):
    """damaged barrel: a band torn loose and hanging askew by its wire, the cap cracked, sparks from two spots."""
    def f(s, c):
        if band and band_y is not None:
            move(s, x0 - 1, band_y, w + 2, 3, 3, 4)
            for y in range(band_y, band_y + 3):
                for k, t in enumerate(ramp_rows(w, TUBE_RAMP)):
                    if s.get(x0 + k, y) == '.': s.g[y][x0 + k] = tone(c, t)
            wire(s, [(x0 + w, band_y + 2), (x0 + w + 1, band_y + 4)])
        crack(s, [(x0 + 2, cap_y), (x0 + 3, cap_y + 3), (x0 + 1, cap_y + 6)], 'K', c.look.hi())
        sx, sy = [(x0 + w + 2, (band_y or cap_y) + 6), (x0 + 1, cap_y + 2)][c.st.i % 2]; spark(s, sx, sy, False)
    return f

def wreck_tube(ycut, x0, w):
    """disabled barrel: snapped and askew, wires across the break."""
    def f(s, c):
        snap(s, ycut, 2, -1)
        wire(s, [(x0 + 2, ycut), (x0 + 3, ycut - 2)]); wire(s, [(x0 + w - 2, ycut + 1), (x0 + w, ycut - 1)])
        crack(s, [(x0 + 3, ycut + 3), (x0 + 5, ycut + 7)], 'K', 'S')
    return f

# ---- heads: what a barrel sits on, by aim class
def breech_fixed(c, w=15, heavy=False):
    """FIXED: the rectangular breech block round the gimbal pin, and the bracing cuff where the tube enters the sleeve.
    heavy: a doubled cuff and side braces."""
    s = c.s; cx, py = c.px, c.py
    plate(s, cx - w // 2, py - 5, w, 12)
    chamfer_fill(s, cx - 2, py - 2, 5, 5, 'S', 1); rim(s, 'S', 'L', 'W', (cx - 2, py - 2, cx + 2, py + 2)); s.put(cx, py, 'E')
    band(s, cx - w // 2 - 1, py - 8, w + 2, 3)
    bolt_row(s, [(cx - w // 2 + 1, py + 4), (cx + w // 2 - 1, py + 4)], 'L')
    if heavy:
        band(s, cx - w // 2 - 2, py - 12, w + 4, 4)
        for side in (-1, 1):
            x = cx - w // 2 - 2 if side < 0 else cx + w // 2 + 1
            plate(s, x, py - 8, 2, 9, cham=False)
        return py - 12
    return py - 8

def hub(c, d=15, eye=True, side=1):
    """TURRET: the compact head that sits in the ring: an octagon disc with an axis cap, and the sensor eye (it aims itself)."""
    s = c.s; cx, cy = c.px, c.py
    oct_disc(s, cx, cy, d, 'S', 'M', 'W')
    s.put(cx, cy, 'L'); s.put(cx + 1, cy + 1, 'W'); s.put(cx - 1, cy, 'M'); s.put(cx, cy - 1, 'M')
    r = d // 2
    if c.line == 'neon': ringpx(s, cx + .5, cy + .5, r - 2.2, r - 1.2, 'c')
    elif c.line == 'scrap': rust_over(s, cx - r, cy - 2, r - 1, r)
    if eye:
        ex = cx + r - 5 if side > 0 else cx - r
        bev(s, ex, cy + 1, 6, 5, 'M', 'S', 'W', cham=False)
        s.rect(ex + 2, cy + 2, 2, 2, '2'); s.put(ex + 2, cy + 2, '3')
        c.lightglow(ex + 2.5, cy + 2.5, 3, 0.5)
    return cy - r + 2

def dome_head(c, r=12, mw=13):
    """TURRET: the dome head of the dome turret: an armoured dome, a seam ring, the mantlet the barrels leave by, the sensor eye."""
    s = c.s; cx, cy = c.px, c.py
    round_disc(s, cx + .5, cy + .5, r + .5, ('L', 'M', 'M', 'S', 'S', 'W', 'E'))
    ringpx(s, cx + .5, cy + .5, r - 3.6, r - 2.6, 'c' if c.line == 'neon' else 'W')
    if c.line == 'scrap': rust_over(s, cx + 2, cy + 1, r, r); weld(s, cx - r + 4, cy + 4, 6)
    plate(s, cx - mw // 2, cy - r - 2, mw, 8)                                  # the mantlet
    s.rect(cx - mw // 2 + 2, cy - r + 3, mw - 4, 1, 'D')
    ex, ey = cx - r + 3, cy - 3                                                # the sensor eye on the dome's flank
    s.rect(ex, ey, 4, 4, 'D'); s.rect(ex + 1, ey + 1, 2, 2, '2'); s.put(ex + 1, ey + 1, '3'); s.put(ex + 3, ey + 3, 'W')
    c.lightglow(ex + 1.5, ey + 1.5, 3.5, 0.55)
    s.put(cx, cy + 2, 'L'); bolt_row(s, [(cx - 5, cy + 6), (cx + 5, cy + 6), (cx + 7, cy)], 'M')
    c.hurts.append(lambda s_, c_: (crack(s_, [(cx + 4, cy - 2), (cx + 6, cy + 2), (cx + 5, cy + 6)], 'K', c_.look.hi()),
                                   spark(s_, *[(cx + 6, cy + 1), (ex, ey)][c_.st.i % 2], False)))
    c.wrecks.append(lambda s_, c_: (soot(s_, cx - 3, cy - 2, 0), dent(s_, cx + 3, cy + 2, 5, 4), crack(s_, [(cx - 6, cy - 5), (cx - 2, cy), (cx - 4, cy + 5)])))
    return cy - r - 2

def pd_head(c, r=6):
    """TURRET, point defence: a small dome with the radar eye (a dish that tracks)."""
    s = c.s; cx, cy = c.px, c.py
    round_disc(s, cx + .5, cy + .5, r + .5, ('L', 'M', 'S', 'S', 'W', 'E'))
    dx, dy = cx + r - 1, cy + 1                                                # the radar dish
    circle(s, dx + .5, dy + .5, 3.5, 'M'); ringpx(s, dx + .5, dy + .5, 2.2, 3.5, 'S')
    s.put(dx, dy, '3'); s.put(dx + 1, dy, '2'); s.put(dx, dy + 1, '2')
    c.lightglow(dx + .5, dy + .5, 3.5, 0.55)
    s.put(cx - 1, cy - 1, 'L')
    return cy - r + 1

def yoke(c, gap=9):
    """SWIVEL: the trunnion cap on the pivot and the yoke fork that carries the barrel on two pins (a U round the tube)."""
    s = c.s; cx, py = c.px, c.py
    oct_disc(s, cx, py, 9, 'S', 'M', 'W')
    s.put(cx, py, 'L'); s.put(cx + 1, py + 1, 'W')
    for side in (-1, 1):
        ax = cx - gap // 2 - 3 if side < 0 else cx + gap // 2 + 1
        bev(s, ax, py - 9, 3, 9, 'L', 'M', 'S', cham=False)                    # the fork arms
        s.vline(ax + 2 if side < 0 else ax, py - 8, 7, 'K')                   # the gap between arm and tube
        s.put(ax + 1, py - 6, 'W')                                             # trunnion pins
    return py - 4

# ---- tubes (top = the tip, bot = where it meets the head)
def tube_single(c, top, bot, w=11, rings=4, pitch=5, heavy=False):
    """the ribbed tube (Laser Mk I): bands every `pitch` px, an end cap, the family lens. heavy: thicker bands near the breech."""
    s = c.s; cx = c.px; o = c.st.rc
    x0 = cx - w // 2
    tube(s, x0, top + 4 + o, w, bot - top - 4)
    for k in range(rings):
        band(s, x0 - 1, bot - 6 - k * pitch + o, w + 2, 4 if heavy and k < 2 else 3)
    plate(s, x0 - 1, top + o, w + 2, 5, True, 'S', 'E', 'D')
    lens_up(s, x0, top + o, w, 3, lens_mode(c))
    c.muzzles.append((cx, top + o)); c.lightglow(cx, top + 1 + o, 5, 0.5, sx=1.3)
    c.tip = (cx, top, w)
    if c.line == 'scrap':                                                      # scrap: a rust band, a hazard collar, a weld down the tube
        rk = min(1, rings - 1)
        if rings: rust_over(s, x0 - 1, bot - 6 - rk * pitch + o, w + 2, 3)
        hazard(s, x0, top + 5 + o, w, 2); weld(s, x0 + w - 3, top + 9 + o, max(2, bot - top - 20), True)
    c.hurts.append(hurt_tube(x0, w, bot - 6 - (rings - 1) * pitch if rings > 1 else None, top + 1))
    c.wrecks.append(wreck_tube((top + bot) // 2, x0, w))

def tube_short(c, top, bot, w=9, rings=2):
    """the short turret barrel: two bands, a cap, the lens."""
    tube_single(c, top, bot, w, rings, 5)

def tube_multi(c, top, bot, n=2, w=5, gap=5, coil=False):
    """two or three rails on a bridge (twin: Laser Mk II; triple: a dome's flak cluster): bands, a lens each, family trim inside.
    coil: a second bridge half way up with a lit coil between the rails (the Mk III machinery)."""
    s = c.s; cx = c.px; o = c.st.rc
    span = n * w + (n - 1) * gap
    xl = cx - span // 2
    plate(s, xl - 1, bot - 6 + o, span + 2, 7)                                 # the bridge
    xs = [xl + k * (w + gap) for k in range(n)]
    for k in range(n - 1): channel(s, xs[k] + w + 1, bot - 4 + o, gap - 2, 3) if gap > 2 else None
    for k, x0 in enumerate(xs):
        tube(s, x0, top + 4 + o, w, bot - top - 9, 'LMSWE')
        for by in range(bot - 12, top + 8, -6): band(s, x0 - 1, by + o, w + 2, 3)
        plate(s, x0 - 1, top + o, w + 2, 5, True, 'S', 'E', 'D')
        lens_up(s, x0, top + o, w, 3, lens_mode(c))
        if gap >= 3:
            ix = x0 + w - 1 if k == 0 else x0
            for y in range(top + 6, bot - 7):
                if s.get(ix, y + o) not in ('L', 'M', '9'): s.put(ix, y + o, '2')
        c.muzzles.append((x0 + w // 2, top + o)); c.lightglow(x0 + w // 2, top + 1 + o, 3, 0.3)
    if coil:
        my = (top + bot) // 2 - 3 + o
        plate(s, xl - 2, my, span + 4, 7)
        recess(s, xl + w - 1, my + 1, span - 2 * w + 2, 5, 'D', 'K')
        for k in range(xl + w, xl + span - w, 2): s.vline(k, my + 2, 3, '2'); s.put(k, my + 2, '3')
        c.lightglow(xl + span / 2.0, my + 3, 4.5, 0.5, sx=1.4)
        bolt_row(s, [(xl - 1, my + 1), (xl + span, my + 1)])
    if c.line == 'scrap':
        rust_over(s, xl - 1, bot - 6 + o, span // 2, 7); hazard(s, xs[0], top + 5 + o, w, 2); rust_over(s, xs[-1] - 1, bot - 18 + o, w + 2, 3)
    c.hurts.append(hurt_tube(xs[-1], w, None, top + 2, band=False))
    c.hurts.append(lambda s_, c_: move(s_, xs[0] - 1, top, w + 2, 6, -1, 3))
    c.wrecks.append(wreck_tube((top + bot) // 2, xs[0], span))

def tube_twin(c, top, bot, w=5, gap=5, coil=False): tube_multi(c, top, bot, 2, w, gap, coil)
def tube_triple(c, top, bot, w=5, gap=2): tube_multi(c, top, bot, 3, w, gap)

def tube_rotary(c, top, bot, r=4.5, tw=3):
    """the rotary cluster (chain): four tubes round an axis seen from above, front, mid and rear clamps, the drive housing.
    `spin` frames turn it a quarter turn in 4 steps (st.i); the chain step (st.lit, 0..3) heats the muzzles."""
    s = c.s; cx = c.px; o = c.st.rc
    spin = c.st.i if c.st.state in ('spin', 'fire') else 0
    plate(s, cx - 8, bot - 8 + o, 17, 9)                                       # the drive housing
    grille(s, cx - 5, bot - 6 + o, 11, 4)
    ts = []
    for k in range(4):
        a = math.radians(spin * 22.5 + 90 * k + 22.5)
        ts.append((math.cos(a), cx + 0.5 + r * math.sin(a)))
    for depth, x in sorted(ts):                                                # back tubes first, each with a dark flank
        x0 = int(round(x - tw / 2.0))
        tone_ = 'LMW' if depth > 0.3 else ('MSE' if depth > -0.3 else 'SWD')
        tube(s, x0 - 1, top + 2 + o, tw + 2, bot - top - 9, 'K' + tone_ + 'K' if depth > -0.3 else 'D' + tone_ + 'D')
        s.hline(x0, top + 2 + o, tw, 'K' if depth > -0.3 else 'D')
    step = c.st.lit or 0
    if step and c.st.powered:                                                  # heat at the muzzles with the chain steps
        for depth, x in ts:
            if depth > -0.3:
                x0 = int(round(x - tw / 2.0))
                for j in range(min(4, step + 1)): s.hline(x0, top + 3 + j + o, tw, ('y', 'o', 'r', 'r')[j] if j < step else 'u')
    span = bot - top - 14
    for y in (top + 6, top + 6 + span // 2, bot - 13):
        band(s, cx - 7, y + o, 15, 3)
    s.put(cx - 6, top + 7 + o, '2'); s.put(cx + 5, top + 7 + o, '2'); c.lightglow(cx, top + 7 + o, 4, 0.4, sx=1.6)
    for depth, x in ts:
        if depth > -0.3: c.muzzles.append((int(x), top + 2 + o))
    c.muzzles[:] = c.muzzles[-1:]                                              # one flash per shot, at the barrel in front
    if step: c.lightglow(cx, top + 5 + o, 4 + 2 * step, 0.12 + 0.1 * step, (255, 110, 40), 0.8)        # heat haze on the glow layer
    c.hurts.append(hurt_tube(cx - 6, 13, None, top + 8, band=False))
    c.hurts.append(lambda s_, c_: move(s_, cx - 7, top + 6, 15, 3, 2, 3))
    c.wrecks.append(wreck_tube((top + bot) // 2, cx - 6, 13))

def tube_cap(c, top, bot, w=9, n=3):
    """the capacitor barrel (charge): n capacitor rings on the tube, lit one by one as volleys are stored (st.lit 0..n)."""
    s = c.s; cx = c.px; o = c.st.rc
    x0 = cx - w // 2
    tube(s, x0, top + 4 + o, w, bot - top - 4)
    lit = 0 if c.st.fire else (c.st.lit or 0)
    span = bot - top - 16
    for k in range(n):                                                         # ring 0 is nearest the breech, lit first
        y = bot - 8 - k * span // max(1, n - 1) - 2 + o if n > 1 else (top + bot) // 2
        y = min(y, bot - 8 + o)
        plate(s, x0 - 3, y, w + 6, 5, True, 'M', 'S', 'W')
        on = c.st.powered and k < lit
        if on:
            s.hline(x0 - 2, y + 1, w + 4, '3'); s.hline(x0 - 2, y + 2, w + 4, '2'); s.hline(x0 - 2, y + 3, w + 4, '1'); s.put(x0 - 1, y + 1, '4')
        else:
            s.hline(x0 - 1, y + 2, w + 2, 'E'); s.put(x0 - 1, y + 2, 'D')
        if on: c.lightglow(cx, y + 2, 6, 0.55, sx=1.5)
    plate(s, x0 - 1, top + o, w + 2, 5, True, 'S', 'E', 'D')
    lens_up(s, cx - (w - 4) // 2, top + o, w - 4, 3, lens_mode(c))
    c.muzzles.append((cx, top + o)); c.lightglow(cx, top + 1 + o, 3.5, 0.35)
    c.hurts.append(hurt_tube(x0, w, None, top + 1, band=False))
    c.wrecks.append(wreck_tube(top + 10, x0, w))

def tube_long(c, top, bot, w=9, fin0=0.40, fin1=0.80):
    """the long barrel: an extended tube with a cooling fin row, a muzzle sleeve, bands at the breech."""
    s = c.s; cx = c.px; o = c.st.rc
    x0 = cx - w // 2; L = bot - top
    tube(s, x0, top + 4 + o, w, L - 4)
    f0, f1 = top + int(L * fin0), top + int(L * fin1)
    for y in range(f0, f1, 3):                                                 # the fin row
        s.hline(x0 - 3, y + o, w + 6, '9'); s.hline(x0 - 3, y + 1 + o, w + 6, 'W'); s.put(x0 - 3, y + 1 + o, 'S')
    band(s, x0 - 1, f0 - 5 + o, w + 2, 3); band(s, x0 - 1, f1 + 1 + o, w + 2, 3)
    for k in range(2): band(s, x0 - 1, bot - 6 - 5 * k + o, w + 2, 3)
    band(s, x0 - 2, top + 5 + o, w + 4, 4)                                    # the muzzle sleeve
    plate(s, x0 - 1, top + o, w + 2, 5, True, 'S', 'E', 'D')
    lens_up(s, cx - (w - 4) // 2, top + o, w - 4, 3, lens_mode(c))
    s.vline(x0 + 1, top + 10 + o, f0 - top - 16, '2')                          # a family sight line along the tube
    c.muzzles.append((cx, top + o)); c.lightglow(cx, top + 1 + o, 3.5, 0.4)
    c.hurts.append(hurt_tube(x0, w, bot - 11, top + 1))
    c.wrecks.append(wreck_tube(f0 - 2, x0, w))

def tube_lance(c, top, bot, w=11):
    """the lance: an armoured core with rings of the family colour, armour collars between, a forked emitter with a focus crystal."""
    s = c.s; cx = c.px; o = c.st.rc
    x0 = cx - w // 2
    tube(s, x0, top + 10 + o, w, bot - top - 10, 'MMSSSWWE')
    for k, y in enumerate(range(bot - 12, top + 18, -9)):
        if k % 2 == 0: fam_ring(s, x0 - 1, y + o, w + 2, 3, c.st.powered); c.lightglow(cx, y + 1 + o, 4.5, 0.4, sx=1.6)
        else: band(s, x0 - 2, y + o, w + 4, 4)
    for px_ in (x0 - 1, x0 + w - 2):                                           # the fork prongs
        plate(s, px_, top + 1 + o, 3, 11, cham=False); s.put(px_, top + 1 + o, '9')
    mode = lens_mode(c)                                                        # the focus crystal between them
    gem = art("""
..3..
.342.
33421
.221.
..1..
""") if mode != 'dead' else art("""
..W..
.WEE.
WEEED
.EED.
..D..
""")
    s.stamp(cx - 2, top + 3 + o, gem)
    band(s, x0 - 1, top + 9 + o, w + 2, 3)
    c.muzzles.append((cx, top + 3 + o)); c.lightglow(cx, top + 5 + o, 5, 0.6)
    c.hurts.append(hurt_tube(x0, w, None, top + 12, band=False))
    c.hurts.append(lambda s_, c_: move(s_, x0 + w - 2, top + 1, 3, 11, 2, 2))
    c.wrecks.append(wreck_tube(top + 22, x0, w))

def tube_pd(c, top, bot, w=3, gap=2):
    """point defence: twin short thin barrels."""
    s = c.s; cx = c.px; o = c.st.rc
    for x0 in (cx - gap // 2 - w, cx + (gap + 1) // 2):
        tube(s, x0, top + 2 + o, w, bot - top - 1, 'MSW')
        s.hline(x0 - 1, top + 5 + o, w + 2, '9'); s.hline(x0 - 1, top + 6 + o, w + 2, 'W')
        s.hline(x0, top + o, w, 'E'); s.put(x0 + 1, top + o, '3' if lens_mode(c) != 'dead' else 'D')
        c.muzzles.append((x0 + 1, top + o))
    c.lightglow(cx, top, 3, 0.3)
    c.hurts.append(lambda s_, c_: move(s_, cx + 1, top, 4, 5, 1, 2))
    c.wrecks.append(wreck_tube(top + 4, cx - 4, 8))

def brake(c):
    """add-on: a muzzle brake at the tip, slotted on both sides (heavy versions)."""
    s = c.s; cx, top, w = c.tip; o = c.st.rc
    bw = w + 6; x0 = cx - bw // 2
    plate(s, x0, top + o, bw, 8, True, 'M', 'S', 'W')
    for y in (top + 2, top + 5):
        s.rect(x0, y + o, 2, 2, 'D'); s.rect(x0 + bw - 2, y + o, 2, 2, 'D')
    lens_up(s, cx - (w - 4) // 2, top + o, w - 4, 3, lens_mode(c))

def lids(c, n=4):
    """the pod's hatch lids over its tubes (the pod's `barrel` sprite, never turned): closed at rest; fire 0-2 = open, half, closing,
    with the warhead's nose showing in the open tube."""
    s = c.s; W = c.w; H = 16
    pitch = (W - 8) // n
    st = c.st
    openf = {0: 1.0, 1: 0.55, 2: 0.2}[st.i] if st.fire else 0.0
    for k in range(n):
        x = 4 + k * pitch + 1; lw, lh = pitch - 2, H - 5
        if openf > 0:                                                         # the open tube: the nose of the next round
            s.rect(x + 1, 3, lw - 2, lh - 2, 'K')
            nx = x + lw // 2 - 2
            s.stamp(nx, 5, art("""
.31.
3331
3HL1
3LL1
"""))
        ph = max(2, int(round(lh * (1 - openf))))
        y0 = 2 + lh - ph
        bev(s, x, y0, lw, ph, 'M', 'S', 'W', cham=False)                      # the lid, folding back to its hinge at the bottom
        s.hline(x, 2 + lh - 1, lw, 'E')
        for hx in range(x + 2, x + lw - 2, 3): s.put(hx, 2 + lh - 1, 'L')       # hinge knuckles
        if ph > 5:
            for j in range(2): s.put(x + lw // 2 - 1 + j, y0 + 2, '6'); s.put(x + lw // 2 - 2 + j * 3, y0 + 3, '6')
            s.put(x + lw // 2, y0 + ph - 3, '2'); c.lightglow(x + lw // 2, y0 + ph - 3, 2.2, 0.35)
        c.muzzles.append((x + lw // 2, 4))
    c.hurts.append(lambda s_, c_: (move(s_, 4 + pitch * (n - 1) + 1, 2, pitch - 2, H - 5, 1, -1), spark(s_, W - 8, 9 + c_.st.i, False)))
    c.wrecks.append(lambda s_, c_: (dent(s_, 6, 4, 5, 5), soot(s_, 4 + pitch + 2, 3, 2), crack(s_, [(4 + pitch * 2 + 3, 3), (4 + pitch * 2 + 5, 8), (4 + pitch * 2 + 4, 12)])))
    return 2

BARREL_PARTS = {'breech_fixed': breech_fixed, 'hub': hub, 'dome_head': dome_head, 'pd_head': pd_head, 'yoke': yoke,
                'single': tube_single, 'short': tube_short, 'twin': tube_twin, 'triple': tube_triple, 'rotary': tube_rotary,
                'capacitor': tube_cap, 'long': tube_long, 'lance': tube_lance, 'pd_twin': tube_pd, 'brake': brake, 'lids': lids}

# ================================================================== BREECHES (inside halves, on the floor; the flange on top over the inner wall face)
def breech_in(c, cells=(2, 2)):
    """the inside half: housing, the column up through the collar, the power coupling, steel capacitors with the family band, the charge strip."""
    s = c.s; W = c.w; y0 = FLANGE; H = c.h - FLANGE; st = c.st
    plate(s, 2, y0 + 1, W - 4, H - 2, True, 'M', 'S', 'W')
    tube(s, W // 2 - 4, y0 + 1, 8, 5, 'LMSSSSWE')
    s.rect(0, y0 + 10, 4, 4, 'q'); s.hline(0, y0 + 10, 4, 'Q'); s.hline(0, y0 + 13, 4, 'n')      # cable stub at the left edge
    bev(s, 3, y0 + 7, 6, 10, 'M', 'S', 'W', cham=False); s.put(5, y0 + 9, '5')
    banks = [(y0 + 7, H - 17)] if H <= 40 else [(y0 + 7, (H - 22) // 2), (y0 + 9 + (H - 22) // 2, (H - 22) // 2)]
    cw = W - 15 if W <= 32 else W - 34
    for (by, bh) in banks:
        recess(s, 10, by, cw, bh, 'D', 'K')
        for k in range((cw - 2) // 4):
            cx_ = 11 + k * 4
            tube(s, cx_, by + 1, 3, bh - 2, 'LSW')
            m = by + bh // 2
            s.hline(cx_, m - 1, 3, 'E'); s.hline(cx_, m, 3, '2'); s.hline(cx_, m + 1, 3, '1')
            c.lightglow(cx_ + 1, m, 2.5, 0.3)
    if W > 32:                                                                  # the wide breech: a repair hatch at the right
        bev(s, W - 22, y0 + 7, 18, H - 17, 'L', 'M', 'S', cham=False)
        s.rect(W - 18, y0 + 7 + (H - 17) // 2 - 1, 10, 2, 'W'); s.put(W - 8, y0 + 7 + (H - 17) // 2 - 1, 'a')
        for (hx, hy) in ((W - 21, y0 + 8), (W - 6, y0 + 8), (W - 21, y0 + H - 12), (W - 6, y0 + H - 12)): s.put(hx, hy, 'W')
    n = max(3, (W - 10) // 8)
    sx = (W - n * 8 + 2) // 2
    recess(s, sx - 2, y0 + H - 7, n * 8, 4, 'D', 'K')
    for k in range(n):
        lit = st.powered and (st.state != 'damaged' or k < n - 1)
        col = 'g' if lit else 'E'
        if st.fire and st.i == 0 and st.powered: col = 'H'
        s.hline(sx + k * 8, y0 + H - 6, 6, col); s.hline(sx + k * 8, y0 + H - 5, 6, col if col != 'H' else 'L')
        if lit and col == 'g': s.put(sx + k * 8, y0 + H - 6, 'H'); c.lightglow(sx + k * 8 + 3, y0 + H - 5.5, 4, 0.4, (107, 211, 74), 1.5)
    if c.line == 'neon': s.hline(4, y0 + 2, W - 8, 'c')
    elif c.line == 'scrap': bev(s, W - 12, y0 + 2, 9, 4, 'Q', 'u', 'n', cham=False); hazard(s, 4, y0 + H - 3, 8, 2)
    c.hurts.append(hurt_base(cracks=[[(13, y0 + 8), (15, y0 + 11), (14, y0 + 14)]], sparks=[(15, y0 + 10), (W - 6, y0 + 12)]))
    c.wrecks.append(wreck_base(cracks=[[(13, y0 + 8), (15, y0 + 12), (13, y0 + 16), (16, y0 + 19)]], wires=[[(4, y0 + 18), (7, y0 + 21), (10, y0 + 22)]]))
