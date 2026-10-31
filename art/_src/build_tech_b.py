"""Regenerates only the racial tech art of group b (Mire, Sporeling, Gauntling, Prismatic, Grundl): 15 weapons (three files each), 15 components, 15 projectiles + impacts, and the ASSETS.md rows."""
import os, subprocess, sys
from px import *
import pal_races1                    # the Mire greens (T t U) before any sprite is drawn
import comp_base, tech_b
if __name__ == '__main__':
    for C in tech_b.ALL:
        c = C() if isinstance(C, type) else C
        _, _, J = comp_base.export(c)
        print(c.id, J['frame'], list(J['anims']))
    tech_b.export_projectiles()
    subprocess.run([sys.executable, os.path.join(os.path.dirname(os.path.abspath(__file__)), 'assets_md.py')], check=True)
