# Hullscrap drones: the bay, combat drones, magnetic limpets and boarders (lead design v1, 2026-11-05)

The owner asked for:
- activated drones that come out of a hangar section of the ship, one active at a time, always moving like FTL's;
- tiers of guns, with weaker fire rate in general;
- a supply cost to launch, and they can be shot down;
- hacker or boarder drones that go through shields and deploy a robot inside, and can be shot down, not in one shot but several;
- sticky drones that poison, burn or heat the room behind the wall they stick to;
- all of them magnetic, so they slowly fall in toward the enemy ship. A shot aimed to the side gets pulled in and hits the side or back rooms, not always the front.

This doc is the design. GUNS.md sets the look and the rules for mounts, families and balance, and drones follow it.

> **D1 landed (rules as built, where they differ from the first draft).**
> - **Content:** the pack `data/packs/drones_1` holds the bays (`drone_bay_mk1-3`: scrap, standard, neon; inside 3x3, outside 3x1, low; power -1, -1, -2), the **drone part** material, the seven kits and their recipes. A kit is an **item of kind `drone`** with its stats in its `drone` entry (role, tier, hp, gun, orbit); the loaded kit is saved on the bay (`kit` in the component record, no version bump). The kit stays in the hold (kits are permanent); two bays need two kits.
> - **Bay power** is the bay's own power figure, drawn whenever it is on, not only while a drone is out. A bay that loses power (or is disabled, cut off or its ship wrecked) recalls its drone.
> - **Re-arm** is 12, 9 and 6 s after a drone is lost, 25% quicker with a crew member in the bay's room; a recalled drone that docks leaves the bay ready at once.
> - **Choosing the kit** (build mode): hover a placed bay and press **K**, or **Alt+click** it. A panel lists the kits the bay can launch (tier, hp, how many the hold has). A bay left empty takes the best kit in the hold at the start of a fight.
> - **Drones:** the orbit is outside the target's hull and shield bubble (`gap` px beyond it), so a drone's shot meets the shield. hp 3, 5, 8; a shot that crosses a drone takes `damage / 3` hp off (at least 0.5), a point-defence hit 1, a turret's tracer its damage share. Turrets and swivels answer a third of their volleys at a drone in reach and arc, flak all of them, point defence counts drones as incoming. Drone guns are about half a hull gun's rate at the same hit (pulse 5.3 s, laser 3.5, ion 7, beam 8 s for 1.2 s, flak 5.5 s).
> - **Controls:** the bay is a slot after the guns on the weapon bar, key 1-9 in order; the slot shows the kit's picture, the part cost and how many are held, the re-arm counting down, and the drone's hp while it is out. Combat and defence drones launch with the key.
> - **Supply:** stations sell parts (14 credits in Kett and Gauntling regions, 24 elsewhere; 30 in small shops); a won fight gives the parts the enemy had left (plus one from a Kett or Gauntling ship), boarding stores hold 1-3 (more in clan halls). A design with a bay starts with 6 parts and a Pulse Drone Mk I (`RunStart.drone_stock`); no shipped starter has one yet (a core starter cannot name a pack's part).
> - **Enemies:** `data/enemy_tables.json` `drones`: a generated enemy (a spec, from stage 2; later stages too) has a bay with the chance of its size, placed on a flank or the stern (`Shipgen.add_bay`), kit weighted by faction, 4-9 parts. The AI launches when the foe is within 2600 px (a defence drone once something threatens or after 8 s).
> - **Art:** `art/_src/drone_export.py` writes the bays and drones (see `art/README.md`); drones are drawn from 32 pre-turned copies at about 1.5 cells, with a screen-size floor, a trail, hit flash and hp bar; a launch grows the drone out of the open hatch in 0.4 s, a recall shrinks it back.

## 1. Pillars
1. **A drone is a second front.**
  - Guns hit the face you point at.
  - Drones go round: combat drones circle, limpets curve in to the side or the back, and boarders put a fight inside.
2. **Every drone costs something and can be stopped.**
  - It costs a drone part to launch.
  - It has hp, so point defence, flak and turrets can shoot it down.
  - Nothing is a free win.
3. **The aim is a skill.**
  - Magnetic flight rewards a player who leads a limpet round the hull.
4. **Strong early, a choice later.** Combat drones carry small guns of the hull families, so they matter most early. Later they are a flank tool, not the main battery, unless you invest in Mk III bays and drones.

## 2. The drone bay (a hull mount)
- **The bay is a hull mount:**
  - Its inside half is **3x3**. The owner wrote "9*9"; I read that as 3x3, nine cells, because a 9x9 bay would be bigger than most starters. It is data, so it can change.
  - Its outside half is a **3x1** launch hatch: low, so rams pass over it (GUNS.md, flush pod rule).
  - It follows the mount rules of CONTENT.md 4f: the link goes through the wall, the hatch must face space, and it rotates to any wall.
- **One drone is out per bay at a time.** Two bays means two drones out.
- **The bay is loaded with one drone kit at a time.**
  - The kits are items in the hold.
  - You change the loaded kit in build mode, or between fights from the bay's card.
  - A kit is permanent. The drone part is what a launch spends.
- **Tiers:**
  - Bay Mk I launches tier 1 drones; Mk II, tier 1 and 2; Mk III, every tier.
  - A higher bay also re-arms faster: after a drone is lost, the next launch waits 12 s, 9 s or 6 s.
- **Power** is drawn while a drone is out. A bay with no power recalls its drone, or for a limpet and a boarder, already flying, nothing happens.
- **Crew:** it works unmanned. A crew member in the bay room makes the re-arm 25% faster.
- **Supplies:** a new material, **drone parts**.
  - A launch costs 1 for tier 1, 2 for tier 2, 3 for tier 3.
  - Parts come from stores, wreck salvage and boarding loot; they are commoner in Gauntling and Kett regions.
  - The starting kit has none. A starter with a bay brings 6.
- **Controls:**
  - The bay is a slot on the weapon bar, with its number key, like a gun.
  - Combat and defence drones launch with the key.
  - Limpets and boarders launch toward the mouse: the hatch throws them that way and the magnet does the rest.
  - The slot shows the loaded kit, the parts it costs, the re-arm time and the drone's hp while it is out.

## 3. Combat drones (gunships)
- **Movement:** they leave the hatch and **orbit** their target ship at their own radius and speed, always moving. Each one weaves a little in its radius (a smooth wobble, on the fight's seeded rng) so it is a hard target.
- **Guns:** one small gun of a hull family (GUNS.md section 4). It fires at the target's hull like a turret with perfect lead, at its own accuracy.
- **Numbers:** a drone's dps is about **0.5x** the hull gun of its family and tier: the same hit, a slower rate ("weaker fire rate in general").
- **hp:** 3, 5 and 8 by tier, and it dies at 0, with debris.
  - **What can hit it:** turrets, swivels, flak and point defence (GUNS.md section 6: drones count as incoming), and any shot that crosses it.
  - Fixed guns can hit it, but rarely.
- **Recall:** when the fight ends it flies home. There is no refund, and the part is spent.
- **The first list:**
  - **Pulse drone Mk I**: pulse, tier 1.
  - **Laser drone Mk II**: laser, tier 2.
  - **Ion drone Mk II**: ion, strips a shield layer.
  - **Beam drone Mk III**: a short beam that sweeps across rooms.
  - **Flak drone Mk III**: flak, good against small ships and the enemy's drones.
- **Defence drones:** they orbit **your own** ship.
  - **Defence drone Mk I:** point defence, about 50% to hit, 1.5 s.
  - **Defence drone Mk II:** about 65% to hit, 1.0 s, and it shoots enemy drones as well as shots.

## 4. Magnetic flight (limpets and boarders)
- **The magnet:** a limpet or boarder flies in a straight line from the hatch toward the mouse at its launch speed. The target ship then pulls it in.
  - The pull is an acceleration of `pull / max(d, d0)^2` toward the nearest point of the target's hull, where `d` is the distance in cells.
  - Its speed is capped, and its course turns with the pull, not in one snap.
- **The aim:**
  - Aimed at the hull, it hits the front.
  - Aimed wide, it swings round and lands on the side or the back.
  - Aimed far too wide, it misses and drifts away.
- **Shot-down:** a limpet has 2–3 hp and a boarder pod has 4–6, so point defence must hit it more than once.
  - It is slow, so PD and flak are its counter (GUNS.md, pd_speed).
- **Shields:** it passes them. A hit on the shield bubble does nothing to it, as with missiles.
- **Sticking:** it sticks to the first hull cell it touches. Its effect works on **the room behind that wall** (the nearest room inside, by the shortest path through wall cells).

## 5. Limpets (sticky effect drones)
- **Fire limpet:** sets the room behind on fire every 6 s, for 30 s.
- **Poison limpet:** poisons the room behind for 30 s:
  - crew there take 2 hp/s (species and suits resist it: a sealed suit stops it);
  - the air drains slowly (the `spores` o2 drain).
- **Heat limpet:** heats the parts in the room behind for 30 s (+heat per second) until they overheat and shut down (the heat system: heat_limit, cooling). Crew there feel it too (heat on foot).
- **Removing a limpet:**
  - It falls off when its time runs out.
  - It goes when its hull cell is destroyed.
  - A crew member who goes to the room behind can scrape it off, with a 6 s job, through a hatch kit. It is a job priority, so the crew decide.
- **Tiers:** Mk I lasts 30 s; Mk II is stronger, and a fire Mk II also spreads.

## 6. Boarder drones (the robot inside)
- **The flight:** like a limpet, magnetic, it passes shields, it has 4–6 hp, and PD and flak can shoot it down.
- **On contact:** it cuts a small breach in the wall cell it hits (the room vents a little until it is patched) and drops **one boarding robot** into the room behind.
- **The robot** is a hostile unit in the enemy ship's crew sim:
  - it fights crew in reach;
  - otherwise it walks to the nearest powered system and damages it (sabotage), then the next.
  - **hp:** 40, 60 and 90 by tier. Enemy crew fight it as they would an intruder.
  - When it dies it is gone, with debris. It does not come home.
- **Tiers:** Mk I is a drill robot (slow, melee); Mk II a shock robot (it ion-locks the system it attacks); Mk III a pair of two robots.
- **The same works on you:** enemy boarders put robots in your ship. Your crew and soldier fight them, and Jobs gains an "intruder" response: crew in reach fight, and the soldier goes.

## 7. The enemy's drones
- **Styles weight them** (shipgen and enemy tables):
  - Gauntling: robots and boarders;
  - Kett: swarms of combat drones;
  - Sporeling: poison limpets;
  - Emberkin: fire limpets;
  - Basalt: heat limpets;
  - Fenn: ion drones;
  - Human: defence drones.
  - From stage 2 on, about 1 enemy in 4 has a bay. More later.
- **The enemy AI** launches when it can afford to: its parts are its budget. It aims limpets at its target with a lead, plus a skill-based wide angle to reach the side and back rooms.

## 8. Look (adds to ART_STYLE.md and GUNS.md section 7)
- **The bay:**
  - Its inside half is a 3x3 hangar: a launch rail, a drone on its cradle (the loaded kit's sprite), parts racks and a family-coloured status strip.
  - Its outside half is a 3x1 hatch with doors that open on launch.
  - Lines follow scrap, standard and neon.
- **Drones are small sprites:**
  - a combat drone is about 1 cell (16 px source), with a body, a small gun and a running light in the family colour;
  - a defence drone has a radar ring;
  - a limpet is a 1-cell spiked disc with a glow core (fire orange, poison green, heat red);
  - a boarder pod is a 1x2 drill-nosed capsule.
  - A thruster trail in the line's colour.
  - Frames: idle, firing and hit flash, plus a stuck limpet's pulsing glow.
- **The robot** is a crew rig, drawn on the repair drone's species rig with a heavier body and a family-coloured eye.
- **Review gate:** a labelled sample sheet of the bay, one of each drone, a stuck limpet in context and the robot, to the lead and then the owner, before the rest.

## 9. Balance
- **Combat drones:** worth about a gun of their tier at half the dps, plus the value of flanking (they hit wherever they orbit). The bench measures a starter with a bay and Pulse Drone Mk I against its stage 1–2 enemies, against the same starter with a gun instead.
- **Limpets:** a fire or poison limpet that sticks does about a hull gun's volley of value over its time, more against crewed rooms. The bench shows PD stopping 50–80% of them.
- **Boarders:** a robot Mk I kills or ties up one crew member and damages a system or two before it falls, against a crew of 3–4.
- **Supply:** a run should see about 1 drone part per fight on average, so a drone build launches about one drone per fight unless it hunts for parts.

## 10. The healing arm (a medbay at higher tiers, owner)
- **Medbay Mk II and Mk III are healing arms:**
  - an articulated arm on a 2x2 base that reaches crew within a radius (Mk II 6 cells, Mk III 9 cells, through doors; walls don't block reach, rooms do, so state the rule) and heals them where they stand: at their posts, in a fight, while repairing;
  - it heals one patient at a time, at the medbay rate (Mk II 1.2x, Mk III 1.6x);
  - **patient choice:** the soldier first when everyone is at the same hp; otherwise the lowest hp share in reach; ties go to the soldier, then to whoever is manning a station;
  - it switches patient only when the current one is full or leaves its reach, to avoid flicker;
  - power: Mk II −3, Mk III −4; it stops in a room without air;
  - **look:** the arm sprite turns toward the patient, with a soft green beam and a glow on the patient.
- **As built (H1, `scripts/crew/jobs.gd`):**
  - **reach rule:** crew whose cell is within `stats.reach` steps of walking from the arm's own cells, over floor and doors (4-neighbour steps through `Pathfinder.walkable`: walls block it, a door does not, a locked door of an abandoned room does). Worked out per arm every 0.5 s.
  - **patient:** the hurt or down crew in reach who can be healed by a medbay and have air (or need none); kept until full or out of reach (or the arm loses power); then the lowest share of hp, ties to the soldier, then to whoever has a `man_station` job, then crew list order. Two arms heal independently and may stack on one patient.
  - **the job:** a hurt crew member with nothing to do is not sent to a bed or medbay while a working arm serves them; they keep their post or work. A crew member who works keeps working as before (rest is the lowest job).
- **Medbay Mk I stays the bed.**
- The arm is a blueprint, Mk II mid-run and Mk III late.

## 11. Plan
- **D0, design** (this doc and its sketch): the owner sees it.
- **H1, the healing arm** (section 10): small, can run now. Its files are `jobs.gd` heal and the medical pack; the art goes through the art pipeline.
- **D1, the bay and combat drones** (sections 2, 3 and 7 for combat and defence drones, with their art). After G2a, since both touch `weapons.gd`, `weapon_bar.gd` and PD.
- **D2, limpets and boarders** (sections 4–6, the robot, the intruder response, with their art). After D1.
