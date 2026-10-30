"""Regenerates only the wave-2 weapon art: laser_mk1 + every weapon (inside half, `_out` half, `_barrel`), the ammo rack, tiles/wreck, and the ASSETS.md rows."""
import subprocess, sys
from px import *
import comp_base, comp_weapons, tile_wreck
if __name__ == '__main__':
    for C in [comp_weapons.WEAPONS[0]] + comp_weapons.ALL:
        _, _, J = comp_base.export(C())
        print(C.id, J['frame'], list(J['anims']))
    tile_wreck.export()
    subprocess.run([sys.executable, 'assets_md.py'], check=True)
