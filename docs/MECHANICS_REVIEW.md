# Mechanics review (the mechanics director, Beta 2 window, round 1)

> The owner's brief: "guide the game's mechanics forward. No unnecessary additions, but cleverly thought-out ones, so the challenge is worth the time and fun to play."

This doc is the director's working notes: what the reference games get right, where our loop is weak (measured, not guessed), and a short list of mechanics. Each one solves a named problem, plays in a concrete way, and has a test that tells us it works. It is updated every round.

**How the findings were measured**: the full test suite on `main` (949 passed), the soak test (3 starters × 3 seeds × 25 jumps: 30 fights, 15 won, 2 lost, 13 drawn), a throwaway probe of 30 AI-vs-AI fights (each starter against the Pirate Raider and the Rustfang Rammer, up to 240 s, with crews aboard, counting what is left of the loser), and reading the campaign, combat, crew and economy code and data.

## 1. What makes the reference games work

| Game | The loop's engine | The lesson for us |
|---|---|---|
| **FTL** | One clock (the rebel fleet) turns every extra beacon into a gamble. One currency (scrap) buys fuel, repairs, weapons and upgrades, so every purchase competes. A fight ends four ways: **destroy** the ship, **kill the crew** (better loot), accept a **surrender** (a sure offer, usually less), or **they escape** (they charge their FTL drive and you must hit engines or the pilot). Crew die, and skilled crew are precious. | Pressure must come from **one clock**, not many. A fight needs more than one ending, so **what you shoot at** matters. |
| **FTL Multiverse** | The same small rule set, 10× the content: races whose traits cancel their own tech's cons, rare factions, quest chains. | The vocabulary must stay small and expressive (our CONTENT_PLAN rule already). |
| **Slay the Spire** | A branching map with node types you can see. **Pick 1 of 3** card rewards, where skipping is a real choice. Elites are optional hard fights with relics. Each act's boss is known in advance, so you build toward it. | "Pick 1 of 3" is the cheapest deep decision in games. Telegraph the big threat early. |
| **Into the Breach** | Perfect information: every enemy shows what it will hit next turn. Hard, but every loss is your mistake. | Telegraph danger, and hard becomes fair. |
| **Cosmoteer** | The ship's design *is* the strategy. Parts get shot off, crew walk to haul ammo, and precise hits on key parts win. | Combat damage should feed back into the build, and precision should pay. |
| **Space Haven** | Autonomous crew with priorities; crises cascade (O2, fire, hull). | Cascades need a lasting cost or they're just noise. |
| **Raft** | A steady trickle of resources on the current, multiplied by where you place your nets. **The shark** and hunger stop you idling. | An idle income loop needs a predator. |
| **Barotrauma** | A physical sub: flooding compartments, crew who drown, the "seal the hatch with your friend inside" moment. | Compartments are only dramatic if people can die in them. |
| **Subnautica** | Depth is progression; oxygen is the leash; scanning fragments of wrecks gives blueprints. | Scanning a wreck for a blueprint makes every wreck pay forward. |

## 2. Where our loop is weak

**F1. Time in space costs nothing (the idle-farming hole).** The debt clock and the danger tier count *jumps*, not time. Intake income counts *minutes*. One Net Mouth brings ~25 scrap a minute, and a Mk1 part costs 20–30 scrap. The average event pays about **11 scrap and 4 credits (wreck fields), 5 scrap and 11 credits (distress), 19 scrap (asteroid fields)**, taking each choice equally often. So **one idle minute is worth about one event**, with no risk. The best strategy is to sit at a safe node and wait. Sector space (the Raft loop, this window) makes it the dominant strategy. Raft has the shark, Subnautica oxygen, FTL the fleet. We have nothing yet.

**F2. Nothing pushes you through a region after stage 2.** The regions brief pauses Ma's debt from stage 3. A region has 16–20 places and a run has 8 regions. With no clock, the right play is to visit every place (~150 jumps), which kills node choice and stretches a 4–8 h run far past its target. FTL's fleet exists precisely for this.

