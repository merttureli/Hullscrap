extends RefCounted
## The structure art: floor, walls (mask4 autotile), doors, breaches, cables (mask4) and fire, from
## art/tiles/<name> and art/fx/fire. Each draw function returns true when it drew with art and
## false when there is none, and then the caller draws its placeholder. Drawing only. A tile is
## drawn into the rect it is given (one frame per cell, whatever its source size). Glow layers go
## to `glow_out` (an Array of quads for an additive GlowLayer) when one is given, else over the sprite.

const Art = preload("res://scripts/view/art.gd")
const SpriteSheet = preload("res://scripts/view/sprite_sheet.gd")
const ARMOUR_TINT := 0.7  ## how far plain wall art is pulled toward a material's colour when there is no armour sheet
const FLOOR_PLAIN := 10  ## of every 16 cells, this many take the plain floor variant (v0)
const DOOR_SECONDS := 0.25  ## a door's open or close, when the art has no timing


## The mask4 frame of the wall at `c`: N*1 + E*2 + S*4 + W*8 over neighbours that are solid or doors.
static func wall_mask(grid, c: Vector2i) -> int:
	return SpriteSheet.mask4(_joins(grid, c + Vector2i.UP), _joins(grid, c + Vector2i.RIGHT),
		_joins(grid, c + Vector2i.DOWN), _joins(grid, c + Vector2i.LEFT))


static func _joins(grid, c: Vector2i) -> bool:
	var id: String = grid.get_tile(c)
	return id != "" and (grid.tile_flag(id, "solid") or grid.tile_flag(id, "door"))


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


## A wall cell. `id`: its tile id. The plain "wall" is drawn as the sheet is. Any other material uses
## walls_armor (neutral greys, multiplied by `color`); with no such sheet the plain walls are tinted
## by `color`, through the colour mask when there is one, else the whole sprite.
static func wall_tile(canvas, rect: Rect2, grid, c: Vector2i, id: String, color: Color) -> bool:
	var armour := id != "wall"
	var s = Art.tiles("walls_armor") if armour else null
	var tex: Texture2D
	var mod := Color.WHITE
	if s != null:
		tex = s.texture
		mod = color
	else:
		s = Art.tiles("walls")
		if s == null:
			return false
		tex = s.texture
		if armour:
			if s.has_mask():
				tex = s.tinted(color)
			else:
				mod = Color.WHITE.lerp(color, ARMOUR_TINT)
	canvas.draw_texture_rect_region(tex, rect, s.region(autotile_frame(s, wall_mask(grid, c))), mod)
	return true


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


## Hand a glow quad {tex, rect, src, xf, mod} to the additive layer's list, or draw it over the sprite.
static func emit(canvas, glow_out, quad: Dictionary) -> void:
	if glow_out is Array:
		glow_out.append(quad)
		return
	canvas.draw_set_transform_matrix(quad["xf"])
	canvas.draw_texture_rect_region(quad["tex"], quad["rect"], quad["src"], quad["mod"])
	canvas.draw_set_transform_matrix(Transform2D.IDENTITY)
