"""Hand weapons (art/items/): every sprite faces UP, interior-only art here, outlined on export.
Each entry: art (interior Spr), grip (the pixel the hand closes on, interior coords), muzzle (where shots / the blade tip are),
class (arm pose), culture, optional foregrip, optional glow spec [(chars, rgb, radius, strength)].
Cultures: scrap = patched (rust u, mismatched greys, hazard tape, bolts, welds), concord = clean steel + stencil + indicator,
lumen = dark navy panels + 1px neon lines + crystal facets, basalt = stone + steel bands + crystal, emberkin = brass + fire,
fenn = fine and fiddly (small details everywhere, brass wire, tiny gauges)."""
from px import *
from mach import bev

def tube(s, x, y, w, h, hi='M', mid='S', lo='W'):
    for j in range(h):
        for i in range(w):
            c = hi if i == 0 else lo if i == w - 1 else mid
            s.put(x + i, y + j, c)

def hazard(s, x, y, w, h, a='a', d='D', phase=0):
    for j in range(h):
        for i in range(w): s.put(x + i, y + j, a if (i + j + phase) % 3 else d)

def A(rows): return from_art(rows)

ITEMS = {}
def item(id, spr, grip, muzzle, cls, culture, foregrip=None, glow=None, notes=''):
    ITEMS[id] = dict(id=id, spr=spr, grip=grip, muzzle=muzzle, cls=cls, culture=culture, foregrip=foregrip, glow=glow or [], notes=notes)

# ===================================================================== HUMAN
# ---- service_pistol: Concord-clean baseline. Even seams, a registry stencil, one indicator.
item('service_pistol', A("""
..E..
.ESE.
.MSW.
.MSW.
MMSSW
MLSSW
MHHoW
MSHSW
MSSSW
EWSWE
.WSW.
.qQn.
.QQn.
"""), grip=(2, 11), muzzle=(2, -1), cls='pistol', culture='concord',
    notes='Concord service pistol: clean steel, white registry stencil, one orange ready light.')

# ---- carbine: Concord rifle. Short, an optic on the rail, three burst lights.
s = Spr(7, 27)
s.stamp(0, 0, """
...E...
..EWE..
..ESE..
..MSW..
..MSW..
..MSW..
..MSW..
.MMSWW.
.MESEW.
.MSSSW.
.MESEW.
.MSSSW.
.MMSWW.
MLSSSMW
MSDDDSW
MSDbDSW
MSDDDSW
MSSSSSW
MSoooSW
MLSHHMW
.WEEEW.
..QQq..
..QQq..
..QQn..
..Qqn..
..qqn..
...nn..
""")
item('carbine', s, grip=(3, 22), foregrip=(3, 9), muzzle=(3, -1), cls='rifle', culture='concord',
     notes='Concord carbine: optic on the rail, three orange lights for the 3-round burst.')

# ---- doorbuster: scrap shotgun. Twin barrels with a breaching crown, rust clamps, hazard tape, a rope-wrapped stock.
s = Spr(9, 28)
s.stamp(0, 0, """
.E.EEE.E.
.MSWEMSW.
.MSWEMSW.
.MSWEMSW.
.MSWEMSW.
.MSWEMSW.
.uLuuuLu.
.MSWEMSW.
.MSWEuSW.
.MSWEMSW.
MuuuuuuuW
MuLuuuLuW
MuuuuSuuW
MSSSSSSSW
aDaDaDaDa
DaDaDaDaD
MSSSSyySW
MSEEEEESW
.WSSSSSW.
..WEEEW..
..QQuQn..
..QQQqn..
..QuQqn..
...QQqn..
...Qqqn..
...qqnn..
....qnn..
""")
s.put(4, 3, 'u'); s.put(2, 5, 'u')                                   # rust bloom on the barrels
item('doorbuster', s, grip=(4, 20), foregrip=(4, 11), muzzle=(4, -1), cls='rifle', culture='scrap',
     notes='Scrap-built breaching shotgun: twin barrels, a toothed crown, hazard tape, rope-wrapped stock.')

