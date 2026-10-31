# Balance report

Written by `tests/tool_balance.gd` (run: after) (docs/CONTENT.md 14). 216 fights: 6 ships x 6 factions x jumps [5, 15, 25, 35] x 2 seeds (the kitted ships at jumps [15, 25]), capped at 180 s, run in 1056 s (3 processes).
Both ships are flown by the pilot AI (the player's at aim 0.75, thinking every 3 ticks); crews run in ShipSim; morale can end a fight (the player takes every surrender). A cell is `win% (won/lost/drawn) mean seconds`; a draw is the cap or an enemy that escaped. Budgets: Shipgen.budget_for(tier, jump, danger of the faction's first region): clans 1.00, concord 1.05, hollow 1.35, lumen 1.00, rustfangs 1.00, wardens 1.20.

**All fights**: won 31%, lost 16%, drawn 54%, mean 129 s.

## Win rate by ship and jump

| ship | jump 5 (budget ~24) | jump 15 (budget ~70) | jump 25 (budget ~200) | jump 35 (budget ~240) |
|---|---|---|---|---|
| Rustbucket | 33% (4/1/7) 138s | 25% (3/0/9) 151s | 0% (0/4/8) 159s | 0% (0/2/10) 173s |
| Courier | 83% (10/1/1) 40s | 67% (8/1/3) 97s | 25% (3/4/5) 132s | 0% (0/7/5) 137s |
| Prism | 50% (6/0/6) 86s | 33% (4/0/8) 123s | 8% (1/5/6) 136s | 0% (0/2/10) 175s |
| Rustbucket + kit | - | 25% (3/0/9) 144s | 0% (0/1/11) 172s | - |
| Courier + kit | - | 67% (8/0/4) 97s | 33% (4/4/4) 118s | - |
| Prism + kit | - | 75% (9/0/3) 100s | 25% (3/2/7) 152s | - |
| **all** | 56% (20/2/14) 88s | 49% (35/1/36) 119s | 15% (11/20/41) 145s | 0% (0/11/25) 162s |

Projected win rate: the wins plus the draws the player was winning, by the rates of the fight (it would have brought the enemy to its morale break, 35% of its hull, before the enemy wrecked it). The cap cuts many fights short; this is the curve the budgets are tuned on.

| ship | jump 5 | jump 15 | jump 25 | jump 35 |
|---|---|---|---|---|
| Rustbucket | 75% | 67% | 8% | 8% |
| Courier | 83% | 75% | 42% | 17% |
| Prism | 75% | 50% | 17% | 8% |
| Rustbucket + kit | - | 50% | 42% | - |
| Courier + kit | - | 83% | 50% | - |
| Prism + kit | - | 83% | 50% | - |

## Before / after (before -> after)

Won, drawn and mean time over the ships without the kit; then each ship's win rate (one number: no earlier run had it).

| | jump 5 | jump 15 | jump 25 | jump 35 | all |
|---|---|---|---|---|---|
| won | 28% -> 56% | 3% -> 42% | 3% -> 11% | 0% -> 0% | 8% -> 27% |
| drawn | 69% -> 39% | 86% -> 56% | 83% -> 53% | 92% -> 69% | 83% -> 54% |
| mean time | 134 s -> 88 s | 169 s -> 124 s | 165 s -> 143 s | 175 s -> 162 s | 161 s -> 129 s |
| Rustbucket won | 33% -> 33% | 8% -> 25% | 0% -> 0% | 0% -> 0% | |
| Courier won | 33% -> 83% | 0% -> 67% | 8% -> 25% | 0% -> 0% | |
| Prism won | 17% -> 50% | 0% -> 33% | 0% -> 8% | 0% -> 0% | |
| Rustbucket + kit won | - | 25% | 0% | - | |
| Courier + kit won | - | 67% | 33% | - | |
| Prism + kit won | - | 75% | 25% | - | |

## By faction (all ships)

