# Hullscrap: setting and lore (lead, v1)

Everything here should make the mechanics feel motivated:
- the three equipment lines are three **cultures**;
- species traits come from where those peoples live;
- wrecks are everywhere for a reason;
- every quest giver wants something.

Tone: **working-class space**. Grimy, funny, a little sad, never grimdark. The jokes come from people getting by. Think *Firefly* crossed with a salvage yard.

## The premise: the Snap
Forty years ago the **Lattice** went dark in one night. It was the network of gate stations that let ships jump between star systems.
- Every ship mid-jump came out wherever it happened to be: thousands of hulls strewn across the **Drift**, the region between three dead gates.
- Nobody knows why. The **Concord** says "solar event". Scrappers say "somebody pulled the plug". The Lumen don't say anything, which people find suspicious.
- With no gates, the Drift became an island. Nothing new gets built from scratch out here: **everything flies on salvage**. That's the game's economy, and its name.

## The player
You inherited (won at cards, stole, were "loaned") a barely-working hull and the debts that come with it. You're a **hullscrapper**: you fly out to wrecks, cut them apart, sell what works, and fit the rest to your own ship.

**The long arc**: rumours say the dead gates still have power in their cores, and whoever restarts one owns the way out of the Drift.
- Every faction wants that. You start out wanting rent money.
- The arc is a sequence of gate expeditions: a Concord gate, a Scrapper gate, a Lumen gate. They're the late-game set pieces, each a huge derelict station to board.

## The three cultures (= the three equipment lines)

### The Scrapper Clans: Scrap line
- **Who**: descendants of the crews stranded by the Snap. They live in **Rustholds**: stations welded together from dozens of wrecks, still spinning on borrowed parts.
- **Values**: if it runs, it's fine; if it doesn't, hit it. Clan reputation is measured in how much junk you can keep flying.
- **Gear**: cheap, loud, repairable with a wrench and a prayer. A Rustbucket Reactor works fine until it doesn't.
- **Politics**: a dozen clans that feud constantly and unite instantly against the Concord. The biggest is the **Gantry Clan**, which runs the main Rusthold. The **Rustfangs** are clan exiles turned pirates. *The pirate raider you fight is Rustfang.*
- **They hire you for** salvage runs, cargo smuggling, clan disputes ("bring back our cousin's reactor"), and races.

### The Concord: Standard (Mk) line
- **Who**: the remnant of the government that ran the Lattice. They hold **Concord Station Meridian**, the one place in the Drift with a working shipyard that can make new Mk parts.
- **Values**: order, paperwork, and the firm belief that they'll fix the gates if everyone just files the right forms. Decent people trapped in a bureaucracy that has nothing left to administer.
- **Gear**: reliable, standardised, tiered Mk1–Mk3, and certified. Their shipyard sells **hull frames**: you expand your ship here.
- **Politics**: they want the gates back under Concord control. They post **bounties** on Rustfangs and are quietly losing a cold war with the clans over who owns salvage rights.
- **They hire you for** bounties, escorts, "official" salvage contracts with inspections, and courier work.

### The Lumen: Neon line
- **Who**: a sect of engineers who were researching the Lattice when it died. They live in **the Prism**, a crystalline station that hums.
- **Values**: they think the Snap was a door opening, not closing. They build with **crystal** and **plasma** salvaged from the dead gates themselves, which is why their gear is brilliant, fragile, runs hot, and **hates ion**: it's built from the same physics that broke.
- **Gear**: neon. High output, needs a proper workshop to make (high fabricator level), expensive. They trade it only to people they've decided are "interesting".
- **Politics**: they want to *study* the gates, not restart them. Possibly they're the ones who turned them off. Their quests are strange, and the rewards are blueprints.
- **They hire you for** scanning anomalies, retrieving crystal from gate debris, testing prototypes (a quest that literally hands you a quirky unique), and escorting researchers.

