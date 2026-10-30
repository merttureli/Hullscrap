# Content loop 1: starts at 10 pm US Central (owner, 2026-10-30)
> "At 10 pm exactly, start the content loop with a fresh tank: more parallel agents adding lore, enemies and enemy designs, procedural generation to the max, and content updates in general: endings, ending ship screens, ending art, etc."

**Rules for every track**:
- Content goes in its own pack under `data/packs/<wave>/` (`docs/CONTENT_PLAN.md` section 7). Art goes by id under `art/`.
- Every track passes `tests/test_content.gd` and the soak test, and shows the owner screenshots or preview sheets before it merges.
- The lead merges as tracks land and keeps `main` playable after every merge.
- Specs come from `docs/CONTENT.md` (sections 8, 11, 13, 14), `docs/CONTENT_PLAN.md`, `docs/LORE.md` and `docs/ART_STYLE.md`.

## Tracks (parallel)
1. **Procedural enemy ships** (code): `scripts/space/shipgen.gd` builds an enemy ship from (faction, size class, seed, budget).
   - **The hull**: a silhouette from faction grammar rules, made of shaped pieces (no rectangles: the 4c rule).
     - Rustfang: jagged, ram bows.
     - Concord: symmetric and clean.
     - Lumen/Warden: faceted.
     - Hollow: wrong-looking.
   - **The inside**: rooms, doors, power and cables.
   - **The loadout**: mounts placed through the real mount rules and bought from the CONTENT 14 budget (`data/enemy_tables.json`).
   - Deterministic, and every result passes the ship tests (power, rooms, paths, mounts) in a 500-seed sweep.
   - The campaign's `fight: "tier"` uses it, with a threat rating against the player.
2. **The balance harness** (code): CONTENT 14. AI-vs-AI fights of the reference builds against generated enemies at jumps 5/15/25/35 produce `docs/BALANCE_REPORT.md`. It feeds track 1's tables.
3. **Procedural derelicts and POIs** (code): wrecks are generated ships with damage, breaches, fires, dead crew and loot (feeding salvage, and later boarding). POI flavour variants per region. These go into the sector generator once step 1 of the sector core lands.
4. **Region event packs** (writers, 2–3 in parallel): 40 events per region (Clan space, Concord space, Lumen space, the Boneyard, the Gate approaches), with blue options for all 10 species, plus 20 derelict logs per region. Each region is its own pack.
5. **Endings and landmarks** (writer plus code):
   - **Writing**: the full Haven chain (8–10 events across regions, with lures), the Way Out per faction, the Hollow chain, Retire, and 6 landmark events (CONTENT 13).
   - **Code**: the `unlock` effect, `data/unlocks.json`, the profile unlocks, **the ending screen** (the ending art, your ship's silhouette in the "hall of ships", the run log, score and unlocks), and new-run options for unlocked starters.
6. **Ending art and ship screens** (art): one pixel illustration per ending (Halcyon's gardens, a restarted gate per faction, the Hollow, retirement at Rusthold), plus hall-of-ships frames and score panel art, in the approved style.
7. **Content waves**: data plus art pairs:
   - **weapons wave 2**: ~20 more across lines and cultures, with a quarter of them turrets;
   - **race wave 2**: Vellum, Oorth, Drakkin, Wisp, Hullkin, Lantern, with the small and floating rigs;
   - **engines wave 2**: CONTENT_PLAN 4 B, C and D, including uniques with quests;
   - **processing** (smelters, steel and alloy) from CONTENT 12.
9. **The race loop to 30** (owner: "loop the races until we reach 30 unique ones"): waves 2, 3 and 4 from `docs/waves/races_2_4.md`.
   - Each wave is a hooks code agent plus an art agent plus a data and writing agent.
   - Run them back to back, with the next wave's art starting while the previous wave's data lands, until 30 species are on main.
10. **Regions** (CONTENT 15): the region graph code (8 stages, 2–3 choices at each exit, region data), then region packs: each race wave ships its homeland region with it.
11. **Unique characters** (CONTENT 16): the crew active-ability code (G, the vocabulary, cooldowns, crew cards), then character packs of about 16 at a time (writer plus art) until 64.
12. **Racial tech** (CONTENT 17): the new damage effects in combat, then per race 3 ship weapons, 3 components and 2 hand weapons (data plus art plus projectile and impact effects). It folds into the race loop: every race wave ships its arsenal, and waves 0–1 (the existing 10 races) get theirs first.
13. **Rare factions** (CONTENT 18): one pack per faction (region, enemy table, events and quests, crew, relics), from uncommon to legendary.
8. **Sector space steps 2 and 3**: the view, autopilot, fights in place, then its content (intakes Mk2/Mk3, radars, tractor), when step 1 lands.

## Order of starting
- At 10 pm, start tracks 1, 4 (two writers), 5 (writer and code), 6, 7 (weapons wave 2: art plus data) and **9 (race wave 2: hooks, art and data; wave 3 art too)** at once.
- Tracks 2 and 3 start when track 1 has a first merge, and track 8 when step 1 of the sector core merges.
- The lead keeps about 6–8 agents running and merges continuously.