| faction | jump 5 | jump 15 | jump 25 | jump 35 |
|---|---|---|---|---|
| clans | 83% (5/0/1) 51s | 50% (6/0/6) 110s | 0% (0/0/12) 180s | 0% (0/1/5) 175s |
| concord | 17% (1/2/3) 105s | 33% (4/1/7) 114s | 17% (2/8/2) 78s | 0% (0/2/4) 142s |
| hollow | 67% (4/0/2) 104s | 50% (6/0/6) 123s | 25% (3/0/9) 152s | 0% (0/0/6) 180s |
| lumen | 83% (5/0/1) 77s | 50% (6/0/6) 118s | 42% (5/3/4) 146s | 0% (0/2/4) 171s |
| rustfangs | 50% (3/0/3) 56s | 33% (4/0/8) 126s | 0% (0/7/5) 141s | 0% (0/3/3) 159s |
| wardens | 33% (2/0/4) 135s | 75% (9/0/3) 121s | 8% (1/2/9) 172s | 0% (0/3/3) 143s |

## Every pairing: won-lost-drawn, mean skulls, mean hull left after a win

| ship | faction | jump 5 | jump 15 | jump 25 | jump 35 |
|---|---|---|---|---|---|
| Rustbucket | clans | 2-0-0, 1.5 sk, 96% hull | 1-0-1, 3.0 sk, 83% hull | 0-0-2, 3.0 sk, 0% hull | 0-0-2, 4.0 sk, 0% hull |
| Rustbucket | concord | 0-1-1, 1.0 sk, 0% hull | 0-0-2, 2.5 sk, 0% hull | 0-2-0, 3.5 sk, 0% hull | 0-0-2, 4.5 sk, 0% hull |
| Rustbucket | hollow | 0-0-2, 1.0 sk, 0% hull | 1-0-1, 1.5 sk, 93% hull | 0-0-2, 2.0 sk, 0% hull | 0-0-2, 3.0 sk, 0% hull |
| Rustbucket | lumen | 1-0-1, 1.0 sk, 94% hull | 0-0-2, 2.0 sk, 0% hull | 0-1-1, 3.5 sk, 0% hull | 0-0-2, 3.5 sk, 0% hull |
| Rustbucket | rustfangs | 1-0-1, 1.5 sk, 99% hull | 0-0-2, 3.0 sk, 0% hull | 0-1-1, 4.5 sk, 0% hull | 0-1-1, 5.0 sk, 0% hull |
| Rustbucket | wardens | 0-0-2, 1.0 sk, 0% hull | 1-0-1, 2.0 sk, 100% hull | 0-0-2, 3.0 sk, 0% hull | 0-1-1, 4.5 sk, 0% hull |
| Courier | clans | 2-0-0, 1.5 sk, 97% hull | 1-0-1, 3.0 sk, 88% hull | 0-0-2, 3.0 sk, 0% hull | 0-1-1, 4.0 sk, 0% hull |
| Courier | concord | 1-1-0, 1.0 sk, 83% hull | 1-1-0, 2.5 sk, 64% hull | 0-2-0, 3.5 sk, 0% hull | 0-2-0, 4.0 sk, 0% hull |
| Courier | hollow | 2-0-0, 1.0 sk, 95% hull | 1-0-1, 1.5 sk, 99% hull | 1-0-1, 2.0 sk, 100% hull | 0-0-2, 3.0 sk, 0% hull |
| Courier | lumen | 2-0-0, 1.0 sk, 90% hull | 2-0-0, 2.0 sk, 56% hull | 2-0-0, 3.5 sk, 17% hull | 0-1-1, 3.5 sk, 0% hull |
| Courier | rustfangs | 1-0-1, 1.5 sk, 98% hull | 1-0-1, 3.0 sk, 88% hull | 0-1-1, 4.5 sk, 0% hull | 0-1-1, 5.0 sk, 0% hull |
| Courier | wardens | 2-0-0, 1.0 sk, 87% hull | 2-0-0, 1.5 sk, 79% hull | 0-1-1, 3.0 sk, 0% hull | 0-2-0, 4.5 sk, 0% hull |
| Prism | clans | 1-0-1, 2.5 sk, 94% hull | 0-0-2, 3.5 sk, 0% hull | 0-0-2, 4.5 sk, 0% hull | 0-0-2, 5.0 sk, 0% hull |
| Prism | concord | 0-0-2, 2.0 sk, 0% hull | 0-0-2, 3.5 sk, 0% hull | 0-2-0, 4.5 sk, 0% hull | 0-0-2, 5.0 sk, 0% hull |
| Prism | hollow | 2-0-0, 1.0 sk, 97% hull | 1-0-1, 2.5 sk, 98% hull | 0-0-2, 3.0 sk, 0% hull | 0-0-2, 3.5 sk, 0% hull |
| Prism | lumen | 2-0-0, 2.0 sk, 92% hull | 1-0-1, 3.0 sk, 85% hull | 1-1-0, 4.5 sk, 64% hull | 0-1-1, 4.5 sk, 0% hull |
| Prism | rustfangs | 1-0-1, 2.5 sk, 86% hull | 1-0-1, 3.5 sk, 71% hull | 0-2-0, 5.0 sk, 0% hull | 0-1-1, 5.0 sk, 0% hull |
| Prism | wardens | 0-0-2, 1.5 sk, 0% hull | 1-0-1, 2.5 sk, 97% hull | 0-0-2, 4.0 sk, 0% hull | 0-0-2, 5.0 sk, 0% hull |
| Rustbucket + kit | clans | - | 0-0-2, 2.5 sk, 0% hull | 0-0-2, 3.0 sk, 0% hull | - |
| Rustbucket + kit | concord | - | 0-0-2, 2.5 sk, 0% hull | 0-1-1, 3.5 sk, 0% hull | - |
| Rustbucket + kit | hollow | - | 1-0-1, 1.0 sk, 90% hull | 0-0-2, 2.0 sk, 0% hull | - |
| Rustbucket + kit | lumen | - | 1-0-1, 2.0 sk, 100% hull | 0-0-2, 3.5 sk, 0% hull | - |
| Rustbucket + kit | rustfangs | - | 0-0-2, 3.0 sk, 0% hull | 0-0-2, 4.5 sk, 0% hull | - |
| Rustbucket + kit | wardens | - | 1-0-1, 1.5 sk, 99% hull | 0-0-2, 3.0 sk, 0% hull | - |
| Courier + kit | clans | - | 2-0-0, 2.5 sk, 91% hull | 0-0-2, 3.0 sk, 0% hull | - |
| Courier + kit | concord | - | 1-0-1, 2.5 sk, 51% hull | 1-1-0, 3.5 sk, 38% hull | - |
| Courier + kit | hollow | - | 1-0-1, 1.0 sk, 97% hull | 1-0-1, 2.0 sk, 99% hull | - |
| Courier + kit | lumen | - | 1-0-1, 2.0 sk, 90% hull | 2-0-0, 3.5 sk, 32% hull | - |
| Courier + kit | rustfangs | - | 1-0-1, 2.5 sk, 94% hull | 0-2-0, 4.5 sk, 0% hull | - |
| Courier + kit | wardens | - | 2-0-0, 1.5 sk, 86% hull | 0-1-1, 3.0 sk, 0% hull | - |
| Prism + kit | clans | - | 2-0-0, 3.0 sk, 84% hull | 0-0-2, 4.0 sk, 0% hull | - |
| Prism + kit | concord | - | 2-0-0, 3.0 sk, 82% hull | 1-0-1, 3.5 sk, 41% hull | - |
| Prism + kit | hollow | - | 1-0-1, 1.5 sk, 99% hull | 1-0-1, 2.5 sk, 98% hull | - |
| Prism + kit | lumen | - | 1-0-1, 2.5 sk, 78% hull | 0-1-1, 4.5 sk, 0% hull | - |
| Prism + kit | rustfangs | - | 1-0-1, 3.0 sk, 88% hull | 0-1-1, 5.0 sk, 0% hull | - |
| Prism + kit | wardens | - | 2-0-0, 2.5 sk, 99% hull | 1-0-1, 3.0 sk, 66% hull | - |

