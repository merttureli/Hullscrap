"""Workshop (violet family accents): fabricator (amber), robot arm, laser cutter, assembly rig, nanoforge, medbay."""
import math
from lines_kit import *
from comp_new import pipe_h, pipe_v
from compose import rotate

def violet_lamp(s, x, y, on, c='V'):
    s.rect(x - 1, y - 1, 4, 4, 'D'); s.rect(x, y, 2, 2, c if on else 'W')
    if on: s.put(x, y, 'X')

# ============================================================ FABRICATOR 4x2 (amber)
class Fabricator(LComp):
    id = 'fabricator'; cells = (4, 2)
    glow_pad = (8, 8, 8, 8)
    anims = [('on', 'on', 4, 6), ('off', 'off', 1, 0), ('damaged', 'damaged', 2, 6), ('disabled', 'disabled', 1, 0)]
    notes = ('Workshop, amber: a print bed with a gantry beam; the print head slides along it and the beam walks across as a part builds up under it (hot newest layer). A violet filament spool on the left, amber lamps and a violet lamp on the right. '
             'Damaged: the bed is cracked, the beam is bent and the head hangs off at an angle spitting sparks. Disabled: the head has fallen onto the bed, the beam is snapped, the part has collapsed to rubble.')
    DMG = (1, 3)
    W = [4, 10, 16, 22]
    HY = [8, 14, 10, 15]
    def interior(self, state, i):
        on = state == 'on'
        s = Spr(64, 32)
        bev(s, 1, 1, 62, 30, 'M', 'S', 'W')
        s.hline(15, 2, 34, 'Z'); s.hline(15, 3, 34, 'V') if False else None
        # filament spool (violet)
        bev(s, 3, 4, 10, 24, 'W', 'E', 'D'); s.rect(5, 6, 6, 20, 'V'); s.vline(5, 6, 20, 'X'); s.vline(10, 6, 20, 'Z')
        s.hline(4, 6, 8, 'S'); s.hline(4, 25, 8, 'S'); s.hline(5, 12, 6, 'Z'); s.hline(5, 19, 6, 'Z'); s.put(6, 9, 'X')
        # the bed
        recess(s, 15, 4, 34, 24, 'D', 'K')
        for x in range(18, 48, 4): s.vline(x, 5, 22, 'E')
        for y in range(8, 26, 4): s.hline(16, y, 32, 'E')
        w = self.W[i % 4] if on else 22
        if on or state == 'off':
            s.rect(17, 18, w, 6, 'S'); s.hline(17, 18, w, 'M'); s.hline(17, 23, w, 'W')
            if on: s.vline(17 + w - 1, 18, 6, 'a'); s.put(17 + w - 1, 18, 'y')
            for x in range(19, 17 + w - 1, 5): s.put(x, 20, 'E')
        bx = 17 + w
        s.rect(bx, 3, 2, 25, 'E'); s.vline(bx, 3, 25, 'S')
        s.rect(bx - 2, 2, 6, 3, 'W'); s.rect(bx - 2, 27, 6, 2, 'W')
        hy = self.HY[i % 4] if on else 8
        s.rect(bx - 2, hy, 6, 5, 'a' if on else 'W'); s.hline(bx - 2, hy, 6, 'y' if on else 'S'); s.vline(bx + 3, hy, 5, 'u' if on else 'E')
        s.put(bx, hy + 5, 'o' if on else 'E'); s.put(bx + 1, hy + 5, 'y' if on else 'E')
        s.put(bx, hy + 1, 'V'); s.put(bx + 1, hy + 1, 'X')
        # right panel: lamps
        bev(s, 51, 4, 11, 24, 'W', 'E', 'D')
        for k, (c, y) in enumerate((('a', 7), ('a', 12), ('o', 17))): s.rect(55, y, 3, 2, c if on and (k + i) % 3 != 2 else 'W')
        violet_lamp(s, 55, 22, on)
        s.hline(53, 5, 7, 'Z'); s.put(53, 5, 'V')
        for (x, y) in ((3, 2), (60, 2), (3, 29), (60, 29)): s.put(x, y, 'L')
        stencil(s, 17, 29, 'L', 2)
        return s
    def hurt(self, s, i):
        crack(s, [(18, 6), (24, 12), (22, 17), (30, 23)], 'M'); crack(s, [(40, 8), (43, 14), (41, 20)], 'M')
        bx = 17 + self.W[self.DMG[i] % 4]
        s.rect(bx - 2, 2, 8, 28, '.') if False else None
        shift_rect(s, bx - 2, bx + 5, 2, 30, 0, 0)
        s.stamp(bx - 6, 20, art("KKKKK.\nKaaaaK\nKyoooK\n.KKKKK")); s.put(bx - 5 + 2 * i, 24, 'y'); s.put(bx - 3, 25 - i, 'H')
        stamp_on(s, 38, 20, SCORCH_S)
        for (x, y) in ((55, 7), (55, 12)): s.rect(x, y, 3, 2, 'r' if i else 'W')
    def wreck(self, s):
        s.stamp(30, 14, art("KKKKKKKK.\nKaaaaaaK.\nKaKaKaaKK\nKKKKKKKK.")); crack(s, [(26, 3), (28, 9), (25, 16), (27, 27)], 'M')
        s.stamp(17, 18, art("K.KK.K.K\nKSKMSKSK\nKWSKSWKS\n.KKSKKK.")); s.stamp(40, 22, art("KK.\nKSK"))
        crack(s, [(15, 8), (22, 12), (20, 20)], 'M'); crack(s, [(44, 6), (46, 12), (42, 18), (47, 25)], 'M')
        s.hline(7, 22, 3, 'Z'); s.vline(10, 22, 6, 'Z'); stamp_on(s, 20, 8, SCORCH_L); stamp_on(s, 52, 20, SCORCH_S)
    def glow(self, state, i, g, ox, oy, flick=None):
        k = 1.0 if flick is None else (0.7 if flick else 0.5)
        bx = 17 + self.W[i % 4]; hy = self.HY[i % 4]
        glow(g, ox + bx + .5, oy + hy + 5, 8, ORANGE, 0.55 * k, 1.8)
        glow(g, ox + bx + 1, oy + hy + 3, 12, AMBER, 0.22 * k, 2.0)
        for y in (7.5, 12.5): glow(g, ox + 56, oy + y + 1, 3.5, AMBER, 0.45 * k, 2.0)
        glow(g, ox + 56, oy + 23, 3.5, VIOLET, 0.5 * k, 2.0)

