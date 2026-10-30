"""Drifting debris for sector space ("Raft in space"): art/debris/<id>.png + .json, 4 tumble frames each (+ glow where it emits).
Each piece is a Layer stack (dbr.py), turned per frame and lit from the top-left every time. Palette letters only, 1 px near-black outline."""
import json, os, math
from px import *
import pal_sector
from dbr import *
from mach import glow

OUTDIR = ART + '/debris'
STEEL = 'EWSML'; RUST = 'nuQ'; COPPER = 'nuTY'; POLY = 'jkLH'; ICE = 'CizH'; CRYSTAL = 'BCcH'; TITAN = 'ExtL'; ROCK = 'nqQM'; GLASS = 'DEWS'
BIG = lambda u, v: -1.0                      # a sdf that is always inside: decals that cover the whole object

def steel(sdf, depth=1.6, top=1.4, **kw): return Layer(sdf, lambda u, v, d: bevel_h(d, depth, top), STEEL, lo=-0.2, hi=1.15, **kw)
def stripes(a, b, w=2, k=1):
    """diagonal hazard stripes (a/b letters) in object coordinates."""
    return lambda u, v, I, c: a if int(math.floor((u * k + v) / w)) % 2 == 0 else b

class Debris(Obj):
    id = '?'; material = ''; loop = 'wrap'; notes = ''; glow_rgb = None; extras = ()          # extras: [(anim name, [frame builders])]
    def extra_frames(s): return {}                                                              # name -> [Spr]
    def glow_frame(s, turn, i, g, ox, oy): pass

# ------------------------------------------------------------------ scrap
class ScrapS(Debris):
    id = 'scrap_chunk_s'; W = H = 16; material = 'scrap'
    notes = 'Scrap chunk S: a torn, bent hull plate with a rust patch, a fold and a bolt hole. Drops scrap 2-3.'
    PLATE = [(-6.3, -2.6), (-3.6, -6.0), (0.8, -4.7), (2.6, -6.4), (6.2, -3.4), (4.6, 0.8), (6.4, 4.4), (1.2, 6.2), (-1.8, 4.6), (-5.4, 5.2)]
    def layers(s):
        body = lambda u, v: sd_poly(u, v, s.PLATE)
        fold = lambda u, v: (v + 0.7 * u + 0.6) / 1.22                            # signed distance to a fold line
        rust = lambda u, v: sd_blob(u, v, 1.8, 2.8, 3.3, [(2, .25, 20), (3, .2, 80)])
        hole = lambda u, v: sd_circle(u, v, -2.6, -1.4, 1.15)
        return [Layer(body, lambda u, v, d: bevel_h(d, 1.5, 1.3) + 1.1 * max(0.0, min(2.0, fold(u, v))), STEEL, lo=-0.2, hi=1.15),
                Layer(rust, lambda u, v, d: 0.5 * blob_h(d, 1.5), RUST, solid=False, lo=-0.3, hi=0.9),
                Layer(hole, lambda u, v, d: -1.3, 'KDWS', solid=False, lo=-0.2, hi=1.0)]

class ScrapM(Debris):
    id = 'scrap_chunk_m'; W = H = 24; material = 'scrap'
    notes = 'Scrap chunk M: a plate wrapped round a bent girder, a scrap of hazard tape, rust and bolts. Drops scrap 3-5.'
    P1 = [(-9.4, -3.4), (-5.2, -8.4), (1.5, -7.2), (4.2, -9.8), (9.6, -4.6), (7.0, 1.6), (9.4, 6.2), (2.4, 8.6), (-3.0, 6.4), (-8.4, 7.6)]
    def layers(s):
        body = lambda u, v: sd_poly(u, v, s.P1)
        fold = lambda u, v: (v + 0.45 * u - 1.2) / 1.1
        girder = lambda u, v: sd_seg(u, v, -8.0, 7.4, 7.8, -7.8, 1.8)
        rust = lambda u, v: sd_blob(u, v, -3.6, -2.2, 3.6, [(2, .25, 0), (3, .22, 60)])
        tape = lambda u, v: sd_poly(u, v, [(1.0, -1.0), (7.5, -4.5), (8.5, -2.5), (2.0, 1.2)])
        hole = lambda u, v: sd_circle(u, v, 3.5, 4.8, 1.25)
        return [Layer(body, lambda u, v, d: bevel_h(d, 1.6, 1.3) + 1.0 * max(0.0, min(2.0, fold(u, v))), STEEL, lo=-0.2, hi=1.15),
                Layer(girder, lambda u, v, d: 1.2 + 1.0 * blob_h(d, 1.9), STEEL, lo=-0.1, hi=1.25),
                Layer(rust, lambda u, v, d: 0.5 * blob_h(d, 1.5), RUST, solid=False, lo=-0.3, hi=0.9),
                Layer(tape, lambda u, v, d: 0.3, None, paint=stripes('a', 'K', 1.7, 1.0), solid=False),
                Layer(hole, lambda u, v, d: -1.3, 'KDWS', solid=False, lo=-0.2, hi=1.0)]
    def specks(s, turn): return [(-7.4, 4.4, 'L'), (6.8, 2.4, 'L'), (-2.2, -6.4, 'L')]