## Threat rating against the result

The rating the radar shows (threat.gd, cuts [0.5, 0.85, 1.6, 2.6]) for each fight, against how the fight went. Target: 1 skull a sure win, 3 even, 5 a likely loss.

| skulls | fights | won | lost | drawn | mean power ratio |
|---|---|---|---|---|---|
| 1 | 41 | 61% | 5% | 34% | 0.36 |
| 2 | 33 | 55% | 0% | 45% | 0.69 |
| 3 | 75 | 25% | 9% | 65% | 1.15 |
| 4 | 39 | 10% | 28% | 62% | 2.04 |
| 5 | 28 | 0% | 50% | 50% | 3.51 |

Cuts these fights suggest: [0.82, 0.83, 1.69, 2.15] (a falling fit of the result, won 1, lost 0, a draw 1 or 0 by its projection, against the power ratio, cut where it crosses [0.85, 0.65, 0.35, 0.15]).

## How fights end

| jump | wreck | capture | surrender | escape | lost | draw | mean time | enemy hull left |
|---|---|---|---|---|---|---|---|---|
| 5 | 7 | 5 | 8 | 3 | 2 | 11 | 88 s | 50% |
| 15 | 14 | 17 | 4 | 9 | 1 | 27 | 119 s | 55% |
| 25 | 4 | 4 | 3 | 1 | 20 | 40 | 145 s | 78% |
| 35 | 0 | 0 | 0 | 0 | 11 | 25 | 162 s | 95% |

