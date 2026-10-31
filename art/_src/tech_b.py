"""Racial tech art, group b: Mire, Sporeling, Gauntling, Prismatic, Grundl (docs/waves/racial_tech_1.md). build_all.py adds ALL to its component list and calls export_projectiles().
 weapons (3 each: inside half, _out half, _barrel):  the WEAPONS lists;  components: the COMPS lists (engines are two halves);  projectiles + impacts: tech_proj.py."""
import tech_mire, tech_sporeling, tech_gauntling, tech_prismatic, tech_grundl, tech_proj
RACES = [('mire', tech_mire), ('sporeling', tech_sporeling), ('gauntling', tech_gauntling), ('prismatic', tech_prismatic), ('grundl', tech_grundl)]
WEAPONS = [C for _, m in RACES for C in m.WEAPONS]
COMPS = [C for _, m in RACES for C in m.COMPS]
ALL = [C for _, m in RACES for C in m.ALL]
def export_projectiles(): tech_proj.export_all()
