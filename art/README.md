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
