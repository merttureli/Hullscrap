"""Healing arms (docs/DRONES.md section 10): Medbay Mk2 (standard line) and Halo Arm Mk3 (neon line), an articulated medical robot arm on a 2x2 base.
Four sprites per arm, each drawn pointing UP with its joints as anchors, so the game poses them as a 2-bone chain (scripts/view/visuals.gd _draw_arm):
  <id>.png        the 2x2 base (the usual component sheet: on / off / damaged / disabled): the white medical plate, a cross, status lamps, the shoulder turntable;
  <id>_upper.png  the upper arm: anchors.pivot = the shoulder (on the base's middle), anchors.tip = the elbow;
  <id>_fore.png   the forearm: anchors.pivot = the elbow, anchors.tip = the wrist; its `damaged` frames are the ones that spark;
  <id>_head.png   the end effector, a three-finger soft gripper round the emitter: anchors.pivot = the wrist, anchors.emitter = where the beam starts.
Segment anims: idle, off (lights dead), damaged (2), disabled (dark; the head's fingers hang limp); the head also has heal (2: the emitter pulses).
`python3 lines_medarm.py` writes art/components/medbay_mk2*, medbay_mk3*; `--sheet out.png` draws the 3x preview sheet (it poses the arm with the
same 2-bone solve as the game, `pose` below)."""
import json, math, os, re, sys
from lines_kit import *
from mach import save_strip

GREEN_SOFT = (120, 240, 150)
CYAN_SOFT = (90, 245, 255)
# private letters for colours already in palette.gpl (no new colour): the medical teal ramp (the Mire teal-greens) and the mint
ALIAS = {'%': '3a9a7e', '[': '1f5f52', ']': '7bd0a6', '&': '8cf0c4'}
def _gpl():
    try: return {l.split('#')[1].split()[0] for l in open(os.path.join(ART, 'palette.gpl')) if re.match(r'\s*\d+\s+\d+\s+\d+\s+#', l)}
    except OSError: return set()
_HEX = _gpl()
for _k, _h in ALIAS.items():
    assert not _HEX or _h in _HEX, (_k, _h)
    RGB[_k] = tuple(int(_h[i:i + 2], 16) for i in (0, 2, 4))

# the two lines, as role letters -> palette letters. w0..w3: the shell, light to dark; t0..t2: the trim (teal; neon cyan); s0..s3: the joints' steel;
# e0..e2: the emitter (bright, mid, rim) and its glow; k: the cable; x: the cross
LOOK = {
 2: dict(w0='H', w1='L', w2='M', w3='S', t0=']', t1='%', t2='[', s0='M', s1='S', s2='W', s3='E', e0='H', e1='&', e2='g', k0='E', k1='W', x='%', rgb=GREEN),
 3: dict(w0='c', w1='j', w2='J', w3='I', t0='c', t1='C', t2='B', s0='j', s1='J', s2='I', s3='N', e0='H', e1='c', e2='C', k0='N', k1='C', x='c', rgb=CYAN),
}

def lamp(s, x, y, on, c='g'):
    s.rect(x, y, 3, 3, 'D'); s.put(x + 1, y + 1, c if on else 'W')
    if on: s.put(x + 1, y, c)

def med_cross(s, x, y, c, hi):
    """the medical cross, 7x7 with arms 3 px thick, lit along its top-left edges."""
    s.rect(x + 2, y, 3, 7, c); s.rect(x, y + 2, 7, 3, c)
    s.hline(x + 2, y, 3, hi); s.vline(x + 2, y, 2, hi); s.hline(x, y + 2, 2, hi); s.vline(x, y + 2, 3, hi)

