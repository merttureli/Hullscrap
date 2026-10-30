"""Engine wave 1 (docs/waves/engines_1.md): the 15 new engines, each as a core (inside half) and an _out (outside half) with glow layers.
 standard  engine_mk3, engine_mk4, engine_mk5     (lines_eng_std.py)
 scrap     engine_scrap_mk2..mk4                  (lines_eng_scrap.py)
 neon      engine_neon_mk2..mk4                   (lines_eng_neon.py)
 strafe    strafe_jets_mk1..mk3                   (lines_eng_strafe.py)
 long-burn longburn_mk1..mk3                      (lines_eng_long.py)
engine_mk1/mk2, engine_scrap_mk1 and engine_neon_mk1 are lines_engine.py, unchanged; every tier here is built on top of them. Preview: sheet_engines1.py."""
import lines_eng_std, lines_eng_scrap, lines_eng_neon, lines_eng_strafe, lines_eng_long
from lines_eng_base import Half2

FULLS = lines_eng_std.ALL + lines_eng_scrap.ALL + lines_eng_neon.ALL + lines_eng_strafe.ALL + lines_eng_long.ALL
ALL = []
for _f in FULLS: ALL += [Half2(_f, 'core'), Half2(_f, 'out')]
