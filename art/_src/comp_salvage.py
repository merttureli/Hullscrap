"""Salvage intakes (hull mounts, no barrel): the mouth outside (an open scoop or net with a `pulling` anim, a magnetic shimmer in the glow layer)
and the sorting hopper inside (bits moving). net_mouth_scrap 2x2+2x2; intake_mk1..mk3 4x2+4x2 (tier ladder); lumen_siphon_neon 4x2+4x2."""
from mnt import *
from lines_kit import navy_panel, crystal

MINT = (140, 240, 196)

# ------------------------------------------------------------------ shared: the magnetic pull shimmer (soft alpha arcs closing on the mouth)
def pull_glow(g, cx, cy, R0, i, n=6, rgb=MINT, strength=0.55, spread=62, rings=3, base=3.0):
    """wavefronts: arcs centred on the mouth, opening upward, that close in one ring-spacing over the animation loop (n frames)."""
    P = (R0 - base) / rings
    for k in range(rings):
        r = base + ((k + 1) - (i / n)) * P
        if r < base * 0.8: continue
        a = strength * (1.0 - (r - base) / (R0 - base + 1e-6)) ** 0.9 + 0.08
        for t in range(-spread * 4, spread * 4 + 1):
            ang = math.radians(-90 + t / 4.0)
            x, y = cx + r * math.cos(ang), cy + r * math.sin(ang)
            fade = 1.0 - abs(t / 4.0) / (spread + 4)
            g.over(int(x), int(y), rgb + (int(255 * max(0.0, min(1.0, a * fade)) * 0.9),))
            g.over(int(x), int(y) - 1, rgb + (int(255 * max(0.0, min(1.0, a * fade)) * 0.4),))

def junk_bits(s, pts, tones):
    """tiny moving cargo: 2x2 bits."""
    for (x, y), c in zip(pts, tones):
        s.rect(x, y, 2, 2, c); s.put(x, y, 'L' if c in 'SMW' else 'H')

# ------------------------------------------------------------------ Net Mouth (scrap) 2x2 + 2x2
def net(s, x0, y0, w, h, shift=0, tone=('M', 'S', 'W')):
    """a welded cargo net over a dark mouth: diamond mesh, a knot at each crossing."""
    s.rect(x0, y0, w, h, 'K')
    for yy in range(h):
        for xx in range(w):
            a, b = (xx + yy + shift) % 6, (xx - yy + 600 + shift) % 6
            if a == 0 or b == 0:
                lit = (xx + yy) < (w + h) * 0.45
                s.put(x0 + xx, y0 + yy, tone[0] if (a == 0 and b == 0) else (tone[1] if lit else tone[2]))

