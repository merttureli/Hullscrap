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
