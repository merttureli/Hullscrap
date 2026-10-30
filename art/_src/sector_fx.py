"""Sector effects: the tractor beam strip (art/projectiles/tractor_beam.png) and the jump drive effects (art/fx/jump_spool.png, jump_flash.png).
Hard pixels in palette colours + their own soft glow layers (banded alpha, palette hues, like the other fx)."""
import json, math, os
from px import *
import pal_sector
from lines_kit import ring, circle, line

def halo_px(spr, w, h, ox, oy, bands, src, wrap_y=None, col=None):
    """banded soft glow for the lit letters in `src` (each lit pixel spreads colour over discrete alpha bands: (max distance px, alpha)); wrap_y tiles along y."""
    out = Rgba(w, h)
    rad = bands[-1][0]
    lit = [(x + ox, y + oy, spr.g[y][x]) for y in range(spr.h) for x in range(spr.w) if spr.g[y][x] in src]
    for (lx, ly, ch) in lit:
        c = RGB[col or ch]
        for y in range(int(ly - rad - 1), int(ly + rad + 2)):
            for x in range(int(lx - rad - 1), int(lx + rad + 2)):
                yy = y % wrap_y if wrap_y else y
                if not (0 <= x < w and 0 <= yy < h): continue
                d = math.hypot(x - lx, y - ly)
                for (md, al) in bands:
                    if d <= md:
                        if al > out.p[yy][x][3]: out.p[yy][x] = list(c) + [al]
                        break
    return out

def save_strip_rgba(frames, path):
    w, h = frames[0].w, frames[0].h
    out = Rgba(w * len(frames), h)
    for i, f in enumerate(frames): out.blit_rgba(f, i * w, 0)
    out.save(path)

def write_json(path, d):
    with open(path, 'w') as f: json.dump(d, f, indent=1); f.write('\n')

# ------------------------------------------------------------------ tractor beam: 12 wide x 16 tall, tiles along y; chevrons point at the turret and crawl toward it
def beam_frames():
    out = []
    for f in range(4):
        t = Spr(12, 16)
        for y in range(0, 16, 2): t.put(5, y, 'i'); t.put(6, y, 'i')                # a pale core thread, dotted
        for m in range(2):
            y0 = (f * 2 + m * 8) % 16                                               # shallow curved wavefronts, bowed toward the turret (down); they crawl down the strip
            for x in range(12):
                dx = abs(x - 5.5)
                off = int(round((5.5 - dx) * 0.34))
                if dx > 4.6 and (x + m) % 2: continue                               # the ends of each wave break up
                t.put(x, (y0 + off) % 16, 'H' if dx < 1 else 'h')
                t.put(x, (y0 + off + 1) % 16, 'i' if dx > 1.5 else 'h')
                if dx < 3.5: t.put(x, (y0 + off - 1) % 16, 'i')
        out.append(t)
    return out

def export_tractor_beam(art_dir=None):
    art_dir = art_dir or ART
    fr = beam_frames()
    save(sheet(fr, 4, 12, 16), art_dir + '/projectiles/tractor_beam.png')
    gl = [halo_px(f, 20, 16, 4, 0, ((1.3, 100), (2.6, 52), (4.0, 22)), 'hHi', wrap_y=16) for f in fr]
    save_strip_rgba(gl, art_dir + '/projectiles/tractor_beam_glow.png')
    write_json(art_dir + '/projectiles/tractor_beam.json', {
        'frame': [12, 16], 'length': 16, 'width': 12, 'orientation': 'up: the head (away from the turret) is at the top; the chevrons point DOWN, at the turret', 'tile': 'y',
        'anims': {'pull': [0, 4, 12]}, 'anchors': {'head': [6, 0], 'tail': [6, 15]},
        'glow': {'image': 'tractor_beam_glow.png', 'frame': [20, 16], 'offset': [-4, 0], 'anims': {'pull': [0, 4, 12]}, 'blend': 'add (preferred) or alpha-over', 'tile': 'y'},
        'notes': 'Tractor beam: a pale green-cyan pulling wave. V-shaped wavefronts crawl DOWN the strip, toward the turret (4 frames, 2 px a frame; they loop seamlessly), round a pale core thread. '
                 'Repeat the frame along y from the turret (tail) to the debris (head); use the same frame on every repeat for a clean wave or offset them for a ripple. No impact flare: the pulled chunk is the target.'})

# ------------------------------------------------------------------ jump spool: a ring of light tightening round the ship over 8 frames (64x64)
def spool_frames():
    out = []
    R = (29.0, 25.5, 22.0, 18.5, 15.5, 12.5, 10.0, 7.5)
    for f in range(8):
        s = Spr(64, 64)
        r = R[f]; th = (1.0, 1.0, 1.5, 1.5, 2.0, 2.0, 2.5, 3.0)[f]
        cols = (('b', 'b'), ('b', 'c'), ('b', 'c'), ('c', 'c'), ('c', 'H'), ('c', 'H'), ('H', 'H'), ('H', 'H'))[f]
        n = 14                                                                       # dashes round the ring; the gaps close as it tightens
        for y in range(64):
            for x in range(64):
                d = math.hypot(x + 0.5 - 32, y + 0.5 - 32)
                if abs(d - r) > th / 2.0 + 0.2: continue
                a = (math.degrees(math.atan2(y + 0.5 - 32, x + 0.5 - 32)) + f * 9.0) % 360
                u = (a / 360.0 * n) % 1.0
                if u < 0.45 + 0.07 * f:
                    s.put(x, y, cols[1] if (d < r) else cols[0])
        for k in range(8):                                                           # streaks of light falling inward, outside the ring
            a = math.radians(k * 45 + 22.5 + f * 4)
            r0 = r + 3 + (f % 2) * 2; ln = 5 if f < 5 else 3
            for q in range(ln):
                rr = r0 + q * 1.5
                x, y = int(32 + rr * math.cos(a)), int(32 + rr * math.sin(a))
                if 0 <= x < 64 and 0 <= y < 64: s.put(x, y, 'b' if q > 1 else 'c' if f > 2 else 'b')
        if f >= 5: circle(s, 32, 32, 1.4 + (f - 5) * 0.8, 'H')                        # the core charging
        if f == 7:
            for (dx, dy) in ((-4, 0), (4, 0), (0, -4), (0, 4)): s.put(32 + dx, 32 + dy, 'H')
        out.append(s)
    return out

