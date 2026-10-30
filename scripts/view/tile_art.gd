extends RefCounted
## The structure art: floor, walls (mask4 autotile, also the shaped cells: slopes and curves), ram
## plating, doors, breaches, cables (mask4), fire, and the exterior hull skin of a ship in a fight,
## from art/tiles/<name> and art/fx/fire (art/README.md has the sheet layouts). Each draw function
## returns true when it drew with art and false when there is none, and then the caller draws its
## placeholder. Drawing only. A tile is drawn into the rect it is given (one frame per cell, whatever
## its source size). Glow layers go to `glow_out` (an Array of quads for an additive GlowLayer) when
## one is given, else over the sprite.

const Art = preload("res://scripts/view/art.gd")
const SpriteSheet = preload("res://scripts/view/sprite_sheet.gd")
const ARMOUR_TINT := 0.7  ## how far plain wall art is pulled toward a material's colour when there is no armour sheet
const FLOOR_PLAIN := 10  ## of every 16 cells, this many take the plain floor variant (v0)
const DOOR_SECONDS := 0.25  ## a door's open or close, when the art has no timing
const SHAPE_CELLS := ["tri", "tri2_low", "tri2_high", "round2_tl", "round2_tr", "round2_bl", "round2_br"]  ## a shaped sheet's 7 rows per orientation (the sheets call the arcs arc_*)
const MASK_FRAMES := 16  ## columns of a mask4 sheet
const JOIN_COVER := 0.6  ## a neighbour counts as solid when it covers this much of the shared edge
const EDGE_EPS := 1e-6
const SIDES: Array[Vector2i] = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
const DECAL_ONE_IN := 7  ## of the skin cells on a flat run, about this many take a decal
const DECALS := ["vent", "antenna", "hatch", "light"]
const GLOW_LINES := ["neon"]  ## the lines whose skin has an edge glow


## The mask4 frame of the wall at `c`: N*1 + E*2 + S*4 + W*8 over the neighbours that join it (see joins()).
static func wall_mask(grid, c: Vector2i) -> int:
	return SpriteSheet.mask4(joins(grid, c, Vector2i.UP), joins(grid, c, Vector2i.RIGHT), joins(grid, c, Vector2i.DOWN), joins(grid, c, Vector2i.LEFT))


## Does the cell next to `c` in direction `dir` join a wall at `c`: a wall (or a door) that covers at least
## JOIN_COVER of the shared edge, so a slope that only touches it does not.
static func joins(grid, c: Vector2i, dir: Vector2i) -> bool:
	return cover(grid, c + dir, -dir) >= JOIN_COVER - EDGE_EPS


## How much of its own edge on `side` the cell `c` fills with wall: 1 for a wall or a door, the polygon's
## share for a shaped wall, 0 for anything else.
static func cover(grid, c: Vector2i, side: Vector2i) -> float:
	var id: String = grid.get_tile(c)
	if id == "":
		return 0.0
	if grid.tile_flag(id, "door"):
		return 1.0
	if not grid.tile_flag(id, "solid"):
		return 0.0
	return edge_cover(grid.polygon_at(c), side) if grid.shapes.has(c) else 1.0


## How much of the edge of the unit square on `side` (UP, RIGHT, DOWN or LEFT) the convex polygon `poly`
## (cell-local, inside the square) fills, 0..1: the run of its vertices that lie on that edge.
static func edge_cover(poly: PackedVector2Array, side: Vector2i) -> float:
	var on_x := side.x != 0
	var line := 1.0 if side.x > 0 or side.y > 0 else 0.0
	var lo := INF
	var hi := -INF
	for p in poly:
		if absf((p.x if on_x else p.y) - line) <= EDGE_EPS:
			var along: float = p.y if on_x else p.x
			lo = minf(lo, along)
			hi = maxf(hi, along)
	return maxf(hi - lo, 0.0) if hi >= lo else 0.0


