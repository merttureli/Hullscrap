"""Every existing gun in its new shape (docs/GUNS.md 8): one recipe per gun, composed from the gun_mod modules and the gun_race signatures.
`GUNS` maps a weapon id to a Gun; `export_all()` writes `art/components/<id>_out.*` and `<id>_barrel.*` (png, json, glow). The inside halves
(`<id>.png`) are not touched: their sizes do not change.

A recipe: R(id, shape, family, line, base=(name, kwargs), barrel=(w, reach, head, tube, add, top), race=livery key, slots=[(motif, x, y, w, h)])."""
import json, os, sys
import gun_mod as gm
import gun_race as gr
import gun_samples as gs
from gun_mod import Ctx, Look, St, FLANGE
from px import *

OUTDIR = ART + '/components'
GUNS = {}

class G(gs.Gun):
    """gun_samples.Gun plus a race livery and motif slots on the base."""
    def __init__(s, name, shape, fam='laser', line='standard', base=('casemate4', {}), barrel=None, label=None, breech=None, race=None, slots=(), arcdeg=None, stagger=0.0):
        super().__init__(name, shape, fam, line, base, barrel, label)
        s.race, s.slots, s.stagger = race, list(slots), stagger
        s.look = Look(line, fam, gr.LIV.get(race))
        if race in gr.STEEL: s.look.steel = dict(s.look.steel, **dict(zip('LMSWE', gr.STEEL[race])))
        s.arcdeg = arcdeg
    def variant(s, **kw):
        d = dict(name=s.name, shape=s.shape, fam=s.fam, line=s.line, base=s.base, barrel=s.bar, label=s.label, race=s.race, slots=s.slots, arcdeg=s.arcdeg, stagger=s.stagger)
        d.update(kw); return G(**d)
    def out(s, state='on', i=0):
        W, H = s.out_cells[0] * 16, s.out_cells[1] * 16 + FLANGE
        c = Ctx(W, H, s.look, St(state, i))
        name, kw = s.base
        gs.BASES[name](c, **kw)
        for (m, x, y, w, h) in s.slots: gm.PARTS['m_' + m](c, x, y, w, h)
        gm.flange(c, H - FLANGE - 1, W)
        return gm.finish(c), gm.glow_layer(c, gs.OPAD), c.pivots

def R(name, shape, fam, line, base, barrel, race=None, slots=(), label=None, **kw):
    """barrel = (w, reach, head, tube, add) [+ top]; head / tube are (module, kwargs)."""
    w, reach, head, tube = barrel[:4]
    add = list(barrel[4]) if len(barrel) > 4 else []
    top = barrel[5] if len(barrel) > 5 else 1
    b = dict(w=w, reach=reach, head=head, tube=tube, add=add, top=top) if tube else dict(w=w, reach=reach, head=head, tube=None, add=add, top=top)
    g = G(name, shape, fam, line, base, b, label or name.replace('_', ' ').upper(), race=race, slots=slots, **kw)
    GUNS[name] = g
    return g

FIXED = ('breech_fixed', {})
def fx(w): return ('breech_fixed', dict(w=w))
def fxl(w): return ('breech_liv', dict(w=w))
CM = lambda a, b: ('casemate4', dict(parts=(a, b)))