## The Haven: the signal in the dark (owner's idea, 2026-10-30)
- **The broadcast**: since a few years after the Snap, a weak looping message has crossed the Drift: *"If you can hear this, we're alive. Come to the Lantern Reach."*
  - Most people think it's a hoax or a Hollow trick. Scrappers call chasing it "going lantern-blind".
- **Halcyon** is real. It's a generation ship that was mid-jump when the Lattice died. It came out in a quiet pocket of the Drift and simply... lived. Forty years of gardens, schools, and children who've never seen a wreck.
  - They built small working gates of their own design and told no one, because everyone they ever answered tried to take them.
- **The lures**: the Hollow learned the broadcast. Some fragments lead to Halcyon, and some lead to something that sounds exactly like it.
- **What it means for play**: the Haven is the hopeful ending. Fragments are found in logs, radar ghosts and distress beacons; the trail crosses every region. Reaching it is a choice between keeping it secret, bringing others, or (if you followed the wrong voice) something worse.

## Species
All are data; traits appear in `data/crew.json` as they're implemented.
- **Humans**: most of the Drift. Balanced, need air, complain about everything.
- **Basalt** (silicon-based): slow, heavy, **don't breathe** (`no_breath`), bad medics because they don't understand soft bodies. Clan engineers love them for vacuum work. Before the Snap they were the gate builders' labour caste, and some remember more than they say.
- **Emberkin**: small, warm-blooded to an absurd degree. **Heat-resistant** (`heat_resistant`), happier in hot rooms, miserable in the cold. The natural crew for neon reactors and afterburner rooms. Many work for the Lumen.
- **Fenn**: quick, clever-handed engineers (`fast_repair`), but fragile (low hp). Long ears, short tempers, an excellent trading culture. They run most station markets.
- Unique recruits are named individuals from quests, each with one odd trait. For example *"Socket"*, a Basalt who can **power one adjacent system by hand**.

### Race wave 2 (data: `data/packs/races_2/`; homelands and events in the same pack)
- **Vellum**: folded paper-folk, the height of a shoulder, a lane for a coat and two ink dots for eyes. After the Snap the Lumen archivists of the Prism had more charts than hands: charts of lanes that no longer exist, drawn by navigators who no longer exist. Somebody folded one, and it sat up and asked the date. They are folded, not born, and each remembers the chart it was made from; the creases are the memory. They are quick, polite, fit through any gap, and afraid of fire in the way you would expect. They read everything, and are mortified to be read. Home: the Vellum Stacks, where the Folding Room makes them one chart at a time. Fragile (hp x0.5, fire x2), fast (x1.2), small (they walk 1-wide crawlspaces).
- **Oorth**: tall, still and hooded, with a third-eye ridge that glows when they listen. The Concord kept them as advisors, and for forty years they sat at the back of Meridian's briefings and were never once asked a question, so the Concord took their silence for approval. They do not read minds so much as ships: the hum of a hull, who stands where, who is afraid. They are mortified by loud people and bad at fighting, since they can see the blow arrive and feel sorry for it (melee x0.5). A crew with an Oorth sees the enemy's crew on the schematic. Home: the Oorth Quietude, whose Listening Gallery has a sign over the door reading PLEASE ASK US SOMETHING.
- **Drakkin**: reptile brawlers with a crest and a scaled hide of rust and ochre, drawn large. The pit-fighters of the Gantry Clan's cargo bays (the fight in Bay 4 is theirs). They are cold-blooded and it shows: slow and sulky in a cold room (x0.7), quick in a hot one (x1.2), which is why every Pit is heated and every bet is placed early. They hit hard (melee x1.75, hp x1.2) and sleep in heaps on reactor casings. Home: the Drakkin Pits, and the Heat Sink at their heart.
- **Wisp**: living current, a body of light ribbons with a trailing tail, no legs and no hands. Forty years ago the first night's lightning met a field of dead reactors still holding their charge, and the storm never quite ended; they were born in it and still arrive with the weather. They do not breathe and no vacuum troubles them, they cannot hold a wrench (no repair or extinguish work), they live in the wiring, and the bonus of a post they man is half again as big (x1.5), and an ion hit hurts them twice as much because it is what they are made of. Home: the Stormfield, and the Earthing Post, the only station in the Drift with a lightning rod instead of a dock.
- **Hullkin**: barnacle-folk, with a ridged shell back, small grasping hands and an eye on a stalk. They live on the outside of old hulls, where the Boneyard's wrecks have become reefs, and take their names from hull-parts (Strake, Garboard, Gunwale). They are very slow (x0.5) and very patient, breathe little (x0.5), and mend: left idle, a Hullkin presses against a wall and the wall slowly closes. Weddings take three weeks, and it is considered rude to hurry anything. Home: the Hullkin Reefs, where the outside of one ship is the street of the next, and Barnacle Row.
- **Lantern**: moth-folk with dusty wings folded on the back, who glide when the gravity lets them and have flown by lamplight for as long as anyone remembers. The Concord's pilots by tradition: Meridian trained them because they will fly into a docking light for a crew member and out again for a friend. They are quick and light (speed x1.3, hp x0.8), they add a little evasion at the helm, and they are drawn to bright things, which they will not admit, and which is why they all teach the same rule: do not look at the lamp, look at the dark it makes. Home: the Lamplit Lanes, a chain of Concord lane-lamps left burning since the Snap, and Vesper Field, where the Concord's pilots are trained.

