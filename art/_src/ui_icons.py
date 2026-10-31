"""The UI icons, drawn pixel by pixel: 18 resource icons (16x16), 7 mode icons (24x24), 7 category icons (16x16), 4 cursors (16x16, hotspots in the JSON).
Each is an ASCII map on the shared palette, light from the top-left, 3 tones per material, outlined 1 px in near-black by `finish()`.
Family colours as everywhere: power green, shield blue, O2 pale cyan, heat orange, amber for hull / credits, workshop violet, neon cyan, plasma orange."""
import math, textwrap
from px import *
import pal_sector
from mach import bev, outline_all
from lines_kit import circle, ring, line, thick


def ico(rows, size=16, dx=0, dy=0):
    """an ASCII map -> a size x size Spr, centred (+ dx, dy), not yet outlined. Rows must share one width."""
    rows = [r.rstrip() for r in textwrap.dedent(rows).strip('\n').split('\n')]
    w = {len(r) for r in rows}
    assert len(w) == 1, 'ragged icon rows %s' % sorted(w)
    s = Spr(size, size)
    ww, hh = len(rows[0]), len(rows)
    assert ww <= size - 2 and hh <= size - 2, 'icon art %dx%d too big for %d' % (ww, hh, size)
    s.stamp((size - ww) // 2 + dx, (size - hh) // 2 + dy, rows)
    return s


def finish(s):
    """outline the silhouette 1 px in near-black."""
    outline_all(s)
    return s


def lit_disc(s, cx, cy, r, tones):
    """a disc shaded from the top-left: tones = (light, mid, dark)."""
    for y in range(s.h):
        for x in range(s.w):
            dx, dy = x + .5 - cx, y + .5 - cy
            if math.hypot(dx, dy) <= r:
                k = (dx + dy) / (2 * r) if r else 0
                s.put(x, y, tones[0] if k < -0.38 else tones[2] if k > 0.42 else tones[1])


def poly(s, pts, c):
    n = len(pts)
    for y in range(s.h):
        for x in range(s.w):
            inside = False
            for k in range(n):
                ax, ay = pts[k]; bx, by = pts[(k + 1) % n]
                if (ay > y + .5) != (by > y + .5) and x + .5 < (bx - ax) * (y + .5 - ay) / (by - ay) + ax: inside = not inside
            if inside: s.put(x, y, c)


def ingot(w, h, hi, mid, lo, glint=None):
    """a bevelled bar with chamfered corners, outlined; (w, h) is the art, the result is 2 px bigger."""
    s = Spr(w + 2, h + 2)
    bev(s, 1, 1, w, h, hi, mid, lo)
    if glint: s.put(2, 2, glint)
    outline_all(s)
    return s


def paste(dst, src, x, y):
    for j in range(src.h):
        for i in range(src.w):
            c = src.g[j][i]
            if c != '.': dst.put(x + i, y + j, c)


# ====================================================================== resource icons, 16x16
def r_scrap():
    """a broken cog: steel teeth, a bite missing from the lower right, rust patches."""
    s = Spr(16, 16)
    for y in range(16):
        for x in range(16):
            dx, dy = x + .5 - 7.6, y + .5 - 8.0
            d = math.hypot(dx, dy)
            a = math.atan2(dy, dx)
            tooth = (int(round((a + math.pi) / (math.pi / 4))) % 2 == 0) or abs(((a + math.pi) / (math.pi / 4)) % 1 - .5) > .22
            rr = 6.7 if tooth else 5.3
            if d <= rr and d > 2.3:
                k = (dx + dy) / 11.0
                s.put(x, y, 'M' if k < -0.28 else 'W' if k > 0.3 else 'S')
    for (x, y) in ((11, 11), (12, 11), (12, 12), (11, 12), (13, 12), (12, 13), (13, 13), (13, 11), (12, 10)): s.erase(x, y)     # the bite
    for (x, y) in ((4, 6), (5, 6), (4, 7), (9, 3), (10, 3), (3, 10), (4, 10), (7, 12), (8, 12)): s.put(x, y, 'u')               # rust
    for (x, y) in ((4, 5), (9, 2)): s.put(x, y, 'T')
    s.put(5, 4, 'L'); s.put(4, 5, 'L')
    outline_all(s)
    return s


def r_copper():
    s = Spr(16, 16)
    a = ingot(6, 4, 'Y', 'T', 'u', 'H')
    paste(s, a, 0, 9); paste(s, a, 7, 9)
    paste(s, a, 3, 4)
    return s


def r_polymer():
    s = Spr(16, 16)
    for (cx, cy, r) in ((5, 10.5, 3.7), (11, 10.5, 3.7), (8, 5.6, 3.7)):
        t = Spr(16, 16); lit_disc(t, cx, cy, r, ('z', 'k', 'x')); outline_all(t); paste(s, t, 0, 0)
    for (x, y) in ((4, 9), (10, 9), (7, 4)): s.put(x, y, 'H')
    return s


def r_titanium():
    s = Spr(16, 16)
    paste(s, ingot(11, 4, 't', 'x', 'W', 'H'), 3, 2)
    paste(s, ingot(11, 4, 't', 'x', 'W', 'H'), 0, 8)
    return s


def r_silicon():
    """a silicon wafer: a chamfered square slab of dark blue-grey cells with a polished glint."""
    s = Spr(16, 16)
    bev(s, 2, 2, 12, 12, 'j', 'J', 'I')
    for k in (5, 8, 11):                                  # the cell grid
        for t in range(3, 13):
            if s.g[k][t] == 'J': s.g[k][t] = 'I'
            if s.g[t][k] == 'J': s.g[t][k] = 'I'
    for y in range(3, 13):                                # a lighter face on every cell's top-left, so they read as cells and not as a tray
        for x in range(3, 13):
            if s.g[y][x] == 'J' and (x - 3) % 3 == 0 and (y - 3) % 3 == 0: s.g[y][x] = 'j'
    for (x, y) in ((4, 4), (5, 4), (4, 5)): s.put(x, y, 'M')
    s.put(4, 4, 'L')
    outline_all(s)
    return s


def r_crystal():
    return finish(ico("""
        ...cccccccc...
        ..cHcccCCCCB..
        .cHccccCCCCCB.
        cccHcccCCCCCBB
        .cccccCCCCCBB.
        ..ccccCCCCBB..
        ...cccCCCBB...
        ....ccCCBB....
        .....cCBB.....
        ......CB......
    """))


def r_plasma_cell():
    return finish(ico("""
        ..SMMMMMMS..
        .SMLLMMMMSW.
        .WWWWWWWWWE.
        ..KHyyoooK..
        ..KyHyoooK..
        ..KyyyoooK..
        ..KyyyyooK..
        ..KooyyooK..
        ..KooooooK..
        ..KrooooKK..
        .WWWWWWWWWE.
        .SMMMMMMMSE.
        ..EEEEEEEE..
    """))


def r_nanite_paste():
    return finish(ico("""
        ......SS......
        .....SMMS.....
        ....SMLMMS....
        ....WSSSSW....
        ...MMMMMSSE...
        ..MLhhhhhSSE..
        ..MhzhhhhhSE..
        ..MhhhhhhhhE..
        ..SShhhhhhEE..
        ...WSSSSSEE...
        ...WWWWWWEE...
        ......hh......
        .....hzhh.....
        ......hh......
    """))


def r_military_circuit():
    return finish(ico("""
        ..a..a..a..a..
        ..a..a..a..a..
        aaEEEEEEEEEEaa
        ..EWWWWWWWWE..
        ..EWSMMMMSWE..
        aaEWMDDDDMWEaa
        ..EWMDrrDMWE..
        aaEWMDrrDMWEaa
        ..EWMDDDDMWE..
        aaEWSMMMMSWEaa
        ..EWWWWWWWWE..
        ..EEEEEEEEEE..
        ..a..a..a..a..
    """))


def r_gate_alloy():
    s = Spr(16, 16)
    a = ingot(9, 4, 'X', 'V', 'Z', 'H')
    paste(s, a, 1, 8); paste(s, a, 5, 3)
    for (x, y) in ((11, 5), (4, 11)): s.put(x, y, 'c')
    s.put(12, 4, 'H')
    return s


def r_void_crystal():
    return finish(ico("""
        .......X......
        ......XVV.....
        .....XVVZZ....
        ....XVVKKZZ...
        ....XVKKKKZ...
        ...XVVKmKKZZ..
        ...XVVKKKKZZ..
        ...VVKKKKKZZ..
        ...VVVKKKZZ...
        ....VVKKKZZ...
        ....VVVKZZ....
        .....VVZZ.....
        ......VZ......
    """))


def r_credits():
    s = Spr(16, 16)
    lit_disc(s, 8, 8, 6.4, ('y', 'a', 'u'))
    ring(s, 8, 8, 4.5, 5.5, 'a')
    for y in range(16):
        for x in range(16):
            if s.g[y][x] == 'a' and 4.5 ** 2 < (x + .5 - 8) ** 2 + (y + .5 - 8) ** 2 <= 5.5 ** 2 and x + y > 14: s.g[y][x] = 'u'
    for (x, y) in ((7, 5), (8, 5), (6, 6), (6, 7), (6, 8), (6, 9), (7, 10), (8, 10)): s.put(x, y, 'u')        # a stamped C
    s.put(5, 4, 'H'); s.put(4, 5, 'H'); s.put(4, 6, 'y')
    outline_all(s)
    return s


def r_fuel():
    return finish(ico("""
        ......yy......
        ......yy......
        .....yyoo.....
        .....yyoo.....
        ....yyyooo....
        ...yyHyyooo...
        ..yyHyyyyooo..
        ..yHyyyyyyoo..
        ..yyyyyyyyoo..
        ..yyyyyyyooo..
        ..oyyyyyyooo..
        ...ooyyyooo...
        ....oooooo....
    """))


def r_power():
    return finish(ico("""
        ......gggggg.
        .....gHHggg..
        ....gHgggg...
        ...gHggggg...
        ..gHgggggggg.
        ..gggggggggg.
        ......gggg...
        .....gggg....
        ....gggg.....
        ...ggg.......
        ..gg.........
        .g...........
    """))


def r_o2():
    """a bubble with a 2 in it: O2."""
    s = Spr(16, 16)
    for y in range(16):
        for x in range(16):
            dx, dy = x + .5 - 8, y + .5 - 8
            if 4.6 < math.hypot(dx, dy) <= 6.6: s.put(x, y, 'z' if (dx + dy) < -3.5 else 'i' if (dx + dy) < 3.5 else 'k')
    for j, r in enumerate(('HHH', '..H', 'HHH', 'H..', 'HHH')):
        for i, c in enumerate(r): s.put(6 + i, 5 + j, c)
    outline_all(s)
    return s


def r_hull():
    return finish(ico("""
        ......MM......
        .....MLLS.....
        .....MaaS.....
        ....MLaaSS....
        ....MLMMSW....
        ...MLMMMMSW...
        ..MMLMMMMSWW..
        .MMLMMDDMSWWW.
        MMLMMMDDMMSWWE
        MLSSMMMMMMSSWE
        MSSWWMMMMWWSWE
        .WE.WMMMMW.EW.
        ...aaWDDWaa...
        ...oo....oo...
    """))


def r_heat():
    return finish(ico("""
        ....MMMM......
        ...MLSSSW.....
        ...MSDDSWM....
        ...MSDrSW.....
        ...MSDrSWM....
        ...MSDrSW.....
        ...MSDrSWM....
        ...MSDoSW.....
        ..MMSDooSWW...
        .MSDrroooWWE..
        .MSrrooooSWE..
        .MSDrroooWWE..
        ..WSDrrSWWE...
        ...WWWWWEE....
    """))


def r_crew():
    return finish(ico("""
        .....MMMM.....
        ....MLLLMS....
        ...MLLLLMMS...
        ...MKJJJJKS...
        ...MKJcJJKS...
        ...MKJJJJKS...
        ....MMMMSS....
        ..CCCCCCCCCB..
        .CcCCCCCCCCBB.
        .CcCCCCCCCCCB.
        .CCCCCCCCCCBB.
        .CBBBBBBBBBBB.
    """))


RES = [('scrap', r_scrap), ('copper', r_copper), ('polymer', r_polymer), ('titanium', r_titanium), ('silicon', r_silicon), ('crystal', r_crystal),
       ('plasma_cell', r_plasma_cell), ('nanite_paste', r_nanite_paste), ('military_circuit', r_military_circuit), ('gate_alloy', r_gate_alloy),
       ('void_crystal', r_void_crystal), ('credits', r_credits), ('fuel', r_fuel), ('power', r_power), ('o2', r_o2), ('hull', r_hull), ('heat', r_heat), ('crew', r_crew)]


# ====================================================================== mode icons, 24x24
def edge_light(s, base, hi, lo):
    """pixels of colour `base` take `hi` on up/left edges and `lo` on down/right edges."""
    n = s.copy()
    for y in range(s.h):
        for x in range(s.w):
            if s.g[y][x] != base: continue
            if s.get(x, y + 1) != base or s.get(x + 1, y) != base: n.g[y][x] = lo
            elif s.get(x, y - 1) != base or s.get(x - 1, y) != base: n.g[y][x] = hi
    s.g = n.g


def m_build():
    """a wrench and a hammer crossed: steel wrench, wood-handled hammer with an amber head."""
    s = Spr(24, 24)
    thick(s, 5, 5, 17, 17, 3, 'S', 'M', 'W')              # the wrench, top-left to bottom-right
    circle(s, 5.5, 5.5, 4.2, 'S')
    for (x, y) in ((3, 2), (4, 3), (4, 2), (5, 3), (2, 3), (3, 4), (2, 2), (3, 3)): s.erase(x, y)      # the open jaw
    circle(s, 18.2, 18.2, 3.2, 'S'); circle(s, 18.7, 18.7, 1.3, 'D')
    edge_light(s, 'S', 'M', 'W')
    thick(s, 4, 19, 15, 8, 3, 'q', 'Q', 'n')              # the hammer, bottom-left to top-right
    poly(s, [(21.8, 8.3), (18.3, 11.8), (11.2, 4.7), (14.7, 1.2)], 'a')
    edge_light(s, 'a', 'y', 'u')
    s.put(14, 3, 'H'); s.put(15, 2, 'y')
    outline_all(s)
    return s


def m_play():
    s = Spr(24, 24)
    poly(s, [(5, 2), (21, 12), (5, 22)], 'g')
    edge_light(s, 'g', 'h', 'B')
    outline_all(s)
    return s


def m_pause():
    s = Spr(24, 24)
    for x0 in (4, 13):
        bev(s, x0, 3, 7, 18, 'y', 'a', 'u')
    outline_all(s)
    return s


def m_map():
    """a star chart: a framed navy sheet with a ringed planet, stars and a dotted course with an X."""
    s = Spr(24, 24)
    bev(s, 1, 3, 22, 18, 'M', 'S', 'W')
    s.rect(3, 5, 18, 14, 'N')
    s.hline(3, 5, 18, 'I'); s.vline(3, 5, 14, 'I')
    for (x, y) in ((5, 7), (17, 7), (7, 16), (19, 14), (12, 7), (4, 12), (15, 17)): s.put(x, y, 'z' if (x + y) % 2 else 'i')
    circle(s, 9.5, 11.5, 3.0, 'c')
    for (x, y) in ((8, 10), (9, 10), (8, 11)): s.put(x, y, 'H')
    for (x, y) in ((10, 13), (11, 13), (11, 12), (7, 13)): s.put(x, y, 'C')
    for (x, y) in ((13, 13), (15, 14), (17, 13), (18, 11)): s.put(x, y, 'a')        # the dotted course
    for (x, y) in ((17, 9), (19, 9), (18, 10), (17, 11), (19, 11)): s.put(x, y, 'r')   # the X
    outline_all(s)
    return s


def m_shields():
    s = Spr(24, 24)
    poly(s, [(2, 3), (12, 1), (22, 3), (21, 13), (12, 23), (3, 13)], 'M')               # the rim
    poly(s, [(4, 5), (12, 3.2), (20, 5), (19, 12.5), (12, 20.8), (5, 12.5)], 'b')       # the field
    for y in range(24):                                   # a lit left half and a darker right half
        for x in range(24):
            if s.g[y][x] == 'b' and x >= 12: s.g[y][x] = 'j'
    for y in range(24):
        for x in range(24):
            if s.g[y][x] == 'b' and y < 8 and x < 12 and x + y < 16: s.g[y][x] = 'z'
    for (x, y) in ((12, 7), (12, 8), (11, 9), (13, 9), (10, 10), (14, 10), (12, 10), (12, 11), (12, 12)): s.put(x, y, 'H')     # a chevron
    edge_light(s, 'M', 'L', 'W')
    outline_all(s)
    return s


def m_crafting():
    """an anvil with a violet spark: the workshop."""
    s = Spr(24, 24)
    rows = """
        ......................
        ..LLLLLLLLLLLLLLLLLL..
        .LMMMMMMMMMMMMMMMMMMS.
        LMSSSSSSSSSSSSSSSSSSSW
        MMSSSSSSSSSSSSSSSSSSWW
        .WSSSSSSSSSSSSSSSWWWW.
        ..WWWSSSSSSSSSWWWWW...
        .....WSSSSSSSWWW......
        ......WSSSSSSWW.......
        ......WSSSSSSWW.......
        .....WWSSSSSSSWW......
        ....WSSSSSSSSSSWW.....
        ...WSSSSSSSSSSSSWW....
        ..MSSSSSSSSSSSSSSWW...
        ..WWWWWWWWWWWWWWWWE...
    """
    s.stamp(1, 6, art(rows))
    for (x, y) in ((6, 7), (7, 7), (8, 7)): s.put(x, y, 'L')
    for (x, y) in ((20, 1), (22, 3), (18, 3), (21, 5), (23, 1)): s.put(x, y, 'X')
    for (x, y) in ((21, 2), (19, 2), (20, 4)): s.put(x, y, 'V')
    s.put(21, 3, 'H')
    outline_all(s)
    return s


def m_help():
    s = Spr(24, 24)
    lit_disc(s, 12, 12, 10.5, ('M', 'S', 'W'))
    lit_disc(s, 12, 12, 8.6, ('J', 'I', 'N'))
    q = art("""
        .HHHH.
        HHHHHH
        HH..HH
        ...HHH
        ..HHH.
        ..HH..
        ..HH..
        ......
        ..HH..
        ..HH..
    """)
    s.stamp(9, 6, q)
    outline_all(s)
    return s


MODE = [('build', m_build), ('play', m_play), ('map', m_map), ('shields', m_shields), ('crafting', m_crafting), ('help', m_help), ('pause', m_pause)]


# ====================================================================== category icons, 16x16 (a steel body and one accent colour each)
def c_structure():
    """a plated wall section: four bolted plates and a hazard-tape foot."""
    s = Spr(16, 16)
    bev(s, 1, 2, 14, 12, 'L', 'S', 'W')
    s.vline(8, 3, 9, 'K'); s.hline(2, 7, 12, 'K')
    for (x, y) in ((3, 3), (10, 3), (3, 8), (10, 8)): s.put(x, y, 'H'); s.put(x + 1, y + 1, 'E')
    for x in range(2, 14): s.put(x, 12, 'a' if x % 2 == 0 else 'K')
    outline_all(s)
    return s


def c_shapes():
    """a slope wedge and a round part: the shaped walls."""
    s = Spr(16, 16)
    poly(s, [(1, 14.5), (1, 5), (11, 14.5)], 'S')
    edge_light(s, 'S', 'L', 'W')
    for (x, y) in ((2, 8), (2, 9), (3, 10)): s.put(x, y, 'L')
    t = Spr(16, 16); lit_disc(t, 11.0, 5.0, 3.7, ('z', 'c', 'B'))
    for y in range(16):
        for x in range(16):
            if t.g[y][x] != '.': s.put(x, y, t.g[y][x])
    s.put(9, 3, 'H'); s.put(10, 2, 'H')
    outline_all(s)
    return s


def c_systems():
    """a reactor core: a steel ring, a dark well, an amber core."""
    s = Spr(16, 16)
    lit_disc(s, 8, 8, 6.6, ('L', 'S', 'W'))
    circle(s, 8, 8, 4.4, 'D')
    lit_disc(s, 8, 8, 3.0, ('y', 'o', 'o'))
    s.put(7, 7, 'H'); s.put(8, 7, 'y'); s.put(7, 8, 'y')
    for (x, y) in ((7, 2), (8, 2), (7, 13), (8, 13), (2, 7), (2, 8), (13, 7), (13, 8)): s.put(x, y, 'K')
    outline_all(s)
    return s


def c_weapons():
    """a missile pointing up, with its flame."""
    return finish(ico("""
        .....rr.....
        ....rHrr....
        ...rHrrro...
        ...rrrrro...
        ...MLSSSW...
        ...MLSSSW...
        ...MLSaSW...
        ...MLSaSW...
        ...MLSSSW...
        ..WMLSSSWW..
        .WWMLSSSWWW.
        WWW.WSSW.WWW
        ....oyyo....
        .....oo.....
    """))


def c_engines():
    """a thruster: an engine block with vents, a flared bell, a flame."""
    return finish(ico("""
        ..SSSSSSSS..
        .SMLLLLLMSW.
        .SMSSSSSSSW.
        .SWWWWWWWEW.
        .WSSSSSSSSW.
        .MMSSSSSSWW.
        MMSSDDDDSSWW
        WSDDDDDDDDSW
        .oyyyyyyyyo.
        ..oyyHHyyo..
        ..ooyyyyoo..
        ...ooyyoo...
        ....ooyo....
        .....oo.....
    """))


def c_utility():
    """a wrench: steel, with a cyan grip band."""
    s = Spr(16, 16)
    thick(s, 4, 4, 11, 11, 3, 'S', 'M', 'W')
    circle(s, 4.5, 4.5, 3.6, 'S')
    for (x, y) in ((2, 2), (3, 2), (2, 3), (3, 3), (1, 1), (4, 2), (2, 4)): s.erase(x, y)           # the open jaw
    circle(s, 12.0, 12.0, 2.6, 'S'); circle(s, 12.3, 12.3, 1.0, 'D')
    edge_light(s, 'S', 'M', 'W')
    for (x, y) in ((7, 6), (6, 7), (8, 7), (7, 8), (9, 8), (8, 9)): s.put(x, y, 'c')
    outline_all(s)
    return s


def c_cargo():
    """a crate with steel straps."""
    return finish(ico("""
        MMMMMMMMMMMMMM
        MLLLLLLLLLLLLS
        MQQQQQQQQQQQQS
        MQqqqQMMQqqqQS
        MQQQQQMMQQQQQS
        MQqqqqMMqqqqQS
        MQQQQQMMQQQQQS
        MQqqqqMMqqqqQS
        MQQQQQMMQQQQQS
        MqqqqqMMqqqqqS
        MnnnnnSSnnnnnE
        WWWWWWWWWWWWWE
    """))


CAT = [('structure', c_structure), ('shapes', c_shapes), ('systems', c_systems), ('weapons', c_weapons), ('engines', c_engines), ('utility', c_utility), ('cargo', c_cargo)]


# ====================================================================== cursors, 16x16 (hotspot in the JSON)
def k_pointer():
    """the arrow: white with a near-black outline, tip (the hotspot) at the top-left."""
    s = Spr(16, 16)
    s.stamp(0, 0, art("""
        K..........
        KK.........
        KHK........
        KHHK.......
        KHHHK......
        KHHHHK.....
        KHHHHHK....
        KHHHHHHK...
        KHHHHHHHK..
        KHHHHKKKKK.
        KHHKHK.....
        KHK.KHK....
        KK..KHK....
        K....KHK...
        .....KK....
    """))
    return s


def _brackets(s, col, arm=3, lo=2, hi=13):
    for (x0, y0, sx, sy) in ((lo, lo, 1, 1), (hi, lo, -1, 1), (lo, hi, 1, -1), (hi, hi, -1, -1)):
        for k in range(arm + 1):
            s.put(x0 + sx * k, y0, col); s.put(x0, y0 + sy * k, col)


def k_place():
    """a placing reticle: amber corner brackets round a centre pip. Hotspot: the middle."""
    s = Spr(16, 16)
    _brackets(s, 'a')
    for (x, y) in ((2, 2), (13, 2), (2, 13), (13, 13)): s.put(x, y, 'y')
    s.put(7, 7, 'y'); s.put(8, 7, 'y'); s.put(7, 8, 'y'); s.put(8, 8, 'a')
    outline_all(s)
    return s


def k_remove():
    """a bold red X. Hotspot: the middle."""
    s = Spr(16, 16)
    thick(s, 3, 3, 12, 12, 3, 'r'); thick(s, 12, 3, 3, 12, 3, 'r')
    for (x, y) in ((3, 2), (4, 3), (2, 3), (12, 2), (11, 3), (13, 3), (7, 7), (8, 7)): s.put(x, y, 'o')
    outline_all(s)
    return s


def k_invalid():
    """the no-entry sign: a red ring with a slash on a dark disc. Hotspot: the middle."""
    s = Spr(16, 16)
    circle(s, 8, 8, 6.8, 'D')
    ring(s, 8, 8, 4.8, 6.8, 'r')
    thick(s, 4, 4, 11, 11, 2, 'r')
    for (x, y) in ((4, 3), (5, 3), (3, 4), (3, 5)): s.put(x, y, 'o')
    outline_all(s)
    return s


CURSORS = [('pointer', k_pointer, (0, 0)), ('place', k_place, (8, 8)), ('remove', k_remove, (8, 8)), ('invalid', k_invalid, (8, 8))]
