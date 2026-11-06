"""Exports the drone art into the game (docs/DRONES.md section 8): the three bays (inside and outside halves in art/components/, in the scrap, standard and neon
lines as Mk I, II and III), every combat and defence drone (art/drones/<name>.png: idle 0-1, fire 0-1, hit; its glow strip and 32 pre-turned copies of each
frame, <name>_rot.png) and the thruster trails (art/drones/trail_<line>.png). Usage: python3 drone_export.py   (writes the files, prints them)."""
import json, os, sys
from px import *
import drone_mod as dm
import drone_samples as ds

ART_C = ART + '/components'
ART_D = ART + '/drones'
BAYS = [('drone_bay_mk1', 'scrap', 'pulse'), ('drone_bay_mk2', 'standard', 'laser'), ('drone_bay_mk3', 'neon', 'ion')]
IN_FRAMES = [('on', 'on', 0), ('on', 'on', 1), ('off', 'off', 0), ('damaged', 'damaged', 0), ('damaged', 'damaged', 1), ('disabled', 'disabled', 0),
             ('launch', 'launch', 0), ('launch', 'launch', 1), ('launch', 'launch', 2), ('launch', 'launch', 3), ('out', 'out', 0), ('out', 'out', 1)]
OUT_FRAMES = [('on', 0), ('on', 1), ('off', 0), ('damaged', 0), ('damaged', 1), ('disabled', 0), ('open', 0), ('open', 1), ('open', 2)]
ROTS = 32
FRAMES = [('idle', 0), ('idle', 1), ('fire', 0), ('fire', 1), ('hit', 0)]


def strip(frames):
    fw, fh = frames[0].w, frames[0].h
    s = Rgba(fw * len(frames), fh)
    for k, g in enumerate(frames): s.blit_rgba(g, k * fw, 0)
    return s


def write(path, obj):
    with open(path, 'w') as f: json.dump(obj, f, indent=1); f.write('\n')