### Race wave 4 (data: `data/packs/races_4/`; homelands and events in the same pack)
- **Warden-frame**: a rebuilt Lumen gatekeeper drone, sleek and neon-panelled, with a single lens and mechanical limbs. Nobody is born one: a Warden that stood its watch at a dead gate for forty years and was never relieved can be woken, by a clean spark of old Lumen light and a name, and then it asks the only question it was ever built to ask: is there something I should be holding? They are mechanical (a crewmate's repair mends them, not a bed), do not breathe, shoot half again as well as anyone (ranged x1.5) and take triple ion damage, because ion is what a drone is afraid of. They name themselves after the furniture of a gate (Lintel, Jamb, Sill, Threshold) and take the post by the hatch. They have no homeland: a late-stage quest that finds a dormant Warden in the wreck fields, lights it and reboots it is the only way in.
- **Murrow**: mole-folk with huge digging claws, tiny dark eyes and a dust-caked miner's harness. The diggers of the asteroid colonies, who live in rocks with a green door in them and eleven kilometres of lamplit tunnel under the crust. They are sturdy (hp x1.2), a little slow above ground (x0.9), and break rock one and a half times as fast as anyone (a miner's mattock, a cutter). They name themselves after spoil and seams (Mulch, Hummock, Culm) and are shy about the surface. Home: the Murrow Diggings, with the warren of Burrowgate; their asteroid-field and mining-field nodes.
- **Siltborn**: gas-giant floaters, a translucent bell and trailing tendrils that glow from inside in soft blues and pinks. They drift in flocks in the rings of a gas giant, netting the ring-ice, and have a quiet seriousness about it. They breathe half as much (o2 x0.5), mend a hit point a second in a room that has almost no air, and burn twice as easily, which is why every dock they keep has a sign that says PLEASE DO NOT LIGHT A FLAME. They carry no weapon. Their names are long and soft (Maelu, Oshe, Selumi). Home: the Siltborn Rings, and the harbour of the Gossamer; they turn up at anomalies.
- **Corvin**: crow-like scavengers with a beaked head, a feather cloak and pockets everywhere. The wreck-traders of the lanes, who can tell what a thing is worth by how it catches the light and will say so, in clicks. A Corvin aboard knocks a tenth off every price at a station (haggler) and finds one more thing in every wreck, salvage pick and loot table (loot bonus). They are honest by their own code and entirely incomprehensible by anyone else's. They are named for what they keep (Tikka, Pica, Spangle, Chough). Home: the Corvin Roost, a bazaar of a thousand hulls, and Tinsel Row; they turn up at trader nodes.
- **Brine**: crab-shelled dockworkers with a broad slate-blue carapace, one huge work claw and one small fine hand. The Concord dock unions' own people: they move the weight, strike by the book and brew the tea. The shell takes a third off every blow in a brawl or a gunfight (damage taken x0.7), they restock a rack half again as fast, they walk slowly (x0.85) and cannot wear a suit, because the shell does not fit. Their names are union families (Corrigan, Tully, Orla). Home: the Brine Yards, and Slip Nine; the union hall at Meridian hires them.
- **Echo**: a shimmering mimic, a smooth glassy body whose face shows a faint, flattering likeness of whoever stands near. Rare, curious and unfailingly polite, they live in the Glassways, where every signal comes back a day late and a little kinder. An Echo copies the best trait of a crewmate in its room, for as long as it stands there; alone it is only a mirror waiting to be asked who it should be. They name themselves after politeness (Pardon, Likewise, Indeed, Encore). Home: the Echo Glassways, and the Receiving Room; they turn up at anomalies.
- **Ferro**: living ferrofluid, a spiky liquid-metal body that ripples, with magnetic sparks along the arms. Born in the Boneyard's magnetic wrecks, where a reactor still pulling will grow a pool the size of a lake. They are immune to ion damage, mend the walls beside them when idle (hull_mend 0.5), and the salvage intake one of them mans pulls a cell further, because they are the magnet. They name themselves after the units and the people of their field (Gauss, Oersted, Weber, Farad). Home: the Ferro Lodes, and Coil Row; they turn up at wreck fields.

