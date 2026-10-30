"""Hull-mount framework for sector gear (wave 3): the weapon format (inside half, `_out` half, optional rotating `_barrel`) with any width in cells.
Intakes have no barrel; radars spin a dish; tractor turrets swivel an emitter head. Built on wbase.Weapon: the barrel, glow and JSON code is the same,
only the width (2 or 4 cells), the states (`pulling`, a sweep) and the no-barrel case are new."""
import json, math
import pal_sector
from wbase import *
from wbase import FLANGE, OutHalf, St, OSt
from lines_kit import circle, ring, line, thick, edge as _edge
from mach import glow, bev, recess
import comp_base

# ------------------------------------------------------------------ small drawing helpers
def fillpoly(s, pts, c):
    """scanline fill of a polygon (pixel centres, even-odd)."""
    ys = [p[1] for p in pts]; xs = [p[0] for p in pts]
    for y in range(int(min(ys)), int(max(ys)) + 1):
        for x in range(int(min(xs)), int(max(xs)) + 1):
            px_, py_ = x + 0.5, y + 0.5; inside = False; n = len(pts)
            for k in range(n):
                ax, ay = pts[k]; bx, by = pts[(k + 1) % n]
                if (ay > py_) != (by > py_) and px_ < (bx - ax) * (py_ - ay) / (by - ay) + ax: inside = not inside
            if inside: s.put(x, y, c)

def lit_poly(s, pts, mid, hi, lo):
    """a bevelled polygon: mid fill, light on the up/left edges, dark on the down/right edges (light from the top-left)."""
    fillpoly(s, pts, mid)
    xs = [p[0] for p in pts]; ys = [p[1] for p in pts]
    rim(s, mid, hi, lo, (max(0, int(min(xs)) - 1), max(0, int(min(ys)) - 1), min(s.w - 1, int(max(xs)) + 1), min(s.h - 1, int(max(ys)) + 1)))

