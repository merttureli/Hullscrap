# Art drop-in (format v1)

The game draws pixel art from this folder and falls back to flat code-drawn placeholders for anything missing, so art can be added one file at a time with no code change. The style law is `docs/ART_STYLE.md`; every file's source and licence goes in `ASSETS.md`.

**How it is read** (`scripts/view/art.gd`): each PNG is read from disk with `Image` + `ImageTexture` (no editor import needed, so headless runs and tests work) and cached for the session: restart the game after adding a file. A PNG with no JSON is one frame; the JSON next to it adds everything else. `scripts/view/sprite_sheet.gd` holds the frame maths. The project's default texture filter is **nearest**.

**Scale**: 1 grid cell = **16 source px**, drawn at 2 screen px per source px at zoom 1 (32 px per cell). Effects and projectiles are drawn at no fewer than 2 screen px per source px at any zoom.

## Folders
- `components/<component_id>.png` (+ `.json`): system sprites. The id is the `id` in `data/components.json`. A part with no art of its own borrows the next lower tier's (`engine_mk2` uses `engine_mk1`) until its own lands (`Art.tier_fallback`).
- `crew/<species>/`: `legs.png`, `torso.png`, `arms.png`, `head.png`, each with a `_color.png` mask, plus `crew.json`.
- `items/<id>.png` (+ `.json`): hand-held items (`pistol`, `rifle`, `wrench`, `extinguisher`).
- `tiles/`: `floor`, `walls`, `walls_armor`, `door`, `breach`, `cable` (+ `cable_on`).
- `fx/`: `fire`, `smoke`, `sparks`, `explosion`, `muzzle`, `shield_ripple`, `heat_shimmer`.
- `projectiles/<kind>`: `laser`, `beam` (hitscan, tiled along y, with `laser_impact` / `beam_impact` flares), `bolt`, `flak`, `missile`.
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
- Species rigs: `human`, `basalt`, `emberkin`, `fenn`, and race wave 1 `kett`, `mire`, `sporeling`, `gauntling`, `prismatic`, `grundl` (`python3 art/_src/build_all.py` rebuilds them; `python3 art/_src/build.py` checks palette, sizes and that every mount sits where the human's does, relative to the pivot).
  - **Large rig (`grundl`)**: its `frame` is 49x49 with `pivot` (24,24), so read both from `crew.json` and never assume 33/16. The art overhangs the 2x2 body (32 px); the shadow and pathing stay at the pivot. Every `mount` and `hand` anchor is the shared one moved by (+8,+8): identical relative to the pivot, so the same item formula (`mount - item.grip`, then rotate about the pivot) puts every item in the right place.
  - `kett` has four arms: the lower pair is small, tucked, and drawn into every arms pose. The glow layers of `sporeling` (spore puffs, 2 drifting frames), `gauntling` (lamp eye, lit LEDs) and `prismatic` (core and lit edges, 2 pulse frames) are multi-frame strips: `torso_glow` carries `anims.on`, `head_glow` lists one frame per head variant per step (see its notes for the fps).
  - Preview sheet: `python3 art/_src/sheet_races1.py out.png`.
- Held item: a wrench while repairing, an extinguisher while extinguishing (the wrench if there is no extinguisher art), a pistol for the player with nothing to do, nothing otherwise.

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
