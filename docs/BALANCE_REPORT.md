# Balance report

Written by `tests/tool_balance.gd` (run: before) (docs/CONTENT.md 14). 144 fights: 3 ships x 6 factions x jumps [5, 15, 25, 35] x 2 seeds, capped at 180 s, run in 1263 s.
Both ships are flown by the pilot AI (the player's at aim 0.75, thinking every 3 ticks); crews run in ShipSim; morale can end a fight (the player takes every surrender). A cell is `win% (won/lost/drawn) mean seconds`; a draw is the cap or an enemy that escaped. Budgets: Shipgen.budget_for(tier, jump, danger of the faction's first region): clans 1.00, concord 1.05, hollow 1.40, lumen 1.00, rustfangs 1.00, wardens 1.20.

**All fights**: won 8%, lost 9%, drawn 83%, mean 161 s.

## Win rate by ship and jump

| ship | jump 5 (budget ~48) | jump 15 (budget ~128) | jump 25 (budget ~280) | jump 35 (budget ~336) |
|---|---|---|---|---|
| Rustbucket | 33% (4/0/8) 132s | 8% (1/0/11) 170s | 0% (0/0/12) 176s | 0% (0/0/12) 180s |
| Courier | 33% (4/1/7) 111s | 0% (0/4/8) 156s | 8% (1/5/6) 142s | 0% (0/3/9) 165s |
| Prism | 17% (2/0/10) 160s | 0% (0/0/12) 180s | 0% (0/0/12) 176s | 0% (0/0/12) 180s |
| **all** | 28% (10/1/25) 134s | 3% (1/4/31) 169s | 3% (1/5/30) 165s | 0% (0/3/33) 175s |

## By faction (all ships)

| faction | jump 5 | jump 15 | jump 25 | jump 35 |
|---|---|---|---|---|
| clans | 33% (2/0/4) 114s | 0% (0/0/6) 180s | 0% (0/1/5) 171s | 0% (0/1/5) 172s |
| concord | 0% (0/1/5) 162s | 0% (0/1/5) 171s | 0% (0/2/4) 145s | 0% (0/1/5) 167s |
| hollow | 17% (1/0/5) 159s | 17% (1/0/5) 160s | 0% (0/0/6) 180s | 0% (0/0/6) 180s |
| lumen | 83% (5/0/1) 75s | 0% (0/2/4) 150s | 17% (1/0/5) 152s | 0% (0/0/6) 180s |
| rustfangs | 0% (0/0/6) 156s | 0% (0/1/5) 172s | 0% (0/1/5) 173s | 0% (0/0/6) 180s |
| wardens | 33% (2/0/4) 140s | 0% (0/0/6) 180s | 0% (0/1/5) 167s | 0% (0/1/5) 171s |

## Every pairing: won-lost-drawn, mean skulls, mean hull left after a win

