"""Belt drives (2x2, three lines) for the conveyor-belt ammo feed, plus the belt floor tiles (art/tiles/belt.png, belt_cut.png).
Rotation 0: the belt rollers come off the TOP edge (north), 16px wide, centred on the cell edge so they meet a belt tile."""
import json, os, math
from lines_kit import *
from lines_shield import seg_ring

def belt_strip(s, i, body='D', rail='E', rib='W', rough=False):
    s.rect(8, 0, 16, 16, body); s.vline(8, 0, 16, rail); s.vline(23, 0, 16, rail)
    for y in range(0, 16):
        if (y + i) % 4 == 0:
            s.hline(9, y, 14, rib)
            if rough and y % 3 == 0: s.put(12 + y % 5, y, 'n')

def roller(s, ry, c=('L', 'S', 'W'), x0=6, w=20):
    s.rect(x0, ry, w, 3, c[1]); s.hline(x0, ry, w, c[0]); s.hline(x0, ry + 2, w, c[2]); s.put(x0, ry + 1, 'D'); s.put(x0 + w - 1, ry + 1, 'D')

class BeltBase(LComp):
    cells = (2, 2)
    glow_pad = (6, 6, 6, 6)
    anims = [('on', 'on', 4, 10), ('off', 'off', 1, 0), ('damaged', 'damaged', 2, 6), ('disabled', 'disabled', 1, 0)]
    DMG = (1, 3)
    anchors = {'belt_out': (16, 0)}
    extra = {'belt': 'rollers come off the top edge; the belt tile continues from there'}

# ---------------------------------------------------------------- Concord Autoloader
class BeltStd(BeltBase):
    id = 'belt_drive_std'
    notes = ('Concord "Autoloader": a clean steel housing with a spoked drive wheel in a window, two roller bars and a belt with scrolling treads coming off the top edge, a registry stencil, a green lamp. '
             'On: the wheel turns a quarter-spoke per frame (4 frames loop) while the treads scroll. Damaged: housing cracked, a spoke bent, roller bar skewed, lamp red and a spark. Disabled: the belt torn, the wheel off its axle, the housing split.')
    def interior(self, state, i):
        on = state == 'on'
        s = Spr(32, 32)
        belt_strip(s, i if on else 0)
        roller(s, 1); roller(s, 9)
        bev(s, 1, 13, 30, 18, 'L', 'M', 'S')
        recess(s, 4, 16, 24, 12, 'D', 'K')
        circle(s, 16, 22, 5.4, 'E'); ring(s, 16, 22, 4.6, 5.4, 'a' if on else 'W')
        for k in range(4):
            a = math.radians((i * 22.5 if on else 11) + 90 * k)
            line(s, 16, 22, int(round(16 + 4.2 * math.sin(a))), int(round(22 - 4.2 * math.cos(a))), 'L' if on else 'S')
        circle(s, 16, 22, 1.6, 'D'); s.put(15, 21, 'L')
        s.put(28, 17, 'g' if on else 'W'); s.put(29, 17, 'g' if on else 'W'); s.put(28, 20, 'a' if on else 'W')
        stencil(s, 5, 29, 'W', 1); stencil(s, 20, 29, 'W', 0)
        for (x, y) in ((3, 14), (28, 14), (3, 29), (28, 29)): s.put(x, y, 'L')
        return s
    def hurt(self, s, i):
        crack(s, [(5, 14), (9, 17), (8, 21), (12, 25)], 'H'); shift_rect(s, 6, 26, 9, 12, 2, 0); s.stamp(23, 22, art("KK.\nKDK"))
        s.put(28, 17, 'r' if i else 'D'); s.put(29, 17, 'D'); s.put(12 + 3 * i, 24, 'y'); s.put(13, 22 - i, 'H')
        line(s, 16, 22, 20, 25, 'W'); stamp_on(s, 19, 17, SCORCH_S)
    def wreck(self, s):
        s.rect(8, 6, 16, 8, '.'); s.stamp(6, 5, art("KK.K..KK.K\nKDKDKKDKDK\n.KKDKK.KK.")); s.stamp(9, 8, art("KKKKKK\nKSMSEK\n.KKKK."))
        crack(s, [(3, 14), (8, 18), (6, 24), (11, 29)], 'M'); s.stamp(13, 19, art("KKKK\nKDDK\nKDKK")); s.stamp(21, 22, art("KK.\nKSK\n.KK"))
        stamp_on(s, 20, 17, SCORCH_L); s.put(28, 17, 'E')
    def glow(self, state, i, g, ox, oy, flick=None):
        k = 1.0 if flick is None else 0.6
        glow(g, ox + 28.5, oy + 17.5, 3.5, RED if flick is not None else GREEN, 0.5 * k, 2.0)
        glow(g, ox + 16, oy + 22, 7, AMBER, 0.28 * k, 2.0)

