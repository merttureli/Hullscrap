"""Drone sample sheets (the review gate of docs/DRONES.md section 8): builds the bay, the drones, the limpets, the boarder pod, the trail and the
boarding robot from drone_mod.py and writes ONLY preview sheets, 3x and labelled, to /home/user/hs/shots/drone-art_<sheet>.png.
Nothing here writes into art/components or art/crew. With --rigs <dir> it also writes the three robot rigs (the crew rig format) to that
scratch folder. Usage: python3 drone_samples.py [out_dir] [sheet ...] [--rigs dir]   (sheets: bay drones limpets robot fight)"""
import math, os, sys, json
from px import *
import gun_mod as gm
import drone_mod as dm
import gun_samples as gs
from gun_samples import space_bg, floor_bg, wall_rows, paste, sheet_stack, SPACE, turn_rgba, rot_rgba
from sheet_v2 import text
from compose import rotate
from mach import outline_all, glow
from gun_mod import FLANGE

K = 3
GREY = RGB['F'] + (255,)

# ------------------------------------------------------------------ small compositing helpers
def blit_glow(img, g, x, y):
    if g is not None: img.blit_rgba(g, x, y, 1, add=True)

def turned(spr, g, deg, pc, gpad):
    """turn an interior-only sprite about its pivot (pc, pc) on a canvas big enough for any angle, outline it after; the glow turns with it.
    -> (sprite, glow, centre) where centre is the pivot on the new canvas."""
    S = 2 * max(spr.w, spr.h) + 3; h = S // 2
    cv = Spr(S, S); cv.stamp(h - pc, h - pc, spr.rows())
    r = rotate(cv, deg, h, h) if deg % 360 else cv
    outline_all(r)
    G = None
    if g is not None:
        G = Rgba(S + 2 * gpad, S + 2 * gpad); G.blit_rgba(g, h - pc, h - pc)
        if deg % 360: G = turn_rgba(G, deg, h + gpad, h + gpad)
    return r, G, h

def put_drone(img, d, state, i, x, y, deg=0, glow_on=True):
    """draw drone (or limpet) d with its pivot at (x, y), facing deg (0 = up, clockwise)."""
    spr, g, _ = d.frame(state, i, raw=True) if isinstance(d, dm.Drone) else d.frame(state, i)
    if isinstance(d, dm.Drone):
        r, G, h = turned(spr, g, deg, dm.DC, dm.GP)
    else:
        r, G, h = spr, g, dm.DC
        if deg % 360:
            r, G, h = turned(strip_outline(spr), g, deg, dm.DC, dm.GP)
    img.blit_spr(r, x - h, y - h)
    if glow_on: blit_glow(img, G, x - h - dm.GP, y - h - dm.GP)

def strip_outline(spr):
    n = spr.copy(); n.g = [['.' if c == 'K' else c for c in row] for row in n.g]; return n

def put_trail(img, line, pts, glow_on=True, ages=None):
    """puffs of the line's trail at pts (oldest last: the later the point, the later the puff's frame, or `ages` gives each one's frame)."""
    fr = dm.trail_frames(line)
    for k, (x, y) in enumerate(pts):
        sp, g = fr[min(3, ages[k] if ages else k)]
        img.blit_spr(sp, int(x) - 2, int(y) - 2)
        if glow_on: blit_glow(img, g, int(x) - 6, int(y) - 6)

