"""art-species exports: art/crew/{basalt,emberkin,fenn}/, art/items/<hand weapons> (+ fx), art/gear/.
(The human rig, including its new heavy and melee poses, is exported by export_crew.py as before.)"""
import json, os
from px import *
import crew_v2 as cv2
from sp_common import POSES, glow_strip
import sp_basalt, sp_emberkin, sp_fenn, sp_items, sp_fx, sp_gear
from sp_gear import outline_outer

SPECIES = [sp_basalt.Basalt, sp_emberkin.Emberkin, sp_fenn.Fenn]

def jdump(obj, path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'w') as f: json.dump(obj, f, indent=1); f.write('\n')

def pair(d, name, sprs):
    save(sheet([cv2.base_of(x) for x in sprs], len(sprs), cv2.N, cv2.N), '%s/%s.png' % (d, name))
    save(sheet([cv2.mask_of(x) for x in sprs], len(sprs), cv2.N, cv2.N), '%s/%s_color.png' % (d, name))

def glow_json(image, n):
    return {'image': image, 'frame': [cv2.N, cv2.N], 'offset': [0, 0], 'frames': n, 'blend': 'add (preferred) or alpha-over'}

def export_species(cls):
    sp = cls(); d = ART + '/crew/' + sp.id
    cv2.OUTLINE = True
    legs = sp.legs()
    pair(d, 'legs', legs)
    pair(d, 'torso', [sp.torso()])
    pair(d, 'arms', [sp.arms(p) for p in POSES])
    pair(d, 'head', [sp.head(h) for h in sp.head_names])
    layers = {
     'legs':  {'image': 'legs.png', 'color_mask': 'legs_color.png', 'anims': {'walk': [0, 6, sp.walk_fps], 'stand': [6, 1, 0]},
               'notes': 'frames 0 and 3 are the contacts; the swing boot (frames 1-2 right, 4-5 left) is lifted'},
     'torso': {'image': 'torso.png', 'color_mask': 'torso_color.png', 'anchors': sp.torso_anchors()},
     'arms':  {'image': 'arms.png', 'color_mask': 'arms_color.png', 'frames': {p: i for i, p in enumerate(POSES)},
               'anchors': {p: {k: (list(v) if v else None) for k, v in a.items()} for p, a in sp.arm_anchors().items()},
               'notes': 'item placement: item top-left = mount - item.grip (both unrotated), then rotate the upper group about the pivot. '
                        'Mounts are identical on every species (and the human), so any item fits any body. Pose = the item\'s class: '
                        'pistol, rifle, tool, heavy, melee.'},
     'head':  {'image': 'head.png', 'color_mask': 'head_color.png', 'frames': {h: i for i, h in enumerate(sp.head_names)}},
    }
    g = sp.legs_glow()
    if g: glow_strip(g).save(d + '/legs_glow.png'); layers['legs']['glow'] = glow_json('legs_glow.png', len(g))
    g = sp.torso_glow()
    if g: glow_strip(g).save(d + '/torso_glow.png'); layers['torso']['glow'] = glow_json('torso_glow.png', len(g))
    g = sp.head_glow()
    if g:
        glow_strip(g).save(d + '/head_glow.png')
        n = len(sp.head_names)
        layers['head']['glow'] = dict(glow_json('head_glow.png', len(g)))
        if len(g) > n:
            layers['head']['glow']['variants'] = {h: [i + k * n for k in range(len(g) // n)] for i, h in enumerate(sp.head_names)}
            layers['head']['glow']['notes'] = 'per head variant, a list of glow frames: alternate them at ~6 fps for the heat shimmer'
    J = {'species': sp.id, 'frame': [cv2.N, cv2.N], 'pivot': [cv2.C, cv2.C], 'notes': sp.notes + ' Same rig as human: every layer faces UP at '
         'rotation 0 on one 33x33 frame, rotate about the pivot; outfit pixels are neutral grey in the base PNG and white in *_color.png '
         '(multiply by the outfit colour there); no baked shadow.',
         'draw_order': ['legs', 'torso', 'arms', 'item', 'head'],
         'rotate': {'legs': 'move direction', 'torso': 'aim', 'arms': 'aim', 'item': 'aim', 'head': 'aim'},
         'layers': layers}
    jdump(J, d + '/crew.json')
    return sp.id

def item_notes(it):
    return ('faces UP. grip = where the hand closes (goes on the arms pose mount of the item\'s class); muzzle = where shots, flame, '
            'sparks or the blade tip are. ' + it['notes'])

def export_items():
    di = ART + '/items'
    for k in sp_items.ORDER:
        it = sp_items.ITEMS[k]
        spr = sp_items.outlined_item(it)
        save(spr, '%s/%s.png' % (di, k))
        J = {'frame': [spr.w, spr.h], 'anchors': sp_items.anchors(it), 'class': it['cls'], 'pose': it['cls'], 'culture': it['culture'],
             'notes': item_notes(it)}
        if it['glow']:
            gl = sp_items.item_glow(it, margin=1)
            gl.save('%s/%s_glow.png' % (di, k))
            J['glow'] = {'image': k + '_glow.png', 'frame': [gl.w, gl.h], 'offset': [-sp_items.GLOW_PAD, -sp_items.GLOW_PAD], 'blend': 'add (preferred) or alpha-over'}
        jdump(J, '%s/%s.json' % (di, k))
    # muzzle flashes
    for name, fn in sp_fx.FX.items():
        frames, org = fn()
        w, h = frames[0].w, frames[0].h
        base = '%s/fx/muzzle_%s' % (di, name)
        save(sheet(frames, len(frames), w, h), base + '.png')
        rgb, r = sp_fx.FX_GLOW[name]
        gl = [sp_fx.glow_frame(f, rgb, r) for f in frames]
        out = Rgba(gl[0].w * len(gl), gl[0].h)
        for i, g in enumerate(gl): out.blit_rgba(g, i * g.w, 0)
        out.save(base + '_glow.png')
        classes = {'pistol': ['pistol'], 'rifle': ['rifle'], 'heavy': ['heavy'], 'flame': ['heavy (torchgun)'], 'spark': ['pistol (spark_pistol)']}[name]
        jdump({'frame': [w, h], 'mode': sp_fx.FX_MODE[name], 'anims': {'play': [0, len(frames), sp_fx.FX_FPS[name]]},
               'anchors': {'muzzle': list(org)}, 'for_class': classes,
               'glow': {'image': 'muzzle_%s_glow.png' % name, 'frame': [gl[0].w, gl[0].h], 'offset': [-sp_fx.PAD, -sp_fx.PAD],
                        'anims': {'play': [0, len(frames), sp_fx.FX_FPS[name]]}, 'blend': 'add (preferred) or alpha-over'},
               'notes': 'Hand-weapon muzzle flash, faces UP (rotation 0): put the muzzle anchor on the weapon\'s muzzle point and rotate with the '
                        'weapon. ' + ('Loops while the torchgun is held down.' if name == 'flame' else 'Plays once per shot.')},
              base + '.json')

GEAR_NOTES = {
 'eva_suit': 'EVA suit: puffy shoulder rings (tinted), twin air tanks with a green gauge on the back, a see-through bubble helmet. Fits the human rig.',
 'combat_vest': 'Combat vest: steel shoulder plates, a back plate, a pouch belt with orange tags. Fits the human rig.',
 'exosuit': 'Exosuit: bulky armour shell (tinted plates), a back power unit with a glowing core, a closed helm with a cyan visor. It replaces the legs and the arms too. Fits the human rig.',
 'salamander_suit': 'Salamander suit: a heat-reflective foil mantle with gold trim and a hood with an ember visor slit. Fits the human rig.',
}
def export_gear():
    dg = ART + '/gear'
    cv2.OUTLINE = True
    for gid in sp_gear.GEAR:
        p = sp_gear.parts(gid)
        bg, hg = sp_gear.glow_for(gid)
        body = cv2.outlined(p['body'])
        frames = [body]; layers = {'body': {'image': gid + '.png', 'frame': 0, 'color_mask': gid + '_color.png', 'draw_after': 'torso'}}
        if p.get('head') is not None:
            head = outline_outer(p['head']) if p.get('head_outer') else cv2.outlined(p['head'])
            frames.append(head)
            layers['head'] = {'image': gid + '.png', 'frame': 1, 'color_mask': gid + '_color.png', 'draw_after': 'head'}
            if p.get('head_outer'): layers['head']['notes'] = 'see-through bubble: only its outside is outlined, the inside is clear so the head shows'
        pair(dg, gid, frames)
        gl = [bg] + ([hg] if p.get('head') is not None else [])
        if any(px[3] for g in gl for row in g.p for px in row):
            glow_strip(gl).save('%s/%s_glow.png' % (dg, gid))
            layers['body']['glow'] = {'image': gid + '_glow.png', 'frame': 0, 'frame_size': [cv2.N, cv2.N], 'blend': 'add (preferred) or alpha-over'}
            if 'head' in layers: layers['head']['glow'] = {'image': gid + '_glow.png', 'frame': 1, 'frame_size': [cv2.N, cv2.N], 'blend': 'add (preferred) or alpha-over'}
        extra = {}
        if p.get('legs'):
            legs = sp_gear.exo_legs()
            save(sheet([cv2.base_of(x) for x in legs], len(legs), cv2.N, cv2.N), '%s/%s_legs.png' % (dg, gid))
            save(sheet([cv2.mask_of(x) for x in legs], len(legs), cv2.N, cv2.N), '%s/%s_legs_color.png' % (dg, gid))
            layers['legs'] = {'image': gid + '_legs.png', 'color_mask': gid + '_legs_color.png', 'replaces': 'legs',
                              'anims': {'walk': [0, 6, 6], 'stand': [6, 1, 0]}}
        if p.get('arms'):
            arms = [sp_gear.exo_arms(pose) for pose in POSES]
            save(sheet([cv2.base_of(x) for x in arms], len(arms), cv2.N, cv2.N), '%s/%s_arms.png' % (dg, gid))
            save(sheet([cv2.mask_of(x) for x in arms], len(arms), cv2.N, cv2.N), '%s/%s_arms_color.png' % (dg, gid))
            layers['arms'] = {'image': gid + '_arms.png', 'color_mask': gid + '_arms_color.png', 'replaces': 'arms',
                              'frames': {pose: i for i, pose in enumerate(POSES)}}
        jdump({'id': gid, 'frame': [cv2.N, cv2.N], 'pivot': [cv2.C, cv2.C], 'fits': 'human rig (same anchors as art/crew/human)',
               'layers': layers,
               'notes': GEAR_NOTES[gid] + ' Layers share the crew frame and rotate about the pivot with the aim (legs with the move direction). '
                        '"draw_after": body goes after the torso (before the arms); head goes after the head layer. Outfit pixels: neutral grey in the PNG, '
                        'white in the _color mask.'}, '%s/%s.json' % (dg, gid))

def export_all():
    for c in SPECIES: print('species', export_species(c))
    export_items(); export_gear()

if __name__ == '__main__':
    export_all()
    print('ok')
