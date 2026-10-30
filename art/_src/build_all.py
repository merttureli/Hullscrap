"""Regenerates every art file this generator owns: palette, crew, items, components, ASSETS.md rows."""
import subprocess, sys
from px import *
import export_crew, comp_base, comp_engine, comp_laser, comp_new, sp_export
COMPS = [comp_engine.Engine, comp_laser.Laser] + comp_new.ALL
if __name__ == '__main__':
    write_palette_gpl(ART + '/palette.gpl')
    export_crew.export()
    sp_export.export_all()          # species (basalt, emberkin, fenn), hand weapons + fx, gear
    for C in COMPS:
        _, _, J = comp_base.export(C())
        print(C.id, J['frame'], list(J['anims']))
    subprocess.run([sys.executable, 'assets_md.py'], check=True)