# ============================================================ ROBOT ARM 2x2
class RobotArm(LComp):
    id = 'robot_arm'; cells = (2, 2)
    glow_pad = (6, 6, 6, 6)
    anims = [('on', 'on', 4, 6), ('off', 'off', 1, 0), ('damaged', 'damaged', 2, 5), ('disabled', 'disabled', 1, 0)]
    notes = ('Workshop: a two-segment articulated arm on a round base with violet joint caps and a band on each segment; the on loop swings the shoulder and elbow through a pick-and-place sweep with a violet part in the claw. '
             'Damaged: the forearm droops, the elbow sparks, a segment is cracked. Disabled: the arm lies limp across the pad with the claw detached.')
    DMG = (1, 3)
    TH1 = [10, 40, 70, 40]; TH2 = [70, 100, 130, 100]
    SH = (8, 23)
    def pose(self, th1, th2):
        sx, sy = self.SH
        e = (sx + 11 * math.sin(math.radians(th1)), sy - 11 * math.cos(math.radians(th1)))
        w = (e[0] + 10 * math.sin(math.radians(th2)), e[1] - 10 * math.cos(math.radians(th2)))
        return e, w
    def draw_arm(self, s, e, w, on, dead=False):
        sx, sy = self.SH
        ex, ey = int(round(e[0])), int(round(e[1])); wx, wy = int(round(w[0])), int(round(w[1]))
        thick(s, sx, sy, ex, ey, 4, 'S', 'M', 'W'); thick(s, ex, ey, wx, wy, 3, 'S', 'M', 'W')
        mx, my = (sx + ex) // 2, (sy + ey) // 2
        s.rect(mx - 1, my - 1, 3, 3, 'V' if on else 'W'); s.put(mx - 1, my - 1, 'X' if on else 'S')
        circle(s, ex + .5, ey + .5, 3.4, 'K'); circle(s, ex + .5, ey + .5, 2.6, 'E'); circle(s, ex + .5, ey + .5, 1.4, 'V' if on else 'W'); s.put(ex, ey, 'X' if on else 'S')
        circle(s, wx + .5, wy + .5, 2.4, 'K'); circle(s, wx + .5, wy + .5, 1.6, 'S')
        ang = math.atan2(wx - ex, -(wy - ey))
        for sgn in (-1, 1):                                       # two claw prongs
            px = wx + 3 * math.sin(ang + sgn * 0.5); py = wy - 3 * math.cos(ang + sgn * 0.5)
            line(s, wx, wy, int(round(px)), int(round(py)), 'L' if sgn < 0 else 'W')
        cx2, cy2 = int(round(wx + 4 * math.sin(ang))), int(round(wy - 4 * math.cos(ang)))
        s.rect(cx2 - 1, cy2 - 1, 3, 3, 'V' if not dead else 'Z'); s.put(cx2 - 1, cy2 - 1, 'X' if not dead else 'V')
    def interior(self, state, i):
        on = state == 'on'
        s = Spr(32, 32)
        bev(s, 1, 1, 30, 30, 'M', 'S', 'W')
        for (x, y) in ((3, 3), (27, 3), (3, 27), (27, 27)): bolt(s, x, y) if False else s.put(x, y, 'L')
        recess(s, 20, 3, 9, 8, 'D', 'K')                          # the part tray the arm feeds from
        s.rect(22, 5, 5, 4, 'Z' if on else 'W'); s.put(22, 5, 'V' if on else 'S')
        circle(s, 8.5, 23.5, 6.4, 'K'); circle(s, 8.5, 23.5, 5.6, 'E'); ring(s, 8.5, 23.5, 4.2, 5.4, 'V' if on else 'W')
        th1, th2 = (self.TH1[i % 4], self.TH2[i % 4]) if on else (25, 85)
        e, w = self.pose(th1, th2)
        self.draw_arm(s, e, w, on)
        circle(s, 8.5, 23.5, 3.4, 'S'); circle(s, 8, 23, 1.6, 'L')
        s.put(26, 27, 'g' if on else 'W'); s.put(27, 27, 'g' if on else 'W'); s.put(24, 27, 'V' if on else 'W')
        return s
    def hurt(self, s, i):
        s.rect(1, 1, 30, 30, '.') if False else None
        for y in range(2, 30):
            for x in range(10, 31):
                if s.get(x, y) in ('S', 'M', 'L', 'V', 'X', 'E') and (x - 8) ** 2 + (y - 23) ** 2 > 36: pass
        e, w = self.pose(40, 160 + 10 * i)
        # redraw the drooping forearm over the pad
        s.rect(10, 7, 20, 16, 'S') if False else None
        crack(s, [(14, 15), (16, 17), (15, 19)], 'K'); s.stamp(15, 12, art("DD.\nKKD\n.KK"))
        s.put(15 + i, 13, 'y'); s.put(16, 14 - i, 'H' if i else 'y'); s.put(14, 16 + i, 'y')
        stamp_on(s, 22, 18, SCORCH_S)
    def wreck(self, s):
        for y in range(1, 31):
            for x in range(9, 31):
                if s.get(x, y) != '.' and s.get(x, y) in 'SMLVXE' and (x - 8) ** 2 + (y - 23) ** 2 > 30 and y < 24: s.put(x, y, 'S')
        s.stamp(10, 20, art("KKKKKKKKKK\nKSMMSSSSWK\nKWSSSEEEEK\n.KKKKKKKK.")); s.stamp(22, 24, art("KKK.\nKVXK\nKZVK\n.KKK")); s.stamp(21, 10, art("K.K\nKDK"))
        crack(s, [(3, 5), (7, 9), (6, 13)], 'M'); stamp_on(s, 16, 8, SCORCH_L); s.put(24, 27, 'E')
    def glow(self, state, i, g, ox, oy, flick=None):
        k = 1.0 if flick is None else (0.7 if flick else 0.4)
        e, w = self.pose(self.TH1[i % 4], self.TH2[i % 4])
        glow(g, ox + e[0] + .5, oy + e[1] + .5, 5, VIOLET, 0.5 * k, 2.0); glow(g, ox + 8.5, oy + 23.5, 8, VIOLET, 0.22 * k, 2.0)
        glow(g, ox + 24.5, oy + 7, 5, VIOLET, 0.3 * k, 2.0)