## Places (stations are walkable ships; see PLAN "On foot")
- **Gantry Rusthold** (Scrapper hub): a scrap market, clan recruiters, cheap repairs, fights in the cargo bay. The first station you dock at.
- **Meridian** (Concord hub): the shipyard (hull frames, Mk parts), the bounty office, a medical deck, very clean floors.
- **The Prism** (Lumen hub): only after a Lumen quest. Neon blueprints, crystal traders, strange crew.
- **The Boneyard**: a dense wreck field near the first dead gate, the main salvage zone. Derelicts float here with their air, fires and occasionally their crew still aboard.
- **Dead Gates** (late game): three huge derelict stations to board, each a dungeon with its own hazards (vacuum zones, overcharged systems, Lumen watchers, Rustfang squatters).

## Pirates and threats
- **Rustfangs**: Scrapper exiles with scrap-line ships, scrap-plate armour and a liking for flak and Bolt Throwers. They **board** when they can. Early-game enemies.
- **Concord Enforcers**: if your Concord reputation drops (smuggling, attacking Concord ships). Mk-line ships with good shields and missiles.
- **Wardens**: Lumen-built automated drones guarding gate debris. Neon weapons, ion-weak. Mid-game.
- **The Hollow**: rumoured ships that came *out of* the dead gates after the Snap. No crew aboard, but the systems still run. The late-game mystery.

## How lore shows up in play (writing rules)
- **No lore dumps.** Lore comes through NPC dialogue, item blurbs, station signage, derelict logs (short data-pad texts found while salvaging), and quest text.
- **Every item blurb has a voice**, the one of the culture that made it. Scrap blurbs are jokes or warnings, Concord blurbs read like spec sheets with tired asides, Lumen blurbs are cryptic.
- **Reputation**: three bars (Clans, Concord, Lumen). Your choices in quests and fights move them. Prices, recruits and which blueprints you're offered depend on them.
- **Names**:
  - Scrapper ships are named like boats and insults ("Second Mortgage", "Ma's Kettle", "Not Again");
  - Concord ships have registry numbers plus a virtue ("CS-114 Diligence");
  - Lumen ships are named after light phenomena ("Caustic", "Afterimage").

## Data to add as content grows
- `data/factions.json`: id, name, line, colours and reputation thresholds.
- `data/species.json`: traits, hp, speed, oxygen use, heat tolerance.
- `data/dialogue/*.json`: NPC dialogue trees.
- `data/quests/*.json`: quest steps, requirements and rewards.
- `data/logs/*.json`: derelict data-pad texts.
- Ship names per faction: `data/names.json`.