class CopperCoil(Debris):
    id = 'copper_coil'; W = H = 16; material = 'copper'
    notes = 'Copper coil: a wound ring of copper wire with a steel clip and a bare end. Drops copper 1-3.'
    R, r0, TURNS = 6.7, 2.3, 10
    def layers(s):
        R, r0, N = s.R, s.r0, s.TURNS
        rm, rw = (R + r0) / 2, (R - r0) / 2
        ring = lambda u, v: abs(math.hypot(u, v) - rm) - rw
        def hgt(u, v, d):
            q = (math.hypot(u, v) - rm) / rw
            return rw * 1.1 * math.sqrt(max(0.0, 1 - q * q))
        def paint(u, v, I, c):
            ph = (math.atan2(v, u) / (2 * math.pi)) * N % 1.0
            if ph > 0.74: return 'n' if I < 0.4 else 'u'                       # the gap between two turns
            if ph < 0.22 and I > 0.5: return 'Y'                              # the lit shoulder of each turn
            return None
        clip = lambda u, v: sd_box(u, v, 0.0, -rm, 1.5, 2.1)
        return [Layer(ring, hgt, COPPER, paint=paint, lo=0.0, hi=1.05),
                Layer(clip, lambda u, v, d: 1.1, 'EWSM', solid=False, lo=-0.2, hi=1.15)]
    def specks(s, turn): return [(0.0, -s.R + 0.4, 'y')]

