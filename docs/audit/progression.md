# Progression audit: the natural progression of a run, played by a bot (Beta 3, track `progress`)

Branch `claude/progress`. The bot is `tests/tool_progress.gd`; this file is its findings and the milestone ladder a tutorial advisor can teach.
Method in one paragraph: a seeded, headless "sensible player" drives the real `Campaign`, `Sector`, events, stores, fabricator, `BuildSession` and the real arena (the pilot AI of `tool_balance.gd`) through 8 stages. Per node it plays every POI event (a value-maximising choice that shuns fights rated 4+ skulls), collects debris for 90 s with the real intakes in the real `DriftDebris`, then spends by a ladder (intake, guns, shield / medbay, engines, fabricator level, titanium, armour last). It crafts what the fabricator can run, buys at stations, sells the surplus, pays the warden's toll when it can, and fights on a copy of its ship (parts count as mended between fights; hull integrity is not).

## 0. Read this first: two mains

- **The tables in sections 2-8 were measured on `origin/main` at 2bca36b** (hull integrity as a pool, fuel start 6, no shop blueprints). While the runs were going, `economy` (fuel start 22 at 14 credits, canisters 6x rarer, small shops with rare items and 7 blueprints on sale), `hull` / `hull2` (no hull pool: block hp, parts wrecked in a fight stay wrecked, stations repair all blocks, crew mend walls) and `board3` merged. The tool is ported to that main (it runs; `Structure` replaces `hull_left` / `fight_hull`, fights are on the ship itself, a `mend()` step runs the crew's repair jobs). The dynamics changed enough that the new-main sample in section 11 does **not** agree with the baseline in places. Re-run the tool before fixing any number into the game.
- What still holds on the new main, and what does not: see section 11. In short, the *direction* of the findings (gun count carries the power rating, blueprints and tier-2 parts are the gate, scrap piles up) holds; "nothing forces you to build" and "the ladder bot almost always finishes" do **not**: fuel and structure now decide runs.

## 1. What was run

| set | policy | runs | stages | note |
|---|---|---|---|---|
| main | `ladder` (the brief's order) | 3 starters x 4 seeds = 12 | 8 | seeds 0-3; 8 finished, 3 stuck, 1 died |
| guns | only intake, laser guns, engines | 3 x 2 | 5 | "spam the scrap gun" |
| turtle | intake, shields, medbay, armour, 2-4 guns | 3 x 2 | 5 | |
| idle | places the intake, builds nothing else | 3 x 3 | 8 | still sells scrap, pays tolls (affordable ones when rated 3+ skulls), flees fights; run before the last toll rule |

The brief asked for 3 x 10; a full 8-stage run costs 5-50 CPU minutes on this shared box (a fight is 3-15 s of real time), so the main set is 12 runs. The numbers are means of few runs: read them as a shape, not a decimal. Raw rows of every run are reproducible with the tool (`seeds=`, `first=`, `policy=`, `dump=`). Data and code are `origin/main` at 2bca36b; main has since gained the boarding B3 events (new people events, which may add credits, crew and blueprints), so re-run before trusting the economy columns to the unit.

Caveats that move the numbers (all of them make the bot a *careful* player):
- The pilot AI draws a lot: 2/3 of fights end in a stand-off at the 180 s cap (300 s for a warden) or when the bot breaks away (hull under 30%, then the 10 s jump spool). `BALANCE_REPORT.md` has the same artefact (54% drawn). So "win %" below is the raw share of kills and captures, and **projected** is the share the player was winning (tool_balance's `_lean`).
- The bot never misplays a flight; it always flees a lost fight in time. Enemy damage per second (0.5-2 against a hull of 200-700) makes a 10 s spool cheap, so deaths are rare. A human will die more.
- The bot visits about 5 POIs and 7.7 nodes a stage and stays 90 s at each node. Time figures are "bot minutes" and depend on those choices.
- It never builds a smelter, a radar, a tractor or a missile boat, and never refits (it only adds). Ammo weapons are not special-cased.

## 2. The curve: player power against enemy power, by stage (main set, 12 runs)

Power is `Threat.power` (sqrt(dps x effective hp) x speed). "Ref enemy" is a generated enemy at the middle of the stage (11 jumps a stage; the bot made 11-17) and the region danger 1.1; "ref warden" the exit warden of six regions. Both come from `Shipgen` / `Wardens` directly, no fights. "Met" is the mean power of the enemies the bot really fought.

| stage | runs in | player power start > end (median end) | ref enemy | ref warden (range) | met | met / player | fights a run | win % raw (projected) | outcome |
|---|---|---|---|---|---|---|---|---|---|
| 1 | 12 | 12 > 21 (21) | 4 | 16 (13-22) | 7 | 0.31 | 5.2 | 61% (90%) | none lost |
| 2 | 12 | 21 > 31 (30) | 9 | 28 (15-39) | 11 | 0.42 | 4.9 | 49% (69%) | 3 courier runs stuck (fuel + hull) |
| 3 | 9 | 31 > 41 (42) | 22 | 45 (32-62) | 14 | 0.37 | 3.1 | 39% (85%) | none |
| 4 | 9 | 41 > 50 (46) | 29 | 45 (33-55) | 18 | 0.37 | 4.3 | 30% (71%) | none |
| 5 | 9 | 50 > 55 (53) | 33 | 47 (31-67) | 27 | 0.49 | 5.8 | 11% (59%) | none |
| 6 | 9 | 55 > 62 (62) | 40 | 48 (30-69) | 29 | 0.47 | 3.1 | 3% (57%) | none |
| 7 | 9 | 62 > 70 (73) | 43 | 42 (31-56) | 30 | 0.45 | 5.3 | 18% (72%) | 1 death at a warden it could not pay |
| 8 | 8 | 71 > 76 (78) | 42 | 46 (31-65) | 28 | 0.38 | 4.9 | 28% (79%) | none |

By starter, power at the end of stages 1 / 4 / 8: Rustbucket 20 / 46 / 67, Courier 23 / 52 / 81, Prism 21 / 54 / 81 (starting at 13 / 13 / 9).

**Where the gap opens and closes**
- Ref enemy / player power at the stage start: 0.34, 0.41, **0.70**, 0.70, 0.65, 0.72, 0.70, 0.60. The enemy budget jumps at jump 25 (tier 3: base 100 against 44, even with the stage factor 0.7): enemy power goes 9 > 22 in one stage while the ladder player goes 21 > 31 > 41. **Stage 3 is the cliff**; after it the ladder player keeps pace (gun count rises one a stage).
- Ref warden / player power at the start: 1.36, 1.35, **1.46**, 1.10, 0.94, 0.88, 0.68, 0.65. The first three wardens are rated above you when you arrive; from stage 5 the ladder outgrows them. The wardens' own power is flat (45-48 from stage 3), so for a player who keeps building, stages 5-8 are easier than 3-4.
- From stage 4 every generated enemy has a shield (`shield_cap` 1.0); stage 3 has 25%. The bot's laser spam still wins most of them; nothing in the data shows a counter being *needed* (it never fought an ion-proof wall on purpose).

**Where runs end** (12 main runs): 8 finished all 8 stages; 3 ended at stage 2 (all Courier: no fuel, hull under 25% so the 15-hull drift jump is refused, one tow used); 1 died at stage 7 (a Concord warden rated 3 skulls that it could not pay: 21 credits against a 280 toll after the stage's repairs).
Past stage 2 the *only* kill was a fight the bot was forced into by an unaffordable toll. In 74 warden meetings the toll was paid 72 times.

## 3. The top 5 problems

1. **Nothing makes you build; wardens are a toll booth.** The `idle` bot (power 12 all run: one intake placed, nothing else built) finished all 8 stages in 9 of 9 runs, 220-290 bot minutes each: it sells scrap at 1 credit each, pays the toll (30-320 credits: `toll x stage`), and leaves every bad fight after the 10 s spool. The ladder bot, at 6x the power, finished 8 of 12; all four failures were fuel, hull or credits, none was firepower. So the owner's "very free and enabling, but we need direction" is exact: no mechanic rewards or demands growth. The levers: the toll formula (30-60 x stage, against 1200-1500 spare credits from stage 3), the 1:1 scrap price, and the cheap escape (enemy dps 0.5-2.2 a second against a hull of 200-700 makes 10 s of spooling cost 1-10% of the hull).
2. **Blueprints are the real gate, and they almost never arrive.** 0 of 583 events grant one. The only sources are a "Scan" row on a salvage page after a won or captured fight (offered in 16 of 77 salvage pages here; 11 of the 13 blueprints learned were Reactor Mk2, a level-3 recipe that needs plasma cells, taken at stage 1 because the early enemies carry it) and the Repair Drone scan (20% of wrecks). Known recipes: 22 > 23 over eight stages. 115 of 151 recipes stay locked all run. With the fabricator at level 2, 78-87 of them would be ready the moment their blueprint arrived; at level 1 only 15.
3. **The fabricator ladder stops at level 2.** Level 2 costs a Robot Arm (15 scrap + 10 copper, a start-known recipe, a 2x2 floor spot in the fabricator's room), so it is reachable in the first minutes; the bot built it at stage 2 by policy. Level 3 needs an Assembly Rig + two arms, and the Rig, the Laser Cutter (also the tool for Titanium) and the Nanoforge are *not* start-known, so no run reached level 3 (0 of 12). Level 2 therefore pays off at once for nothing, and the titanium recipe (20 scrap > 2 titanium, needs the cutter) is out of reach: titanium sits at 22-39 (events only), silicon 17 > 82, both never the bottleneck because nothing uses them.
4. **Scrap and copper pile up unused while credits and fuel decide the run.** Scrap held at the end of a stage goes 1127 > 1619 > 1990 > 2605 > 2532 > 2654 > 3070 > 3334 (copper 260 > 1069), after the bot sold every stop's surplus above 600 + 250 x stage. Events give 66-71% of the scrap (1360 > 1019 a stage), debris 30% > 19%, wrecks 4-10%. Credits come from selling that scrap (1 each) and are scarce only before the first station. Debris income *falls* as the ship grows (scrap 607 > 266 a stage, pieces 359 > 160) although mouths go 1 > 3: the ship gets heavier (acceleration 85 > 48 even with 1 + stage/2 extra engines) and the intake rate follows the flight speed; the Hollow tide also thins late stages.
5. **Hull and fuel make the Courier unplayable by this bot.** Hull is repaired only at stations (one per region, 2 credits a point) and a drift jump with no fuel costs 15. Hull max is 20 + 2 x armour cells: Rustbucket 246, Courier 168 and Prism 152 at the start. Courier reached stage 2 with 59-128 hull of 168 in all four runs and no fuel in two, then drifted until the hull was under 25 and stranded (3 of 4). 4 of 12 runs reached stage 2 with no fuel. (The `economy` track is cutting fuel; this gets worse, see section 9.)

Smaller things: stage 1 costs 40 bot-minutes and the whole run 258 (320 for finishers); the fights a finisher meets number 27-51 (mean 37), 2/3 of them stand-offs; the third and second intake are not worth their upkeep by the bot's numbers (see 5); the debt (1000 credits, 100 every 8 jumps in stages 1-2) is ignored by a player who pays no instalments, and costs only the "repo" fights (36 of them in the 12 runs, the most common fight).

## 4. Stalls

- **First 10 minutes:** nothing to buy. The starters carry 250 scrap, 80 copper, 300-500 credits, and their intake *unplaced*. Until it is mounted the hold only grows from events.
- **Stage 1-2 credits:** the first station is the only sink and source; credits end stage 1 at 20-570 and the hire price is 450, so a ship that hires a crewmate there (the bot does when it has price + 100) cannot afford fuel or repair at the next stop.
- **From stage 3:** nothing to spend scrap on but more laser guns, plates and Mk1 shields. Ready-to-craft tier-2 parts need blueprints; stores that stock them (Meridian: shield 330, laser 280, reactor 320; 15 of 29 region stocks list a tier-2 weapon, shield or reactor, mostly race parts at 280-560) are one per region and rarely in reach (one Mk2 shield bought in 12 runs).
- **A resource always short:** fuel (6 at the start; 5 > 25 bought and found per stage; 4 of 12 runs reached stage 2 empty) and, until the first sale, credits.
- **Never short:** scrap, copper, polymer, titanium, silicon (nothing consumes them).

## 5. Too easy: one strategy carries the run

Five-stage runs (stages 1-5); the ladder row is the main set cut at stage 5, the others are 6 runs each on seeds 0-1:

| policy | finished stage 5 | power end of stage 1 / 3 / 5 | guns / layers at stage 5 | raw win % (projected) stages 1-5 |
|---|---|---|---|---|
| ladder | 9 of 12 (the other 3 stranded at stage 2) | 21 / 41 / 55 | 8 / 5 | 61, 49, 39, 30, 11 (90, 69, 85, 71, 59) |
| guns | 4 of 6 (a Rustbucket short of the 30-credit stage-1 toll, a Courier stranded at stage 2) | 27 / 41 / 52 | 14.5 / 1.2 | 54, 60, 62, 72, 18 (88, 95, 87, 90, 86) |
| turtle | 2 of 6 (stuck at the stage-1 and stage-2 wardens at power 14 and 24, one dead at stage 2, one stuck at stage 5) | 19 / 37 / 48 | 4.7 / 6.3 | 42, 30, 50, 22, 23 (67, 46, 90, 77, 47) |
| idle | 6 of 6 | 12 / 12 / 12 | 1.3 / 1 | 56, 52, 55, 20, 0 (82, 70, 66, 20, 0) |

- Guns alone reach the power of the whole ladder one stage earlier (27 against 21 at the end of stage 1) with half the installs per run (13 against 27), and win more of their fights (raw 54-72% in stages 1-4 against 61-30%). Dps is linear in guns while effective hp grows slowly, so a Mk1 laser is worth more rating than a shield layer or ten plates until the ship is slow: `laser_mk1` alone is 96 of the ladder's 328 installs.
- A Mk1 laser costs 18 scrap + 12 copper and takes a 2x2 inside and a 4x2 outside spot; the bot adds one a visit. Nothing in the 14.5-gun runs shows a counter being needed before stage 5.
- The turtle (shields and plates first) is the one that does not work: at the same age it has a third of the guns, loses the early wardens (power 14-24 against 16-28) and dies or sticks in 4 of 6 runs. Shields and plates are not what the early game rewards.
- The idle ship is not slower to finish: it never stops to build (220-290 bot minutes for eight stages against 258-320 for the ladder).
- Armour is cheapest (a scrap plate is 1 scrap for +2 hull) and the weakest lever: 79 plate visits add +200 cells by stage 8 (Rustbucket hull max 246 > 646) at the price of mass (acceleration).

## 6. Gates

| gate | finding |
|---|---|
| Fabricator level 2 | reachable in the first minutes (a Robot Arm: 15 scrap + 10 copper, in the fab room). The bot had it at the end of stage 2 in 12 of 12 runs. It pays off only when a blueprint arrives. |
| Fabricator level 3, 4 | not reached (0 of 12): Assembly Rig, Laser Cutter, Nanoforge need blueprints; the Nanoforge also nanite paste (events, very rare). |
| Tier-2 parts | craftable: none in 12 runs (no Mk2 blueprint came; Reactor Mk2 came 11 times and is a level-3 recipe). Bought: 1 Shield Mk2. Found: a few Mk2 parts cut from wrecks. |
| Tier-3 parts | never seen. Stores sell tier-3 engines only (Meridian 480). |
| Blueprints | 13 learned in 12 runs x up to 8 stages (11 Reactor Mk2, 2 Repair Drone); 16 Scan rows offered in 77 salvage pages; first one at stage 1. |
| Smelters | 12 of 151 recipes (8%) need a smelter product (steel, alloy, conductor, glass lattice): engines Mk3+, the neon / scrap engine tiers and the Smelter Mk3. No gun, shield or reactor does. A smelter is worth building only for a tier-3 engine; none of the 12 runs missed it. |
| Fights in a run | 27-51 (mean 37), 3-7 a stage, 40% of them forced by "repo" or hollow events; 1 in 3 ends in a kill, a capture or a surrender, 1 in 10 in an escape of the enemy, the rest in a stand-off or a break-away. |
| Warden | paid 72 of 74 times. The toll is `30-60 x stage` (30, 69, 110, 151, 169, 233, 245, 320 as met). |

The screen of recipes at fabricator level 2 (mean over runs, per stage): 22 craftable now, 78-87 would be ready with their blueprint, 14 need level 3, 10-19 are short of materials, 3 need a tool.

## 7. The milestone ladder (what a good player should do, stage by stage)

Checks are `Ship` queries a tutorial advisor can run: `intakes` = working intakes (`DriftDebris.intakes`), `guns` = powered weapons, `layers` = `Shields.layers_of_ship`, `fab` = `Workshop.best(ship).level`, `power` = `Threat.power(ship, 0.75).power`, `margin` = supply less demand of the biggest power network, `accel` = `Sector.flight_numbers(ship).accel`, `plates` = armour cells added to the starter's own.
Power targets are the lowest end-of-stage power among the ladder runs that went on (the floor), with the median in brackets; the "warden" figure is the mean rating of that stage's exit warden.

**Stage 1 (jumps 0-14; enemy 4, warden 16): a ship that collects and shoots**
1. Mount the intake from the hold on the bow side, facing the debris. Check `intakes >= 1`. Why: the starters carry it unplaced; debris is 30% of the scrap and about 50 scrap a minute with one net mouth.
2. Three guns and a shield or a medbay (a Reactor Mk1 with the third gun). Check `guns >= 3 and (layers >= 1 or medbays >= 1) and margin >= 0`. Why: it takes power 12 > 21 and is the first thing the pilot AI needs to finish a fight.
3. At the first station: sell scrap above 600 and copper above 330, repair, buy fuel to 6+. Check `fuel >= 6` and `hull_left >= 70%` when leaving. Why: 4 of 12 runs reached stage 2 with no fuel.
4. Keep 70 credits for the toll (30) and do not hire before fuel is bought. Check `credits >= 70` at the beacon, or `power >= 17`.

**Stage 2 (jumps 14-28; enemy 9, warden 28): a fabricator that can grow**
1. Fabricator level 2 (a Robot Arm in the fabricator's room). Check `fab >= 2`. Why: 85 recipes become ready once their blueprints are found; cost 25 scrap + copper.
2. Four guns, one engine per three guns and 2 shield layers (or 20 plates). Check `guns >= 4 and layers >= 2 and accel >= 0.75 x start and power >= 28` (median 30).
3. Take every Scan row. Check `known >= 23`; a Mk2 laser or shield blueprint ranks above anything else on the salvage page. Visit a station that sells Mk2 parts (Meridian) with 330 credits.
4. Before the beacon: credits above the toll (70) + 40, fuel above the jumps to the exit, hull at 60%+.

**Stage 3 (jumps 28-42; enemy 22, warden 45): the cliff, tier-3 enemies from jump 25**
1. Six guns, three shield layers, a second intake. Check `guns >= 6 and layers >= 3 and intakes >= 2 and power >= 34` (median 42).
2. Plates: +40. Check `plates >= 40`.
3. Credits for the 110 toll, sold from scrap at a station before the beacon. Check `credits >= 150`.
4. Do not take a fight rated 4+ skulls (`ratio >= 1.6`). The only death in the sample was a 3-skull warden fought because the toll could not be paid.

**Stages 4-5 (enemy 29-33, warden 45-47): every enemy has a shield**
1. Eight guns, 4-5 layers. Check `guns >= 8 and layers >= 4 and power >= 43 (stage 4; median 46), 45 (stage 5; median 53)`.
2. Carry one shield-piercing weapon (ion blast, Artemis with a rack of missiles). Check one `weapon.pass_shields` or `damage_type == ion` among the guns. Why: stated by CONTENT 14, not tested by the bot, which won with lasers.
3. Three engines or more. Check `accel >= 0.6 x start`: the Courier-build at 0.5 starts to lose the intake and the aim.
4. Plates +70-100, a tier-2 shield bought if a station has one.

**Stages 6-8 (enemy 40-43, warden 42-48)**
1. Nine, ten, eleven guns; 5-7 layers; power 54 / 59 / 61 at least (medians 62 / 73 / 78). Check `power >= 54, 59, 61`.
2. Plates +130 to +200 and `hull_left >= 60%` before every beacon.
3. Credits 250 / 250 / 330 + 40 for the toll; sell above `600 + 250 x stage` scrap.
4. Keep `margin >= 0`: the bot ran with a margin of 1-3 after each reactor.

## 8. Warning triggers (an advisor can fire these with the numbers it already has)

| trigger | warn when | numbers behind it |
|---|---|---|
| Outgunned at a beacon | `power < 0.8 x warden` of the stage (13 / 23 / 36 / 36 / 38 / 38 / 34 / 37) and credits below the toll | warden means 16 / 28 / 45 / 45 / 47 / 48 / 42 / 46; ladder end-of-stage medians 21 / 30 / 42 / 46 / 53 / 62 / 73 / 78 |
| The stage-3 cliff | entering stage 3 (or jump 25) with `power < 36` | ref enemy 9 > 22 |
| An enemy that outguns you | the fight's `Threat.rate(...).ratio >= 1.6` (4 skulls) | idle bot meets 4-5 skulls from stage 4 and survives only by leaving |
| Toll unaffordable | `credits < toll + 40` within 2 jumps of the beacon and `scrap > 600` | the one death |
| Hull | `hull_left < 55%` and the next station is over 3 jumps away | hull ends stages at 55-72% |
| Fuel | `fuel < jumps to the beacon` or `fuel == 0 and hull_left < 25%` (a drift jump would refuse) | 4 of 12 runs, 3 stranded |
| Unspent scrap | `scrap > 1500` and `credits < 200`: "sell the surplus at a station" | scrap 1100 > 3300 held |
| Mass | `accel < 0.6 x start`: add engines | accel 85 > 48 with engines; 85 > 20 without |
| Power | `margin < 0` after a purchase | a gun is 1-3 power, a reactor 9-15 |
| Blueprints | `known == 22` after stage 3: "take Scan rows, read the stores" | 22 > 23 in 8 stages |

## 9. Balance fixes

**Tweaks made: none.** The numbers do not show a single data value that is clearly wrong. Every candidate is a design call (what should force growth), so they are proposals, ordered by what they would change.

Proposals (with the effect the bot predicts):
1. **Give the fabricator ladder its blueprints.** Add `laser_cutter`, `assembly_rig` and `titanium` to `recipes.json` `start_known` (or put a `blueprint` outcome in the station, trader and anomaly events: there are none now). Effect: level 3 and the titanium loop (20 scrap > 2 titanium) become reachable at stage 2-3, which turns the unused scrap pile into tier-2 parts (laser Mk2, shield Mk2, pulse Mk2 need 4-8 titanium, 3-4 silicon: both held at 22-39 and 17-82 unused).
2. **Make the Scan row useful.** Pick the unknown recipe the *ship could craft next* (known tools, a level it has) instead of the highest-tier part among the picks. Now 11 of 13 scans were a level-3 Reactor Mk2.
3. **Put a price on the toll.** Tolls of 30-320 are 5-25% of the credits a stage-3+ player holds; scrap sells at 1:1 without limit. Options: toll `x stage^1.5`, a falling price for a big sale, or a toll in parts. Effect: the warden stops being a formality and power targets in section 7 become real.
4. **Make leaving a fight cost.** The 10 s spool costs 1-10% of the hull because enemy dps is 0.5-2.2 against a hull of 200-700. A spool that leaves the hull open to the enemy's whole broadside, or a stand-off that costs fuel, would make growth the safer road.
5. **Decouple debris from mass.** Scrap from debris halves by stage 8 although mouths triple: the flow depends on flight speed, and every gun and plate slows the ship.
6. **Courier and Prism hull** (168, 152) against the Rustbucket (246): both start under the hull the ladder needs to survive a repo fight; one more armour layer at the start, or the station repair at 1 credit a point in stage 1, would remove the stage-2 spiral.

How the tracks that were pending have shifted these numbers (they merged during the work; see section 11 for the measured effect):
- `economy` (fuel start 22, price 14, canisters 6x rarer, 13 of 33 stations sell 2-4 units; small shops with rare items and blueprints; rarer crystal / titanium / silicon in the drift): fuel is now the run's limit (section 11). Shops now sell `pulse_mk2`, `tractor_mk2`, `radar_mk2`, `intake_mk2`, and the Mk3 engines (360-640 credits), which answers part of problem 2 (blueprints) but none of the recipes that block the ladder: `laser_mk2`, `shield_mk2`, `laser_cutter`, `assembly_rig`, `titanium` are still on no shelf.
- `hull` / `hull2` (structure): the tables' hull columns, the 25-hull drift check and "hull_loss" repair do not exist any more. Threat's effective hp changed with it, so **the power numbers of sections 2, 7 and 8 are on the old scale** (a Rustbucket is 13 power before and after, but the ladder ship is 33 at the end of stage 1 on the new main against 21 on the old). Treat the ladder's checks that are not power (intake, guns, layers, fab level, engines, margin, known, fuel, credits) as stable and re-derive the power floors with the tool.

## 10. How to run the tool

```
godot --headless --path . --script res://tests/tool_progress.gd -- seeds=10 first=0 policy=ladder jobs=3 dump=rows.json out=report.md
```
Keys: `seeds`, `first`, `ships` (default the three open starters), `policy` (ladder, guns, turtle, idle), `stages`, `stay` (seconds of debris per node), `nodes`, `pois` (POIs flown per node, default 5), `jobs`, `rows`, `merge`, `dump`, `out`, `v=1`. A 3 x 4 run of 8 stages takes about an hour on three cores.
It is not a test (the runner only loads `test_*.gd`); the full suite passes with it in the tree.

## 11. A sample on the new main (economy + hull + hull2 + board3 merged)

Ladder, 3 starters x 2 seeds, 5 stages; and idle, 3 x 3, 8 stages. The sample is small, so only large shifts are worth reading.

| | baseline (2bca36b) | new main |
|---|---|---|
| ladder, runs past stage 5 | 9 of 12 | 2 of 6 (4 stuck at wardens rated 3-5 skulls at stages 2, 3, 3, 5) |
| ladder power end of stage 1 / 3 / 5 | 21 / 41 / 55 | 33 / 43 / 68 (the scale moved with structure) |
| drift jumps a stage (no fuel, each hurts the structure) | 0.3 / 1.9 / 0.3 / 0 / 0 | 0.2 / 8.7 / 4.6 / 5.7 / 11.7 |
| fuel held at the end of a stage | 5 / 9 / 22 / 24 / 19 | 2.2 / 1.7 / 0.4 / 0 / 0 |
| fuel bought a stage | 5 / 3.7 / 3 / 1.2 / 1.2 | 5 / 4.2 / 10.4 / 1.3 / 12 |
| idle, finished all 8 stages | 9 of 9 | 2 of 9 (5 stranded without fuel, 2 stuck at a 5-skull warden) |
| idle power end of stage 1 / 2 / 4 | 12 / 12 / 12 | 5.7 / 5.7 / 3.3 (parts wrecked in fights are not rebuilt) |

- **The hold-and-flee strategy is gone**: a ship that builds nothing loses its guns and reactor to the first few fights (guns 0.4 of 1.3 by stage 1), because a wrecked part stays wrecked. Building, and re-building, is now required; the tutorial has something real to teach (repair at stations: every damaged block or nothing, at 2 credits a hp; keep spare reactors and guns in the hold).
- **Fuel decides**: 5-12 drift jumps a stage in the ladder from stage 2 on, debris gives 0-2 fuel a stage (it was 5-17), events 5-13. The stage 2-3 wardens then stop the run because the ship arrives wrecked (power 43 against a warden of 45-62), with 500-1500 credits it cannot spend at the beacon. The milestone "fuel >= 6 when leaving the station" in section 7 now needs to be "fuel >= the jumps to the beacon + 2" and the warning "fuel < jumps to the beacon" fires almost always.
- Everything else (fab level 2 by stage 2 in 5 of 6; no level 3; 23 known recipes; scrap 1200-1800 held and unspent; Reactor Mk2 the usual scan) matches the baseline.