# ============================================================ THE BASES (2x2): the plate, a cross, lamps, the shoulder turntable in the middle
class MedArm2(LComp):
    id = 'medbay_mk2'; cells = (2, 2)
    glow_pad = (8, 8, 8, 8)
    anims = [('on', 'on', 4, 4), ('off', 'off', 1, 0), ('damaged', 'damaged', 2, 5), ('disabled', 'disabled', 1, 0)]
    anchors = {'pivot': (16, 16)}
    notes = ('Healing arm base, standard line, 2x2: a clean white medical plate with a teal stripe and a teal cross, three green status lamps that chase while it works, '
             'the power line in a groove from the left edge to the shoulder turntable in the middle (anchors.pivot: the arm\'s shoulder, medbay_mk2_upper, sits on it). '
             'Damaged: scorched, a dead lamp, the plate cracked. Disabled: dark, lamps out.')
    DMG = (1, 3)
    def interior(self, state, i):
        on = state == 'on'
        s = Spr(32, 32)
        chamfer_fill(s, 0, 0, 32, 32, 'L', 3); rim(s, 'L', 'H', 'M')
        for k in range(4, 28): s.put(k, 3, 'M'); s.put(3, k, 'M'); s.put(k, 28, 'H'); s.put(28, k, 'H')       # the panel seam (inset)
        s.hline(4, 25, 24, ']'); s.hline(4, 26, 24, '%'); s.hline(4, 27, 24, '[')                            # the teal stripe along the foot
        med_cross(s, 4, 4, '%', ']')
        for k, (x, y) in enumerate(((23, 5), (23, 20), (5, 20))): lamp(s, x, y, on and (k + i) % 4 != 3)
        s.rect(0, 14, 6, 4, 'E'); s.hline(0, 14, 6, 'D'); s.hline(0, 17, 6, 'W')                              # the power line in its groove
        s.hline(0, 15, 6, 'q'); s.hline(0, 16, 6, 'n')
        circle(s, 15.5, 15.5, 9.2, 'W'); ring(s, 15.5, 15.5, 8.3, 9.2, 'S')                                  # the well the arm folds into (darker, so the white arm reads on it)
        for k in range(0, 360, 8):
            if 200 <= k <= 330: s.put(int(15.5 + 8.7 * math.cos(math.radians(k))), int(15.5 + 8.7 * math.sin(math.radians(k))), 'E')
        circle(s, 15.5, 15.5, 7.0, 'S'); ring(s, 15.5, 15.5, 6.0, 7.0, 'M')                                  # the turntable
        ring(s, 15.5, 15.5, 4.6, 5.6, '%' if on else '[')
        circle(s, 15.5, 15.5, 4.2, 'W'); circle(s, 15.5, 15.5, 3.0, 'E')
        if on:                                                                                               # a bright tick turning round the ring
            a = i * math.pi / 2 + 0.6
            s.put(int(15.5 + 5.1 * math.cos(a)), int(15.5 + 5.1 * math.sin(a)), ']')
        for (x, y) in ((11, 10), (20, 10), (11, 21), (20, 21)): s.put(x, y, 'M')                            # the well's bolts
        return s
    def hurt(self, s, i):
        crack(s, [(20, 4), (18, 8), (21, 12)], 'M'); stamp_on(s, 4, 20, SCORCH_L); stamp_on(s, 22, 26, SCORCH_S)
        s.rect(23, 20, 3, 3, 'D'); s.put(24, 21, 'r' if i else 'D')
    def wreck(self, s):
        crack(s, [(20, 4), (18, 8), (21, 12), (19, 15)], 'M'); stamp_on(s, 18, 3, SCORCH_L); stamp_on(s, 3, 19, SCORCH_L)
    def glow(self, state, i, g, ox, oy, flick=None):
        k = 1.0 if flick is None else (0.7 if flick else 0.3)
        glow(g, ox + 16, oy + 16, 9, GREEN, 0.16 * k, 2.0)
        for n, (x, y) in enumerate(((24, 6), (24, 21), (6, 21))):
            if (n + i) % 4 != 3: glow(g, ox + x, oy + y, 4, GREEN, 0.5 * k, 2.0)

