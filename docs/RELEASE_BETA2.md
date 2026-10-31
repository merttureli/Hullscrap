# Hullscrap Beta 2

Built in one night after the Beta 1 playtest ("combat is amazing"). Play it from **GitHub → Actions → beta builds → the latest green run → Artifacts** (Windows, Linux, macOS).

## Your Beta 1 feedback
- **Faster ships**: thrust, acceleration and top speed ×1.5; turning in proportion.
- **Build mode pauses the world**: crew, fires, air, heat and crafting stop; anyone caught in a new wall steps clear when you leave. You can't enter build mode with an enemy within 2,500 px (red alert).
- **A real build UI**: a parts palette with tabs and sprite cards, a details card, a placement preview that shows both mount halves (green, or red with the reason), a resource bar and a mode bar.
- **Start with very little**: starters are 1.6–1.8× bigger, with only the essentials built (76–83% empty) and building materials in the hold.

## The core loop
- **Regions**: an 8-stage run; at each exit you choose between 2–3 regions (danger skulls, rarity); a final region at the Gate.
- **Open space (the Raft loop)**: fly each place in real time; click a marker and the helm flies there (cruise ×3); debris drifts on the current into your salvage intakes; radar Mk1–Mk3 (Mk3 sees hidden things), tractor beam (hold Q); fights happen in place; light-speed jumps spool from the map.
- **Generated enemies** per faction and size, with 1–5 skull threat ratings shown before you fight.
- **Exit wardens**: every region's exit is held by a generated ship: pay its toll, be waved through on standing, break through, or turn back.
- **The Hollow tide**: a front sweeps each region one step per jump and every 4 minutes you linger; places behind it go Hollow (ghost ships every 60 s, no trade, almost no loot).
- **Region hazards**: ion storms, star heat, gas clouds, radiation, debris surges.
- **Fights end three ways**: enemies surrender (Y takes the offer), flee (shoot their engines or helm), or are captured when their crew is all down.
- **Salvage**: after a win, cut out one of the enemy's surviving parts, scan one for its blueprint, or strip her for scrap; more picks against dangerous enemies.
- **Enemy intent**: your schematic shows what they're aiming at and counts down their heavy shots.
- **Crew can die**: downed crew bleed out in 45 s unless revived or in a powered medbay (your soldier never dies this way).
- **Ammo racks and conveyor belts**: crew restock racks from cargo; belt drives carry ammo to the guns.
- **Smelters**: scrap → steel → alloy, conductor, glass lattice.
- **Endings, landmarks and unlocks**: 8 endings (the Haven chain, a Way Out per faction, the Hollow, Retire), 6 landmarks; unlocked starters, species, blueprints, map variants and hull skins apply at a new run; the ending screen and the hall of ships.

## The races
- **30 species** (the original 10 plus waves 2, 3 and 4), each with its own homeland region and events (the Warden-frame is recruited by a quest instead).
- **The first 10 races are complete**: racial weapons, components and hand weapons whose drawbacks their own race cancels; 2 starter ships each; 2 unique characters each with an active ability (G).
- **48 unique characters** with active abilities, **30 starter ships** in the hangar.
- **Rare factions**: the **Salvage Barons** (uncommon: gaudy pirate lords in Clan space and the Boneyard, gilded weapons, a relic shield) and the **Leviathans** (rare: living ships in their own region, the Deep Drift, and a roaming encounter; the self-repairing Starwhale Fin and bone armour). Meeting either unprepared can end a run; they show 4–5 skulls and always offer a way out.

## Balance (docs/BALANCE_REPORT.md)
- A harness flies the starters against generated enemies of every faction at jumps 5, 15, 25 and 35.
- Fixed: pilots kept large enemies out of gun range; a starter's only gun died to the first hit (weapon outside halves now have 2x hp); crew couldn't repair breaches next to a gun mount; the Heat Lance overheated.
- AI-vs-AI: jump 5 starters win 56% (78% projected), jump 15 with a few upgrades 56% (72%), jump 35 bare 0% (11%). Enemies break at half hull; wardens are a clear step above the fights around them.

## Known issues
- Fights are long (90-150 s in AI-vs-AI); your own flying is the real test.
- Smelters and the new materials use placeholder art.
- The intent panel shows no reticle when the enemy pilot aims at your hull instead of a part (most pilots now).
