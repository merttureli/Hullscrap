# Race waves 2–4: on to 30 species (owner, 2026-10-30: "loop the races until we reach 30 unique ones")
Ten are on main: Human, Basalt, Emberkin, Fenn, Kett, Mire, Sporeling, Gauntling, Prismatic and Grundl. These waves add 20 more.
- Each wave is the same three-part loop as race wave 1 (`docs/waves/races_1.md`):
  - **hooks**: one code brief for the new trait keys the wave needs (in `scripts/crew/traits.gd`, one test per key, an entry in its `KEYS` list);
  - **art**: the rigs, in the approved style, with a preview sheet;
  - **data and writing**: a pack `data/packs/races_<n>/` (species, traits, names), recruiting tables, and **3 events per race with blue options**.
- The waves run back to back. A wave's art can start before its hooks merge.
- **Silhouettes must read apart at 1×** against all the earlier species. Art agents get the full line-up sheet of every species so far.

## Wave 2: six races (new rigs: small, floating, large)
| id | name | look | lore and home | traits (keys) | sidearm |
|---|---|---|---|---|---|
| vellum | Vellum | folded paper-folk: crisp creased planes, ink-mark eyes, a **small rig** (art fits 1 cell) | Lumen archivists, folded from salvaged star charts; Prism | `body` 1 (fits 1-cell crawlspaces), hp ×0.5, speed ×1.2, fire ×2 | spark_pistol |
| oorth | Oorth | tall, still and hooded, with a glowing third-eye ridge | quiet telepaths who read ships; Meridian advisors | `reveal_enemy` (your schematic shows the enemy's crew and systems), melee ×0.5 | service_pistol |
| drakkin | Drakkin | a reptile brawler with a crest and a scaled hide in rust and ochre, on the **large rig** | Clan pit-fighters; Rusthold | melee ×1.75, hp ×1.2, `heat_speed` (speed ×0.7 when room heat < 20, ×1.2 when > 50) | quarry_hammer |
| wisp | Wisp | living current: a **floating rig** (no legs, a trailing glow tail), a body of light ribbons | born where lightning met wreck-fields; anomalies | `vacuum_walk` (no breach or vacuum penalties), o2_use 0, `no_tools` (can't repair or extinguish), station manned ×1.5, ion ×2 | none |
| hullkin | Hullkin | barnacle-folk: a ridged shell back, small grasping limbs, an eye-stalk | they live on the outside of old hulls; Boneyard wrecks | `hull_mend` (idle: repairs adjacent wall hp 1/s and seals breaches slowly), speed ×0.5, o2_use 0.5 | multi_tool |
| lantern | Lantern | moth-folk: dusty wings folded on the back (**floating rig** when gliding), feathery antennae | Concord pilots by tradition; Meridian | speed ×1.3, station evasion +0.05 at the helm, hp ×0.8 | carbine |
- **Hooks for wave 2**:
  - `body` 1: the pathfinder learns 1×1 clearance for small bodies. They can use 1-wide corridors, which ships may now include as crawlspaces.
  - `reveal_enemy`, `heat_speed`, `vacuum_walk`, `no_tools`, `hull_mend`;
  - `station.evasion_add`.

## Wave 3: seven races
| id | name | look | lore and home | traits | sidearm |
|---|---|---|---|---|---|
| revenant | Revenant | pale, stitched, in a salvaged pressure-suit with dead lamps; their eyes are faint cold dots | Hollow-touched survivors, avoided by all; Gate approaches | o2_use 0, `revive_once` (the first downing revives at 50 hp after 10 s), bed heal ×0, medbay ×0.5, hp ×1.1 | rivet_gun |
| choir | Choir | crystal singers: a hollow resonant body with sound holes and a ring of tuning prongs | Lumen chantry; Prism | aura work ×1.15 for others in the room, melee ×0.3 | none |
| rattler | Rattler | scrap gremlins: big ears, goggles, a tool belt, on the **small rig** | live in Rusthold's walls; Rusthold | `body` 1, `line_affinity` {scrap: work ×2}, hp ×0.6 | multi_tool |
| tessellate | Tessellate | a swarm of tiny bots in a person shape; pixel "gaps" show between the bots | a runaway Concord repair swarm that woke up; Boneyard | `split_on_death` (becomes 2 small 1×1 bodies that reform in 30 s if both live), o2_use 0, ion ×2 | spark_pistol |
| sable | Sable | lean and dark-coated, with cutter torches on both forearms | boarding-crew families; pirate nests and traders | breach work ×2 (cutting doors), ranged ×1.25, hp ×0.9 | carbine |
| quillback | Quillback | spined and proud: a back of quills (they flare as a pose), striped | Clan duellists; Rusthold | `counter_melee` 10, hp ×1.1, `no_suit` | ember_knife |
| kite | Kite | born in zero-g: long thin limbs, a tail for grip, wide eyes | drift-nomads living in ship gaps; empty nodes | suffocate ×0.5, `vacuum_speed` ×1.5 (in rooms below 30% air), hp ×0.9 | flare_gun |
- **Hooks for wave 3**: `revive_once`, `line_affinity`, `split_on_death`, `counter_melee`, `no_suit`, `vacuum_speed`.

## Wave 4: seven races, completing the roster at 30
| id | name | look | lore and home | traits | sidearm |
|---|---|---|---|---|---|
| warden_frame | Warden-frame | a rebuilt Lumen drone: sleek neon panels, a single lens, mechanical limbs | recruited only by quest (rebooting a Warden); landmark | `mechanical`, o2_use 0, ranged ×1.5, ion ×3 | gatekeepers_lance |
| murrow | Murrow | mole-folk: huge digging claws, tiny eyes, a dust-caked miner's harness, **large rig** | asteroid-colony diggers; mining fields | `mining_mult` 1.5 (rock damage when manning a mining tool or cutting), hp ×1.2, speed ×0.9 | quarry_hammer |
| siltborn | Siltborn | jellyfish-like gas floaters: a translucent bell and trailing tendrils, **floating rig** | from a gas giant's rings; anomalies | o2_use 0.5, `low_pressure_heal` (heal 1 hp/s in rooms below 50% air), fire ×2 | none |
| corvin | Corvin | crow-like scavengers: a beaked head, a feather cloak, pockets everywhere | wreck traders with an eye for shine; traders | `haggler` (prices −10%), `loot_bonus` (+1 roll on wreck, salvage and loot tables) | service_pistol |
| brine | Brine | crab-shelled dockworkers: a broad carapace, one big work claw, **large rig** | Concord dock unions; Meridian | damage_taken melee ×0.7 and ranged ×0.7, restock ×1.5, speed ×0.85, `no_suit` | rivet_gun |
| echo | Echo | a shimmering mimic: a smooth body whose surface shows a faint reflection of whoever is near | rare, curious and polite; anomalies | `mimic` (copies the best non-body trait of another crew member in the same room, while there) | spark_pistol |
| ferro | Ferro | living ferrofluid: a spiky liquid-metal body that ripples, with magnetic sparks | born in the Boneyard's magnetic wrecks; Boneyard | ion ×0 (immune), `station.pull_bonus` +1 (the salvage intake they man pulls 1 cell further), `hull_mend` 0.5 | multi_tool |
- **Hooks for wave 4**: `mining_mult`, `low_pressure_heal`, `haggler`, `loot_bonus`, `mimic`, `station.pull_bonus`. Warden-frame needs a quest event that grants it (writer).

## Writing per wave
- **LORE.md**: one paragraph per race.
- **Names**: 12 per race, each with its own sound.
- **3 events per race**: one where the race is the centre of the story, and two blue options in existing node types.
- **The recruit weights** at their home stations and node types.