class MedArm3(LComp):
    id = 'medbay_mk3'; cells = (2, 2)
    glow_pad = (8, 8, 8, 8)
    anims = [('on', 'on', 4, 4), ('off', 'off', 1, 0), ('damaged', 'damaged', 2, 5), ('disabled', 'disabled', 1, 0)]
    anchors = {'pivot': (16, 16)}
    notes = ('Halo Arm base, neon line, 2x2: navy panels with cyan edges, a cyan cross, crystal facets in two corners and the halo turntable in the middle '
             '(anchors.pivot: the arm\'s shoulder, medbay_mk3_upper, sits on it); its beads run round while it works. Damaged: scorched, a crystal cracked. Disabled: dark, crystals dull.')
    DMG = (1, 3)
    def interior(self, state, i):
        on = state == 'on'
        s = Spr(32, 32)
        chamfer_fill(s, 0, 0, 32, 32, 'J', 3); rim(s, 'J', 'j', 'I')
        chamfer_fill(s, 2, 2, 28, 28, 'I', 2); edge(s, 2, 2, 28, 28, 2, 'c' if on else 'B')
        med_cross(s, 4, 4, 'C' if on else 'B', 'c' if on else 'C')
        for (x, y) in ((23, 4), (4, 23), (23, 23)):
            crystal(s, x, y, "..0..\n.010.\n0121.\n.121.\n..2..", ['c', 'C', 'B'] if on else ['C', 'B', 'N'])
        s.rect(0, 14, 9, 4, 'N'); s.hline(0, 15, 8, 'C' if on else 'B'); s.hline(0, 16, 8, 'B')               # the power line, lit
        circle(s, 15.5, 15.5, 9.2, 'N'); ring(s, 15.5, 15.5, 8.3, 9.2, 'B' if on else 'I')                    # the well the arm folds into
        circle(s, 15.5, 15.5, 7.0, 'J'); ring(s, 15.5, 15.5, 6.0, 7.0, 'j')
        circle(s, 15.5, 15.5, 5.6, 'N')
        for k in range(8):                                                                                   # the halo: eight beads, one bright, running round
            a = k * math.pi / 4
            s.put(int(15.5 + 5.0 * math.cos(a)), int(15.5 + 5.0 * math.sin(a)), ('H' if (k + i) % 4 == 0 else 'c') if on else 'C')
        circle(s, 15.5, 15.5, 3.4, 'I'); circle(s, 15.5, 15.5, 2.2, 'J')
        return s
    def hurt(self, s, i):
        crack(s, [(20, 4), (18, 8), (21, 12)], 'j'); stamp_on(s, 4, 20, SCORCH_L); s.put(23, 7, 'N'); s.put(24, 8, 'N')
    def wreck(self, s):
        crack(s, [(20, 4), (18, 8), (21, 12), (19, 15)], 'j'); stamp_on(s, 18, 3, SCORCH_L); stamp_on(s, 3, 19, SCORCH_L)
    def glow(self, state, i, g, ox, oy, flick=None):
        k = 1.0 if flick is None else (0.7 if flick else 0.3)
        glow(g, ox + 16, oy + 16, 10, CYAN, 0.22 * k, 2.0)
        for (x, y) in ((25, 6), (6, 25), (25, 25)): glow(g, ox + x, oy + y, 4, CYAN, 0.45 * k, 2.0)

# ============================================================ THE SEGMENTS (pointing UP; the game turns each about anchors.pivot)
SEG = {   # name: (frame w, h, pivot, tip) in source px; the length pivot -> tip is the bone
 'upper': (11, 24, (5, 19), (5, 4)),
 'fore':  (9, 21, (4, 17), (4, 4)),
 'head':  (13, 14, (6, 12), (6, 5)),
}
def bone(name): w, h, p, t = SEG[name]; return (p[1] - t[1]) / 16.0          # in cells

def col_shade(w, look):
    """the shell's tones across its width, lit from the left."""
    L = look
    if w <= 3: return [L['w0'], L['w1'], L['w3']][:w]
    return [L['w0']] + [L['w1']] * max(1, w - 3) + [L['w2'], L['w3']]

def shell(s, cx, y0, y1, w0, w1, look):
    """a tapered shell from row y0 (width w0) to row y1 (width w1), centred on column cx."""
    for y in range(min(y0, y1), max(y0, y1) + 1):
        t = (y - y0) / float(y1 - y0) if y1 != y0 else 0
        w = int(round(w0 + (w1 - w0) * t))
        x0 = cx - w // 2
        for k, c in enumerate(col_shade(w, look)): s.put(x0 + k, y, c)

def joint(s, cx, cy, r, look, hub=True):
    """a joint cap seen from above: a steel ring, the trim hub, a bolt."""
    L = look
    circle(s, cx + .5, cy + .5, r, L['s1']); ring(s, cx + .5, cy + .5, r - 1, r, L['s2'])
    for a in range(0, 360, 15):                                                 # the ring's lit upper-left
        if 200 <= a <= 320:
            x = int(cx + .5 + (r - .5) * math.cos(math.radians(a))); y = int(cy + .5 + (r - .5) * math.sin(math.radians(a)))
            if s.get(x, y) == L['s2']: s.put(x, y, L['s0'])
    if hub:
        circle(s, cx + .5, cy + .5, r - 1.6, L['t1']); s.put(cx - 1, cy - 1, L['t0']) if r > 3 else None
        s.put(cx, cy, L['t2'] if r > 3 else L['t0'])