# ============================================================ LASER CUTTER 2x4
class LaserCutter(LComp):
    id = 'laser_cutter'; cells = (2, 4)
    glow_pad = (6, 6, 6, 6)
    anims = [('on', 'on', 4, 8), ('off', 'off', 1, 0), ('damaged', 'damaged', 2, 6), ('disabled', 'disabled', 1, 0)]
    notes = ('Workshop: a gantry bridge on two rails over a metal sheet; the carriage carries a red cutting point (white core, sparks) and the bridge creeps down the sheet leaving a dark kerf behind. Violet rail caps and lamps. '
             'Damaged: the bridge is skewed on its rails, the lens is cracked and the beam stutters, the sheet is scorched. Disabled: the bridge has dropped off one rail, the lens is gone, the kerf is an open burn.')
    DMG = (1, 3)
    GY = [14, 24, 34, 44]
    def interior(self, state, i):
        on = state == 'on'
        s = Spr(32, 64)
        bev(s, 1, 1, 30, 62, 'M', 'S', 'W')
        for x in (3, 26):                                          # rails
            s.rect(x, 4, 3, 56, 'E'); s.vline(x, 4, 56, 'S'); s.vline(x + 2, 4, 56, 'D')
            for y in range(7, 58, 6): s.put(x + 1, y, 'L')
        for y in (4, 57): s.rect(3, y, 3, 3, 'V' if on else 'W'); s.rect(26, y, 3, 3, 'V' if on else 'W')
        recess(s, 8, 5, 16, 54, 'D', 'K')
        s.rect(10, 7, 12, 50, 'M'); s.hline(10, 7, 12, 'L'); s.vline(10, 7, 50, 'L'); s.hline(10, 56, 12, 'S'); s.vline(21, 7, 50, 'S')
        bolts(s, [(10, 8), (19, 8), (10, 53), (19, 53)])
        gy = self.GY[i % 4] if on else 8
        if on: s.vline(14, 14, gy - 14 + 1, 'K'); s.vline(15, 14, gy - 14 + 1, 'D')           # the kerf so far
        elif state == 'off': s.vline(14, 14, 31, 'K'); s.vline(15, 14, 31, 'D')
        # bridge + carriage
        s.rect(3, gy - 2, 26, 5, 'E'); s.hline(3, gy - 2, 26, 'S'); s.hline(3, gy + 2, 26, 'D')
        s.rect(2, gy - 3, 4, 7, 'S'); s.rect(26, gy - 3, 4, 7, 'S'); s.hline(2, gy - 3, 4, 'L'); s.hline(26, gy - 3, 4, 'L')
        s.put(3, gy, 'V' if on else 'W'); s.put(28, gy, 'V' if on else 'W')
        cx = 14
        s.rect(cx - 2, gy - 3, 5, 7, 'W'); s.hline(cx - 2, gy - 3, 5, 'M'); s.vline(cx - 2, gy - 3, 7, 'M'); s.put(cx, gy, 'D'); s.rect(cx - 1, gy + 4, 3, 1, 'E')
        if on:
            s.put(cx, gy + 4, 'r'); s.put(cx - 1, gy + 4, 'r'); s.put(cx + 1, gy + 4, 'r'); s.put(cx, gy + 5, 'H'); s.put(cx, gy + 6, 'r' if i % 2 else 'H')
            for (dx, dy) in ([(2, 6), (-2, 7), (3, 8)], [(-2, 6), (2, 8), (-3, 7)], [(3, 6), (-1, 8), (1, 7)], [(-3, 6), (2, 7), (0, 9)])[i % 4]:
                s.put(cx + dx, gy + dy, 'y' if (dx + i) % 2 else 'o')
        else: s.put(cx, gy + 4, 'W')
        # control end
        bev(s, 8, 58, 16, 4, 'W', 'E', 'D') if False else None
        for k, c in enumerate(('g', 'a', 'V')): s.rect(11 + 4 * k, 60, 2, 1, c if on else 'W')
        return s
    def hurt(self, s, i):
        gy = self.GY[self.DMG[i] % 4]
        shift_rect(s, 3, 29, gy - 3, gy + 5, 0, 0)
        s.rect(3, gy + 3, 14, 2, 'K'); s.stamp(20, gy + 1, art("KKK\nKDK\n.KK"))                 # bridge skewed: the right end sags
        crack(s, [(13, gy - 2), (15, gy + 1), (14, gy + 3)], 'H')
        s.put(14 + (2 if i else -2), gy + 7, 'y'); s.put(13, gy + 5 + i, 'H')
        stamp_on(s, 11, 40, SCORCH_S); stamp_on(s, 17, 22, SCORCH_S)
        for k in range(3): s.put(11 + 4 * k, 60, 'r' if (k + i) % 2 else 'W')
    def wreck(self, s):
        s.stamp(3, 33, art("KKKKKKKKKKKKKKKKKKKKKKKKK\nKSSEEEEEEEEEEEEEEEEEEEEEK\nKSMDDDDDDDDDDDDDDDDDDDDDK\n.KKKKKKKKKKKKKKKKKKKKKKK.")); s.stamp(25, 30, art("KK.\nKSK\n.KK"))
        s.stamp(11, 36, art("KKKKK\nKDDDK\n.KKK.")); crack(s, [(12, 10), (16, 14), (14, 19), (17, 24)], 'M'); s.vline(14, 14, 20, 'K'); s.vline(15, 14, 20, 'D')
        stamp_on(s, 11, 44, SCORCH_L); stamp_on(s, 12, 14, SCORCH_S)
        for k in range(3): s.put(11 + 4 * k, 60, 'E')
    def glow(self, state, i, g, ox, oy, flick=None):
        k = 1.0 if flick is None else (0.8 if flick else 0.3)
        gy = self.GY[i % 4]
        glow(g, ox + 14.5, oy + gy + 5.5, 6, RED, 0.65 * k, 1.8); glow(g, ox + 14.5, oy + gy + 5.5, 11, RED, 0.22 * k, 2.0)
        for (x, y) in ((4.5, 5.5), (27.5, 5.5), (4.5, 58.5), (27.5, 58.5)): glow(g, ox + x, oy + y, 3.5, VIOLET, 0.4 * k, 2.0)

