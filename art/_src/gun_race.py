"""Race signatures for the gun modules (docs/GUNS.md 8: "race guns keep their identity"). Each race gun keeps the look of its homeland on the new shape:
 - a WING MOTIF that fills a wing or corner slot (x, y, w, h) of any base: a hive comb, crystals, a green coolant tank, copper coils ...
   They register in gun_mod.PARTS as 'm_<race>', so a casemate/heavy/broadside names them in `parts`, and a ring/sponson/pod takes them in `slots`;
 - HEADS that wrap a gun_mod head and add the livery band and the race's own flourish (BARREL_PARTS 'hub_liv', 'dome_liv', ...);
 - TIPS and BANDS: add-ons at the muzzle or round the tube (BARREL_PARTS 'tip_*', 'liv_band').
Colours: the livery letters '7' (dark) and '8' (light) of the race (LIV, from the race's ship palette in data/ship_styles.json), the family's own lights,
and palette letters that already exist. Nothing here adds a colour."""
import gun_mod as gm
from gun_mod import plate, tube, band, bolt_row, grille, stencil, round_disc, oct_disc, channel, rust_over
from px import *
from wbase import hazard

# race -> (dark, light) livery letters (ship_styles.json palette tint/accent, nearest palette colours)
LIV = {
 'human':     ('J', 'b'),   # concord blue and white
 'kett':      ('n', 'g'),   # hive amber body, green lamps
 'basalt':    ('u', 'o'),   # stone with an ember seam
 'emberkin':  ('e', 'o'),   # kiln red, flame orange
 'fenn':      ('q', 'y'),   # cream fur and brown, lantern yellow
 'mire':      ('[', '&'),   # bog teal and mint
 'gauntling': ('n', 'Q'),   # welded copper
 'prismatic': ('B', 'c'),   # violet body, cyan crystal edges
 'grundl':    ('u', 'a'),   # rust and amber lamps on charcoal
 'sporeling': ('Z', 'p'),   # violet and pink spores on bark
 'barons':    ('D', 'H'),   # black and white trim on gold
 'leech':     ('%', 'g'),   # the Leech Laser's green tank
 'siren':     ('B', 'C'),   # siren crystals: neon cyan, dark and mid
}
# race -> the body's steel ramp (L, M, S, W, E): the colour of the homeland ships, so a race gun is known at a glance (existing palette letters only)
STEEL = {
 'kett':      'yauqn',      # hive amber
 'prismatic': 'XVVZZ',      # violet
 'fenn':      'ffQqn',      # cream
 'mire':      ']%%[[',      # bog teal
 'sporeling': 'QQqnn',      # bark brown
 'emberkin':  'uqnnD',      # kiln: dark with a rust edge
 'grundl':    'SWEDD',      # charcoal
 'basalt':    'MSWED',      # stone
 'barons':    'yauuD',      # gold
 'leech':     'LMSWE',
}
# letters the disabled pass must darken (the livery ones)
gm.DARKX.update({']': '[', '[': 'E', 'N': 'N', 'b': 'J', 'f': 'q', '&': 'E', 'X': 'V', 'V': 'Z', 'Z': 'N', 'p': 'q', 'C': 'B', 'B': 'N', 'g': 'E', 'o': 'u', 'y': 'a', '(': 'n', ')': 'q', 'Q': 'q'})

def _plate(c, x, y, w, h): plate(c.s, x, y, w, h)