def cable(s, x, y0, y1, look, clips=()):
    """a cable along a segment, 1 px, with a highlight now and then and clips that hold it to the shell."""
    for y in range(y0, y1 + 1): s.put(x, y, look['k1'] if (y - y0) % 4 == 1 else look['k0'])
    for (cx, cy) in clips: s.put(cx, cy, look['s0'])

def seg_upper(kind, state, i):
    L = LOOK[kind]; s = Spr(11, 24)
    shell(s, 5, 17, 5, 7, 5, L)                                                 # the shell, tapering to the elbow
    circle(s, 5.5, 4.5, 2.6, L['s1']); s.put(4, 3, L['s0']); s.put(6, 5, L['s2'])   # the elbow knuckle (the forearm's joint cap sits on it)
    s.hline(2, 11, 7, L['t1']); s.hline(2, 10, 7, L['t0']); s.put(8, 11, L['t2'])  # the trim band
    if kind == 3: s.vline(2, 7, 9, 'c'); s.put(5, 13, 'c'); s.put(5, 8, 'c')
    else: s.vline(5, 13, 3, L['w2'])                                            # a panel seam
    cable(s, 9, 7, 16, L, clips=((8, 8), (8, 14)))
    joint(s, 5, 19, 4, L, hub=False)                                            # the shoulder
    circle(s, 5.5, 19.5, 1.8, L['t1']); s.put(5, 19, L['t0'])
    return s

def seg_fore(kind, state, i):
    L = LOOK[kind]; s = Spr(9, 21)
    shell(s, 4, 15, 6, 5, 4, L)
    s.hline(2, 7, 5, L['t0']); s.hline(2, 8, 5, L['t1'])                        # the trim band at the wrist end
    if kind == 3: s.vline(2, 9, 5, 'c')
    s.hline(2, 4, 5, L['s1']); s.hline(2, 5, 5, L['s2']); s.put(2, 4, L['s0'])  # the wrist collar
    cable(s, 1, 6, 14, L, clips=((2, 7), (2, 12)))
    joint(s, 4, 17, 3, L)                                                       # the elbow
    return s

HEAD = """
.............
..pp.....pp..
..f.......F..
..f.......F..
..ff.....FF..
...ff.t.FF...
...fhhhhhF...
...hhhhhhH...
....hhhhH....
.....ccc.....
.....CCC.....
"""   # 'f' finger (lit), 'F' finger (shade), 'p' soft pad (trim), 't' the thumb's pad, 'h' palm, 'H' palm shade, 'c' 'C' the wrist collar

def seg_head(kind, state, i):
    """the end effector: a soft gripper, two fingers curled round the emitter and the thumb under it, holding the light: a glowing orb (Mk3: a crystal)."""
    L = LOOK[kind]; s = Spr(13, 14)
    sub = {'f': L['w1'], 'F': L['w2'], 'p': L['t0'], 't': L['t1'], 'h': L['w1'], 'H': L['w3'], 'c': L['s1'], 'C': L['s2']}
    s.stamp(0, 2, art(HEAD), sub)
    s.put(2, 4, L['w0']); s.put(2, 5, L['w0']); s.put(4, 8, L['w0']); s.put(4, 9, L['w0'])
    lit = state in ('idle', 'heal')
    pulse = state == 'heal' and i % 2 == 0
    ox, oy = 6, 5                                                               # the orb, held between the fingertips
    if lit:
        orb = (['.1.', '101', '.1.'] if pulse else ['.2.', '212', '.2.']) if kind == 2 else (['.1.', '101', '.2.'] if pulse else ['.1.', '121', '.2.'])
        s.stamp(ox - 1, oy - 1, orb, {'0': L['e0'], '1': L['e1'], '2': L['e2']})
        if kind == 3: s.put(ox - 1, oy - 1, 'c'); s.put(ox + 1, oy + 1, 'B')     # Mk3: the crystal's facets
    else:
        s.stamp(ox - 1, oy - 1, ['.E.', 'EWE', '.E.'] if kind == 2 else ['.N.', 'NIN', '.N.'])
    if kind == 3 and lit: s.put(3, 8, 'c'); s.put(9, 8, 'c')                    # Mk3: cyan knuckles
    if state == 'disabled':                                                     # the fingers hang open and down
        shift_rect(s, 0, 5, 0, 8, -1, 1); shift_rect(s, 8, 13, 0, 8, 1, 1)
    return s

