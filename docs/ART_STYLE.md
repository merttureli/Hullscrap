# Hullscrap art style: FTL's visual language, our own drawings (lead, v1)

We re-create the *style* of FTL / FTL: Multiverse. **We never use their files.** All art is original, made to these rules, or human-made packs under CC0 or CC-BY (logged in `ASSETS.md`).

## Medium
- **Pixel art**: hard pixels, nearest-neighbour scaling, no blur or soft gradients. Light shading comes from 2–3 hand-placed tones, and dithering only where it's needed.
- **Source scale**: 1 grid cell = **16 × 16 source pixels**, displayed at 2× (32 screen px per cell at zoom 1).
  - So a crew sprite is a **24 × 24** source canvas (about 3×3 cells on screen).
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

## Crew
- **24×24 source**, in FTL's three-quarter top-down view: big readable head, simple body.
- **Each species has a distinct silhouette** and each outfit a distinct colour.
- **Animations** (frames per direction; 4 directions, or 2 mirrored):
  - walk 4 frames;
  - idle 2 frames (breathing);
  - work or repair 2–4 frames (tool motion);
  - extinguish 2 frames;
  - shoot 2 frames;
  - down 1 frame.
- Played at 6–8 fps, never interpolated.

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

## Files
- `art/<area>/<id>.png` (crew in `art/crew/<species>_<outfit>.png` as sprite sheets), plus a JSON next to each sheet with frame size, frames per animation and fps.
- The game picks them up through `scripts/view/visuals.gd` (components), and through the crew and person drawers once they read sheets. Placeholders stay as the fallback.
