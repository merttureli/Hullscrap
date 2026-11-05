"""The 39 new guns of G2 (briefs/guns_g2_list.md, docs/GUNS.md 5 and 7): one recipe each, composed from the gun_mod modules, plus their breeches.
Run `python3 gun_recipes_g2.py [outdir]`: writes `<id>_out.*` and `<id>_barrel.*` (png, json, glow) of the 39 guns, the breech `<id>.png/.json/_glow.png` of the 39 and of the three Baron guns
(sovereign_turret, gilded_lance, baron_tithe_gun). Same art format as gun_recipes.py (art/README.md "Guns in their new shapes"), plus the version anims:
  chain  barrel anim `spin` (4 frames, fps 0): the rotary cluster a quarter turn in 4 steps; the game steps it faster with each chain step (the heat glows on `lit` in the code).
  charge barrel anim `charge` (4 frames, fps 0): frame k lights k of the 3 capacitor rings (slug_spinal stores 2: 3 frames, 0-2).
  pd     PD tracking is the barrel turned about its pivot (a turret); Mk II and Mk III add a radar mast, a second dish, ammo boxes and a clamp.
  broadside, strip: `pivots_on_base` + `stagger_s`; pods: the hatch lids are the barrel (swarm_pod has 8 small lids)."""
import os, sys
import gun_mod as gm
import gun_race as gr_
import gun_recipes as gr
import gun_breech as gb
from gun_mod import plate, tube, band, bolt_row, round_disc, lens_up, fam_ring, hurt_tube, wreck_tube, move
from mach import recess
from lines_kit import circle, ring as ringpx
from px import *

BEFORE = set(gr.GUNS)
gr.NOTES.update({'spinal': 'a spinal sleeve (2x6 cells): two tapering armour plates along the barrel channel with conduits of the family colour: a FIXED gun that must face the target',
                 'strip': 'a gun strip (8x1 cells): a long low bar with five small sleeved ports on one gimbal rail: a FIXED gun for a flank wall'})
R0 = gr.R
def R(name, shape, fam, line, base, barrel, race=None, slots=(), label=None, bv=None, extra=(), note='', **kw):
    g = R0(name, shape, fam, line, base, barrel, race, slots, label, **kw)
    g.breech_ver, g.extra, g.extra_note = bv, list(extra), note
    return g

# ------------------------------------------------------------------ new parts
gm.BARREL_PARTS['multi'] = gm.tube_multi

def tip_nose(c):
    """a warhead nose (red band, white tip) seated in the muzzle: the torpedo."""
    s = c.s; cx, top, w = gr_._tip(c); o = c.st.rc
    s.stamp(cx - 3, top - 7 + o, art("""
...HH...
..H33L..
.H3322L.
.332221.
.332221.
.311111.
"""))
    c.muzzles[:] = [(cx, top - 7 + o)]; c.lightglow(cx, top - 4 + o, 4, 0.4)
gm.BARREL_PARTS['tip_nose'] = tip_nose

def tip_needle(c):
    """a needle of the family colour standing on the muzzle: the ion needle."""
    s = c.s; cx, top, w = gr_._tip(c); o = c.st.rc
    s.vline(cx, top - 9 + o, 10, '2'); s.vline(cx - 1, top - 4 + o, 5, 'M'); s.vline(cx + 1, top - 4 + o, 5, 'S')
    s.put(cx, top - 10 + o, '4'); s.put(cx, top - 9 + o, '3')
    c.muzzles[:] = [(cx, top - 10 + o)]; c.lightglow(cx, top - 6 + o, 4, 0.45)
gm.BARREL_PARTS['tip_needle'] = tip_needle

def lance_cap(c, top, bot, w=11, n=2):
    """the spinal lance with n capacitor rings (the charge version): lit one by one (st.lit 0..n), the rest are steel collars."""
    s = c.s; cx = c.px; o = c.st.rc
    x0 = cx - w // 2
    tube(s, x0, top + 10 + o, w, bot - top - 10, 'MMSSSWWE')
    lit = 0 if c.st.fire else (c.st.lit or 0)
    j = 0
    for k, y in enumerate(range(bot - 12, top + 18, -9)):
        if k % 2 == 0 and j < n:
            on = c.st.powered and j < lit
            fam_ring(s, x0 - 1, y + o, w + 2, 3, on)
            if on: c.lightglow(cx, y + 1 + o, 4.5, 0.5, sx=1.6)
            j += 1
        else: band(s, x0 - 2, y + o, w + 4, 4 if k % 2 else 3)
    for px_ in (x0 - 1, x0 + w - 2):
        plate(s, px_, top + 1 + o, 3, 11, cham=False); s.put(px_, top + 1 + o, '9')
    gem = art("""
..3..
.342.
33421
.221.
..1..
""") if gm.lens_mode(c) != 'dead' else art("""
..W..
.WEE.
WEEED
.EED.
..D..
""")
    s.stamp(cx - 2, top + 3 + o, gem)
    band(s, x0 - 1, top + 9 + o, w + 2, 3)
    c.muzzles.append((cx, top + 3 + o)); c.lightglow(cx, top + 5 + o, 5, 0.6)
    c.hurts.append(hurt_tube(x0, w, None, top + 12, band=False))
    c.hurts.append(lambda s_, c_: move(s_, x0 + w - 2, top + 1, 3, 11, 2, 2))
    c.wrecks.append(wreck_tube(top + 22, x0, w))