def finish_seg(s, state, i, name, kind):
    L = LOOK[kind]
    if state == 'damaged' and name == 'fore':                                   # the forearm is the one that sparks: a cracked shell, the cable torn loose
        crack(s, [(3, 9), (5, 11), (4, 13)], L['w0'])
        for (x, y) in ((1, 9), (0, 10), (0, 11)): s.put(x, y, L['k0'])
        s.erase(1, 10); s.erase(1, 11)
        sx, sy = [(6, 10), (1, 12)][i % 2]
        s.put(sx, sy, 'H'); s.put(sx + 1, sy, 'y'); s.put(sx - 1, sy, 'y'); s.put(sx, sy - 1, 'y'); s.put(sx, sy + 1, 'o')
    if state == 'disabled':
        s = s.sub(dict(DARK, **{'N': 'N', 'j': 'J', 'J': 'I', 'I': 'N', 'c': 'C', 'C': 'B', 'B': 'N', 'H': 'M', ']': '%', '%': '[', '[': 'D', '&': 'W'}))
        soot = {'upper': (4, 12), 'fore': (3, 10), 'head': (5, 9)}[name]
        s.put(soot[0], soot[1], 'D'); s.put(soot[0] + 1, soot[1] + 1, 'D')
    s = s.copy(); outline_all(s)
    return s

SEGS = {'upper': seg_upper, 'fore': seg_fore, 'head': seg_head}
SEG_ANIMS = {   # the game draws: idle, or heal on the head; the forearm's damaged under half hp; off with no power; disabled at hp 0
 'upper': [('idle', 'idle', 1, 0), ('off', 'off', 1, 0), ('disabled', 'disabled', 1, 0)],
 'fore':  [('idle', 'idle', 1, 0), ('off', 'off', 1, 0), ('damaged', 'damaged', 2, 6), ('disabled', 'disabled', 1, 0)],
 'head':  [('idle', 'idle', 1, 0), ('heal', 'heal', 2, 5), ('off', 'off', 1, 0), ('disabled', 'disabled', 1, 0)],
}
GP = 8

def seg_frame(kind, name, state, i):
    return finish_seg(SEGS[name](kind, state, i), state, i, name, kind)

def seg_glow(kind, name, state, i):
    w, h, p, t = SEG[name]
    g = Rgba(w + 2 * GP, h + 2 * GP)
    if name != 'head' or state in ('off', 'disabled'): return g
    k = {'heal': (1.0, 0.7)[i % 2], 'idle': 0.45}[state]
    glow(g, GP + 6.5, GP + 5.5, 7.0, LOOK[kind]['rgb'], 0.8 * k, 2.0)
    glow(g, GP + 6.5, GP + 5.5, 2.5, (255, 255, 255), 0.35 * k, 1.6)
    return g

def export_segments(kind, outdir):
    cid = 'medbay_mk%d' % kind
    for name in ('upper', 'fore', 'head'):
        w, h, p, t = SEG[name]
        frames, gfr, anims, ganims = [], [], {}, {}
        for (an, st, n, fps) in SEG_ANIMS[name]:
            anims[an] = [len(frames), n, fps]
            for i in range(n): frames.append(seg_frame(kind, name, st, i))
            if name == 'head' and st not in ('off', 'disabled'):
                ganims[an] = [len(gfr), n, fps]
                for i in range(n): gfr.append(seg_glow(kind, name, st, i))
        save(sheet(frames, len(frames), w, h), '%s/%s_%s.png' % (outdir, cid, name))
        anchors = {'pivot': list(p), ('emitter' if name == 'head' else 'tip'): list(t)}
        J = {'frame': [w, h], 'anims': anims, 'anchors': anchors, 'notes': SEG_NOTES[name] % cid}
        if gfr:
            save_strip(gfr, '%s/%s_%s_glow.png' % (outdir, cid, name))
            J['glow'] = {'image': '%s_%s_glow.png' % (cid, name), 'frame': [w + 2 * GP, h + 2 * GP], 'offset': [-GP, -GP], 'anims': ganims}
        with open('%s/%s_%s.json' % (outdir, cid, name), 'w') as f: json.dump(J, f, indent=1); f.write('\n')

SEG_NOTES = {
 'upper': 'The upper arm of %s, drawn pointing UP: anchors.pivot is the shoulder (on the base\'s middle), anchors.tip the elbow; the game turns it about the shoulder '
          'toward the elbow of the pose (Visuals.arm_pose). The shoulder joint cap is in this sprite; a cable runs down its right side.',
 'fore':  'The forearm of %s, drawn pointing UP: anchors.pivot is the elbow, anchors.tip the wrist. Its damaged frames (2) are the arm\'s sparks: a cracked shell and the cable torn loose.',
 'head':  'The head of %s: a soft gripper, two fingers curled round the emitter (a glowing orb; Mk3 a crystal) and the thumb under it, drawn pointing UP: '
          'anchors.pivot is the wrist, anchors.emitter where the soft beam starts. heal (2): the emitter pulses; off: dark; disabled: dark, the fingers hang open. The glow is the emitter\'s light.',
}

