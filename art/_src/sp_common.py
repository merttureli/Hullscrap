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






def pose_anchors(unarmed_l, unarmed_r, hands=None, shift=0):
    """hand and mount targets per pose. `shift` moves the shared targets for a bigger frame whose pivot is at (16+shift, 16+shift):
    the mounts stay identical RELATIVE TO THE PIVOT, which is what makes every item fit every body."""
    h = dict(HANDS if hands is None else hands)
    mv = lambda v: (v[0] + shift, v[1] + shift)
    out = {'unarmed': dict(hand_l=unarmed_l, hand_r=unarmed_r, mount=None)}
    for p in POSES[1:]:
        out[p] = dict(hand_l=mv(h[p]['hand_l']), hand_r=mv(h[p]['hand_r']), mount=mv(MOUNT[p]))
    return out

# ---------------------------------------------------------------- glow layers (soft alpha, one RGBA frame per sprite frame)
def new_glow(w=N, h=N): return Rgba(w, h)
def glow_px(layer, pts, rgb, strength=0.9, r=3.0, power=1.6):
    for (x, y) in pts: glow(layer, x + 0.5, y + 0.5, r, rgb, strength, power)

def glow_px_max(layer, pts, rgb, strength=0.9, r=3.0, power=1.6):
    """like glow_px, but the strongest light wins per pixel instead of blending, so every glow pixel keeps an exact palette hue (alpha varies)."""
    for (x, y) in pts:
        cx, cy = x + 0.5, y + 0.5
        for yy in range(int(cy - r - 1), int(cy + r + 2)):
            for xx in range(int(cx - r - 1), int(cx + r + 2)):
                if not (0 <= xx < layer.w and 0 <= yy < layer.h): continue
                d = ((xx + 0.5 - cx) ** 2 + (yy + 0.5 - cy) ** 2) ** 0.5
                if d >= r: continue
                a = int(255 * strength * (1 - d / r) ** power)
                if a > 5 and a > layer.p[yy][xx][3]: layer.p[yy][xx] = list(rgb) + [a]

def spr_pts(s, chars):
    return [(x, y) for y in range(s.h) for x in range(s.w) if s.g[y][x] in chars]

def glow_strip(frames):
    w = frames[0].w
    out = Rgba(w * len(frames), frames[0].h)
    for i, f in enumerate(frames): out.blit_rgba(f, i * w, 0)
    return out

class Species:
    """what export and the compose kit read."""
    id = '?'
    N = N                  # frame size (square) and pivot pixel; the large rig (Grundl) overrides both
    C = C
    walk_fps = 8
    glow_fps = None        # fps of multi-frame torso/head glows that pulse or drift (set by the race-wave-1 species; the older ones stay silent)
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
