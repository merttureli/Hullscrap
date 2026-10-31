"""Shared kit for the racial tech art (docs/waves/racial_tech_1.md): a weapon base class that takes its colours from the race, and a small drawing
vocabulary (steam, chains, arcs, gems, spore sacs, rivets) that the per-race modules tech_<race>.py build their parts from. No palette additions:
every colour is an existing letter, so palette.gpl does not change."""
import math
from wbase import *

from lines_kit import circle, ring, line, thick, shift_rect, glow_xy, col_tones, chamfer_tones, octant
from comp_base import chamfer_fill, rim, DARK

RGB_ = {'cyan': (60, 242, 255), 'amber': (225, 161, 54), 'orange': (255, 138, 30), 'yellow': (255, 210, 58), 'green': (107, 211, 74),
        'magenta': (255, 79, 216), 'violet': (160, 110, 230), 'red': (224, 65, 59), 'white': (244, 246, 248), 'blue': (79, 163, 255),
        'teal': (123, 208, 166), 'pink': (232, 138, 160)}

def flash_arts(sub):
    """the muzzle flash arts recoloured: sub maps the letters o, y, H to the race's colours."""
    return [[''.join(sub.get(c, c) for c in r) for r in a] for a in FLASH_E]

# ------------------------------------------------------------------ polygons, gems, small shapes
def fillpoly(s, pts, c):
    """scanline fill of a convex-or-not polygon (pixel centres), clipped to the sprite."""
    ys = [p[1] for p in pts]
    for y in range(int(math.floor(min(ys))), int(math.ceil(max(ys))) + 1):
        yy = y + 0.5; xs = []
        for (x0, y0), (x1, y1) in zip(pts, pts[1:] + pts[:1]):
            if (y0 <= yy < y1) or (y1 <= yy < y0): xs.append(x0 + (yy - y0) * (x1 - x0) / (y1 - y0))
        xs.sort()
        for a, b in zip(xs[0::2], xs[1::2]):
            for x in range(int(math.ceil(a - 0.5)), int(math.floor(b - 0.5)) + 1): s.put(x, y, c)

