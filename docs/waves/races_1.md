# Race wave 1: the spec (lead, 2026-10-30)
Six new races (CONTENT_PLAN section 5, rows 5–9 and 11). Each race is data plus art plus writing:
- **data**: a pack `data/packs/races_1/` with `species.json` and the new traits;
- **art**: `art/crew/<species>/`, the same layered rig format as `art/crew/human`, `basalt`, `emberkin` and `fenn`, with the same arm mounts so every item fits;
- **writing**: names, 3+ events each with blue options, and a culture line in LORE.

## The six
| id | name | look (art) | lore | traits (library keys, CONTENT_PLAN section 2) | sidearm |
|---|---|---|---|---|---|
| kett | Kett | insectoid hive-workers: a chitin plate back in amber/brown, 4 thin arms (only 2 hold items, 2 are small and tucked), antennae, compound eyes as 2 glossy dark pixels | stranded hive fragments working Scrapper docks in crews of 3–5; they get sad alone | `swarm` (work +25% per other Kett in the room, max +50%), hp ×0.8 | rivet_gun |
| mire | Mire | amphibians: smooth teal-green skin with a paler belly band, wide head, webbed hands, a dripping water-tank backpack (their own rig accessory) | shipboard firefighters by tradition; Concord fire crews | extinguish ×2, fire damage ×0.5, `dries_out` (lose 2 hp/s in rooms with heat > 60) | service_pistol |
| sporeling | Sporeling | a walking fungus colony: a mushroom-cap head (cream with rust spots), a fibrous body, spore puffs as glow pixels | grown aboard derelicts; Lumen find them fascinating | aura o2 +0.01/s and heal +1 hp/s in their room, speed ×0.8, fire damage ×1.5 | flare_gun |
| gauntling | Gauntling | salvage cyborgs: half the body is mismatched machine plates and a work lamp eye, with cable dreadlocks | Scrapper outcasts rebuilt after accidents; proud of every part | `mechanical` (healed by the repair job, not beds), o2_use 0.5, `ion_stun` 3 s, repair ×0.8 | multi_tool |
| prismatic | Prismatic | Lumen crystal-born: a faceted crystal body in navy and cyan with a light core in the chest (glow), no visible mouth | born inside the Prism's growth chambers; they hum when content | station `power_bonus` +1 to the system they man, ion damage ×2, melee ×0.5 | gatekeepers_lance |
| grundl | Grundl | huge haulers: drawn **larger** (the large rig: up to 4×4 cells of art over the normal 2×2 body), a hunched back, a tusked heavy jaw, a cargo harness | freight families on Concord barges; gentle, enormous, always hungry | hp ×1.8, speed ×0.7, restock ×2, melee ×2, repair ×1.3 (clumsy) | quarry_hammer |

- **Body**: every one of them uses the normal **2×2 body** for pathfinding (they fit 2-wide doors). The Grundl's *art* is larger and overhangs; its shadow and pivot stay at the 2×2 centre.
- **New trait keys this wave needs** (one code brief before the data lands):
  - `swarm`, `dries_out`, and `aura` (o2 and heal);
  - `mechanical`, `ion_stun`;
  - `station.power_bonus`;
  - `work_mult` groups (repair, extinguish, restock);
  - `melee_mult`, `damage_taken` by type.
- **Recruiting**:
  - Kett at Gantry Rusthold;
  - Mire and Grundl at Meridian;
  - Sporeling and Prismatic at the Prism;
  - Gauntling at Gantry Rusthold and in Scrap `trader` events.

## Art brief (one agent; the species art agent's rig, generator and quality bar)
- Read `docs/ART_STYLE.md` "The approved look" and look at `docs/art_reference/crew_species.png`, the bar to match.
- Reuse `art/_src/sp_*.py` (the species generators) and the human rig layout: legs (walk 6 + stand), torso, arms (6 poses: unarmed, pistol, rifle, tool, heavy, melee), head (hair/helmet or species variants), `_color` masks, and `crew.json` anchors **identical to the other species**, so items fit.
- **Silhouettes must read apart at 1×**: the Kett's extra arms and antennae, the Mire's head and tank, the Sporeling's cap, the Gauntling's lamp eye and asymmetry, the Prismatic's facets and core glow, the Grundl's size.
- Glow layers: Sporeling spores, the Gauntling lamp, the Prismatic core and edges.
- A preview sheet like `species_sheet.png`: every race at 4 rotations × 3 weapons, a 1× line-up of all 10 species, silhouettes, and the Grundl next to a human for scale.