# ---- rivet_gun: scrap "gun that also repairs". Nozzle, body, a rivet strip on the right, an air hose looping at the back.
item('rivet_gun', A("""
....E....
...EWE...
...MSW...
...MSW...
..MMSWW..
..MuSSW..
..MSSSWSL
.LMSSSWSS
..MSuSWSL
..MSSSWSS
..WSSSWSL
...WEW.SS
...qQn...
..quQn...
.qQ.Qn...
.q..Qn...
.qq.qn...
..qqn....
"""), grip=(4, 12), muzzle=(4, -1), cls='tool', culture='scrap',
    notes='Scrap rivet gun: a nozzle, a strip of rivets on the side, an air hose looping off the back. Repairs walls at half speed.')

# ---- flare_gun: scrap signal pistol. A fat tube with a lit flare in the mouth.
item('flare_gun', A("""
..yoy..
.rooor.
.rrrrr.
.MuuuW.
.MuSSW.
.uuSSW.
.MSSLW.
.MSSSW.
.WEEEW.
..qQn..
..QuQn.
..quQn.
..qQn..
"""), grip=(3, 9), muzzle=(3, -1), cls='pistol', culture='scrap',
    glow=[('yo', (255, 138, 30), 3.0, 0.7)],
    notes='Scrap flare gun: fat signal tube, a red flare shell lit in the muzzle, wire-wrapped grip. Sets fires.')

# ===================================================================== BASALT
# ---- quarry_hammer: a stone block head with a crystal vein, steel bands, a long dark haft with a leather grip.
s = Spr(11, 31)
s.stamp(0, 0, """
.MLMMMMMMW.
WSSSWWWWWEE
WSSWWWcWWEE
WSWWWcbWWEE
WWWWcbbWWED
WWWWWbWWEDD
WWWWWWWEEDD
.EEEEEEEED.
.SMMMMMMMW.
..WSSSSSW..
""")
for y in range(10, 31):
    tube(s, 4, y, 3, 1, 'W', 'E', 'D')
for y in (13, 14): s.hline(3, y, 5, 'M')                              # a steel collar
s.hline(3, 14, 5, 'S')
for y in range(20, 27):                                               # leather grip wrap
    s.put(4, y, 'Q'); s.put(5, y, 'q'); s.put(6, y, 'n')
for y in (21, 23, 25): s.hline(4, y, 3, 'u')
s.stamp(3, 27, """
WSSSW
WSWWE
.EEE.
""")
item('quarry_hammer', s, grip=(5, 23), muzzle=(5, -1), cls='melee', culture='basalt',
     glow=[('cH', (60, 242, 255), 2.4, 0.5)],
     notes='Basalt quarry hammer: block head with a crystal vein, steel collar, stone pommel. Breaches walls.')

# ---- slugthrower: Basalt heavy. Stone muzzle weight, a steel barrel with a stone ring, a hopper on a stone receiver.
s = Spr(9, 36)
s.stamp(0, 0, """
..WWWWW..
.WSKKKWE.
.WWEEEEE.
..EEEEE..
...MSW...
...MSW...
...McW...
...MSW...
...MSW...
..WWWWE..
..EEEEE..
...MSW...
...MSW...
...MSW...
...MSW...
...MSW...
...MSW...
.MWWWWWE.
SSWWWWWEE
SWDDDDDWE
SWDSWSDWE
WWDWSWDcE
WWDSWSDbE
WWDDDDDEE
WaaaaaaaE
WSWWWWWED
WWWWcbWEE
.EEEEEEE.
..WWWWW..
..QQqn...
..QQqn...
..Qqqnn..
..WWWWW..
.WSEEEEW.
.WEEEEEW.
..DDDDD..
""")
s.put(0, 20, 'D'); s.put(8, 24, 'D')
item('slugthrower', s, grip=(4, 29), foregrip=(4, 14), muzzle=(4, -1), cls='heavy', culture='basalt',
     glow=[('cH', (60, 242, 255), 2.4, 0.5)],
     notes='Basalt slugthrower: stone muzzle weight, steel barrel, hopper on a crystal-veined stone receiver. Heavy; pierces.')