# ------------------------------------------------------------------ casemates 4x2 (fixed, gimbal 6)
R('laser_mk1', 'casemate', 'laser', 'standard', CM('cells', 'sensor'), (19, 35, FIXED, ('single', dict(rings=4))))
R('laser_mk2', 'casemate', 'laser', 'standard', CM('caps', 'vent'), (21, 36, FIXED, ('twin', {})))
R('pulse_mk1', 'casemate', 'pulse', 'standard', CM('cells', 'sensor'), (17, 35, FIXED, ('single', dict(w=9, rings=3))))
R('pulse_mk2', 'casemate', 'pulse', 'standard', CM('caps', 'sensor'), (19, 36, FIXED, ('twin', dict(gap=3))))
R('ion_blast_mk1', 'casemate', 'ion', 'standard', CM('caps', 'sensor'), (17, 38, FIXED, ('single', dict(w=9, rings=5, pitch=4))))
R('artemis_mk1', 'casemate', 'missile', 'standard', CM('cells', 'sensor'), (21, 36, FIXED, ('single', dict(w=15, rings=2))))
R('bolt_thrower_scrap', 'casemate', 'missile', 'scrap', CM('vent', 'cells'), (17, 36, FIXED, ('single', dict(w=11, rings=3))))
R('basalt_magma_spitter', 'casemate', 'slug', 'standard', CM('m_slab', 'm_furnace'), (21, 37, fxl(15), ('single', dict(w=13, rings=2)), [('liv_rings', dict(ys=(15,)))], 6), race='basalt')
R('emberkin_cinder_mortar', 'casemate', 'slug', 'standard', CM('m_furnace', 'cells'), (23, 36, fxl(15), ('single', dict(w=15, rings=2)), [('tip_flare', {})], 5), race='emberkin')
R('gauntling_arc_hammer', 'casemate', 'pulse', 'standard', CM('m_coil', 'sensor'), (23, 36, fxl(17), ('single', dict(w=15, rings=3, heavy=True)), [('liv_rings', dict(ys=(13, 23)))], 2), race='gauntling')
R('mire_bog_mortar', 'casemate', 'slug', 'standard', CM('m_steam', 'vent'), (21, 36, fxl(15), ('single', dict(w=13, rings=2)), [('tip_flare', {})], 5), race='mire')
R('sporeling_spore_cannon', 'casemate', 'pulse', 'standard', CM('m_sacs', 'cells'), (19, 36, fxl(15), ('single', dict(w=11, rings=1)), [('tip_flare', dict(extra=2))], 5), race='sporeling')
R('prismatic_refractor', 'casemate', 'pulse', 'neon', CM('m_crystal', 'sensor'), (19, 40, fxl(15), ('single', dict(w=9, rings=2)), [('tip_crystal', {})], 10), race='prismatic')

# ------------------------------------------------------------------ point turrets 2x2 (turret)
RING2 = ('ring', dict(cells=2))
S2 = lambda m: [(m, 1, 21, 8, 10), (m, 23, 21, 8, 10)]
R('laser_turret_mk1', 'point', 'laser', 'standard', RING2, (17, 17, ('hub', {}), ('short', dict(w=7, rings=1))))
R('rattle_burst_scrap', 'point', 'pulse', 'scrap', RING2, (17, 17, ('hub', {}), ('triple', dict(w=3, gap=1)), [], 2))
R('sovereign_turret', 'point', 'pulse', 'standard', RING2, (17, 19, ('hub_liv', {}), ('twin', dict(w=3, gap=2)), [('liv_rings', dict(ys=(8,)))], 1), race='barons', slots=S2('gilded'))
R('fenn_twitch_cannon', 'point', 'pulse', 'standard', RING2, (17, 17, ('hub_liv', {}), ('short', dict(w=5, rings=1))), race='fenn', slots=S2('lantern'))
R('kett_drone_picket', 'point', 'pd', 'standard', RING2, (17, 19, ('pd_liv', {}), ('pd_twin', dict(gap=3))), race='kett', slots=S2('hive'))
R('prismatic_glimmer_turret', 'point', 'pulse', 'standard', RING2, (17, 22, ('hub_liv', {}), ('short', dict(w=5, rings=1)), [('tip_crystal', dict(h=5))], 8), race='prismatic', slots=S2('crystal'))
R('human_flak_screen', 'point', 'pd', 'standard', RING2, (17, 19, ('pd_liv', {}), ('pd_twin', dict(gap=3))), race='human', slots=S2('concord'))

# ------------------------------------------------------------------ dome turrets 3x3 (turret)
RING3 = ('ring', dict(cells=3))
S3 = lambda m: [(m, 0, 34, 12, 14), (m, 36, 34, 12, 14)]
DOME = lambda tube, add=(), top=1: (27, 33, ('dome_liv', {}), tube, list(add), top)
R('leech_laser', 'dome', 'laser', 'standard', RING3, DOME(('single', dict(w=9, rings=2))), race='leech', slots=S3('tank'))
R('siren_ion_neon', 'dome', 'ion', 'neon', RING3, DOME(('triple', {})), race='siren', slots=S3('crystal'))
R('emberkin_flare_turret', 'dome', 'pulse', 'standard', RING3, DOME(('single', dict(w=9, rings=1)), [('tip_flare', {})], 5), race='emberkin', slots=S3('furnace'))
R('fenn_spark_lattice', 'dome', 'pulse', 'standard', RING3, DOME(('triple', dict(w=3, gap=3))), race='fenn', slots=S3('lantern'))
R('gauntling_tesla_picket', 'dome', 'ion', 'standard', RING3, DOME(('triple', dict(w=3, gap=3)), [('liv_rings', dict(ys=(14,)))]), race='gauntling', slots=S3('coil'))
R('grundl_barge_flak', 'dome', 'flak', 'standard', RING3, DOME(('triple', {})), race='grundl', slots=S3('amber'))
R('mire_mist_projector', 'dome', 'pulse', 'standard', RING3, DOME(('short', dict(w=9, rings=1)), [('tip_flare', {})], 5), race='mire', slots=S3('steam'))
R('sporeling_pollen_turret', 'dome', 'pulse', 'standard', RING3, DOME(('single', dict(w=9, rings=1)), [('tip_flare', dict(extra=2))], 5), race='sporeling', slots=S3('sacs'))

