"""Gun sample sheets (the review gate of docs/GUNS.md section 7): builds guns from module recipes (gun_mod.py) and writes ONLY preview sheets.
Nothing here writes into art/components. Usage: python3 gun_samples.py [out_dir] [sheet ...]   (sheets: shapes lines versions families states ship)

A recipe names the shape (GUNS.md section 3), the family, the base module with its arguments, then the barrel: its canvas (width, and how far
the tip reaches above the pivot), a head by aim class (breech_fixed, yoke, hub, dome_head, pd_head, lids), a tube and add-ons:
    R('laser_heavy', 'heavy', 'laser', ('heavy', dict(parts=('cells', 'vent'))), 25, 47,
      ('breech_fixed', dict(w=19, heavy=True)), ('single', dict(w=15, rings=3, heavy=True)), [('brake', {})])
`.variant(line=..., fam=...)` gives the same gun in another line or family. Barrel frames: idle, off, fire 0-2, damaged 0-1, disabled,
plus spin 0-3 (rotary, `lit` = the chain step) and charge (capacitor, `lit` = rings lit 0-3)."""
import math, os, sys
from px import *
import gun_mod as gm
from gun_mod import Ctx, Look, St, FLANGE
from compose import rotate
from sheet_v2 import text

SPACE = (14, 18, 28)
#            outside cells  breech cells  aim       arc (turret / swivel: total degrees; fixed: gimbal either side)
SHAPES = {
 'point':     ((2, 2), (2, 2), 'turret', 300),
 'dome':      ((3, 3), (2, 2), 'turret', 300),
 'sponson':   ((3, 2), (2, 2), 'swivel', 180),
 'casemate':  ((4, 2), (2, 2), 'fixed', 6),
 'long':      ((2, 4), (2, 2), 'fixed', 3),
 'broadside': ((6, 2), (4, 2), 'fixed', 20),
 'strip':     ((8, 1), (4, 2), 'fixed', 20),
 'heavy':     ((4, 3), (4, 2), 'fixed', 4),
 'spinal':    ((2, 6), (2, 4), 'fixed', 2),
 'pod':       ((4, 1), (2, 2), 'fixed', 10),
}
BASES = {'casemate4': gm.casemate4, 'casemate6': gm.casemate6, 'casemate2': gm.casemate2, 'heavy': gm.heavy4, 'spinal': gm.spinal,
         'sponson': gm.sponson, 'strip': gm.strip8, 'pod': gm.pod_plate, 'ring': gm.ring_base}
BPAD = 16                 # barrel glow padding (the muzzle flash reaches past the tip)
OPAD = 8

def _flash_up():
    from wbase import FLASH_E, ccw
    return [ccw(from_art(a)) for a in FLASH_E]
FLASH_UP = _flash_up()

class Gun:
    """one gun from a recipe: the outside half, the barrel(s) and the breech, each frame recoloured by line and family."""
    def __init__(s, name, shape, fam='laser', line='standard', base=('casemate4', {}), barrel=None, label=None, breech=None):
        s.name, s.shape, s.fam, s.line = name, shape, fam, line
        s.out_cells, s.in_cells, s.aim, s.arc = SHAPES[shape]
        s.base, s.bar = base, barrel
        s.label = label or name
        s.look = Look(line, fam)
    def variant(s, **kw):
        d = dict(name=s.name, shape=s.shape, fam=s.fam, line=s.line, base=s.base, barrel=s.bar, label=s.label)
        d.update(kw); return Gun(**d)
    # ---- outside half
    def out(s, state='on', i=0):
        W, H = s.out_cells[0] * 16, s.out_cells[1] * 16 + FLANGE
        c = Ctx(W, H, s.look, St(state, i))
        name, kw = s.base
        BASES[name](c, **kw)
        gm.flange(c, H - FLANGE - 1, W)
        return gm.finish(c), gm.glow_layer(c, OPAD), c.pivots
    # ---- barrel
    def barrel(s, state='idle', i=0, lit=None):
        b = s.bar
        if not b: return None
        w, reach = b['w'], b['reach']
        st = St(state, i, lit)
        def canvas():
            c = Ctx(w, reach + b.get('tail', 12), s.look, st); c.px, c.py = w // 2, reach; return c
        hn, hkw = b['head']
        neck = gm.BARREL_PARTS[hn](canvas(), **hkw)                       # where the tube meets the head (a dry run)
        c = canvas()
        if b.get('tube'):
            tn, tkw = b['tube']
            gm.BARREL_PARTS[tn](c, b.get('top', 1), neck + 1, **tkw)
        for an, akw in b.get('add', []): gm.BARREL_PARTS[an](c, **akw)
        gm.BARREL_PARTS[hn](c, **hkw)
        spr = gm.finish(c, shadow=False)
        g = gm.glow_layer(c, BPAD, (lambda g, p: s.flash_glow(c, g, p)) if st.fire else None)
        return spr, g, (c.px, c.py)
    def flash_glow(s, c, g, p):
        """the muzzle flash on the glow layer: a hard-edged flash shape in the family colour, a white core, a soft halo."""
        i = c.st.i; fr = FLASH_UP[i]
        rgb, core = s.look.rgb, s.look.core
        for (mx, my) in c.muzzles:
            gm.glow(g, p + mx + 0.5, p + my - 2 + i, (11, 8, 6)[i], rgb, (0.55, 0.45, 0.3)[i], 2.0)
            ox, oy = p + mx - fr.w // 2, p + my - fr.h + 1
            for y in range(fr.h):
                for x in range(fr.w):
                    ch = fr.g[y][x]
                    if ch == '.': continue
                    col, a = {'H': (core, 250), 'y': (mix(core, rgb, 0.45), 225), 'o': (rgb, 170)}[ch]
                    g.over(ox + x, oy + y, col + (a,))
    # ---- breech
    def breech(s, state='on', i=0):
        W, H = s.in_cells[0] * 16, s.in_cells[1] * 16 + FLANGE
        c = Ctx(W, H, s.look, St(state, i))
        gm.breech_in(c, s.in_cells)
        gm.flange(c, 0, W, up=False)
        return gm.finish(c), gm.glow_layer(c, OPAD)