def gem(s, cx, cy, hw, hh, tones=('c', 'C', 'B'), core='H', lit=True, tilt=0):
    """a faceted crystal standing on its point-up axis: light top-left facet, mid left, dark right, a white ridge when lit."""
    top, bot = (cx + tilt, cy - hh), (cx - tilt, cy + hh)
    ul, ur = (cx - hw + tilt // 2, cy - hh * 0.35), (cx + hw + tilt // 2, cy - hh * 0.35)
    ll, lr = (cx - hw - tilt // 2, cy + hh * 0.35), (cx + hw - tilt // 2, cy + hh * 0.35)
    m = (cx, cy - hh * 0.15)
    fillpoly(s, [top, ul, ll, bot, lr, ur], tones[1])
    fillpoly(s, [top, bot, lr, ur], tones[2])
    fillpoly(s, [top, ul, m], tones[0])
    if lit and core:
        s.put(int(cx), int(cy - hh * 0.5), core)
        if hh > 4: s.put(int(cx - 1), int(cy - hh * 0.35), core)

def sac(s, x, y, w, h, tones=('X', 'V', 'Z'), gloss='H'):
    """a spore sac: a glossy oval, light top-left, a gloss pixel."""
    chamfer_fill(s, x, y, w, h, tones[1], max(1, min(w, h) // 3))
    rim(s, tones[1], tones[0], tones[2], (x, y, x + w - 1, y + h - 1))
    if gloss: s.put(x + 1, y + 1, gloss)

def puff(s, x, y, k, c=('H', 'L', 'M')):
    """a steam puff (k 0..3 = growing and thinning), standing on (x, y) = its centre."""
    A = [[(0, 0), (1, 0), (0, -1)], [(0, 0), (1, 0), (-1, 0), (0, -1), (1, -1)],
         [(0, 0), (1, 0), (-1, 0), (0, -1), (1, -1), (-1, -1), (0, -2), (2, -1)], [(0, 0), (-1, -1), (1, -2), (2, -1), (0, -2)]][k % 4]
    for j, (dx, dy) in enumerate(A): s.put(x + dx, y + dy, c[0] if j == 0 else (c[1] if j < 4 else c[2]))

def jet(s, x, y, n, dx, dy, i, c=('H', 'L', 'M')):
    """a leaking jet of steam: n dots leaving (x, y) along (dx, dy), spreading and fading, the pattern shifting with i."""
    for k in range(n):
        px, py = x + dx * (k + 1) + (k % 2) * dy * (1 if (i + k) % 2 else -1), y + dy * (k + 1) + (k % 2) * dx * (1 if (i + k) % 2 else -1)
        s.put(px, py, c[min(2, k * 3 // max(1, n))])

def drip(s, x, y, i, n=3, c='c', c2='H'):
    for k in range(n): s.put(x, y + ((i + k * 2) % (n * 2)), c if k % 2 else c2)

def arc(s, pts, core='H', rim_='c', halo='C', thick_=True):
    """an electric arc along a polyline: white core, cyan rim, dim cyan halo on empty pixels only."""
    for (x0, y0), (x1, y1) in zip(pts, pts[1:]):
        n = max(abs(x1 - x0), abs(y1 - y0), 1)
        for t in range(n + 1):
            x = x0 + round((x1 - x0) * t / n); y = y0 + round((y1 - y0) * t / n)
            if halo:
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    if s.get(x + dx, y + dy) == '.': s.put(x + dx, y + dy, halo)
    for (x0, y0), (x1, y1) in zip(pts, pts[1:]):
        n = max(abs(x1 - x0), abs(y1 - y0), 1)
        for t in range(n + 1):
            x = x0 + round((x1 - x0) * t / n); y = y0 + round((y1 - y0) * t / n)
            s.put(x, y, rim_)
    for (x0, y0), (x1, y1) in zip(pts, pts[1:]):
        s.put((x0 + x1) // 2, (y0 + y1) // 2, core)
    s.put(*pts[0], core); s.put(*pts[-1], core)

def zig(x0, y0, x1, y1, n, amp, seed=0):
    """a jagged polyline from (x0, y0) to (x1, y1) with n kinks of amplitude amp; deterministic from seed."""
    pts = [(x0, y0)]
    dx, dy = x1 - x0, y1 - y0; L = max(1.0, math.hypot(dx, dy)); nx, ny = -dy / L, dx / L
    for k in range(1, n):
        t = k / n; o = amp * (1 if (k + seed) % 2 else -1) * (0.6 + 0.4 * ((k * 7 + seed * 3) % 3) / 2)
        pts.append((int(round(x0 + dx * t + nx * o)), int(round(y0 + dy * t + ny * o))))
    pts.append((x1, y1)); return pts

def chain(s, pts, c1='M', c2='W', c3='E'):
    """a chain along a polyline: links alternate flat (a 2x1 oval) and edge-on (a single pixel), with a dark pixel under each flat link."""
    k = 0
    for (x0, y0), (x1, y1) in zip(pts, pts[1:]):
        n = max(abs(x1 - x0), abs(y1 - y0), 1)
        for t in range(n):
            x = x0 + round((x1 - x0) * t / n); y = y0 + round((y1 - y0) * t / n)
            if k % 3 == 0: s.put(x, y, c1); s.put(x + 1, y, c2)
            elif k % 3 == 1: s.put(x, y, c2)
            else: s.put(x, y, c3)
            k += 1

def rivet(s, x, y, big=False):
    if big: s.put(x, y, 'L'); s.put(x + 1, y, 'M'); s.put(x, y + 1, 'S'); s.put(x + 1, y + 1, 'E')
    else: s.put(x, y, 'L'); s.put(x + 1, y + 1, 'E')

def rivet_row(s, x, y, n, pitch=4, big=False, vert=False):
    for k in range(n):
        if vert: rivet(s, x, y + k * pitch, big)
        else: rivet(s, x + k * pitch, y, big)

def pipe_h(s, x, y, w, h=3, tones='LSE', clamps=()):
    for k, c in enumerate(ramp_rows(h, tones)): s.hline(x, y + k, w, c)
    for cx in clamps: s.vline(cx, y - 1, h + 2, 'W'); s.vline(cx + 1, y - 1, h + 2, 'M')

def pipe_v(s, x, y, w, h, tones='LSE', clamps=()):
    for k, c in enumerate(ramp_rows(w, tones)): s.vline(x + k, y, h, c)
    for cy in clamps: s.hline(x - 1, cy, w + 2, 'W'); s.hline(x - 1, cy + 1, w + 2, 'M')

def wheel(s, cx, cy, r=3, c='r', hub_='L', turn=0):
    """a valve hand-wheel seen from above: a ring with two spokes (turn 0/1 swaps the spoke axis)."""
    ring(s, cx + .5, cy + .5, r - 1, r, c)
    if turn % 2 == 0: s.hline(cx - r + 1, cy, 2 * r - 1, c); s.vline(cx, cy - r + 1, 2 * r - 1, c)
    else:
        for d in range(-(r - 1), r): s.put(cx + d, cy + d, c); s.put(cx + d, cy - d, c)
    s.put(cx, cy, hub_)

def dial(s, x, y, needle=0, c='H', face='D', rimc='M'):
    """a 5x5 pressure dial; needle 0..3 picks one of four needle positions."""
    s.stamp(x, y, art(".MMM.\nMDDDM\nMDDDM\nMDDDM\n.MMM."))
    s.put(x + 1, y + 1, 'L')
    for (dx, dy) in [((1, 1), (2, 1)), ((2, 1), (3, 1)), ((3, 2), (3, 3)), ((1, 3), (1, 2))][needle % 4][:2]: s.put(x + dx, y + dy, 'r')
    s.put(x + 2, y + 2, c)

def dead_lamp(s, x, y, w=2, h=2): s.rect(x, y, w, h, 'E'); s.put(x, y, 'W')

# ------------------------------------------------------------------ the race weapon base
class RW(Weapon):
    """Weapon with the race's colours: HT = housing tones (light, mid, dark), FT = flange tones, CH = charge colours (charging row, second row, ready)."""
    HT = ('M', 'S', 'W'); FT = ('M', 'S', 'W'); CH = ('y', 'a', 'g')
    LIVE = (255, 210, 58); READY = (107, 211, 74)       # glow colours of the charge strip
    pivot = (32, 12)
    DK = {}                                           # the race's letters -> their dead (disabled) tones; the shared DARK map covers the steel and the standard colours
    def dm(self):
        m = dict(DARK); m.update(self.DK); return m
    def frame(self, state, i):
        st = St(state, i); s = Spr(self.w, self.h)
        self.inside(s, st)
        flange(s, 0, self.line); self.trim(s, st, 'in')
        if st.dmg == 1: self.hurt_in(s, st)
        elif st.dmg == 2: s = s.sub(self.dm()); self.wreck_in(s, st)
        s = s.copy(); outline_all(s); return drop_shadow(s)
    def out_frame(self, state, i, h):
        st = OSt(state, i); s = Spr(64, h)
        self.outside(s, st)
        flange(s, h - FLANGE - 1, self.line, up=True); self.trim(s, st, 'out')
        if st.dmg == 1: self.hurt_out(s, st)
        elif st.dmg == 2: s = s.sub(self.dm()); self.wreck_out(s, st)
        s = s.copy(); outline_all(s); return drop_shadow(s)
    def barrel_frame(self, state, i, outline=True):
        st = BSt(state, i); b = Spr(self.blen, self.bwid)
        self.barrel(b, st)
        if st.dmg == 1: self.bhurt(b, st)
        elif st.dmg == 2: b = self.bbreak(b, st); b = b.sub(self.dm()); self.bwreck(b, st)
        if outline: b = b.copy(); outline_all(b); self.bafter(b, st)
        return ccw(b)
    def trim(self, s, st, half):
        y = 0 if half == 'in' else s.h - FLANGE - 1
        hi, mid, lo = self.FT
        bev(s, 1, y, 62, FLANGE + 1, hi, mid, lo)
        for x in (4, 13, 50, 59): s.put(x, y + 2, 'L')
        self.flange_trim(s, st, half, y)
    def flange_trim(self, s, st, half, y): pass
    # shared inside pieces
    def rhousing(self, s, y0, col=True):
        hi, mid, lo = self.HT
        bev(s, 2, y0 + 1, 60, 30, hi, mid, lo)
        if col: cylv(s, 28, y0 + 1, 8, 5, 'LMSSSSWE')
        s.hline(4, y0 + 22, 56, 'D'); s.hline(4, y0 + 29, 56, 'D')               # panel seams above and below the indicator
        for x in (5, 10, 54, 58): s.put(x, y0 + 26, 'W'); s.put(x, y0 + 27, 'E')   # vent slots
    def rstrip(self, s, st, y0): strip(s, st, STRIP_X, y0 + STRIP_DY, cols=self.CH)
    def rstrip_glow(self, g, ox, oy, state, i, y0): strip_glow(g, ox, oy, state, i, STRIP_X, y0 + STRIP_DY, ready_rgb=self.READY, live_rgb=self.LIVE)
    # shared outside pieces
    def rgun_housing(self, s, cy=12, bw=26, bh=26, out_h=32):
        """fixed gun, outside: a forward-heavy block with the barrel sleeve at its outward end and a gimbal collar (pin at (32, cy)), in the race's tones."""
        hi, mid, lo = self.HT
        pad_y = cy + 8
        bev(s, 6, pad_y, 52, out_h - pad_y, hi, mid, lo)
        x0 = 32 - bw // 2; top = cy - 10
        bev(s, x0, top, bw, bh, hi, mid, lo)
        sw = bw - 4
        bev(s, 32 - sw // 2, top - 1, sw, 8, hi, mid, lo)
        s.rect(32 - (sw - 8) // 2, top, sw - 8, 6, 'D'); s.hline(32 - (sw - 8) // 2, top, sw - 8, 'K')
        bev(s, x0 - 1, cy - 3, bw + 2, 5, 'L', 'M', 'S', cham=False)
        s.put(32, cy, 'L'); s.put(33, cy + 1, 'W'); s.put(31, cy, 'M')
        bolts(s, [(x0 + 2, cy - 1), (x0 + bw - 3, cy - 1)])
        s.rect(x0 + 4, cy + 6, bw - 8, 1, 'D'); s.rect(x0 + 4, cy + 9, bw - 8, 1, 'D')
        s.hline(x0 + 4, cy + 12, 3, 'W'); s.hline(x0 + 8, cy + 12, 2, 'W')
        return x0, top
    def rturret_seat(self, s, cy=15, d=25):
        hi, mid, lo = self.HT
        py = cy + 4
        bev(s, 6, py, 52, 32 - py, hi, mid, lo)
        turret_ring(s, 32, cy, d)