gm.BARREL_PARTS['lance_cap'] = lance_cap

def pd_head_t(c, tier=1, r=6):
    """point defence head by tier: Mk I the dome and its radar dish; Mk II + a radar mast; Mk III + a second dish on the other flank."""
    s = c.s; cx, cy = c.px, c.py
    neck = gm.pd_head(c, r)
    if tier >= 2:
        mx = cx - r + 1
        s.vline(mx, cy - r - 3, 6, 'M'); s.vline(mx + 1, cy - r - 3, 6, 'W'); s.put(mx, cy - r - 4, '3'); s.put(mx - 1, cy - r - 3, 'L'); s.put(mx + 2, cy - r - 3, 'L')
        c.lightglow(mx + .5, cy - r - 4, 3, 0.5); neck = min(neck, cy - r - 3)
    if tier >= 3:
        dx, dy = cx - r + 2, cy + 2
        circle(s, dx + .5, dy + .5, 2.5, 'M'); ringpx(s, dx + .5, dy + .5, 1.2, 2.5, 'S'); s.put(dx, dy, '3')
        c.lightglow(dx + .5, dy + .5, 3, 0.45)
        s.hline(cx - 3, cy + r - 2, 7, 'W')
    return neck
gm.BARREL_PARTS['pd_head_t'] = pd_head_t

def pd_shroud(c):
    """add-on (PD Mk III): a clamp joining the twin barrels and a muzzle collar."""
    s = c.s; cx = c.px; o = c.st.rc
    top = min(m[1] for m in c.muzzles) - o
    plate(s, cx - 6, top + 5 + o, 13, 3, True, 'M', 'S', 'W'); s.hline(cx - 5, top + 6 + o, 11, '9')
    plate(s, cx - 5, top + 11 + o, 11, 2, cham=False)
gm.BARREL_PARTS['pd_shroud'] = pd_shroud

def m_pdbox(c, x, y, w, h):
    """a PD ammo box on a corner pad of the ring base: a steel box with green ready lamps."""
    s = c.s
    plate(s, x, y, w, h - 2); s.hline(x + 1, y + 2, w - 2, 'D')
    s.put(x + 2, y + 5, '2'); s.put(x + 4, y + 5, '2'); s.put(x + 6, y + 5, '3'); c.lightglow(x + 4, y + 5, 3, 0.3)
gm.PARTS['m_pdbox'] = m_pdbox

# ------------------------------------------------------------------ shorthands
FIXED = ('breech_fixed', {})
def fx(w, **k): return ('breech_fixed', dict(w=w, **k))
CM = lambda a, b, **k: ('casemate4', dict(parts=(a, b), **k))
LP = lambda a, b: ('casemate2', dict(parts=(a, b)))
HV = lambda a, b: ('heavy', dict(parts=(a, b)))
RING2, RING3 = ('ring', dict(cells=2)), ('ring', dict(cells=3))
HBH = fx(19, heavy=True)
S, STD, N = 'scrap', 'standard', 'neon'
CHAIN = [('spin', 'spin', 4, 0, False)]
CHARGE = [('charge', 'charge', 4, 0, True)]
N_CHAIN = ' spin: 4 frames (the rotary cluster a quarter turn per frame, fps 0): the game plays it faster with each chain step (1-3), and the muzzles glow with `lit` in the code.'
N_CHARGE = ' charge: 4 frames (fps 0): frame k lights k of the 3 capacitor rings; fire releases them.'