## The row of a shaped sheet (walls_shapes and the others laid out like it) for the stored shape `sd`
## ({shape, rot, mirror}): orient * 7 + the cell's place, orient = mirror * 4 + rot. -1 for a full
## square or a shape with no row.
static func shape_row(sd: Dictionary) -> int:
	var i := SHAPE_CELLS.find(str(sd.get("shape", "")))
	if i < 0:
		return -1
	return ((4 if bool(sd.get("mirror", false)) else 0) + posmod(int(sd.get("rot", 0)), 4)) * SHAPE_CELLS.size() + i


## The frame of an autotile sheet for `mask` (16 frames in mask4 order), or the first frame of a plain sheet.
static func autotile_frame(sheet, mask: int) -> int:
	if sheet.autotile == "mask4" or (sheet.autotile == "" and sheet.count == 16):
		return mask
	return 0


## One of the sheet's frames chosen by the cell (a breach, so neighbours differ).
static func variant(sheet, c: Vector2i) -> int:
	return 0 if sheet.count <= 1 else posmod(hash(c), sheet.count)


## A floor frame by the cell: the plain one (v0) for FLOOR_PLAIN of every 16 cells, the others share the rest.
static func floor_variant(sheet, c: Vector2i) -> int:
	if sheet.count <= 1:
		return 0
	var h := posmod(hash(c), 16)
	return 0 if h < FLOOR_PLAIN else 1 + (h - FLOOR_PLAIN) % (sheet.count - 1)


static func floor_tile(canvas, rect: Rect2, c: Vector2i, alpha := 1.0) -> bool:
	var s = Art.tiles("floor")
	if s == null:
		return false
	canvas.draw_texture_rect_region(s.texture, rect, s.region(floor_variant(s, c)), Color(1, 1, 1, alpha))
	return true


## A wall cell. `id`: its tile id. The plain "wall" is drawn as the sheet is. Ram plating (tile quirk
## "ram") has fixed colours: walls_ram, never tinted. Any other material uses walls_armor (neutral
## greys, multiplied by `color`); with no such sheet the plain walls are tinted by `color`, through the
## colour mask when there is one, else the whole sprite. A shaped cell (a slope or a curve) takes the
## same sheet with `_shapes` on its name, the frame `row * 16 + mask`; its open part is transparent.
static func wall_tile(canvas, rect: Rect2, grid, c: Vector2i, id: String, color: Color) -> bool:
	var sd: Dictionary = grid.shape_of(c)
	var row := shape_row(sd) if not sd.is_empty() else -1
	if not sd.is_empty() and row < 0:
		return false
	var tail := "_shapes" if row >= 0 else ""
	var ram := is_ram(grid, id)
	var s = Art.tiles("walls_ram" + tail) if ram else null
	var armour := id != "wall" and s == null
	var tex: Texture2D
	var mod := Color.WHITE
	if s != null:
		tex = s.texture
	else:
		s = Art.tiles("walls_armor" + tail) if armour else null
		if s != null:
			tex = s.texture
			mod = color
		else:
			s = Art.tiles("walls" + tail)
			if s == null:
				return false
			tex = s.texture
			if armour:
				if s.has_mask():
					tex = s.tinted(color)
				else:
					mod = Color.WHITE.lerp(color, ARMOUR_TINT)
	var frame := autotile_frame(s, wall_mask(grid, c))
	canvas.draw_texture_rect_region(tex, rect, s.region(maxi(row, 0) * MASK_FRAMES + frame), mod)
	return true


## Is tile `id` ram plating (its quirk says so)?
static func is_ram(grid, id: String) -> bool:
	return grid.defs != null and str(grid.defs.get_def(id).get("quirk", "")) == "ram"


## Does the open part of the shaped wall `c` look into the ship: is there a floor (or a door) beside an
## edge its polygon does not fill? Then floor is drawn under it, else it is open to space.
static func open_over_floor(grid, c: Vector2i) -> bool:
	if not grid.shapes.has(c):
		return false
	var poly: PackedVector2Array = grid.polygon_at(c)
	for d in SIDES:
		if edge_cover(poly, d) < 1.0 - EDGE_EPS:
			var id: String = grid.get_tile(c + d)
			if id != "" and not grid.tile_flag(id, "solid"):
				return true
	return false


