"""writes art/crew/human/* and art/items/*"""
import json, os
from px import *
import crew_v2 as cv2

def jdump(obj, path):
    with open(path, 'w') as f: json.dump(obj, f, indent=1); f.write('\n')

def export():
    d = ART + '/crew/human'; os.makedirs(d, exist_ok=True)
    cv2.OUTLINE = True
    def pair(name, sprs):
        save(sheet([cv2.base_of(x) for x in sprs], len(sprs), cv2.N, cv2.N), '%s/%s.png' % (d, name))
        save(sheet([cv2.mask_of(x) for x in sprs], len(sprs), cv2.N, cv2.N), '%s/%s_color.png' % (d, name))
    pair('legs', cv2.legs())
    pair('torso', [cv2.torso()])
    pair('arms', [cv2.arms(p) for p in cv2.POSES])
    pair('head', [cv2.head(h) for h in cv2.HEADS])
    J = {
     'frame': [cv2.N, cv2.N],
     'pivot': [cv2.C, cv2.C],
     'notes': 'Top-down layered human. Every layer faces UP at rotation 0 and shares one 33x33 frame; rotate about pivot. '
              'Anchors are source px from the frame top-left. Outfit pixels are neutral grey in the base PNG and white in *_color.png: '
              'multiply by the outfit colour there. No baked shadow: draw a 1px down-right shadow from the final silhouette. '
              'Rotation: quarter turns are lossless; for other angles nearest works, or pre-render 32 rotations (reference: art/_src/compose.py).',
     'draw_order': ['legs', 'torso', 'arms', 'item', 'head'],
     'rotate': {'legs': 'move direction', 'torso': 'aim', 'arms': 'aim', 'item': 'aim', 'head': 'aim'},
     'layers': {
      'legs':  {'image': 'legs.png', 'color_mask': 'legs_color.png', 'anims': {'walk': [0, 6, 8], 'stand': [6, 1, 0]},
                'notes': 'frames 0 and 3 are the contacts; the swing boot (frames 1-2 right, 4-5 left) is lighter'},
      'torso': {'image': 'torso.png', 'color_mask': 'torso_color.png',
                'anchors': {'head': [16, 14], 'back': [16, 24], 'shoulder_l': [8, 14], 'shoulder_r': [24, 14]}},
      'arms':  {'image': 'arms.png', 'color_mask': 'arms_color.png', 'frames': {p: i for i, p in enumerate(cv2.POSES)},
                'anchors': {p: {k: (list(v) if v else None) for k, v in cv2.ARM[p].items()} for p in cv2.POSES},
                'notes': 'item placement: item top-left = mount - item.grip (both unrotated), then rotate the upper group about the pivot. '
                         'Use pose "pistol" for pistols, "rifle" for rifles, "tool" for the wrench and extinguisher, "heavy" for heavy guns, "melee" for blades and hammers (an item JSON\'s "class" names its pose).'},
      'head':  {'image': 'head.png', 'color_mask': 'head_color.png', 'frames': {h: i for i, h in enumerate(cv2.HEADS)},
                'notes': 'hair is not tinted; the helmet shell takes the outfit colour, its visor and glint stay as drawn'},
     },
    }
    jdump(J, d + '/crew.json')
    di = ART + '/items'; os.makedirs(di, exist_ok=True)
    pose = {'pistol': 'pistol', 'rifle': 'rifle', 'wrench': 'tool', 'extinguisher': 'tool'}
    for n in cv2.ITEM_ART:
        sp = cv2.item(n)
        save(sp, '%s/%s.png' % (di, n))
        jdump({'frame': [sp.w, sp.h], 'anchors': cv2.item_anchors(n), 'class': pose[n], 'pose': pose[n],
               'notes': 'faces UP. grip = where the hand closes (goes on the arms pose mount); muzzle = where shots, spray or the tool tip come out.'},
              '%s/%s.json' % (di, n))

if __name__ == '__main__':
    export()
    print('ok')