# ---------------------------------------------------------------- Clan Chain Drive
class BeltScrap(BeltBase):
    id = 'belt_drive_scrap'
    anims = [('on', 'on', 4, 10), ('off', 'off', 1, 0), ('damaged', 'damaged', 2, 6), ('disabled', 'disabled', 1, 0), ('jammed', 'jammed', 2, 6)]
    notes = ('Scrapper Clans "Chain Drive": a greasy housing of two mismatched plates, hazard tape, a toothed sprocket in a window driving a chain (link dots crawl along it) up to the roller axle, a rough rubber belt with a rusty roller. '
             'On: the sprocket turns a quarter-tooth per frame (4 frames), chain links and treads move. JAMMED (2 frames): a bolt is wedged in the sprocket, the chain hangs slack, sparks, the red lamp flashes. '
             'Damaged: the chain has jumped a tooth and sags, plate cracked, tape peeling, sparks. Disabled: the chain snapped and lying across the housing, belt torn, sprocket bent.')
    def sprocket(self, s, ang):
        circle(s, 16, 22, 5.2, 'K'); circle(s, 16, 22, 4.4, 'W'); circle(s, 16, 22, 3.0, 'E'); circle(s, 16, 22, 1.2, 'L')
        for k in range(8):
            a = math.radians(ang + 45 * k)
            tx, ty = 16 + 5.6 * math.sin(a), 22 - 5.6 * math.cos(a)
            s.put(int(round(tx)), int(round(ty)), 'M'); s.put(int(round(16 + 6.4 * math.sin(a))), int(round(22 - 6.4 * math.cos(a))), 'K')
    def interior(self, state, i):
        on = state == 'on'; jam = state == 'jammed'
        s = Spr(32, 32)
        belt_strip(s, i if on else 0, body='n', rail='E', rib='D', rough=True)
        roller(s, 1, ('M', 'S', 'W')); roller(s, 9, ('Q', 'u', 'n'))
        plate(s, 1, 13, 16, 18, 'M', False); plate(s, 16, 13, 15, 18, 'S', False); weld(s, 16, 15, 14, True)
        bolts(s, [(3, 14), (27, 14)])
        recess(s, 4, 16, 24, 12, 'D', 'K')
        self.sprocket(s, (i * 11.25 if on else (0 if jam else 6)))
        # roller-axle sprocket (small, left) and the chain between the two
        circle(s, 4.5, 10.5, 2.5, 'K'); circle(s, 4.5, 10.5, 1.8, 'W'); s.put(4, 10, 'L')
        if jam: pts = [(11, 20), (8, 17), (6, 13)]
        else: pts = [(11, 21), (7, 16), (5, 12)]
        for (a, b) in zip(pts, pts[1:]): line(s, a[0], a[1], b[0], b[1], 'E')
        for (a, b) in zip([(p[0] + 2, p[1] + 1) for p in pts], [(p[0] + 2, p[1] + 1) for p in pts][1:]): line(s, a[0], a[1], b[0], b[1], 'E')
        for t in range(4): 
            if on and (t + i) % 4 == 0: s.put(pts[1][0] + (t - 1), pts[1][1] + t - 1, 'L')
        if jam: s.stamp(20, 19, art("KKK\nKLK\nKKK")); s.put(21, 20, 'S')
        hazard(s, 2, 29, 12, 2)
        s.put(28, 17, 'a' if on else 'r' if jam and i == 0 else 'W'); s.put(29, 17, 'a' if on else 'W')
        stamp_on(s, 6, 25, art("n.\nnn")); stamp_on(s, 24, 24, art("u.\nuu"))
        if jam:
            for (x, y) in (((22, 18), (24, 21), (20, 17)) if i == 0 else ((23, 17), (19, 20), (25, 19))): s.put(x, y, 'y' if (x + i) % 2 else 'H')
        return s
    def hurt(self, s, i):
        crack(s, [(18, 14), (20, 18), (19, 23), (22, 27)], 'M'); s.stamp(5, 17, art("KK.\nKDK")); s.hline(3, 29, 6, 'K'); s.put(8, 30, 'a')
        for (x, y) in ((9, 18 + i), (10, 19 + i)): s.put(x, y, 'D')
        s.put(11, 24 + i, 'y'); s.put(12, 25, 'H' if i else 'y'); s.put(28, 17, 'r' if i else 'D')
    def wreck(self, s):
        s.rect(8, 7, 16, 7, '.'); s.stamp(7, 6, art("KK.K..K.KK\nKDKDKKDKDK\n.KKDKKK.K.")); s.stamp(8, 9, art("KKKKKK\nKnSnDK\n.KKKK."))
        crack(s, [(17, 14), (18, 19), (16, 24), (20, 29)], 'M'); s.stamp(8, 17, art("KKKKKKKKKK\nKESEEESEEK\nKKKKKKKKKK")); s.stamp(21, 22, art("KK.\nKSK\n.KK"))
        s.stamp(18, 25, art("K.K.\nKEKE")); stamp_on(s, 4, 22, SCORCH_L); s.put(28, 17, 'E')
    def glow(self, state, i, g, ox, oy, flick=None):
        k = 1.0 if flick is None else 0.6
        glow(g, ox + 28.5, oy + 17.5, 3.5, AMBER if flick is None else RED, 0.5 * k, 2.0)
        if state == 'jammed': glow(g, ox + 22, oy + 19, 5, YEL, 0.5 if i else 0.3, 2.0); glow(g, ox + 28.5, oy + 17.5, 4, RED, 0.6 if i == 0 else 0.15, 2.0)