# ------------------------------------------------------------------ rendering
def turn_rgba(o, deg, cx, cy):
    """nearest-neighbour turn of a glow layer about (cx, cy) (soft alpha: no jaggies to worry about)."""
    n = Rgba(o.w, o.h); t = math.radians(deg); co, si = math.cos(t), math.sin(t)
    for y in range(o.h):
        for x in range(o.w):
            dx, dy = x + .5 - cx, y + .5 - cy
            sx, sy = co * dx + si * dy + cx, -si * dx + co * dy + cy
            xi, yi = int(math.floor(sx)), int(math.floor(sy))
            if 0 <= xi < o.w and 0 <= yi < o.h: n.p[y][x] = list(o.p[yi][xi])
    return n

def place_barrel(img, bar, x, y, deg, glow_on=True):
    """blit a barrel sprite so its pivot lands on (x, y), turned by deg (0 = up, clockwise positive)."""
    spr, g, (px, py) = bar
    if deg:
        S = 2 * max(spr.w, spr.h) + 4; h = S // 2
        cv = Spr(S, S); cv.stamp(h - px, h - py, spr.rows())
        img.blit_spr(rotate(cv, deg, h, h), x - h, y - h)
        if glow_on and g:
            G = Rgba(S + 2 * BPAD, S + 2 * BPAD); G.blit_rgba(g, h - px, h - py)
            img.blit_rgba(turn_rgba(G, deg, h + BPAD, h + BPAD), x - h - BPAD, y - h - BPAD, 1, add=True)
    else:
        img.blit_spr(spr, x - px, y - py)
        if glow_on and g: img.blit_rgba(g, x - px - BPAD, y - py - BPAD, 1, add=True)