# ============================================================ ASSEMBLY RIG 4x4
class AssemblyRig(LComp):
    id = 'assembly_rig'; cells = (4, 4)
    glow_pad = (8, 8, 8, 8)
    anims = [('on', 'on', 4, 5), ('off', 'off', 1, 0), ('damaged', 'damaged', 2, 5), ('disabled', 'disabled', 1, 0)]
    notes = ('Workshop: a steel jig frame with T-slot rails and four clamps round a half-built chassis (bolt circle, motor boss). The clamps press in turn (N, E, S, W) with a violet toggle lever flipping, and a weld spark runs round the joint. '
             'Damaged: the east clamp arm is bent, the chassis is knocked out of true, a rail is cracked and the weld sparks. Disabled: clamps flung open and dead, the chassis fallen into pieces on the table.')
    DMG = (1, 2)
    def interior(self, state, i):
        on = state == 'on'
        s = Spr(64, 64)
        chamfer_fill(s, 1, 1, 61, 61, 'S', 5); rim(s, 'S', 'M', 'W')
        chamfer_fill(s, 4, 4, 55, 55, 'E', 4)
        recess(s, 9, 9, 46, 46, 'D', 'K')
        for t in range(12, 53, 6):                                    # T-slot grid
            s.hline(10, t, 44, 'E'); s.vline(t, 10, 44, 'E')
        for x in (6, 57):
            for y in (6, 57): s.put(x, y, 'L')
        # workpiece: a chassis plate
        bev(s, 20, 20, 24, 24, 'L', 'M', 'S'); ring(s, 32, 32, 6.5, 8.5, 'E'); circle(s, 32, 32, 5, 'W'); circle(s, 32, 32, 3.2, 'S'); circle(s, 31.5, 31.5, 1.6, 'L')
        for (x, y) in ((22, 22), (41, 22), (22, 41), (41, 41)): s.put(x, y, 'D'); s.put(x + 1, y + 1, 'W')
        s.hline(22, 32, 5, 'E'); s.hline(37, 32, 5, 'E')
        # four clamps: base block on the rail, arm that presses in, violet toggle
        press = (i % 4) if on else -1
        for k in range(4):
            e = 3 if k == press else 0
            if k == 0:   bx, by = 27, 10; s.rect(bx, by, 10, 6, 'W'); s.hline(bx, by, 10, 'S'); s.rect(29, 16, 6, 3 + e, 'M'); s.vline(29, 16, 3 + e, 'L'); s.rect(28, 19 + e, 8, 2, 'S'); lx, ly = 31, 11
            elif k == 1: bx, by = 48, 27; s.rect(bx, by, 6, 10, 'W'); s.vline(bx + 5, by, 10, 'D'); s.rect(45 - e, 29, 3 + e, 6, 'M'); s.hline(45 - e, 29, 3 + e, 'L'); s.rect(43 - e, 28, 2, 8, 'S'); lx, ly = 50, 31
            elif k == 2: bx, by = 27, 48; s.rect(bx, by, 10, 6, 'W'); s.hline(bx, by + 5, 10, 'D'); s.rect(29, 45 - e, 6, 3 + e, 'M'); s.vline(29, 45 - e, 3 + e, 'L'); s.rect(28, 43 - e, 8, 2, 'S'); lx, ly = 31, 49
            else:        bx, by = 10, 27; s.rect(bx, by, 6, 10, 'W'); s.vline(bx, by, 10, 'S'); s.rect(16, 29, 3 + e, 6, 'M'); s.hline(16, 29, 3 + e, 'L'); s.rect(19 + e, 28, 2, 8, 'S'); lx, ly = 11, 31
            hot = k == press
            s.rect(lx, ly, 2, 2, 'V' if on else 'W'); s.put(lx, ly, ('H' if hot else 'X') if on else 'S')
        # weld spark circling the joint
        if on:
            a = math.radians(i * 90 + 45)
            sx, sy = int(round(32 + 9 * math.sin(a))), int(round(32 - 9 * math.cos(a)))
            s.put(sx, sy, 'H'); s.put(sx + 1, sy, 'y'); s.put(sx, sy + 1, 'o'); s.put(sx - 1, sy - 1, 'y')
        s.hline(10, 7, 10, 'Z'); s.put(10, 7, 'V'); s.hline(44, 56, 10, 'Z'); s.put(53, 56, 'V')
        stencil(s, 8, 58, 'L', 1)
        return s
    def hurt(self, s, i):
        s.rect(46, 29, 3, 6, 'D'); s.stamp(40, 28, art("KKKKK.\nKMSSSK\nKSWWKK\n.KKKK.")); s.stamp(43, 33, art("K.K\nKSK"))     # east clamp arm bent off
        shift_rect(s, 20, 44, 20, 44, 1, 1) if False else None
        crack(s, [(20, 24), (26, 28), (24, 34), (30, 40)], 'M'); crack(s, [(50, 8), (53, 13), (51, 18)], 'M')
        s.put(36 + 4 * i, 36 + 2 * i, 'y'); s.put(40, 34, 'H' if i else 'y'); s.put(47, 28 + i, 'H')
        stamp_on(s, 36, 38, SCORCH_S); stamp_on(s, 12, 14, SCORCH_S)
    def wreck(self, s):
        s.rect(20, 20, 24, 24, 'D'); s.stamp(20, 20, art("KKKKKKKKKK..\nKDDDKDDDDKK.\nKDKDDDDKDDDK\nKDDDDKDDDDDK\n.KKDDKDKKDDK\n...KKKK.KKKK"))
        s.stamp(36, 34, art("KKKKKK\nKSMSSK\nKSWWKK\n.KKKK.")); s.stamp(14, 40, art("KKK.\nKSMK\n.KSK")); s.stamp(46, 18, art("KK.\nKMK\n.KK"))
        for (x, y) in ((27, 11), (28, 11)): s.put(x, y, 'K')
        crack(s, [(9, 9), (14, 14), (13, 20)], 'M'); crack(s, [(54, 54), (50, 49), (53, 44)], 'M'); stamp_on(s, 28, 26, SCORCH_L)
        for (lx, ly) in ((31, 11), (50, 31), (31, 49), (11, 31)): s.put(lx, ly, 'Z')
    def glow(self, state, i, g, ox, oy, flick=None):
        k = 1.0 if flick is None else (0.7 if flick else 0.4)
        a = math.radians(i * 90 + 45)
        glow(g, ox + 32 + 9 * math.sin(a), oy + 32 - 9 * math.cos(a), 8, ORANGE, 0.55 * k, 1.8)
        for kk, (x, y) in enumerate(((32, 12), (51, 32), (32, 50), (12, 32))): glow(g, ox + x, oy + y, 6 if kk == i % 4 else 3.4, VIOLET, (0.6 if kk == i % 4 else 0.3) * k, 2.0)