class PolymerBarrel(Debris):
    id = 'polymer_barrel'; W, H = 16, 24; material = 'polymer'; loop = 'pingpong'
    turns = (-12, -4, 4, 12)
    notes = 'Polymer barrel: a pale blue-white drum with two steel hoops, a bung and an amber hazard label. Drops polymer 2.'
    def layers(s):
        body = lambda u, v: sd_rbox(u, v, 0, 0, 4.8, 9.4, 1.8)
        def hgt(u, v, d): return 3.6 * math.sqrt(max(0.0, 1 - (u / 4.8) ** 2)) * min(1.0, -d / 1.2)
        hoop = lambda cy: (lambda u, v: sd_box(u, v, 0, cy, 5.2, 0.8))
        bung = lambda u, v: sd_circle(u, v, -1.6, -7.2, 1.3)
        label = lambda u, v: sd_box(u, v, 0, 0.6, 2.9, 2.0)
        lab = lambda u, v, I, c: 'a' if ((int(math.floor(u + 20)) + int(math.floor(v + 20))) // 2) % 2 == 0 else 'K'
        return [Layer(body, hgt, POLY, lo=-0.05, hi=1.05),
                Layer(hoop(-4.8), lambda u, v, d: 0.5, 'WSMM', solid=False, lo=-0.1, hi=1.0),
                Layer(hoop(5.6), lambda u, v, d: 0.5, 'WSMM', solid=False, lo=-0.1, hi=1.0),
                Layer(bung, lambda u, v, d: 0.6 * blob_h(d, 1.3), 'EWSM', solid=False, lo=-0.1, hi=1.1),
                Layer(label, None, None, paint=lab, solid=False)]

class IceS(Debris):
    id = 'ice_chunk_s'; W = H = 16; material = 'ice'
    notes = 'Ice chunk S: a faceted lump of pale cyan ice with frost glints. Refills O2 a little when collected.'
    def layers(s):
        return [solid_planes([(200, 1.0, 5.4), (250, 0.9, 6.7), (305, 1.1, 5.6), (355, 0.8, 6.6), (50, 1.0, 5.2), (100, 0.9, 6.5), (150, 1.1, 5.5), (0, 0, 3.2)], ICE, lo=-0.1, hi=1.05)]
    def specks(s, turn): return [(-2.4, -2.6, 'H')]

class TitaniumPlate(Debris):
    id = 'titanium_plate'; W, H = 24, 16; material = 'titanium'; loop = 'pingpong'
    turns = (-9, -3, 3, 9)
    notes = 'Titanium plate: a clean, bevelled cool-grey armour plate with a diagonal sheen. Drops titanium 1-2.'
    def layers(s):
        P = [(-9.6, -5.0), (6.6, -5.4), (9.6, -2.2), (9.6, 5.2), (-6.2, 5.4), (-9.6, 2.2)]
        body = lambda u, v: sd_poly(u, v, P)
        def sheen(u, v, I, c):
            d = (c.x + c.y) - 1.0
            if abs(d) < 0.9: return 'H'
            if -3.0 < d < -1.6: return 't'
            return None
        return [Layer(body, lambda u, v, d: bevel_h(d, 1.3, 1.1), TITAN, paint=sheen, lo=-0.1, hi=1.5)]

def shard(hw, hl, tl, tilt=0.0, cx=0.0, cy=0.0, slope=1.2):
    """height function of a pointed prism: half-width hw, half-length hl, tip length tl; left face, right face and a leaning cap, tilted and moved."""
    N = math.hypot(hw, tl); a_tip = math.degrees(math.atan2(-hw, tl)); r_tip = hw * hl / N
    spec = [(180, slope, hw), (0, slope, hw), (45, 0.35, 4.6), (a_tip, 1.0, r_tip), (180 - a_tip, 1.0, r_tip), (-a_tip, 1.0, r_tip), (180 + a_tip, 1.0, r_tip)]
    H = planes([(a + tilt, sl, r) for (a, sl, r) in spec])
    return lambda u, v: H(*rot(u, v, 0.0, cx, cy))

class CrystalShard(Debris):
    id = 'crystal_shard'; W = H = 16; material = 'crystal'; glow_rgb = (60, 242, 255)
    notes = 'Crystal shard: a cyan prism with a smaller shard beside it; it glows. Drops crystal 1.'
    def layers(s):
        Hs = [shard(1.5, 3.7, 2.0, 52, 3.4, 2.6), shard(1.9, 4.8, 2.5, -36, -3.0, 1.6), shard(2.6, 6.2, 3.3, 12, 0.8, -0.8)]
        mk = lambda H: Layer(lambda u, v: -H(u, v), lambda u, v, d: -d, CRYSTAL, mode='set', lo=-0.1, hi=1.3)
        return [mk(H) for H in Hs]
    def glow_frame(s, turn, i, g, ox, oy):
        glow(g, ox + 8, oy + 8, 11, (60, 242, 255), (0.40, 0.48, 0.40, 0.32)[i], 2.0)


class IceM(Debris):
    id = 'ice_chunk_m'; W = H = 24; material = 'ice'
    notes = 'Ice chunk M: a big faceted block of pale ice with frost cracks and bubbles. Refills O2 when collected.'
    def layers(s):
        sp = [(190, 1.0, 8.4), (232, 0.8, 10.4), (270, 1.1, 9.2), (318, 0.9, 10.6), (5, 1.0, 8.8), (48, 0.85, 10.2), (92, 1.1, 8.6), (140, 0.9, 10.0), (0, 0, 5.0)]
        crack = lambda u, v: polyline_sd(u, v, [(-6.5, -3.0), (-3.0, -1.0), (-1.5, 3.0), (2.5, 5.5)], 0.45)
        return [solid_planes(sp, ICE, lo=-0.1, hi=1.05),
                Layer(crack, lambda u, v, d: -0.5, 'CCi', solid=False, lo=0.0, hi=1.0)]
    def specks(s, turn): return [(-4.6, -5.0, 'H'), (3.4, -2.6, 'H'), (1.2, 2.4, 'z'), (-3.4, 4.6, 'z')]

class SiliconRock(Debris):
    id = 'silicon_rock'; W = H = 24; material = 'silicon'
    notes = 'Silicon rock: dark grey-blue rock with cleaved, glassy faces that catch the light. Drops silicon 1-2.'
    def layers(s):
        sp = [(196, 0.9, 9.6), (240, 0.8, 9.0), (285, 1.0, 10.0), (335, 0.85, 9.4), (20, 0.9, 10.2), (68, 0.8, 9.2), (112, 1.0, 9.8), (155, 0.9, 9.5), (0, 0, 4.4)]
        glass = lambda pts: Layer(lambda u, v: sd_poly(u, v, pts), lambda u, v, d: 0.9, 'xtH', paint=None, solid=False, lo=0.2, hi=1.0)
        noise = Layer(BIG, lambda u, v, d: 1.1 * (fbm(u / 2.6 + 9, v / 2.6 + 4, 5) - 0.5), None, solid=False)
        return [solid_planes(sp, GLASS, lo=-0.25, hi=1.25), noise,
                glass([(-6.5, -4.5), (-1.5, -7.0), (1.0, -3.6), (-3.8, -1.6)]),
                glass([(2.0, 1.5), (7.0, -1.0), (8.0, 3.5), (3.5, 5.5)]),
                glass([(-6.0, 3.0), (-2.5, 2.2), (-1.5, 6.0), (-5.0, 7.0)])]
    def specks(s, turn): return [(-3.4, -5.0, 'H'), (5.0, 1.0, 'H'), (-4.2, 4.2, 'H')]

class OreRock(Debris):
    id = 'ore_rock_s'; W = H = 24; material = 'ore'
    notes = 'Ore rock S: a brown-grey rock with craters and copper/iron vein specks. Shoot it to break it into chunks.'
    SP = [(196, 0.8, 9.6), (242, 0.9, 9.0), (292, 0.8, 10.0), (340, 0.9, 9.2), (22, 0.8, 10.2), (70, 0.9, 9.2), (118, 0.8, 9.8), (160, 0.9, 9.4), (0, 0, 4.2)]
    CRATERS = [(-3.0, 3.6, 2.8, 1.6), (4.6, -3.8, 2.0, 1.2)]
    VEINS = [([(-6.8, -2.4), (-4.0, -3.4), (-1.2, -2.6), (1.0, -4.8)], 'T'), ([(2.0, 3.0), (4.6, 1.6), (7.0, 2.4)], 'a')]
    SPECKS = [(-4.0, -3.4, 'Y'), (-1.2, -2.6, 'Y'), (1.0, -4.8, 'T'), (4.6, 1.6, 'y'), (7.0, 2.4, 'a')]
    seed = 11
    def layers(s):
        L = [solid_planes(s.SP, ROCK, lo=-0.2, hi=1.6),
             Layer(BIG, lambda u, v, d: 1.4 * (fbm(u / 3.0 + s.seed, v / 3.0 + 2, s.seed, 3) - 0.5), None, solid=False)]
        for (cx, cy, r, dp) in s.CRATERS:
            L.append(Layer(lambda u, v, cx=cx, cy=cy, r=r: sd_circle(u, v, cx, cy, r),
                           lambda u, v, d, cx=cx, cy=cy, r=r, dp=dp: -dp * (1 - (math.hypot(u - cx, v - cy) / r) ** 2), None, solid=False))
        for (pts, col) in s.VEINS:
            ramp = {'T': 'uTY', 'a': 'uay', 'x': 'Wxt', 'c': 'BCc'}[col]
            L.append(Layer(lambda u, v, pts=pts: polyline_sd(u, v, pts, 0.7), lambda u, v, d: 0.2, ramp, solid=False, lo=0.0, hi=1.0))
        return L
    def specks(s, turn): return list(s.SPECKS)

class OreRockL(OreRock):
    id = 'ore_rock_l'; W = H = 48
    notes = ('Ore rock L: a big asteroid chunk with craters and visible ore veins (copper orange, iron rust, titanium pale, a little crystal cyan). '
             'cracked_1 / cracked_2 are the damage stages (turn 0): fissures, then the rock split apart. Break it into chunks with any weapon.')
    SP = [(190, 0.7, 20.0), (222, 0.8, 19.0), (255, 0.7, 21.0), (288, 0.8, 19.6), (322, 0.7, 21.2), (355, 0.8, 20.0), (28, 0.7, 21.0), (62, 0.8, 19.4), (96, 0.7, 20.6), (130, 0.8, 19.0), (160, 0.7, 20.8), (0, 0, 8.5)]
    CRATERS = [(-7.0, 8.0, 5.4, 2.8), (9.0, -9.0, 4.0, 2.2), (6.0, 11.0, 3.0, 1.6), (-12.0, -9.0, 2.6, 1.4)]
    VEINS = [([(-16, -4), (-11, -6), (-6, -4.5), (-1, -8), (3, -14)], 'T'), ([(4, 4), (9, 2), (14, 5), (18, 3)], 'a'),
             ([(-14, 12), (-9, 14), (-6, 18)], 'x'), ([(0, 10), (2, 14), (5, 17)], 'c')]
    SPECKS = [(-11, -6, 'Y'), (-6, -4.5, 'Y'), (-1, -8, 'T'), (3, -14, 'y'), (9, 2, 'y'), (14, 5, 'a'), (18, 3, 'y'), (-9, 14, 't'), (-6, 18, 'H'), (2, 14, 'H'), (5, 17, 'c'), (-16, -4, 'Y')]
    seed = 23
    def layers(s):
        L = OreRock.layers(s)
        return L
    def crack_stage(s, n):
        spr = s.render(0, outline=False)
        main = [(14, -19), (10, -11), (11, -4), (5, 2), (4, 9), (-3, 14), (-5, 21)]
        cr = [main, [(11, -4), (18, 0), (22, 6)], [(5, 2), (-4, 0), (-12, 3)]]
        cr2 = [[(-17, -14), (-9, -9), (-4, -3), (5, 2)], [(4, 9), (12, 13), (17, 18)], [(-4, 0), (-8, 7), (-13, 9)]]
        if n > 1:                                           # the rock splits along the main fissure: the far half slides away, the gap shows dark
            moved = Spr(spr.w, spr.h)
            for y in range(spr.h):
                for x in range(spr.w):
                    c = spr.g[y][x]
                    if c == '.': continue
                    px_, py_ = x - 24, y - 24
                    side = min(((b[0] - a[0]) * (py_ - a[1]) - (b[1] - a[1]) * (px_ - a[0]), abs(px_ - a[0]) + abs(py_ - a[1])) for a, b in zip(main, main[1:]))
                    far = max(((b[0] - a[0]) * (py_ - a[1]) - (b[1] - a[1]) * (px_ - a[0])) for a, b in zip(main, main[1:])) if False else side[0]
                    moved.put(x + (2 if far < 0 else 0), y + (1 if far < 0 else 0), c)
            spr = moved
        for pts in (cr + (cr2 if n > 1 else [])):
            for (a, b) in zip(pts, pts[1:]):
                steps = int(max(abs(b[0] - a[0]), abs(b[1] - a[1])) * 2) + 1
                for k in range(steps + 1):
                    x = a[0] + (b[0] - a[0]) * k / steps; y = a[1] + (b[1] - a[1]) * k / steps
                    ix, iy = int(math.floor(x + 24)), int(math.floor(y + 24))
                    if spr.get(ix, iy) != '.':
                        spr.g[iy][ix] = 'K'
                        if spr.get(ix + 1, iy + 1) not in ('.', 'K') and (ix + iy) % 3 == 0: spr.g[iy + 1][ix + 1] = 'Q'
        add_outline(spr)
        return spr
    def extra_frames(s): return {'cracked_1': [s.crack_stage(1)], 'cracked_2': [s.crack_stage(2)]}


class PlasmaCanister(Debris):
    id = 'plasma_canister'; W, H = 16, 24; material = 'plasma'; loop = 'pingpong'; glow_rgb = (255, 79, 216)
    turns = (-12, -4, 4, 12)
    notes = 'Plasma canister: a steel bottle with a window full of swirling magenta plasma; it glows. A rare plasma cell, found near anomalies.'
    def layers(s):
        body = lambda u, v: sd_rbox(u, v, 0, 0, 4.8, 9.5, 2.0)
        def hgt(u, v, d): return 3.4 * math.sqrt(max(0.0, 1 - (u / 4.8) ** 2)) * min(1.0, -d / 1.2)
        cap = lambda cy: (lambda u, v: sd_box(u, v, 0, cy, 5.2, 1.2))
        win = lambda u, v: sd_rbox(u, v, 0, 0.0, 2.5, 5.0, 1.2)
        def plasma(u, v, I, c):
            r = abs(u) / 2.5; core = 1.0 - r * 0.95 - 0.22 * abs(math.sin(v * 1.25 + 0.6))
            return 'H' if core > 0.72 else 'X' if core > 0.46 else 'm' if core > 0.2 else 'P'
        return [Layer(body, hgt, STEEL, lo=-0.2, hi=1.15),
                Layer(cap(-8.4), lambda u, v, d: 0.6, 'DEWS', solid=False, lo=-0.1, hi=1.1),
                Layer(cap(8.4), lambda u, v, d: 0.6, 'DEWS', solid=False, lo=-0.1, hi=1.1),
                Layer(win, lambda u, v, d: -0.9, 'KDW', paint=plasma, solid=False)]
    def specks(s, turn): return [(-3.4, -8.4, 'a'), (3.4, 8.4, 'a'), (0, -6.6, 'L')]
    def glow_frame(s, turn, i, g, ox, oy):
        glow(g, ox + 8, oy + 12, 12, (255, 79, 216), (0.40, 0.50, 0.40, 0.30)[i], 2.0)

class FuelCanister(Debris):
    id = 'fuel_canister'; W, H = 16, 24; material = 'fuel'; loop = 'pingpong'; glow_rgb = (255, 138, 30)
    turns = (-12, -4, 4, 12)
    notes = 'Fuel canister: an amber jerrycan with a steel handle, a red cap, an embossed cross and a glowing gauge; rare. Drops fuel 1.'
    FUEL = 'uayH'
    P = [(-5.0, -4.2), (-1.0, -4.8), (2.4, -4.8), (5.0, -2.4), (5.0, 8.6), (-5.0, 8.6)]
    def layers(s):
        body = lambda u, v: sd_poly(u, v, s.P)
        handle = lambda u, v: max(sd_rbox(u, v, -1.6, -7.2, 3.6, 2.8, 1.2), -sd_box(u, v, -1.6, -7.4, 2.0, 0.9))
        cap = lambda u, v: sd_circle(u, v, 3.2, -5.6, 1.7)
        x1 = lambda u, v: sd_seg(u, v, -3.6, -1.6, 3.6, 6.8, 0.4)
        x2 = lambda u, v: sd_seg(u, v, 3.6, -1.6, -3.6, 6.8, 0.4)
        gauge = lambda u, v: sd_box(u, v, 0, 2.6, 1.4, 1.9)
        gp = lambda u, v, I, c: 'H' if v < 1.1 else ('y' if v < 2.5 else 'o')
        return [Layer(body, lambda u, v, d: bevel_h(d, 1.4, 1.2), s.FUEL, lo=-0.3, hi=1.65),
                Layer(handle, lambda u, v, d: bevel_h(d, 1.0, 1.0), 'EWSM', lo=-0.2, hi=1.2),
                Layer(x1, lambda u, v, d: -0.5, s.FUEL, solid=False, lo=-0.3, hi=1.65),
                Layer(x2, lambda u, v, d: -0.5, s.FUEL, solid=False, lo=-0.3, hi=1.65),
                Layer(cap, lambda u, v, d: 0.6 + blob_h(d, 1.5), 'nrro', lo=-0.1, hi=1.1),
                Layer(gauge, lambda u, v, d: -0.8, 'KDW', paint=gp, solid=False)]
    def specks(s, turn): return [(-3.8, 7.2, 'y')]
    def glow_frame(s, turn, i, g, ox, oy):
        glow(g, ox + 8, oy + 14, 11, (255, 138, 30), (0.34, 0.42, 0.34, 0.28)[i], 2.0)

class Crate(Debris):
    id = 'sealed_crate'; W = H = 24; material = 'crate'
    notes = 'Sealed crate: a brown cargo crate with steel corner brackets, an amber seal band and a latch. Shoot it open: 1-2 random items or materials. `broken` is the burst crate left behind.'
    def layers(s):
        body = lambda u, v: sd_rbox(u, v, 0, 0, 10.4, 10.4, 1.4)
        panel = lambda u, v: sd_rbox(u, v, 0, 0, 6.8, 6.8, 0.8)
        brk = lambda sx, sy: (lambda u, v: sd_box(u, v, sx * 8.2, sy * 8.2, 2.5, 2.5))
        L = [Layer(body, lambda u, v, d: bevel_h(d, 2.0, 1.3), 'nqQM', lo=-0.2, hi=1.5),
             Layer(panel, lambda u, v, d: -0.9 + 0.5 * min(1.0, -d / 1.0), 'nqQM', solid=False, lo=-0.2, hi=1.5)]
        for sx in (-1, 1):
            for sy in (-1, 1): L.append(Layer(brk(sx, sy), lambda u, v, d: 0.7, 'WSM', solid=False, lo=-0.2, hi=1.2))
        L.append(Layer(lambda u, v: sd_box(u, v, 0, 0, 10.4, 1.5), lambda u, v, d: 0.6, 'uay', solid=False, lo=-0.1, hi=1.5))
        L.append(Layer(lambda u, v: sd_box(u, v, 0, 0, 2.2, 2.2), lambda u, v, d: 0.9, 'EWSM', solid=False, lo=-0.2, hi=1.2))
        return L
    def specks(s, turn): return [(0, 0, 'r'), (-8.2, -8.2, 'L'), (8.2, 8.2, 'L'), (-8.2, 8.2, 'L'), (8.2, -8.2, 'L')]
    def extra_frames(s): return {'broken': [BrokenCrate().render(0)]}

class BrokenCrate(Debris):
    id = 'sealed_crate_broken'; W = H = 24
    def layers(s):
        pan = lambda pts: Layer(lambda u, v: sd_poly(u, v, pts), lambda u, v, d: bevel_h(d, 1.5, 1.2), 'nqQM', lo=-0.2, hi=1.5)
        void = Layer(lambda u, v: sd_poly(u, v, [(-5.5, -4.5), (0.5, -6.5), (6.0, -3.5), (5.5, 3.5), (-0.5, 6.0), (-6.0, 3.0)]), lambda u, v, d: -1.0, 'KDE', lo=-0.5, hi=1.0)
        return [void,
                pan([(-10.5, -6.5), (-3.5, -10.5), (-1.5, -5.5), (-8.5, -2.5)]),
                pan([(2.5, -10.0), (10.5, -7.0), (9.0, -2.5), (2.0, -5.0)]),
                pan([(-10.5, 3.0), (-3.0, 1.5), (-2.5, 8.0), (-9.0, 10.5)]),
                pan([(3.0, 2.0), (10.5, 3.5), (9.5, 10.0), (3.5, 7.5)]),
                Layer(lambda u, v: sd_poly(u, v, [(-1, -10.8), (3, -11), (2, -9)]), lambda u, v, d: 0.5, 'nqQ', lo=-0.2, hi=1.2)]
    def specks(s, turn): return [(-2.0, -1.0, 'Y'), (1.5, 1.0, 'a'), (-1.0, 2.5, 'M'), (2.5, -2.0, 'T'), (0.5, -3.0, 'k'), (-3, 0.5, 'a')]

class DeadDrone(Debris):
    id = 'dead_drone'; W = H = 24; material = 'drone'
    notes = 'Dead drone: a dead quad-rotor maintenance drone, one arm snapped, lens dark, scorched. Salvage it for a chance of a component.'
    def layers(s):
        L = []
        for (sx, sy, ok) in ((-1, -1, True), (1, -1, True), (-1, 1, True), (1, 1, False)):
            cx, cy = sx * 7.6, sy * 7.6
            L.append(Layer(lambda u, v, a=sx, b=sy: sd_seg(u, v, 0, 0, a * (5.4 if ok else 3.6), b * (5.4 if ok else 3.6), 1.1), lambda u, v, d: 0.9 * blob_h(d, 1.1), STEEL, lo=-0.2, hi=1.2))
        for (sx, sy, ok) in ((-1, -1, True), (1, -1, True), (-1, 1, True)):
            cx, cy = sx * 7.6, sy * 7.6
            L.append(Layer(lambda u, v, cx=cx, cy=cy: sd_circle(u, v, cx, cy, 3.6), lambda u, v, d: 1.2 * blob_h(d, 2.0), 'DEWS', lo=-0.2, hi=1.2))
            L.append(Layer(lambda u, v, cx=cx, cy=cy: min(sd_seg(u, v, cx - 2.9, cy, cx + 2.9, cy, 0.4), sd_seg(u, v, cx, cy - 2.9, cx, cy + 2.9, 0.4)), lambda u, v, d: 0.4, 'WSM', solid=False, lo=-0.2, hi=1.2))
        L.append(Layer(lambda u, v: sd_circle(u, v, 0, 0, 5.6), lambda u, v, d: 1.5 * blob_h(d, 3.0), STEEL, lo=-0.2, hi=1.15))
        L.append(Layer(lambda u, v: sd_blob(u, v, -1.6, -1.8, 2.4, [(2, .2, 0)]), lambda u, v, d: 0.3, None, paint=lambda u, v, I, c: 'a' if I > 0.35 else 'u', solid=False))
        L.append(Layer(lambda u, v: sd_circle(u, v, 0.8, 0.8, 2.1), lambda u, v, d: -1.2, 'KDW', solid=False, lo=-0.3, hi=1.1))
        L.append(Layer(lambda u, v: sd_blob(u, v, 5.2, 6.4, 2.6, [(3, .3, 40)]), lambda u, v, d: 0.0, 'nDE', solid=False, lo=-0.5, hi=1.0))
        return L
    def specks(s, turn): return [(0.4, 0.4, 'W'), (-3.4, 3.6, 'r'), (4.0, 3.8, 'u'), (4.8, 5.4, 'Y'), (6.0, 6.2, 'o'), (-6.6, 4.4, 'L')]

# ------------------------------------------------------------------ fragments: 8x8, neutral greys (the game multiplies a material tint over them)
FRAGMENTS = [art("""
..KKKK..
.KMLLSK.
KLMMSSWK
KMMSSWWK
KMSSWWEK
.KSWWEK.
..KKKK..
........
"""), art("""
........
..KKK...
.KLMSK..
KLMSWK..
KMSWEK..
.KSEEK..
..KKK...
........
"""), art("""
...KK...
..KMLK..
.KMLMSK.
KMLMSWWK
KMSSWWWK
.KKKKKK.
........
........
"""), art("""
.KKKK...
KLMSSK..
KMSSWWK.
KSSWWEK.
.KWWEEK.
..KEEK..
...KK...
........
""")]

OBJS = [ScrapS, ScrapM, CopperCoil, PolymerBarrel, IceS, IceM, TitaniumPlate, SiliconRock, CrystalShard, PlasmaCanister, Crate, OreRock, OreRockL, DeadDrone, FuelCanister]

def build(O):
    """-> (frames, glow frames or None, {anim: [first, count, fps]}, json). Tumble frames first, then the extras (broken / cracked)."""
    o = O()
    fr = [o.render(t) for t in o.turns]
    anims = {'tumble': [0, len(fr), 3]}
    for name, lst in o.extra_frames().items():
        anims[name] = [len(fr), len(lst), 0]; fr += lst
    if 'cracked_1' in anims: anims['cracked'] = [anims['cracked_1'][0], 2, 0]
    for i, f in enumerate(fr):
        assert not touches_border(f), '%s frame %d touches the frame edge' % (o.id, i)
    gl = None
    if o.glow_rgb:
        pad = 8
        gl = []
        for i in range(len(o.turns)):
            g = Rgba(o.W + 2 * pad, o.H + 2 * pad); o.glow_frame(o.turns[i], i, g, pad, pad); gl.append(g)
    J = {'frame': [o.W, o.H], 'anims': anims}
    if gl:
        gw, gh = o.W + 16, o.H + 16
        J['glow'] = {'image': o.id + '_glow.png', 'frame': [gw, gh], 'offset': [-8, -8], 'anims': {'tumble': [0, len(gl), 3]}}
    J['anchors'] = {'center': [o.W // 2, o.H // 2]}
    J['tumble_deg'] = list(o.turns); J['loop'] = o.loop; J['material'] = o.material
    J['notes'] = o.notes + (' Frames are the piece turned %s degrees, lit from the top-left each time; loop them %s (`wrap` = 1,2,3,4,1... ; `pingpong` = 1,2,3,4,3,2,...), the game may also rotate the node. ' % (list(o.turns), o.loop)) + \
                 ('`cracked_1` / `cracked_2` = damage stages, `broken` = the burst crate left behind. ' if len(anims) > 2 else '') + ('Glow layer: additive, pulsing a little per frame.' if gl else '')
    return fr, gl, anims, J

def export(outdir=None):
    outdir = outdir or OUTDIR
    os.makedirs(outdir, exist_ok=True)
    for O in OBJS:
        fr, gl, anims, J = build(O)
        save(sheet(fr, len(fr), fr[0].w, fr[0].h), '%s/%s.png' % (outdir, O.id))
        if gl:
            strip = Rgba(gl[0].w * len(gl), gl[0].h)
            for k, g in enumerate(gl): strip.blit_rgba(g, k * gl[0].w, 0)
            strip.save('%s/%s_glow.png' % (outdir, O.id))
        with open('%s/%s.json' % (outdir, O.id), 'w') as f: json.dump(J, f, indent=1); f.write('\n')
        print(O.id, J['frame'], list(anims))
    for f in FRAGMENTS: assert len(f) == 8 and all(len(r) == 8 for r in f)
    fs = [from_art(f) for f in FRAGMENTS]
    save(sheet(fs, 4, 8, 8), outdir + '/fragment.png')
    J = {'frame': [8, 8], 'anims': {'v%d' % i: [i, 1, 0] for i in range(4)}, 'variants': 4, 'anchors': {'center': [4, 4]}, 'material': 'any',
         'notes': 'Fragments: the small chunk breaking a piece leaves behind, 4 variants in neutral greys (chunk, sliver, wedge, nugget). Multiply a material tint over them (copper, ice, scrap...); pick a variant per chunk, turn freely.'}
    with open(outdir + '/fragment.json', 'w') as f: json.dump(J, f, indent=1); f.write('\n')
    print('fragment', J['frame'], list(J['anims']))

if __name__ == '__main__':
    import sys
    if len(sys.argv) > 1 and sys.argv[1] == 'export': export()
    else:
        from dview import show
        show(OBJS, sys.argv[1] if len(sys.argv) > 1 else '/tmp/dv.png')