## A solid cell of the ship: the wall art (wall_tile), with floor under the open part of a shaped cell
## that looks into the ship. With no art it is a flat polygon (a full square when the cell has no shape).
static func solid_cell(canvas, rect: Rect2, grid, c: Vector2i, id: String, color: Color) -> void:
	var shaped: bool = grid.shapes.has(c)
	if shaped and open_over_floor(grid, c) and not floor_tile(canvas, rect, c):
		canvas.draw_rect(rect, grid.defs.color("floor") if grid.defs != null and grid.defs.has("floor") else color.darkened(0.5))
	if wall_tile(canvas, rect, grid, c, id, color):
		return
	if not shaped:
		canvas.draw_rect(rect, color)
		canvas.draw_rect(rect.grow(-3), color.lightened(0.12))
		return
	var pts := PackedVector2Array()
	for p in grid.polygon_at(c):
		pts.append(rect.position + p * rect.size)
	canvas.draw_colored_polygon(pts, color.lightened(0.06))


## How far open a door is, 0 (closed) to 1 (open), moving toward `open` over `dur` seconds. `state`
## (a Dictionary the view keeps) remembers each door by `key`; a door seen for the first time is already there.
static func door_progress(state: Dictionary, key, open: bool, now: float, dur: float) -> float:
	var d: Dictionary = state.get(key, {"open": open, "p0": 1.0 if open else 0.0, "t0": -1.0e9})
	var p := clampf(float(d["p0"]) + (now - float(d["t0"])) / maxf(dur, 0.01) * (1.0 if d["open"] else -1.0), 0.0, 1.0)
	if d["open"] != open:  # turned round (possibly half way): carry on from where it is
		d = {"open": open, "p0": p, "t0": now}
	state[key] = d
	return p


## door_progress() with the timing of the door art (DOOR_SECONDS when there is none).
static func door_fraction(state: Dictionary, key, open: bool, now: float) -> float:
	var s = Art.tiles("door")
	return door_progress(state, key, open, now, door_seconds(s) if s != null else DOOR_SECONDS)


## Seconds the door art takes to open: its `open` animation's frames at its fps.
static func door_seconds(sheet) -> float:
	if sheet.has_anim("open") and sheet.anims["open"]["fps"] > 0.0:
		return float(sheet.anims["open"]["count"]) / sheet.anims["open"]["fps"]
	return DOOR_SECONDS


## The frame of the door sheet at `progress` (0 closed, 1 open): along the `open` animation (closed
## to open); with no such animation the first frame, or the second when more than half open.
static func door_frame(sheet, progress: float) -> int:
	if sheet.has_anim("open"):
		return sheet.frame_frac("open", progress)
	return mini(1, sheet.count - 1) if progress >= 0.5 else 0


## A door piece over the cells `rects` (screen rects, in order), `progress` open. The sheet is drawn
## for a horizontal piece and turned a quarter for a vertical one. Its glow (frame i goes with frame i) is optional.
static func door_piece(canvas, rects: Array, horizontal: bool, progress: float, glow_out = null) -> bool:
	var s = Art.tiles("door")
	if s == null or rects.is_empty():
		return false
	var whole: Rect2 = rects[0]
	for q in rects:
		whole = whole.merge(q)
	var size := whole.size if horizontal else Vector2(whole.size.y, whole.size.x)
	var frame := door_frame(s, progress)
	var xf := Transform2D(0.0 if horizontal else PI / 2.0, whole.get_center())
	var dest := Rect2(-size / 2.0, size)
	canvas.draw_set_transform_matrix(xf)
	canvas.draw_texture_rect_region(s.texture, dest, s.region(frame), Color.WHITE)
	canvas.draw_set_transform_matrix(Transform2D.IDENTITY)
	var g = s.glow
	if g != null and frame < g.count:
		var k := size / Vector2(s.frame)
		emit(canvas, glow_out, {"tex": g.texture, "rect": Rect2(dest.position + g.offset * k, Vector2(g.frame) * k),
			"src": g.region(frame), "xf": xf, "mod": Color.WHITE})
	return true