ALL = [MedArm2, MedArm3]

def export_arms(outdir=None):
    """the segments of both arms (the bases are exported with the other components)."""
    outdir = outdir or ART + '/components'
    for k in (2, 3): export_segments(k, outdir)

# ============================================================ the pose: the same 2-bone solve as Visuals.arm_pose (scripts/view/visuals.gd)
R_REST = 0.50            # cells from the shoulder to the wrist when folded (a V that stays over the base)
R_FAR = 1.50             # the farthest the wrist reaches (the emitter is a head's length further: about 1.9 cells)
SIDE = 1                 # the elbow bends to the left of the reach (counter-clockwise)
def ang_dir(a): return (math.sin(a), -math.cos(a))

def pose(angle, ext=0.0, dist=0.0, sway=0.0, state='idle'):
    """-> dict of cell offsets from the shoulder: elbow, wrist, emitter, and the angles of the upper arm, the forearm and the head (clockwise from up)."""
    l1, l2 = bone('upper'), bone('fore')
    far = max(R_REST, min(dist - 0.6, R_FAR)) if dist > 0 else R_REST
    r = R_REST + (far - R_REST) * ext
    if state == 'disabled': r = R_REST * 0.75
    th = angle + sway
    c = (l1 * l1 + r * r - l2 * l2) / (2 * l1 * r)
    a = math.acos(max(-1.0, min(1.0, c)))
    ua = th - SIDE * a
    ex, ey = ang_dir(ua); elbow = (l1 * ex, l1 * ey)
    wx, wy = ang_dir(th); wrist = (r * wx, r * wy)
    fa = math.atan2(wrist[0] - elbow[0], -(wrist[1] - elbow[1]))
    ha = th
    if state == 'disabled': ha = fa - SIDE * 1.1
    w, h, p, t = SEG['head']
    ox, oy = ang_dir(ha); reach = (p[1] - t[1]) / 16.0
    return dict(elbow=elbow, wrist=wrist, emitter=(wrist[0] + ox * reach, wrist[1] + oy * reach), upper=ua, fore=fa, head=ha)

# ============================================================ the preview sheet (3x): the segments, the rest pose, three reaches, both lines, the states
def _turn_glow(o, deg, cx, cy):
    n = Rgba(o.w, o.h); t = math.radians(deg); co, si = math.cos(t), math.sin(t)
    for y in range(o.h):
        for x in range(o.w):
            dx, dy = x + .5 - cx, y + .5 - cy
            xi, yi = int(math.floor(co * dx + si * dy + cx)), int(math.floor(-si * dx + co * dy + cy))
            if 0 <= xi < o.w and 0 <= yi < o.h: n.p[y][x] = list(o.p[yi][xi])
    return n

def _place(img, glows, spr, piv, at, ang, g=None, shadow=0):
    """blit segment `spr` turned by `ang` (radians, clockwise from up) about its pivot `piv`, with the pivot on `at` (canvas px); a dark copy `shadow` px down-right first."""
    from compose import rotate
    S = 2 * max(spr.w, spr.h) + 3; h = S // 2
    cv = Spr(S, S); cv.stamp(h - piv[0], h - piv[1], [''.join('.' if c == 'K' else c for c in r) for r in spr.rows()])
    r = rotate(cv, int(round(math.degrees(ang))) % 360, h, h); outline_all(r)
    x0, y0 = int(round(at[0])) - h, int(round(at[1])) - h
    if shadow:
        for y in range(S):
            for x in range(S):
                if r.g[y][x] != '.': img.over(x0 + x + shadow, y0 + y + shadow, (0, 0, 0, 110))
    img.blit_spr(r, x0, y0)
    if g is not None:
        G = Rgba(S + 2 * GP, S + 2 * GP); G.blit_rgba(g, h - piv[0], h - piv[1])
        glows.append((_turn_glow(G, math.degrees(ang), h + GP, h + GP), x0 - GP, y0 - GP))

