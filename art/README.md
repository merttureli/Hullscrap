# Art drop-in (format v1)

The game draws pixel art from this folder and falls back to flat code-drawn placeholders for anything missing, so art can be added one file at a time with no code change. The style law is `docs/ART_STYLE.md`; every file's source and licence goes in `ASSETS.md`.

**How it is read** (`scripts/view/art.gd`): each PNG is read from disk with `Image` + `ImageTexture` (no editor import needed, so headless runs and tests work) and cached for the session: restart the game after adding a file. A PNG with no JSON is one frame; the JSON next to it adds everything else. `scripts/view/sprite_sheet.gd` holds the frame maths. The project's default texture filter is **nearest**.

**Scale**: 1 grid cell = **16 source px**, drawn at 2 screen px per source px at zoom 1 (32 px per cell). Effects and projectiles are drawn at no fewer than 2 screen px per source px at any zoom.

## Folders
- `components/<component_id>.png` (+ `.json`): system sprites. The id is the `id` in `data/components.json`. A part with no art of its own borrows the next lower tier's (`engine_mk2` uses `engine_mk1`) until its own lands (`Art.tier_fallback`).
  - **Compact parts** (playtest 2, P2): the tier 1-2 weapons, engines, reactors and shields take less room inside the ship (`data/components.json`: 2x2 for a gun or engine breech, 2x4 for a reactor or shield). Their inside art is the original 64 px wide art cut to 32 px by `art/_src/compact.py` (the part's own edge columns plus the centre columns, then outline and shadow as usual; glow layers cut the same way; `SHIFT` / `KEEP` there move one part's window). The `_out` and `_barrel` art of guns and engines is unchanged. The medbay is drawn new at 2x4 (one bed).
- `crew/<species>/`: `legs.png`, `torso.png`, `arms.png`, `head.png`, each with a `_color.png` mask, plus `crew.json`.
- `gear/<id>.json` (+ `.png`, `_color`, `_glow`, `_legs`, `_arms`): the hand-made body gear of the human rig, drawn by `PersonDrawer` (`Art.gear`) on any rig with the human's anchors (`Art.gear_fits`: human, gauntling); `data/boarding.json` `looks.<item>.art` names the id. The spec's layers: `body` after the torso, `head` after the head, `legs` and `arms` replace the rig's; glow is additive.
- `gear/<art id>/<rig>.png` + `gear/<art id>/gear.json`: gear made for each rig from that rig's own torso, head, arm and leg sprites (`python3 art/_src/sp_wardrobe.py`, `--sheet <png>` writes a contact sheet): one strip of rig-frame cells (body, then one cell per head frame, per arm pose, per legs frame) of overlays in the item's palette, no colour mask and no glow. `Art.gear_rig(id, rig)` cuts the layers; `PersonDrawer.plan` draws body after the torso, sleeves after the arms, head after the same head frame, legs after the same legs frame. Every rig has art for the 14 new items; for the five old items only the rigs without hand-made art (every rig but human and gauntling) have a folder entry.
- `items/<id>.png` (+ `.json`): hand-held items (`pistol`, `rifle`, `wrench`, `extinguisher`).
- `tiles/`: `floor`, `walls`, `walls_armor`, `door`, `breach`, `cable` (+ `cable_on`).
- `fx/`: `fire`, `smoke`, `sparks`, `explosion`, `muzzle`, `shield_ripple`, `heat_shimmer`, `jump_spool`, `jump_flash`.
- `projectiles/<kind>`: `laser`, `beam` (hitscan, tiled along y, with `laser_impact` / `beam_impact` flares), `bolt`, `flak`, `missile`, `tractor_beam` (tiled along y).
- `debris/<id>.png` (+ `.json`, `_glow`): drifting sector debris (see "Sector space art" below).
- `ui/`: `poi_icons` (HUD icons for sector points of interest).
- `space/`: `stars_far`, `stars_mid`, `stars_near` (tiling parallax layers) and `nebula_<region>` (faint soft overlays).
- `palette.gpl`: the shared palette. Hard-pixel layers use only its colours; glow layers are soft alpha.

## Sprite JSON (one per PNG; every field optional)
```json
{"frame": [w, h], "cells": [cw, ch], "offset": [dx, dy], "orientation_rot": 0,
 "anims": {"on": [start, count, fps], "off": [1, 1, 0]},
 "glow": {"image": "<id>_glow.png", "frame": [w, h], "offset": [dx, dy], "anims": {"on": [0, 3, 6]}},
 "color_mask": "<id>_color.png", "anchors": {"muzzle": [x, y]}, "notes": "free text"}
```
- Frames sit in a **horizontal strip**, left to right; an animation is `[first frame, frame count, fps]` (fps 0 = a held frame). With no `frame` the whole image is one frame.
- Anchors are source px from the frame's **top-left pixel**.
- `glow` is its own strip, added over the sprite (**additively** in the interior and fights, through `scripts/view/glow_layer.gd`; plain alpha when no layer is at hand). `offset` places its frame against the sprite frame's top-left (negative = it spills over the edge). Its animations use the same names as the sprite's; the game falls back to the glow's `on`.
- `color_mask`: white where the outfit is; the game multiplies the base by the colour there (crew suits, tinted armour). The mask defaults to `<id>_color.png` when that file exists.
- `orientation_rot`: quarter turns clockwise added to the part's own rotation, for art not drawn facing the game's rotation 0. Even values keep the footprint; odd ones turn the art against it, so only use them when the art is authored for the swapped footprint.

## Components
- Drawn at the footprint (`cells` = its size in `data/components.json`), turned with the part's `rot`, 16 source px per cell. A sheet with a JSON is drawn at `cell / 16`; a bare PNG is stretched over the footprint.
- **Animation by state**, the game picking in this order (a missing name falls back to the next line):
  1. disabled (hp 0 or status disabled): `disabled`, else the `off` frame dimmed with `fx/smoke` over it;
  2. a consumer with no power: `off`, with no glow;
  3. malfunction: `malfunction`, else a flicker between `on` and `off`;
  4. overheated: `overheated`, else the normal frame with a red pulse and `fx/heat_shimmer`;
  5. a weapon: `fire` for 0.15 s after a shot, else `charge` by the cooldown (frame `round(fraction * (count - 1))`; the last frame is READY, so a weapon at rest shows it);
  6. under half hp: `damaged`, else `fx/sparks` (or code-drawn specks) over the normal frame;
  7. `on`, looping.