def wall_rows(w, rows=2):
    s = Spr(w, 16 * rows)
    for r in range(rows):
        for cx in range(w // 16 + 1):
            x, y = cx * 16, r * 16
            s.rect(x, y, 16, 16, 'D'); s.hline(x, y, 16, 'E')
            for (rx, ry) in ((3, 3), (12, 3), (3, 12), (12, 12)): s.put(x + rx, y + ry, 'W')
    return s

def space_bg(img, x0, y0, x1, y1, seed=0):
    for y in range(y0, y1):
        for x in range(x0, x1): img.p[y][x] = list(SPACE) + [255]
    n = (x1 - x0) * (y1 - y0) // 160
    h = 2166136261 ^ seed
    for k in range(n):                                                         # a fixed hash, so the stars never line up
        h = (h * 16777619 + k * 2654435761) & 0xffffffff; x = x0 + h % max(1, x1 - x0)
        h = (h * 16777619 + 97) & 0xffffffff; y = y0 + (h >> 7) % max(1, y1 - y0)
        img.p[y][x] = [120 + (k % 3) * 40, 130 + (k % 3) * 40, 160 + (k % 3) * 30, 255]

def floor_bg(img, x0, y0, x1, y1):
    for y in range(y0, y1):
        for x in range(x0, x1):
            img.p[y][x] = list(RGB['G'] if ((x - x0) % 16 == 0 or (y - y0) % 16 == 0) else RGB['F']) + [255]

ARC_RGB = {'fixed': (232, 108, 88), 'swivel': (240, 196, 90), 'turret': (110, 184, 240)}     # the sketch's arc colours
def draw_arc(img, gun, cx, cy, r, y_max):
    """the aim arc as a faint wedge behind the gun (space only): red fixed, yellow swivel, blue turret."""
    half = gun.arc / 2.0 if gun.aim != 'fixed' else gun.arc
    rgb = ARC_RGB[gun.aim]
    for y in range(max(0, int(cy - r - 1)), min(y_max, int(cy + r + 2))):
        for x in range(max(0, int(cx - r - 1)), min(img.w, int(cx + r + 2))):
            dx, dy = x + .5 - cx, y + .5 - cy
            d = (dx * dx + dy * dy) ** 0.5
            if d > r or d < 3: continue
            a = math.degrees(math.atan2(dx, -dy))
            if abs(a) > half: continue
            edge = d > r - 1.2 or abs(abs(a) - half) * math.pi / 180 * d < 1.0
            img.over(x, y, rgb + ((120 if edge else 34),))

def scene(gun, ostate='on', oi=0, bstate='idle', bi=0, deg=0, istate='on', ii=0, pad=16, top=None, arc=0, glow_on=True, lit=None, stagger=False, w=None):
    """outside half in space + a 2-row wall + the breech on the floor, every barrel turned by deg."""
    fo, go, pivots = gun.out(ostate, oi)
    fi, gi = gun.breech(istate, ii)
    reach = gun.bar['reach'] if gun.bar else 0
    oy_foot = gun.out_cells[1] * 16
    if top is None: top = (max(10, reach - min(p[1] for p in pivots) + 14) if gun.bar else 14) + (10 if bstate == 'fire' else 0)
    W = w or max(fo.w, fi.w) + 2 * pad
    H = top + oy_foot + 32 + fi.h - FLANGE + 12
    img = Rgba(W, H, RGB['F'] + (255,))
    wy = top + oy_foot
    space_bg(img, 0, 0, W, wy, len(gun.name)); floor_bg(img, 0, wy + 32, W, H)
    ox = (W - fo.w) // 2
    if arc:
        for (px, py) in pivots: draw_arc(img, gun, ox + px, top + py, arc, wy)
    img.blit_spr(wall_rows(W), 0, wy)
    img.blit_spr(fo, ox, top)
    ix = (W - fi.w) // 2; iy = wy + 32 - FLANGE
    img.blit_spr(fi, ix, iy)
    if glow_on:
        img.blit_rgba(go, ox - OPAD, top - OPAD, 1, add=True); img.blit_rgba(gi, ix - OPAD, iy - OPAD, 1, add=True)
    if gun.bar:
        for k, (px, py) in enumerate(pivots):
            bs, b_i = bstate, bi
            if stagger and bstate == 'fire':
                b_i = bi + k
                if b_i > 2: bs, b_i = 'idle', 0
            place_barrel(img, gun.barrel(bs, b_i, lit), ox + px, top + py, deg, glow_on)
    return img

def paste(img, a, x, y, K=1):
    """copy an opaque surface onto the sheet, scaled K times (nearest): rows are copied, not blended."""
    for j in range(a.h):
        row = [list(p) for p in a.p[j] for _ in range(K)]
        for dy in range(K):
            yy = y + j * K + dy
            if 0 <= yy < img.h: img.p[yy][x:x + len(row)] = [list(p) for p in row]

def put_scene(img, a, x, y, K, label=None, sub=None, col='H'):
    paste(img, a, x, y, K)
    if label: text(img, x + 6, y + 6, label, col, 3)
    if sub:                                                                   # wrap at double spaces when the scene is narrow
        lines = [sub] if len(sub) * 12 <= a.w * K - 8 else sub.split('  ')
        for k, ln in enumerate(reversed(lines)): text(img, x + 6, y + a.h * K - 22 - 20 * k, ln, 'L', 3)

def grid(cells, K=3, W=2400, gap=14, title=None, row_h=None):
    """lay scenes out left to right, wrapping; returns the sheet."""
    rows, cur, cw = [], [], 20
    for it in cells:
        a = it[0]
        if cur and cw + a.w * K > W - 20: rows.append(cur); cur, cw = [], 20
        cur.append(it); cw += a.w * K + gap
    if cur: rows.append(cur)
    H = (60 if title else 20) + sum(max(it[0].h for it in r) * K + gap for r in rows) + 10
    img = Rgba(W, H, RGB['F'] + (255,))
    y = 20
    if title: text(img, 20, y, title, 'H', 4); y += 40
    for r in rows:
        x = 20; rh = max(it[0].h for it in r) * K
        for it in r:
            a, lab = it[0], it[1]; sub = it[2] if len(it) > 2 else None
            put_scene(img, a, x, y + rh - a.h * K, K, lab, sub)
            x += a.w * K + gap
        y += rh + gap
    return img

SHEETS = {}
# ------------------------------------------------------------------ recipes
FIXED = ('breech_fixed', {})
def R(name, shape, fam, base, w, reach, head, tube=None, add=(), label=None, line='standard'):
    """a recipe: the base module and its arguments; the barrel canvas (width, reach above the pivot), its head, tube and add-ons."""
    return Gun(name, shape, fam, line, base, dict(w=w, reach=reach, head=head, tube=tube, add=list(add)), label)

LASER_MK1 = R('laser_mk1', 'casemate', 'laser', ('casemate4', dict(parts=('cells', 'sensor'))), 19, 35, FIXED, ('single', dict(rings=4)), label='LASER MK I')
LASER_MK2 = R('laser_mk2', 'casemate', 'laser', ('casemate4', dict(parts=('caps', 'vent'))), 21, 36, FIXED, ('twin', {}), label='LASER MK II')
LASER_MK3 = R('laser_mk3', 'casemate', 'laser', ('casemate4', dict(parts=('coolant', 'vent'), mk3=True)), 23, 38, ('breech_fixed', dict(heavy=True)), ('twin', dict(coil=True)), label='LASER MK III')
LASER_LIGHT = R('laser_light', 'point', 'laser', ('ring', dict(cells=2)), 17, 17, ('hub', {}), ('short', dict(w=7, rings=1)), label='LASER LIGHT')
LASER_HEAVY = R('laser_heavy', 'heavy', 'laser', ('heavy', dict(parts=('cells', 'vent'))), 25, 47, ('breech_fixed', dict(w=19, heavy=True)),
                ('single', dict(w=15, rings=3, heavy=True)), [('brake', {})], label='LASER HEAVY')
LASER_BURST = R('laser_burst', 'broadside', 'laser', ('casemate6', dict(n=3, parts=('cells', 'sensor'))), 15, 30, ('breech_fixed', dict(w=11)), ('single', dict(w=7, rings=2)), label='LASER BURST')
LASER_CHAIN = R('laser_chain', 'casemate', 'laser', ('casemate4', dict(parts=('cells', 'vent'))), 19, 40, FIXED, ('rotary', {}), label='LASER CHAIN')
LASER_CHARGE = R('laser_charge', 'sponson', 'laser', ('sponson', {}), 19, 35, ('yoke', {}), ('capacitor', {}), label='LASER CHARGE')
BEAM_LIGHT = R('beam_light', 'sponson', 'beam', ('sponson', {}), 19, 33, ('yoke', {}), ('single', dict(w=9, rings=3)), label='BEAM LIGHT')
LASER_LONG = R('laser_long', 'long', 'laser', ('casemate2', {}), 17, 86, ('breech_fixed', dict(w=13)), ('long', {}), label='LASER LONG')
LASER_LANCE = R('laser_lance', 'spinal', 'laser', ('spinal', {}), 17, 104, ('breech_fixed', dict(w=13)), ('lance', {}), label='LASER LANCE')
MISSILE_POD = R('missile_pod', 'pod', 'missile', ('pod', {}), 64, 8, ('lids', {}), label='MISSILE POD')
PD_MK1 = R('pd_mk1', 'point', 'pd', ('ring', dict(cells=2)), 17, 19, ('pd_head', {}), ('pd_twin', dict(gap=3)), label='PD MK I')
FLAK_DOME = R('flak_turret', 'dome', 'flak', ('ring', dict(cells=3)), 27, 33, ('dome_head', {}), ('triple', {}), label='FLAK TURRET')
GUN_STRIP = R('gun_strip', 'strip', 'laser', ('strip', dict(n=5)), 11, 14, ('breech_fixed', dict(w=7)), ('single', dict(w=5, rings=1)), label='GUN STRIP')

ARC_TXT = {'turret': 'TURRET %d', 'swivel': 'SWIVEL %d', 'fixed': 'FIXED +-%d'}
def shape_label(g):
    o, i = g.out_cells, g.in_cells
    return '%s %dX%d IN %dX%d' % (g.shape.upper(), o[0], o[1], i[0], i[1]), ARC_TXT[g.aim] % g.arc

def sheet_shapes():
    guns = [LASER_LIGHT, BEAM_LIGHT, LASER_MK1, MISSILE_POD, GUN_STRIP,
            FLAK_DOME, LASER_BURST.variant(fam='pulse', label='PULSE BATTERY'), LASER_HEAVY.variant(fam='pulse', label='PULSE HEAVY'),
            LASER_LONG.variant(fam='slug', label='SLUG RAIL'), LASER_LANCE.variant(fam='ion', label='ION SPINAL')]
    cells = []
    for g in guns:
        a, b = shape_label(g)
        _, _, pv = g.out()
        R = {'turret': 40 + 8 * (g.out_cells[0] - 2), 'swivel': 44, 'fixed': 72}[g.aim]
        kw = dict(arc=R)
        if g.aim != 'fixed':                                                   # room for the whole disc or fan
            kw.update(pad=max(16, R + 6 - g.out_cells[0] * 8), top=max(14, R + 6 - pv[0][1]))
        else: kw.update(pad=24 if g.out_cells[0] >= 4 else 36)
        cells.append((scene(g, **kw), a, g.label + '  ' + b))
    return grid(cells, 3, 2400, title='GUN SHAPES: ONE GUN PER SHAPE, STANDARD LINE, AIM ARC BEHIND IT. RED FIXED, YELLOW SWIVEL, BLUE TURRET')
SHEETS['shapes'] = sheet_shapes

def strip_cell(spr, g, pad, K, label):
    """one sprite on the sheet's grey with its glow, labelled underneath (as the reference sheets show frames)."""
    a = Rgba(spr.w + 2 * pad, spr.h + 2 * pad + 6, RGB['F'] + (255,))
    a.blit_spr(spr, pad, pad)
    if g is not None: a.blit_rgba(g, 0, 0, 1, add=True)
    return (a, None, label)

def frames_row(gun, K=3):
    """the outside half's frames and the barrel's frames of one gun."""
    out = []
    for (st, i, lab) in (('on', 0, 'OUT ON 0'), ('on', 1, 'OUT ON 1'), ('off', 0, 'OUT OFF'), ('damaged', 0, 'OUT DAMAGED 0'), ('damaged', 1, 'OUT DAMAGED 1'),
                         ('disabled', 0, 'OUT DISABLED 0'), ('disabled', 1, 'OUT DISABLED 1')):
        f, g, _ = gun.out(st, i); out.append(strip_cell(f, g, OPAD, K, lab))
    for (st, i, lab) in (('idle', 0, 'IDLE'), ('off', 0, 'OFF'), ('fire', 0, 'FIRE 0'), ('fire', 1, 'FIRE 1'), ('fire', 2, 'FIRE 2'), ('damaged', 0, 'DMG 0'), ('damaged', 1, 'DMG 1'), ('disabled', 0, 'DISABLED')):
        f, g, _ = gun.barrel(st, i); out.append(strip_cell(f, g, BPAD, K, lab))
    return out

def sheet_stack(blocks, W=2400, K=3):
    """stack titled grids: blocks = [(title, cells)]."""
    imgs = [grid(cells, K, W, title=title) for title, cells in blocks]
    H = sum(i.h for i in imgs) + 10 * len(imgs)
    img = Rgba(W, H, RGB['F'] + (255,))
    y = 0
    for k, im in enumerate(imgs):
        paste(img, im, 0, y); y += im.h
        if k < len(imgs) - 1:
            for x in range(W): img.p[y + 4][x] = list(RGB['G']) + [255]
        y += 10
    return img

def sheet_lines():
    cells = []
    for g, nm in ((LASER_MK1, 'CASEMATE'), (LASER_LIGHT, 'POINT'), (BEAM_LIGHT, 'SPONSON BEAM'), (LASER_BURST.variant(fam='pulse'), 'BROADSIDE PULSE')):
        cells += [(scene(g.variant(line=ln), pad=14), ln.upper(), nm) for ln in gm.LINES]
    return grid(cells, 3, 2400, title='LINES: SCRAP / STANDARD / NEON ON THE SAME RECIPES. RUST HAZARD TAPE AND WELDS  CLEAN STEEL  NAVY WITH CYAN EDGES')

def sheet_versions():
    guns = [LASER_MK1, LASER_MK2, LASER_MK3, LASER_CHAIN, LASER_LIGHT, PD_MK1, MISSILE_POD, LASER_CHARGE, LASER_BURST, LASER_HEAVY, LASER_LONG, LASER_LANCE]
    notes = {'laser_mk1': 'SINGLE RIBBED BARREL', 'laser_mk2': '+ TWIN RAILS  CAPS', 'laser_mk3': '+ COIL BRIDGE  COOLANT', 'laser_light': 'ONE SHORT BARREL',
             'laser_heavy': 'DOUBLE SLEEVE STRUTS BRAKE', 'laser_burst': '3 BARRELS STAGGERED', 'laser_chain': 'ROTARY CLUSTER', 'laser_charge': '3 CAPACITOR RINGS',
             'laser_long': 'LONG BARREL  FIN ROW', 'laser_lance': 'SPINAL SLEEVE  RINGS', 'missile_pod': 'HATCH LIDS', 'pd_mk1': 'DOME  TWIN  RADAR EYE'}
    cells = []
    for g in guns:
        kw = dict(pad=24 if g.out_cells[0] >= 4 else 30)
        if g is LASER_CHARGE: kw.update(lit=2, bstate='charge')
        cells.append((scene(g, **kw), g.label, notes[g.name]))
    return grid(cells, 3, 2400, title='LASER VERSIONS (GUNS.MD 5 AND 7): EACH READS BY ITS ADD-ON. PLUS A MISSILE POD AND A PD MK I. STANDARD LINE')

def sheet_families():
    cells = []
    for f in gm.FAMILIES:
        g = LASER_MK1.variant(fam=f, label=f.upper())
        cells.append((scene(g, pad=12), f.upper()))
    fire = [(scene(LASER_MK1.variant(fam=f), bstate='fire', istate='fire', pad=12), f.upper() + ' FIRE 0') for f in gm.FAMILIES]
    return sheet_stack([('FAMILIES: THE SAME CASEMATE IN EACH FAMILY COLOUR. THE COLOUR LIVES IN THE LIGHT PIXELS AND THE GLOW ONLY', cells),
                        ('FIRING: THE MUZZLE FLASH IS ON THE GLOW LAYER IN THE FAMILY COLOUR', fire)])

def sheet_states():
    blocks = []
    for g, turret in ((LASER_MK1, False), (FLAK_DOME, True)):
        blocks.append(('%s FRAMES: OUTSIDE HALF  THEN BARREL  3X  WITH GLOW' % g.label, frames_row(g)))
        if turret: plan = [(0, 'TURRET 0', {}), (45, 'TURRET 45', {}), (-60, 'TURRET -60', {}), (0, 'FIRE 0', dict(bstate='fire', bi=0, istate='fire')),
                           (-60, 'FIRE 1 AT -60', dict(bstate='fire', bi=1, istate='fire', ii=1))]
        else: plan = [(0, 'FIXED 0', {}), (6, 'GIMBAL +6', {}), (0, 'FIRE 0', dict(bstate='fire', bi=0, istate='fire')),
                      (-6, 'FIRE 2 GIMBAL -6', dict(bstate='fire', bi=2, istate='fire', ii=1))]
        plan += [(0, 'OFF', dict(ostate='off', istate='off', bstate='off')), (0, 'DAMAGED 0', dict(ostate='damaged', bstate='damaged', istate='damaged')),
                 (0, 'DAMAGED 1', dict(ostate='damaged', oi=1, bstate='damaged', bi=1, istate='damaged', ii=1)), (0, 'DISABLED', dict(ostate='disabled', bstate='disabled', istate='disabled'))]
        cells = []
        for (deg, lab, kw) in plan:
            a = scene(g, deg=deg, pad=14 if not turret else 16, **kw)
            cells.append((a, lab))
        blocks.append(('%s IN CONTEXT' % g.label, cells))
    chain = [(scene(LASER_CHAIN, bstate='spin', bi=i, lit=0, pad=12), 'SPIN %d' % i) for i in range(4)]
    chain += [(scene(LASER_CHAIN, bstate='spin', bi=i, lit=i, pad=12), 'STEP %d HEAT' % i) for i in (1, 2, 3)]
    chain += [(scene(LASER_CHAIN, bstate='fire', bi=0, lit=3, istate='fire', pad=12), 'FIRE STEP 3')]
    blocks.append(('LASER CHAIN: ROTARY SPIN FRAMES 0-3 (PLAYED FASTER EACH STEP), THEN HEAT AT STEPS 1-3', chain))
    charge = [(scene(LASER_CHARGE, bstate='charge', lit=k, pad=16), 'CHARGE %d' % k) for k in range(4)]
    charge += [(scene(LASER_CHARGE, bstate='fire', bi=i, istate='fire', pad=16), 'RELEASE %d' % i) for i in range(3)]
    charge += [(scene(LASER_CHARGE, deg=-70, bstate='charge', lit=3, pad=24), 'SWIVEL -70  3 HELD')]
    blocks.append(('LASER CHARGE: CAPACITOR RINGS LIT 0-3 AS VOLLEYS ARE STORED, THEN RELEASED', charge))
    pd = [(scene(PD_MK1, deg=d, pad=22, **kw), lab) for d, lab, kw in ((0, 'PD 0', {}), (-50, 'TRACK -50', {}), (70, 'TRACK 70', {}), (70, 'FIRE', dict(bstate='fire', istate='fire')))]
    pod = [(scene(MISSILE_POD, bstate=b, bi=i, istate='fire' if b == 'fire' else 'on', pad=10), lab) for b, i, lab in (('idle', 0, 'POD SHUT'), ('fire', 0, 'LIDS OPEN'), ('fire', 1, 'HALF'), ('fire', 2, 'CLOSING'))]
    blocks.append(('PD TRACKING AND THE POD LIDS', pd + pod))
    return sheet_stack(blocks)

# ------------------------------------------------------------------ the ship sheet: a small hull carrying the shapes, at the game's scale
def rot_rgba(o, k):
    for _ in range(k % 4):
        n = Rgba(o.h, o.w)
        for y in range(o.h):
            for x in range(o.w): n.p[x][o.h - 1 - y] = list(o.p[y][x])
        o = n
    return o

def mount_local(gun, deg=0, bstate='idle', bi=0, istate='on', lit=None, stagger=False):
    """one mount at rotation 0 on its own transparent canvas (outside half, a 1-cell wall gap, the breech), plus its glow;
    returns (sprite layer, glow layer, margin, grid cells (w, h))."""
    fo, go, pivots = gun.out()
    fi, gi = gun.breech(istate)
    ow, oh = gun.out_cells; iw, ih = gun.in_cells
    wc, hc = max(ow, iw), oh + 1 + ih
    m = (gun.bar['reach'] if gun.bar else 0) + 8
    L = Rgba(wc * 16 + 2 * m, hc * 16 + 2 * m); G = Rgba(L.w, L.h)
    ox, iy = m + (wc - ow) // 2 * 16, m + (oh + 1) * 16 - FLANGE
    ix = m + (wc - iw) // 2 * 16
    L.blit_spr(fo, ox, m); L.blit_spr(fi, ix, iy)
    G.blit_rgba(go, ox - OPAD, m - OPAD); G.blit_rgba(gi, ix - OPAD, iy - OPAD)
    for k, (px, py) in enumerate(pivots):
        bs, b_i = bstate, bi
        if stagger and bstate == 'fire':
            b_i = bi + k
            if b_i > 2: bs, b_i = 'idle', 0
        bar = gun.barrel(bs, b_i, lit)
        if bar: place_barrel(L, bar, ox + px, m + py, deg, False); place_glow(G, bar, ox + px, m + py, deg)
    return L, G, m, (wc, hc)

def place_glow(G, bar, x, y, deg):
    spr, g, (px, py) = bar
    if not g: return
    if deg:
        S = 2 * max(spr.w, spr.h) + 4; h = S // 2
        T = Rgba(S + 2 * BPAD, S + 2 * BPAD); T.blit_rgba(g, h - px, h - py)
        G.blit_rgba(turn_rgba(T, deg, h + BPAD, h + BPAD), x - h - BPAD, y - h - BPAD)
    else: G.blit_rgba(g, x - px - BPAD, y - py - BPAD)


# the hull: 10 x 16 cells, prow up. '#' wall, '.' floor, ' ' space
HULL = [
 '   ####   ',
 '   #..#   ',
 '   #..#   ',
 '##########',
 '#........#',
 '#........#',
 '#........#',
 '#...##...#',
 '#........#',
 '#........#',
 '#........#',
 '#...##...#',
 '#........#',
 '#........#',
 '#........#',
 '##########',
]
SHIP = [  # (recipe, rotation in quarter turns: 0 out = up, 1 right, 3 left, the wall cell where the grid starts (col, row))
 ('prow',  0, (4, 0)),
 ('point', 0, (7, 3)),
 ('dome',  3, (0, 5)),
 ('bs_l',  3, (0, 9)),
 ('bs_r',  1, (9, 5)),
 ('pod',   1, (9, 11)),
]
def ship_guns():
    return {'prow': LASER_LONG.variant(fam='slug'), 'point': LASER_LIGHT, 'dome': FLAK_DOME,
            'bs_l': LASER_BURST.variant(fam='pulse'), 'bs_r': LASER_BURST.variant(fam='pulse'), 'pod': MISSILE_POD}

def draw_ship(fight=False, line='standard', K=2):
    guns = {k: (g.variant(line=line) if line != 'standard' else g) for k, g in ship_guns().items()}
    MX, MY = 5, 7                                                             # cells of space round the hull (the prow gun needs the top)
    W, H = (10 + 2 * MX) * 16, (16 + MY + 2) * 16
    img = Rgba(W, H, SPACE + (255,)); space_bg(img, 0, 0, W, H, 3)
    hull = Spr(W, H)
    for r, row in enumerate(HULL):
        for cc, ch in enumerate(row):
            x, y = (MX + cc) * 16, (MY + r) * 16
            if ch == '#':
                hull.rect(x, y, 16, 16, 'D'); hull.hline(x, y, 16, 'E')
                for (rx, ry) in ((3, 3), (12, 3), (3, 12), (12, 12)): hull.put(x + rx, y + ry, 'W')
            elif ch == '.':
                hull.rect(x, y, 16, 16, 'F'); hull.hline(x, y, 16, 'G'); hull.vline(x, y, 16, 'G')
    img.blit_spr(hull, 0, 0)
    glows = []
    aim = {'point': 35, 'dome': 35 - 270 + 360, 'prow': 0}
    for key, k, (wc_, wr_) in SHIP:
        g = guns[key]
        kw = {}
        if fight:
            if g.aim != 'fixed': kw['deg'] = max(-g.arc / 2, min(g.arc / 2, ((40 - 90 * k + 180) % 360) - 180))
            if key in ('bs_r', 'prow', 'pod', 'dome'): kw.update(bstate='fire', bi=0, istate='fire', stagger=key.startswith('bs'))
            if key == 'point': kw.update(bstate='fire', bi=1)
        L, G, m, (wc, hc) = mount_local(g, **kw)
        oh = g.out_cells[1]; ih = g.in_cells[1]
        if k == 0: gx, gy = wc_ - 0, wr_ - oh
        elif k == 1: gx, gy = wc_ - ih, wr_
        elif k == 3: gx, gy = wc_ - oh, wr_
        else: gx, gy = wc_, wr_ - ih
        Lr, Gr = rot_rgba(L, k), rot_rgba(G, k)
        if k == 0: ax, ay = m, m
        elif k == 1: ax, ay = L.h - m - hc * 16, m
        elif k == 3: ax, ay = m, L.w - m - wc * 16
        else: ax, ay = L.w - m - wc * 16, L.h - m - hc * 16
        X, Y = (MX + gx) * 16 - ax, (MY + gy) * 16 - ay
        img.blit_rgba(Lr, X, Y); glows.append((Gr, X, Y))
    for (Gr, X, Y) in glows: img.blit_rgba(Gr, X, Y, 1, add=True)
    return img

def sheet_ship():
    a, b = draw_ship(), draw_ship(fight=True)
    c = draw_ship(line='scrap', fight=True); d = draw_ship(line='neon')
    W = 2400; K = 2
    H = 60 + a.h * K + 40 + a.h + 40
    img = Rgba(W, H, RGB['F'] + (255,))
    text(img, 20, 20, 'A COURIER-SIZE HULL 10X16 AT THE GAME SCALE 2 PX PER SOURCE PX: LONG BARREL ON THE PROW  POINT TURRET ON A SHOULDER  DOME AMIDSHIPS', 'H', 3)
    text(img, 20, 40, 'BROADSIDE ON EACH FLANK  FLUSH POD AFT. STANDARD AT REST  STANDARD IN A FIGHT  NEON AT REST. IN A FIGHT THE TURRETS TRACK A TARGET UP RIGHT  THE BROADSIDE AND POD FIRE', 'L', 3)
    y = 64
    for k, s in enumerate((a, b, d)): paste(img, s, 20 + k * (a.w * K + 20), y, K)
    y += a.h * K + 16
    text(img, 20, y, 'ZOOMED OUT 1 PX PER SOURCE PX: STANDARD AT REST  IN A FIGHT  SCRAP IN A FIGHT  NEON AT REST', 'H', 3)
    y += 24
    for k, s in enumerate((a, b, c, d)): paste(img, s, 20 + k * (a.w + 20), y, 1)
    return img

SHEETS.update(lines=sheet_lines, versions=sheet_versions, families=sheet_families, states=sheet_states, ship=sheet_ship)

def out_dir():
    return sys.argv[1] if len(sys.argv) > 1 and not sys.argv[1] in SHEETS else '/home/user/hs/shots'

if __name__ == '__main__':
    want = [a for a in sys.argv[1:] if a in SHEETS] or list(SHEETS)
    d = out_dir()
    for nm in want:
        p = os.path.join(d, 'gun-art_%s.png' % nm)
        SHEETS[nm]().save(p); print(p)
