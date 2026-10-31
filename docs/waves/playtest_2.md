# Playtest 2: what the owner asked for, and the plan (Beta 3)

The owner played Beta 2. Fights and events are good. This round fixes everything below before the next playtest.
The pace is slower than the Beta 2 night: **two builders at a time**, in four waves, and the lead reviews and merges each wave before the next one starts.

## The owner's notes, as decisions

### Open space
- **Space has walls.** The sector should feel endless. Chunk streaming: past the generated POIs, space is cut into chunks, and each chunk rolls a few POIs of its own from the sector's seed, so wherever you fly there is something ahead. (S1)
- **More events in open space.** (S2)
- **Debris vanishes when you fly fast.** Keep a steady flow whatever your speed, from one main current plus up to two side streams. Every cargo type (scrap, copper, polymer, ice, fuel, crates) is in the flow. (S3)
- **Ships are too fast in open space.** Lower the sector cruise speed; fights stay the same. (F4)
- **The Hollow tide doesn't push you.** As it nears: the debris thins, fog creeps in from the tide's side, and the tide clock pulses. (S4)

### Flying and controls
- **Rear engines alone can't strafe.** Every engine also gives 30% of its thrust sideways (left and right). Side engines still give their full thrust sideways, so they stay worth building. (F3)
- **The soldier's WASD turns with the ship.** WASD is screen-relative: W is always up on the screen. (F1)
- **Scrolling the build palette also zooms the game.** The mouse wheel over any panel scrolls that panel and never zooms. (F2)

### Starts, crew and ships
- **Always start alone.** Ada becomes the likely first crewmate, found early.
- **Crew is very hard to find.** Every new crewmate should feel like a big moment. (A1, A2)
- **Starters come too complete.** Each has a helm, a reactor, 1–2 engines, 1–2 guns, air and one bed, plus a shield or a medbay (about half each), not both. A few have two guns and neither. Less scrap in the hold. (P3)
- **The medbay is one bed.** (P1)
- **Parts are too big for small ships.** Tier 1–2 parts get smaller footprints; tier 3+ stay big, so bigger tech pushes you to build a bigger ship. Starter hulls grow a little (+15% area). (P2, P4)
- **Enemy ships come too loaded.** Early stages get smaller budgets and fewer shields. (C3)
- **Continue loses the crew.** Saves keep the crew. (F6)

### Commanding the crew
- **Crew need proper commands.** A station bar: one button per crewable system. Select a crewmate, click a station, and they are posted there for good. A posted crewmate leaves only to restock its ammo, repair their own station or fight a fire in their room, then goes back. (K1)
- **Breaches.** When a room starts losing air, time slows and a prompt asks: Repair or Evacuate. Evacuate abandons the room: no jobs inside, the crew leave and its doors seal. (K2)
- **Crew repair until they die.** Crew low on health in a room with no air leave it on their own, and come back when healed or the air returns. (K3)

### Combat pacing
- **Repairs are too fast.** Repair times roughly double. (F5)
- **Shields come back at once.** Each generator has its own recharge time (Mk1 about 7 s per layer, up from 2 s). Layers come back one at a time, and an emptied sector waits 3 s more. (C1)
- **Guns fire too fast and become spam.**
  - Most guns get slower, heavier shots.
  - Only 10–15% of guns are fast-firing: a spammable early one, a medium one mid-game and a very good one late.
  - The fast-firing guns are auto turrets, so later you aim your missiles by hand while they fire themselves.
  - Fights get a little slower overall. (C2)

### Information
- **Every part needs a description**: what it does, its stats (power, damage, fire rate, thrust...), what its damage type or effect means (a laser does X, ion does Y, a turret auto-aims), and a line of lore. (I1)
- **The build menu shows everything, even parts you can't make.** It shows only what you hold or can craft (blueprint known). Everything else lives in the crafting menu only. (I2)
- **Crafting needs more explanation.** (I3)

## Waves (two builders each)
| wave | builder A | builder B |
|---|---|---|
| 1 | `feel`: F1–F6 | `pace`: C1–C3 |
| 2 | `space`: S1–S4 | `parts`: P1–P4 |
| 3 | `alone`: A1, A2, K3 | `info`: I1–I3 |
| 4 | `command`: K1, K2 | then a QA playthrough, Beta 3 build |

## Budget
- The round stops at **40% weekly usage** (it was 26% at the start), or when wave 4 is merged.
- At that point the lead ships Beta 3 and holds until the owner's next playtest.