- The game still draws the **heat bar**, the **hp pips**, the "!" for overheating and the gear for a malfunction on top. Do not paint them.
- Orientation of the shipped art: the engine has its nozzles on the **west** end and the laser its muzzle on the **east** end at rotation 0 (both landscape 4x2). The starter ships place engines and lasers at rot 0, so their exhaust and muzzles point sideways; turn them with `R` (an engine at rot 3 exhausts down the ship, a laser at rot 3 points up) or set `orientation_rot` once the footprints are decided.

## Crew (`crew/<species>/crew.json`)
Top-down and layered; every layer faces UP at rotation 0 and shares one frame (`frame`) rotated about `pivot`.
- `legs` (rotated to the **movement** direction; `walk` frames advance with the distance walked, `stand` when idle); `torso`, `arms`, the held `item` and `head` (rotated to the **aim**: the mouse for the player, the job's target or the way they walk for the others).
- `arms` has a pose per item class (`frames`: `unarmed`, `pistol`, `rifle`, `tool`) and a `mount` anchor per pose; an item's top-left goes at `mount - item.grip`. `head` has `hair` and `helmet` frames.
- Colour masks tint the outfit with the crew member's `suit` colour (cached per colour). A 1 px shadow is drawn in code.
- Species rigs: `human`, `basalt`, `emberkin`, `fenn`, and race wave 1 `kett`, `mire`, `sporeling`, `gauntling`, `prismatic`, `grundl` (waves 2, 3 and 4 below) (`python3 art/_src/build_all.py` rebuilds them; `python3 art/_src/build.py` checks palette, sizes and that every mount sits where the human's does, relative to the pivot).
  - **Large rig (`grundl`)**: its `frame` is 49x49 with `pivot` (24,24), so read both from `crew.json` and never assume 33/16. The art overhangs the 2x2 body (32 px); the shadow and pathing stay at the pivot. Every `mount` and `hand` anchor is the shared one moved by (+8,+8): identical relative to the pivot, so the same item formula (`mount - item.grip`, then rotate about the pivot) puts every item in the right place.
  - **Rig kinds (race wave 2)**: `crew.json` may carry `"kind"`: `normal` (the default when absent), `large`, `small` or `floating`. The kind fixes the frame, the pivot and what the drawer does (`scripts/crew/person_drawer.gd`). In EVERY kind the arms `mount` anchors are the human's moved by `pivot - (16,16)`, i.e. identical relative to the pivot, so any item fits any body; `hand_*` anchors are art only (keep them inside the frame). Never assume 33/16: read `frame` and `pivot` from `crew.json`.

    | kind | frame | pivot | body and pathing | the art | used by |
    |---|---|---|---|---|---|
    | `normal` | 33x33 | (16,16) | 2x2 cells (32 px) | fills the 32 px body | human, basalt, ... |
    | `large` | 49x49 | (24,24) | still the 2x2 body; shadow and pivot at the 2x2 centre | overhangs the body | grundl, drakkin, murrow, brine |
    | `small` | 25x25 | (12,12) | 1x1 cell (the trait `body` 1: 16 px); the pivot is the cell centre | legs, torso and head inside the central 15x15 (pivot +-7) so it fits a 1-wide crawlspace; only the arms may reach beyond it, to the shared mounts (at most 12 px ahead, 7 to the side) | vellum, rattler, tessellate_half |
    | `floating` | 49x49 | (24,24) | the 2x2 body | no legs: the `legs` layer is the TRAILING TAIL (drawn pointing back, i.e. down at rotation 0, and turned to the movement direction, so it streams behind a mover); the torso and head are the body; the tail may run to the frame edge (24 px behind the pivot, 8 px past the 2x2 body) | wisp, lantern (gliding), siltborn |

    - `legs` anims for `floating`: no `walk`. A `float` anim (a flowing tail, any frame count and fps, played by time) and a `stand` frame (used when there is no `float`). The drawer ignores `walk` on a floating rig and never advances it with distance.
    - The drawer bobs a `floating` body: every layer but the shadow rides up and down about 1.5 source px (a slow sine of time), and the shadow sits 1 px further away (it hovers). Do not bake a bob into the frames.
    - `small` and `large` have no special drawing: the same `walk` / `stand` legs, `pistol`/`rifle`/`tool`/`heavy`/`melee`/`unarmed` arm poses and `hair`/`helmet` heads as the human, on the smaller or bigger frame. A `small` figure is drawn at the same 16 px per cell as everything else, so it is half a normal body wide.
  - `kett` has four arms: the lower pair is small, tucked, and drawn into every arms pose. The glow layers of `sporeling` (spore puffs, 2 drifting frames), `gauntling` (lamp eye, lit LEDs) and `prismatic` (core and lit edges, 2 pulse frames) are multi-frame strips: `torso_glow` carries `anims.on`, `head_glow` lists one frame per head variant per step (see its notes for the fps).
  - Preview sheet: `python3 art/_src/sheet_races1.py out.png`.
- Held item: a wrench while repairing, an extinguisher while extinguishing (the wrench if there is no extinguisher art), a pistol for the player with nothing to do, nothing otherwise.
- **Race wave 2** (`vellum`, `oorth`, `drakkin`, `wisp`, `hullkin`, `lantern`; generator `art/_src/sp_races2.py`, preview `python3 art/_src/sheet_races2.py out.png [lineup.png]`): `crew.json` carries `kind` (`small` 25x25 pivot (12,12), `large` and `floating` 49x49 pivot (24,24); none = normal 33x33 pivot (16,16); `PersonDrawer.RIGS`). The mounts are the human's moved by `pivot - (16,16)` in every kind. No palette colour was added.
  - `vellum` (**small**, 25x25): legs, torso and every head inside the central 15x15 (pivot +-7); only the long thin paper arms reach out to the mounts; the `hand_*` anchors are art only (the validator, `art/_src/build.py`, only checks them against the frame). Heads `fold`, `cap`, `helmet`.
  - `oorth` (normal): a robe whose train is in the legs layer and sways with the walk; `head_glow` pulses the third-eye ridge (2 frames per head, ~2 fps). Heads `hood`, `bare`, `helmet`.
  - `drakkin` (**large**, 49x49): the tail is in the legs layer and swishes with the walk. Heads `crest`, `helmet`, `scarred`.
  - `wisp` and `lantern` (**floating**, 49x49): no `walk`. The `legs` layer is what trails behind the body (the Wisp's helix glow tail to the frame edge, the Lantern's hanging legs and fluttering wing tips), `float` = frames 0-5 (a closed loop, played by time), `stand` = frame 6. The torso, head and arms are the normal body drawn in the middle of the frame, so the drawer's bob is not baked in. Glow layers: Wisp torso (2 flicker frames), head and legs (one per legs frame); Lantern wing eye-spots and antenna lamps (2 pulse frames). Heads: Wisp `orb`, `forked`; Lantern `antennae`, `goggles`, `helmet`.
  - `hullkin` (normal): a ridged shell trails behind the head and the eye-stalk is held off to one side so it never covers a held item. Heads `stalk`, `twin`. The Wisp and the Hullkin have no `helmet` frame (frame 0 is worn).
- **Race wave 3** (`revenant`, `choir`, `rattler`, `tessellate`, `tessellate_half`, `sable`, `quillback`, `kite`; generator `art/_src/sp_races3.py`, preview `python3 art/_src/sheet_races3.py out.png [lineup.png]`): no new rig kind and no palette colour; every mount is the human's moved by `pivot - (16,16)`. Normal rigs (33x33): `revenant`, `choir`, `tessellate`, `sable`, `quillback`, `kite`. Small rigs (25x25, pivot (12,12), body inside the central 15x15): `rattler` and `tessellate_half`.
  - `tessellate` is a swarm: every bot is a 2x2 block with a 1 px GAP of floor between neighbours, and the outline is drawn only round the outside of the swarm (`swarm_outline`), so the gaps are transparent in the PNGs. `tessellate_half` is the same swarm in the 1x1 body of the trait `split_on_death` (a second rig: use `rig: "tessellate_half"` for the two small bodies); it has the same head names, outfit mask and 4x4 lattice. Heads for both: `swarm`, `visor`, `helmet`.
  - `quillback`'s quills flare as an arm pose: the torso layer is one frame (the validator and the drawer take one), so the `melee` pose of the arms layer also carries a full sunburst of longer quills round the back and sides (the front 80 degrees stay clear). Every other pose shows the quills at rest, swept back in the torso layer. The drawer already draws arms over the torso and the item and head over the arms, so showing the flare needs no code: pick the `melee` pose (the ember knife, their sidearm, is one). Heads `crest`, `helmet`, `scarred`.
  - `revenant`: the hose that dangles behind is in the legs layer (it sways with the walk); `head_glow` has 2 frames per head (faint cold eyes, ~1 fps). Heads `bare`, `hood`, `helmet`. `choir`: `torso_glow` 2 frames (resonance in the rose hole, ~2 fps) and `head_glow` (the singer's open mouth). Heads `singer`, `mitre`, `helmet`. `rattler`: heads `goggles`, `pushed`, `helmet`. `sable`: a cutter torch on each forearm with a small blue-white flame in the arms layer (hard pixels, no glow layer); heads `bare`, `hood`, `helmet`. `kite`: the prehensile tail is in the legs layer; heads `wide`, `goggles`, `helmet`.
- **Race wave 4** (`warden_frame`, `murrow`, `siltborn`, `corvin`, `brine`, `echo`, `ferro`; generator `art/_src/sp_races4.py`, preview `python3 art/_src/sheet_races4.py out.png [lineup.png] [--only=name,name]`): completes the roster at 30. No new rig kind and no palette colour; every mount is the human's moved by `pivot - (16,16)`. Normal rigs (33x33): `warden_frame`, `corvin`, `echo`, `ferro`. **Large** (49x49, pivot (24,24)): `murrow`, `brine`. **Floating** (49x49, no walk, `float` 6 frames + `stand`): `siltborn`.
  - `warden_frame`: a rebuilt Lumen drone: navy panels with cyan edge lines, a delta chassis with two swept fins, ONE magenta lens (`head_glow`, 2 frames ~2 fps; `torso_glow` lights the neon lines). The left pauldron is a mismatched steel plate. Heads `lens`, `hood`, `helmet`.
  - `murrow` (large): dusty velvet fur, a snout with a pink star-nose, huge spade claws (a spread pair when unarmed, a smaller grip drawn a little WIDER than the anchors when holding an item so the claws show beside the snout), miner's harness, ore sack. `head_glow` is the headlamp of the `lamp` and `helmet` heads. Heads `snout`, `lamp`, `helmet`.
  - `siltborn` (floating): a frilled translucent bell with an amber gas sac (head layer); the legs layer is a skirt and five wavy tendrils (`float` = frames 0-5 played by time, `stand` = frame 6, `legs_glow` per frame). The sling across the bell is the outfit. Heads `crown`, `bloom`, `helmet` (a bubble helm).
  - `corvin`: a blue-black feather cloak with a ragged hem and pointed wing tips, an amber beak, a tail-feather fan in the legs layer, pouches and shiny trinkets. Heads `beak`, `loupe` (glow on the glass), `helmet`.
  - `brine` (large): a crab: a carapace with spines, three jointed legs a side in the legs layer, eyestalks (head layer), ONE big pincer on the right arm (its gap is centred on the item's `mount`, so it straddles the held item) and a small claw on the left. Heads `stalks`, `goggles`, `helmet`.
  - `echo`: a chrome mannequin shaded like a mirror ball (sky, a hard horizon, ground, violet bounce); two ripples trail behind in the legs layer. The shimmer is `torso_glow` and `head_glow` with 4 frames at ~4 fps (a diagonal sheen sweeping the body). Heads `smooth`, `mimic` (a faint face), `helmet`.
  - `ferro`: a gunmetal ferrofluid urchin: a lattice of cones and a ring of long spikes, spike-finger hands, cyan eyes; `torso_glow` and `head_glow` have 3 frames at ~4 fps (spark arcs between spike tips). Heads `crown`, `ripple`, `helmet`.

## Tiles, effects, projectiles
- `walls` and `cable` are **mask4 autotiles**: 16 frames, index = N*1 + E*2 + S*4 + W*8 over the neighbours that are solid (walls; doors count) or cable. Materials other than the plain `wall` use `walls_armor` multiplied by their colour (else `walls` pulled toward it). `cable_on` is the powered version (a network with supply), with `cable`'s glow.
- `floor`: variants chosen by cell, the first (`v0`) for about 10 of 16 cells. `breach`: a variant per cell.
- `door`: 32x16 (a 2-cell piece, turned for a vertical wall); frames 0-4 are `open`, played toward open or closed as the door moves; the glow frame matches the door frame.
- `fx/fire`: a flame standing on the cell's bottom edge, scaled by the intensity. Effects play their first animation (`play` once, `loop` repeating); `anchors` name the pixel placed on the spot (`muzzle`, `impact`, `center`, `base`). `muzzle` and `shield_ripple` face up and are turned to the shot.
- Projectiles face up; the `head` (else `center`) pixel sits on the projectile and the sprite turns to its velocity. A hitscan `laser`/`beam` is tiled along y from the weapon to the hit, with the `<kind>_impact` flare at the end.

## Adding or changing art
1. Drop the PNG (and JSON) in the folder above, log it in `ASSETS.md`.
2. `godot --headless --path . --script res://tests/run_tests.gd`: `test_every_shipped_sheet_is_consistent` checks every JSON's animations against its frame count.
3. Tests use their own tiny images in `tests/fixtures/art/`; the loader's root is `Art.root`.

## Shaped walls, ram plating and the hull skin (`art/tiles/`)

Geometry is in `tiles/shapes.json` (cell-local 0..1, y down, rotation 0; see `docs/CONTENT.md` 4d). Every sheet is a grid: 16 columns (autotile mask) and, for shaped cells, 56 rows = `orient * 7 + cell`, where `orient = mirror*4 + rot` and the cell order is in each JSON (`rows.cells`). Rows 0-6 are rotation 0. Every orientation is drawn already (lit from the top-left), so the game picks a frame and never rotates a sprite.

- `walls_shapes`, `walls_armor_shapes` (tinted like `walls_armor`), `walls_ram_shapes`: mask bit = that neighbour is solid (same as `walls.png`). `walls_ram.png` is the 16-frame full cell. Ram plating has fixed colours, no tint.
- `hull_skin` (16 mask frames x 4 panel variants), `hull_skin_shapes` (same grid as the wall shapes), `*_glow` (neon edge glow, 22x22 frames drawn at offset -3,-3), `hull_skin_decals` (+ glow): **mask bit = that side faces open space**, not "solid neighbour". Neutral greys, multiply a tint per line (`suggested_tints` in `hull_skin.json`).
- `python3 art/_src/build.py` regenerates everything and runs the checks; `python3 art/_src/preview_shapes.py out.png [components dir]` draws the preview sheet.

## Weapons (hull mounts, in three files each)
A weapon straddles the hull wall, so it is drawn as two halves plus a rotating barrel. Outward is UP at rotation 0. Generator: `art/_src/comp_weapons.py` (`python3 art/_src/build_weapons.py`); preview: `python3 art/_src/sheet_weapons.py [out.png] [ids]`.
- `<id>.png` + `.json`: the INSIDE half, on the floor against the inner wall face (which is above it). Footprint `cells` [4,2]; the frame is 64x36 with `offset` [0,-4]: its top 4 px are a mounting flange that overhangs the wall face. Anims `on` (2), `off`, `charge` (6, the charge strip or the weapon's own charge indicator; frame 5 = ready), `fire` (2, a discharge flash then dark), `damaged` (2), `disabled`. Breech, capacitor, power coupling (cable stub at the left edge), repair hatch, and for ammo weapons a feed chute to the right edge where an `ammo_rack` sits.
- `<id>_out.png` + `.json`: the OUTSIDE half, in space against the outer wall face (which is below it). `cells` [4,2] (heavy `shrapnel_cannon_scrap`: [4,3], frame 64x52; the data layout assumed here is outside 3 rows, wall 1, inside 2); the bottom 4 px are a flange that overhangs the wall. Anims `on` (2), `off`, `damaged` (2), `disabled` (2, scorched, dented, ring cracked, sparking: broken but fixable, never shattered). `anchors.pivot` is where the barrel turns, in this frame. Its JSON also holds a `barrel` block (the same data as `<id>_barrel.json`).
- `<id>_barrel.png` + `.json`: the rotating barrel or head, drawn pointing UP. Anims `idle`, `fire` (3: recoil 2/1/0 px and a muzzle flash), `damaged` (2), `disabled` (bent or snapped). `anchors.pivot` (the turning point) is placed on the outside half's `pivot_on_base`; `anchors.muzzle` is the tip. `aim` is `fixed` (aimed by pointing the ship; the barrel only gimbals `gimbal_deg` degrees and recoils; a long straight barrel braced in a sleeve) or `turret` (swivels in its ring within the arc: compact head, short barrel, sensor eye). The barrel has no baked drop shadow (it rotates). Glow layers: `<id>_glow`, `<id>_out_glow`, `<id>_barrel_glow` (fire flash).
- Fixed: laser_mk1, laser_mk2, pulse_mk1, pulse_mk2, artemis_mk1, ion_blast_mk1, shrapnel_cannon_scrap, bolt_thrower_scrap, heat_lance_neon, breach_harpoon. Turrets: laser_turret_mk1 (the Concord Point Turret), rattle_burst_scrap, siren_ion_neon, leech_laser.
- `ammo_rack.png` (2x2, 32x32): anims `fill_0..4` (missiles, also `on` = full), `scrap_0..4`, `slug_0..4`, `damaged` (2), `disabled`, `wrecked`.
- `tiles/wreck.png`: a 16x16 debris decal, 4 variants (scorched floor, twisted plate, loose cables, burnt scrap).

## Sector space art ("Raft in space", `docs/CONTENT.md` section 11)
Generator: `art/_src/sector_all.py` (`debris.py`, `comp_salvage.py`, `comp_radar.py`, `comp_tractor.py`, `sector_fx.py`, `poi_icons.py`, `space_bg.py`); `build_all.py` rebuilds it all, `python3 art/_src/sector_all.py` just this set, and `python3 art/_src/sheet_sector.py out.png` draws the 3x preview sheet. Palette: 8 colours were added at the end of `palette.gpl` (45 in all): copper `T` `Y`, ice `i` `z`, polymer `k`, titanium `x` `t`, tractor mint `h`.

**Drifting debris** (`debris/<id>.png`, 1 px near-black outline, lit from the top-left in every frame, no baked shadow: it floats in space). Anim `tumble` = 4 frames (the piece turned by the degrees in `tumble_deg`; `loop` is `wrap` (1,2,3,4,1...) for the near-round pieces, `pingpong` for the long ones: barrel, canisters, plate); the game may also turn the node. Anchor `center`. `glow` (additive, 16 px bigger all round, offset -8,-8) on `crystal_shard`, `plasma_canister` and `fuel_canister`.
| id | frame | material cue | extras |
|---|---|---|---|
| `scrap_chunk_s` / `_m` | 16x16 / 24x24 | grey steel, rust patches, hazard tape | |
| `copper_coil` | 16x16 | copper orange windings, a steel clip | |
| `polymer_barrel` | 16x24 | white-blue drum, steel hoops, amber label | |
| `ice_chunk_s` / `_m` | 16x16 / 24x24 | pale cyan facets, frost glints | |
| `titanium_plate` | 24x16 | cool grey with a diagonal sheen | |
| `silicon_rock` | 24x24 | dark rock with glassy faces | |
| `crystal_shard` | 16x16 | saturated cyan prisms | glow |
| `plasma_canister` | 16x24 | steel bottle, magenta plasma window | glow |
| `sealed_crate` | 24x24 | brown crate, steel corners, amber seal | `broken` (frame 5) |
| `ore_rock_s` / `ore_rock_l` | 24x24 / 48x48 | brown rock, craters, vein specks (copper, iron, titanium, crystal) | `cracked_1`, `cracked_2` (`cracked` = both) on `ore_rock_l` |
| `dead_drone` | 24x24 | grey quad-rotor, one arm snapped, amber plate | |
| `fuel_canister` | 16x24 | amber jerrycan, red cap, glowing gauge | glow |
| `fragment` | 8x8 | neutral greys: multiply a material tint | 4 variants, anims `v0`..`v3` |

**Salvage intakes** (hull mounts, the weapon two-halves format, NO barrel): `net_mouth_scrap` (2x2 + 2x2, frames 32x36), `intake_mk1`, `_mk2`, `_mk3`, `lumen_siphon_neon` (4x2 + 4x2, frames 64x36). Outward is UP, offsets and flanges as for weapons.
- `<id>_out` (the mouth): anims `on` (2), `pulling` (6, 10 fps), `off`, `damaged` (2), `disabled` (2). `pulling` lights the coils and slides bits down the ribs; the magnetic shimmer (mint wavefronts closing on the mouth, cyan for the Lumen Siphon) is in `<id>_out_glow.png`, whose frame is TALLER than the sprite (its JSON `offset` is [-8, -N] with N = 20..48: the pull radius made visible). Use the glow's `pulling` anim (the game falls back to its `on` otherwise).
- `<id>` (the hopper): anims `on` (6, bits drift to the belt), `pulling` (6, busy), `off`, `damaged` (2), `disabled`. Outside mouths are only ever scorched and dented.

**Radars** (hull mounts, weapon format, rotating dish as the `_barrel`): `radar_mk1` (inside 2x2), `radar_mk2`, `radar_mk3`, `lumen_eye_neon` (inside 4x2), `listening_horn_scrap` (inside 2x2); every outside base is 2x2 (frame 32x36, `cells` [2,2] in `<id>_out.json`). The inside console `on` is an 8-frame SWEEP on its screen (a line turning one step per frame, blips lighting as it passes; `damaged` glitches, `disabled` is dead). `<id>_barrel.png` is the dish drawn pointing UP; JSON `aim` is `"spin"` (turns continuously, the game sets the speed), `anchors.pivot` goes on `pivot_on_base` of the `_out` half. Barrel anims: `idle` (2, a blinking lamp), `damaged` (2), `disabled`.

**Tractor Beam turrets** (`tractor_mk1`, `tractor_mk2`, turret format as `laser_turret_mk1`, 4x2 + 4x2): anims as a turret; `fire` = the beam is ON (the strip pulses; the head `fire` = 3 frames, the coil rings light mint one by one and wavefronts leave the lens, no recoil). The beam is `projectiles/tractor_beam.png`: 12x16, 4 frames (`pull`, 12 fps), tiled along y from the turret (tail) to the debris (head), shallow V-shaped waves crawling toward the turret; glow `tractor_beam_glow.png` tiles too. No impact flare.

**HUD icons** `ui/poi_icons.png` (+ `_glow`, 24x24 frames at -4,-4): 16x16 per type, anim name = POI type: `station`, `store`, `trader`, `distress`, `wreck`, `abandoned_station`, `mining_field`, `unknown`, `pirate_nest`, `concord_checkpoint`, `anomaly`, `quest`, `contact` (an unidentified radar contact), `course` (the set-course marker). Family colours: distress red + amber, quest gold, Lumen cyan, Concord blue, pirate red.

**Space backdrop** (`space/`, transparent, soft alpha: the one place soft gradients are allowed): `stars_far`, `stars_mid`, `stars_near` are 256x256 and TILE on both axes (draw repeated, offset by camera x `parallax` 0.04 / 0.12 / 0.35); `nebula_clan`, `_concord`, `_lumen`, `_boneyard`, `_gate` are 512x512 faint overlays in palette greys (at most 52..76 of 255 alpha, edges fade to nothing): multiply the `suggested_tints` of their JSON over them (clan rust, Concord blue-grey, Lumen cyan-violet, Boneyard murky olive, gate pale) and draw them big, behind the ship.

**Jump drive** `fx/jump_spool.png` (64x64, 8 frames: a ring of light tightening, 1 fps over the 8 s spool, or stretch it to the timer) and `fx/jump_flash.png` (96x96, 6 frames at 14 fps: spark, white-out with a vertical streak, expanding shock ring, sparkles), each with a `_glow`.

## Racial tech (docs/waves/racial_tech_1.md)

### Group b: Mire, Sporeling, Gauntling, Prismatic, Grundl
Generators: `art/_src/tech_<race>.py` (one module per race, on top of `tech_kit.py`), `tech_proj.py` (projectiles and impacts), `tech_b.py` (the lists `build_all.py` reads); `python3 art/_src/build_tech_b.py` builds just these, `python3 art/_src/sheet_tech_b.py out.png` draws the preview (run the build first). No palette colours were added. Each race has one visual signature: **Mire** wet green-teal, brass pipes, red hand-wheels, steam; **Sporeling** grown cream and brown housings, violet spore sacs, gills; **Gauntling** mismatched scrap, copper coils, cyan arcs; **Prismatic** faceted violet crystal with cyan and magenta light cores; **Grundl** dark riveted freight metal, amber stencils, chains.

**Weapons**: the standard hull-mount format of "Weapons" above (inside half `<id>.png`, outside half `<id>_out.png`, `<id>_barrel.png`, each with its `_glow`; frames 64x36, `cells` [4,2] for both halves; anims `on`, `off`, `charge` (6), `fire`, `damaged`, `disabled`; barrel `idle`, `fire` (3), `damaged`, `disabled`). The charge strip is the race's own indicator (Mire water-gauge tubes, Sporeling spore sacs, Gauntling copper coils, Prismatic crystals, Grundl amber lamps); frame 5 is READY in every one. The ammo weapons (`sporeling_rot_pod`, `gauntling_scrap_shotgun`, `grundl_slug_mortar`, `grundl_barge_flak`) have a feed chute at the right edge of the inside half where an `ammo_rack` sits; `grundl_slug_mortar`'s charge animation shows the slug rolling in.
| id | aim | what it is |
|---|---|---|
| `mire_steam_lance` | fixed | long teal lance with a brass nozzle, boiler tank and red hand-wheel |
| `mire_bog_mortar` | fixed | squat mortar with a flared brass mouth, bubbling slurry vat |
| `mire_mist_projector` | turret | head with a fan of three brass spray nozzles |
| `sporeling_spore_cannon` | fixed | fleshy ringed tube, spotted bell mouth, violet spore sacs |
| `sporeling_rot_pod` | fixed (missile) | claw cradle holding a violet rot pod, pod nursery |
| `sporeling_pollen_turret` | turret | flower head, pink petals round a yellow stamen nozzle |
| `gauntling_arc_hammer` | fixed | ram tube with copper windings and a battered hammer head with two ball electrodes |
| `gauntling_scrap_shotgun` | fixed | two sawn-off pipes (steel and rust), junk hopper |
| `gauntling_tesla_picket` | turret | copper-wound Tesla coil topped with a steel ball |
| `prismatic_prism_lens` | fixed (beam) | violet tube, focusing lens ring, glass prism at the tip |
| `prismatic_refractor` | fixed | short barrel with a big faceted crystal head |
| `prismatic_glimmer_turret` | turret | ring head with a floating crystal and two orbiting shards |
| `grundl_slug_mortar` | fixed | massive banded barrel, rack of fat slugs, hoist chain |
| `grundl_grapple_harpoon` | fixed | launch tube with a barbed harpoon and chain winch |
| `grundl_barge_flak` | turret | four fat banded barrels, ammo drum with a chain belt |

**Components** (plain sprites, anims `on` (4 or 6 frames), `off`, `damaged` (2), `disabled`; engines are two halves):
| id | cells | notes |
|---|---|---|
| `mire_rain_shield` | 4x4 | shield: a ripple spreads from a drop, rain falls, corner valves |
| `mire_wetwell_reactor` | 4x4 | reactor: amber core under water, bubbles, steam vents |
| `mire_spray_deck` | 2x2 | utility: drain grate, four spray heads |
| `sporeling_bloom_reactor` | 4x4 | reactor: a flower blooms round an amber core |
| `sporeling_mycelium_shield` | 4x4 | shield: a mycelium web, blue nodes pulse |
| `sporeling_garden_bay` | 2x2 | O2: planter with mushrooms, a sprout and rising bubbles (the O2 family is 2x4 elsewhere, so set `size` to [2,2] or ask for a 2x4 redraw) |
| `gauntling_arc_core` | 4x4 | reactor: copper ring round a steel ball, arcs to four corner posts |
| `gauntling_overclock_engine` + `_out` | 4x2 + 4x2 | engine: two mismatched bells with copper coils and an arc between them (`on` 3 frames; anchors `exhaust_left`, `exhaust_right`) |
| `gauntling_graft_bay` | 4x4 | utility: work table, two robot arms welding a limb, spares rack |
| `prismatic_lattice_shield` | 4x4 | shield: two nested diamond lattices round a crystal (`on` 6 frames) |
| `prismatic_song_reactor` | 4x4 | reactor: a singing crystal, rings of light spread out (`on` 6 frames) |
| `prismatic_resonance_helm` | 2x2 | helm: console, cushion seat, a humming crystal |
| `grundl_hauler_thrusters` + `_out` | 4x2 + 4x2 | engine: two huge riveted bells, strapped fuel cells (anchors as above) |
| `grundl_freight_shield` | 4x4 | shield: a blue disc in a heavy cage, four fuel-cell lamps, chains |
| `grundl_cargo_deck` | 4x4 | utility: crates, shell rack, a hoist with a swinging hook |

**Projectiles and impacts** (`projectiles/<weapon id>.png` + `.json` + `_glow.png`, and `<weapon id>_impact.png` + `.json` + `_glow.png`; the `.json` of a projectile also carries an `impact` block). Hard pixels use the base palette only; the glow layers are palette hues.
- **Bolts** (face up, anim `fly`, anchors `head` and `tail`): `mire_bog_mortar` (green glob), `mire_mist_projector` (white mist), `sporeling_spore_cannon` (spore ball), `sporeling_rot_pod` (spotted pod, spore thread), `sporeling_pollen_turret` (pollen grains), `gauntling_arc_hammer` (slug in cyan arcs), `gauntling_scrap_shotgun` (six scrap pellets), `prismatic_refractor` (crystal shard), `prismatic_glimmer_turret` (crystal dart), `grundl_slug_mortar` (heavy slug with smoke), `grundl_grapple_harpoon` (barbed head with its chain; the tether is the tiling `grundl_grapple_harpoon_chain.png`, anim `clank`), `grundl_barge_flak` (steel shell).
- **Beams** (tile along y like `beam`, 8 px wide, 16 long, 3 flicker frames; use one tile if the weapon is a bolt kind): `mire_steam_lance` (steam jet), `gauntling_tesla_picket` (lightning thread), `prismatic_prism_lens` (white core, cyan edges, magenta fringe).
- **Impacts** (anim `play`, once, anchor `center`): 16x16 and 3 or 4 frames, except `grundl_slug_mortar` 24x24 x5 and `grundl_barge_flak` 20x20 x4.
Each race's parts share one visual signature that reads at 1x. Generators: `art/_src/techa_<race>.py` (group a: human, basalt, emberkin, fenn, kett), shared pieces in `techa_kit.py`, export + preview in `techa_all.py` (`build_all.py` calls `techa_all.export_all()`; `python3 art/_src/techa_all.py preview out.png` draws the preview). No palette colour was added: every part is drawn with existing palette letters. The ids below are the ones the data pack must use.

**Group a: human, basalt, emberkin, fenn, kett.** Ship weapons are the usual three files (`<id>`, `<id>_out`, `<id>_barrel`, all 4x2 + 4x2 cells, outward is up); engines are two halves (`<id>` core 4x2, `<id>_out` nozzles 4x2); the rest are plain sprites. Every component has `on`, `off`, `damaged` (2) and `disabled`; shields also `hit` (3) and `recharge` (4) like `shield_mk2`; weapons also `charge` (6, frame 5 = ready) and `fire`. Each weapon id also has `projectiles/<id>.png` and `projectiles/<id>_impact.png` (+ `_glow` layers, one JSON each; the projectile JSON carries the `impact` block like `laser.json`).
| race | signature | ship weapons (fixed / turret) | components |
|---|---|---|---|
| human | Concord clean steel, blue accent, Clan amber | `human_volley_rack` (fixed, missile), `human_concord_railgun` (fixed), `human_flak_screen` (turret) | `human_reactor_plus` (reactor 4x4), `human_comms_array` (utility 2x2), `human_crew_quarters_deluxe` (utility 2x2, the bed) |
| basalt | rough stone, glowing magma seams | `basalt_magma_spitter` (fixed), `basalt_quarry_driver` (fixed), `basalt_pumice_flak` (turret) | `basalt_vacuum_forge` (reactor 4x4), `basalt_stonehide_bay` (utility 2x2), `basalt_gravity_anchor` (utility 2x2) |
| emberkin | brass and fire, flame vents, navy enamel | `emberkin_pyre_lance` (fixed, beam), `emberkin_cinder_mortar` (fixed), `emberkin_flare_turret` (turret) | `emberkin_pyre_drive` (engine, two halves), `emberkin_furnace_core` (reactor 4x4), `emberkin_hearth_shield` (shield 4x4) |
| fenn | delicate cream panels, antennas, many small parts | `fenn_twitch_cannon` (fixed), `fenn_spark_lattice` (turret), `fenn_market_missile` (fixed, missile) | `fenn_haggle_engine` (engine, two halves), `fenn_jury_reactor` (reactor 4x4), `fenn_quickfix_bay` (utility 2x2) |
| kett | amber chitin plates, hive cells, drone bays | `kett_hive_swarm_launcher` (fixed, missile), `kett_chitin_thrower` (fixed), `kett_drone_picket` (turret) | `kett_hive_battery` (shield 4x4), `kett_nest_reactor` (reactor 4x4), `kett_brood_hold` (utility 2x2) |
- Projectile art per weapon id (`projectiles/<id>`, anim `fly`, faces UP, anchors `head` and `tail`; the impact anim `play` is a one-shot, anchor = its centre): slag, rock slug, pumice rock (basalt); a tiling flame stream for the Pyre Lance (`tile: y`, 8x16, glow tiles too), a cinder shell, a flare (emberkin); a tiny bolt, spark splinters, a scrap missile with confetti (fenn); a drone swarm, chitin needles, an interceptor drone (kett); a small missile, a blue-white rail slug with a Concord rail flash, a flak tracer (human). `emberkin_pyre_lance` is a beam: draw it tiled from the lance to the hit, like `beam`.
- Sizes worth knowing: `human_crew_quarters_deluxe` is 2x2 (a bunk pod), not the 2x4 of `bed`. Long barrels are drawn long: `basalt_quarry_driver` 72 px, `human_concord_railgun` 74 px, `emberkin_pyre_lance` 74 px (the barrel sprite may extend far above its outside half; the muzzle is in the JSON `barrel.muzzle`).
- Engines: `emberkin_pyre_drive` breathes a hard-pixel flame over its bell (3-frame loop) and `fenn_haggle_engine` has four small nozzles; anchors `exhaust`/`exhaust_a..d`, `power_coupling`, `repair_hatch` are in the JSONs as for the other engines.

### Guns in their new shapes (gun rework, docs/GUNS.md 3, 7 and 8)
Generator `art/_src/gun_recipes.py` (one recipe per gun, from the modules of `gun_mod.py` and the race signatures of `gun_race.py`; `build_all.py` and `build_weapons.py` run it last, so it overwrites the older `_out` / `_barrel` files); sheets `python3 art/_src/gun_sheets.py [out_dir] [old_components_dir]`. It writes only `<id>_out.*` and `<id>_barrel.*` (png, json, glow); the inside half `<id>.png` is not touched.
- **Outside half** `<id>_out.png`: W x (cells high * 16 + 4) px (the bottom 4 px are the flange over the wall face), `cells` is the shape's outside size (point 2x2, dome 3x3, sponson 3x2, casemate 4x2, long 2x4, broadside 6x2, strip 8x1, heavy 4x3, spinal 2x6, pod 4x1). Anims `on` (2), `off`, `damaged` (2), `disabled` (2); the glow strip has `on` and `damaged`. `anchors.pivot` is the barrel pin; a base with several barrels has `anchors.pivots` instead.
- **Barrel** `<id>_barrel.png`: drawn pointing UP, anims `idle` (1), `fire` (3: recoil 2/1/0 px and the family muzzle flash on the glow layer), `damaged` (2), `disabled`, and `off` (lights dead). The glow strip has `fire`, `damaged` and `idle`.
- **Barrel keys** (in the `barrel` block of `<id>_out.json`, and in `<id>_barrel.json`):
  - `pivot_on_base` [x, y] and `pivot_on_barrel` [x, y], `muzzle` [x, y]: single-barrel guns, as before;
  - `pivots_on_base`: a list of [x, y], for a base with several barrels (broadside battery, gun strip): the same barrel sprite is turned about `pivot_on_barrel` on each of them. It replaces `pivot_on_base`;
  - `stagger_s`: seconds between one barrel's recoil and the next one's (staggered fire), only with `pivots_on_base`;
  - `aim`: `fixed` (with `gimbal_deg`: casemate 6, long 3, broadside and strip 20, heavy 4, spinal 2, pod 10), `turret` or `swivel`;
  - a flush pod's barrel sprite is its hatch lids (64 x 20, never turned): fire frames 0-2 open, half-close and close them;
  - the optional `off` anim is a barrel frame with its lights dead; a game that has no use for it can ignore it.
- **How the game reads it:** `Mounts._read_barrel` takes `pivots_on_base` (else `pivot_on_base`) and `stagger_s`; the muzzle comes from `pivot_on_barrel` and `muzzle`. A shot leaves from the barrel that fires next, round-robin by shot; `Visuals._draw_barrel` draws one barrel per pivot, the recoil of barrel k delayed by k x `stagger_s`. A flush pod's barrel never turns (it is drawn along the mount). The `off` anim shows while the mount is unpowered. An `_out.json` whose `cells` differ from the gun's outside half is ignored: the flat placeholder is drawn instead, never stretched art.
- **Centring rule:** a breech (inside half) narrower than the outside half sits at `floor((W - bw) / 2)` cells from the outside half's left edge at rotation 0 (W, bw in cells). The inside halves are unchanged.
- Race guns keep their homeland on the new shape: the body's steel ramp (`gun_race.STEEL`), the livery letters (`LIV`, from `data/ship_styles.json`), a wing motif in the wing or corner slots, and a tip or band on the barrel.

### Racial hand weapons (race wave 1: Kett, Mire, Sporeling, Gauntling, Prismatic, Grundl)
Generator `art/_src/hand_race.py` (one module, no new palette colours; `build_all.py` calls it), preview `python3 art/_src/sheet_hand.py out.png`. Same format as the other hand weapons of `items/`: ONE PNG per weapon (faces UP, 1 px outline, `anchors.grip` / `muzzle`, `class` = the arm pose), which is both the held sprite and the item's icon, plus `<id>_glow.png`. The id is the `art` of the weapon in `data/packs/tech_<race>/hand_weapons.json`. Muzzle flashes go in `items/fx/muzzle_<name>.png` (3 frames, anim `play`, faces UP, anchor `muzzle` on the weapon's muzzle; `for_item` names the weapon); the melee weapons have none, like the quarry hammer and the ember knife.
| weapon (class) | race signature | flash |
|---|---|---|
| `sting_pistol` (pistol), `hive_prod` (melee) | Kett: amber chitin, cream needle, green venom, honeycomb cells | `muzzle_sting` |
| `bubble_rifle` (rifle), `hook_gaff` (melee) | Mire: wet teal housing, brass, glass foam tank, red hand-wheel, steel crook | `muzzle_bubble` |
| `spore_puffer` (tool), `thorn_lash` (melee) | Sporeling: cream and brown growth, violet spore sac, thorns | `muzzle_puff` |
| `rivet_fist` (heavy), `arc_welder` (tool) | Gauntling: mismatched steel and rust, copper winding, cyan arc | `muzzle_rivet`, `muzzle_weld` |
| `lens_pistol` (pistol), `shard_lance` (heavy) | Prismatic: faceted violet and navy, cyan and magenta cores | `muzzle_lens`, `muzzle_shard` |
| `freight_hammer` (melee), `chain_gun` (heavy) | Grundl: dark riveted gunmetal, amber stencil, chains | `muzzle_chain` |
Each race's `sidearm` in `data/packs/races_1/species.json` is its first weapon of this list.