## What the guns did (means per fight)

Shots fired; damage to the hull pool (walls, doors) and to parts; shield layers spent; the share of the time the player had a working gun, and had the pilot's target within a gun's range; the mean hull-to-hull gap (along the line between the centres, PilotAI.extent(); the before run measured it between the bounding circles); when the player's last gun was shot out (disabled or cut off, not jammed).

| ship | jump | shots (you/foe) | hull dmg (you/foe) | part dmg (you/foe) | shields hit (you/foe) | armed | in range | gap px | guns out at |
|---|---|---|---|---|---|---|---|---|---|
| Rustbucket | 5 | 28 / 125 | 6 / 50 | 31 / 99 | 2 / 0 | 31% | 14% | 472 | 5 of 12 fights, ~47 s |
| Rustbucket | 15 | 41 / 113 | 19 / 33 | 39 / 145 | 20 / 0 | 46% | 35% | 397 | 4 of 12 fights, ~46 s |
| Rustbucket | 25 | 24 / 172 | 10 / 138 | 18 / 90 | 31 / 0 | 23% | 23% | 272 | 8 of 12 fights, ~43 s |
| Rustbucket | 35 | 20 / 166 | 7 / 139 | 10 / 80 | 35 / 0 | 17% | 17% | 275 | 9 of 12 fights, ~44 s |
| Courier | 5 | 21 / 35 | 19 / 26 | 14 / 10 | 1 / 0 | 74% | 38% | 530 | 1 of 12 fights, ~19 s |
| Courier | 15 | 55 / 56 | 44 / 55 | 15 / 30 | 17 / 0 | 80% | 74% | 478 | 5 of 12 fights, ~70 s |
| Courier | 25 | 64 / 120 | 26 / 99 | 25 / 54 | 36 / 0 | 66% | 62% | 411 | 7 of 12 fights, ~46 s |
| Courier | 35 | 51 / 143 | 22 / 122 | 14 / 48 | 30 / 0 | 50% | 49% | 401 | 9 of 12 fights, ~60 s |
| Prism | 5 | 8 / 60 | 23 / 28 | 7 / 15 | 1 / 0 | 48% | 46% | 512 | 3 of 12 fights, ~29 s |
| Prism | 15 | 12 / 75 | 26 / 51 | 8 / 38 | 13 / 0 | 51% | 48% | 463 | 6 of 12 fights, ~32 s |
| Prism | 25 | 11 / 137 | 18 / 88 | 5 / 45 | 33 / 0 | 41% | 41% | 285 | 10 of 12 fights, ~47 s |
| Prism | 35 | 13 / 137 | 13 / 70 | 5 / 34 | 56 / 0 | 38% | 38% | 284 | 9 of 12 fights, ~63 s |
| Rustbucket + kit | 15 | 82 / 97 | 28 / 33 | 56 / 66 | 37 / 41 | 100% | 65% | 366 | never |
| Rustbucket + kit | 25 | 75 / 174 | 24 / 76 | 33 / 101 | 85 / 55 | 89% | 88% | 164 | 1 of 12 fights, ~157 s |
| Courier + kit | 15 | 81 / 53 | 60 / 33 | 27 / 28 | 23 / 25 | 96% | 88% | 389 | 1 of 12 fights, ~76 s |
| Courier + kit | 25 | 81 / 125 | 34 / 99 | 23 / 54 | 47 / 28 | 92% | 89% | 299 | 6 of 12 fights, ~42 s |
| Prism + kit | 15 | 39 / 62 | 43 / 23 | 12 / 17 | 27 / 56 | 97% | 95% | 394 | 1 of 12 fights, ~154 s |
| Prism + kit | 25 | 40 / 182 | 32 / 67 | 11 / 48 | 51 / 107 | 88% | 83% | 264 | 5 of 12 fights, ~84 s |