## A shot-out cell.
static func breach(canvas, rect: Rect2, c: Vector2i) -> bool:
	var s = Art.tiles("breach")
	if s == null:
		return false
	canvas.draw_texture_rect_region(s.texture, rect, s.region(variant(s, c)), Color.WHITE)
	return true


## A cable cell: the mask4 frame over the neighbouring cable cells (`has`: Callable(cell) -> bool).
## A powered cable uses the sheet named by "powered" in the JSON (cable_on) and its glow.
static func cable(canvas, rect: Rect2, has: Callable, c: Vector2i, powered := false, glow_out = null) -> bool:
	var s = Art.tiles("cable")
	if s == null:
		return false
	var lit = Art.tiles(str(s.meta.get("powered", "cable_on.png")).get_basename()) if powered else null
	var mask := SpriteSheet.mask4(has.call(c + Vector2i.UP), has.call(c + Vector2i.RIGHT), has.call(c + Vector2i.DOWN), has.call(c + Vector2i.LEFT))
	var frame := autotile_frame(s, mask)
	var base = lit if lit != null else s
	canvas.draw_texture_rect_region(base.texture, rect, base.region(frame), Color.WHITE)
	var g = s.glow if powered else null
	if g != null:
		var k := rect.size / Vector2(s.frame)
		emit(canvas, glow_out, {"tex": g.texture, "rect": Rect2(rect.position + g.offset * k, Vector2(g.frame) * k),
			"src": g.region(frame if g.count > frame else 0), "xf": Transform2D.IDENTITY, "mod": Color.WHITE})
	return true


## A burning cell, `intensity` 0..1: the fx/fire loop standing on the cell's bottom edge, bigger and
## brighter with the intensity, a different phase per cell, with its glow.
static func fire_cell(canvas, rect: Rect2, intensity: float, t: float, c: Vector2i, glow_out = null) -> bool:
	var s = Art.fx("fire")
	if s == null:
		return false
	var i := clampf(intensity, 0.0, 1.0)
	var phase := float(hash(c) & 255) / 255.0 * 1.5
	var f: int = s.loop_frame(t + phase)
	var k := rect.size.x / SpriteSheet.SRC_CELL * (0.6 + 0.4 * i)
	var size := Vector2(s.frame) * k
	var dest := Rect2(Vector2(rect.get_center().x - size.x / 2.0, rect.end.y - size.y), size)
	canvas.draw_texture_rect_region(s.texture, dest, s.region(f), Color(1, 1, 1, 0.55 + 0.45 * i))
	var g = s.glow
	if g != null:
		emit(canvas, glow_out, {"tex": g.texture, "rect": Rect2(dest.position + g.offset * k, Vector2(g.frame) * k),
			"src": g.region(mini(f, g.count - 1)), "xf": Transform2D.IDENTITY, "mod": Color(1, 1, 1, 0.4 + 0.6 * i)})
	return true


# --- the exterior hull skin (a ship in a fight) -----------------------------------------------------

## Does the edge of cell `c` on `dir` face open space: nothing is built beside it (empty space, a hole,
## the unbuilt hull), or a shaped wall that does not cover the edge and whose open part is outside?
## Floor and doors are the inside of the ship; a wall that joins (see joins()) is not space either.
static func faces_space(grid, c: Vector2i, dir: Vector2i) -> bool:
	var n: Vector2i = c + dir
	var id: String = grid.get_tile(n)
	if id == "":
		return true
	if not grid.tile_flag(id, "solid") or joins(grid, c, dir):
		return false
	return not open_over_floor(grid, n)