# ------------------------------------------------------------------ sponson 3x2 (swivel 180)
R('basalt_pumice_flak', 'sponson', 'flak', 'standard', ('sponson', {}), (19, 35, ('yoke_liv', {}), ('triple', dict(w=3, gap=2)), [], 1), race='basalt', slots=[('slab', 0, 21, 8, 11), ('slab', 40, 21, 8, 11)])

# ------------------------------------------------------------------ long barrels 2x4 (fixed, gimbal 3)
LONG = lambda w=13: (17, 86, fx(w), ('long', {}))
LP = lambda a, b: ('casemate2', dict(parts=(a, b)))
R('human_concord_railgun', 'long', 'slug', 'standard', LP('m_concord', 'sensor'), (17, 86, fxl(13), ('long', {}), [('tip_fork', {}), ('liv_rings', dict(ys=(24, 48), h=3))], 8), race='human')
R('gilded_lance', 'long', 'laser', 'standard', LP('m_gilded', 'cells'), (17, 88, fxl(13), ('long', {}), [('tip_crown', {}), ('liv_rings', dict(ys=(24, 48), h=3))], 8), race='barons')
R('heat_lance_neon', 'long', 'beam', 'neon', LP('cells', 'sensor'), LONG())
R('prismatic_prism_lens', 'long', 'beam', 'standard', LP('m_crystal', 'sensor'), (17, 90, fxl(13), ('long', {}), [('tip_crystal', {})], 12), race='prismatic')
R('emberkin_pyre_lance', 'long', 'beam', 'standard', LP('m_furnace', 'cells'), (17, 88, fxl(13), ('long', {}), [('tip_flare', dict(extra=2)), ('liv_rings', dict(ys=(24, 48), h=3))], 8), race='emberkin')
R('mire_steam_lance', 'long', 'laser', 'standard', LP('m_steam', 'vent'), (17, 88, fxl(13), ('long', {}), [('tip_vent', {}), ('liv_rings', dict(ys=(24, 48), h=3))], 8), race='mire')
R('breach_harpoon', 'long', 'slug', 'standard', LP('cells', 'sensor'), (17, 90, FIXED, ('long', {}), [('tip_barb', {})], 10))
R('grundl_grapple_harpoon', 'long', 'slug', 'standard', LP('m_amber', 'cells'), (17, 90, fxl(13), ('long', {}), [('tip_barb', {}), ('liv_rings', dict(ys=(30, 48), h=3))], 10), race='grundl')

# ------------------------------------------------------------------ heavy cannons 4x3 (fixed, gimbal 4)
HV = lambda a, b: ('heavy', dict(parts=(a, b)))
HB = (25, 47, ('breech_fixed', dict(w=19, heavy=True)), ('single', dict(w=15, rings=3, heavy=True)))
R('shrapnel_cannon_scrap', 'heavy', 'flak', 'scrap', HV('drum', 'vent'), HB + ([('brake', {})],))
R('basalt_quarry_driver', 'heavy', 'slug', 'standard', HV('m_slab', 'm_slab'), HB + ([('brake', {}), ('liv_rings', dict(ys=(25,)))],), race='basalt')
R('grundl_slug_mortar', 'heavy', 'slug', 'standard', HV('m_amber', 'drum'), (25, 44, ('breech_fixed', dict(w=19, heavy=True)), ('single', dict(w=15, rings=2, heavy=True)), [('tip_flare', dict(extra=3))], 6), race='grundl')
R('baron_tithe_gun', 'heavy', 'slug', 'standard', HV('m_gilded', 'm_gilded'), HB + ([('brake', {}), ('liv_rings', dict(ys=(25,)))],), race='barons')

# ------------------------------------------------------------------ flush pods 4x1 (fixed, missiles home)
POD = ('pod', {})
for pid, race in (('human_volley_rack', 'human'), ('kett_hive_swarm_launcher', 'kett'), ('sporeling_rot_pod', 'sporeling'), ('fenn_market_missile', 'fenn')):
    R(pid, 'pod', 'missile', 'standard', POD, (64, 8, ('lids_liv', dict(race=race)), None), race=race)