def export_bay(bid, line, fam):
    bay = dm.Bay(line, fam)
    ins = [bay.inside(st, i, None) for (_, st, i) in IN_FRAMES]
    outs = [bay.outside(st, i) for (st, i) in OUT_FRAMES]
    for name, res, cells, frames, anims, ganims in (
            (bid, ins, [3, 3], IN_FRAMES, {'on': [0, 2, 3], 'off': [2, 1, 0], 'damaged': [3, 2, 4], 'disabled': [5, 1, 0], 'fire': [6, 4, 10], 'out': [10, 2, 3]}, {'on': [0, 2, 3], 'damaged': [3, 2, 4], 'fire': [6, 4, 10], 'out': [10, 2, 3]}),
            (bid + '_out', outs, [3, 1], OUT_FRAMES, {'on': [0, 2, 3], 'off': [2, 1, 0], 'damaged': [3, 2, 4], 'disabled': [5, 1, 0], 'fire': [6, 3, 8]}, {'on': [0, 2, 3], 'damaged': [3, 2, 4], 'fire': [6, 3, 8]})):
        spr = [r[0] for r in res]; gl = [r[1] for r in res]
        save(sheet(spr, len(spr), spr[0].w, spr[0].h), '%s/%s.png' % (ART_C, name))
        g2 = [g for k, g in enumerate(gl)]
        strip(g2).save('%s/%s_glow.png' % (ART_C, name))
        J = {'frame': [spr[0].w, spr[0].h], 'cells': cells, 'anims': anims,
             'glow': {'image': name + '_glow.png', 'frame': [g2[0].w, g2[0].h], 'offset': [-dm.GP, -dm.GP], 'anims': ganims}}
        if name == bid:
            J['offset'] = [0, -dm.FLANGE]
            J['anchors'] = {'cradle': [dm.RX, dm.BH - 48 + dm.REST]}
            J['cradle_launch_up'] = dm.LAUNCH
            J['notes'] = ('INSIDE half of the %s (%s line, 3x3): the hangar pit with its launch rail, the cradle (EMPTY here: the game draws the loaded drone on it while docked, '
                          'and an empty cradle while it is out), parts racks and a status strip. fire = launch 0-3 (the cradle runs up the rail), out = re-arming. '
                          'anchors.cradle is the cradle pivot in frame px at rest; cradle_launch_up the px it has risen per launch frame.' % (bid, line))
        else:
            J['anchors'] = {'pivot': [dm.OW // 2, dm.OH - dm.FLANGE - 1]}
            J['notes'] = 'OUTSIDE half of the %s (3x1, low): a hatch of two door leaves over the launch well. fire = open 0-2 (the leaves slide apart); the bottom flange overhangs the outer wall face.' % bid
        write('%s/%s.json' % (ART_C, name), J)
        print(name, J['frame'])


def turned_frames(d):
    """-> (frames, S): the sprite of each of FRAMES at ROTS headings, turned about the pivot, outlined after. Row = frame, column = heading."""
    out = []
    S = None
    for (st, i) in FRAMES:
        spr, g, _ = d.frame(st, i, raw=True)
        row = []
        for k in range(ROTS):
            r, G, h = ds.turned(spr, None, k * 360 // ROTS, dm.DC, dm.GP)
            row.append(r); S = r.w
        out.append(row)
    return out, S


def export_drone(d):
    spr, gl = [], []
    for (st, i) in FRAMES:
        s, g, anch = d.frame(st, i)
        spr.append(s); gl.append(g)
    save(sheet(spr, len(spr), spr[0].w, spr[0].h), '%s/%s.png' % (ART_D, d.name))
    strip(gl).save('%s/%s_glow.png' % (ART_D, d.name))
    muzzle = anch['muzzle'][0] if anch['muzzle'] else [dm.DC, 2]
    rot, S = turned_frames(d)
    big = Spr(S * ROTS, S * len(FRAMES))
    for r, row in enumerate(rot):
        for k, sp in enumerate(row): big.stamp(k * S, r * S, sp.rows())
    save(big, '%s/%s_rot.png' % (ART_D, d.name))
    J = {'frame': [spr[0].w, spr[0].h], 'pivot': [dm.DC, dm.DC], 'anims': {'idle': [0, 2, 3], 'fire': [2, 2, 12], 'hit': [4, 1, 0]},
         'glow': {'image': d.name + '_glow.png', 'frame': [gl[0].w, gl[0].h], 'offset': [-dm.GP, -dm.GP], 'anims': {'idle': [0, 2, 3], 'fire': [2, 2, 12], 'hit': [4, 1, 0]}},
         'rot': {'image': d.name + '_rot.png', 'frame': [S, S], 'count': ROTS, 'frames': [f[0] + str(f[1]) for f in FRAMES], 'pivot': [S // 2, S // 2]},
         'anchors': {'muzzle': list(muzzle)}, 'kind': d.kind, 'family': d.fam, 'tier': d.tier,
         'notes': 'A %s drone facing UP (nose = the way it flies and shoots), %dx%d px, pivot at its middle. Frames: idle 0-1, fire 0-1, hit (a white flash). <name>_rot.png holds %d pre-turned '
                  'copies of every frame (column k = turned k*%d degrees clockwise, row = frame, outlined after turning), so a turned drone does not jag at 2x; the glow strip is turned by the '
                  'engine (it is soft).' % (d.kind, dm.DN, dm.DN, ROTS, 360 // ROTS)}
    write('%s/%s.json' % (ART_D, d.name), J)
    print(d.name, J['frame'], S)


def export_trails():
    for line in ('scrap', 'standard', 'neon'):
        fr = dm.trail_frames(line)
        save(sheet([f[0] for f in fr], 4, 5, 5), '%s/trail_%s.png' % (ART_D, line))
        strip([f[1] for f in fr]).save('%s/trail_%s_glow.png' % (ART_D, line))
        write('%s/trail_%s.json' % (ART_D, line), {'frame': [5, 5], 'pivot': [2, 2], 'anims': {'puff': [0, 4, 0]},
              'glow': {'image': 'trail_%s_glow.png' % line, 'frame': [fr[0][1].w, fr[0][1].h], 'offset': [-4, -4], 'anims': {'puff': [0, 4, 0]}},
              'notes': 'A thruster puff of the %s line: 4 frames (a hot core, the body colour, its fade). One puff every few px behind a nozzle; frame = age.' % line})


LIMPET_FRAMES = [('flying', 0), ('flying', 1), ('stuck', 0), ('stuck', 1), ('stuck', 2), ('stuck', 3), ('husk', 0)]
POD_FRAMES = [('flying', 0), ('flying', 1), ('drilling', 0), ('drilling', 1), ('drilling', 2), ('husk', 0)]
POD_S = 37                                                                   # the pod's square turning canvas (pivot at its middle)


def export_limpet(l):
    """art/drones/<name>.png: flying 0-1, stuck 0-3 (the core pulses, the spikes splayed), husk; 25 px, pivot at the core. It is round: the game does not turn it."""
    spr, gl = [], []
    for (st, i) in LIMPET_FRAMES:
        s, g, _ = l.frame(st, i)
        spr.append(s); gl.append(g)
    save(sheet(spr, len(spr), spr[0].w, spr[0].h), '%s/%s.png' % (ART_D, l.name))
    strip(gl).save('%s/%s_glow.png' % (ART_D, l.name))
    an = {'fly': [0, 2, 6], 'stuck': [2, 4, 5], 'husk': [6, 1, 0]}
    write('%s/%s.json' % (ART_D, l.name), {'frame': [spr[0].w, spr[0].h], 'pivot': [dm.DC, dm.DC], 'anims': an,
          'glow': {'image': l.name + '_glow.png', 'frame': [gl[0].w, gl[0].h], 'offset': [-dm.GP, -dm.GP], 'anims': an}, 'kind': 'limpet', 'family': l.fam,
          'notes': 'A %s limpet, 25 px square, pivot at its core. Frames: flying 0-1 (spikes folded), stuck 0-3 (spikes splayed, the core pulses), husk (dead, bent spikes). '
                   'It is round: draw it unturned. The game pulses the glow strip with the same frame.' % l.fam})
    print(l.name)


def export_pod(p):
    """art/drones/<name>.png: flying 0-1, drilling 0-2, husk (21 x 37) and <name>_rot.png: 32 pre-turned copies of each (37 px square, pivot at the middle)."""
    spr, gl = [], []
    rot = Spr(POD_S * ROTS, POD_S * len(POD_FRAMES))
    for r, (st, i) in enumerate(POD_FRAMES):
        s, g, _ = p.frame(st, i)
        spr.append(s); gl.append(g)
        pad = Spr(POD_S, POD_S); pad.stamp(POD_S // 2 - dm.PCX, 0, ds.strip_outline(s).rows())
        gp = Rgba(POD_S + 2 * dm.GP, POD_S + 2 * dm.GP); gp.blit_rgba(g, POD_S // 2 - dm.PCX, 0)
        for k in range(ROTS):
            t, G, h = ds.turned(pad, gp, k * 360 // ROTS, POD_S // 2, dm.GP)
            rot.stamp(k * POD_S, r * POD_S, t.rows())
    save(sheet(spr, len(spr), spr[0].w, spr[0].h), '%s/%s.png' % (ART_D, p.name))
    strip(gl).save('%s/%s_glow.png' % (ART_D, p.name))
    save(rot, '%s/%s_rot.png' % (ART_D, p.name))
    an = {'fly': [0, 2, 8], 'drill': [2, 3, 12], 'husk': [5, 1, 0]}
    write('%s/%s.json' % (ART_D, p.name), {'frame': [spr[0].w, spr[0].h], 'pivot': [dm.PCX, 18], 'anims': an,
          'glow': {'image': p.name + '_glow.png', 'frame': [gl[0].w, gl[0].h], 'offset': [-dm.GP, -dm.GP], 'anims': an},
          'rot': {'image': p.name + '_rot.png', 'frame': [POD_S, POD_S], 'count': ROTS, 'frames': [f[0] + str(f[1]) for f in POD_FRAMES], 'pivot': [POD_S // 2, POD_S // 2]},
          'kind': 'boarder', 'family': p.fam,
          'notes': 'A boarder pod, nose (the drill) UP, 21 x 37 px, pivot on the hatch. Frames: flying 0-1, drilling 0-2 (claws gripped, sparks), husk (empty). '
                   '<name>_rot.png: 32 pre-turned copies of every frame (column = heading, row = frame).'})
    print(p.name)


def export_robots():
    ds.export_rigs(ART + '/crew')


if __name__ == '__main__':
    os.makedirs(ART_D, exist_ok=True)
    for l in dm.LIMPETS: export_limpet(l)
    export_pod(dm.BOARDER); export_pod(dm.BOARDER.variant(name='boarder_pod_ion', fam='ion', label='SHOCK POD'))
    export_robots()
    if '--d2' not in sys.argv:
        for b in BAYS: export_bay(*b)
        for d in dm.COMBAT + dm.DEFENCE: export_drone(d)
        export_trails()
