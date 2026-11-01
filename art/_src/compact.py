"""Compact pass (playtest 2, P2): tier 1-2 parts take less room INSIDE the ship, so their inside art shrinks to match.
data/components.json and the packs give these parts the new sizes (weapon and engine inside halves 2x2 instead of 4x2, reactor and
shield 2x4 instead of 4x4); the outside halves of the guns and engines are unchanged. Nothing here is redrawn: comp_base.export
builds each frame as it always did, and the outline step (mach.outline_all) first cuts the 64 px wide interior down to 32 px,
keeping the part's own left and right edge columns (so the bevel, the chamfered corners and the side plating come through)
and the centre columns between them, then outlines, shadows and exports as usual. The glow layers are cut the same way, so a lamp's glow
stays on its lamp. Same input, same output: build_all.py stays byte-identical. The medbay is not here: it is drawn new at 2x4 (lines_shop.py).
SHIFT moves one part's centre window (negative = left) when the middle of its art is not the part worth keeping; KEEP gives a part its own columns."""
import mach
from px import Spr, Rgba

WEAPONS = [
    'artemis_mk1', 'basalt_magma_spitter', 'basalt_pumice_flak', 'bolt_thrower_scrap', 'emberkin_cinder_mortar', 'emberkin_flare_turret',
    'emberkin_pyre_lance', 'fenn_market_missile', 'fenn_spark_lattice', 'fenn_twitch_cannon', 'gauntling_arc_hammer',
    'gauntling_scrap_shotgun', 'gauntling_tesla_picket', 'grundl_barge_flak', 'grundl_grapple_harpoon', 'heat_lance_neon',
    'human_flak_screen', 'human_volley_rack', 'ion_blast_mk1', 'kett_chitin_thrower', 'kett_drone_picket', 'kett_hive_swarm_launcher',
    'laser_mk1', 'laser_mk2', 'laser_turret_mk1', 'mire_bog_mortar', 'mire_mist_projector', 'mire_steam_lance', 'prismatic_glimmer_turret',
    'prismatic_prism_lens', 'prismatic_refractor', 'pulse_mk1', 'pulse_mk2', 'rattle_burst_scrap', 'shrapnel_cannon_scrap',
    'siren_ion_neon', 'sporeling_pollen_turret', 'sporeling_rot_pod', 'sporeling_spore_cannon',
]
ENGINES = [
    'emberkin_pyre_drive', 'engine_mk1', 'engine_mk2', 'engine_neon_mk1', 'engine_neon_mk2', 'engine_scrap_mk1', 'engine_scrap_mk2',
    'fenn_haggle_engine', 'gauntling_overclock_engine', 'grundl_hauler_thrusters', 'longburn_mk1', 'longburn_mk2',
]
REACTORS = [
    'basalt_vacuum_forge', 'emberkin_furnace_core', 'fenn_jury_reactor', 'gauntling_arc_core', 'human_reactor_plus', 'kett_nest_reactor',
    'mire_wetwell_reactor', 'prismatic_song_reactor', 'reactor_mk1', 'reactor_mk2', 'reactor_neon_mk1', 'reactor_scrap_mk1',
    'sporeling_bloom_reactor',
]
SHIELDS = [
    'emberkin_hearth_shield', 'grundl_freight_shield', 'kett_hive_battery', 'mire_rain_shield', 'prismatic_lattice_shield', 'shield_mk1',
    'shield_mk2', 'shield_neon_mk1', 'shield_scrap_mk1', 'sporeling_mycelium_shield',
]

FAMILIES = {'weapon': WEAPONS, 'engine': ENGINES, 'reactor': REACTORS, 'shield': SHIELDS}
CELLS = {'weapon': (2, 2), 'engine': (2, 2), 'reactor': (2, 4), 'shield': (2, 4)}     # the new inside footprint
OLD_W, NEW_W = 64, 32                                                                    # frame width in source px, before and after
EDGE = {'weapon': 3, 'engine': 3, 'reactor': 2, 'shield': 2}                           # edge columns kept on each side
SHIFT = {'sporeling_rot_pod': -9}                                                            # id -> columns to move the centre window by (the spore and the pod's end, not the blank middle)
KEEP = {}                                                                                # id -> explicit source columns [(from, to), ...] (to exclusive), NEW_W in all


def columns(pid, family):
    """the source column of every column of the compact frame, left to right."""
    if pid in KEEP:
        cols = [x for a, b in KEEP[pid] for x in range(a, b)]
    else:
        e = EDGE[family]
        mid = NEW_W - 2 * e
        c0 = (OLD_W - mid) // 2 + SHIFT.get(pid, 0)
        cols = list(range(e)) + list(range(c0, c0 + mid)) + list(range(OLD_W - e, OLD_W))
    assert len(cols) == NEW_W and all(0 <= x < OLD_W for x in cols), (pid, len(cols))
    return cols


class Plan:
    def __init__(s, pid, family):
        s.id, s.family, s.cells, s.cols = pid, family, CELLS[family], columns(pid, family)

    def crop(s, spr):
        assert spr.w == OLD_W, (s.id, spr.w)
        n = Spr(NEW_W, spr.h)
        for y in range(spr.h):
            row = spr.g[y]
            n.g[y] = [row[x] for x in s.cols]
        return n

    def glow(s, g, pad_l):
        """a glow layer (sprite + padding on every side) cut with the sprite's columns; the padding stays as it was."""
        pad_r = g.w - pad_l - OLD_W
        n = Rgba(pad_l + NEW_W + pad_r, g.h)
        src = list(range(pad_l)) + [pad_l + x for x in s.cols] + [pad_l + OLD_W + k for k in range(pad_r)]
        for y in range(g.h):
            row = g.p[y]
            n.p[y] = [list(row[x]) for x in src]
        return n

    def anchor(s, xy):
        """an anchor point (x, y in frame px) moved to the compact frame: the nearest column that was kept."""
        x = min(range(NEW_W), key=lambda j: (abs(s.cols[j] - xy[0]), j))
        return [x, xy[1]]

    def frame(s, c, state, i):
        mach.CROP = s.crop
        try: return c.frame(state, i)
        finally: mach.CROP = None


PLANS = {pid: Plan(pid, f) for f, ids in FAMILIES.items() for pid in ids}

def plan_for(pid):
    return PLANS.get(pid)