**F3. A fight has one ending, and crew state doesn't matter to the enemy.** You shoot the hull pool to 0. Enemies never flee and never surrender. In the probe, **an enemy with all 3 crew down kept flying and firing at full effect**. Rammer fights ran past 240 s with the enemy crew all down (both Rustbucket and Courier, hull 83/192 and 18/192). So fights drag, and nothing about *how* you fight changes the result.

**F4. Loot ignores how you won.** A win pays credits and scrap × tier, plus a 25% roll for one random enemy part. In the probe, every hull-pool kill left **7–9 of the enemy's 9 parts intact**, yet you get at most one at random. The game's own name, cutting apart what you beat, isn't in the loop. Blueprints only come from events (the crafting panel's `U` key says "debug, until salvage gives real ones").

**F5. Crew can't die in the ship game.** At 0 hp a crew member is *down* until revived; only events remove crew. Fire, vacuum and breaches never cost anything lasting, so the Barotrauma/FTL decision "vent the room with Rook inside?" has no stakes. That weakens pillars 1 (compartments) and 4 (crew are people), and the 64 planned unique characters can never be lost.

**F6. The hull pool rewards cheap plating (for the balance harness, not a new mechanic).** Hull integrity is 20 + 2 per *non-steel* wall cell, so scrap plate (3 hp, dirt cheap) adds hull and steel adds none: Rustbucket 226, Courier 76, Prism 48. In the probe, the AI-flown Courier and Prism lost or drew all 6 fights against the basic pirate; the Rustbucket won all 3. Handed to tracks 2 (balance harness) and P0 (starters).

**F7. Titanium from scrap (data, for the lead).** The `titanium` recipe makes 1 titanium from 5 scrap at fab level 2, which bypasses the regional scarcity of CONTENT 11 (titanium floats only in Concord space). Suggest 20 scrap, or removing the recipe once processing (CONTENT 12) lands.

**F8. Build mode during a fight (a rule, for the lead).** P0 makes build mode pause the world, and sector step 2 moves fights into play mode. Then B mid-fight pauses the fight and lets you rebuild breached walls instantly. Rule: **build mode refuses while a hostile is within 2,500 px** ("Red alert: hostiles near"), the same range at which sector flight drops cruise speed. Handed to the build UI and sector view owners.