def shard(s, cx, y0, hh, ww, dark='7', lite='8', tip='H'):
    """one crystal standing in a socket: a long diamond, lit left, dark right, a bright tip."""
    for k in range(hh):
        t = k / max(1, hh - 1)
        half = (ww / 2.0) * (min(1.0, t * 2.2) if t < 0.5 else (1.0 - t) * 1.6 + 0.15)
        x0 = int(round(cx - half)); x1 = int(round(cx + half))
        for x in range(x0, x1 + 1): s.put(x, y0 + k, lite if x <= cx else dark)
    s.put(cx, y0, tip)
    s.vline(cx, y0 + 1, max(0, hh // 2 - 1), 'L')

def m_crystal(c, x, y, w, h):
    s = c.s; _plate(c, x, y, w, h)
    s.rect(x + 1, y + h - 5, w - 2, 4, 'D')                                    # the socket
    n = 3 if w >= 14 else 2
    pitch = (w - 2) // n
    for k in range(n):
        cx = x + 1 + pitch // 2 + k * pitch + (1 if k else 0)
        hh = h - 3 - (3 if k % 2 else 0)
        shard(s, cx, y + 1 + (3 if k % 2 else 0), hh, 5 if w >= 14 else 4)
    s.hline(x + 1, y + h - 5, w - 2, 'E'); bolt_row(s, [(x + 1, y + h - 2), (x + w - 2, y + h - 2)])
    c.lightglow(x + w // 2, y + h // 2, 5, 0.35, (150, 120, 255))

def m_hive(c, x, y, w, h):
    s = c.s; _plate(c, x, y, w, h)
    cell = ['.88.', '8778', '8778', '.88.']
    for r in range((h - 3) // 3):
        for k in range((w - 2) // 4):
            ox = x + 1 + k * 4 + (2 if r % 2 and (k + 1) * 4 + 3 <= w - 1 + 2 and False else 0)
            oy = y + 2 + r * 3
            if oy + 4 > y + h - 1: continue
            for j, row in enumerate(cell):
                for i, ch in enumerate(row):
                    if ch != '.': s.put(ox + i, oy + j, ch)
    s.put(x + w - 3, y + h - 3, 'g'); c.lightglow(x + w - 3, y + h - 3, 3, 0.4, (143, 224, 74))

def m_tank(c, x, y, w, h):
    """the Leech Laser's green tank: a glass-fronted drum, the level, bubbles, a draw-off pipe."""
    s = c.s; _plate(c, x, y, w, h)
    s.rect(x + 2, y + 2, w - 4, h - 5, 'K')
    lvl = y + 5
    s.rect(x + 3, lvl, w - 6, y + h - 4 - lvl, '7')
    s.hline(x + 3, lvl, w - 6, '8'); s.vline(x + 3, lvl + 1, y + h - 5 - lvl, '8')
    for (bx, by) in ((x + 5, lvl + 3), (x + w - 6, lvl + 6), (x + 7, lvl + 8)):
        s.put(bx, by, '8')
    for ty in range(y + 4, y + h - 5, 3): s.put(x + w - 4, ty, 'L')            # level ticks
    s.hline(x + 1, y + h - 3, w - 2, 'q'); s.hline(x + 1, y + h - 2, w - 2, 'n')
    c.lightglow(x + w // 2, y + h // 2, 5, 0.4, (110, 220, 90))

def m_coil(c, x, y, w, h):
    s = c.s; _plate(c, x, y, w, h)
    for k in range(2, h - 2, 2):
        s.hline(x + 2, y + k, w - 4, 'Q'); s.hline(x + 2, y + k + 1, w - 4, 'q')
    s.vline(x + w - 3, y + 2, h - 4, 'n'); s.hline(x + 1, y + 1, w - 2, '8')
    s.put(x + 2, y + h - 3, 'o'); s.put(x + w - 4, y + 3, 'o')
    c.lightglow(x + 2, y + h - 3, 2.5, 0.35, (255, 160, 64))

def m_sacs(c, x, y, w, h):
    s = c.s; _plate(c, x, y, w, h)
    s.rect(x + 1, y + 1, w - 2, h - 2, 'D')
    for k, (cx, cy, r) in enumerate(((x + w // 3, y + h // 3 + 1, 3.4), (x + w - w // 3 - 1, y + h // 2 + 3, 3.6))):
        round_disc(s, cx + .5, cy + .5, r, ('8', '8', '7', '7'))
        s.put(int(cx) - 1, int(cy) - 1, 'H'); s.put(int(cx) + 1, int(cy) + 1, 'p' if k == 0 else 'm')
    s.hline(x + 2, y + h - 3, w - 4, 'q')

def m_furnace(c, x, y, w, h):
    s = c.s; _plate(c, x, y, w, h)
    for k in range(3):
        yy = y + 3 + k * 4
        if yy + 2 > y + h - 2: break
        s.rect(x + 2, yy, w - 4, 3, 'D'); s.hline(x + 2, yy + 1, w - 4, 'o'); s.hline(x + 3, yy + 1, w - 6, 'y')
    s.hline(x + 1, y + 1, w - 2, '8'); s.hline(x + 1, y + h - 2, w - 2, '7')
    c.lightglow(x + w // 2, y + h // 2, 5, 0.4, (255, 128, 48))

def m_lantern(c, x, y, w, h):
    s = c.s; _plate(c, x, y, w, h)
    n = 2 if w < 14 else 3
    pitch = (w - 2) // n
    for k in range(n):
        cx = x + 1 + pitch // 2 + k * pitch
        top = y + 2 + (k % 2) * 3
        s.vline(cx, y + 1, top - y, '7')
        s.rect(cx - 1, top, 3, 2, '7'); s.rect(cx - 2, top + 2, 5, 5, '8'); s.rect(cx - 1, top + 3, 3, 3, 'y'); s.put(cx, top + 4, 'H')
        s.hline(cx - 2, top + 7, 5, '7')
        c.lightglow(cx, top + 4, 3.5, 0.4, (255, 240, 144))

def m_gilded(c, x, y, w, h):
    s = c.s; s.box(x, y, w, h, 'y', 'a', 'u', 'K')
    s.hline(x + 2, y + 3, w - 4, 'y')
    for k in range(2, w - 2, 3): s.put(x + k, y + h // 2, 'u'); s.put(x + k, y + h // 2 + 1, 'y')
    pts = [(x + w // 2, y + h - 6), (x + w // 2 - 1, y + h - 5), (x + w // 2 + 1, y + h - 5), (x + w // 2, y + h - 4)]
    for (px_, py_) in pts: s.put(px_, py_, 'u')
    bolt_row(s, [(x + 1, y + 1), (x + w - 2, y + 1), (x + 1, y + h - 2), (x + w - 2, y + h - 2)], 'H')

def m_concord(c, x, y, w, h):
    s = c.s; _plate(c, x, y, w, h)
    s.rect(x + 2, y + 3, w - 4, h - 7, '7')
    s.hline(x + 2, y + 3, w - 4, '8')
    s.rect(x + 3, y + h - 8, w - 6, 1, 'H')                                    # the white stripe
    cx, cy = x + w // 2, y + 6
    for dx, dy in ((0, 0), (1, 0), (-1, 0), (0, 1), (0, -1)): s.put(cx + dx, cy + dy, 'H')     # the star

def m_slab(c, x, y, w, h):
    s = c.s; _plate(c, x, y, w, h)
    s.rect(x + 1, y + 1, w // 2 - 1, h - 2, 'S'); s.rect(x + w // 2 + 1, y + 2, w - w // 2 - 2, h - 3, 'W')
    s.vline(x + w // 2, y + 1, h - 2, '8'); s.put(x + w // 2, y + h // 2, 'y')            # an ember seam
    s.hline(x + 1, y + 1, w // 2 - 1, 'M'); s.hline(x + w // 2 + 1, y + 2, w - w // 2 - 2, 'S')
    for (bx, by) in ((x + 3, y + 5), (x + w - 4, y + 8), (x + 4, y + h - 5)): s.put(bx, by, 'E'); s.put(bx + 1, by, 'E')
    c.lightglow(x + w // 2, y + h // 2, 4, 0.3, (255, 176, 96))

def m_amber(c, x, y, w, h):
    s = c.s; _plate(c, x, y, w, h)
    s.rect(x + 1, y + 1, w - 2, 5, 'u'); s.hline(x + 1, y + 1, w - 2, 'Q'); s.hline(x + 1, y + 5, w - 2, 'n')
    for k in range(3):
        lx = x + 3 + k * max(3, (w - 6) // 3)
        s.rect(lx, y + h - 6, 2, 3, 'a'); s.put(lx, y + h - 6, 'y'); s.hline(lx, y + h - 3, 2, 'n')
        c.lightglow(lx, y + h - 5, 2.5, 0.35, (255, 154, 58))
    hazard(s, x + 1, y + 7, w - 2, 2)

def m_steam(c, x, y, w, h):
    s = c.s; _plate(c, x, y, w, h)
    for k, yy in enumerate((y + 3, y + 7)):
        s.hline(x + 1, yy, w - 2, '8'); s.hline(x + 1, yy + 1, w - 2, '7')
    s.rect(x + w // 2 - 2, y + h - 7, 5, 5, 'D'); round_disc(s, x + w // 2 + .5, y + h - 4.5, 2.2, ('H', '8', '8')); s.put(x + w // 2, y + h - 5, '7')
    for (px_, py_) in ((x + 3, y + h - 3), (x + w - 4, y + h - 5), (x + w - 3, y + h - 8)): s.put(px_, py_, 'H')

MOTIFS = {'crystal': m_crystal, 'hive': m_hive, 'tank': m_tank, 'coil': m_coil, 'sacs': m_sacs, 'furnace': m_furnace,
          'lantern': m_lantern, 'gilded': m_gilded, 'concord': m_concord, 'slab': m_slab, 'amber': m_amber, 'steam': m_steam}
for k, f in MOTIFS.items(): gm.PARTS['m_' + k] = f

# ------------------------------------------------------------------ heads: a gun_mod head plus the livery band and a flourish
def _band(c, y, x0, x1):
    """a livery band across whatever is drawn at row y (only on existing pixels): dark under, light over."""
    s = c.s
    for x in range(x0, x1 + 1):
        if s.get(x, y) not in ('.', 'K') : s.g[y][x] = '8'
        if s.get(x, y + 1) not in ('.', 'K'): s.g[y + 1][x] = '7'

def hub_liv(c, flour=None, **kw):
    r = gm.hub(c, **kw)
    d = kw.get('d', 15); cx, cy = c.px, c.py
    _band(c, cy - d // 2 + 3, cx - d // 2, cx + d // 2)
    return r

def dome_liv(c, **kw):
    r = gm.dome_head(c, **kw)
    cx, cy, rr = c.px, c.py, kw.get('r', 12)
    _band(c, cy - rr + 5, cx - rr, cx + rr)
    _band(c, cy + rr - 6, cx - rr + 2, cx + rr - 2)
    return r

def pd_liv(c, **kw):
    r = gm.pd_head(c, **kw)
    cx, cy, rr = c.px, c.py, kw.get('r', 6)
    _band(c, cy - rr + 2, cx - rr, cx + rr - 2)
    return r

def breech_liv(c, **kw):
    r = gm.breech_fixed(c, **kw)
    w = kw.get('w', 15); cx, py = c.px, c.py
    c.s.hline(cx - w // 2 + 1, py - 3, w - 2, '8'); c.s.hline(cx - w // 2 + 1, py - 2, w - 2, '7')
    return r

def yoke_liv(c, **kw):
    r = gm.yoke(c, **kw)
    s = c.s; cx, py = c.px, c.py
    for k in range(-3, 4): 
        if s.get(cx + k, py + 1) != '.': s.put(cx + k, py + 1, '8')
    return r

LID_MARK = {'human': ('.H.', 'HHH', '.H.'), 'kett': ('.8.', '8H8', '.8.'), 'sporeling': ('.p.', 'pHp', '.p.'), 'fenn': ('.y.', 'yHy', '.y.')}
def lids_liv(c, n=4, race=None, **kw):
    r = gm.lids(c, n)
    s = c.s; W = c.w; pitch = (W - 8) // n
    for k in range(n):
        x = 4 + k * pitch + 1; lw = pitch - 2
        for y in range(2, 18):
            if s.get(x + 1, y) == 'M' and s.get(x + 1, y + 1) in ('S', 'M'):
                s.hline(x + 1, y + 1, lw - 2, '8'); s.hline(x + 1, y + 2, lw - 2, '7')
                if race in LID_MARK and s.get(x + lw // 2, y + 7) in ('S', 'M', 'W'): s.stamp(x + lw // 2 - 1, y + 5, LID_MARK[race])
                break
    return r

for k, f in (('hub_liv', hub_liv), ('dome_liv', dome_liv), ('pd_liv', pd_liv), ('breech_liv', breech_liv), ('yoke_liv', yoke_liv), ('lids_liv', lids_liv)):
    gm.BARREL_PARTS[k] = f

# ------------------------------------------------------------------ add-ons: round the tube and at the muzzle (drawn before the head; `c.tip` = (cx, top, w))
def _tip(c):
    if c.tip: return c.tip
    xs = [m[0] for m in c.muzzles]; top = min(m[1] for m in c.muzzles) - c.st.rc
    return ((min(xs) + max(xs)) // 2, top, max(xs) - min(xs) + 5)

def _tube_band(c, y, h=2):
    s = c.s; cx, top, w = _tip(c); o = c.st.rc
    for x in range(cx - w // 2 - 1, cx + w // 2 + 2):
        for j in range(h):
            if s.get(x, y + o + j) not in ('.', 'K'): s.g[y + o + j][x] = '8' if j == 0 else '7'

def liv_rings(c, ys=(14,), h=2): 
    for y in ys: _tube_band(c, y, h)

def tip_crystal(c, h=9):
    """a prism cluster standing on the muzzle: three facets, the centre one tall."""
    s = c.s; cx, top, w = _tip(c); o = c.st.rc
    plate(s, cx - w // 2 - 1, top + o, w + 2, 3, True, 'S', 'E', 'D')
    shard(s, cx, top - h + 3 + o, h + 3, 5)
    shard(s, cx - 4, top - h + 7 + o, h - 2, 3); shard(s, cx + 4, top - h + 7 + o, h - 2, 3)
    c.muzzles[:] = [(cx, top - h + 3 + o)]; c.lightglow(cx, top - 2 + o, 5, 0.45, (170, 150, 255))

def tip_prongs(c, reach=5):
    """chitin mandibles: two curved prongs closing on the muzzle."""
    s = c.s; cx, top, w = _tip(c); o = c.st.rc
    for side in (-1, 1):
        for k in range(reach + 3):
            x = cx + side * (w // 2 + 2 - (1 if k > reach else 0) + (k // 4 if k > 2 else 0) * -side * 0 + (1 if k < 2 else 0))
            s.put(x, top - k + 3 + o, '8'); s.put(x + side, top - k + 3 + o, '7')
        s.put(cx + side * (w // 2 + 1), top - reach + 2 + o, 'H')

def tip_barb(c, h=8):
    """a harpoon head seated in the muzzle: the barbed spear point and a line of cable."""
    s = c.s; cx, top, w = _tip(c); o = c.st.rc
    for k in range(h):
        half = 1 + (k if k < 4 else 4 - (k - 4) // 2) // 2 if k > 1 else 0
        for x in range(cx - half, cx + half + 1): s.put(x, top - h + 4 + k + o, 'L' if x <= cx else 'M')
    s.put(cx, top - h + 4 + o, 'H')
    for k in range(3): s.put(cx - 3 - (k % 2), top + 2 + k * 3 + o, 'q'); s.put(cx + 3 + (k % 2), top + 3 + k * 3 + o, 'q')

def tip_flare(c, extra=3):
    """a bell mouth: the muzzle flares (flare turrets, mortars, brass horns)."""
    s = c.s; cx, top, w = _tip(c); o = c.st.rc
    ww = w + 2 * extra
    for k in range(5):
        half = (w // 2) + (extra * (5 - k)) // 5 + (1 if k < 2 else 0)
        for x in range(cx - half, cx + half + 1): s.put(x, top + k + o, 'L' if k == 0 else ('M' if x <= cx else 'S'))
    s.hline(cx - ww // 2, top + 5 + o, ww, 'E')
    gm.lens_up(s, cx - (w - 4) // 2, top + 1 + o, w - 4, 3, gm.lens_mode(c))
    c.muzzles[:] = [(cx, top + 1 + o)]

def tip_fork(c):
    """two short rails standing either side of the muzzle (a rail's accelerator fork)."""
    s = c.s; cx, top, w = _tip(c); o = c.st.rc
    for side in (-1, 1):
        x = cx + side * (w // 2 + 2) - (1 if side < 0 else 0)
        plate(s, x, top - 5 + o, 2, 10, cham=False); s.put(x + (0 if side < 0 else 1), top - 5 + o, '8')

def tip_crown(c):
    """a gilded crown of three points round the muzzle (the barons' guns)."""
    s = c.s; cx, top, w = _tip(c); o = c.st.rc
    for dx in (-3, 0, 3):
        for k in range(4): s.put(cx + dx, top - k + 1 + o, 'y' if k < 3 else 'H')
        s.put(cx + dx + 1, top + 1 + o, 'u')
    s.hline(cx - 4, top + 1 + o, 9, 'a')

def tip_vent(c):
    """steam: a vent pipe each side of the muzzle with a white puff."""
    s = c.s; cx, top, w = _tip(c); o = c.st.rc
    for side in (-1, 1):
        x = cx + side * (w // 2 + 2)
        s.vline(x, top + o, 6, '8'); s.put(x + side, top + 1 + o, '7')
        s.put(x, top - 2 + o, 'H'); s.put(x + side, top - 3 + o, 'H'); s.put(x - side, top - 4 + o, 'H')

for k, f in (('tip_fork', tip_fork), ('tip_crown', tip_crown), ('tip_vent', tip_vent), ('liv_rings', liv_rings), ('tip_crystal', tip_crystal), ('tip_prongs', tip_prongs), ('tip_barb', tip_barb), ('tip_flare', tip_flare)): gm.BARREL_PARTS[k] = f