def flange_w(s, y, W, line_='standard', up=False):
    """the mounting flange that overhangs the wall face (4 px), any width."""
    hi, mid, lo = ('S', 'W', 'E') if line_ == 'scrap' else (('W', 'E', 'D') if line_ == 'neon' else ('M', 'S', 'W'))
    bev(s, 1, y, W - 2, FLANGE + 1, hi, mid, lo)
    for x in (4, 13, W - 14, W - 5) if W > 40 else (4, W - 5): s.put(x, y + 2, 'L')
    if line_ == 'neon':
        s.hline(3, y + (1 if up else 3), W - 6, 'c')
    elif line_ == 'scrap':
        n = W // 3
        for x in range(W // 2 - n // 2 - 2, W // 2 + n // 2 + 2): s.put(x, y + 2, 'a' if ((x - W // 2) // 2) % 2 == 0 else 'D')

def housing_w(s, y0, W, line_='standard', h=30):
    tones = ('M', 'W', 'E') if line_ == 'scrap' else (('W', 'E', 'D') if line_ == 'neon' else ('M', 'S', 'W'))
    bev(s, 2, y0 + 1, W - 4, h, *tones)

def lamp_px(s, x, y, c, on=True):
    s.put(x, y, c if on else 'E')

class OutHalfW(OutHalf):
    """the OUTSIDE half as its own component `<id>_out`, any width; the animation list comes from the mount."""
    def __init__(s, wpn):
        OutHalf.__init__(s, wpn)
        s.anims = wpn.out_anims
        s.glow_pad = getattr(wpn, 'out_glow_pad', (8, 8, 8, 8))
    @property
    def w(self): return self.cells[0] * 16
    def frame(self, state, i): return self.wpn.out_frame(state, i, self.h)

class Mount(Weapon):
    """subclass: set id, cells (cw, 2), line; implement inside / outside (+ hurt/wreck hooks, glow). has_barrel False = an intake."""
    has_barrel = False
    out_anims = [('on', 'on', 2, 3), ('off', 'off', 1, 0), ('damaged', 'damaged', 2, 4), ('disabled', 'disabled', 2, 3)]
    anims = [('on', 'on', 2, 3), ('off', 'off', 1, 0), ('damaged', 'damaged', 2, 4), ('disabled', 'disabled', 1, 0)]
    pivot = (16, 14)
    bnotes = 'Rotating part, drawn pointing UP.'
    @property
    def w(self): return self.cells[0] * 16
    @property
    def out_cells(self): return self.cells
    def frame(self, state, i):
        st = St(state, i)
        s = Spr(self.w, self.h)
        self.inside(s, st)
        flange_w(s, 0, self.w, self.line); self.trim(s, st, 'in')
        if st.dmg == 1: self.hurt_in(s, st)
        elif st.dmg == 2:
            s = s.sub(DARK); self.wreck_in(s, st)
        s = s.copy(); outline_all(s); return drop_shadow(s)
    def out_frame(self, state, i, h):
        st = OSt(state, i)
        ow = self.out_cells[0] * 16
        s = Spr(ow, h)
        self.outside(s, st)
        flange_w(s, h - FLANGE - 1, ow, self.line, up=True); self.trim(s, st, 'out')
        if st.dmg == 1: self.hurt_out(s, st)
        elif st.dmg == 2:
            s = s.sub(DARK); self.wreck_out(s, st)
        s = s.copy(); outline_all(s); return drop_shadow(s)
    def finish_json(self, J, outdir):
        J['offset'] = [0, -FLANGE]
        comp_base.export(OutHalfW(self), outdir)
    def finish_barrel(self, J, outdir):
        if not self.has_barrel: return
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
        px_, py_ = self.bpivot; mx, my = self.bmuzzle
        piv = [py_, self.blen - 1 - px_]; mz = [my, self.blen - 1 - mx]
        B = {'image': self.id + '_barrel.png', 'frame': [bw, bh], 'pivot_on_base': list(self.pivot), 'pivot_on_barrel': piv, 'anims': anims, 'aim': self.aim}
        BJ = {'frame': [bw, bh], 'pivot_on_base': list(self.pivot), 'aim': self.aim, 'anims': anims, 'anchors': {'pivot': piv}, 'notes': self.bnotes}
        if self.aim in ('fixed', 'turret'): B['muzzle'] = mz; BJ['anchors']['muzzle'] = mz
        if self.aim == 'spin': B['spin'] = True; BJ['spin'] = True
        if gframes:
            gw, gh = gframes[0].w, gframes[0].h
            strip_ = Rgba(gw * len(gframes), gh)
            for k, g in enumerate(gframes): strip_.blit_rgba(g, k * gw, 0)
            strip_.save('%s/%s_barrel_glow.png' % (outdir, self.id))
            B['glow'] = {'image': self.id + '_barrel_glow.png', 'frame': [gw, gh], 'offset': [-self.bpad, -self.bpad], 'anims': ganims}
            BJ['glow'] = dict(B['glow'])
        J['barrel'] = B
        with open('%s/%s_barrel.json' % (outdir, self.id), 'w') as f: json.dump(BJ, f, indent=1); f.write('\n')

# ------------------------------------------------------------------ damage vocabulary shared by the sector parts
def dead_lamp(s, x, y): s.put(x, y, 'E'); s.put(x + 1, y, 'E') if False else None

def lamp_row(s, x, y, cols, states):
    """a row of 2x2 lamps; cols[k] lit colour, states[k] True = lit."""
    for k, (c, on) in enumerate(zip(cols, states)):
        s.rect(x + k * 4, y, 2, 2, c if on else 'E')
        if on: s.put(x + k * 4, y, 'H')

# ------------------------------------------------------------------ sweep screen (radar consoles): a dark scope with a turning line and blips
SWEEP = {'standard': ('g', 'g', 'D'), 'scrap': ('a', 'o', 'n'), 'neon': ('c', 'C', 'N')}
def scope(s, x, y, w, h, i, n=8, line_='standard', powered=True, blips=((0.62, 0.30), (0.30, 0.72), (0.78, 0.66)), square=False):
    """a radar scope: dark recess, range rings, a sweep line turning one step per frame with a short fading trail, blips lighting as it passes.
    i = frame 0..n-1 (None = a dead screen)."""
    bright, trail, back = SWEEP[line_]
    if i is None: powered = False
    recess(s, x, y, w, h, 'K' if line_ != 'neon' else 'N', 'K')
    s.rect(x + 1, y + 1, w - 2, h - 2, 'K' if line_ != 'neon' else 'N')
    cx, cy = x + w / 2.0, y + h / 2.0; R = min(w, h) / 2.0 - 1.6
    if not powered:
        for k in range(1, 3): s.put(int(cx - 2 + k), int(cy), 'E')
        return
    dim = {'g': 'E', 'a': 'n', 'c': 'I'}[bright]
    for r in (R, R * 0.55):
        for t in range(0, 360, 6):
            px_, py_ = int(cx + r * math.cos(math.radians(t))), int(cy + r * math.sin(math.radians(t)))
            if x < px_ < x + w - 1 and y < py_ < y + h - 1 and s.get(px_, py_) in ('K', 'N'): s.put(px_, py_, dim)
    ang = (360.0 / n) * i - 90.0
    for k, (c, back_) in enumerate(((bright, 0), (trail, 14), ('E' if bright == 'g' else dim, 30))):
        a = math.radians(ang - back_)
        for rr in range(0, int(R) + 1):
            px_, py_ = int(cx + rr * math.cos(a)), int(cy + rr * math.sin(a))
            if x < px_ < x + w - 1 and y < py_ < y + h - 1 and (k == 0 or s.get(px_, py_) in ('K', 'N', dim)): s.put(px_, py_, c)
    for (bx, by) in blips:                                                      # a blip lights up when the sweep passes, then fades
        px_, py_ = int(x + 1 + bx * (w - 2)), int(y + 1 + by * (h - 2))
        a_b = (math.degrees(math.atan2(py_ - cy, px_ - cx)) + 90) % 360
        a_s = (ang + 90) % 360
        d = (a_s - a_b) % 360
        if d < 150: s.put(px_, py_, 'H' if d < 45 else bright); s.put(px_ + 1, py_, bright) if d < 45 else None
