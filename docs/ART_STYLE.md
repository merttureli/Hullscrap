# Hullscrap art style: FTL's visual language, our own drawings (lead, v1)

We re-create the *style* of FTL / FTL: Multiverse. **We never use their files.** All art is original, made to these rules, or human-made packs under CC0 or CC-BY (logged in `ASSETS.md`).

## Medium
- **Pixel art**: hard pixels, nearest-neighbour scaling, no blur or soft gradients, except soft alpha **glow layers** (lights, projectiles, engines). Light shading comes from 2–3 hand-placed tones, and dithering only where it's needed.
- **Source scale**: 1 grid cell = **16 × 16 source pixels**, displayed at 2× (32 screen px per cell at zoom 1).
  - So a crew body is about **28 × 28** source pixels, top-down and layered (see Crew).
  - A 4×4 reactor is 64 × 64 source.
- Light comes from the top-left. Every object has a **1 px dark outline** (not pure black: a dark shade of its own colour) and a 1 px drop shadow down-right on the floor.

## Palette (muted base, saturated state)
- The base world is **desaturated and calm**:
  - floors warm light grey `#b9b4a8`, with 1 px grid lines `#8f8a80`;
  - walls dark slate `#3b3f45` with a lighter top edge `#5a6068`;
  - room interior shadow `#6f6a62`.
- **Colour is saved for state and function**:
  - power is green `#6bd34a`, shields blue `#4fa3ff`, oxygen-low pink `#e88aa0`, fire orange and yellow `#ff8a1e` / `#ffd23a`, damage and breach red `#e0413b`, hull and doors amber `#e1a136`;
  - lines: scrap rust `#9c5a33`, neon cyan `#3cf2ff` with magenta `#ff4fd8` accents.
- At most about 24 colours across the whole game, defined once in `art/palette.gpl`.

## Interiors (the FTL look)
- **Rooms read as rooms**: light floor tiles in 16 px squares with the grid visible, slim dark walls, and each room's edge slightly darker (a 1 px inner shadow).
- **Doors** are amber frames with two sliding halves. Open is 2 frames, closed is a solid bar.
- **Systems**: a **pixel machine sprite** plus a **white system icon** (power, engine, O2, shield, weapon, medbay) shown on the floor of its room, as in FTL. Manned stations have a small console with a glowing screen (2-frame flicker).
- **State overlays**:
  - low O2 tints the room pink;
  - fire is a 4-frame flame loop per cell;
  - a breach is a black hole with jagged edges and 2–3 pixel debris specks;
  - a damaged system gets a red flashing icon;
  - an unpowered one has its icon greyed.

## Crew: strictly top-down and layered (owner, 2026-10-30)
FTL's three-quarter view needs a full set of drawings per direction, which we can't afford for a shooter. **Our crew are drawn straight from above and rotate freely**, built from layers so gear never needs a redraw:
1. **Legs**: a walk cycle of 4–6 frames plus a standing frame. It rotates to the **movement** direction.
2. **Torso, shoulders and head**: one drawing per species. Outfit colour is on a `_color` mask (tinted per crew member). Helmets, backpacks and exosuits are overlays.
   - It rotates to the **aim** direction: the cursor for the player, the target for NPCs.
3. **Arms**: one pose per weapon class: `unarmed`, `pistol` (one or two hands, short), `rifle` (two hands, long), `tool` (wrench or extinguisher). Arms rotate with the torso.
4. **Weapons and tools**: separate small sprites, each with a **grip** anchor and a **muzzle** anchor. A new gun is one small drawing.
- **Anchors** are stored in JSON next to each sprite, in source pixels relative to the sprite centre: `hand_r`, `hand_l`, `head`, `back` for the body; `grip`, `muzzle` for weapons.
- **Size**: the body is about 28×28 source pixels (2×2 cells is the collision; the drawing may overhang a little).
  - Rotate with nearest-neighbour. If jaggies show, pre-render 32 rotations at load time.
  - Same law as before: 1 px dark outline, 2–3 tones per material, top-left light (baked; we accept the inconsistency on rotation).
- **Animations**: legs walk at 8 fps; arm recoil is 2 frames; tool use is 2–3 frames on the arms only; "down" is one frame.

## Ships in space (combat view)
- **The hull is a hand-shaped exterior**: panel lines, rivets and greebles, darker outline, engine glows (2-frame pulse), and line accents.
- In combat at a distance, the hull exterior shows. Hovering or zooming fades it to reveal the rooms, as FTL does.
- **Projectiles**:
  - lasers are 1–2 px bright lines with a 3-frame muzzle flash;
  - bolts are 4–6 px glowing pellets;
  - missiles are 8–10 px sprites with a 3-frame exhaust;
  - explosions are 5–6 frames, sparks 3 frames, smoke 4 frames.
- The shield is a pixel ellipse with a 1 px bright edge and a soft 2-tone fill; a hit ripples over 4 frames.

## UI
- Chunky panels: dark slate fill `#1f2630`, 2 px light border `#cfd6df`, a 1 px inner highlight.
- A **pixel font**, white, 8 px source.
- Power bars are stacked green segments. Hull is a green-to-red bar, shield layers are blue pips, and weapon cooldowns are segmented bars.