| ship | faction | jump 5 | jump 15 | jump 25 | jump 35 |
|---|---|---|---|---|---|
| Rustbucket | clans | 1-0-1, 2.5 sk, 65% hull | 0-0-2, 3.5 sk, 0% hull | 0-0-2, 4.5 sk, 0% hull | 0-0-2, 5.0 sk, 0% hull |
| Rustbucket | concord | 0-0-2, 2.5 sk, 0% hull | 0-0-2, 2.5 sk, 0% hull | 0-0-2, 4.0 sk, 0% hull | 0-0-2, 5.0 sk, 0% hull |
| Rustbucket | hollow | 1-0-1, 1.0 sk, 96% hull | 1-0-1, 1.5 sk, 98% hull | 0-0-2, 3.5 sk, 0% hull | 0-0-2, 4.0 sk, 0% hull |
| Rustbucket | lumen | 1-0-1, 1.0 sk, 99% hull | 0-0-2, 3.0 sk, 0% hull | 0-0-2, 4.5 sk, 0% hull | 0-0-2, 4.5 sk, 0% hull |
| Rustbucket | rustfangs | 0-0-2, 3.0 sk, 0% hull | 0-0-2, 4.5 sk, 0% hull | 0-0-2, 5.0 sk, 0% hull | 0-0-2, 5.0 sk, 0% hull |
| Rustbucket | wardens | 1-0-1, 1.5 sk, 100% hull | 0-0-2, 1.5 sk, 0% hull | 0-0-2, 4.0 sk, 0% hull | 0-0-2, 5.0 sk, 0% hull |
| Courier | clans | 1-0-1, 2.0 sk, 100% hull | 0-0-2, 3.5 sk, 0% hull | 0-1-1, 4.0 sk, 0% hull | 0-1-1, 5.0 sk, 0% hull |
| Courier | concord | 0-1-1, 2.5 sk, 0% hull | 0-1-1, 2.5 sk, 0% hull | 0-2-0, 3.5 sk, 0% hull | 0-1-1, 5.0 sk, 0% hull |
| Courier | hollow | 0-0-2, 1.0 sk, 0% hull | 0-0-2, 1.5 sk, 0% hull | 0-0-2, 3.5 sk, 0% hull | 0-0-2, 4.0 sk, 0% hull |
| Courier | lumen | 2-0-0, 1.0 sk, 99% hull | 0-2-0, 3.0 sk, 0% hull | 1-0-1, 4.5 sk, 100% hull | 0-0-2, 4.0 sk, 0% hull |
| Courier | rustfangs | 0-0-2, 3.0 sk, 0% hull | 0-1-1, 4.5 sk, 0% hull | 0-1-1, 5.0 sk, 0% hull | 0-0-2, 5.0 sk, 0% hull |
| Courier | wardens | 1-0-1, 1.5 sk, 100% hull | 0-0-2, 1.5 sk, 0% hull | 0-1-1, 3.5 sk, 0% hull | 0-1-1, 5.0 sk, 0% hull |
| Prism | clans | 0-0-2, 3.5 sk, 0% hull | 0-0-2, 4.5 sk, 0% hull | 0-0-2, 5.0 sk, 0% hull | 0-0-2, 5.0 sk, 0% hull |
| Prism | concord | 0-0-2, 3.5 sk, 0% hull | 0-0-2, 4.0 sk, 0% hull | 0-0-2, 4.5 sk, 0% hull | 0-0-2, 5.0 sk, 0% hull |
| Prism | hollow | 0-0-2, 1.5 sk, 0% hull | 0-0-2, 2.0 sk, 0% hull | 0-0-2, 4.5 sk, 0% hull | 0-0-2, 5.0 sk, 0% hull |
| Prism | lumen | 2-0-0, 2.0 sk, 100% hull | 0-0-2, 4.5 sk, 0% hull | 0-0-2, 5.0 sk, 0% hull | 0-0-2, 5.0 sk, 0% hull |
| Prism | rustfangs | 0-0-2, 4.0 sk, 0% hull | 0-0-2, 5.0 sk, 0% hull | 0-0-2, 5.0 sk, 0% hull | 0-0-2, 5.0 sk, 0% hull |
| Prism | wardens | 0-0-2, 2.0 sk, 0% hull | 0-0-2, 2.5 sk, 0% hull | 0-0-2, 4.5 sk, 0% hull | 0-0-2, 5.0 sk, 0% hull |

## Threat rating against the result

The rating the radar shows (threat.gd, cuts [0.55, 0.95, 1.5, 2.4]) for each fight, against how the fight went. Target: 1 skull a sure win, 3 even, 5 a likely loss.

| skulls | fights | won | lost | drawn | mean power ratio |
|---|---|---|---|---|---|
| 1 | 17 | 41% | 0% | 59% | 0.39 |
| 2 | 20 | 15% | 5% | 80% | 0.80 |
| 3 | 21 | 5% | 14% | 81% | 1.19 |
| 4 | 32 | 0% | 9% | 91% | 1.94 |
| 5 | 54 | 2% | 11% | 87% | 3.78 |