# ------------------------------------------------------------------ laser
R('laser_light', 'point', 'laser', STD, RING2, (17, 17, ('hub', {}), ('short', dict(w=7, rings=1))), label='LASER LIGHT')
R('laser_mk3', 'casemate', 'laser', STD, CM('coolant', 'vent', mk3=True), (23, 38, fx(15, heavy=True), ('twin', dict(coil=True))), label='LASER MK III', bv='mk')
R('laser_burst', 'broadside', 'laser', STD, ('casemate6', dict(n=3, parts=('cells', 'sensor'))), (15, 30, fx(11), ('single', dict(w=7, rings=2))), label='BURST LASER', bv='burst', stagger=0.07)
R('laser_chain', 'casemate', 'laser', STD, CM('cells', 'vent'), (19, 40, FIXED, ('rotary', {})), label='CHAIN LASER', bv='chain', extra=CHAIN, note=N_CHAIN)
R('laser_heavy', 'heavy', 'laser', STD, HV('cells', 'vent'), (25, 47, HBH, ('single', dict(w=15, rings=3, heavy=True)), [('brake', {})]), label='HEAVY LASER', bv='heavy')
R('laser_long', 'long', 'laser', N, LP('cells', 'sensor'), (17, 86, fx(13), ('long', {})), label='LONG LASER')
R('laser_lance', 'spinal', 'laser', STD, ('spinal', {}), (17, 104, fx(13), ('lance', {})), label='LANCE LASER', bv='lance')

# ------------------------------------------------------------------ pulse
R('pulse_light', 'point', 'pulse', S, RING2, (17, 17, ('hub', {}), ('short', dict(w=7, rings=1))), label='LIGHT PULSE')
R('pulse_mk3', 'casemate', 'pulse', STD, CM('coolant', 'caps', mk3=True), (23, 38, fx(15, heavy=True), ('multi', dict(n=3, w=4, gap=3, coil=True))), label='PULSE MK III', bv='mk')
R('pulse_battery', 'broadside', 'pulse', STD, ('casemate6', dict(n=3, parts=('drum', 'cells'))), (15, 30, fx(11), ('single', dict(w=9, rings=1))), label='PULSE BATTERY', bv='burst', stagger=0.07)
R('pulse_chain', 'sponson', 'pulse', STD, ('sponson', {}), (19, 44, ('yoke', {}), ('rotary', {})), label='CHAIN PULSE', bv='chain', extra=CHAIN, note=N_CHAIN)
R('pulse_heavy', 'heavy', 'pulse', STD, HV('drum', 'cells'), (25, 47, HBH, ('single', dict(w=15, rings=3, heavy=True)), [('brake', {})]), label='HEAVY PULSE', bv='heavy')

# ------------------------------------------------------------------ ion
R('ion_needle', 'long', 'ion', N, LP('cells', 'sensor'), (17, 92, fx(13), ('long', dict(w=7)), [('tip_needle', {})], 10), label='ION NEEDLE')
R('ion_mk2', 'casemate', 'ion', STD, CM('caps', 'sensor'), (21, 38, FIXED, ('twin', dict(gap=4))), label='ION BLAST MK2', bv='mk')
R('ion_heavy', 'heavy', 'ion', STD, HV('caps', 'vent'), (25, 47, HBH, ('single', dict(w=15, rings=4, heavy=True)), [('brake', {})]), label='HEAVY ION', bv='heavy')
R('ion_charge', 'sponson', 'ion', N, ('sponson', {}), (19, 35, ('yoke', {}), ('capacitor', {})), label='CHARGE ION', bv='charge', extra=CHARGE, note=N_CHARGE)

# ------------------------------------------------------------------ flak
R('flak_turret', 'dome', 'flak', S, RING3, (27, 33, ('dome_head', {}), ('triple', {})), label='FLAK TURRET')
R('flak_mk2', 'casemate', 'flak', STD, CM('drum', 'vent'), (21, 36, FIXED, ('triple', dict(w=4, gap=2))), label='FLAK MK2', bv='mk')
R('flak_heavy', 'heavy', 'flak', STD, HV('drum', 'drum'), (25, 44, HBH, ('single', dict(w=15, rings=2, heavy=True)), [('tip_flare', dict(extra=3))], 6), label='HEAVY FLAK', bv='heavy')
R('flak_battery', 'broadside', 'flak', S, ('casemate6', dict(n=3, parts=('drum', 'drum'))), (15, 32, fx(11), ('single', dict(w=9, rings=1)), [('tip_flare', dict(extra=2))], 5), label='FLAK BATTERY', bv='burst', stagger=0.07)

# ------------------------------------------------------------------ missile
R('missile_pod', 'pod', 'missile', STD, ('pod', {}), (64, 8, ('lids', {}), None), label='MISSILE POD')
R('artemis_mk2', 'casemate', 'missile', STD, CM('caps', 'sensor'), (21, 36, FIXED, ('twin', dict(w=7, gap=3))), label='ARTEMIS MK2', bv='mk')
R('swarm_pod', 'pod', 'missile', STD, ('pod', dict(n=8)), (64, 8, ('lids', dict(n=8)), None), label='SWARM POD')
R('torpedo', 'heavy', 'missile', STD, HV('cells', 'drum'), (25, 54, HBH, ('single', dict(w=15, rings=2, heavy=True)), [('tip_nose', {})], 8), label='TORPEDO', bv='heavy')