def draw_arm(img, kind, base_xy, ang, ext=0.0, dist=0.0, sway=0.0, state='idle', i=0, glows=None, heal=None):
    """the base at base_xy (its top-left, canvas px) and the arm posed over it; returns the emitter (canvas px). Like Visuals._draw_arm."""
    glows = [] if glows is None else glows
    import comp_base
    c = (MedArm2 if kind == 2 else MedArm3)()
    bstate = {'idle': 'on', 'heal': 'on', 'off': 'off', 'damaged': 'damaged', 'disabled': 'disabled'}[state]
    bf = c.frame(bstate, i % (2 if bstate == 'damaged' else 4) if bstate in ('on', 'damaged') else 0)
    img.blit_spr(bf, base_xy[0], base_xy[1])
    gl = c.glow_frame(bstate, i % 2 if bstate == 'damaged' else i % 4) if bstate in ('on', 'damaged') else None
    if gl is not None: glows.append((gl, base_xy[0] - 8, base_xy[1] - 8))
    P = pose(ang, ext, dist, sway, state)
    sh = (base_xy[0] + 16, base_xy[1] + 16)
    at = lambda v: (sh[0] + v[0] * 16, sh[1] + v[1] * 16)
    seg_state = {'idle': 'idle', 'heal': 'idle', 'off': 'off', 'damaged': 'idle', 'disabled': 'disabled'}[state]
    shadow = 2
    _place(img, glows, seg_frame(kind, 'upper', seg_state, 0), SEG['upper'][2], sh, P['upper'], shadow=shadow)
    fst = 'damaged' if state == 'damaged' else seg_state
    _place(img, glows, seg_frame(kind, 'fore', fst, i % 2), SEG['fore'][2], at(P['elbow']), P['fore'], shadow=shadow)
    hst = {'heal': 'heal', 'idle': 'idle', 'off': 'off', 'damaged': 'heal' if heal or (heal is None and ext > 0) else 'idle', 'disabled': 'disabled'}[state]
    _place(img, glows, seg_frame(kind, 'head', hst, i % 2), SEG['head'][2], at(P['wrist']), P['head'],
           g=seg_glow(kind, 'head', hst, i % 2) if hst not in ('off', 'disabled') else None, shadow=shadow)
    return at(P['emitter'])

def _beam(img, a, b, rgb):
    """the soft beam and the ring on the patient, as ArmFx.draw_beams draws them (here at 1 source px)."""
    n = int(max(abs(b[0] - a[0]), abs(b[1] - a[1]), 1))
    for k in range(n + 1):
        x = a[0] + (b[0] - a[0]) * k / n; y = a[1] + (b[1] - a[1]) * k / n
        for dx in (-1, 0, 1):
            for dy in (-1, 0, 1): img.add(int(x) + dx, int(y) + dy, rgb + (40,))
        img.over(int(x), int(y), rgb + (190,))
    g = Rgba(40, 40); glow(g, 20, 20, 14, rgb, 0.22, 1.4); img.blit_rgba(g, int(b[0]) - 20, int(b[1]) - 20, 1, add=True)
    for k in range(48):
        t = 2 * math.pi * k / 48; img.over(int(b[0] + 13 * math.cos(t)), int(b[1] + 13 * math.sin(t)), rgb + (150,))

def _scene(kind, ang, ext, dist, state, i=0, patient=None, W=128, H=96, bx=24, by=32):
    """a room floor with the arm on its base and, when it heals, the patient (a crew member) at `dist` cells along `ang`."""
    img = Rgba(W, H, RGB['F'] + (255,))
    for y in range(H):
        for x in range(W):
            if x % 16 == 0 or y % 16 == 0: img.p[y][x] = list(RGB['G']) + [255]
    glows = []
    sh = (bx + 16, by + 16)
    if patient:
        px, py = sh[0] + math.sin(ang) * dist * 16, sh[1] - math.cos(ang) * dist * 16
        from sp_compose import SKit, render
        from sheet_species import draw_fig
        f, g = render(patient, 6, int(math.degrees(ang)) + 180, int(math.degrees(ang)) + 180, 'tool', 'multi_tool', 'hair', tint=(232, 145, 58))
        draw_fig(img, f, g, int(px) - 16, int(py) - 16, 1, crop=33)
    e = draw_arm(img, kind, (bx, by), ang, ext, dist, 0.0, state, i, glows)
    for (g, x, y) in glows: img.blit_rgba(g, x, y, 1, add=True)
    if patient and state in ('heal', 'damaged'): _beam(img, e, (px, py), LOOK[kind]['rgb'])
    return img