## How fights end

| jump | wreck | capture | surrender | escape | lost | draw | mean time | enemy hull left |
|---|---|---|---|---|---|---|---|---|
| 5 | 1 | 5 | 4 | 2 | 1 | 23 | 134 s | 81% |
| 15 | 1 | 0 | 0 | 0 | 4 | 31 | 169 s | 93% |
| 25 | 0 | 0 | 1 | 2 | 5 | 28 | 165 s | 97% |
| 35 | 0 | 0 | 0 | 0 | 3 | 33 | 175 s | 99% |

## What the guns did (means per fight)

Shots fired; damage to the hull pool (walls, doors) and to parts; shield layers spent; the share of the time the player had a working gun, and had the pilot's target within a gun's range; the mean hull-to-hull gap (centres less both bounding radii); when the player's last gun was shot out (disabled or cut off, not jammed).

| ship | jump | shots (you/foe) | hull dmg (you/foe) | part dmg (you/foe) | shields hit (you/foe) | armed | in range | gap px | guns out at |
|---|---|---|---|---|---|---|---|---|---|
| Rustbucket | 5 | 22 / 80 | 22 / 54 | 17 / 51 | 5 / 0 | 27% | 23% | 45 | 9 of 12 fights, ~2 s |
| Rustbucket | 15 | 46 / 59 | 19 / 31 | 19 / 36 | 83 / 0 | 44% | 43% | 38 | 8 of 12 fights, ~21 s |
| Rustbucket | 25 | 40 / 102 | 6 / 63 | 7 / 51 | 103 / 0 | 37% | 36% | 53 | 7 of 12 fights, ~5 s |
| Rustbucket | 35 | 54 / 86 | 7 / 23 | 11 / 34 | 136 / 0 | 48% | 48% | 38 | 6 of 12 fights, ~8 s |
| Courier | 5 | 46 / 55 | 15 / 43 | 45 / 23 | 13 / 0 | 59% | 57% | 39 | 7 of 12 fights, ~3 s |
| Courier | 15 | 39 / 98 | 0 / 88 | 31 / 38 | 24 / 0 | 41% | 34% | 36 | 9 of 12 fights, ~1 s |
| Courier | 25 | 44 / 102 | 0 / 89 | 8 / 31 | 39 / 0 | 46% | 46% | 35 | 8 of 12 fights, ~2 s |
| Courier | 35 | 48 / 115 | 0 / 52 | 13 / 40 | 40 / 0 | 51% | 51% | 36 | 9 of 12 fights, ~4 s |
| Prism | 5 | 8 / 91 | 2 / 59 | 25 / 26 | 1 / 0 | 18% | 17% | 41 | 9 of 12 fights, ~4 s |
| Prism | 15 | 7 / 85 | 0 / 42 | 18 / 20 | 12 / 0 | 21% | 17% | 39 | 10 of 12 fights, ~9 s |
| Prism | 25 | 10 / 101 | 2 / 46 | 6 / 23 | 36 / 0 | 22% | 22% | 52 | 7 of 12 fights, ~2 s |
| Prism | 35 | 14 / 102 | 0 / 17 | 13 / 14 | 46 / 0 | 37% | 37% | 38 | 7 of 12 fights, ~12 s |

## Reading

- Draws are 83% of all fights (too many: fights that do not end).
- Rustbucket at jump 5 wins 33%, outside the target 70-90%.
- Courier at jump 5 wins 33%, outside the target 70-90%.
- Prism at jump 5 wins 17%, outside the target 70-90%.
- Rustbucket at jump 15 wins 8%, outside the target 45-65%.
- Courier at jump 15 wins 0%, outside the target 45-65%.
- Prism at jump 15 wins 0%, outside the target 45-65%.
- Rustbucket at jump 25 wins 0%, outside the target 20-50%.
- Courier at jump 25 wins 8%, outside the target 20-50%.
- Prism at jump 25 wins 0%, outside the target 20-50%.
