"""Healing arms (docs/DRONES.md section 10): Medbay Mk2 (standard) and Halo Arm Mk3 (neon).
Each is a 2x2 base (the usual component sheet: on / off / damaged / disabled) with a socket ring in the middle, and an
ARM sprite `<id>_arm` drawn pointing UP that the game turns about the socket toward the patient (scripts/view/visuals.gd draw_arm).
`python3 lines_medarm.py` writes art/components/medbay_mk2*, medbay_mk3*."""
import json, os
from lines_kit import *
from mach import save_strip

GREEN_SOFT = (120, 240, 150)
CYAN_SOFT = (90, 245, 255)

def lamp(s, x, y, on, c='g'):
    s.rect(x, y, 3, 3, 'D'); s.put(x + 1, y + 1, c if on else 'W')
    if on: s.put(x + 1, y, c)

def cross(s, x, y, c='H'):
    s.rect(x + 1, y, 2, 4, c); s.rect(x, y + 1, 4, 2, c)

# ============================================================ MEDBAY MK2: the standard healing arm base
class MedArm2(LComp):
    id = 'medbay_mk2'; cells = (2, 2)
    glow_pad = (8, 8, 8, 8)
    anims = [('on', 'on', 4, 4), ('off', 'off', 1, 0), ('damaged', 'damaged', 2, 5), ('disabled', 'disabled', 1, 0)]
    anchors = {'pivot': (16, 16)}
    notes = ('Healing arm base, standard line, 2x2: a plate with a socket ring in the middle (the arm sprite medbay_mk2_arm turns about it), a medical cross, four status lamps that chase round while it works, violet trim. '
             'Damaged: scorched plate, a dead lamp, the ring cracked. Disabled: dark, lamps out, ring scorched.')
    DMG = (1, 3)
    def interior(self, state, i):
        on = state == 'on'
        s = Spr(32, 32)
        chamfer_fill(s, 0, 0, 32, 32, 'S', 3); rim(s, 'S', 'M', 'W')
        chamfer_fill(s, 2, 2, 28, 28, 'E', 2)
        for k, (x, y) in enumerate(((4, 4), (25, 4), (25, 25), (4, 25))): lamp(s, x, y, on and (k + i) % 4 != 3)
        s.hline(9, 3, 14, 'Z'); s.hline(9, 28, 14, 'Z'); s.hline(10, 4, 12, 'V') if False else None
        cross(s, 5, 14); 
        for y in (11, 12, 13): s.hline(25, y, 3, 'W')
        for y in (18, 19, 20): s.hline(25, y, 3, 'W')
        circle(s, 15.5, 15.5, 8.5, 'D'); ring(s, 15.5, 15.5, 7.5, 9.5, 'W'); ring(s, 15.5, 15.5, 8.5, 9.5, 'M' if on else 'S')
        circle(s, 15.5, 15.5, 4.5, 'E'); circle(s, 15.5, 15.5, 3.2, 'W'); s.put(15, 15, 'S'); s.put(16, 16, 'D')
        if on:
            for (x, y) in ((8, 15), (23, 15), (15, 8), (15, 23)): s.put(x, y, 'g')
        return s
    def hurt(self, s, i):
        crack(s, [(9, 9), (12, 13), (10, 18), (13, 22)], 'M'); stamp_on(s, 19, 5, SCORCH_S); stamp_on(s, 4, 22, SCORCH_L)
        s.rect(4, 4, 3, 3, 'D')
        s.put(26, 26, 'r' if i else 'D')
    def wreck(self, s):
        crack(s, [(9, 9), (12, 13), (10, 18), (13, 22)], 'M'); stamp_on(s, 18, 4, SCORCH_L); stamp_on(s, 4, 20, SCORCH_L)
    def glow(self, state, i, g, ox, oy, flick=None):
        k = 1.0 if flick is None else (0.7 if flick else 0.3)
        glow(g, ox + 16, oy + 16, 11, GREEN, 0.22 * k, 2.0)
        for n, (x, y) in enumerate(((5, 5), (26, 5), (26, 26), (5, 26))):
            if (n + i) % 4 != 3: glow(g, ox + x, oy + y, 4, GREEN, 0.5 * k, 2.0)