**F9. Fights aren't telegraphed.** You can't see which of your systems the enemy is aiming at, so shield balance is a guess rather than a decision (Into the Breach's lesson). Round 2.

**F10. No long horizon.** Nothing tells you what you'll have to beat at the end of a region, so you can't plan a build around it (Slay the Spire's known bosses). Round 2, once regions and shipgen land.

## 3. Proposals

### P1. The Hollow Tide (one clock, three problems) — **round 1, build**
- **Problem**: F1 (idle farming), F2 (full-clearing every region), and the run length.
- **How it plays**: each region map has a **front** that sweeps from the entry toward the exit. Every jump moves it one step (also waiting for a trader, and the tow). Places behind the front go **Hollow**: dead beacons, ghost ships, no rewards. **Stations and the exit beacon hold** (their services stay open), but the lanes to them don't. Lingering also counts: **every 4 minutes of play in one place moves the tide a step** (with warnings at 1:00 and 0:15; build mode and fights don't count).
  - *Example*: stage 3, the Kett Hives. The map shows the tide two lanes behind you. A distress beacon is one jump off your path, and the tide reaches it in 2 jumps. Go for it and you'll be fleeing Hollow nodes on the way back to the exit; skip it and you reach the exit with fuel and hull to spare. Sitting in a rich wreck field farming debris? The HUD says "Tide rises in 0:58".
- **Lore**: the Hollow is already the late-game pressure (CONTENT 13, act 3). This generalises it: the tide follows you everywhere, faster in later stages. It changes one design decision (the act-3-only tide), proposed here, not silently.
- **Cost**: medium. A new `tide.gd` (pure logic), small hooks in `campaign.gd` (advance, arrive, save) and `map_view.gd` (draw, linger), `data/tide.json`, 6 Hollow events in a pack.
- **Bloat risk**: low. It replaces the need for any other "hurry up" rule.
- **We'll know it works when**: in the soak, runs reach the far side in 15–25 jumps rather than wandering; the idle test (sit 20 minutes) costs 5 tide steps; playtesters talk about "one more beacon?" decisions.

### P2. Three ways to win, one way to lose it (enemy morale) — **round 1, build**
- **Problem**: F3 (fights have one ending; enemy crew don't matter; stalemates).
- **How it plays**: when an enemy breaks (hull ≤ 35%, or no working weapon), it rolls from its faction's morale (data):
  - **Surrender**: it stops firing and hails. "Enough! Take it and let us go." The offer shows in a banner: credits, fuel or missiles, sometimes a part. **Y** accepts within 12 s; hitting them means no.
  - **Flee**: it turns away, burns, and **spools its jump drive (15 s)**, shown as a red bar on its schematic. The spool stops while its engines are all disabled or its helm is unmanned. If it finishes, they're gone, with their loot.
  - **Captured**: if every enemy crew member is down at once for 3 s, the ship goes dark: you win and its hull is whole (better salvage, P3).
  - *Example*: the pirate drops to 30% and starts spooling. You have 15 s: swing round and put the Bolt Thrower into its engine block, or ion its helm room. Or ignore it and take the surrender offer next fight. A Heat Lance build sets fires to drop the crew and capture ships whole; a Shrapnel build shreds hulls fast but can't stop a runner.
- **Symmetry (round 2)**: the player's own J spool should follow the same rule, holding while all your engines are out or your helm is unmanned (FTL needs engines and a pilot to jump). Then protecting your engine room matters when you want to run.
- **Cost**: medium. A new `morale.gd`, small hooks in `pilot_ai.gd` (flee, hold fire), `combat_session.gd` (end states) and `combat_view.gd` (banner, Y, spool bar), `data/morale.json`.
- **Bloat risk**: low. It's three outcomes of one roll, all data-driven by faction.
- **We'll know it works when**: AI-vs-AI fights stop stalemating (draws in the soak drop well below 13/30); in the probe, part hits on engines and helm rise; playtesters aim at engines on purpose.

### P3. Cut it apart: salvage what survives — **round 1, build**
- **Problem**: F4 (loot ignores how you won; no blueprint source).
- **How it plays**: after a win, the wreck opens a **salvage choice** (shown in the event panel, no new UI): **pick one of up to 3 of its surviving parts**, or **scan one for its blueprint**, or **strip her for scrap**. Parts you wrecked in the fight aren't on the list. A **captured** ship offers 4 parts *and* the scrap. A **spared** ship pays its offer; an **escaped** one pays nothing.
  - *Example*: you beat a raider. "Cut out the Shrapnel Cannon" (a part now), "Scan the Ion Blast Mk1" (craft it forever, if you have the materials and fab level), or "Strip her for 64 scrap". You wrecked its reactor with that lucky shot, so the reactor isn't on the list.
- **Cost**: small. A new `salvage.gd` that builds an event dict from the enemy ship; `campaign.fight_done` and `loot` change; one hook in `map_view.gd`. The sector view can call the same function when you approach the wreck POI.
- **Bloat risk**: none. It replaces the flat 25% roll and the random wreck-field event after fights.
- **We'll know it works when**: blueprint counts at jump 15 rise from ~0 to 3–6 in the soak; players can say why they took a part.

### P4. Bleed out — **round 1, build (with P3)**
- **Problem**: F5 (crew can't die in the ship game).
- **How it plays**: a downed crew member **dies after 45 s** unless a crewmate is reviving them or a powered medbay is healing them (the timer pauses). Your soldier never dies. Enemy crew follow the same rule, which feeds P2's capture.
  - *Example*: Rook is down in the burning engine room. Juno can run in through the fire to revive him (10 hp a second of fire on her), or you vent the room to kill the fire and lose Rook. A red ring over Rook counts down.
- **Cost**: small. A new `mortality.gd`, one line in `ship_sim.gd`, one field on `CrewMember`, a ring in `crew_view.gd`, `bleed_out_s` in `data/crew.json`.
- **Bloat risk**: none (a rule, not content).
- **We'll know it works when**: medbays, doors and fire crews become things players build for; deaths happen in maybe 1 run in 3, never as a surprise (the ring warns).

### P5. Red alert — **a rule, handed to the lead** (F8)
Build mode refuses while a hostile ship is within 2,500 px. One check, so it lives with the build UI and sector view tracks.

### P6. Enemy intent on your schematic — round 2
- **Problem**: F9. **How**: your schematic (top left) marks the room the enemy pilot is aiming at with a red reticle, and a heavy weapon charging (a missile, a lance) shows its target 1.5 s before it fires. Then shield balance and turning to put armour toward it become informed decisions. **Cost**: small (the pilot AI already has `target_uid`). **Bloat**: none. **Works when**: players move the shield balance *before* hits, not after.

### P7. Exit wardens (known region bosses) — round 2, after regions and shipgen
- **Problem**: F10. **How**: the region-choice card names what guards the exit beacon ("Concord Bulwark: 4-sector shields; bring ion or missiles"). Beat it, or pay a toll, to leave the region. You build toward it all region. **Cost**: medium. **Bloat**: low (one fight per region, from shipgen). **Works when**: players buy or craft counters before the exit.

### P8. Sector hazards (FTL's environments) — round 2, briefed
- **Problem**: every fight happens in the same empty space, so sectors differ only by POIs. The regions already name hazards (`debris_surge`, `star_heat`, `radiation`, `ion_storm`, `gas_cloud`), but none does anything.
- **How it plays**: some places in a region roll one of its hazards, shown on the map. Each changes *how* you fight, not just how hard:
  - **ion storm**: shields recharge at half speed;
  - **star heat**: a flare every 25 s lights fires next to the walls facing the star;
  - **gas cloud**: turrets −0.2 accuracy, and enemy aim is worse;
  - **radiation**: unsuited crew lose 0.5 hp/s while their ship has no shield layer up;
  - **debris surge**: every 20 s, 4 kinetic hits land on the walls facing the current.
  - *Example*: a Concord shield brick you can't crack in open space is beatable in an ion storm. That's a reason to take the stormy lane. In radiation, an ion hit on your shields becomes a crew emergency.
- **Cost**: medium (a new `hazards.gd`, one-line hooks in the arena, weapons, pilot, campaign and map; data). **Bloat**: low, five entries, already named by the regions. **Works when**: players choose a route *because* of a hazard.

### P9. Cargo has mass — considered
- Hauled materials add flight mass (a small factor per unit), so hoarding 900 scrap makes you sluggish. That's a reason to spend, sell or smelt (steel is denser value). Cheap (one number in `flight.gd`), but it could feel opaque. Revisit if the playtest shows hoarding.

### Considered and rejected for now
- **Crew veterancy** (skills grow with use): good for attachment, but bleed-out plus unique characters already give crew weight; it adds numbers to tune. Revisit after the owner's playtest.
- **Wages and upkeep**: a second economic clock next to the tide. One clock is better.
- **Stealth, smoke and decoys**: escape already exists (the J spool); more ways to avoid fights would dilute P2.

## 4. Round 1 plan
- **Builder A, `claude/mech-tide`**: P1.
- **Builder B, `claude/mech-salvage`**: P3 and P4.
- **Builder C, `claude/mech-morale`**: P2.
- **The contract between B and C**: a fight's result dict gains `state` = `won` | `captured` | `spared` | `escaped` | `fled` | `lost`, and `offer` ({item: count}) when spared. C produces these in the combat code; B handles every state in the campaign. Neither edits the other's files.
- P5 goes to the lead, F6 to the balance harness and the starters, F7 to the lead.

## 5. What changed and why it's more fun
*(Filled in at the end of the window, with screenshots in `/home/user/hs/shots/mech_*`.)*