## Lessons from studying real FTL: Multiverse sprites (lead, 2026-10-30)
These come from a human-made Multiverse add-on on GitHub (TCC). They're **for reference only, never copied or traced.**
- **Crew** are tiny, crisp silhouettes:
  - sheets of **35×35 frames, 8 columns**, with the figure only ~15–18 px tall inside each frame;
  - a **1 px near-black outline** around everything, the body in **2–3 tones of one hue**, limbs 1–2 px wide, the head 4–6 px;
  - rows: **walk 4 frames × down/up/left/right** (not mirrored), then action rows (repair, melee swings with a weapon line, shooting);
  - outfit colour sits on a **separate `_color` mask layer** that the game tints. We do the same: one base sheet, plus a colour mask for outfits and factions.
- **Hulls are the star**. Painterly pixel art with big planar panels, each in **3–4 tones**, dark panel-seam lines, chamfered silhouettes, decals and insignia.
  - Light strips (orange or teal) and engine glow live on a **separate `_glow` layer**; faction colour on a `_color` layer.
- **Floors** are one flat **cool grey silhouette** of the whole interior, with a **2 px near-black outline and chamfered corners**. The game draws rooms, walls and doors on top.
- **Room props**: small machine sprites (35×35 or 35×70) standing against walls. Muted greys and browns with a few lit indicator pixels; glow on its own layer.
- **Weapons** sit on the **hull edge** as small sprites with an **animated charge strip** (indicator lights fill up frame by frame as it charges), then fire frames.
- **Projectiles** are 4-frame strips: a bright 1–2 px core with a **soft alpha glow**. Soft glow is the one allowed exception to "hard pixels".
- **Explosions** are **flat 2–3 colour shapes** (white core, coloured body) that fragment over many frames (about 30). Bold and graphic, not realistic.
- **What this means for us**: restraint everywhere except hulls, lights and effects. A muted interior, crisp outlined crew, and rich hull exteriors. Every sprite gets optional `_glow` and `_color` layers.

## The approved look: our art bible (owner, 2026-10-30: "exactly what we are looking for", "so so good")
The reference sheets are in **`docs/art_reference/`**. Every new art agent reads these first and matches them.
- crew and species: `crew_species.png`;
- systems: `systems_v2.png` and `lines_reactors_engines.png`;
- shields: `shields.png`;
- workshop and belts: `workshop_belts.png`;
- weapons: `weapons_mounted.png` and `weapon_states_laser_mk1.png`;
- structure: `structure.png` and `shapes_hull_skin.png`.

**The recipe that works (keep it)**
1. **Made in code, pixel by pixel.** Each sprite is an ASCII map in a Python generator in `art/_src/`.
   - Every colour comes from the palette, and the rebuild is byte-identical.
   - `build.py` checks palette, frame sizes and glow sizes.
   - No noise, no maths gradients, no AI images.
2. **The shape of everything**: 16 px per cell, a 1 px near-black outline, light from the top-left, and a 3–4 tone steel ramp. Panel seams, bolts at the corners, and a few lit indicator pixels.
3. **Family colour** (light pixels and glow) is the same across every line:
   - reactor amber, engines orange exhaust, O2 green, shields blue;
   - weapons red/orange/teal by type, workshop violet, fabricator amber, belts neutral.
4. **Line language**:
   - **Scrap** has rust patches, hazard tape, bolt heads, weld seams, amber lamps and slight asymmetry.
   - **Standard** is clean and symmetrical, with a registry stencil; higher tiers add machinery.
   - **Neon** has navy panels, crisp 1 px cyan/magenta edges and crystal facets, with the glow carrying the light.
5. **States tell a story** (the v1 lesson: never one generic damage stamp):
   - `on` loops (2–8 frames; shields 8, with a 3-frame `hit` and a 4-frame `recharge`).
   - `off` has its lights dead.
   - `damaged` is specific to the object: this panel cracks, that cable hangs, and sparks come from one spot.
   - `disabled` is visibly broken: a split casing, a dead core, a snapped barrel.
   - **Outside mount halves are never shattered, only scorched and dented**, because they can always be repaired.
6. **Hull mounts** are an inside half and an outside half.
   - Each half has a 3–4 px flange overhanging its wall face (`offset`), with the wall drawn between them.
   - The barrel is its own sprite, drawn pointing up. Fixed guns have a long barrel braced in a sleeve; turrets have a ring base, a compact head and a sensor eye.
7. **Crew** are top-down layered rigs. **Every species uses the same arm mounts**, so any item fits any body. Outfits are tinted through `_color` masks.
8. **Shaped walls are pre-lit in all 8 orientations.** The game picks a frame and never rotates a lit sprite.
9. **Tiers grow by adding parts**: Mk2 adds a second accent, Mk3 extra machinery, Mk4 and Mk5 heavier housings, all in the same silhouette family. So a Mk5 reads as a big brother of the Mk1.
10. **Every art agent ships a labelled 3× preview sheet** with every frame and an assembled in-context view (mounted through a wall, in a room). The lead reviews it, and the owner sees it before merging.

**Palette budget**: 37 colours now. A new colour needs a reason and is registered in `px.py`/`pal_*.py`, never ad hoc. Stay under 48.

## Files
- `art/<area>/<id>.png` (crew in `art/crew/<species>_<outfit>.png` as sprite sheets), plus a JSON next to each sheet with frame size, frames per animation and fps.
- The game picks them up through `scripts/view/visuals.gd` (components), and through the crew and person drawers once they read sheets. Placeholders stay as the fallback.