# ---------------------------------------------------------------- Lumen Mag-Rail
class BeltNeon(BeltBase):
    id = 'belt_drive_neon'
    notes = ('Lumen "Mag-Rail": no chain or tread, a magnetic rail: a navy track with cyan edge lines and four coil rings whose pulse climbs the rail (the on loop), a navy housing with a flywheel ring of four cyan segments spinning inside it, magenta pins. '
             'Damaged: a coil ring is dark and cracked, the flywheel stutters, arcs spit at the rail. Disabled: the rail split and dull, the flywheel stopped and cracked, every cyan line dead.')
    COIL = (2, 6, 10, 14)
    def interior(self, state, i):
        on = state == 'on'
        s = Spr(32, 32)
        s.rect(8, 0, 16, 16, 'N'); s.vline(8, 0, 16, 'c' if on else 'W'); s.vline(23, 0, 16, 'c' if on else 'W')
        s.vline(9, 0, 16, 'B' if on else 'E'); s.vline(22, 0, 16, 'B' if on else 'E')
        for k, y in enumerate(self.COIL):
            lit = on and ((3 - k) + i) % 4 == 0                       # the pulse climbs the rail
            s.rect(6, y, 20, 3, 'J'); s.hline(6, y, 20, 'j'); s.hline(6, y + 2, 20, 'I')
            s.hline(8, y + 1, 16, 'H' if lit else ('C' if on else 'E'))
            s.put(6, y + 1, 'm' if on else 'E'); s.put(25, y + 1, 'm' if on else 'E')
        for y in range(0, 16, 4): s.put(15, (y + i) % 16 if on else y, 'C' if on else 'E')
        navy_panel(s, 1, 13, 30, 18); edge(s, 1, 13, 30, 18, 1, 'c' if on else 'W')
        recess(s, 4, 16, 24, 12, 'N', 'I')
        circle(s, 16, 22, 5.6, 'I'); ring(s, 16, 22, 4.4, 5.6, 'J')
        if on: seg_ring(s, 16, 22, 3.4, 5.4, 4, .5, i * 22.5, 'c', 'H')
        else: seg_ring(s, 16, 22, 3.4, 5.4, 4, .5, 20, 'W', 'S')
        circle(s, 16, 22, 2.4, 'N'); s.put(15, 21, 'm' if on else 'E'); s.put(16, 22, 'P' if on else 'E')
        s.put(28, 17, 'c' if on else 'W'); s.put(28, 20, 'm' if on else 'E')
        return s
    def hurt(self, s, i):
        y = self.COIL[1]
        s.rect(6, y, 20, 3, 'N'); crack(s, [(8, y), (12, y + 2), (16, y + 1)], 'H'); s.put(20 + i, y + 1, 'B')
        s.put(5, y + 1, 'm' if i else 'H'); s.put(26, y - 1 - i, 'c')
        crack(s, [(22, 15), (24, 20), (22, 25)], 'H'); seg_ring(s, 16, 22, 3.4, 5.4, 4, .5, 30 + 40 * i, 'B', 'C')
        s.put(11 + 4 * i, 18, 'H'); stamp_on(s, 5, 25, SCORCH_S)
    def wreck(self, s):
        s.rect(8, 6, 16, 4, '.'); s.stamp(7, 5, art("KK.K..K.KK\nKJKJKKJKJK\n.KKIKKK.K.")); s.stamp(9, 9, art("KKKKKK\nKNIJNK\n.KKKK."))
        crack(s, [(3, 14), (9, 19), (8, 25), (13, 29)], 'M'); s.stamp(12, 18, art("KKKKK\nKNNNK\nKNKKK\n.KKK.")); s.stamp(22, 22, art("KK.\nKSK\n.KK"))
        stamp_on(s, 20, 24, SCORCH_L); s.put(28, 17, 'E'); s.put(28, 20, 'E')
    def glow(self, state, i, g, ox, oy, flick=None):
        k = 1.0 if flick is None else 0.55
        for kk, y in enumerate(self.COIL):
            if flick is not None and kk == 1: continue
            lit = ((3 - kk) + i) % 4 == 0
            glow(g, ox + 16, oy + y + 1.5, 10 if lit else 5, CYAN, (0.55 if lit else 0.15) * k, 2.0, sx=1.6)
        glow(g, ox + 16, oy + 22, 8, CYAN, 0.4 * k, 1.8); glow(g, ox + 6.5, oy + 7.5, 3, MAGENTA, 0.3 * k, 2.0)

