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

## Shaped walls, ram plating and the hull skin (`art/tiles/`)

Geometry is in `tiles/shapes.json` (cell-local 0..1, y down, rotation 0; see `docs/CONTENT.md` 4d). Every sheet is a grid: 16 columns (autotile mask) and, for shaped cells, 56 rows = `orient * 7 + cell`, where `orient = mirror*4 + rot` and the cell order is in each JSON (`rows.cells`). Rows 0-6 are rotation 0. Every orientation is drawn already (lit from the top-left), so the game picks a frame and never rotates a sprite.

- `walls_shapes`, `walls_armor_shapes` (tinted like `walls_armor`), `walls_ram_shapes`: mask bit = that neighbour is solid (same as `walls.png`). `walls_ram.png` is the 16-frame full cell. Ram plating has fixed colours, no tint.
- `hull_skin` (16 mask frames x 4 panel variants), `hull_skin_shapes` (same grid as the wall shapes), `*_glow` (neon edge glow, 22x22 frames drawn at offset -3,-3), `hull_skin_decals` (+ glow): **mask bit = that side faces open space**, not "solid neighbour". Neutral greys, multiply a tint per line (`suggested_tints` in `hull_skin.json`).
- `python3 art/_src/build.py` regenerates everything and runs the checks; `python3 art/_src/preview_shapes.py out.png [components dir]` draws the preview sheet.

## After adding files

- Run `godot --headless --path . --import` (or open the project in the editor) so Godot imports them. In a development run the game also reads a new PNG straight from disk before it is imported.
- The game remembers which ids have no art for the whole session: restart it after adding a file.
- Record the source and licence of every file in `ASSETS.md`.
