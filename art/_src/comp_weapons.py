"""Every weapon of art wave 2 (two halves + barrel) and the ammo rack. build_all.py adds ALL to its list; build_weapons.py builds just these."""
import comp_laser, comp_w_std, comp_w_scrap, comp_w_neon, comp_ammo
WEAPONS = [comp_laser.Laser] + comp_w_std.ALL + comp_w_scrap.ALL + comp_w_neon.ALL
ALL = comp_w_std.ALL + comp_w_scrap.ALL + comp_w_neon.ALL + [comp_ammo.AmmoRack]      # laser_mk1 is already in build_all's list
