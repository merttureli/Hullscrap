"""Weapon sprite framework (wave 2). A weapon is TWO layers (lead's rule: rot 0 = ship forward is UP, the head tracks the aim):
  <id>.png         the MOUNT: housing, power coupling, turret ring, charge strip; anims on/off/charge 0-5/damaged/disabled (+ _glow)
  <id>_barrel.png  the BARREL / head drawn pointing UP; anims idle/fire (recoil + flash)/damaged/disabled (+ _barrel_glow)
Barrels are painted pointing EAST on a scratch canvas and turned a quarter turn counter-clockwise (lossless), so the
tip is at the top of the frame. Damage is drawn by each weapon (`hurt` = what cracks / hangs loose / sparks,
`wreck` = what is visibly broken), never by a shared stamp."""
from comp_base import *
from comp_base import DARK

# ------------------------------------------------------------------ small drawing helpers
RAMP = 'LMMSSSSWWE'
def ramp_rows(h, ramp=RAMP):
    """tone per row for a horizontal cylinder h rows high (highlight on top, shade underneath)."""
    if h <= len(ramp):
        idx = [round(k * (len(ramp) - 1) / max(1, h - 1)) for k in range(h)]
        return [ramp[k] for k in idx]
    return [ramp[min(len(ramp) - 1, k * len(ramp) // h)] for k in range(h)]

def cylh(s, x, y, w, h, ramp=RAMP):
    for k, c in enumerate(ramp_rows(h, ramp)): s.hline(x, y + k, w, c)

def cylv(s, x, y, w, h, ramp=RAMP):
    for k, c in enumerate(ramp_rows(w, ramp)): s.vline(x + k, y, h, c)

def band(s, x, y, h, w=2, hi='L', lo='W'):
    """clamp ring across a horizontal barrel."""
    s.vline(x, y, h, hi)
    for k in range(1, w): s.vline(x + k, y, h, lo)

def hazard(s, x, y, w, h):
    """hazard tape: diagonal amber/black."""
    for j in range(h):
        for i in range(w): s.put(x + i, y + j, 'a' if ((i + j) // 2) % 2 == 0 else 'D')

def lamp(s, x, y, c, on):
    s.rect(x, y, 2, 2, c if on else 'E')
    if on: s.put(x, y, 'H')

def bolts(s, pts, c='L'):
    for (x, y) in pts: s.put(x, y, c)

def weld(s, x, y, n, vert=False):
    """a weld seam: a bead of rust/steel dashes."""
    for k in range(n):
        xx, yy = (x, y + k) if vert else (x + k, y)
        s.put(xx, yy, 'S' if k % 2 else 'W')

def crack(s, pts, c='K', chip='M'):
    """a hand-placed crack: polyline through pts, drawn only where the sprite has pixels; chipped lit edge beside it."""
    for (x0, y0), (x1, y1) in zip(pts, pts[1:]):
        n = max(abs(x1 - x0), abs(y1 - y0), 1)
        for t in range(n + 1):
            x = x0 + round((x1 - x0) * t / n); y = y0 + round((y1 - y0) * t / n)
            if s.get(x, y) != '.':
                s.g[y][x] = c
                if chip and t % 3 == 1 and s.get(x - 1, y) not in ('.', c): s.g[y][x - 1] = chip

def spark(s, x, y, big=True):
    """a bright electrical spark, painted over anything."""
    s.put(x, y, 'H')
    for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)): s.put(x + dx, y + dy, 'y')
    if big:
        for dx, dy in ((2, 0), (-2, 0), (0, 2), (0, -2)): s.put(x + dx, y + dy, 'o')
        for dx, dy in ((1, 1), (-1, -1)): s.put(x + dx, y + dy, 'o')

def wire(s, pts, c='u', c2='n'):
    """a loose cable: polyline, rust-copper with a dark underside."""
    for (x0, y0), (x1, y1) in zip(pts, pts[1:]):
        n = max(abs(x1 - x0), abs(y1 - y0), 1)
        for t in range(n + 1):
            x = x0 + round((x1 - x0) * t / n); y = y0 + round((y1 - y0) * t / n)
            s.put(x, y, c)
    return s

def cleave(s, seam, dx, dy, gap='K', edge='M', rows=None):
    """split a casing: everything at/after seam(y) shifts by (dx, dy); the opening shows as a dark gap with a lit cut edge.
    rows=(y0, y1) limits the split to those rows (the outside half of a mount)."""
    n = Spr(s.w, s.h)
    xs = {}
    r0, r1 = rows or (0, s.h)
    for y in range(s.h):
        sx = (seam(y) if callable(seam) else seam[y]) if r0 <= y < r1 else s.w + 9
        xs[y] = sx
        for x in range(s.w):
            c = s.g[y][x]
            if c == '.': continue
            if x >= sx: n.put(x + dx, y + dy, c)
            else: n.put(x, y, c)
    for y in range(s.h):
        sx = xs[y]
        if s.get(sx - 1, y) != '.' and s.get(sx, y) != '.':
            for k in range(dx):
                n.g[y][sx + k] = gap if (k in (0, dx - 1) or dx < 3) else 'E'
            if edge and 0 <= sx + dx < s.w and n.g[y][sx + dx] != '.' and y % 2 == 0: n.g[y][sx + dx] = edge
    return n

def move(s, x0, y0, w, h, dx, dy):
    """pick up the pixels in a rectangle and put them down shifted by (dx, dy): a part that sags, hangs or snaps off."""
    blk = [[s.get(x0 + i, y0 + j) for i in range(w)] for j in range(h)]
    for j in range(h):
        for i in range(w):
            if blk[j][i] != '.': s.g[y0 + j][x0 + i] = '.'
    for j in range(h):
        for i in range(w):
            if blk[j][i] != '.': s.put(x0 + i + dx, y0 + j + dy, blk[j][i])

def lens(s, x, y, w, h, on, big=False):
    """emitter lens: red-orange-yellow core when lit, dead slate otherwise."""
    if on:
        s.rect(x, y, w, h, 'r'); s.rect(x + 1, y, w - 1, h, 'o')
        s.rect(x + w - 1, y, 1, h, 'y')
        if h > 2: s.rect(x + w - 1, y + 1, 1, h - 2, 'H')
        else: s.put(x + w - 1, y, 'H')
    else:
        s.rect(x, y, w, h, 'E'); s.put(x, y, 'W')

def ccw(s):
    """quarter turn counter-clockwise (east-pointing -> up-pointing), lossless."""
    n = Spr(s.h, s.w)
    for y in range(s.h):
        for x in range(s.w): n.g[s.w - 1 - x][y] = s.g[y][x]
    return n

def ccw_rgba(o):
    n = Rgba(o.h, o.w)
    for y in range(o.h):
        for x in range(o.w): n.p[o.w - 1 - x][y] = list(o.p[y][x])
    return n

class St:
    """what one INSIDE-half frame shows."""
    def __init__(s, state, i):
        s.state, s.i = state, i
        s.fire = state == 'fire'
        s.flash = s.fire and i == 0                                      # the discharge flash on the strip
        s.dmg = {'damaged': 1, 'disabled': 2}.get(state, 0)
        s.powered = state not in ('off', 'disabled')
        s.charge = state == 'charge'
        s.lit = {'charge': i, 'on': 5, 'damaged': 5}.get(state, 0)     # cells/lamps lit, 0..5
        s.ready = state in ('on', 'damaged') or (state == 'charge' and i == 5)
        if state == 'damaged' and i == 1: s.ready = False                # a damaged part flickers out of ready

class OSt:
    """what one OUTSIDE-half frame shows."""
    def __init__(s, state, i):
        s.state, s.i = state, i
        s.dmg = {'damaged': 1, 'disabled': 2}.get(state, 0)
        s.powered = state not in ('off', 'disabled')

class BSt:
    """what one BARREL frame shows."""
    def __init__(s, state, i):
        s.state, s.i = state, i
        s.fire = state == 'fire'
        s.dmg = {'damaged': 1, 'disabled': 2}.get(state, 0)
        s.rc = (2, 1, 0)[i] if s.fire else 0                             # recoil: how far the barrel is pulled back (px)

FLANGE = 4                           # mounting flange that overhangs the wall face (px)

class OutHalf(Comp):
    """the OUTSIDE half as its own component: `<id>_out`. The turret ring sits in space; the bottom flange overhangs the outer wall face."""
    glow_pad = (8, 8, 8, 8)
    anims = [('on', 'on', 2, 3), ('off', 'off', 1, 0), ('damaged', 'damaged', 2, 4), ('disabled', 'disabled', 2, 3)]
    def __init__(s, wpn):
        s.wpn = wpn; s.id = wpn.id + '_out'; s.cells = wpn.out_cells; s.notes = wpn.out_notes
        s.anchors = {'pivot': list(wpn.pivot)}
    @property
    def w(self): return 64
    @property
    def h(self): return self.cells[1] * 16 + FLANGE
    def frame(self, state, i): return self.wpn.out_frame(state, i, self.h)
    def glow(self, state, i, g, ox, oy): self.wpn.out_glow(state, i, g, ox, oy)
    def finish_json(self, J, outdir): self.wpn.finish_barrel(J, outdir)

class Weapon(Comp):
    """A weapon = INSIDE half (this component, `<id>`), OUTSIDE half (`<id>_out`) and the rotating BARREL (`<id>_barrel`).
    Outward is UP at rotation 0: the outside half sits in space above the wall, the inside half on the floor below it."""
    cells = (4, 2)                       # the inside half's footprint; the frame is taller by the flange that overhangs the wall face
    out_cells = (4, 2)
    glow_pad = (8, 8, 8, 8)
    anims = [('on', 'on', 2, 3), ('off', 'off', 1, 0), ('charge', 'charge', 6, 0), ('fire', 'fire', 2, 12),
             ('damaged', 'damaged', 2, 4), ('disabled', 'disabled', 1, 0)]
    aim = 'fixed'                        # 'fixed' (aimed by pointing the ship; barrel gimbals a few degrees) or 'turret' (swivels in its ring)
    gimbal = 6                           # fixed guns: gimbal travel either side of straight out (degrees)
    pivot = (32, 12)                     # pivot_on_base in the OUTSIDE half's frame: the gimbal pin (fixed) or the turret ring centre (turret)
    iy = FLANGE                          # top of the inside footprint in its frame
    out_notes = ''
    # barrel, in EAST scratch-canvas terms: canvas is (length, width); pivot axis and muzzle tip on it
    blen, bwid = 42, 15
    bpivot = (6, 7)
    bmuzzle = (29, 7)
    bpad = 10                            # barrel glow padding
    banims = [('idle', 'idle', 1, 0), ('fire', 'fire', 3, 14), ('damaged', 'damaged', 2, 4), ('disabled', 'disabled', 1, 0)]
    line = 'standard'
    @property
    def w(self): return 64
    @property
    def h(self): return self.cells[1] * 16 + FLANGE
    # ---- inside half
    def inside(self, s, st): raise NotImplementedError
    def trim(self, s, st, half): pass      # extra trim drawn over the flange (gold on uniques)
    def hurt_in(self, s, st): pass         # damaged: sparks, a dead lamp, a crack
    def wreck_in(self, s, st): pass        # disabled: drawn after the dark pass
    def frame(self, state, i):
        st = St(state, i)
        s = Spr(self.w, self.h)
        self.inside(s, st)
        flange(s, 0, self.line); self.trim(s, st, 'in')
        if st.dmg == 1: self.hurt_in(s, st)
        elif st.dmg == 2:
            s = s.sub(DARK); self.wreck_in(s, st)
        s = s.copy(); outline_all(s); return drop_shadow(s)
    def glow(self, state, i, g, ox, oy): pass
    # ---- outside half
    def outside(self, s, st): raise NotImplementedError         # the turret seat and what rides on it (in space)
    def hurt_out(self, s, st): pass        # damaged: crack, dent, a loose part
    def wreck_out(self, s, st): pass       # disabled: scorched and dented, ring cracked, sparking (but never destroyed)
    def out_frame(self, state, i, h):
        st = OSt(state, i)
        s = Spr(64, h)
        self.outside(s, st)
        flange(s, h - FLANGE - 1, self.line, up=True); self.trim(s, st, 'out')
        if st.dmg == 1: self.hurt_out(s, st)
        elif st.dmg == 2:
            s = s.sub(DARK); self.wreck_out(s, st)
        s = s.copy(); outline_all(s); return drop_shadow(s)
    def out_glow(self, state, i, g, ox, oy): pass
    # ---- barrel
    def barrel(self, b, st): raise NotImplementedError          # paint pointing east on b
    def bhurt(self, b, st): pass
    def bbreak(self, b, st): return b
    def bwreck(self, b, st): pass
    def bafter(self, b, st): pass                                # flash etc., after the outline
    def bglow(self, state, i, g, ox, oy): pass                   # east-canvas coordinates
    def bpivot_final(self):
        px, py = self.bpivot
        return (py, self.blen - 1 - px)
    def barrel_frame(self, state, i, outline=True):
        st = BSt(state, i)
        b = Spr(self.blen, self.bwid)
        self.barrel(b, st)
        if st.dmg == 1: self.bhurt(b, st)
        elif st.dmg == 2:
            b = self.bbreak(b, st); b = b.sub(DARK); self.bwreck(b, st)
        if outline:
            b = b.copy(); outline_all(b); self.bafter(b, st)
        return ccw(b)
    def barrel_glow_frame(self, state, i):
        p = self.bpad
        g = Rgba(self.blen + 2 * p, self.bwid + 2 * p)
        if state != 'disabled': self.bglow(state, i, g, p, p)
        if state == 'damaged':
            for row in g.p:
                for q in row: q[3] = int(q[3] * (0.55 if i % 2 else 0.8))
        return ccw_rgba(g)
    def finish_json(self, J, outdir):
        """called by comp_base.export for the inside half: records the flange offset and exports the outside half and the barrel."""
        J['offset'] = [0, -FLANGE]
        import comp_base
        comp_base.export(OutHalf(self), outdir)
    def finish_barrel(self, J, outdir):
        """called for the outside half: writes the barrel layer (+ its own JSON) and adds the "barrel" block to the outside JSON."""
        frames, ganims, anims, gframes = [], {}, {}, []
        for (name, state, n, fps) in self.banims:
            anims[name] = [len(frames), n, fps]
            for i in range(n): frames.append(self.barrel_frame(state, i))
            if state != 'disabled':
                gl = [self.barrel_glow_frame(state, i) for i in range(n)]
                if any(q[3] for g in gl for row in g.p for q in row):
                    ganims[name] = [len(gframes), n, fps]; gframes += gl
        bw, bh = frames[0].w, frames[0].h
        save(sheet(frames, len(frames), bw, bh), '%s/%s_barrel.png' % (outdir, self.id))
        px, py = self.bpivot; mx, my = self.bmuzzle
        piv = [py, self.blen - 1 - px]; mz = [my, self.blen - 1 - mx]
        B = {'image': self.id + '_barrel.png', 'frame': [bw, bh], 'pivot_on_base': list(self.pivot), 'pivot_on_barrel': piv, 'muzzle': mz, 'anims': anims, 'aim': self.aim}
        if self.aim == 'fixed': B['gimbal_deg'] = self.gimbal
        BJ = {'frame': [bw, bh], 'pivot_on_base': list(self.pivot), 'aim': self.aim, 'anims': anims, 'anchors': {'pivot': piv, 'muzzle': mz},
              'notes': 'Rotating barrel, drawn pointing UP. Turn it about anchors.pivot placed on pivot_on_base of %s_out. fire: 3 frames, recoil 2/1/0 px with a muzzle flash.' % self.id}
        if self.aim == 'fixed': BJ['gimbal_deg'] = self.gimbal
        if gframes:
            gw, gh = gframes[0].w, gframes[0].h
            strip_ = Rgba(gw * len(gframes), gh)
            for k, g in enumerate(gframes): strip_.blit_rgba(g, k * gw, 0)
            strip_.save('%s/%s_barrel_glow.png' % (outdir, self.id))
            B['glow'] = {'image': self.id + '_barrel_glow.png', 'frame': [gw, gh], 'offset': [-self.bpad, -self.bpad], 'anims': ganims}
            BJ['glow'] = dict(B['glow'])
        J['barrel'] = B
        with open('%s/%s_barrel.json' % (outdir, self.id), 'w') as f: json.dump(BJ, f, indent=1); f.write('\n')

# ------------------------------------------------------------------ shared mount / barrel pieces
def turret_ring(s, cx=32, cy=14, d=19, hi='M', mid='S', lo='W', well='E'):
    """the socket the barrel pivots in: a raised steel ring round a dark well."""
    r = d // 2
    chamfer_fill(s, cx - r, cy - r, d, d, mid, d // 3); rim(s, mid, hi, lo, (cx - r, cy - r, cx + r, cy + r))
    w = d - 4; q = w // 2
    chamfer_fill(s, cx - q, cy - q, w, w, well, w // 3); rim(s, well, 'D', 'M', (cx - q, cy - q, cx + q, cy + q))
    for (x, y) in ((cx, cy - r + 1), (cx, cy + r - 1), (cx - r + 1, cy), (cx + r - 1, cy)): s.put(x, y, 'L')

def strip(s, st, x, y, n=5, cw=6, pitch=8, h=2, cols=('y', 'a', 'g')):
    """charge strip: n cells, yellow while charging, green when ready; dim and dark when idle."""
    recess(s, x - 2, y - 1, n * pitch + 2, h + 2, 'D', 'K')
    for k in range(n):
        cx = x + k * pitch
        on = st.powered and k < st.lit
        for r in range(h):
            if getattr(st, 'flash', False) and st.powered: c = 'H' if r == 0 else 'L'
            elif st.ready and on: c = cols[2]
            elif on: c = cols[0] if r == 0 else cols[1]
            else: c = 'W' if r == 0 else 'E'
            s.hline(cx, y + r, cw, c)
        if on: s.put(cx, y, 'H')

def strip_glow(g, ox, oy, st_state, i, x, y, n=5, cw=6, pitch=8, h=2, ready_rgb=(107, 211, 74), live_rgb=(255, 210, 58)):
    lit = {'charge': i, 'on': 5, 'damaged': 3}.get(st_state, 0)
    ready = st_state in ('on', 'damaged') or (st_state == 'charge' and i == 5)
    if st_state == 'damaged' and i == 1: ready = False
    for k in range(lit):
        glow(g, ox + x + k * pitch + cw / 2, oy + y + h / 2, 5.5, ready_rgb if ready else live_rgb, 0.5, 2.0, sx=1.5)

# muzzle flashes pointing EAST (column 0 sits on the muzzle): big, medium, afterglow
FLASH_E = [art("""
..oo..........
.oyyo.........
.yHHyoo.......
oyHHHHyoo.....
yHHHHHHHyyoo..
HHHHHHHHHHHyyo
HHHHHHHHHHHHHy
HHHHHHHHHHHyyo
yHHHHHHHyyoo..
oyHHHHyoo.....
.yHHyoo.......
.oyyo.........
..oo..........
"""), art("""
..o.........
.oyo........
.yHyoo......
oyHHHyyo....
yHHHHHHHyo..
HHHHHHHHHHyo
yHHHHHHHyo..
oyHHHyyo....
.yHyoo......
.oyo........
..o.........
"""), art("""
.o.......
oyo......
yHyoo....
HHHHyo...
yHyoo....
oyo......
.o.......
""")]

# ------------------------------------------------------------------ hull-mount template: outside | wall collar | inside
def turret_seat(s, out_h=32, cy=15, line='standard', d=25):
    """OUTSIDE: the armoured seat the turret ring sits on, widening into the collar."""
    py = cy + 4
    hi, mid, lo = ('S', 'W', 'E') if line == 'scrap' else (('W', 'E', 'D') if line == 'neon' else ('M', 'S', 'W'))
    bev(s, 6, py, 52, out_h - py, hi, mid, lo)
    turret_ring(s, 32, cy, d)

def flange(s, y, line='standard', up=False):
    """the mounting flange that overhangs the wall face (4 px): top of the inside half, bottom of the outside half."""
    hi, mid, lo = ('S', 'W', 'E') if line == 'scrap' else (('W', 'E', 'D') if line == 'neon' else ('M', 'S', 'W'))
    bev(s, 1, y, 62, FLANGE + 1, hi, mid, lo)
    for x in (4, 13, 50, 59): s.put(x, y + 2, 'L')
    if line == 'neon':
        s.hline(3, y + (1 if up else 3), 58, 'c')
    elif line == 'scrap':
        for x in range(20, 44): s.put(x, y + 2, 'a' if ((x - 20) // 2) % 2 == 0 else 'D')

def coupling(s, x, y, st, c='g'):
    """INSIDE: the power coupling where a cable plugs in (cable stub runs off the left edge)."""
    s.rect(0, y + 4, x + 2, 4, 'q'); s.hline(0, y + 4, x + 2, 'Q'); s.hline(0, y + 7, x + 2, 'n')
    bev(s, x, y, 10, 12, 'M', 'S', 'W')
    s.rect(x + 2, y + 3, 6, 6, 'D'); s.put(x + 3, y + 5, 'L'); s.put(x + 6, y + 5, 'L'); s.put(x + 3, y + 7, 'L'); s.put(x + 6, y + 7, 'L')
    s.put(x + 8, y + 1, c if st.powered else 'E')

def hatch(s, x, y, st, w=11, h=9, open_=False):
    """INSIDE: the repair hatch crew open: a latched panel with a wrench slot."""
    bev(s, x, y, w, h, 'L', 'M', 'S', cham=False)
    s.rect(x + 3, y + h // 2 - 1, w - 6, 2, 'W'); s.put(x + w - 3, y + h // 2 - 1, 'a'); s.put(x + w - 3, y + h // 2, 'u')
    s.put(x + 1, y + 1, 'W'); s.put(x + w - 2, y + 1, 'W'); s.put(x + 1, y + h - 2, 'W'); s.put(x + w - 2, y + h - 2, 'W')

def housing(s, y0, line='standard', strip_y=None):    # y0 = top of the inside footprint
    """INSIDE: the floor-standing housing."""
    if line == 'scrap': bev(s, 2, y0 + 1, 60, 30, 'M', 'W', 'E')
    elif line == 'neon': bev(s, 2, y0 + 1, 60, 30, 'W', 'E', 'D')
    else: bev(s, 2, y0 + 1, 60, 30, 'M', 'S', 'W')
    cylv(s, 28, y0 + 1, 8, 5, 'LMSSSSWE')                            # the turret column comes through the collar

STRIP_X, STRIP_DY = 14, 24           # charge strip: x of the first cell, y below the inside top

# ------------------------------------------------------------------ shared barrel helpers (east-pointing scratch canvas)
def hub(b, cy, d=15, mid='S', hi='M', lo='W'):
    """the turret hub that sits in the ring: a chamfered disc with an axis cap. Returns the pivot x."""
    r = d // 2
    chamfer_fill(b, 1, cy - r, d, d, mid, d // 3); rim(b, mid, hi, lo, (1, cy - r, d, cy + r))
    cx = 1 + r
    b.put(cx, cy, 'L'); b.put(cx + 1, cy + 1, 'W'); b.put(cx - 1, cy, hi); b.put(cx, cy - 1, hi)
    return cx

def fire_glow(g, ox, oy, i, tipx, cy, rgb=(255, 130, 50), core=(255, 235, 160), sx=1.3, scale=1.0):
    rc = (2, 1, 0)[i]
    glow(g, ox + tipx + 3 - rc, oy + cy + 0.5, (16, 11, 8)[i] * scale, rgb, (0.65, 0.5, 0.35)[i], 2.0, sx=sx)
    glow(g, ox + tipx + 2 - rc, oy + cy + 0.5, (8, 5, 3)[i] * scale, core, (0.75, 0.55, 0.4)[i], 1.6)

def stamp_flash(b, st, tipx, cy, arts=None, sub=None):
    a = (arts or FLASH_E)[st.i]
    b.stamp(tipx - st.rc, cy - len(a) // 2, a, sub)

def dead_cells(s, st, y, ks=(3, 4), n=5):
    for k in ks:
        for r in range(2): s.hline(STRIP_X + 8 * k, y + r, 6, 'E' if r else 'W')
    s.put(STRIP_X + 8 * ks[-1] + 2, y, 'r')

def wires_across(s, pts, n=7):
    """two wires bridging a split casing; each entry is (y, x)."""
    for yy, x in pts:
        for k in range(-1, n): s.put(x + k, yy, 'u' if k % 2 == 0 else 'n')

# ------------------------------------------------------------------ damage vocabulary for the outside half (disabled = scorched, dented, cracked, sparking: broken but fixable)
SOOT = [art("""
..DD....
.DKKD.D.
DKKKKDD.
.DKKKKD.
..DKDD..
...D....
"""), art("""
.D..DD.
DKDDKKD
.KKKKKD
DKKKKD.
.DDKD..
"""), art("""
..DD.
.DKKD
DKKKD
.DKD.
""")]
def soot(s, x, y, k=0):
    """soot only lands on pixels that exist."""
    for j, r in enumerate(SOOT[k]):
        for i, c in enumerate(r):
            if c != '.' and s.get(x + i, y + j) != '.': s.g[y + j][x + i] = c

def dent(s, x, y, w, h):
    """a sunken dent: dark lip top-left, lit lip bottom-right (the light is top-left, so a dent is the bevel inverted)."""
    s.hline(x, y, w, 'K'); s.vline(x, y, h, 'K')
    s.hline(x + 1, y + h - 1, w - 1, 'M'); s.vline(x + w - 1, y + 1, h - 1, 'M')
    s.rect(x + 1, y + 1, w - 2, h - 2, 'E') if w > 3 and h > 3 else None

def scorched(s, st, crack_pts=(), dents=(), soots=(), wires_=(), sparks=(), flap=None):
    """the OUTSIDE half's disabled state: soot, dents, a cracked ring, loose cables, sparks (alternating between two frames)."""
    for (x, y, k) in soots: soot(s, x, y, k)
    for (x, y, w, h) in dents: dent(s, x, y, w, h)
    for pts in crack_pts: crack(s, pts)
    for pts in wires_: wire(s, pts)
    if flap: s.stamp(flap[0], flap[1], FLAP)
    if sparks: spark(s, sparks[st.i % len(sparks)][0], sparks[st.i % len(sparks)][1], False)

FLAP = art("""
....SSM.
..SSMMS.
SSMMSS..
""")

def coil_v(s, x, y, w, h, lit, c=('c', 'b', 'E')):
    """a vertical coil: horizontal windings round a cylinder (lit = bright winding colours)."""
    ramp = ''.join((c[0], c[1], c[1], c[1], c[1], c[2])) if lit else 'MSSWWE'
    for r in range(h):
        if r % 2 == 0:
            for k, tone in enumerate(ramp_rows(w, ramp)): s.put(x + k, y + r, tone)
        else: s.hline(x, y + r, w, 'D')
    s.vline(x, y, h, 'K') if False else None

def coil_h(b, x, y, n, h, lit=True, c=('c', 'b', 'E'), flange='M'):
    """a coil on a barrel (east-pointing): vertical windings, flanges at both ends."""
    ramp = ''.join((c[0], c[1], c[1], c[1], c[1], c[2])) if lit else 'MSSWWE'
    for k in range(n):
        if k in (0, n - 1): b.vline(x + k, y, h, flange); b.put(x + k, y + h - 1, 'W')
        elif k % 2 == 1:
            for r, tone in enumerate(ramp_rows(h, ramp)): b.put(x + k, y + r, tone)
        else: b.vline(x + k, y, h, 'D')

def lens_c(s, x, y, w, h, on, cols):
    """lens in any family colour: cols = (outer, mid, core, hot); dead slate when off."""
    if on:
        s.rect(x, y, w, h, cols[0]); s.rect(x + 1, y, w - 1, h, cols[1]); s.rect(x + w - 1, y, 1, h, cols[2])
        if h > 2: s.rect(x + w - 1, y + 1, 1, h - 2, cols[3])
    else:
        s.rect(x, y, w, h, 'E'); s.put(x, y, 'W')

def fliph(rows): return [r[::-1] for r in rows]

# ------------------------------------------------------------------ scrap line vocabulary
def plate(s, x, y, w, h, kind='a', bolt=True):
    """a patch plate: three mismatched kinds (light grey, dark grey, rust), bolted on."""
    hi, mid, lo = {'a': ('M', 'S', 'W'), 'b': ('S', 'W', 'E'), 'r': ('Q', 'u', 'n')}[kind]
    bev(s, x, y, w, h, hi, mid, lo, cham=False)
    if bolt and w > 5 and h > 5:
        for (bx, by) in ((x + 1, y + 1), (x + w - 2, y + 1), (x + 1, y + h - 2), (x + w - 2, y + h - 2)): s.put(bx, by, 'L')

def scrap_ring(s, cx=32, cy=15, d=25):
    turret_ring(s, cx, cy, d, 'S', 'W', 'E', 'D')
    r = d // 2
    for k in range(3): s.put(cx - 4 + 4 * k, cy - r + 2, 'u')           # rust bleed on the ring

def junk(s, x, y, kind=0):
    """a few pieces of scrap: gear, bolt, plate, pipe."""
    arts = [art("""
.L.
LSL
.W.
"""), art("""
MS.
WSS
.WE
"""), art("""
..Q
uuQ
nuu
"""), art("""
LLM
.SW
""")]
    s.stamp(x, y, arts[kind % 4])


# ------------------------------------------------------------------ FIXED guns: forward-heavy housing, barrel in a sleeve / gimbal collar
def gun_housing(s, line='standard', out_h=32, cy=12, bw=26, bh=26):
    """OUTSIDE half of a fixed gun: a forward-heavy housing block with the barrel sleeve at its outward end and a gimbal collar (pin at (32, cy))."""
    hi, mid, lo = ('S', 'W', 'E') if line == 'scrap' else (('W', 'E', 'D') if line == 'neon' else ('M', 'S', 'W'))
    pad_y = cy + 8
    bev(s, 6, pad_y, 52, out_h - pad_y, hi, mid, lo)                              # base pad running into the flange
    x0 = 32 - bw // 2; top = cy - 10
    bev(s, x0, top, bw, bh, hi, mid, lo)                                          # the housing block
    sw = bw - 4
    bev(s, 32 - sw // 2, top - 1, sw, 8, hi, mid, lo)                              # the sleeve at the outward end
    s.rect(32 - (sw - 8) // 2, top, sw - 8, 6, 'D'); s.hline(32 - (sw - 8) // 2, top, sw - 8, 'K')   # the barrel channel
    bev(s, x0 - 1, cy - 3, bw + 2, 5, 'L', 'M', 'S', cham=False)                   # gimbal collar
    s.put(32, cy, 'L'); s.put(33, cy + 1, 'W'); s.put(31, cy, 'M')
    bolts(s, [(x0 + 2, cy - 1), (x0 + bw - 3, cy - 1)])
    if line == 'scrap':
        plate(s, x0 + 3, cy + 5, 9, 7, 'r'); weld(s, x0 + 14, cy + 6, 6, True)
        s.hline(32 - sw // 2 + 1, top + 5, 4, 'u')
    elif line == 'neon':
        s.hline(x0 + 1, top, bw - 2, 'c'); s.hline(x0 - 1, cy - 3, bw + 2, 'c'); s.hline(x0 - 1, cy + 1, bw + 2, 'c')
    else:
        s.rect(x0 + 4, cy + 6, bw - 8, 1, 'D'); s.rect(x0 + 4, cy + 9, bw - 8, 1, 'D')
        s.hline(x0 + 4, cy + 12, 3, 'W'); s.hline(x0 + 8, cy + 12, 2, 'W')

def breech(b, cy, w=15, mid='S', hi='M', lo='W'):
    """fixed gun, barrel side: the rectangular breech with the gimbal pin and a bracing cuff where the barrel enters the sleeve."""
    bev(b, 1, cy - w // 2, 11, w, hi, mid, lo)
    chamfer_fill(b, 4, cy - 2, 5, 5, 'S', 1); rim(b, 'S', 'L', 'W', (4, cy - 2, 8, cy + 2)); b.put(6, cy, 'E')
    bev(b, 11, cy - w // 2 - 1, 3, w + 2, 'L', 'M', 'S', cham=False); b.vline(13, cy - w // 2 - 1, w + 2, 'W')

def eye(b, x, y, c='c'):
    """a small sensor eye on a turret head (it aims itself)."""
    b.rect(x, y, 3, 3, 'D'); b.put(x + 1, y + 1, c); b.put(x, y, 'L'); b.put(x + 2, y + 2, 'W')

def pod(b, x, y, c='c'):
    """a sensor pod on the side of a turret head: a small housing with a lit eye."""
    bev(b, x, y, 6, 4, 'M', 'S', 'W', cham=False); b.put(x + 2, y + 1, c); b.put(x + 3, y + 1, c); b.put(x + 2, y + 2, 'D'); b.put(x + 3, y + 2, 'D')
