"""Exports the drone art into the game (docs/DRONES.md section 8): the three bays (inside and outside halves in art/components/, in the scrap, standard and neon
lines as Mk I, II and III), every combat and defence drone (art/drones/<name>.png: idle 0-1, fire 0-1, hit; its glow strip and 32 pre-turned copies of each
frame, <name>_rot.png) and the thruster trails (art/drones/trail_<line>.png). Usage: python3 drone_export.py   (writes the files, prints them)."""
import json, os
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


def export_defence_parts(d):
    """a defence drone is two layers: the hoop, dome and backing (never turned) and the twin barrel (turned by the engine, 32 headings)."""
    base = [d.frame(st, i, part='base')[0] for (st, i) in FRAMES]
    save(sheet(base, len(base), base[0].w, base[0].h), '%s/%s_base.png' % (ART_D, d.name))
    big = None
    for r, (st, i) in enumerate(FRAMES):
        spr = d.frame(st, i, raw=True, part='barrel')[0]
        for k in range(ROTS):
            t, G, h = ds.turned(spr, None, k * 360 // ROTS, dm.DC, dm.GP)
            if big is None: big = Spr(t.w * ROTS, t.w * len(FRAMES))
            big.stamp(k * t.w, r * t.w, t.rows())
    save(big, '%s/%s_barrel_rot.png' % (ART_D, d.name))


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
    if d.kind == 'defence':
        export_defence_parts(d)
        J['parts'] = {'base': d.name + '_base.png', 'barrel_rot': d.name + '_barrel_rot.png'}
        J['notes'] += ' A defence drone is drawn in two layers: <name>_base.png (the dark backing, hoop and dome, never turned) and <name>_barrel_rot.png (the twin barrel, 32 headings); the full sprite above is for the bar and the cards.'
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


if __name__ == '__main__':
    os.makedirs(ART_D, exist_ok=True)
    for b in BAYS: export_bay(*b)
    for d in dm.COMBAT + dm.DEFENCE: export_drone(d)
    export_trails()