# ===================================================================== EMBERKIN
# ---- torchgun: brass flame projector with a fuel tank, a pressure gauge, a pilot flame at the nozzle.
s = Spr(11, 31)
s.stamp(1, 0, """
y.ayaya.y
.aDDoDDa.
..auuua..
..auua...
""")
for y in range(4, 14):
    s.put(4, y, 'y'); s.put(5, y, 'a'); s.put(6, y, 'u'); s.put(7, y, 'n')
s.hline(3, 8, 5, 'a'); s.hline(3, 9, 5, 'u')                                      # nozzle collar
s.stamp(1, 13, """
.yaaaaau.
yyaaaaauu
uuuuuuuuu
yyaaaaauu
yaHHHaauu
yaHrHaauu
yaHHHaauu
yyaaaaauu
uuyuuyuuu
yyaaaaauu
.uuuuuun.
""")
s.stamp(4, 24, """
.q.
qQn
QQn
QQn
qQn
.nn
""")
s.put(9, 18, 'q'); s.put(10, 19, 'q')                                             # fuel line
item('torchgun', s, grip=(5, 26), foregrip=(5, 11), muzzle=(5, -1), cls='heavy', culture='emberkin',
     glow=[('oy', (255, 138, 30), 3.0, 0.7)],
     notes='Emberkin torchgun: brass nozzle with a pilot flame, riveted fuel tank, pressure gauge, wood grip. Sets fires; Emberkin do not burn.')

# ---- ember_knife: dark blade with a glowing edge, a brass guard, a wrapped grip with an ember in the pommel.
s = Spr(7, 21)
s.stamp(0, 0, """
...y...
...o...
..oHo..
..oDo..
..oDo..
..oDo..
..oDo..
..oDo..
..oDo..
..oDo..
.aYaYa.
.auuua.
..qQn..
..auA..
..qQn..
..auA..
..qQn..
..nan..
..ayo..
...o...
""".replace('A', 'a').replace('Y', 'y').replace('H', 'y'))
item('ember_knife', s, grip=(3, 14), muzzle=(3, -1), cls='melee', culture='emberkin',
     glow=[('oy', (255, 138, 30), 2.6, 0.6)],
     notes='Emberkin ember knife: a dark blade with a glowing edge, a brass guard and wrapped grip. Ignites on hit.')

# ===================================================================== FENN
# ---- spark_pistol: slim, fiddly. A forked electrode with a spark gap, brass coil winding, a tiny dial, cream panels.
item('spark_pistol', A("""
.b...b.
.M.H.M.
.M...M.
.MaaaM.
..MSW..
.aMSWa.
.uMSWu.
.aMSWa.
..fSs..
..fgs..
..fSs..
..qQn..
..QQn..
..qQn..
"""), grip=(3, 11), muzzle=(3, -1), cls='pistol', culture='fenn',
     glow=[('bH', (79, 163, 255), 2.6, 0.7)],
     notes='Fenn spark pistol: forked electrode with a spark gap, brass coil winding, a tiny charge dial. Stuns (ion).')

# ---- multi_tool: a fan of heads on a brass hub: a driver, a cutter, a probe and a wrench jaw, a cream handle with a gem.
item('multi_tool', A("""
....H....
....M....
..L.M.y..
..L.M.y..
.LL.S.yy.
.Lv.S.vy.
..vMSMv..
...aaa...
...fSs...
...fgs...
...fSs...
...aaa...
...fSs...
...fSs...
...fvs...
...qnq...
"""), grip=(4, 9), muzzle=(4, -1), cls='tool', culture='fenn',
     notes='Fenn multi-tool: a fan of heads on a brass hub (driver, cutter, probe, jaw), a cream handle with a gem. Repairs at 2x speed.')