# ---------------------------------------------------------------- floor tiles
def belt_tile(mask, f):
    s = Spr(16, 16)
    N, E, S, W = bool(mask & 1), bool(mask & 2), bool(mask & 4), bool(mask & 8)
    s.rect(3, 3, 10, 10, 'G')
    if N: s.rect(3, 0, 10, 3, 'G')
    if S: s.rect(3, 13, 10, 3, 'G')
    if W: s.rect(0, 3, 3, 10, 'G')
    if E: s.rect(13, 3, 3, 10, 'G')
    vflow = N or S or not (E or W)
    for y in range(16):                                             # treads scroll north on vertical arms
        if (y + f) % 4 == 0:
            for x in range(4, 12):
                if s.get(x, y) == 'G' and (y < 3 or y > 12 or (vflow and 3 <= y <= 12)): s.put(x, y, 'W')
    for x in range(16):                                             # ... and east on horizontal arms
        if (x - f) % 4 == 0:
            for y in range(4, 12):
                if s.get(x, y) == 'G' and (x < 3 or x > 12 or (not vflow and 3 <= x <= 12)): s.put(x, y, 'W')
    for x in range(3, 13):                                          # rails where the channel has no arm
        if not N: s.put(x, 3, 'E')
        if not S: s.put(x, 12, 'E')
    for y in range(3, 13):
        if not W: s.put(3, y, 'E')
        if not E: s.put(12, y, 'E')
    for y in range(0, 3):
        if N: s.put(3, y, 'E'); s.put(12, y, 'E')
    for y in range(13, 16):
        if S: s.put(3, y, 'E'); s.put(12, y, 'E')
    for x in range(0, 3):
        if W: s.put(x, 3, 'E'); s.put(x, 12, 'E')
    for x in range(13, 16):
        if E: s.put(x, 3, 'E'); s.put(x, 12, 'E')
    return s

def belt_cut():
    s = belt_tile(5, 0)
    for y in range(6, 10):
        for x in range(3, 13): s.erase(x, y)
    for (x, y) in ((3, 6), (5, 7), (7, 6), (9, 7), (11, 6), (12, 7), (4, 9), (6, 8), (8, 9), (10, 8)): s.put(x, y, 'K')
    for (x, y) in ((4, 5), (6, 5), (8, 5), (10, 5), (5, 10), (7, 10), (9, 10), (11, 10)): s.put(x, y, 'E')
    s.stamp(6, 7, art("WE\nEW")); s.put(10, 8, 'D'); s.put(9, 4, 'a'); s.put(8, 11, 'o')
    return s

def export_tiles(outdir):
    os.makedirs(outdir, exist_ok=True)
    frames = [[belt_tile(m, f) for m in range(16)] for f in range(4)]
    sh = Spr(256, 64)
    for f in range(4):
        for m in range(16): sh.stamp(m * 16, f * 16, frames[f][m].rows())
    save(sh, outdir + '/belt.png')
    J = {'frame': [16, 16], 'cells': [1, 1], 'autotile': 'mask4', 'mask': {'N': 1, 'E': 2, 'S': 4, 'W': 8}, 'frames': 16,
         'layout': 'column = mask (N*1 + E*2 + S*4 + W*8), row = scroll frame', 'scroll_frames': 4, 'scroll_fps': 8,
         'anims': {'scroll': [0, 4, 8]},
         'notes': 'Conveyor-belt floor overlay, flat and low contrast so crew read on top. Treads scroll north on vertical arms and east on horizontal arms (4 frames loop); the game mirrors or rotates the draw to the belt heading. Frame for mask m, scroll step f is the 16x16 cell at x = m*16, y = f*16.'}
    json.dump(J, open(outdir + '/belt.json', 'w'), indent=1); open(outdir + '/belt.json', 'a').write('\n')
    save(belt_cut(), outdir + '/belt_cut.png')
    J2 = {'frame': [16, 16], 'cells': [1, 1], 'anims': {'cut': [0, 1, 0]},
          'notes': 'A broken belt cell: the treads torn across the middle with a loose tread lying in the gap. Drawn as a straight north-south run; rotate for east-west. Replace the belt tile when the cell is cut.'}
    json.dump(J2, open(outdir + '/belt_cut.json', 'w'), indent=1); open(outdir + '/belt_cut.json', 'a').write('\n')

ALL = [BeltStd, BeltScrap, BeltNeon]
