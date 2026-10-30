"""Reference compositor for any species (generalises compose.py). Layers are interior-only; each is rotated, then outlined.
Order: legs (move dir) -> [gear legs] -> torso -> [gear body] -> arms -> item -> head -> [gear head]. Glow layers add on top."""
import math
from px import *
from mach import outline_all
from compose import rotate, floor_shadow, G, GC, _on_group
import crew_v2 as cv2
from sp_common import MOUNT
ITEM_GLOW_PAD = 4
from crew_v2 import C

class SKit:
    def __init__(s, sp, items=None, gear=None):
        cv2.OUTLINE = False
        s.sp = sp
        s.legs = sp.legs(); s.torso = sp.torso()
        s.arms = {p: sp.arms(p) for p in sp.arm_anchors()}
        s.heads = {h: sp.head(h) for h in sp.head_names}
        s.legs_glow = sp.legs_glow(); s.torso_glow = sp.torso_glow(); s.head_glow = sp.head_glow()
        s.arms_glow = {p: sp.arms_glow(p) for p in s.arms}
        s.items = items
        s.gear = gear
        cv2.OUTLINE = True

def _rot_rgba(o, deg, cx, cy):
    """nearest rotate of an RGBA layer (glow is soft, so nearest is fine)."""
    deg %= 360
    t = math.radians(deg); c, sn = math.cos(t), math.sin(t)
    n = Rgba(o.w, o.h)
    for y in range(o.h):
        for x in range(o.w):
            px_, py_ = x + 0.5 - cx - 0.5, y + 0.5 - cy - 0.5
            u = c * px_ + sn * py_; v = -sn * px_ + c * py_
            xi, yi = int(math.floor(cx + 0.5 + u)), int(math.floor(cy + 0.5 + v))
            if 0 <= xi < o.w and 0 <= yi < o.h: n.p[y][x] = list(o.p[yi][xi])
    return n

def _glow_on_group(g, ox, oy):
    out = Rgba(G, G)
    for y in range(g.h):
        for x in range(g.w):
            if g.p[y][x][3] and 0 <= x + ox < G and 0 <= y + oy < G: out.p[y + oy][x + ox] = list(g.p[y][x])
    return out

def compose(kit, leg_frame, leg_deg, aim_deg, pose='unarmed', item=None, head=None, gear=None, glow_out=None):
    """returns an interior+outline Spr on the 97x97 group canvas; if glow_out is an Rgba, the rotated glow layers are added to it."""
    sp = kit.sp
    out = Spr(G, G); o = GC - C
    glows = []
    def put(layer, deg, gl=None, outer=False, gl_off=(0, 0)):
        r = rotate(layer, deg, GC, GC)
        if outer:
            from sp_gear import outline_outer
            r = outline_outer(r)
        else: outline_all(r)
        out.stamp(0, 0, r.rows())
        if gl is not None and glow_out is not None:
            glows.append(_rot_rgba(_glow_on_group(gl, o + gl_off[0], o + gl_off[1]), deg, GC, GC))
    gear = gear or {}
    legs_layer = gear['legs'][leg_frame] if gear and gear.get('legs') else kit.legs[leg_frame]
    lg = kit.legs_glow[leg_frame] if kit.legs_glow else None
    put(_on_group(legs_layer, o, o), leg_deg, lg)
    put(_on_group(kit.torso, o, o), aim_deg, kit.torso_glow[0] if kit.torso_glow else None)
    if gear and gear.get('body') is not None:
        put(_on_group(gear['body'], o, o), aim_deg, gear.get('body_glow'))
    arm_layer = gear['arms'][pose] if gear and gear.get('arms') else kit.arms[pose]
    put(_on_group(arm_layer, o, o), aim_deg, kit.arms_glow.get(pose)[0] if kit.arms_glow.get(pose) else None)
    if item:
        it = kit.items[item]
        mx, my = MOUNT[pose]
        gx, gy = it['grip']
        gl = it.get('glow')
        put(_on_group(it['spr'], o + mx - gx, o + my - gy), aim_deg, gl, gl_off=(mx - gx - ITEM_GLOW_PAD, my - gy - ITEM_GLOW_PAD))
    if head:
        hl = gear['head_replace'] if gear and gear.get('head_replace') is not None else kit.heads[head]
        put(_on_group(hl, o, o), aim_deg, kit.head_glow[kit.sp.head_names.index(head)] if kit.head_glow else None)
    if gear and gear.get('head') is not None:
        put(_on_group(gear['head'], o, o), aim_deg, gear.get('head_glow'), outer=gear.get('head_outer', False))
    if glow_out is not None:
        for g in glows:
            for y in range(G):
                for x in range(G):
                    p = g.p[y][x]
                    if p[3]: glow_out.p[y][x] = ([p[0], p[1], p[2], p[3]] if glow_out.p[y][x][3] == 0 else _addpix(glow_out.p[y][x], p))
    return out

def _addpix(d, p):
    a = min(255, d[3] + p[3])
    t = p[3] / 255.0
    return [min(255, int(d[0] + p[0] * t)), min(255, int(d[1] + p[1] * t)), min(255, int(d[2] + p[2] * t)), a]

def tint_spr(spr, tint, outfit_grey=cv2.OUTFIT_GREY):
    """Spr with outfit symbols -> RGBA (outfit tinted)."""
    return cv2.tinted_rgba(spr, tint)

def render(kit, leg_frame, leg_deg, aim_deg, pose, item=None, head=None, gear=None, tint=cv2.TEAL):
    """-> (figure Rgba with shadow, glow Rgba) on the 97x97 group canvas. Blit the figure over the floor, then add the glow."""
    glow_out = Rgba(G, G)
    f = compose(kit, leg_frame, leg_deg, aim_deg, pose, item, head, gear, glow_out)
    f = floor_shadow(f)
    return cv2.tinted_rgba(f, tint), glow_out
