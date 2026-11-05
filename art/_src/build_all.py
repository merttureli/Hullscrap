"""Regenerates every art file this generator owns: palette, crew, items, components, tiles, ASSETS.md rows."""
import os, subprocess, sys
from px import *
import export_crew, comp_base, comp_laser, comp_new, sp_export, comp_weapons, tile_wreck
import pal_races1                 # race wave 1: three Mire skin greens + two private cyan letters (before the palette is written)
import lines_reactor, lines_engine, lines_engine1, lines_o2_shield, lines_shield, lines_shop, lines_belt     # equipment lines + workshop + belts (extra palette letters register on import)
import lines_medarm              # healing arms (docs/DRONES.md section 10): Medbay Mk2 / Mk3 bases and their turning arms
import tech_b                     # racial tech, group b: Mire, Sporeling, Gauntling, Prismatic, Grundl (docs/waves/racial_tech_1.md)
import hand_race                  # racial hand weapons (12 sprites + 8 muzzle flashes) for the six race-wave-1 races; existing palette letters only
import techa_all                  # racial tech, group a (human, basalt, emberkin, fenn, kett): 15 weapons, 15 components, 15 projectile sets; uses existing palette letters only
LINES = lines_reactor.ALL + lines_engine.ALL + lines_engine1.ALL + lines_o2_shield.ALL + lines_shield.ALL + lines_shop.ALL + lines_belt.ALL
REPLACED = {'engine_mk1', 'shield_mk1'}            # redrawn by the lines modules (engine split into core + _out, shield with the new animation); comp_engine.py is the old west-facing engine, superseded
COMPS = [C for C in [comp_laser.Laser] + comp_new.ALL if C.id not in REPLACED] + LINES + comp_weapons.ALL
COMPS += tech_b.ALL
COMPS += lines_medarm.ALL
def _sector_colours():
    """pal_sector's colours, read without importing it (its letters clash with pal_races1), under private keys."""
    import ast
    src = open(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'pal_sector.py')).read()
    new = ast.literal_eval(src[src.index('NEW = {') + 6:src.index('}', src.index('NEW = {')) + 1])
    for i, (k, (h, n)) in enumerate(new.items()):
        PAL['sector_%d' % i] = (h, n)
        RGB['sector_%d' % i] = tuple(int(h[j:j + 2], 16) for j in (0, 2, 4))


if __name__ == '__main__':
    _sector_colours()
    import pal_guns; pal_guns.register()      # the beam crimson and the slug straw (50 colours in all)
    write_palette_gpl(ART + '/palette.gpl')
    export_crew.export()
    sp_export.export_all()          # species (basalt, emberkin, fenn + race wave 1), hand weapons + fx, gear
    for C in COMPS:
        c = C() if isinstance(C, type) else C
        _, _, J = comp_base.export(c)
        print(c.id, J['frame'], list(J['anims']))
    lines_medarm.export_arms()       # the healing arms' segments (medbay_mk2/3 _upper, _fore, _head)
    lines_belt.export_tiles(ART + '/tiles')
    tile_wreck.export()
    tech_b.export_projectiles()      # racial tech projectiles + impacts (group b)
    techa_all.export_all()          # racial tech a
    hand_race.export_all()          # racial hand weapons (art/items/<id>.png + art/items/fx/muzzle_<name>.png)
    # every gun's outside half and barrel in its new shape (docs/GUNS.md 8): overwrites the older `_out` / `_barrel` files above; own process, as its palette letters are its own
    subprocess.run([sys.executable, os.path.join(os.path.dirname(os.path.abspath(__file__)), 'gun_recipes.py')], check=True, cwd=os.path.dirname(os.path.abspath(__file__)), stdout=subprocess.DEVNULL)
    subprocess.run([sys.executable, os.path.join(os.path.dirname(os.path.abspath(__file__)), 'gun_recipes_g2.py')], check=True, cwd=os.path.dirname(os.path.abspath(__file__)), stdout=subprocess.DEVNULL)    # the 39 G2 guns and their breeches (docs/GUNS.md 5, 7)
    # sector space art (debris, intakes, radars, tractor, HUD icons, backdrop, jump fx) runs in its own process: its palette
    # letters (pal_sector) reuse letters that race wave 1 (pal_races1) gives other colours, so the two can't share px.PAL
    subprocess.run([sys.executable, '-c', 'import sector_all; sector_all.export_all()'], check=True, cwd=os.path.dirname(os.path.abspath(__file__)))
    # the pixel UI kit (9-slice frames, icons, cursors in art/ui) also runs in its own process, for the same palette-letter reason
    subprocess.run([sys.executable, os.path.join(os.path.dirname(os.path.abspath(__file__)), 'ui_kit.py')], check=True, cwd=os.path.dirname(os.path.abspath(__file__)))
    subprocess.run([sys.executable, os.path.join(os.path.dirname(os.path.abspath(__file__)), 'assets_md.py')], check=True)
