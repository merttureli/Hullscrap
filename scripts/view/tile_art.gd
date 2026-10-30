extends RefCounted
## The structure art: floor, walls (mask4 autotile), doors, breaches, cables (mask4) and fire, from
## art/tiles/<name> and art/fx/fire. Each draw function returns true when it drew with art and
## false when there is none, and then the caller draws its placeholder. Drawing only. A tile is
## drawn into the rect it is given (one frame per cell, whatever its source size).

const Art = preload("res://scripts/view/art.gd")
const SpriteSheet = preload("res://scripts/view/sprite_sheet.gd")
const ARMOUR_TINT := 0.7  ## how far a wall sheet with no colour mask is pulled toward its material colour
const FIRE_FPS := 8.0  ## fire frames per second when the sheet names no animation


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


## One of the sheet's frames chosen by the cell, so a floor or a breach does not repeat in a grid.
static func variant(sheet, c: Vector2i) -> int:
	return 0 if sheet.count <= 1 else posmod(hash(c), sheet.count)


static func floor_tile(canvas, rect: Rect2, c: Vector2i, alpha := 1.0) -> bool:
	var s = Art.tiles("floor")
	if s == null:
		return false
	canvas.draw_texture_rect_region(s.texture, rect, s.region(variant(s, c)), Color(1, 1, 1, alpha))
	return true


## A wall cell. `id`: its tile id (the plain "wall" is drawn as the sheet is; any other material is
## tinted by `color`, through the sheet's colour mask when it has one, else the whole sprite).
static func wall_tile(canvas, rect: Rect2, grid, c: Vector2i, id: String, color: Color) -> bool:
	var s = Art.tiles("walls")
	if s == null:
		return false
	var tex: Texture2D = s.texture
	var mod := Color.WHITE
	if id != "wall":
		if s.has_mask():
			tex = s.tinted(color)
		else:
			mod = Color.WHITE.lerp(color, ARMOUR_TINT)
	canvas.draw_texture_rect_region(tex, rect, s.region(autotile_frame(s, wall_mask(grid, c))), mod)
	return true


## The frame of the door sheet: the `open` animation while open, else `closed` (or the first frame).
static func door_frame(sheet, open: bool, t: float) -> int:
	if open:
		return sheet.frame_at("open", t) if sheet.has_anim("open") else mini(1, sheet.count - 1)
	return sheet.frame_at("closed", t) if sheet.has_anim("closed") else 0


## A door piece over the cells `rects` (screen rects, in order). The sheet is drawn for a horizontal
## piece and turned a quarter for a vertical one.
static func door_piece(canvas, rects: Array, horizontal: bool, open: bool, t: float) -> bool:
	var s = Art.tiles("door")
	if s == null or rects.is_empty():
		return false
	var whole: Rect2 = rects[0]
	for q in rects:
		whole = whole.merge(q)
	var size := whole.size if horizontal else Vector2(whole.size.y, whole.size.x)
	canvas.draw_set_transform(whole.get_center(), 0.0 if horizontal else PI / 2.0, Vector2.ONE)
	canvas.draw_texture_rect_region(s.texture, Rect2(-size / 2.0, size), s.region(door_frame(s, open, t)), Color.WHITE)
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	return true


## A shot-out cell.
static func breach(canvas, rect: Rect2, c: Vector2i) -> bool:
	var s = Art.tiles("breach")
	if s == null:
		return false
	canvas.draw_texture_rect_region(s.texture, rect, s.region(variant(s, c)), Color.WHITE)
	return true


## A cable cell: mask4 frame over the neighbouring cable cells (`has`: Callable(cell) -> bool).
static func cable(canvas, rect: Rect2, has: Callable, c: Vector2i, tint := Color.WHITE) -> bool:
	var s = Art.tiles("cable")
	if s == null:
		return false
	var mask := SpriteSheet.mask4(has.call(c + Vector2i.UP), has.call(c + Vector2i.RIGHT), has.call(c + Vector2i.DOWN), has.call(c + Vector2i.LEFT))
	canvas.draw_texture_rect_region(s.texture, rect, s.region(autotile_frame(s, mask)), tint)
	return true


## A burning cell, `intensity` 0..1: the fx/fire loop (an animation named "on", else all the frames),
## bigger and brighter with the intensity, a different phase per cell.
static func fire_cell(canvas, rect: Rect2, intensity: float, t: float, c: Vector2i) -> bool:
	var s = Art.fx("fire")
	if s == null:
		return false
	var i := clampf(intensity, 0.0, 1.0)
	var phase := float(hash(c) & 255) / 255.0
	var f: int = s.frame_at("on", t + phase) if s.has_anim("on") else int((t + phase) * FIRE_FPS) % s.count
	var k := rect.size.x / SpriteSheet.SRC_CELL * (0.6 + 0.4 * i)
	var size := Vector2(s.frame) * k
	canvas.draw_texture_rect_region(s.texture, Rect2(rect.get_center() - size / 2.0, size), s.region(f), Color(1, 1, 1, 0.55 + 0.45 * i))
	return true