# ============================================================ MEDBAY MK3: the neon healing arm base
class MedArm3(LComp):
    id = 'medbay_mk3'; cells = (2, 2)
    glow_pad = (8, 8, 8, 8)
    anims = [('on', 'on', 4, 4), ('off', 'off', 1, 0), ('damaged', 'damaged', 2, 5), ('disabled', 'disabled', 1, 0)]
    anchors = {'pivot': (16, 16)}
    notes = ('Halo Arm base, neon line, 2x2: navy panels with cyan seams, a crystal on each flank and a bright socket ring in the middle (medbay_mk3_arm turns about it); the ring pulses round while it works. '
             'Damaged: scorched, a crystal cracked, the ring flickering. Disabled: dark, crystals dull.')
    DMG = (1, 3)
    def interior(self, state, i):
        on = state == 'on'
        s = Spr(32, 32)
        chamfer_fill(s, 0, 0, 32, 32, 'J', 3); rim(s, 'J', 'j', 'I')
        chamfer_fill(s, 2, 2, 28, 28, 'I', 2); edge(s, 2, 2, 28, 28, 2, 'c' if on else 'B')
        for x in (5, 24): crystal(s, x, 6, "..0..\n.010.\n0121.\n.121.\n..2..", ['c', 'C', 'B'] if on else ['C', 'B', 'N'])
        for x in (5, 24): crystal(s, x, 21, "..0..\n.010.\n0121.\n.121.\n..2..", ['c', 'C', 'B'] if on else ['C', 'B', 'N'])
        cross(s, 14, 3, 'H' if on else 'j') if False else None
        circle(s, 15.5, 15.5, 8.5, 'N'); ring(s, 15.5, 15.5, 7.5, 9.5, 'J')
        for k in range(8):                       # the halo: eight beads, one bright
            a = k * 3.14159 / 4
            import math
            x, y = 15.5 + 8.3 * math.cos(a), 15.5 + 8.3 * math.sin(a)
            s.put(int(x), int(y), ('H' if (k + i) % 8 == 0 else 'c') if on else 'C')
        circle(s, 15.5, 15.5, 4.5, 'J'); circle(s, 15.5, 15.5, 3.2, 'I'); s.put(15, 15, 'j'); s.put(16, 16, 'N')
        return s
    def hurt(self, s, i):
        crack(s, [(9, 9), (12, 13), (10, 18), (13, 22)], 'j'); stamp_on(s, 19, 5, SCORCH_S); stamp_on(s, 4, 22, SCORCH_L)
        s.put(7, 8, 'N'); s.put(8, 9, 'N')
    def wreck(self, s):
        crack(s, [(9, 9), (12, 13), (10, 18), (13, 22)], 'j'); stamp_on(s, 18, 4, SCORCH_L); stamp_on(s, 4, 20, SCORCH_L)
    def glow(self, state, i, g, ox, oy, flick=None):
        k = 1.0 if flick is None else (0.7 if flick else 0.3)
        glow(g, ox + 16, oy + 16, 12, CYAN, 0.26 * k, 2.0)
        for x in (7, 26): glow(g, ox + x, oy + 8, 4, CYAN, 0.45 * k, 2.0); glow(g, ox + x, oy + 23, 4, CYAN, 0.45 * k, 2.0)

# ============================================================ THE ARMS (point UP; the game turns them about the pivot)
AW, AH, PIV = 16, 40, (8, 32)