## The mask4 frame of the skin sheets for wall `c`: bit N, E, S, W set when that side faces open space.
static func skin_mask(grid, c: Vector2i) -> int:
	return SpriteSheet.mask4(faces_space(grid, c, Vector2i.UP), faces_space(grid, c, Vector2i.RIGHT),
		faces_space(grid, c, Vector2i.DOWN), faces_space(grid, c, Vector2i.LEFT))


## The skin of a ship's grid: {"cells": [{c, mask, row, variant, decal}], "line"}. The skin goes over the
## solid cells next to space (ram plating keeps its hazard tape, and a shaped cell that looks into the
## ship has no skin): `mask` is skin_mask(), `row` the row of the shaped sheet (-1 for a full cell),
## `variant` a panel variant by the cell's position, `decal` a greeble ("" for none). `line` is the line
## that most of those cells' tiles belong to, plus `extra` (line -> cells, e.g. the ship's parts), a tie going to standard.
static func skin_plan(grid, extra := {}) -> Dictionary:
	var cells := []
	var index := {}
	var lines := {}
	for c in grid.tiles:
		var id: String = grid.tiles[c]
		if not grid.tile_flag(id, "solid") or is_ram(grid, id):
			continue
		var sd: Dictionary = grid.shape_of(c)
		var row := shape_row(sd) if not sd.is_empty() else -1
		if not sd.is_empty() and (row < 0 or open_over_floor(grid, c)):
			continue
		var mask := skin_mask(grid, c)
		if sd.is_empty() and mask == 0:
			continue
		var line := str(grid.defs.get_def(id).get("line", "standard")) if grid.defs != null else "standard"
		lines[line] = int(lines.get(line, 0)) + 1
		var e := {"c": c, "mask": mask, "row": row, "variant": posmod(hash(c), 4), "decal": ""}
		cells.append(e)
		index[c] = e
	for e in cells:
		e["decal"] = decal_for(index, e)
	for line in extra:
		lines[line] = int(lines.get(line, 0)) + int(extra[line])
	return {"cells": cells, "line": dominant_line(lines)}


## The line with the most cells in `counts` (line id -> n); standard when it is among the most.
static func dominant_line(counts: Dictionary) -> String:
	var best := "standard"
	var top := int(counts.get(best, 0))
	var ids := counts.keys()
	ids.sort()
	for id in ids:
		if int(counts[id]) > top:
			best = str(id)
			top = int(counts[id])
	return best


static func _decal_gate(c: Vector2i) -> bool:
	return posmod(hash(c), DECAL_ONE_IN) == 0


## The greeble on skin cell `e` of `index` (cell -> entry), "" for none: about one flat-run cell in
## DECAL_ONE_IN, by position, never on the cell after one (a vent covers two cells), on full cells that
## face space on one side only. A vent needs a skin cell of the same face beside it, else it is a hatch.
static func decal_for(index: Dictionary, e: Dictionary) -> String:
	var c: Vector2i = e["c"]
	if e["row"] >= 0 or not (e["mask"] in [1, 2, 4, 8]) or not _decal_gate(c) or _decal_gate(c + Vector2i.LEFT):
		return ""
	var kind: String = DECALS[posmod(hash(c) / DECAL_ONE_IN, DECALS.size())]
	if kind == "vent":
		var next: Dictionary = index.get(c + Vector2i.RIGHT, {})
		if not (e["mask"] in [1, 4] and next.get("mask", -1) == e["mask"] and next.get("row", 0) < 0):
			return "hatch"
	return kind


## The multiply tint of a line's skin: the `suggested_tints` of the hull_skin sheet `sheet` (standard's
## for a line it does not list, white with no sheet).
static func skin_tint(sheet, line: String) -> Color:
	var listed: bool = sheet != null and sheet.meta.get("suggested_tints", {}).has(line)
	return _tint(sheet, line if listed else "standard")