# ============================================================ NANOFORGE 4x4
def swirl_sprite():
    s = Spr(41, 41)
    for arm in range(4):
        for r in range(3, 19):
            th = math.radians(arm * 90 + r * 15.0)
            x, y = 20.5 + r * math.sin(th), 20.5 - r * math.cos(th)
            s.put(int(x), int(y), 'H' if r % 6 == 0 else 'c')
            s.put(int(x + .5 + math.cos(th) * .6), int(y + .5 + math.sin(th) * .6), 'C')
    for arm in range(4):
        th = math.radians(arm * 90 + 40)
        s.put(int(20.5 + 14 * math.sin(th)), int(20.5 - 14 * math.cos(th)), 'H')
    return s

class Nanoforge(LComp):
    id = 'nanoforge'; cells = (4, 4)
    glow_pad = (10, 10, 10, 10)
    anims = [('on', 'on', 4, 6), ('off', 'off', 1, 0), ('damaged', 'damaged', 2, 6), ('disabled', 'disabled', 1, 0)]
    notes = ('Workshop, neon-ish: a round vat of nanite paste in a navy-violet cradle with a cyan glass rim. The paste carries a four-arm swirl of bright nanites that turns a quarter-arm per... (4 frames = a quarter turn of a four-fold swirl, so it loops cleanly); four feed pipes with violet lamps. '
             'Damaged: the glass is cracked and paste weeps out onto the cradle, the swirl stutters. Disabled: the vat is dry and dull, the glass shattered, paste dried round the crack.')
    DMG = (1, 3)
    SW = None
    def interior(self, state, i):
        on = state == 'on'
        s = Spr(64, 64)
        chamfer_fill(s, 1, 1, 61, 61, 'I', 8); rim(s, 'I', 'J', 'N')
        for (x, y) in ((3, 3), (56, 3), (3, 56), (56, 56)):
            bev(s, x, y, 6, 6, 'j', 'J', 'I'); s.rect(x + 2, y + 2, 2, 2, 'V' if on else 'E'); s.put(x + 2, y + 2, 'X' if on else 'W')
        for (a, b) in (((9, 31), (13, 31)), ((50, 31), (54, 31))): pass
        pipe_h(s, 4, 29, 8, ()) if False else None
        s.rect(4, 29, 9, 5, 'Z'); s.hline(4, 29, 9, 'V'); s.hline(4, 33, 9, 'N'); s.rect(51, 29, 9, 5, 'Z'); s.hline(51, 29, 9, 'V'); s.hline(51, 33, 9, 'N')
        s.rect(29, 4, 5, 9, 'Z'); s.vline(29, 4, 9, 'V'); s.vline(33, 4, 9, 'N'); s.rect(29, 51, 5, 9, 'Z'); s.vline(29, 51, 9, 'V'); s.vline(33, 51, 9, 'N')
        circle(s, 32, 32, 26.5, 'K'); circle(s, 32, 32, 25.5, 'J'); ring(s, 32, 32, 24.2, 25.5, 'j'); circle(s, 32, 32, 24, 'I')
        ring(s, 32, 32, 22.5, 24, 'c' if on else 'W')                      # the neon glass rim
        circle(s, 32, 32, 22, 'N')
        circle(s, 32, 32, 20.5, 'B' if on else 'E'); ring(s, 32, 32, 16, 18, 'C' if on else 'W') if False else None
        if on:
            ring(s, 32, 32, 12, 14, 'C'); ring(s, 32, 32, 6, 7.5, 'C')
            if Nanoforge.SW is None: Nanoforge.SW = swirl_sprite()
            sw = rotate(Nanoforge.SW, i * 22.5, 20, 20) if i else Nanoforge.SW
            for y in range(sw.h):
                for x in range(sw.w):
                    if sw.g[y][x] != '.': s.put(12 + x, 12 + y, sw.g[y][x])
            circle(s, 32, 32, 3.5 + (i % 2) * .4, 'H')
        else:
            ring(s, 32, 32, 12, 13, 'W'); circle(s, 32, 32, 2, 'S')
        for (x, y) in ((17, 20), (46, 23), (21, 45), (43, 44)): s.put(x, y, 'H' if on and (x + i) % 2 else ('M' if not on else 'c'))
        # glass glint, top-left
        for (x, y) in ((17, 15), (18, 14), (19, 13), (21, 12), (16, 17)): s.put(x, y, 'H' if on else 'M')
        stencil(s, 28, 59, 'X' if on else 'W', 2)
        return s
    def hurt(self, s, i):
        crack(s, [(46, 17), (43, 22), (46, 27), (42, 31)], 'H'); crack(s, [(46, 27), (50, 30)], 'H')
        for (x, y) in ((47, 31 + k * 2) for k in range(5)): s.put(x, y + i, 'C'); s.put(x + 1, y + i + 1, 'B')
        s.stamp(46, 36, art(".KKK.\nKCBBK\nKBBCK\n.KKK.")); s.stamp(44, 40 + i, art("KK\nKC"))
        for (x, y) in ((24, 34), (25, 34), (26, 35)): s.put(x, y, 'N' if i else 'B')
        stamp_on(s, 12, 44, SCORCH_S)
    def wreck(self, s):
        crack(s, [(14, 20), (20, 25), (18, 32), (26, 38), (24, 45)], 'M'); crack(s, [(46, 17), (43, 22), (46, 27), (42, 31), (47, 38)], 'M'); crack(s, [(30, 20), (32, 28), (36, 32)], 'M')
        s.stamp(46, 38, art(".KKKK.\nKEWWSK\nKWEESK\n.KKKK.")); s.stamp(20, 44, art("KK.\nKSK\n.KK")); s.stamp(40, 44, art("K.K\nKMK"))
        stamp_on(s, 14, 40, SCORCH_L); stamp_on(s, 38, 12, SCORCH_S)
        for (x, y) in ((6, 6), (57, 6), (6, 57), (57, 57)): s.put(x, y, 'E')
    def glow(self, state, i, g, ox, oy, flick=None):
        k = 1.0 if flick is None else (0.6 if flick else 0.35)
        glow(g, ox + 32, oy + 32, 28, CYAN, (0.26 + 0.03 * (i % 2)) * k, 1.4); glow(g, ox + 32, oy + 32, 10, (210, 250, 255), 0.4 * k, 1.8)
        for (x, y) in ((6, 6), (59, 6), (6, 59), (59, 59)): glow(g, ox + x, oy + y, 4, VIOLET, 0.5 * k, 2.0)
        for (x, y) in ((8, 31), (56, 31), (31, 8), (31, 56)): glow(g, ox + x, oy + y, 5, VIOLET, 0.25 * k, 2.0)