def arm_frame(kind, state, i):
    """kind 2 or 3; state idle / heal / damaged / disabled; i the frame."""
    neon = kind == 3
    hi, mid, lo = ('j', 'J', 'I') if neon else ('M', 'S', 'W')
    s = Spr(AW, AH)
    heal = state == 'heal'
    bend = 2 if state == 'damaged' else 0
    # upper arm and base hub
    s.rect(5, 22, 6, 10, mid); s.vline(5, 22, 10, hi); s.vline(10, 22, 10, lo)
    s.hline(5, 25, 6, lo); s.hline(5, 28, 6, lo)
    circle(s, 8, 32, 5, 'E' if not neon else 'I'); circle(s, 8, 32, 3, mid); s.put(7, 31, hi); s.put(8, 32, 'D' if not neon else 'N')
    # forearm, shifted when damaged (jammed skewed)
    fa = Spr(AW, AH)
    fa.rect(6, 11, 4, 11, mid); fa.vline(6, 11, 11, hi); fa.vline(9, 11, 11, lo)
    fa.hline(6, 16, 4, lo)
    circle(fa, 8, 22, 3, 'E' if not neon else 'I'); fa.put(8, 22, 'M' if not neon else 'c'); fa.put(7, 21, hi)
    # the head: a lens in a chamfered cup (Mk3: a halo ring round it)
    chamfer_fill(fa, 3, 1, 10, 9, 'E' if not neon else 'I', 2); edge(fa, 3, 1, 10, 9, 2, hi)
    lens = 'H' if heal and i % 2 == 0 else 'g'
    if neon: lens = 'H' if heal and i % 2 == 0 else 'c'
    circle(fa, 8, 5, 2.3, 'D' if not neon else 'N'); circle(fa, 8, 5, 1.5, lens)
    if neon: ring(fa, 8, 5, 3, 3.9, 'c' if heal else 'C')
    if state == 'disabled':
        circle(fa, 8, 5, 1.5, 'W')
    if bend: shift_rect(fa, 0, AW, 0, 22, bend, 0)
    if state == 'disabled': shift_rect(fa, 0, AW, 0, 22, 4, 5)
    for y in range(AH):
        for x in range(AW):
            if fa.g[y][x] != '.': s.put(x, y, fa.g[y][x])
    if state == 'damaged':
        stamp_on(s, 5, 24, SCORCH_S); s.put(8 + bend, 12, 'y' if i else 'o')
    if state == 'disabled':
        s = s.sub(dict(DARK, **{'N': 'N', 'j': 'J', 'J': 'I', 'I': 'N', 'c': 'C', 'C': 'B', 'H': 'W', 'g': 'W'}))
    s = s.copy(); outline_all(s)
    return s

def arm_glow(kind, state, i):
    g = Rgba(AW + 16, AH + 16)
    rgb = CYAN if kind == 3 else GREEN
    k = 1.0 if state == 'heal' and i % 2 == 0 else 0.55 if state == 'heal' else 0.3
    glow(g, 8 + 8, 5 + 8, 8, rgb, 0.55 * k, 2.0)
    glow(g, 8 + 8, 32 + 8, 5, rgb, 0.2 * k, 2.0)
    return g

def export_arm(kind, outdir):
    cid = 'medbay_mk%d' % kind
    frames, gfr, anims, ganims = [], [], {}, {}
    for name, state, n, fps in (('idle', 'idle', 1, 0), ('heal', 'heal', 2, 5), ('damaged', 'damaged', 2, 5), ('disabled', 'disabled', 1, 0)):
        anims[name] = [len(frames), n, fps]
        for i in range(n): frames.append(arm_frame(kind, state, i))
        if state != 'disabled':
            ganims[name] = [len(gfr), n, fps]
            for i in range(n): gfr.append(arm_glow(kind, state, i))
    save(sheet(frames, len(frames), AW, AH), '%s/%s_arm.png' % (outdir, cid))
    save_strip(gfr, '%s/%s_arm_glow.png' % (outdir, cid))
    J = {'frame': [AW, AH], 'anims': anims, 'aim': 'turret', 'anchors': {'pivot': list(PIV), 'tip': [8, 2]},
         'glow': {'image': cid + '_arm_glow.png', 'frame': [AW + 16, AH + 16], 'offset': [-8, -8], 'anims': ganims},
         'notes': ('The arm of %s, drawn pointing UP and turned about anchors.pivot (the socket ring in the middle of the 2x2 base) toward the patient; '
                   'anchors.tip is the head. idle (at rest), heal (2: the lens pulses while it heals), damaged (2: forearm jammed skewed, sparks), disabled (drooped). The soft green beam and the glow on the patient are drawn in code.') % cid}
    with open('%s/%s_arm.json' % (outdir, cid), 'w') as f: json.dump(J, f, indent=1); f.write('\n')

ALL = [MedArm2, MedArm3]

def export_arms(outdir=None):
    outdir = outdir or ART + '/components'
    for k in (2, 3): export_arm(k, outdir)

if __name__ == '__main__':
    import comp_base
    for C in ALL:
        c = C()
        _, _, J = comp_base.export(c)
        print(c.id, J['frame'], list(J['anims']))
    export_arms()
