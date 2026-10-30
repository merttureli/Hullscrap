"""Shared bits for the species rigs (basalt, emberkin, fenn). Same rig as crew_v2 (human): 33x33 frame, pivot (16,16),
every layer faces UP, layers are interior-only until outlined. Outfit symbols A/B/C = light/base/dark (tint mask)."""
from px import *
from mach import bev, outline_all, glow
import crew_v2 as cv2
from crew_v2 import N, C, shade_edges, brush, outlined, OUTFIT, OUTFIT_GREY

POSES = ['unarmed', 'pistol', 'rifle', 'tool', 'heavy', 'melee']

# Item mounts are shared by every species so any item fits any body (hand art differs, the mount does not).
MOUNT = {'unarmed': None, 'pistol': (16, 5), 'rifle': (20, 8), 'tool': (21, 4), 'heavy': (19, 11), 'melee': (23, 8)}
# hand targets common to every species (unarmed differs per body)
HANDS = {
 'pistol': dict(hand_l=(14, 5), hand_r=(18, 5)),
 'rifle':  dict(hand_l=(17, 1), hand_r=(21, 9)),
 'tool':   dict(hand_l=(13, 9), hand_r=(21, 4)),
 'heavy':  dict(hand_l=(14, 3), hand_r=(21, 12)),
 'melee':  dict(hand_l=(12, 7), hand_r=(23, 8)),
}

def shade_gen(s, base, hi, lo):
    """base pixels: lo on bottom/right-facing edges, hi on top/left-facing edges (top-left light)."""
    n = s.copy()
    for y in range(s.h):
        for x in range(s.w):
            if s.g[y][x] != base: continue
            if s.get(x, y + 1) == '.' or s.get(x + 1, y) == '.': n.g[y][x] = lo
            elif s.get(x, y - 1) == '.' or s.get(x - 1, y) == '.': n.g[y][x] = hi
    return n






def pose_anchors(unarmed_l, unarmed_r, hands=None):
    h = dict(HANDS if hands is None else hands)
    out = {'unarmed': dict(hand_l=unarmed_l, hand_r=unarmed_r, mount=None)}
    for p in POSES[1:]:
        out[p] = dict(hand_l=h[p]['hand_l'], hand_r=h[p]['hand_r'], mount=MOUNT[p])
    return out

# ---------------------------------------------------------------- glow layers (soft alpha, one RGBA frame per sprite frame)
def new_glow(w=N, h=N): return Rgba(w, h)
def glow_px(layer, pts, rgb, strength=0.9, r=3.0, power=1.6):
    for (x, y) in pts: glow(layer, x + 0.5, y + 0.5, r, rgb, strength, power)

def spr_pts(s, chars):
    return [(x, y) for y in range(s.h) for x in range(s.w) if s.g[y][x] in chars]

def glow_strip(frames):
    out = Rgba(N * len(frames), N)
    for i, f in enumerate(frames): out.blit_rgba(f, i * N, 0)
    return out

class Species:
    """what export and the compose kit read."""
    id = '?'
    walk_fps = 8
    head_names = []
    notes = ''
    def legs(self): raise NotImplementedError
    def torso(self): raise NotImplementedError
    def arms(self, pose): raise NotImplementedError
    def head(self, name): raise NotImplementedError
    def torso_anchors(self): return {'head': [16, 14], 'back': [16, 24], 'shoulder_l': [8, 14], 'shoulder_r': [24, 14]}
    def arm_anchors(self): raise NotImplementedError
    # optional glow layers: return list of Rgba frames or None
    def legs_glow(self): return None
    def torso_glow(self): return None
    def arms_glow(self, pose): return None
    def head_glow(self): return None