# ===================================================================== UNIQUE
# ---- gatekeepers_lance: a neon beam rifle from a dead gate. Navy panels, cyan edge lines, gold trim, a floating crystal.
s = Spr(9, 43)
s.stamp(0, 0, """
.E..c..E.
.EC.H.cE.
.Ec.b.cE.
.Ec.b.cE.
.EDEcEDE.
..EDcDE..
...DcD...
""".replace('C', 'c'))
for y in range(7, 25):                                    # slim barrel: navy with 1px cyan edge lines
    s.put(3, y, 'c'); s.put(4, y, 'D'); s.put(5, y, 'c')
    s.put(2, y, 'E'); s.put(6, y, 'E')
for y in (10, 11, 17, 18):                                # gold trim bands
    s.hline(1, y, 7, 'y' if y in (10, 17) else 'a')
s.put(4, 14, 'm'); s.put(4, 21, 'm')
s.stamp(0, 25, """
.EEDDDEE.
EDDEcEDDE
EDcyyycDE
EcyaDayc?
EcyDmDycE
EcyaDayc?
EDcyyycDE
EDDEcEDDE
.EDDcDDE.
""".replace('?', 'E'))
s.stamp(1, 34, """
.EDcDE.
.EDcDE.
..EcE..
..EDE..
.EDmDE.
.EDDDE.
..EEE..
..yay..
""")
item('gatekeepers_lance', s, grip=(4, 29), foregrip=(4, 14), muzzle=(4, -1), cls='heavy', culture='lumen',
     glow=[('cb', (60, 242, 255), 2.6, 0.7), ('H', (244, 246, 248), 3.0, 0.8), ('m', (255, 79, 216), 2.2, 0.5), ('y', (255, 210, 58), 2.0, 0.4)],
     notes='Gatekeeper\'s Lance (unique): a neon beam rifle from a dead gate. Navy panels, cyan edge lines, gold trim, a floating crystal emitter. Its shots bounce.')

ORDER = ['service_pistol', 'carbine', 'doorbuster', 'rivet_gun', 'flare_gun', 'quarry_hammer', 'slugthrower',
         'torchgun', 'ember_knife', 'spark_pistol', 'multi_tool', 'gatekeepers_lance']

def outlined_item(it):
    from mach import outline_all
    sp = it['spr']
    n = Spr(sp.w + 2, sp.h + 2)
    n.stamp(1, 1, sp.rows())
    outline_all(n)
    return n

GLOW_PAD = 4
def item_glow(it, margin=0):
    """soft glow layer for an item: Rgba of (w + 2*margin + 2*GLOW_PAD) squared; margin=1 aligns with the outlined export frame."""
    from mach import glow
    sp = it['spr']; P = GLOW_PAD
    g = Rgba(sp.w + 2 * margin + 2 * P, sp.h + 2 * margin + 2 * P)
    for chars, rgb, r, st in it['glow']:
        for y in range(sp.h):
            for x in range(sp.w):
                if sp.g[y][x] in chars: glow(g, x + margin + P + 0.5, y + margin + P + 0.5, r, rgb, st, 1.6)
    return g

def kit_items(ids=None):
    """-> {id: {'spr': interior Spr, 'grip': (x,y), 'muzzle': (x,y), 'glow': Rgba|None}} for sp_compose (interior coords; the
    compositor outlines after rotating)."""
    out = {}
    for k in (ids or ORDER):
        it = ITEMS[k]
        out[k] = {'spr': it['spr'], 'grip': tuple(it['grip']), 'muzzle': tuple(it['muzzle']), 'cls': it['cls'],
                  'glow': item_glow(it) if it['glow'] else None}
    return out

def anchors(it):
    a = {'grip': [it['grip'][0] + 1, it['grip'][1] + 1], 'muzzle': [it['muzzle'][0] + 1, it['muzzle'][1] + 1]}
    if it['foregrip']: a['foregrip'] = [it['foregrip'][0] + 1, it['foregrip'][1] + 1]
    return a
