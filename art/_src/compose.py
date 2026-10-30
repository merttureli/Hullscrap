"""Reference compositor: rotates interior-only layers (RotSprite-style), re-outlines, stacks them.
The game can do the same with nearest filtering, or pre-render 32 rotations at load time."""
import math
from px import *
from mach import outline_all
import crew_v2 as cv2

def _scale2x(s):
    n = Spr(s.w * 2, s.h * 2)
    for y in range(s.h):
        for x in range(s.w):
            P = s.g[y][x]; A = s.get(x, y - 1); B = s.get(x + 1, y); Cc = s.get(x - 1, y); D = s.get(x, y + 1)
            p1 = p2 = p3 = p4 = P
            if Cc == A and Cc != D and A != B: p1 = A
            if A == B and A != Cc and B != D: p2 = B
            if D == Cc and D != B and Cc != A: p3 = Cc
            if B == D and B != A and D != Cc: p4 = D
            n.g[2*y][2*x] = p1; n.g[2*y][2*x+1] = p2; n.g[2*y+1][2*x] = p3; n.g[2*y+1][2*x+1] = p4
    return n

def rotate(s, deg, cx, cy):
    """0 = up, positive = clockwise. Quarter turns are lossless; other angles: Scale2x x2, nearest at 4x, majority vote."""
    deg %= 360
    n = Spr(s.w, s.h)
    if deg % 90 == 0:
        q = deg // 90
        for y in range(s.h):
            for x in range(s.w):
                dx, dy = x - cx, y - cy
                sx, sy = [(dx, dy), (dy, -dx), (-dx, -dy), (-dy, dx)][q]
                xi, yi = cx + sx, cy + sy
                if 0 <= xi < s.w and 0 <= yi < s.h: n.g[y][x] = s.g[yi][xi]
        return n
    big = _scale2x(_scale2x(s))
    t = math.radians(deg); c, sn = math.cos(t), math.sin(t)
    bcx, bcy = cx * 4 + 2, cy * 4 + 2
    for y in range(s.h):
        for x in range(s.w):
            votes = {}
            for j in range(4):
                for i in range(4):
                    px_, py_ = x * 4 + i + 0.5 - bcx, y * 4 + j + 0.5 - bcy
                    u = c * px_ + sn * py_; v = -sn * px_ + c * py_
                    xi, yi = int(math.floor(bcx + u)), int(math.floor(bcy + v))
                    ch = big.g[yi][xi] if 0 <= xi < big.w and 0 <= yi < big.h else '.'
                    votes[ch] = votes.get(ch, 0) + 1
            if sum(v for k, v in votes.items() if k != '.') >= 8:
                n.g[y][x] = max((k for k in votes if k != '.'), key=lambda k: (votes[k], k))
    return n

G = 97; GC = 48          # group canvas and its centre
class Kit:
    """interior-only layers, built once."""
    def __init__(s):
        cv2.OUTLINE = False
        s.legs = cv2.legs(); s.torso = cv2.torso()
        s.arms = {p: cv2.arms(p) for p in cv2.POSES}
        s.heads = {h: cv2.head(h) for h in cv2.HEADS}
        s.items = {n: cv2.item(n) for n in cv2.ITEM_ART}
        cv2.OUTLINE = True

def _on_group(spr, ox, oy):
    g = Spr(G, G); g.stamp(ox, oy, spr.rows()); return g

def compose(kit, leg_frame, leg_deg, aim_deg, pose='unarmed', item=None, head='hair'):
    out = Spr(G, G); o = GC - cv2.C
    def put(layer, deg):
        r = rotate(layer, deg, GC, GC); outline_all(r); out.stamp(0, 0, r.rows())
    put(_on_group(kit.legs[leg_frame], o, o), leg_deg)
    put(_on_group(kit.torso, o, o), aim_deg)
    put(_on_group(kit.arms[pose], o, o), aim_deg)
    if item:
        mx, my = cv2.ARM[pose]['mount']
        gx, gy = cv2.item_anchors(item)['grip']
        put(_on_group(kit.items[item], o + mx - gx, o + my - gy), aim_deg)
    put(_on_group(kit.heads[head], o, o), aim_deg)
    return out

def floor_shadow(s, c='W'):
    n = s.copy()
    for y in range(s.h):
        for x in range(s.w):
            if s.g[y][x] != '.' and s.get(x + 1, y + 1) == '.' and n.get(x + 1, y + 1) == '.':
                n.put(x + 1, y + 1, c)
    return n

if __name__ == '__main__':
    kit = Kit()
    k = 5
    cases = [(6, 0, 0, 'unarmed', None, 'hair'), (0, 0, 0, 'pistol', 'pistol', 'helmet'), (3, 0, 0, 'rifle', 'rifle', 'hair'),
             (1, 0, 0, 'tool', 'wrench', 'helmet'), (0, 90, 0, 'tool', 'extinguisher', 'hair'), (3, 90, 45, 'rifle', 'rifle', 'helmet'),
             (2, 180, 135, 'pistol', 'pistol', 'hair'), (4, 270, 270, 'tool', 'wrench', 'helmet')]
    img = Rgba(G * k * 4, G * k * 2 + 33 * k, RGB['F'] + (255,))
    for i, (lf, ld, ad, pose, it, hd) in enumerate(cases):
        f = floor_shadow(compose(kit, lf, ld, ad, pose, it, hd))
        img.blit_rgba(cv2.tinted_rgba(f), (i % 4) * G * k, (i // 4) * G * k, k)
    cv2.OUTLINE = True
    for i, f in enumerate(cv2.legs()):
        img.blit_rgba(cv2.tinted_rgba(f), i * 33 * k, 2 * G * k, k)
    img.save(PREVIEW + '/preview/v2_crew.png')
