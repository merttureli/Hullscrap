# Art drop-in

Every placed component is drawn by `scripts/view/visuals.gd`. If an art file exists for a component id, the game draws it; if not, it draws a flat placeholder. So real art can be added one component at a time, with no code change.

## Components

Put the file at `art/components/<component id>.png` (or `.svg`). The id is the `id` of the entry in `data/components.json`, for example:

- `art/components/reactor_mk1.png`
- `art/components/engine_scrap_mk1.png`
- `art/components/radiator.svg`

If both exist, the `.png` wins.

- **Size**: the footprint times **32 px per cell**, at rotation 0. A 4x2-cell engine is **128 x 64 px**, a 4x4 reactor 128 x 128, a 2x2 radiator 64 x 64 (the `size` field is `[width, height]` in cells). A bigger file with the same proportions is scaled down to fit.
- **Facing up = rotation 0**: draw the part as it sits unrotated, its front towards the top of the image. The game turns it clockwise by 90 degrees per `rot` (`rot` 1 is a quarter turn clockwise, and swaps width and height).
- **Transparent background**, nothing outside the footprint.
- **Look** (see "Art direction" and "Equipment lines" in `docs/PLAN.md`): strictly top-down, light from the top-left, the same outline weights for all three lines. Only the surface differs: grit for Scrap, polish for Standard, glow for Neon.
- **Do not paint state**: the heat bar, the "!" for overheated, the gear for a malfunction, the grey of a disabled part and the hp pips are drawn on top by the game. The Scrap hazard-stripe corner and the Neon outline are placeholder accents and disappear once a part has art.

## After adding files

- Run `godot --headless --path . --import` (or open the project in the editor) so Godot imports them. In a development run the game also reads a new PNG straight from disk before it is imported.
- The game remembers which ids have no art for the whole session: restart it after adding a file.
- Record the source and licence of every file in `ASSETS.md`.

## Weapons (hull mounts, in three files each)
A weapon straddles the hull wall, so it is drawn as two halves plus a rotating barrel. Outward is UP at rotation 0. Generator: `art/_src/comp_weapons.py` (`python3 art/_src/build_weapons.py`); preview: `python3 art/_src/sheet_weapons.py [out.png] [ids]`.
- `<id>.png` + `.json`: the INSIDE half, on the floor against the inner wall face (which is above it). Footprint `cells` [4,2]; the frame is 64x36 with `offset` [0,-4]: its top 4 px are a mounting flange that overhangs the wall face. Anims `on` (2), `off`, `charge` (6, the charge strip or the weapon's own charge indicator; frame 5 = ready), `fire` (2, a discharge flash then dark), `damaged` (2), `disabled`. Breech, capacitor, power coupling (cable stub at the left edge), repair hatch, and for ammo weapons a feed chute to the right edge where an `ammo_rack` sits.
- `<id>_out.png` + `.json`: the OUTSIDE half, in space against the outer wall face (which is below it). `cells` [4,2] (heavy `shrapnel_cannon_scrap`: [4,3], frame 64x52; the data layout assumed here is outside 3 rows, wall 1, inside 2); the bottom 4 px are a flange that overhangs the wall. Anims `on` (2), `off`, `damaged` (2), `disabled` (2, scorched, dented, ring cracked, sparking: broken but fixable, never shattered). `anchors.pivot` is where the barrel turns, in this frame. Its JSON also holds a `barrel` block (the same data as `<id>_barrel.json`).
- `<id>_barrel.png` + `.json`: the rotating barrel or head, drawn pointing UP. Anims `idle`, `fire` (3: recoil 2/1/0 px and a muzzle flash), `damaged` (2), `disabled` (bent or snapped). `anchors.pivot` (the turning point) is placed on the outside half's `pivot_on_base`; `anchors.muzzle` is the tip. `aim` is `fixed` (aimed by pointing the ship; the barrel only gimbals `gimbal_deg` degrees and recoils; a long straight barrel braced in a sleeve) or `turret` (swivels in its ring within the arc: compact head, short barrel, sensor eye). The barrel has no baked drop shadow (it rotates). Glow layers: `<id>_glow`, `<id>_out_glow`, `<id>_barrel_glow` (fire flash).
- Fixed: laser_mk1, laser_mk2, pulse_mk1, pulse_mk2, artemis_mk1, ion_blast_mk1, shrapnel_cannon_scrap, bolt_thrower_scrap, heat_lance_neon, breach_harpoon. Turrets: laser_turret_mk1 (the Concord Point Turret), rattle_burst_scrap, siren_ion_neon, leech_laser.
- `ammo_rack.png` (2x2, 32x32): anims `fill_0..4` (missiles, also `on` = full), `scrap_0..4`, `slug_0..4`, `damaged` (2), `disabled`, `wrecked`.
- `tiles/wreck.png`: a 16x16 debris decal, 4 variants (scorched floor, twisted plate, loose cables, burnt scrap).