def stars(img, x0, y0, x1, y1, seed):
    """a sparse fixed starfield for small cells (gun_samples.space_bg's hash lines its stars up in a cell this small)."""
    import random
    r = random.Random(seed)
    for k in range(max(1, (x1 - x0) * (y1 - y0) // 220)):
        x, y = r.randrange(x0, x1), r.randrange(y0, y1); t = r.randrange(3)
        img.p[y][x] = [120 + t * 40, 130 + t * 40, 160 + t * 30, 255]

def cell_of(spr, g, pad, bg=SPACE, gpad=None, w=None, h=None, seed=0):
    """one sprite on its own small background (space by default) with its glow: a frame cell for the strips."""
    gpad = dm.GP if gpad is None else gpad
    W = w or spr.w + 2 * pad; H = h or spr.h + 2 * pad
    a = Rgba(W, H, bg + (255,))
    if bg == SPACE: stars(a, 0, 0, W, H, seed * 31 + spr.w * 7 + spr.h)
    ox, oy = (W - spr.w) // 2, (H - spr.h) // 2
    a.blit_spr(spr, ox, oy)
    blit_glow(a, g, ox - gpad, oy - gpad)
    return a

def label_under(a, lab):
    """a cell with room under it for a label (grid() writes `sub` labels at the bottom of the cell)."""
    b = Rgba(a.w, a.h + 9, GREY); paste(b, a, 0, 0); return (b, None, lab)

def one_x_strip(cells, gap=3, bg=GREY):
    """several 1x cells side by side on grey, as one image (they are shown at 1x on the sheet: the real size)."""
    W = sum(c.w for c in cells) + gap * (len(cells) - 1); H = max(c.h for c in cells)
    o = Rgba(W, H, bg); x = 0
    for c in cells: paste(o, c, x, (H - c.h) // 2); x += c.w + gap
    return o

def sheet_rows(title, rows, W=2400, subtitle=None):
    """rows of (label, [(Rgba at 3x-to-be, sublabel)], [1x Rgba images]) on one sheet: each row's 3x cells, then its 1x cells after a gap."""
    H = 70 + (24 if subtitle else 0)
    plan = []
    for (lab, big, small) in rows:
        bw = 20 + sum(b.w * K + 8 for b, _ in big) + 10 + sum(q.w + 6 for q in small)
        rh = max([b.h * K for b, _ in big] + [q.h for q in small] + [0]) + 40 + (max([q.h for q in small] + [0]) + 26 if bw > W else 0)
        plan.append((lab, big, small, rh)); H += rh + 12
    img = Rgba(W, H, GREY)
    text(img, 20, 20, title, 'H', 4)
    y = 64
    if subtitle: text(img, 20, y - 6, subtitle, 'L', 3); y += 24
    for (lab, big, small, rh) in plan:
        text(img, 20, y, lab, 'a', 3)
        x = 20; yy = y + 22
        for b, sl in big:
            paste(img, b, x, yy, K)
            if sl: text(img, x + 4, yy + b.h * K + 2, sl, 'L', 2)
            x += b.w * K + 8
        if small:
            x += 10
            if x + sum(q.w + 6 for q in small) > W: x = 20; yy += max(b.h * K for b, _ in big) + 18
            text(img, x, yy + max(q.h for q in small) + 12, '1X', 'M', 2)
            for q in small:
                paste(img, q, x, yy + 6, 1); x += q.w + 6
        y += rh + 12
    return img

# ------------------------------------------------------------------ the bay in context: the outside half in space, a 2-row wall, the inside half on the floor
def bay_scene(line, drone, istate='on', ii=0, ostate='on', oi=0, pad=16, top=36, fly=None, glow_on=True):
    """fly: (drone state, i, dy above the hatch's top, trail?) draws the launched drone over the hatch, nose up, with its trail under it."""
    b = dm.Bay(line, drone.fam)
    fo, go, _ = b.outside(ostate, oi)
    fi, gi, _ = b.inside(istate, ii, drone)
    W = dm.BW + 2 * pad
    oy_foot = 16
    H = top + oy_foot + 32 + fi.h - FLANGE + 12
    img = Rgba(W, H, GREY)
    wy = top + oy_foot
    space_bg(img, 0, 0, W, wy, len(line) * 31 + ii)
    floor_bg(img, 0, wy + 32, W, H)
    img.blit_spr(wall_rows(W), 0, wy)
    img.blit_spr(fo, pad, top)
    iy = wy + 32 - FLANGE
    img.blit_spr(fi, pad, iy)
    if glow_on: blit_glow(img, go, pad - dm.GP, top - dm.GP); blit_glow(img, gi, pad - dm.GP, iy - dm.GP)
    if fly:
        st, i, dy, tr = fly
        x, y = pad + dm.RX, top + 2 - dy
        if tr: put_trail(img, line, [(x - 6, y + 7), (x + 6, y + 8), (x - 6, y + 12), (x + 6, y + 14)][:tr], glow_on)
        put_drone(img, drone.variant(line=line), st, i, x, y, 0, glow_on)
    return img

def sheet_bay():
    D = {d.name: d for d in dm.COMBAT}
    kits = [('scrap', D['flak_drone_mk3']), ('standard', D['pulse_drone_mk1']), ('neon', D['ion_drone_mk2'])]
    short = lambda d: d.label.replace(' DRONE', '')
    lines = [(bay_scene(ln, d.variant(line=ln), pad=20), ln.upper(), short(d)) for ln, d in kits]
    d = D['laser_drone_mk2']
    seq = [(bay_scene('standard', d, 'on', 0, 'on', 0), 'READY', 'LOADED  HATCH SHUT'),
           (bay_scene('standard', d, 'launch', 0, 'open', 0), 'LAUNCH 0', 'CLAMPS OFF'),
           (bay_scene('standard', d, 'launch', 1, 'open', 1), 'LAUNCH 1', 'UP THE RAIL'),
           (bay_scene('standard', d, 'launch', 2, 'open', 2), 'LAUNCH 2', 'INTO THE WALL'),
           (bay_scene('standard', d, 'launch', 3, 'open', 2, fly=('idle', 0, 6, 2)), 'LAUNCH 3', 'OUT OF THE HATCH'),
           (bay_scene('standard', d, 'out', 0, 'open', 1, top=52, fly=('idle', 1, 30, 4)), 'OUT 0', 'HATCH CLOSING'),
           (bay_scene('standard', d, 'out', 1, 'on', 0), 'OUT 1', 'RE-ARMING')]
    b = dm.Bay('standard', d.fam)
    inside = []
    for st, i, lab in (('on', 0, 'ON 0'), ('on', 1, 'ON 1'), ('off', 0, 'OFF'), ('damaged', 0, 'DAMAGED 0'), ('damaged', 1, 'DAMAGED 1'), ('disabled', 0, 'DISABLED'),
                       ('launch', 0, 'LAUNCH 0'), ('launch', 1, 'LAUNCH 1'), ('launch', 2, 'LAUNCH 2'), ('launch', 3, 'LAUNCH 3'), ('out', 0, 'OUT 0'), ('out', 1, 'OUT 1')):
        f, g, _ = b.inside(st, i, d)
        inside.append(label_under(cell_of(f, g, 6, RGB['F']), lab))
    outside = []
    for st, i, lab in (('on', 0, 'ON 0'), ('on', 1, 'ON 1'), ('off', 0, 'OFF'), ('damaged', 0, 'DAMAGED 0'), ('damaged', 1, 'DAMAGED 1'), ('disabled', 0, 'DISABLED'),
                       ('open', 0, 'OPEN 0'), ('open', 1, 'OPEN 1'), ('open', 2, 'OPEN 2')):
        f, g, _ = b.outside(st, i)
        outside.append(label_under(cell_of(f, g, 6, RGB['F']), lab))
    fams = [(bay_scene('standard', D[n].variant(), pad=12), 'STANDARD', short(D[n])) for n in ('laser_drone_mk2', 'beam_drone_mk3')]
    return sheet_stack([
        ('DRONE BAY: INSIDE 3X3 AND HATCH 3X1 THROUGH A WALL, IN THE THREE LINES. THE CRADLE HOLDS THE LOADED KIT; THE STRIP IS IN ITS FAMILY', lines + fams),
        ('LAUNCH IN CONTEXT: THE CRADLE RUNS UP THE RAIL INTO THE WALL WHILE THE HATCH OPENS, THEN THE BAY RE-ARMS', seq),
        ('INSIDE HALF FRAMES  3X  WITH GLOW  (LASER DRONE MK II LOADED)', inside),
        ('OUTSIDE HALF FRAMES: THE HATCH. OUTSIDE HALVES ARE SCORCHED AND DENTED, NEVER SHATTERED', outside)])

# ------------------------------------------------------------------ the drones: every frame at 3x, the same at 1x
def drone_cells(d, states, pad=3):
    big, small = [], []
    for st, i, lab in states:
        f, g, _ = d.frame(st, i)
        big.append((cell_of(f, g, pad), lab))
        small.append(cell_of(f, g, 2))
    return big, small

DSTATES = [('idle', 0, 'IDLE 0'), ('idle', 1, 'IDLE 1'), ('fire', 0, 'FIRE 0'), ('fire', 1, 'FIRE 1'), ('hit', 0, 'HIT')]
LSTATES = [('flying', 0, 'FLY 0'), ('flying', 1, 'FLY 1'), ('stuck', 0, 'STUCK 0'), ('stuck', 1, 'STUCK 1'), ('stuck', 2, 'STUCK 2'), ('stuck', 3, 'STUCK 3'), ('husk', 0, 'HUSK')]
PSTATES = [('flying', 0, 'FLY 0'), ('flying', 1, 'FLY 1'), ('drilling', 0, 'DRILL 0'), ('drilling', 1, 'DRILL 1'), ('drilling', 2, 'DRILL 2'), ('husk', 0, 'HUSK')]
NOTE = {'pulse_drone_mk1': 'MK I: HULL + LENS  PODS  SHORT PULSE BARREL', 'laser_drone_mk2': 'MK II: + SWEPT FINS  POD LAMPS  TWIN RAILS',
        'ion_drone_mk2': 'MK II: + FINS  POD LAMPS  COIL BARREL', 'beam_drone_mk3': 'MK III: + ARMOUR COLLAR  BIG PODS  ENGINE  MAST  PRISM',
        'flak_drone_mk3': 'MK III: + COLLAR  BIG PODS  ENGINE  MAST  TRIPLE', 'defence_drone_mk1': 'PD DOME + RADAR SCOPE  HOOP WITH 3 EMITTERS  TWIN',
        'defence_drone_mk2': 'MK II: DOUBLED HOOP  4 EMITTERS  LONGER TWIN  2ND DISH'}

def module_cells():
    """each drone module on its own, as drone_mod draws it, for the key."""
    def one(fn, fam='laser'):
        c = gm.Ctx(dm.DN, dm.DN, gm.Look('standard', fam), dm.DSt('idle')); c.px = c.py = dm.DC; c.nozzles = []
        fn(c); spr = gm.finish(c, shadow=False)
        return cell_of(spr, gm.glow_layer(c, dm.GP), 2)
    M = [('HULL', lambda c: dm.hull(c, 1)), ('PODS I II', lambda c: dm.pods(c, 1)), ('PODS III', lambda c: dm.pods(c, 3)), ('FINS', lambda c: dm.fins(c, 2)),
         ('COLLAR', lambda c: dm.hull(c, 3)), ('ENGINE', lambda c: dm.engine(c, 3)), ('MAST', lambda c: dm.mast(c, 3)), ('LIGHT', lambda c: dm.running_light(c, 1)),
         ('STUB', dm.gun_stub), ('TWIN', dm.gun_twin), ('COIL', dm.gun_coil), ('PRISM', dm.gun_prism), ('TRIPLE', dm.gun_triple),
         ('PD DOME', lambda c: dm.pd_dome(c, 1)), ('HOOP', lambda c: dm.radar_ring(c, 1)), ('PD TWIN', lambda c: dm.pd_barrels(c, 1))]
    return [(one(fn, 'pd' if lab.startswith('PD') or lab == 'HOOP' else 'laser'), lab) for lab, fn in M]

def sheet_drones():
    rows = []
    for d in dm.COMBAT + dm.DEFENCE:
        big, small = drone_cells(d, DSTATES)
        rows.append((d.label + ': ' + NOTE[d.name].split(': ')[-1], big, small))
    for l in dm.LIMPETS:
        big, small = drone_cells(l, LSTATES)
        rows.append((l.label + ': SPIKES FOLDED IN FLIGHT  SPLAYED WHEN STUCK  CORE PULSES', big, small))
    for p, lab in ((dm.BOARDER, 'BOARDER POD 1X2: DRILL NOSE  CLAMP CLAWS  HATCH'), (dm.BOARDER.variant(fam='ion'), 'BOARDER POD OF THE SHOCK ROBOT: ION LIGHTS')):
        big, small = drone_cells(p, PSTATES)
        rows.append((lab, big, small))
    lines = []
    for d in (dm.COMBAT[0], dm.COMBAT[2], dm.COMBAT[4], dm.DEFENCE[0]):
        for ln in gm.LINES:
            f, g, _ = d.variant(line=ln).frame('idle', 0)
            lines.append((cell_of(f, g, 3), ln.upper()))
    small = [cell_of(*d.variant(line=ln).frame('idle', 0)[:2], 2) for d in (dm.COMBAT[0], dm.COMBAT[2], dm.COMBAT[4], dm.DEFENCE[0]) for ln in gm.LINES]
    rows.append(('LINES: SCRAP  STANDARD  NEON. SCRAP: A RUSTED SPARE POD  NEON: NAVY  CYAN EDGES', lines[:6], small[:6]))
    rows.append(('LINES: FLAK MK III AND DEFENCE MK I', lines[6:], small[6:]))
    trail = []
    for ln in gm.LINES:
        for k, (sp, g) in enumerate(dm.trail_frames(ln)):
            trail.append((cell_of(sp, g, 4, gpad=4), '%s %d' % (ln[:3].upper(), k)))
    rows.append(('THRUSTER TRAIL: 4 FRAMES 5X5 IN THE LINE COLOUR, ONE PUFF EVERY FEW PX BEHIND A NOZZLE', trail,
                 [cell_of(sp, g, 2, gpad=4) for ln in gm.LINES for sp, g in dm.trail_frames(ln)]))
    n = len(dm.COMBAT) + len(dm.DEFENCE)
    mods = module_cells()
    rows.insert(n, ('MODULES: A DRONE RECIPE IS A HULL  PODS  A GUN AND ADD-ONS (STANDARD  LASER COLOURS)', mods[:11], []))
    rows.insert(n + 1, ('', mods[11:], []))
    n += 2
    a = sheet_rows('DRONES: EVERY FRAME AT 3X WITH GLOW, THEN AT 1X', rows[:n], W=1190,
                   subtitle='NOSE UP: THE GUN TURNS WITH THE DRONE. TIERS GROW BY ADDING PARTS')
    b = sheet_rows('LIMPETS  THE BOARDER POD  LINES  THE TRAIL', rows[n:], W=1190, subtitle='LIMPETS 1 CELL  THE POD 1X2. FIRE ORANGE  POISON GREEN  HEAT RED')
    img = Rgba(2400, max(a.h, b.h), GREY)
    paste(img, a, 0, 0); paste(img, b, 1210, 0)
    for y in range(img.h): img.p[y][1200] = list(RGB['G']) + [255]
    return img

# ------------------------------------------------------------------ the limpets and the boarder in context: a hull wall, the room behind with its effect
ROOM_W, ROOM_H = 5, 3                                                         # the room behind, in cells

def wall_and_room(img, x0, wy, w):
    """one wall row (the hull) at wy, the room behind it below, a wall round the room's other sides."""
    s = Spr(w, 16)
    for cx in range(w // 16 + 1):
        x = cx * 16; s.rect(x, 0, 16, 16, 'D'); s.hline(x, 0, 16, 'E')
        for (rx, ry) in ((3, 3), (12, 3), (3, 12), (12, 12)): s.put(x + rx, ry, 'W')
    img.blit_spr(s, x0, wy)
    floor_bg(img, x0, wy + 16, x0 + w, wy + 16 + ROOM_H * 16)
    for y in range(wy + 16, wy + 16 + ROOM_H * 16):                          # the room's 1 px inner shadow under the wall
        if y == wy + 16:
            for x in range(x0, x0 + w): img.p[y][x] = list(RGB['W']) + [255]

def tint_room(img, x0, y0, w, h, rgb, a):
    for y in range(y0, y0 + h):
        for x in range(x0, x0 + w): img.over(x, y, rgb + (a,))

def overlay_fire(img, x0, y0, w, h, t):
    """the room burning: the fire fx (art/fx/fire) in a few cells, an orange wash, and its glow."""
    import fx
    fr = fx.fire_frames()
    tint_room(img, x0, y0, w, h, (255, 120, 30), 40)
    for k, (cx, cy) in enumerate(((0, 0), (1, 1), (4, 0), (2, 2), (5, 1))):
        img.blit_spr(fr[(t + k) % 4], x0 + cx * 16, y0 + cy * 16)
        g = Rgba(28, 28); glow(g, 14, 16, 12, (255, 130, 40), 0.35, 1.8); img.blit_rgba(g, x0 + cx * 16 - 6, y0 + cy * 16 - 6, 1, add=True)

def overlay_poison(img, x0, y0, w, h, t):
    """the room poisoned: a sick green wash and drifting gas specks (toxin bubbles)."""
    tint_room(img, x0, y0, w, h, (120, 210, 50), 44)
    pts = [(9, 9), (24, 24), (38, 11), (52, 33), (67, 17), (81, 38), (94, 24), (15, 40), (45, 43), (73, 7), (100, 41), (30, 33)]
    for k, (x, y) in enumerate(pts):                                          # gas bubbles: a lit cap, a green body, rising frame by frame
        yy = y0 + 2 + (y - 3 * t) % (h - 4)
        xx = x0 + x % (w - 2)
        img.over(xx, yy, RGB[']'] + (230,)); img.over(xx + 1, yy, RGB['g'] + (220,)); img.over(xx, yy + 1, RGB['g'] + (220,)); img.over(xx + 1, yy + 1, RGB['['] + (200,))
        if k % 3 == 0: img.over(xx + 3, yy - 3, RGB['g'] + (170,))

def overlay_heat(img, x0, y0, w, h, t):
    """the room hot: a red wash darker at the edges and the heat shimmer fx rising over its parts."""
    import fx
    tint_room(img, x0, y0, w, h, (255, 60, 30), 48)
    sh = fx.shimmer_frames()
    for k, cx in enumerate((0, 2, 4)):
        o = sh[(t + k) % 3]
        for yy in range(o.h):
            for xx in range(o.w):
                p = o.p[yy][xx]
                if p[3]: img.over(x0 + cx * 16 + xx, y0 + 12 + yy, tuple(p))
    g = Rgba(w, h); glow(g, w / 2.0, h / 2.0, w / 2.0, (255, 70, 30), 0.3, 1.4); img.blit_rgba(g, x0, y0, 1, add=True)

def a_part(img, x, y, line='standard'):
    """a part standing in the room (a small console), so the heat has something to heat."""
    s = Spr(16, 16); gm.plate(s, 1, 2, 14, 12); s.rect(4, 5, 8, 4, 'D'); s.hline(5, 6, 6, 'g'); s.put(3, 11, 'g'); outline_all(s)
    img.blit_spr(s, x, y)

def magnet_arc(img, x0, y0, x1, y1, bend, n=9, rgb=(140, 240, 196)):
    """the dotted course of a magnetic flight: a faint mint curve (the tractor/magnet colour), for the sheet only."""
    for k in range(1, n):
        t = k / float(n)
        x = x0 + (x1 - x0) * t + bend * math.sin(math.pi * t)
        y = y0 + (y1 - y0) * t
        img.over(int(x), int(y), rgb + (150,)); img.over(int(x) + 1, int(y), rgb + (70,))

def limpet_scene(lim, mode, t=0):
    """mode: flying (it curves in over the wall), stuck (on the wall's face, the room behind under its effect), husk (falling off)."""
    W = ROOM_W * 16 + 24; top = 46
    H = top + 16 + ROOM_H * 16 + 10
    img = Rgba(W, H, GREY)
    space_bg(img, 0, 0, W, top, len(lim.name) + t)
    wall_and_room(img, 0, top, W)
    rx0, ry0 = 12, top + 16
    a_part(img, rx0 + 3 * 16, ry0 + 16)
    cx = W // 2
    if mode == 'stuck':
        {'fire': overlay_fire, 'poison': overlay_poison, 'heat': overlay_heat}[lim.fam](img, 0, ry0 + 1, W, ROOM_H * 16 - 1, t)
        put_drone(img, lim, 'stuck', t, cx, top + 1)
    elif mode == 'flying':
        magnet_arc(img, cx - 34, 2, cx, top - 6, -22)
        put_drone(img, lim, 'flying', t, cx - 5, top - 17, 0)
    else:
        put_drone(img, lim, 'husk', 0, cx + 8, top - 9, 25)
        tint_room(img, 0, ry0 + 1, W, ROOM_H * 16 - 1, (255, 255, 255), 0)
    return img

def pod_scene(mode, t=0, line='standard'):
    """the boarder pod: flying in, drilling into the wall (the nose in it), then the empty husk stuck in a breach and the robot in the room."""
    p = dm.BOARDER.variant(line=line)
    W = ROOM_W * 16 + 24; top = 60
    H = top + 16 + ROOM_H * 16 + 10
    img = Rgba(W, H, GREY)
    space_bg(img, 0, 0, W, top, 77 + t)
    wall_and_room(img, 0, top, W)
    cx = W // 2
    if mode == 'flying':
        spr, g, an = p.frame('flying', t)
        x, y = cx - dm.PCX, top - 48
        put_trail(img, line, [(cx - 3, y + 4), (cx + 3, y + 1), (cx, y - 4), (cx - 1, y - 10)])
        img.blit_spr(rot_spr180(spr), x, y); blit_glow(img, rot_rgba(g, 2), x - dm.GP, y - dm.GP)
        return img
    spr, g, an = p.frame('drilling' if mode == 'drilling' else 'husk', t)
    s2, g2 = rot_spr180(spr), rot_rgba(g, 2)                                  # the pod flies DOWN onto this wall: turned 180
    sink = {0: 2, 1: 6, 2: 9}[t] if mode == 'drilling' else 9                 # how deep the nose is in the wall
    x, y = cx - dm.PCX, top - s2.h + 3 + sink
    if mode == 'husk':                                                        # the breach it cut, under the stuck husk, and the robot inside
        import tiles
        bfr = tiles.breach_frames()[0]
        img.blit_spr(bfr, cx - 8, top)
        from sp_compose import SKit, render
        from sheet_species import draw_fig
        f, gl = render(SKit(dm.ROBOTS[0]), 6, 200, 200, 'unarmed', None, 'lens', tint=ROBOT_TINT)
        draw_fig(img, f, gl, cx - 30, top + 16 + 2, 1, crop=33)
    for yy in range(s2.h):                                                    # the nose inside the wall is hidden by it (drawn over the wall up to its face)
        for xx in range(s2.w):
            ch = s2.g[yy][xx]
            if ch == '.': continue
            Y = y + yy
            if Y >= top: continue
            img.over(x + xx, Y, RGB[ch] + (255,))
    blit_glow(img, g2, x - dm.GP, y - dm.GP)
    if mode == 'drilling':                                                    # sparks and grit thrown off the wall's face
        import fx
        sf = fx.sparks_frames()[t % 3]
        for sx in ((cx - 15,) if t % 2 else (cx + 1,)):                       # thrown off to one side of the drill, then the other
            for yy in range(sf.h):
                for xx in range(sf.w):
                    ch = sf.g[yy][xx]
                    if ch != '.' and top - 9 + yy < top + 2: img.over(sx + xx, top - 9 + yy, RGB[ch] + (255,))
        gg = Rgba(30, 20); glow(gg, 15, 10, 9, (255, 220, 120), 0.45, 1.6); img.blit_rgba(gg, cx - 15, top - 10, 1, add=True)
    return img

def rot_spr180(spr):
    n = Spr(spr.w, spr.h)
    for y in range(spr.h):
        for x in range(spr.w): n.g[spr.h - 1 - y][spr.w - 1 - x] = spr.g[y][x]
    return n

ROBOT_TINT = (200, 70, 60)

def sheet_limpets():
    blocks = []
    for lim in dm.LIMPETS:
        what = {'fire': 'FIRE BEHIND', 'poison': 'GAS BEHIND', 'heat': 'PARTS HEAT UP'}[lim.fam]
        cells = [(limpet_scene(lim, 'flying', 0), 'FLYING', 'MAGNET PULL')]
        cells += [(limpet_scene(lim, 'stuck', t), 'STUCK %d' % t, what if t == 0 else None) for t in range(4)]
        cells += [(limpet_scene(lim, 'husk'), 'HUSK', 'FALLS OFF')]
        blocks.append(('%s: FLYING  STUCK ON THE HULL WITH THE ROOM BEHIND UNDER ITS EFFECT (4 FRAMES)  THEN THE HUSK' % lim.label, cells))
    pod = [(pod_scene('flying', 0), 'FLYING', 'MAGNET PULL')]
    pod += [(pod_scene('drilling', t), 'DRILLING %d' % t, 'CLAWS GRIP' if t == 0 else None) for t in range(3)]
    pod += [(pod_scene('husk'), 'EMPTY HUSK', 'ROBOT INSIDE')]
    blocks.append(('THE BOARDER POD DRILLING IN: IT CUTS A SMALL BREACH AND DROPS A ROBOT INTO THE ROOM BEHIND (ALL AT ONE SCALE)', pod))
    return sheet_stack(blocks)

# ------------------------------------------------------------------ the boarding robot
def sheet_robot():
    from sp_compose import SKit, render
    from sheet_species import draw_fig
    crop = 40; cw = crop * K + 6
    rows_ = []
    for rb in dm.ROBOTS:
        kit = SKit(rb)
        fr = [(6, 0, 0, 'unarmed', 'STAND'), (6, 90, 90, 'unarmed', '90'), (6, 180, 180, 'unarmed', '180'), (6, 270, 270, 'unarmed', '270'), (6, 0, 0, 'melee', 'STRIKE'),
              (6, 0, 0, 'melee_2', 'STRIKE 2')] + [(k, 0, 0, 'unarmed', 'WALK %d' % k) for k in range(6)] + [(2, 45, 315, 'melee', 'AIM ACROSS')]
        rows_.append((rb, kit, fr))
    H = 70 + len(rows_) * (cw + 40 + crop + 30) + 300
    img = Rgba(2400, H, GREY)
    text(img, 20, 20, 'BOARDING ROBOT: A CREW RIG (33X33 PIVOT 16  TOP-DOWN  LAYERED) BUILT ON THE REPAIR DRONE: ROUND BODY  ONE LENS  ITS TWO PODS NOW TREADS', 'H', 3)
    text(img, 20, 42, 'THE EYE IN THE FAMILY COLOUR  THE SHOULDER PLATES TAKE THE OWNER COLOUR (TINT MASK  RED HERE)  TREADS RUN WITH THE WALK FRAMES', 'L', 3)
    y = 70
    labels = {1: 'MK I  DRILL ROBOT  AMBER  A DRILL ARM AND THE REPAIR DRONE CLAW', 2: 'MK II  SHOCK ROBOT  ION  TWO PRONG ARMS  BLUE ARCS ON THE STRIKE',
              3: 'MK III  THE DRILL ROBOT UNDER HEAVIER PLATING  ARMOUR SKIRTS  FLANK PLATES  BIGGER DRILL'}
    for rb, kit, fr in rows_:
        text(img, 20, y, labels[rb.mk], 'a', 3)
        x = 20
        for (lf, ld, ad, pose, lab) in fr:
            f, g = render(kit, lf, ld, ad, pose, None, 'lens', tint=ROBOT_TINT)
            text(img, x + 4, y + 22, lab, 'M', 2)
            draw_fig(img, f, g, x, y + 32, K, crop=crop)
            draw_fig(img, f, g, x + crop + 2, y + 32 + cw + 6, 1, crop=crop)
            x += cw
        y += cw + 40 + crop + 30
    # the corridor: a robot meets a crew member, at 3x, then the same at the game scale 2x
    text(img, 20, y, 'IN A CORRIDOR WITH A HUMAN FOR SCALE: 3X  THEN THE GAME SCALE 2X', 'H', 3)
    cor = corridor()
    paste(img, cor, 20, y + 26, 3)
    paste(img, cor, 20 + cor.w * 3 + 30, y + 26, 2)
    lx = 20 + cor.w * 5 + 70
    text(img, lx, y, 'THE LAYERS OF MK I  3X  (LEGS TURN TO THE MOVE  THE REST TO THE AIM)', 'H', 3)
    import crew_v2 as cv2
    rb = dm.ROBOTS[0]; x = lx
    lay = [(rb.legs()[0], None, 'LEGS 0'), (rb.legs()[3], None, 'LEGS 3'), (rb.torso(), rb.torso_glow()[0], 'TORSO'),
           (rb.arms('unarmed'), None, 'ARMS REST'), (rb.arms('melee'), None, 'MELEE'), (rb.arms('melee_2'), None, 'MELEE 2'), (rb.head('lens'), rb.head_glow()[0], 'HEAD')]
    for spr, g, lab in lay:
        a = Rgba(rb.N, rb.N, GREY); a.blit_rgba(cv2.tinted_rgba(spr, ROBOT_TINT), 0, 0)
        if g is not None: a.blit_rgba(g, 0, 0, 1, add=True)
        paste(img, a, x, y + 26, 3); text(img, x + 4, y + 26 + rb.N * 3 + 4, lab, 'M', 2)
        x += rb.N * 3 + 8
        if x > 2300: x = lx; y += rb.N * 3 + 24
    y += rb.N * 3 + 64
    text(img, lx, y, 'OWNER TINT: OURS (CREW TEAL)  THEIRS (RED)  MK I  II  III', 'H', 3)
    from sp_compose import SKit, render
    from sheet_species import draw_fig
    x = lx
    for rb_ in dm.ROBOTS:
        for tint in ((79, 196, 184), ROBOT_TINT):
            f, g = render(SKit(rb_), 6, 0, 0, 'unarmed', None, 'lens', tint=tint)
            draw_fig(img, f, g, x, y + 24, K, crop=36); x += 36 * K + 6
    return img

def corridor():
    """a 2-cell-wide corridor 12 cells long: walls, floor, a door; the human aims at the drill robot, the shock robot behind it."""
    from sp_compose import SKit, render
    from sheet_species import draw_fig
    from sheet_races1 import ALL as SPECIES, TINTS
    W, H = 12 * 16, 5 * 16
    img = Rgba(W, H, GREY)
    floor_bg(img, 0, 16, W, H - 16)
    for yy in (0, H - 16):
        s = Spr(W, 16)
        for cx in range(W // 16):
            s.rect(cx * 16, 0, 16, 16, 'D'); s.hline(cx * 16, 0, 16, 'E')
            for (rx, ry) in ((3, 3), (12, 3), (3, 12), (12, 12)): s.put(cx * 16 + rx, ry, 'W')
        img.blit_spr(s, 0, yy)
    for x in range(W): img.p[16][x] = list(RGB['W']) + [255]
    hk = SKit(dict(SPECIES)['human'](), __import__('sp_items').kit_items())
    f, g = render(hk, 6, 90, 90, 'rifle', 'carbine', 'helmet', tint=TINTS['human'])
    draw_fig(img, f, g, 2 * 16 - 33 + 16, 16 + 16 - 33 + 16, 1, crop=66)
    r1 = SKit(dm.ROBOTS[0]); f, g = render(r1, 2, 270, 270, 'melee_2', None, 'lens', tint=ROBOT_TINT)
    draw_fig(img, f, g, 6 * 16 - 33 + 16, 16 + 16 - 33 + 16, 1, crop=66)
    r2 = SKit(dm.ROBOTS[1]); f, g = render(r2, 4, 270, 270, 'melee', None, 'lens', tint=ROBOT_TINT)
    draw_fig(img, f, g, 9 * 16 - 33 + 16, 16 + 16 - 33 + 16, 1, crop=66)
    return img

# ------------------------------------------------------------------ the fight: our small carrier and an enemy hull at the game's 2 px per source px
OURS = [
 '   ####   ',
 '   #..#   ',
 '##########',
 '#........#',
 '#........#',
 '#........#',
 '#........#',
 '#........#',
 '#........#',
 '#........#',
 '#........#',
 '#........#',
 '#........#',
 '##########',
]
THEIRS = [
 '  #####  ',
 '  #...#  ',
 '#########',
 '#.......#',
 '#.......#',
 '#.......#',
 '#.......#',
 '#.......#',
 '#.......#',
 '#########',
]

def draw_hull(img, rows, MX, MY):
    s = Spr(img.w, img.h)
    for r, row in enumerate(rows):
        for c, ch in enumerate(row):
            x, y = (MX + c) * 16, (MY + r) * 16
            if ch == '#':
                s.rect(x, y, 16, 16, 'D'); s.hline(x, y, 16, 'E')
                for (rx, ry) in ((3, 3), (12, 3), (3, 12), (12, 12)): s.put(x + rx, y + ry, 'W')
            elif ch == '.':
                s.rect(x, y, 16, 16, 'F'); s.hline(x, y, 16, 'G'); s.vline(x, y, 16, 'G')
    img.blit_spr(s, 0, 0)

def bay_local(bay, drone, istate='out', ii=0, ostate='open', oi=2):
    """the bay at rotation 0 on its own canvas as gun_samples.mount_local lays a gun out: outside half, a 1-cell wall gap, the inside half."""
    fo, go, _ = bay.outside(ostate, oi); fi, gi, _ = bay.inside(istate, ii, drone)
    wc, hc = 3, 1 + 1 + 3; m = 8
    L = Rgba(wc * 16 + 2 * m, hc * 16 + 2 * m); G = Rgba(L.w, L.h)
    L.blit_spr(fo, m, m); L.blit_spr(fi, m, m + 2 * 16 - FLANGE)
    G.blit_rgba(go, m - dm.GP, m - dm.GP); G.blit_rgba(gi, m - dm.GP, m + 2 * 16 - FLANGE - dm.GP)
    return L, G, m, (wc, hc), 1, 3

def gun_local(g, **kw):
    L, G, m, (wc, hc) = gs.mount_local(g, **kw)
    return L, G, m, (wc, hc), g.out_cells[1], g.in_cells[1]

def place(img, glows, local, k, wall, MX, MY):
    """put a mount laid out at rotation 0 on the hull: k quarter turns (0 out = up, 1 right, 2 down, 3 left), wall = the wall cell where it starts."""
    L, G, m, (wc, hc), oh, ih = local
    wc_, wr_ = wall
    if k == 0: gx, gy = wc_, wr_ - oh
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

def shot_line(img, x0, y0, x1, y1, rgb, core=(255, 255, 255), w=1):
    """a beam/laser shot: a bright 1 px core with the family colour round it, and a soft glow."""
    n = int(max(abs(x1 - x0), abs(y1 - y0)))
    for k in range(n + 1):
        x = x0 + (x1 - x0) * k / n; y = y0 + (y1 - y0) * k / n
        img.over(int(x), int(y), core + (240,))
        for dx, dy in ((1, 0), (0, 1), (-1, 0), (0, -1)): img.over(int(x) + dx, int(y) + dy, rgb + (150,))
        if k % 2 == 0: g = Rgba(7, 7); glow(g, 3.5, 3.5, 3.5, rgb, 0.25, 1.6); img.blit_rgba(g, int(x) - 3, int(y) - 3, 1, add=True)

def flash(img, x, y, rgb, r=6, a=0.8):
    g = Rgba(2 * r + 2, 2 * r + 2); glow(g, r + 1, r + 1, r, rgb, a, 1.6); img.blit_rgba(g, int(x) - r - 1, int(y) - r - 1, 1, add=True)
    img.over(int(x), int(y), (255, 255, 255, 255))
    for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)): img.over(int(x) + dx, int(y) + dy, rgb + (220,))

def orbit_pos(c, rx, ry, a):
    return (c[0] + rx * math.sin(math.radians(a)), c[1] - ry * math.cos(math.radians(a)))

def draw_fight(glow_on=True):
    W, H = 52 * 16, 24 * 16
    img = Rgba(W, H, SPACE + (255,)); space_bg(img, 0, 0, W, H, 11)
    OX, OY = 6, 4; EX, EY = 36, 6
    draw_hull(img, OURS, OX, OY); draw_hull(img, THEIRS, EX, EY)
    glows = []
    D = {d.name: d for d in dm.COMBAT}
    ld, pd_, dd = D['laser_drone_mk2'], D['pulse_drone_mk1'], dm.DEFENCE[0]
    place(img, glows, bay_local(dm.Bay('standard', 'laser'), ld), 1, (9, 3), OX, OY)               # two bays on the flank toward the enemy
    place(img, glows, bay_local(dm.Bay('standard', 'pulse'), pd_), 1, (9, 8), OX, OY)
    place(img, glows, bay_local(dm.Bay('standard', 'pd'), dd), 2, (2, 13), OX, OY)                 # and one aft for the defence drone
    place(img, glows, gun_local(gs.LASER_LIGHT, deg=60), 3, (0, 4), OX, OY)
    place(img, glows, gun_local(gs.LASER_MK1), 3, (0, 4), EX, EY)                                  # the enemy: a casemate facing us, a PD on its shoulder
    place(img, glows, gun_local(gs.PD_MK1, deg=-60), 0, (6, 2), EX, EY)
    for (Gr, X, Y) in glows: blit_glow(img, Gr, X, Y)
    oc = ((OX + 5) * 16, (OY + 7.5) * 16); ec = ((EX + 4.5) * 16, (EY + 5) * 16)
    # the defence drone round our hull, shooting down a fire limpet the enemy threw wide (it curves in toward our stern)
    da = 124; dx, dy = orbit_pos(oc, 122, 146, da)
    lx, ly = oc[0] + 142, oc[1] + 126
    magnet_arc(img, ec[0] - 150, ec[1] + 60, lx + 6, ly - 2, 34, 16, (255, 150, 60))
    put_drone(img, dm.LIMPETS[0], 'flying', 0, int(lx), int(ly))
    ang = math.degrees(math.atan2(lx - dx, -(ly - dy)))
    for side in (-1, 1):
        put_trail(img, 'standard', [orbit_pos(oc, 122 + side * 4, 146 + side * 4, da - 4 - 2 * k) for k in range(8)], ages=[0, 0, 1, 1, 2, 2, 3, 3])
    put_drone(img, dd, 'fire', 0, int(dx), int(dy), ang)
    shot_line(img, dx + 9 * math.sin(math.radians(ang)), dy - 9 * math.cos(math.radians(ang)), lx - 4, ly - 2, (110, 220, 90), (220, 255, 210))
    flash(img, lx - 4, ly - 2, (110, 220, 90), 5)
    # two combat drones round the enemy hull: they face it and strafe round; the laser drone fires, the pulse drone's bolt is in flight
    for (d, a, st, i) in ((ld, 232, 'fire', 0), (pd_, 330, 'idle', 0)):
        x, y = orbit_pos(ec, 118, 128, a)
        tx, ty = (EX * 16 + 40, (EY + 9) * 16 + 4) if d is ld else ec           # it faces what it shoots: the gun is part of the drone
        ang = math.degrees(math.atan2(tx - x, -(ty - y)))
        for side in (-1, 1):                                                  # a stream behind each pod
            pts = [orbit_pos(ec, 118 + side * 6, 128 + side * 6, a - 4 - 2 * k) for k in range(8)]
            put_trail(img, 'standard', pts, ages=[0, 0, 1, 1, 2, 2, 3, 3])
        put_drone(img, d, st, i, int(x), int(y), ang)
        mx, my = x + 12 * math.sin(math.radians(ang)), y - 12 * math.cos(math.radians(ang))
        if d is ld:
            hx, hy = tx, ty
            shot_line(img, mx, my, hx, hy, (240, 62, 40), (255, 200, 160)); flash(img, hx, hy, (255, 120, 60), 8)
        else:
            bx, by = mx + (ec[0] - x) * 0.35, my + (ec[1] - y) * 0.35
            g = Rgba(16, 16); glow(g, 8, 8, 7, (255, 124, 16), 0.8, 1.6); img.blit_rgba(g, int(bx) - 8, int(by) - 8, 1, add=True)
            for (ox, oy, c) in ((0, 0, (255, 255, 255)), (1, 0, (255, 226, 140)), (0, 1, (255, 226, 140)), (-1, 0, (255, 160, 40)), (0, -1, (255, 160, 40))):
                img.over(int(bx) + ox, int(by) + oy, c + (255,))
    draw_fight.spots = [(int(dx + lx) // 2, int(dy + ly) // 2)] + [tuple(int(v) for v in orbit_pos(ec, 118, 128, a_)) for a_ in (232, 330)]
    return img

def sheet_fight():
    a = draw_fight()
    W = 2400; k = 2
    H = 64 + a.h * k + 16 + 24 + max(a.h, 64 * 4) + 20
    img = Rgba(W, H, GREY)
    text(img, 20, 20, 'IN A FIGHT AT THE GAME SCALE 2 PX PER SOURCE PX: OUR SMALL CARRIER (LEFT) WITH THREE BAYS  ONE DRONE OUT PER BAY  AGAINST AN ENEMY HULL', 'H', 3)
    text(img, 20, 42, 'LASER MK II FIRING AND PULSE MK I STRAFE ROUND THE ENEMY FACING IT  THE DEFENCE DRONE SHOOTS DOWN A FIRE LIMPET CURVING IN ON OUR STERN', 'L', 3)
    paste(img, a, 20, 64, k)
    y = 64 + a.h * k + 16
    text(img, 20, y, 'THE SAME AT 1 PX PER SOURCE PX (ZOOMED OUT)', 'H', 3)
    paste(img, a, 20, y + 24, 1)
    x = 20 + a.w + 40
    text(img, x, y, 'DETAIL AT 4X: THE DEFENCE DRONE ON THE LIMPET  LASER MK II FIRING  PULSE MK I', 'H', 3)
    for (cx, cy), cw in zip(draw_fight.spots, (86, 64, 64)):
        ch = 64
        crop = Rgba(cw, ch)
        for yy in range(ch):
            for xx in range(cw):
                X, Y = cx - cw // 2 + xx, cy - ch // 2 + yy
                if 0 <= X < a.w and 0 <= Y < a.h: crop.p[yy][xx] = list(a.p[Y][X])
        paste(img, crop, x, y + 24, 4); x += cw * 4 + 16
    return img

# ------------------------------------------------------------------ the robot rigs into a scratch folder (the crew rig format of art/README.md), for the samples only
def export_rigs(d):
    import sp_export
    import crew_v2 as cv2
    from sp_common import glow_strip
    for rb in dm.ROBOTS:
        out = os.path.join(d, rb.id); os.makedirs(out, exist_ok=True)
        cv2.OUTLINE = True
        sp_export.pair(out, 'legs', rb.legs(), rb.N)
        sp_export.pair(out, 'torso', [rb.torso()], rb.N)
        sp_export.pair(out, 'arms', [rb.arms(p) for p in rb.POSES], rb.N)
        sp_export.pair(out, 'head', [rb.head(h) for h in rb.head_names], rb.N)
        glow_strip(rb.head_glow()).save(out + '/head_glow.png'); glow_strip(rb.torso_glow()).save(out + '/torso_glow.png')
        ag = [rb.arms_glow(p) or [Rgba(rb.N, rb.N)] for p in rb.POSES]
        glow_strip([g[0] for g in ag]).save(out + '/arms_glow.png')
        J = {'species': rb.id, 'frame': [rb.N, rb.N], 'pivot': [rb.C, rb.C],
             'notes': rb.notes + ' A crew rig (normal kind) for a hostile unit: every layer faces UP at rotation 0; the legs are treads; arms poses unarmed / melee / '
                      'melee_2 (the strike, two frames: play them alternately while it attacks); no item is held. The shoulder plates are the tint mask (the owner colour).',
             'draw_order': ['legs', 'torso', 'arms', 'head'],
             'rotate': {'legs': 'move direction', 'torso': 'aim', 'arms': 'aim', 'head': 'aim'},
             'layers': {'legs': {'image': 'legs.png', 'color_mask': 'legs_color.png', 'anims': {'walk': [0, 6, 8], 'stand': [6, 1, 0]}, 'notes': 'tread links run back one px a frame'},
                        'torso': {'image': 'torso.png', 'color_mask': 'torso_color.png', 'anchors': rb.torso_anchors(), 'glow': {'image': 'torso_glow.png', 'frame': [rb.N, rb.N], 'frames': 1}},
                        'arms': {'image': 'arms.png', 'color_mask': 'arms_color.png', 'frames': {p: i for i, p in enumerate(rb.POSES)},
                                 'glow': {'image': 'arms_glow.png', 'frame': [rb.N, rb.N], 'frames': len(rb.POSES)},
                                 'anchors': {p: {k: (list(v) if v else None) for k, v in a.items()} for p, a in rb.arm_anchors().items()}},
                        'head': {'image': 'head.png', 'color_mask': 'head_color.png', 'frames': {'lens': 0},
                                 'glow': {'image': 'head_glow.png', 'frame': [rb.N, rb.N], 'frames': 2, 'notes': 'alternate at 2 fps: the lens pulses'}}}}
        with open(out + '/crew.json', 'w') as f: json.dump(J, f, indent=1); f.write('\n')
        print(out)

SHEETS = {'bay': sheet_bay, 'drones': sheet_drones, 'limpets': sheet_limpets, 'robot': sheet_robot, 'fight': sheet_fight}

if __name__ == '__main__':
    args = sys.argv[1:]
    rigs = None
    if '--rigs' in args:
        i = args.index('--rigs'); rigs = args[i + 1]; del args[i:i + 2]
    want = [a for a in args if a in SHEETS] or list(SHEETS)
    outd = next((a for a in args if a not in SHEETS), '/home/user/hs/shots')
    if rigs: export_rigs(rigs)
    for nm in want:
        p = os.path.join(outd, 'drone-art_%s.png' % nm)
        SHEETS[nm]().save(p); print(p)