class NetMouth(Mount):
    id = 'net_mouth_scrap'; line = 'scrap'; cells = (2, 2); pivot = (16, 16)
    glow_pad = (8, 8, 8, 8)
    out_glow_pad = (8, 20, 8, 8)
    out_anims = [('on', 'on', 2, 3), ('pulling', 'pulling', 6, 10), ('off', 'off', 1, 0), ('damaged', 'damaged', 2, 4), ('disabled', 'disabled', 2, 3)]
    anims = [('on', 'on', 6, 4), ('pulling', 'pulling', 6, 10), ('off', 'off', 1, 0), ('damaged', 'damaged', 2, 4), ('disabled', 'disabled', 1, 0)]
    out_notes = ('OUTSIDE half of the Net Mouth (scrap, 2x2): a welded cargo net stretched on a rusty frame, hazard tape on the posts, a horseshoe magnet wired to the top brace, junk caught in the mesh. '
                 'pulling: the net billows, caught bits slide to the throat, the magnet throws mint shimmer arcs (glow layer). damaged: net torn open, a post bent, tape peeling; disabled: scorched, dented, net burnt to strands, sparking.')
    notes = ('INSIDE half of the Net Mouth (scrap, 2x2): a riveted junk hopper with a patched chute and a dial gauge. on: scrap bits slowly tumble down the hopper (6 frames); pulling: the same, faster, with the gauge swinging and the lamp blinking. '
             'damaged: chute dented, a bit jammed, lamp dead; disabled: a chunk jammed in the chute.')
    PATH = [(9, 11), (13, 12), (17, 13), (20, 15), (20, 18), (17, 20), (14, 21), (13, 24), (14, 27), (15, 29), (16, 31), (16, 33)]

    # ---------------------------------------------------------------- mouth (outside)
    def outside(self, s, st):
        i = st.i; moving = st.state in ('on', 'pulling')
        sh = (i % 2) if st.state == 'on' else ((i // 2) % 3 if st.state == 'pulling' else 0)
        bev(s, 2, 5, 5, 26, 'S', 'W', 'E'); bev(s, 25, 5, 5, 26, 'S', 'W', 'E')                    # posts
        plate(s, 2, 20, 5, 8, 'r', bolt=False); weld(s, 3, 18, 3)
        hazard(s, 25, 12, 5, 7); hazard(s, 2, 9, 5, 5)
        net(s, 7, 7, 18, 18, sh)
        junk(s, 18, 15 + (1 if st.state == 'pulling' and i % 2 else 0), 1); junk(s, 9, 18, 0)
        if st.state == 'pulling':                                                                    # bits slide down into the throat
            for k in range(2):
                yy = 9 + ((i * 3 + k * 8) % 15)
                s.rect(11 + k * 8, yy, 2, 2, 'u' if k == 0 else 'M'); s.put(11 + k * 8, yy, 'Q' if k == 0 else 'L')
        bev(s, 1, 1, 30, 5, 'S', 'W', 'E'); weld(s, 4, 3, 12); bolts(s, [(4, 2), (26, 2)])         # top brace
        s.hline(25, 0, 5, 'S'); s.put(29, 0, 'M'); s.put(30, 1, 'S')                                # bent rebar poking out
        bev(s, 7, 24, 18, 7, 'S', 'W', 'E'); s.rect(11, 26, 10, 2, 'K'); s.hline(11, 25, 10, 'u')   # throat plate and its slot
        weld(s, 8, 29, 16); s.put(8, 25, 'L'); s.put(23, 25, 'L')
        self.magnet(s, 12, 6, st)
    def magnet(self, s, x, y, st):
        """a horseshoe magnet hanging off the top brace: red body, steel pole tips."""
        s.stamp(x, y, art("""
.rrrrrr.
rrHrrrrr
rr....rr
rr....rr
rr....rr
SS....SS
LM....MW
"""))
        if st.state == 'pulling' and st.i % 2 == 0: s.put(x + 1, y + 5, 'h'); s.put(x + 6, y + 5, 'h')
    def hurt_out(self, s, st):
        for y in range(10, 22):                                                                      # the net is ripped open, strands hang
            for x in range(11, 21):
                if (x - 11) + (y - 10) * 0.6 < 9 and (x - 11) * 0.7 + (21 - y) > 6 and (x + y) % 5: s.erase(x, y)
        s.stamp(10, 20, art("S.S.\n.SS.\nS..S"));  wire(s, [(14, 12), (15, 15), (13, 18)], 'S', 'W')
        s.stamp(25, 2, art("..SSM\n.SSM.\nSM..."))                                                  # the right post is bent
        crack(s, [(26, 8), (27, 12), (26, 17)])
        for k in range(4): s.put(25 + k, 12 + (k % 2), 'a' if k % 2 else 'D')                       # the tape peels
        spark(s, 22, 9, False) if st.i == 0 else spark(s, 5, 15, False)
    def wreck_out(self, s, st):
        for y in range(8, 24):
            for x in range(8, 24):
                if (x * 5 + y * 3) % 7 < 5: s.erase(x, y)                                            # burnt to strands
        wire(s, [(9, 9), (12, 14), (10, 22)], 'S', 'W'); wire(s, [(22, 8), (19, 15), (21, 22)], 'S', 'W')
        scorched(s, st, crack_pts=[[(27, 7), (26, 12), (28, 18), (26, 24)]], dents=[(3, 12, 3, 5), (14, 25, 6, 3)], soots=[(9, 1, 0), (20, 2, 2), (3, 22, 2)],
                 wires_=[[(24, 24), (27, 27), (28, 30)]], sparks=[(16, 14), (5, 8)])
        s.erase(15, 8); s.erase(16, 8)

    # ---------------------------------------------------------------- hopper (inside)
    def inside(self, s, st):
        y = self.iy; i = st.i; pw = st.powered
        housing_w(s, y, 32, 'scrap')
        s.hline(3, y + 2, 26, 'S'); bolts(s, [(4, y + 3), (26, y + 3)])
        chamfer_fill(s, 5, y + 4, 22, 17, 'W', 4); rim(s, 'W', 'S', 'E', (5, y + 4, 26, y + 20))    # the round hopper bin
        chamfer_fill(s, 7, y + 6, 18, 13, 'D', 3); rim(s, 'D', 'E', 'M', (7, y + 6, 24, y + 18))
        bev(s, 11, y + 20, 10, 8, 'S', 'W', 'E'); s.rect(13, y + 21, 6, 6, 'K')                        # chute
        bev(s, 9, y + 27, 14, 3, 'M', 'S', 'W'); hazard(s, 10, y + 28, 12, 1)
        # dial gauge, bottom-left
        circle(s, 6.5, y + 25, 3.4, 'S'); circle(s, 6.5, y + 25, 2.7, 'L'); circle(s, 6.5, y + 25, 1.9, 'H')
        nx, ny = ((5, 26), (5, 25), (5, 24), (6, 24), (7, 24), (8, 24))[i % 6] if st.state == 'pulling' else (5, 26)
        s.put(6, y + 25, 'K'); s.put(nx, ny, 'r'); s.put((nx + 6) // 2, (ny + 25) // 2, 'r') if False else None
        s.rect(24, y + 21, 5, 6, 'u'); s.vline(24, y + 21, 6, 'Q'); weld(s, 25, y + 22, 4, True)         # a patch plate and a weld seam
        plate(s, 3, y + 29, 5, 1, 'b', bolt=False)
        lamp(s, 24, y + 28, 'a', pw and st.state != 'damaged')
        bits = []
        n = len(self.PATH)
        if st.state in ('on', 'pulling', 'damaged'):
            step = 2 if st.state != 'pulling' else 4
            for k in range(3):
                bits.append(self.PATH[(i * (step // 2) + k * 4) % n] if st.state != 'pulling' else self.PATH[(i * 2 + k * 4) % n])
        elif st.state == 'off': bits = [self.PATH[2], self.PATH[6], self.PATH[9]]
        junk_bits(s, bits, ['M', 'u', 'a'][:len(bits)])
    def hurt_in(self, s, st):
        y = self.iy
        dent(s, 12, y + 21, 7, 4); crack(s, [(8, y + 7), (10, y + 10), (9, y + 14)])
        s.put(24, y + 28, 'E'); s.put(25, y + 28, 'E')
        spark(s, 16, y + 24, False) if st.i == 0 else spark(s, 26, y + 17, False)
    def wreck_in(self, s, st):
        y = self.iy
        crack(s, [(8, y + 7), (10, y + 10), (9, y + 14), (11, y + 17)]); crack(s, [(21, y + 5), (23, y + 9)])
        junk(s, 14, y + 22, 1); junk(s, 17, y + 23, 3)                                                       # a chunk jammed in the chute
        wire(s, [(4, y + 20), (6, y + 22), (9, y + 24)])

    # ---------------------------------------------------------------- glow
    def glow(self, state, i, g, ox, oy):
        y = self.iy
        if state in ('on', 'pulling', 'damaged'): glow(g, ox + 25, oy + y + 29, 3, (255, 190, 60), 0.5, 2.0)
        if state == 'pulling' and i % 2 == 0: glow(g, ox + 6.5, oy + y + 25, 3.5, (255, 138, 30), 0.35, 2.0)
    def out_glow(self, state, i, g, ox, oy):
        if state == 'pulling':
            pull_glow(g, ox + 16, oy + 12, 30, i, 6, MINT, 0.5, 60, 3, 4.0)
            glow(g, ox + 16, oy + 12, 6, MINT, 0.18 + 0.10 * (i % 2), 2.0)


# ------------------------------------------------------------------ Salvage Intake Mk1-Mk3 (standard) 4x2 + 4x2
def coil_seg(s, x0, y0, x1, y1, w, endc=None, tones='QQqqn', gap=3):
    """a copper magnet coil along a line: windings across a cylinder (light on the up/left side), steel end caps, an optional lit lamp."""
    L = math.hypot(x1 - x0, y1 - y0); n = int(L)
    ax, ay = (x1 - x0) / L, (y1 - y0) / L; px_, py_ = -ay, ax
    if px_ + py_ < 0: px_, py_ = -px_, -py_
    rr = ramp_rows(w, tones)
    for t in range(n + 1):
        for k in range(w):
            o = k - (w - 1) / 2.0
            x, y = round(x0 + ax * t + px_ * o), round(y0 + ay * t + py_ * o)
            s.put(x, y, 'n' if t % gap == gap - 1 and 0 < t < n else rr[k])
    for t in (0, n):
        for k in range(-1, w + 1):
            o = k - (w - 1) / 2.0
            s.put(round(x0 + ax * t + px_ * o), round(y0 + ay * t + py_ * o), 'M' if k in (-1, w) else 'S')
    if endc:
        s.put(round(x0 + ax * 0.5 + px_ * 0), round(y0 + ay * 0.5), endc)

class Intake(Mount):
    line = 'standard'; cells = (4, 2); pivot = (32, 16)
    tier = 1
    glow_pad = (8, 8, 8, 8)
    out_anims = [('on', 'on', 2, 3), ('pulling', 'pulling', 6, 10), ('off', 'off', 1, 0), ('damaged', 'damaged', 2, 4), ('disabled', 'disabled', 2, 3)]
    anims = [('on', 'on', 6, 4), ('pulling', 'pulling', 6, 10), ('off', 'off', 1, 0), ('damaged', 'damaged', 2, 4), ('disabled', 'disabled', 1, 0)]
    GEO = {1: dict(tl=11, tr=52, rim=4, coils=1, reach=34, pad=30), 2: dict(tl=9, tr=54, rim=5, coils=2, reach=44, pad=40), 3: dict(tl=7, tr=56, rim=6, coils=3, reach=56, pad=48)}
    @property
    def out_glow_pad(self): return (8, self.GEO[self.tier]['pad'], 8, 8)
    TL, TR = 22, 41                                                         # throat edges at the bottom of the funnel
    def geo(self): return self.GEO[self.tier]
    # ---------------------------------------------------------------- mouth (outside)
    def cheeks(self):
        g = self.geo(); tl, tr, rim = g['tl'], g['tr'], g['rim']
        left = [(tl - rim, 2), (tl, 2), (self.TL, 27), (self.TL - rim, 29)]
        right = [(tr + 1, 2), (tr + 1 + rim, 2), (self.TR + 1 + rim, 29), (self.TR + 1, 27)]
        return left, right
    def outside(self, s, st):
        g = self.geo(); tl, tr, rim = g['tl'], g['tr'], g['rim']; i = st.i; pw = st.powered
        pulling = st.state == 'pulling'
        left, right = self.cheeks()
        TL, TR = self.TL, self.TR
        # shoulders: low armoured plates joining the funnel to the flange, so the mouth stays the tallest thing
        for sx in (0, 1):
            pts = [(1, 13), (tl - rim - 1, 9), (TL - rim, 30), (1, 30)] if sx == 0 else [(62, 13), (tr + rim + 2, 9), (TR + rim + 1, 30), (62, 30)]
            lit_poly(s, pts, 'W', 'S', 'E')
        if self.tier == 3:
            for y in (17, 22): s.hline(3, y, 9, 'E'); s.hline(52, y, 9, 'E')
            for (x, y) in ((3, 15), (60, 15)): s.put(x, y, 'L')
        # the funnel: a dark throat, converging guide ribs, baffles
        fillpoly(s, [(tl, 3), (tr + 1, 3), (TR + 1, 27), (TL, 27)], 'D')
        for yy in range(14, 27):
            for xx in range(tl, tr + 2):
                if s.get(xx, yy) == 'D': s.put(xx, yy, 'K' if yy >= 18 else 'E' if False else 'D')
        nrib = 5 if self.tier == 1 else 7
        for k in range(nrib):
            f = k / (nrib - 1.0)
            x0, x1 = tl + 2 + (tr - tl - 3) * f, TL + 2 + (TR - TL - 3) * f
            line(s, int(x0), 4, int(x1), 26, 'W')
            for yy in range(5, 26, 4): s.put(int(x0 + (x1 - x0) * (yy - 4) / 22.0), yy, 'S')
        for yy in (9, 15, 21):                                                                  # baffle bars
            xa = tl + (TL - tl) * (yy - 3) / 24.0; xb = tr + 1 + (TR - tr) * (yy - 3) / 24.0
            s.hline(int(xa) + 1, yy, int(xb - xa) - 1, 'S'); s.hline(int(xa) + 1, yy + 1, int(xb - xa) - 1, 'K')
        # the cheeks, then the copper coils wound on them
        lit_poly(s, left, 'S', 'M', 'W'); lit_poly(s, right, 'S', 'M', 'W')
        spans = {1: [(0.14, 0.86)], 2: [(0.06, 0.46), (0.54, 0.94)], 3: [(0.04, 0.34), (0.37, 0.65), (0.68, 0.96)]}[self.tier]
        w = rim; tones = 'YTun' if w == 4 else 'YTTun'
        for k, (t0, t1) in enumerate(spans):
            for sx in (0, 1):
                (p0, p1) = ((tl - rim / 2.0 + 0.5, 3), (TL - rim / 2.0 + 0.5, 28)) if sx == 0 else ((tr + rim / 2.0 + 0.5, 3), (TR + rim / 2.0 + 0.5, 28))
                a = (p0[0] + (p1[0] - p0[0]) * t0, p0[1] + (p1[1] - p0[1]) * t0); b_ = (p0[0] + (p1[0] - p0[0]) * t1, p0[1] + (p1[1] - p0[1]) * t1)
                coil_seg(s, int(a[0]), int(a[1]), int(b_[0]), int(b_[1]), w, tones=tones)
                lamp_c = ('h' if pulling else 'g') if (pw and ((k + sx + (i if st.state == 'on' else 0)) % 2 == 0 or pulling)) else 'E'
                lx, ly = int(a[0]) + (0 if sx == 0 else 1), int(a[1]) - 1
                s.put(lx, ly, lamp_c); s.put(lx + 1, ly, lamp_c)
        # overhead emitter bar bridging the mouth (Mk3)
        if self.tier == 3:
            bev(s, 12, 0, 40, 3, 'M', 'S', 'W', cham=False)
            for k, x in enumerate((17, 31, 45)):
                s.rect(x, 1, 3, 1, ('h' if pulling and (i + k) % 2 == 0 else 'g') if pw else 'E')
        # moving bits sucked down the ribs
        if pulling:
            for k in range(3):
                f = ((i / 6.0) + k / 3.0) % 1.0
                for lane, col in ((0.25, ('M', 'T', 'k')[k]), (0.75, ('i', 'u', 'M')[k])):
                    x0, x1 = tl + 2 + (tr - tl - 3) * lane, TL + 2 + (TR - TL - 3) * lane
                    bx, by = int(x0 + (x1 - x0) * f), int(5 + 20 * f)
                    s.rect(bx, by, 2, 2, col); s.put(bx, by, 'L' if col in 'MS' else 'H')
        # throat plate and its sensor
        bev(s, TL - 3, 26, TR - TL + 7, 5, 'M', 'S', 'W'); s.hline(TL + 1, 28, TR - TL - 2, 'D')
        for k in range(self.tier): s.put(32 - (self.tier - 1) + 2 * k, 27, 'L')                  # tier marks
        s.put(TL - 1, 28, 'g' if pw and (st.state != 'on' or i == 0) else 'E')
        s.put(TR + 3, 28, 'g' if pw and (st.state != 'on' or i == 1) else 'E')
        bolts(s, [(8, 26), (54, 26)])
    # ---------------------------------------------------------------- damage (outside)
    def hurt_out(self, s, st):
        g = self.geo(); tl, tr, rim = g['tl'], g['tr'], g['rim']
        crack(s, [(tl - 1, 5), (tl + 3, 12), (tl + 5, 17), (self.TL + 1, 24)])                    # left cheek cracked through
        for (x, y) in ((tr + 3, 8), (tr + 4, 9), (tr + 5, 10)): s.erase(x, y)
        wire(s, [(tr + 2, 11), (tr + 5, 15), (tr + 3, 20), (tr + 6, 24)])                       # a coil's wire pulled loose, hanging
        s.stamp(tr + 5, 15, art("QQq\nqnn"))
        s.stamp(tl - rim - 1, 3, art("..SSM\n.SSMM\nSMM.."))
        dent(s, 6, 20, 6, 4); s.put(self.TL - 1, 28, 'r'); s.put(self.TR + 3, 28, 'E')
        spark(s, tl + 3, 10, False) if st.i == 0 else spark(s, tr - 4, 20, False)
    def wreck_out(self, s, st):
        g = self.geo(); tl, tr = g['tl'], g['tr']
        scorched(s, st, crack_pts=[[(tl - 1, 5), (tl + 3, 12), (tl + 5, 17), (self.TL + 1, 25)], [(tr + 4, 6), (tr + 2, 13), (tr + 5, 20)]],
                 dents=[(4, 18, 6, 4), (54, 18, 5, 5), (28, 26, 8, 3)], soots=[(18, 3, 0), (36, 4, 1), (4, 9, 2), (50, 20, 2)],
                 wires_=[[(tr + 2, 11), (tr + 5, 16), (tr + 2, 22)], [(tl - 3, 10), (tl - 5, 15)]], sparks=[(32, 12), (tr, 22)])
        for (x, y, w_, h_) in ((20, 6, 6, 2),): s.rect(x, y, w_, h_, 'K')

    # ---------------------------------------------------------------- hopper (inside)
    def inside(self, s, st):
        y = self.iy; i = st.i; pw = st.powered; pulling = st.state == 'pulling'
        housing_w(s, y, 64, 'standard')
        coupling(s, 3, y + 8, st)
        # the glass-fronted sorting hopper: a funnel with two lanes into the belt
        bev(s, 16, y + 3, 28, 19, 'M', 'S', 'W')
        recess(s, 18, y + 5, 24, 15, 'K', 'K'); s.rect(19, y + 6, 22, 13, 'K')
        for (xa, xb) in ((19, 28), (40, 31)):
            line(s, xa, y + 6, xb, y + 14, 'E')
        s.hline(27, y + 15, 7, 'W'); s.hline(27, y + 16, 7, 'E')                                 # outlet lip
        belt_y = y + 17
        s.rect(19, belt_y, 22, 2, 'E'); s.hline(19, belt_y, 22, 'W')
        for x in range(19 + (i * 2 if st.state in ('on', 'pulling') else 0) % 4, 41, 4): s.put(x, belt_y + 1, 'S')   # belt ticks crawl
        nb = 2 if st.state == 'on' else (5 if pulling else 0)
        if st.state == 'off': nb = 0
        for k in range(nb):
            lane = k % 2; f = ((i / 6.0) + k / float(max(nb, 1))) % 1.0
            x0, x1 = (21, 29) if lane == 0 else (38, 31)
            bx, by = int(x0 + (x1 - x0) * f), int(y + 6 + 8 * f)
            col = ('M', 'T', 'i', 'k', 'u')[k % 5]
            s.rect(bx, by, 2, 2, col); s.put(bx, by, 'L' if col in 'MS' else 'H')
        # sorter panel: output chutes with lamps
        bev(s, 47, y + 3, 14, 19, 'M', 'S', 'W')
        for k in range(3):
            s.rect(49 + k * 4, y + 6, 3, 9, 'D'); s.hline(49 + k * 4, y + 6, 3, 'K')
            c = ('a', 'c', 'g')[k]
            s.rect(49 + k * 4, y + 17, 3, 2, c if pw else 'E'); s.put(49 + k * 4, y + 17, 'H') if pw else None
            if pulling:
                yy = y + 7 + ((i * 2 + k * 3) % 8)
                s.put(50 + k * 4, yy, ('T', 'M', 'k')[k])
        # tier machinery
        if self.tier >= 2:
            s.rect(19, y + 23, 22, 6, 'D'); s.hline(19, y + 23, 22, 'K')                       # a second, narrower belt and a cargo counter
            for x in range(20 + (i * 2 if pulling else 0) % 4, 41, 4): s.put(x, y + 25, 'S')
            for k in range(4):
                s.rect(44 + k * 3, y + 24, 2, 4, 'D'); s.put(44 + k * 3, y + 24 + (3 - (k + (i if pulling else 0)) % 4), 'g' if pw else 'E')
        if self.tier == 3:
            coil_v(s, 56, y + 23, 5, 8, pw, ('h', 'c', 'E'))                                    # the field stabiliser
            s.put(57, y + 22, 'L')
        # flow bar
        for k in range(5):
            on = pw and (st.state == 'pulling' and (k + i) % 5 < 3 or st.state == 'on' and k == (i // 2) % 5)
            s.rect(4 + k * 3, y + 24, 2, 2, ('g' if on else 'E'))
        s.hline(4, y + 29, 2, 'W'); s.hline(7, y + 29, 3, 'W')
    def hurt_in(self, s, st):
        y = self.iy
        crack(s, [(22, y + 4), (25, y + 8), (24, y + 13)])                                       # the glass is cracked
        dent(s, 48, y + 4, 5, 3); s.rect(53, y + 17, 3, 2, 'E'); s.put(50, y + 18, 'r')
        spark(s, 38, y + 10, False) if st.i == 0 else spark(s, 54, y + 12, False)
        s.rect(5, y + 24, 3, 2, 'E'); s.rect(8, y + 24, 3, 2, 'E')
    def wreck_in(self, s, st):
        y = self.iy
        crack(s, [(22, y + 4), (25, y + 8), (24, y + 13), (27, y + 16)]); crack(s, [(48, y + 5), (51, y + 10), (50, y + 15)])
        s.rect(30, y + 11, 3, 3, 'M'); s.rect(34, y + 12, 3, 2, 'u')                                  # cargo jammed in the outlet
        wire(s, [(14, y + 20), (17, y + 24), (22, y + 25)])

    # ---------------------------------------------------------------- glow
    def glow(self, state, i, g, ox, oy):
        y = self.iy
        if state in ('on', 'pulling', 'damaged'):
            for k in range(5):
                on = (state == 'pulling' and (k + i) % 5 < 3) or (state == 'on' and k == (i // 2) % 5) or state == 'damaged' and k > 2
                if on: glow(g, ox + 5 + k * 3, oy + y + 25, 3, (107, 211, 74), 0.5, 2.0)
            for k, c in enumerate(((255, 190, 60), (60, 242, 255), (107, 211, 74))):
                glow(g, ox + 50.5 + k * 4, oy + y + 18, 3, c, 0.4, 2.0)
            if state == 'pulling':
                for k in range(3): glow(g, ox + 21 + (i * 4 + k * 9) % 18, oy + y + 12, 4, MINT, 0.22, 2.0)
            if self.tier == 3: glow(g, ox + 58, oy + y + 27, 6, MINT if state == 'pulling' else (60, 242, 255), 0.35, 2.0)
    def out_glow(self, state, i, g, ox, oy):
        gg = self.geo(); tl, tr = gg['tl'], gg['tr']
        if state in ('on', 'pulling', 'damaged'):
            for sx, x in ((0, tl - gg['rim'] + 3), (1, tr + gg['rim'] - 1)):
                glow(g, ox + x + 0.5, oy + 8, 3, MINT if state == 'pulling' else (107, 211, 74), 0.5 if state == 'pulling' else 0.35, 2.0)
        if state == 'pulling':
            pull_glow(g, ox + 32, oy + 16, gg['reach'], i, 6, MINT, 0.55, 40, 3, 5.0)
            glow(g, ox + 32, oy + 15, 8, MINT, 0.14 + 0.08 * (i % 2), 2.0, sx=2.0)

class IntakeMk1(Intake):
    id = 'intake_mk1'; tier = 1
    out_notes = ('OUTSIDE half of the Salvage Intake Mk1 (standard, 4x2): a steel funnel mouth with guide ribs, one copper magnet coil on each cheek, a sensor throat plate. Pull radius 2 cells. '
                 'pulling: the coil lamps go mint, bits slide down the ribs and mint wavefronts close on the mouth (glow layer). damaged: a cheek cracked, a coil wire hanging; disabled: scorched, dented, sparking.')
    notes = ('INSIDE half of the Salvage Intake Mk1 (standard, 4x2): a glass-fronted sorting hopper with a belt, a sorter panel with three chutes (amber, cyan, green lamps) and a flow bar. '
             'on: bits drift to the belt (6 frames); pulling: busy, five bits, the flow bar chases. damaged: glass cracked, chute lamps dead, bar half dead; disabled: cargo jammed in the outlet.')
class IntakeMk2(Intake):
    id = 'intake_mk2'; tier = 2
    out_notes = ('OUTSIDE half of the Salvage Intake Mk2 (standard, 4x2): a wider mouth with thicker, double-lit rims, two copper coils on each cheek and seven guide ribs. Pull radius 3 cells. States as Mk1.')
    notes = ('INSIDE half of the Salvage Intake Mk2 (standard, 4x2): the Mk1 hopper plus a second belt and a cargo counter. States as Mk1.')
class IntakeMk3(Intake):
    id = 'intake_mk3'; tier = 3
    out_notes = ('OUTSIDE half of the Salvage Intake Mk3 (standard, 4x2): the widest mouth, heavy rims with armour chevrons, three fat coils on each cheek and an overhead emitter bar with three mint nodes. Pull radius 4 cells. States as Mk1.')
    notes = ('INSIDE half of the Salvage Intake Mk3 (standard, 4x2): the Mk2 hopper plus a field stabiliser coil with a mint core. States as Mk1.')

# ------------------------------------------------------------------ Lumen Siphon (neon) 4x2 + 4x2: a crystal funnel with a cyan vortex
SPIKE = art("""
..0..
..0..
.010.
.011.
.0112
01122
01122
""")
def spike(s, x, y, on=True, scale=1):
    """a crystal spike (5x7) standing on (x, y) bottom-centre."""
    tones = ('c', 'C', 'B') if on else ('M', 'S', 'W')
    for j, r in enumerate(SPIKE):
        for i, ch in enumerate(r):
            if ch != '.': s.put(x - 2 + i, y - 6 + j, tones[int(ch)])

class LumenSiphon(Mount):
    id = 'lumen_siphon_neon'; line = 'neon'; cells = (4, 2); pivot = (32, 16)
    glow_pad = (8, 8, 8, 8)
    out_glow_pad = (8, 48, 8, 10)
    out_anims = [('on', 'on', 2, 3), ('pulling', 'pulling', 6, 10), ('off', 'off', 1, 0), ('damaged', 'damaged', 2, 4), ('disabled', 'disabled', 2, 3)]
    anims = [('on', 'on', 6, 4), ('pulling', 'pulling', 6, 10), ('off', 'off', 1, 0), ('damaged', 'damaged', 2, 4), ('disabled', 'disabled', 1, 0)]
    out_notes = ('OUTSIDE half of the Lumen Siphon (neon, 4x2): a funnel of navy panels crowned with crystal spikes, a cyan vortex of dashed rings spiralling into a faceted crystal core at the throat. Pull radius 6 cells, small debris only. '
                 'pulling: the vortex turns and the core flares, with a wide cyan glow and shimmer arcs (glow layer). damaged: a spike snapped and hanging, the collar cracked, the vortex stuttering; disabled: scorched, dull, dented, sparking.')
    notes = ('INSIDE half of the Lumen Siphon (neon, 4x2): a crystal chamber, a cyan-lit glass column with motes orbiting inside it (6 frames), side lamps and a flow bar. pulling: more motes, magenta flickers. '
             'damaged: the column cracked, motes jittering; disabled: dark column, a crystal chunk jammed.')
    TL, TR = 20, 43
    def outside(self, s, st):
        i = st.i; pw = st.powered; pulling = st.state == 'pulling'
        tl, tr = 9, 54
        for sx in (0, 1):
            pts = [(1, 14), (tl - 5, 11), (self.TL - 5, 30), (1, 30)] if sx == 0 else [(62, 14), (tr + 6, 11), (self.TR + 6, 30), (62, 30)]
            lit_poly(s, pts, 'I', 'J', 'N'); 
        fillpoly(s, [(tl, 4), (tr + 1, 4), (self.TR + 1, 27), (self.TL, 27)], 'N')
        # the vortex: stacked rings narrowing to the throat; dashes crawl round them
        if pw:
            phase = (i / 6.0) if pulling else (i * 0.5 / 2.0 if st.state == 'on' else 0.0)
            for k in range(10):
                cy_, rx, ry = 25.5 - 2.3 * k, 3.5 + 2.4 * k, 1.2 + 0.5 * k
                tone = ('H', 'c', 'c', 'c', 'C', 'C', 'C', 'B', 'B', 'B')[k]
                for t in range(0, 360, 3):
                    a = math.radians(t)
                    f = ((t / 360.0) * 6 + k * 0.45 + phase) % 1.0
                    if f > 0.55: continue
                    x, y = int(32 + rx * math.cos(a)), int(cy_ + ry * math.sin(a))
                    front = math.sin(a) > 0
                    if s.get(x, y) == 'N': s.put(x, y, tone if front else {'H': 'c', 'c': 'C', 'C': 'B', 'B': 'I'}[tone])
        # cheeks: navy strips with a cyan edge, crowned with crystal spikes
        left = [(tl - 4, 3), (tl, 3), (self.TL, 27), (self.TL - 4, 29)]; right = [(tr + 1, 3), (tr + 5, 3), (self.TR + 5, 29), (self.TR + 1, 27)]
        lit_poly(s, left, 'J', 'j', 'I'); lit_poly(s, right, 'J', 'j', 'I')
        thick(s, tl, 3, self.TL, 27, 1, 'c' if pw else 'W'); thick(s, tr + 1, 3, self.TR + 1, 27, 1, 'c' if pw else 'W')
        for k, t in enumerate((0.0, 0.22, 0.44, 0.66)):
            for sx in (0, 1):
                x = (tl - 2 + (self.TL - 2 - tl + 2) * t) if sx == 0 else (tr + 3 + (self.TR + 3 - tr - 3) * t)
                y = 3 + 24 * t
                if sx == 0: x -= 3
                else: x += 3
                spike(s, int(x), int(y) + 2, pw, 1)
        # throat collar with the faceted crystal core
        navy_panel(s, self.TL - 2, 26, self.TR - self.TL + 5, 5); s.hline(self.TL, 27, self.TR - self.TL + 1, 'c' if pw else 'W')
        core = ('H', 'c', 'C') if pw and (pulling or i == 0) else (('c', 'C', 'B') if pw else ('M', 'S', 'W'))
        crystal(s, 29, 21, """
..0..
.001.
.0012
01122
.012.
..2..
""", core)
        s.put(3, 26, 'c' if pw else 'E'); s.put(60, 26, 'm' if pw else 'E')
    def hurt_out(self, s, st):
        for (x, y) in ((17, 2), (17, 3), (18, 3)): s.erase(x, y)
        s.stamp(14, 1, art("c.\nBc\n.B"))
        crack(s, [(25, 24), (28, 26), (27, 30)], 'K', 'c'); crack(s, [(14, 14), (16, 19), (14, 24)])
        wire(s, [(46, 8), (48, 12), (46, 16)], 'm', 'P')
        spark(s, 38, 14, False) if st.i == 0 else spark(s, 24, 18, False)
        s.put(60, 26, 'E')
    def wreck_out(self, s, st):
        scorched(s, st, crack_pts=[[(25, 24), (28, 26), (27, 30)], [(14, 14), (16, 19), (14, 24), (17, 28)]], dents=[(4, 18, 6, 4), (52, 20, 6, 4)],
                 soots=[(16, 5, 0), (38, 6, 1), (3, 9, 2)], wires_=[[(46, 8), (48, 12), (46, 18)]], sparks=[(32, 12), (26, 20)])
    def inside(self, s, st):
        y = self.iy; i = st.i; pw = st.powered; pulling = st.state == 'pulling'
        housing_w(s, y, 64, 'neon')
        coupling(s, 3, y + 8, st, 'c')
        navy_panel(s, 16, y + 3, 32, 20)                                                         # the crystal chamber
        recess(s, 20, y + 5, 24, 16, 'N', 'K'); s.rect(21, y + 6, 22, 14, 'N')
        for xx in (21, 42): s.vline(xx, y + 6, 14, 'c' if pw else 'W')
        nm = 3 if st.state == 'on' else (7 if pulling else (3 if st.state == 'damaged' else 0))
        for k in range(nm):
            a = 2 * math.pi * ((k / float(nm)) + (i / 6.0) * (1 if pulling else 0.5))
            rx, ry = 8 + (k % 3) * 2, 3.5 + (k % 2) * 1.5
            x, yy = int(32 + rx * math.cos(a)), int(y + 13 + ry * math.sin(a))
            c = ('H' if k % 3 == 0 else 'c', 'm' if (pulling and k % 2) else 'C')[k % 2]
            s.put(x, yy, c); s.put(x + 1, yy, 'C' if c != 'm' else 'P')
        if pw: crystal(s, 30, y + 9, """
..0..
.001.
0011.
.012.
..2..
""", ('c', 'C', 'B'))
        for k in range(4): s.rect(51, y + 5 + k * 4, 9, 2, 'c' if pw and (k + i) % 4 < 2 and pulling or pw and k == 1 else 'W'); s.hline(51, y + 7 + k * 4, 9, 'N') if False else None
        bev(s, 4, y + 24, 28, 4, 'j', 'J', 'I', cham=False)
        for k in range(6):
            on = pw and (pulling and (k + i) % 6 < 3 or st.state == 'on' and k == (i // 1) % 6)
            s.rect(6 + k * 4, y + 25, 3, 2, 'c' if on else 'N')
        s.hline(36, y + 27, 20, 'N'); s.put(57, y + 27, 'm' if pw else 'E')
    def hurt_in(self, s, st):
        y = self.iy
        crack(s, [(24, y + 5), (28, y + 11), (26, y + 17)], 'K', 'c'); s.rect(51, y + 9, 9, 2, 'E'); s.rect(51, y + 17, 9, 2, 'E')
        spark(s, 38, y + 10, False) if st.i == 0 else spark(s, 55, y + 15, False)
        s.rect(8, y + 25, 3, 2, 'E'); s.rect(12, y + 25, 3, 2, 'E')
    def wreck_in(self, s, st):
        y = self.iy
        crack(s, [(24, y + 5), (28, y + 11), (26, y + 17), (29, y + 20)], 'K', 'M'); crack(s, [(40, y + 6), (38, y + 12)], 'K', 'M')
        s.stamp(33, y + 16, art("SS.\nMSW\n.WW"))
        wire(s, [(14, y + 20), (17, y + 24), (22, y + 26)], 'm', 'P')
    def glow(self, state, i, g, ox, oy):
        y = self.iy
        pulling = state == 'pulling'
        if state in ('on', 'pulling', 'damaged'):
            glow(g, ox + 32, oy + y + 13, 13, (60, 242, 255), (0.30 if pulling else 0.20), 2.0, sx=1.5)
            if pulling:
                for k in range(4): glow(g, ox + 32 + 9 * math.cos(2 * math.pi * (k / 4.0 + i / 6.0)), oy + y + 13 + 4 * math.sin(2 * math.pi * (k / 4.0 + i / 6.0)), 3, (255, 79, 216), 0.35, 2.0)
            for k in range(4):
                if k == 1 or pulling and (k + i) % 4 < 2: glow(g, ox + 55.5, oy + y + 6 + k * 4, 4, (60, 242, 255), 0.4, 2.0, sx=1.8)
            for k in range(6):
                if pulling and (k + i) % 6 < 3 or state == 'on' and k == i % 6: glow(g, ox + 7.5 + k * 4, oy + y + 26, 3, (60, 242, 255), 0.45, 2.0)
    def out_glow(self, state, i, g, ox, oy):
        if state in ('on', 'pulling', 'damaged'):
            pulling = state == 'pulling'
            glow(g, ox + 32, oy + 16, 22, (60, 242, 255), (0.34 + 0.06 * (i % 2)) if pulling else 0.18, 2.0, sx=1.8)
            glow(g, ox + 32, oy + 24, 6, (255, 255, 255), 0.5 if pulling else 0.28, 2.0)
            if pulling:
                pull_glow(g, ox + 32, oy + 14, 62, i, 6, (60, 242, 255), 0.5, 36, 4, 6.0)
                for k in range(3): glow(g, ox + 32 + 12 * math.cos(2 * math.pi * (k / 3.0 + i / 6.0)), oy + 14 + 5 * math.sin(2 * math.pi * (k / 3.0 + i / 6.0)), 3, (255, 79, 216), 0.35, 2.0)

ALL = [NetMouth, IntakeMk1, IntakeMk2, IntakeMk3, LumenSiphon]