## The colour of the edge glow of a line's skin, or null for a line that does not glow.
static func skin_glow(sheet, line: String) -> Variant:
	return _tint(sheet, "edge_glow_" + line) if line in GLOW_LINES else null


## A colour of the skin sheet's `suggested_tints` (written 0..255), white when it is not there.
static func _tint(sheet, key: String) -> Color:
	var v = sheet.meta.get("suggested_tints", {}).get(key) if sheet != null else null
	return Color8(int(v[0]), int(v[1]), int(v[2])) if v is Array and v.size() >= 3 else Color.WHITE


## Draw a skin plan (skin_plan) of a grid whose cell (0, 0) starts at `origin` px, `cell_px` per cell:
## the skin over every planned cell, then the decals over them (`t`: seconds, for the lamps). Neon
## skin adds its edge glow. False when there is no skin art.
static func draw_skin(canvas, plan: Dictionary, origin: Vector2, cell_px: float, t: float, glow_out = null) -> bool:
	var plain = Art.tiles("hull_skin")
	var shaped = Art.tiles("hull_skin_shapes")
	if plain == null:
		return false
	var line: String = plan["line"]
	var tint := skin_tint(plain, line)
	var edge = skin_glow(plain, line)
	var lamp := _tint(plain, "lamp_glow")
	for e in plan["cells"]:
		var s = shaped if e["row"] >= 0 else plain
		if s == null:
			continue
		var rect := Rect2(origin + Vector2(e["c"]) * cell_px, Vector2(cell_px, cell_px))
		var frame: int = (e["row"] if e["row"] >= 0 else e["variant"]) * MASK_FRAMES + e["mask"]
		canvas.draw_texture_rect_region(s.texture, rect, s.region(frame), tint)
		var g = s.glow
		if g != null and edge != null:
			var k := rect.size / Vector2(s.frame)
			emit(canvas, glow_out, {"tex": g.texture, "rect": Rect2(rect.position + g.offset * k, Vector2(g.frame) * k),
				"src": g.region(frame if e["row"] >= 0 else e["mask"]), "xf": Transform2D.IDENTITY, "mod": edge})
	var decals = Art.tiles("hull_skin_decals")
	if decals != null:
		for e in plan["cells"]:
			if e["decal"] != "":
				_decal(canvas, decals, e, origin, cell_px, tint, lamp, t, glow_out)
	return true


## One greeble of the decal atlas over its skin cell (a vent spans two cells); lights blink, and the
## lit ones and the antenna tip glow.
static func _decal(canvas, sheet, e: Dictionary, origin: Vector2, cell_px: float, tint: Color, lamp: Color, t: float, glow_out) -> void:
	var kind: String = e["decal"]
	if kind == "light":
		kind = "light_on" if (int(t) + (hash(e["c"]) & 1)) % 2 == 0 else "light_off"
	var r = sheet.meta.get("rects", {}).get(kind)
	if not (r is Array and r.size() == 4):
		return
	var src := Rect2(float(r[0]), float(r[1]), float(r[2]), float(r[3]))
	var dest := Rect2(origin + Vector2(e["c"]) * cell_px, src.size / SpriteSheet.SRC_CELL * cell_px)
	canvas.draw_texture_rect_region(sheet.texture, dest, src, tint)
	var g = sheet.glow
	if g != null and kind in ["antenna", "light_on"]:
		emit(canvas, glow_out, {"tex": g.texture, "rect": dest, "src": src, "xf": Transform2D.IDENTITY, "mod": lamp})


## Hand a glow quad {tex, rect, src, xf, mod} to the additive layer's list, or draw it over the sprite.
static func emit(canvas, glow_out, quad: Dictionary) -> void:
	if glow_out is Array:
		glow_out.append(quad)
		return
	canvas.draw_set_transform_matrix(quad["xf"])
	canvas.draw_texture_rect_region(quad["tex"], quad["rect"], quad["src"], quad["mod"])
	canvas.draw_set_transform_matrix(Transform2D.IDENTITY)