## Reading

- Draws are 54% of all fights (many: fights are long, the cap cuts them short); 49% of all fights are won or were being won at the cap.
- Jump 5, the starters bare: projected 78% (won 56%), target 70-90%: on target.
- Jump 15, the starters with the kit: projected 72% (won 56%), target 45-65%: OFF TARGET.
-   Courier + kit at jump 15: projected 83%, well outside it.
-   Prism + kit at jump 15: projected 83%, well outside it.
- Jump 35, the starters bare: projected 11% (won 0%), target 0-30%: on target.

## The balance pass of 2026-10-31: what was wrong, what changed

Before: the first version of this file (commit 52ec6b6; its numbers are `docs/balance_before.json`, the `compare=` baseline). That run had 144 fights, 83% drawn, 8% won and 9% lost. After: the tables above (`claude/balance`).

**What made fights not happen or not end** (found with this harness and single-fight probes):
1. **Standoff.** The pilot kept both bounding circles plus 40 px apart. A starter's pivot is the centre of its big, mostly empty frame (radius 420-485 px); a large enemy's is 580-830 px. Either the guns were out of range, or the hulls clipped. The before gap column above is between the bounding circles (35-55 px).
2. **Guns that never fired.** A row of fixed bow guns (5° gimbals) cannot all point at one part, and the pilot fired only a gun whose cone held its aim point. A large Concord ship fired 1 of its 7 guns. Its flank turrets were out of reach at the distance it held.
3. **Target choice.** The order was weapons, then engines, then the reactor. Every shot went into parts, which the crew repair, and hits on parts take nothing off the hull pool. The enemy's hull never moved (93-99% left at jumps 15-35). The player's pilot then parked its aim on stern engines out of range and stopped firing.
4. **The starter's single bow gun** had a 4 hp outside half. The first rattle volley or the second laser hit disabled it in 2-4 s, in 9 of 12 fights. A breach in its wall could not be sealed (no stand spot): the lead fixed that on main.
5. **The Heat Lance** overheated at its own fire rate with no radiator in its room. The Prism's gun was up about 15% of a fight.
6. **The curve.** A jump 5 enemy (budget 48) carried two guns and armour against the starter's one gun.

