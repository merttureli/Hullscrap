"""Regenerates every art file this generator owns: palette, crew, items, components, tiles, ASSETS.md rows."""
import subprocess, sys
from px import *
import export_crew, comp_base, comp_laser, comp_new, sp_export
import lines_reactor, lines_engine, lines_o2_shield, lines_shield, lines_shop, lines_belt     # equipment lines + workshop + belts (extra palette letters register on import)
LINES = lines_reactor.ALL + lines_engine.ALL + lines_o2_shield.ALL + lines_shield.ALL + lines_shop.ALL + lines_belt.ALL
REPLACED = {'engine_mk1', 'shield_mk1'}            # redrawn by the lines modules (engine split into core + _out, shield with the new animation); comp_engine.py is the old west-facing engine, superseded
COMPS = [C for C in [comp_laser.Laser] + comp_new.ALL if C.id not in REPLACED] + LINES
if __name__ == '__main__':
    write_palette_gpl(ART + '/palette.gpl')
    export_crew.export()
    sp_export.export_all()          # species (basalt, emberkin, fenn), hand weapons + fx, gear
    for C in COMPS:
        c = C() if isinstance(C, type) else C
        _, _, J = comp_base.export(c)
        print(c.id, J['frame'], list(J['anims']))
    lines_belt.export_tiles(ART + '/tiles')
    subprocess.run([sys.executable, 'assets_md.py'], check=True)