def flash_frames():
    out = []
    for f in range(6):
        s = Spr(96, 96); cx = cy = 47.5
        if f == 0:
            circle(s, cx, cy, 5, 'c'); circle(s, cx, cy, 3.5, 'H')
            for k in range(-9, 10): s.put(int(cx + k), 47, 'c' if abs(k) > 4 else 'H'); s.put(47, int(cy + k), 'c' if abs(k) > 4 else 'H')
        elif f == 1:
            circle(s, cx, cy, 15, 'c'); circle(s, cx, cy, 12, 'H')
            for y in range(6, 90): s.rect(46, y, 4, 1, 'H' if 14 < abs(y - 47.5) < 30 else 'c')
            for x in range(22, 74): s.rect(x, 47, 1, 2, 'c')
        elif f == 2:
            circle(s, cx, cy, 30, 'b'); circle(s, cx, cy, 25, 'c'); circle(s, cx, cy, 21, 'H')
            for y in range(0, 96): s.rect(44, y, 8, 1, 'H' if abs(y - 47.5) < 40 else 'c')
            for x in range(10, 86): s.rect(x, 46, 1, 3, 'c')
        elif f == 3:
            ring(s, cx, cy, 33, 37, 'c'); ring(s, cx, cy, 31, 33, 'H'); circle(s, cx, cy, 12, 'H')
            for y in range(4, 92): s.rect(45, y, 6, 1, 'c' if abs(y - 47.5) > 20 else 'H')
        elif f == 4:
            ring(s, cx, cy, 40, 43, 'b'); ring(s, cx, cy, 39, 40, 'c'); circle(s, cx, cy, 6, 'H')
            for y in range(8, 88):
                if (y // 3) % 2 == 0: s.rect(46, y, 4, 1, 'b' if abs(y - 47.5) > 16 else 'c')
        else:
            for k in range(24):
                a = math.radians(k * 15 + 7)
                s.put(int(cx + 45 * math.cos(a)), int(cy + 45 * math.sin(a)), 'b' if k % 2 else 'k')
            for (dx, dy) in ((-3, 0), (3, 0), (0, -3), (0, 3), (0, 0)): s.put(48 + dx, 48 + dy, 'c')
            for y in range(20, 76, 5): s.put(47, y, 'b'); s.put(48, y + 2, 'b')
        out.append(s)
    return out

def export_jump(art_dir=None):
    art_dir = art_dir or ART
    fr = spool_frames()
    save(sheet(fr, 8, 64, 64), art_dir + '/fx/jump_spool.png')
    gl = [halo_px(f, 80, 80, 8, 8, ((1.6, 95), (3.4, 48), (5.4, 20)), 'cHb') for f in fr]
    save_strip_rgba(gl, art_dir + '/fx/jump_spool_glow.png')
    write_json(art_dir + '/fx/jump_spool.json', {
        'frame': [64, 64], 'cells': [4, 4], 'mode': 'once', 'anims': {'spool': [0, 8, 1]}, 'anchors': {'center': [32, 32]},
        'glow': {'image': 'jump_spool_glow.png', 'frame': [80, 80], 'offset': [-8, -8], 'anims': {'spool': [0, 8, 1]}, 'blend': 'add (preferred) or alpha-over'},
        'notes': 'Jump spool: a ring of light tightening round the ship over 8 frames (blue, then cyan, then white; the dashes close up and streaks fall inward, the core charges at the end). '
                 'The drive spools for 8 s, so play it at 1 fps (frame = floor(elapsed)) or stretch it with the spool timer; scale it up to the ship (it is drawn for a 4x4-cell ship) and hold the last frame until the flash.'})
    fr = flash_frames()
    save(sheet(fr, 6, 96, 96), art_dir + '/fx/jump_flash.png')
    gl = [halo_px(f, 112, 112, 8, 8, ((1.8, 100), (3.8, 52), (6.0, 24)), 'cHb') for f in fr]
    save_strip_rgba(gl, art_dir + '/fx/jump_flash_glow.png')
    write_json(art_dir + '/fx/jump_flash.json', {
        'frame': [96, 96], 'cells': [6, 6], 'mode': 'once', 'anims': {'flash': [0, 6, 14]}, 'anchors': {'center': [48, 48]},
        'glow': {'image': 'jump_flash_glow.png', 'frame': [112, 112], 'offset': [-8, -8], 'anims': {'flash': [0, 6, 14]}, 'blend': 'add (preferred) or alpha-over'},
        'notes': 'Jump flash, 6 frames at 14 fps: a spark, a white-out disc with a vertical streak (light speed runs along the ship\'s forward = up), a shock ring that expands and thins, then a few sparkles. '
                 'Play it on the ship the moment the jump fires, then remove the ship; the streak is drawn vertical, turn it with the ship.'})

if __name__ == '__main__':
    export_tractor_beam(); export_jump()