# ============================================================ MEDBAY 4x4
def draw_bed(s, x, y, w, h):
    bev(s, x, y, w, h, 'M', 'S', 'W')
    s.rect(x + 2, y + 2, w - 4, h - 4, 'L'); s.hline(x + 2, y + 2, w - 4, 'H'); s.vline(x + 2, y + 2, h - 4, 'H')
    s.rect(x + 4, y + 4, w - 8, 8, 'H'); s.hline(x + 4, y + 11, w - 8, 'M'); s.vline(x + w - 5, y + 4, 8, 'M')       # pillow
    by = y + h // 2 - 4
    s.rect(x + 2, by, w - 4, h - (by - y) - 2, 'q'); s.vline(x + 2, by, h - (by - y) - 2, 'Q'); s.vline(x + w - 3, by, h - (by - y) - 2, 'n')
    s.rect(x + 2, by - 3, w - 4, 3, 'H'); s.hline(x + 2, by - 1, w - 4, 'M')
    for yy in (by + 12, by + 18): s.hline(x + 3, yy, w - 6, 'Q')

class Medbay(LComp):
    id = 'medbay'; cells = (4, 4)
    glow_pad = (8, 8, 8, 8)
    anims = [('on', 'on', 4, 4), ('off', 'off', 1, 0), ('damaged', 'damaged', 2, 5), ('disabled', 'disabled', 1, 0)]
    notes = ('Workshop/medical: two beds side by side and a scanner arch on rails that sweeps down the beds with a green scan line, a pulse monitor between them, violet trim on the equipment rail. The arch runs up and back down over the 4 frames. '
             'Damaged: the arch is jammed skewed on its rails, the scan line flickers and one monitor is dead, a bed is torn. Disabled: the arch has dropped across one bed, scanner dead, monitors dark.')
    DMG = (1, 3)
    AY = [12, 28, 44, 28]
    def interior(self, state, i):
        on = state == 'on'
        s = Spr(64, 64)
        chamfer_fill(s, 0, 0, 64, 64, 'S', 4); rim(s, 'S', 'M', 'W')
        chamfer_fill(s, 2, 2, 60, 60, 'E', 3)
        for x in (2, 60): s.rect(x, 8, 2, 52, 'D'); s.vline(x, 8, 52, 'W')                       # rails
        draw_bed(s, 5, 14, 24, 46); draw_bed(s, 35, 14, 24, 46)
        # equipment rail and the pulse monitor between the beds
        bev(s, 5, 3, 54, 8, 'W', 'E', 'D')
        for k, x in enumerate((8, 14, 20)): s.rect(x, 5, 4, 4, 'D'); s.hline(x, 7 + (k + i) % 2 if on else 7, 4, 'g' if on else 'W')
        bev(s, 28, 4, 8, 6, 'M', 'S', 'W'); s.put(31, 6, 'g' if on else 'W'); s.put(32, 7, 'g' if on else 'W'); s.hline(30, 7, 1, 'g' if on else 'W')
        for k in range(3): violet_lamp(s, 40 + 5 * k, 5, on and (k + i) % 3 != 2)
        s.rect(30, 12, 4, 48, 'W'); s.vline(30, 12, 48, 'S'); s.vline(33, 12, 48, 'D')
        for y in range(15, 58, 10): s.put(31, y, 'g' if on else 'W'); s.put(32, y + 1, 'g' if on else 'W')
        # scanner arch
        ay = self.AY[i % 4] if on else 4 if state == 'off' else self.AY[0]
        if state == 'off': ay = 12
        s.rect(2, ay, 60, 7, 'S'); s.hline(2, ay, 60, 'L'); s.hline(2, ay + 6, 60, 'W'); s.rect(2, ay + 1, 3, 5, 'E'); s.rect(59, ay + 1, 3, 5, 'E')
        s.rect(6, ay + 2, 52, 3, 'D'); s.hline(6, ay + 2, 52, 'E')
        for x in range(8, 56, 8): s.put(x, ay + 1, 'M')
        s.put(4, ay + 3, 'V' if on else 'W'); s.put(59, ay + 3, 'V' if on else 'W')
        if on:
            s.hline(6, ay + 3, 52, 'g')
            s.hline(6, ay + 7, 52, 'g')
            for x in range(6 + (i * 9) % 13, 58, 13): s.rect(x, ay + 3, 3, 1, 'H'); s.put(x + 1, ay + 7, 'H')
        else:
            s.hline(6, ay + 3, 52, 'W')
        return s
    def hurt(self, s, i):
        ay = self.AY[self.DMG[i] % 4]
        shift_rect(s, 40, 62, ay - 1, ay + 9, 0, 3)
        s.rect(40, ay + 3, 22, 1, 'K'); s.stamp(34, ay + 3, art("KKK\nKDK"))
        for k in range(3): s.hline(8 + 6 * k, 7, 4, 'D') if k == 1 else None
        s.rect(14, 5, 4, 4, 'D'); s.put(15, 6, 'r' if i else 'D')
        crack(s, [(38, 22), (44, 27), (41, 33)], 'M'); s.stamp(8, 40, art("KKKK\nKQqK\n.KKK")); s.put(20, ay + 8 + i, 'y')
        stamp_on(s, 46, 44, SCORCH_S)
    def wreck(self, s):
        s.stamp(2, 30, art("KKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKK\nKLSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSK\nKSEDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDK\n.KKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKK.")) if False else None
        for y in range(8, 40):
            for x in range(2, 62):
                if s.get(x, y) in ('S', 'L', 'W', 'E', 'D', 'g', 'H') and y >= self.AY[0] and y < self.AY[0] + 9: pass
        s.stamp(34, 36, art("KKKKKKKKKKKKKKKKKKKKKKKK\nKLSSSSSSSSSSSSSSSSSSSSSK\nKSEDDDDDDDDDDDDDDDDDDDEK\n.KKKKKKKKKKKKKKKKKKKKKK.")); s.stamp(55, 34, art("K.K\nKSK"))
        crack(s, [(38, 22), (44, 27), (41, 33)], 'M'); s.stamp(10, 20, art("KKKK.\nKQqK.\nKnQKK\n.KKK.")); stamp_on(s, 46, 44, SCORCH_L); stamp_on(s, 14, 50, SCORCH_S)
        for k in range(3): s.rect(8 + 6 * k, 5, 4, 4, 'D')
        s.put(4, 4, 'K')
    def glow(self, state, i, g, ox, oy, flick=None):
        k = 1.0 if flick is None else (0.7 if flick else 0.3)
        ay = self.AY[i % 4]
        glow(g, ox + 32, oy + ay + 5, 34, GREEN, 0.18 * k, 2.0, sx=1.0)
        glow(g, ox + 32, oy + ay + 7.5, 20, GREEN, 0.4 * k, 2.2, sx=2.2)
        for k2 in range(3): glow(g, ox + 41 + 5 * k2 + 1, oy + 6.5, 3.4, VIOLET, 0.45 * k, 2.0)
        glow(g, ox + 32, oy + 8, 6, GREEN, 0.4 * k, 2.0)

ALL = [Fabricator, RobotArm, LaserCutter, AssemblyRig, Nanoforge, Medbay]