# ------------------------------------------------------------------ broadside batteries 6x2 (fixed, gimbal 20; three barrels, staggered recoil)
R('gauntling_scrap_shotgun', 'broadside', 'flak', 'standard', ('casemate6', dict(n=3, parts=('drum', 'm_coil'))), (15, 30, fxl(11), ('single', dict(w=9, rings=1)), [('liv_rings', dict(ys=(12,)))], 1), race='gauntling', stagger=0.07)
R('kett_chitin_thrower', 'broadside', 'flak', 'standard', ('casemate6', dict(n=3, parts=('m_hive', 'cells'))), (15, 34, fxl(11), ('single', dict(w=7, rings=1)), [('tip_prongs', {})], 6), race='kett', stagger=0.07)

# ------------------------------------------------------------------ export (the art format of art/README.md "Guns")
OUT_ANIMS = [('on', 'on', 2, 3), ('off', 'off', 1, 0), ('damaged', 'damaged', 2, 4), ('disabled', 'disabled', 2, 3)]
BAR_ANIMS = [('idle', 'idle', 1, 0), ('fire', 'fire', 3, 14), ('damaged', 'damaged', 2, 4), ('disabled', 'disabled', 1, 0), ('off', 'off', 1, 0)]
GIMBAL = {'casemate': 6, 'long': 3, 'broadside': 20, 'strip': 20, 'heavy': 4, 'spinal': 2, 'pod': 10}
NOTES = {
 'point': 'a ring base (2x2 cells), a compact head and a sensor eye: a TURRET',
 'dome': 'a ring base (3x3 cells) under an armoured dome head and its sensor eye: a TURRET',
 'sponson': 'a half-round sponson on a yoke with a painted rail track: a SWIVEL gun (180 deg)',
 'casemate': 'a rectangular casemate (4x2 cells), the barrel braced in a sleeve with a gimbal collar: a FIXED gun',
 'long': 'a narrow braced cradle (2x4 cells) for a long barrel: a FIXED gun that sticks out far',
 'broadside': 'a broadside battery (6x2 cells), three barrels on one gimbal rail: a FIXED gun for a flank wall',
 'heavy': 'a heavy cannon housing (4x3 cells) with struts and a doubled sleeve: a FIXED gun',
 'pod': 'a flush pod plate (4x1 cells); the barrel sprite is its hatch lids, which open and close as it fires',
}

def _write_strip(path, frames):
    fw, fh = frames[0].w, frames[0].h
    strip = Rgba(fw * len(frames), fh)
    for k, g in enumerate(frames): strip.blit_rgba(g, k * fw, 0)
    strip.save(path)