# ------------------------------------------------------------------ beam
R('beam_light', 'sponson', 'beam', N, ('sponson', {}), (19, 33, ('yoke', {}), ('single', dict(w=9, rings=3))), label='LIGHT BEAM')
R('beam_mk2', 'casemate', 'beam', STD, CM('coolant', 'sensor'), (21, 38, FIXED, ('twin', dict(gap=4))), label='BEAM MK2', bv='mk')
R('beam_long', 'long', 'beam', N, LP('cells', 'sensor'), (17, 88, fx(13), ('long', {})), label='LONG BEAM')
R('beam_spinal', 'spinal', 'beam', N, ('spinal', {}), (17, 104, fx(13), ('lance', {})), label='SPINAL BEAM', bv='lance')

# ------------------------------------------------------------------ slug
R('slug_gun', 'casemate', 'slug', S, CM('drum', 'vent'), (19, 35, FIXED, ('single', dict(w=11, rings=3))), label='SLUG GUN')
R('slug_mortar', 'casemate', 'slug', S, CM('drum', 'cells'), (23, 34, fx(15), ('single', dict(w=15, rings=2)), [('tip_flare', dict(extra=2))], 5), label='MORTAR')
R('slug_rail', 'long', 'slug', STD, LP('cells', 'sensor'), (17, 88, fx(13), ('long', {}), [('tip_fork', {})], 8), label='RAIL')
R('slug_chain', 'sponson', 'slug', S, ('sponson', {}), (19, 44, ('yoke', {}), ('rotary', {})), label='CHAIN SLUG', bv='chain', extra=CHAIN, note=N_CHAIN)
R('slug_spinal', 'spinal', 'slug', STD, ('spinal', {}), (17, 104, fx(13), ('lance_cap', dict(n=2))), label='SPINAL RAIL', bv='lance', extra=[('charge', 'charge', 3, 0, True)],
  note=' charge: 3 frames (fps 0): frame k lights k of the 2 capacitor rings (this gun stores 2); fire releases them.')

# ------------------------------------------------------------------ point defence (tiers grow by adding parts)
PDB = lambda *xs: [('pdbox', x, 21, 8, 10) for x in xs]
R('pd_mk1', 'point', 'pd', STD, RING2, (17, 19, ('pd_head_t', dict(tier=1)), ('pd_twin', dict(gap=3))), label='POINT DEFENCE MK I')
R('pd_mk2', 'point', 'pd', STD, RING2, (17, 21, ('pd_head_t', dict(tier=2)), ('pd_twin', dict(gap=3))), slots=PDB(23), label='POINT DEFENCE MK II', bv='mk')
R('pd_mk3', 'point', 'pd', STD, RING2, (17, 21, ('pd_head_t', dict(tier=3)), ('pd_twin', dict(gap=3)), [('pd_shroud', {})]), slots=PDB(1, 23), label='POINT DEFENCE MK III', bv='mk')

# ------------------------------------------------------------------ strips and a heavy battery
R('gun_strip', 'strip', 'pulse', S, ('strip', dict(n=5)), (11, 14, fx(7), ('single', dict(w=5, rings=1))), label='GUN STRIP', bv='strip', stagger=0.07)
R('laser_strip', 'strip', 'laser', N, ('strip', dict(n=5)), (11, 14, fx(7), ('single', dict(w=5, rings=1))), label='LASER STRIP', bv='strip', stagger=0.07)
R('heavy_battery', 'broadside', 'slug', STD, ('casemate6', dict(n=3, parts=('drum', 'drum'))), (19, 36, HBH, ('single', dict(w=11, rings=2, heavy=True)), [('brake', {})]), label='HEAVY BATTERY', bv='heavy_burst', stagger=0.1)

GUNS2 = {k: v for k, v in gr.GUNS.items() if k not in BEFORE}
BARONS = {'sovereign_turret': None, 'gilded_lance': None, 'baron_tithe_gun': 'heavy'}
for k, v in BARONS.items(): gr.GUNS[k].breech_ver = v

def export_all(outdir=gr.OUTDIR):
    assert len(GUNS2) == 39, len(GUNS2)
    for pid, g in GUNS2.items():
        gr.export(g, outdir); gb.export(g, outdir)
        print(pid)
    for pid in BARONS: gb.export(gr.GUNS[pid], outdir); print(pid, 'breech')

if __name__ == '__main__':
    export_all(sys.argv[1] if len(sys.argv) > 1 else gr.OUTDIR)