**Fixes** (each has a test):
- **Pilot range.** It keeps a gap of 70% of each gun's range between the hulls, measured from each hull's extent along the line between the centres (the mechanics director's call), with each gun's place counted. The gap is at least 96 px. Tests: `test_pilot_ai`: `test_the_hold_distance_counts_each_hull_and_each_gun`, `test_a_starter_reaches_a_large_enemy_and_hits_it`.
- **Pilot fire.** A fixed gun that cannot bear on its aim point fires when its barrel, at the gimbal's edge, lines up on the foe's hull within range. Tests: `test_a_large_enemy_brings_its_guns_to_bear`, `test_a_shot_lines_up_on_the_hull_or_not`.
- **Pilot aim.** Only a pilot of aim 0.8 or better aims at the foe's weapons first. Everyone else, and the sniper once the guns are out, aims at an outside wall on the facing side, nearest its line to the foe's centre and clear of the guns' outside halves. A fleeing foe's engines come first (they hold its jump drive). Test: `test_who_aims_at_what`.
- **Weapons.** A weapon's outside_hp is twice its hp, so the barrel survives a volley; engines and intakes stay at 75%. This covers all 44 weapons, the saved out_hp of every ship design, and the rule in `test_mounts` and `test_tech_b`.
- **Heat Lance cooling** 3 -> 6. It still overheats after about 80 s when manned, and a radiator still cures it.
- **Budgets.** `tier_base` 40/80/140 -> 20/44/100. `per_jump` stays 0.04, as in CONTENT 14. Threat cuts 0.55/0.95/1.5/2.4 -> 0.5/0.85/1.6/2.6. Test: `test_balance`: `test_the_threat_cuts_are_the_measured_ones`, `test_starter_fights_at_jump_5_now_end`.

**Threat rating.** The cuts sit where the measured result (won 1, lost 0, a draw by its projection) crosses 85%, 65%, 35% and 15%, pooled over the last two runs: power ratio under 0.5 for 1 skull, 0.5-0.85 for 2, 0.85-1.6 for 3, 1.6-2.6 for 4, and over 2.6 for 5. In the table above, 1-2 skulls are won 55-61% and lost 0-5%, with the rest drawn and mostly ahead. 5 skulls are won 0% and lost 50%.

**The soak** (`tests/test_soak.gd`):
- default: 33 fights, 11 won / 1 lost / 21 drawn -> 35 fights, 20 / 4 / 11;
- `SOAK_FULL=1`, every fight in the arena: 31 fights, 1 / 3 / 27 -> 31 fights, 3 / 6 / 22.

On main, the full soak failed one check ("a won fight led to the salvage") because it had too few wins; it passes now. In the soak the player's ship has no crew spawned, so nothing repairs its gun, and its pilot is the soak's own (aim 0.6, no engine targeting).

**Open for the lead and the owner:**
- **Fights are long.** Tier 1 guns deal about 1-1.5 damage a second against hull pools of 130-250, so a fight takes 90-150 s, and half the harness fights reach the 180 s cap. The budgets are tuned on the projected win rate. Shorter fights would need a design call: the hull pool (`arena.gd` HULL_PER_ARMOR), the morale break (`data/morale.json` break_hull), or gun damage.
- **Jump 15 with the kit** is projected at 72% (won 56%), a little easier than the 50-60% target, because the Courier and the Prism do well. `tier_base` 2 at 50 would bring it down.
- **The Rustbucket** wins least. Its Rattle Burst jams 12% a volley, it is slow, and the turret's random hit point often lands on the enemy's guns. **The Prism** is the weakest by threat rating (0.75 damage a second). Both are starters' parts, so they were left alone.
- **The Concord at tier 3** won most fights at jump 25: 2 won, 8 lost and 2 drawn over all six ships. That is its "shield wall" counter: ion, missiles or beams.
- **Large ships' flank turrets** reach a small foe only at the 96 px gap, so a large ship fights close. Moving shipgen's turrets forward, or a pilot that turns broadside, would change that.
- **Intent** (`intent.gd`) shows no reticle for a pilot that aims at the hull (`target_uid` -1). Most pilots now do. The room under `hull_aim` could be shown instead.
- **All 30 hangar ships.** `ships=all` fights every one (packs included). It is not in this report because of run time (about 15 minutes per seed for one jump).
- **Run time.** The defaults (1 seed, the kit at jump 15, 3 processes) give 90 fights in about 8-10 minutes on this busy 4-core machine. This report used 2 seeds.