def export(g, outdir=OUTDIR):
    """writes <id>_out.png/.json/_glow.png and <id>_barrel.png/.json/_glow.png."""
    os.makedirs(outdir, exist_ok=True)
    fr, gl, ganims, anims = [], [], {}, {}
    for (nm, st, n, fps) in OUT_ANIMS:
        anims[nm] = [len(fr), n, fps]
        res = [g.out(st, i) for i in range(n)]
        fr += [r[0] for r in res]
        if st not in ('off', 'disabled'): ganims[nm] = [len(gl), n, fps]; gl += [r[1] for r in res]
    pivots = g.out('on', 0)[2]
    fw, fh = fr[0].w, fr[0].h
    save(sheet(fr, len(fr), fw, fh), '%s/%s_out.png' % (outdir, g.name))
    _write_strip('%s/%s_out_glow.png' % (outdir, g.name), gl)
    gw, gh = gl[0].w, gl[0].h
    OJ = {'frame': [fw, fh], 'cells': list(g.out_cells), 'anims': anims,
          'glow': {'image': g.name + '_out_glow.png', 'frame': [gw, gh], 'offset': [-gs.OPAD, -gs.OPAD], 'anims': ganims}}
    multi = len(pivots) > 1
    OJ['anchors'] = {'pivots': [list(p) for p in pivots]} if multi else {'pivot': list(pivots[0])}
    OJ['notes'] = ('OUTSIDE half of the %s (%s): %s%s; the bottom flange overhangs the outer wall face. damaged: cracks, a loose plate, a spark; disabled: dark, scorched and dented, never destroyed. '
                   'The inside half (breech) is narrower or wider than this half in places: it sits at floor((W - bw) / 2) cells from this half\'s left edge at rotation 0.'
                   % (g.label.title(), g.shape, NOTES[g.shape], (' in the livery of the ' + g.race + ' guns') if g.race else ''))
    # barrel
    b = g.bar
    bf, bg, banims, bganims = [], [], {}, {}
    def add(nm, st, n, fps, glow=True, lit=False):
        banims[nm] = [len(bf), n, fps]
        res = [g.barrel(st, i, i if lit else None) for i in range(n)]
        bf.extend(r[0] for r in res)
        if glow and st != 'disabled': bganims[nm] = [len(bg), n, fps]; bg.extend(r[1] for r in res)
    add('idle', 'idle', 1, 0); add('fire', 'fire', 3, 14); add('damaged', 'damaged', 2, 4); add('disabled', 'disabled', 1, 0)
    banims['off'] = [len(bf), 1, 0]; bf.append(g.barrel('off', 0)[0])
    # the glow strip: fire 0-2, damaged 0-1 (the old order), then idle
    bganims = {'fire': bganims['fire'], 'damaged': bganims['damaged'], 'idle': bganims['idle']}
    for (nm, st, n, fps, lit) in getattr(g, 'extra', []): add(nm, st, n, fps, True, lit); bganims[nm] = [len(bg) - n, n, fps]     # extra anims (spin, charge) after `off`
    bw, bh = bf[0].w, bf[0].h
    save(sheet(bf, len(bf), bw, bh), '%s/%s_barrel.png' % (outdir, g.name))
    _write_strip('%s/%s_barrel_glow.png' % (outdir, g.name), bg)
    px_, py_ = g.barrel('idle', 0)[2]
    # muzzle: from the idle frame's registered muzzles (centre x, top y); rebuilt by a dry run
    mz = _muzzle(g)
    BG = {'image': g.name + '_barrel_glow.png', 'frame': [bg[0].w, bg[0].h], 'offset': [-gs.BPAD, -gs.BPAD], 'anims': bganims}
    B = {'image': g.name + '_barrel.png', 'frame': [bw, bh], 'pivot_on_barrel': [px_, py_], 'muzzle': list(mz), 'anims': banims, 'aim': g.aim}
    if multi: B['pivots_on_base'] = [list(p) for p in pivots]; B['stagger_s'] = g.stagger or 0.07
    else: B['pivot_on_base'] = list(pivots[0])
    if g.aim == 'fixed': B['gimbal_deg'] = GIMBAL[g.shape]
    B['glow'] = BG
    BJ = {'frame': [bw, bh], 'aim': g.aim, 'anims': banims, 'anchors': {'pivot': [px_, py_], 'muzzle': list(mz)}, 'glow': BG,
          'notes': 'Rotating barrel, drawn pointing UP. Turn it about anchors.pivot placed on %s of %s_out. fire: 3 frames, recoil 2/1/0 px with the family muzzle flash on the glow layer; off: lights dead.'
                   % ('each of pivots_on_base (staggered by stagger_s)' if multi else 'pivot_on_base', g.name) + getattr(g, 'extra_note', '')}
    if multi: BJ['pivots_on_base'] = B['pivots_on_base']; BJ['stagger_s'] = B['stagger_s']
    else: BJ['pivot_on_base'] = B['pivot_on_base']
    if g.aim == 'fixed': BJ['gimbal_deg'] = B['gimbal_deg']
    OJ['barrel'] = B
    for nm, J in ((g.name + '_out', OJ), (g.name + '_barrel', BJ)):
        with open('%s/%s.json' % (outdir, nm), 'w') as f: json.dump(J, f, indent=1); f.write('\n')
    return OJ

def _muzzle(g):
    """the muzzle anchor: centre x of the muzzles, the topmost y, on the idle frame (a dry run of the barrel)."""
    b = g.bar
    hn, hkw = b['head']
    neck = gm.BARREL_PARTS[hn](_cv(g), **hkw)
    c = _cv(g)
    if b.get('tube'):
        tn, tkw = b['tube']; gm.BARREL_PARTS[tn](c, b.get('top', 1), neck + 1, **tkw)
    for an, akw in b.get('add', []): gm.BARREL_PARTS[an](c, **akw)
    gm.BARREL_PARTS[hn](c, **hkw)
    ms = c.muzzles
    return (sum(m[0] for m in ms) // len(ms), min(m[1] for m in ms))

def _cv(g):
    b = g.bar; w, reach = b['w'], b['reach']
    c = Ctx(w, reach + b.get('tail', 12), g.look, St('idle', 0)); c.px, c.py = w // 2, reach
    return c

def export_all(outdir=OUTDIR):
    for pid, g in GUNS.items():
        OJ = export(g, outdir)
        print(pid, OJ['frame'], OJ['barrel']['frame'])

if __name__ == '__main__':
    export_all()