def draw_sheet(path, K=3):
    """the 3x preview: per line the segments with their frames, the base, the rest pose, three reaches and the off / damaged / disabled poses."""
    from sheet_v2 import text
    from sp_compose import SKit
    from sp_items import kit_items
    from sheet_races1 import ALL as SPECIES
    who = SKit(dict(SPECIES)['human'](), kit_items())
    blocks = []
    for kind, title in ((2, 'MEDBAY MK2  STANDARD LINE: CLEAN WHITE AND TEAL  A GREEN EMITTER'), (3, 'HALO ARM MK3  NEON LINE: NAVY  CYAN EDGES AND FACETS  A CYAN CRYSTAL')):
        segs = []
        for name in ('upper', 'fore', 'head'):
            for (an, st, n, fps) in SEG_ANIMS[name]:
                for i in range(n):
                    segs.append((seg_frame(kind, name, st, i), seg_glow(kind, name, st, i) if name == 'head' else None, name.upper(), an.upper() + ((' %d' % i) if n > 1 else '')))
        c = (MedArm2 if kind == 2 else MedArm3)()
        for st, n in (('on', 4), ('off', 1), ('damaged', 2), ('disabled', 1)):
            for i in range(n): segs.append((c.frame(st, i), c.glow_frame(st, i) if st in ('on', 'damaged') else None, 'BASE', st.upper() + ((' %d' % i) if n > 1 else '')))
        poses = [(_scene(kind, 0.5, 0.0, 0.0, 'idle', W=80, bx=24), 'REST', 'FOLDED  IT SWAYS'),
                 (_scene(kind, 1.2, 1.0, 2.4, 'heal', 0, who, W=96), 'REACH 1', 'PATIENT 2.4 CELLS'),
                 (_scene(kind, 1.75, 1.0, 4.5, 'heal', 1, who), 'REACH 2', 'PATIENT 4.5 CELLS'),
                 (_scene(kind, 2.5, 1.0, 3.2, 'heal', 0, who, by=16), 'REACH 3', 'PATIENT 3.2 CELLS'),
                 (_scene(kind, 1.75, 0.45, 4.5, 'heal', 1, who), 'UNFOLDING', 'EASED  HALF WAY'),
                 (_scene(kind, 0.5, 0.0, 0.0, 'off', W=80, bx=24), 'OFF', 'LIGHTS DEAD'),
                 (_scene(kind, 1.75, 1.0, 3.6, 'damaged', 1, who, W=112), 'DAMAGED', 'THE FOREARM SPARKS'),
                 (_scene(kind, 0.5, 0.0, 0.0, 'disabled', W=80, bx=24), 'DISABLED', 'SLUMPED')]
        blocks.append((title, segs, poses))
    H = 30 + sum(34 + 34 * K + 42 + 96 * K + 30 for _ in blocks) + 20
    SW = 2900
    img = Rgba(SW, H, RGB['F'] + (255,))
    text(img, 20, 16, 'HEALING ARMS: AN ARTICULATED MEDICAL ARM ON A 2X2 BASE. FOUR SPRITES (BASE  UPPER ARM  FOREARM  HEAD) POSED AS A 2-BONE CHAIN. 3X', 'H', 3)
    y = 44
    for title, segs, poses in blocks:
        text(img, 20, y, title, 'a', 4); y += 34
        x = 20
        for spr, g, lab, lab2 in segs:
            cw = max(spr.w * K, 8 * max(len(lab), len(lab2)))
            img.blit_spr(spr, x, y, K)
            if g is not None:
                off = (g.w - spr.w) // 2
                img.blit_rgba(g.scaled(K), x - off * K, y - off * K, 1, add=True)
            text(img, x, y + 34 * K, lab, 'L', 2); text(img, x, y + 34 * K + 12, lab2, 'M', 2)
            x += cw + 14
        y += 34 * K + 42
        x = 20
        for a, lab, sub in poses:
            img.blit_rgba(a.scaled(K), x, y)
            text(img, x + 6, y + 6, lab, 'H', 3); text(img, x + 6, y + a.h * K - 18, sub, 'L', 2)
            x += a.w * K + 12
        y += 96 * K + 30
    img.save(path)

if __name__ == '__main__':
    if '--sheet' in sys.argv:
        draw_sheet(sys.argv[sys.argv.index('--sheet') + 1])
        sys.exit(0)
    import comp_base
    for C in ALL:
        c = C()
        _, _, J = comp_base.export(c)
        print(c.id, J['frame'], list(J['anims']))
    export_arms()
