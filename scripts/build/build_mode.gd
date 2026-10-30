extends Node2D
## Build mode: place floors, walls and doors on the ship grid.
## A square ghost shows where the tile goes (green = allowed, red = not, with the reason in the HUD).
## LMB place (hold to paint), RMB remove (hold to erase), 1-9 pick a tile, wheel zoom,
## Ctrl+S save to user://ship.json, Ctrl+L load it.

const ShipGrid = preload("res://scripts/ship/ship_grid.gd")
const TileDefs = preload("res://scripts/ship/tile_defs.gd")
const CELL := 32
const SAVE_PATH := "user://ship.json"

var defs: TileDefs
var grid: ShipGrid
var selected := ""
var hover := Vector2i(-1, -1)
var message := ""

@onready var hud: Label = get_node_or_null("../HUD/Label")
@onready var cam: Camera2D = get_node_or_null("../Camera2D")


func _ready() -> void:
	defs = TileDefs.new()
	defs.load_file("res://data/tiles.json")
	grid = ShipGrid.new(Vector2i(31, 31), defs)
	grid.fill_circle_hull(14.0)
	selected = defs.ids()[0]
	_update_hud()


func cell_at(world: Vector2) -> Vector2i:
	var p := (world - _origin()) / CELL
	return Vector2i(floori(p.x), floori(p.y))


func cell_rect(c: Vector2i) -> Rect2:
	return Rect2(_origin() + Vector2(c * CELL), Vector2(CELL, CELL))


func _origin() -> Vector2:
	return -Vector2(grid.size * CELL) / 2.0


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventMouseMotion:
		hover = cell_at(get_global_mouse_position())
		if e.button_mask & MOUSE_BUTTON_MASK_LEFT:
			_place(hover, true)
		elif e.button_mask & MOUSE_BUTTON_MASK_RIGHT:
			_remove(hover, true)
	elif e is InputEventMouseButton and e.pressed:
		match e.button_index:
			MOUSE_BUTTON_LEFT:
				_place(hover, false)
			MOUSE_BUTTON_RIGHT:
				_remove(hover, false)
			MOUSE_BUTTON_WHEEL_UP:
				_zoom(1.1)
			MOUSE_BUTTON_WHEEL_DOWN:
				_zoom(1.0 / 1.1)
	elif e is InputEventKey and e.pressed and not e.echo:
		if e.ctrl_pressed and e.keycode == KEY_S:
			_save()
		elif e.ctrl_pressed and e.keycode == KEY_L:
			_load()
		else:
			var i: int = e.keycode - KEY_1
			if i >= 0 and i < defs.ids().size():
				selected = defs.ids()[i]
				message = ""
	queue_redraw()
	_update_hud()


func _place(c: Vector2i, dragging: bool) -> void:
	var why := grid.can_place(selected, c)
	if why == "":
		grid.place(selected, c)
		message = ""
	elif not (dragging and why == "already there"):
		message = why


func _remove(c: Vector2i, dragging: bool) -> void:
	var why := grid.can_remove(c)
	if why == "":
		grid.remove(c)
		message = ""
	elif not (dragging and why == "nothing to remove"):
		message = why


func _zoom(f: float) -> void:
	if cam:
		cam.zoom = (cam.zoom * f).clamp(Vector2(0.3, 0.3), Vector2(3, 3))


func _save() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(grid.to_dict(), "  "))
	message = "saved to " + ProjectSettings.globalize_path(SAVE_PATH)


func _load() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		message = "no saved ship yet (Ctrl+S saves)"
		return
	var d = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	message = grid.load_dict(d) if d is Dictionary else "save file is not valid JSON"
	if message == "":
		message = "ship loaded"


func _update_hud() -> void:
	if hud == null:
		return
	var keys := []
	for i in defs.ids().size():
		var id := defs.ids()[i]
		var label := "[%d] %s" % [i + 1, defs.get_def(id).get("name", id)]
		keys.append(("> " + label + " <") if id == selected else label)
	hud.text = "HULLSCRAP  build mode\n%s\nLMB place   RMB remove   wheel zoom   Ctrl+S save   Ctrl+L load\ntiles %d   cost %d%s" % [
		"   ".join(keys), grid.tiles.size(), grid.total_cost(), ("\n" + message) if message != "" else ""]


func _draw() -> void:
	for c in grid.hull:
		draw_rect(cell_rect(c), Color("#141922"))
		draw_rect(cell_rect(c), Color(1, 1, 1, 0.05), false, 1.0)
	for c in grid.tiles:
		_draw_tile(c, grid.tiles[c])
	if grid.in_bounds(hover):
		var ok := grid.can_place(selected, hover) == ""
		var r := cell_rect(hover).grow(-1)
		var tint := Color(0.35, 1, 0.45) if ok else Color(1, 0.35, 0.35)
		draw_rect(r, Color(defs.color(selected), 0.45))
		draw_rect(r, tint, false, 2.0)


## Placeholder look: flat shapes until real art lands (see docs/PLAN.md, milestone 8).
func _draw_tile(c: Vector2i, id: String) -> void:
	var r := cell_rect(c)
	var col := defs.color(id)
	var def := defs.get_def(id)
	if def.get("door", false):
		draw_rect(r, defs.color("floor") if defs.has("floor") else col.darkened(0.5))
		var across_x := grid._is_solid(c + Vector2i.LEFT) and grid._is_solid(c + Vector2i.RIGHT)
		var bar := Rect2(r.position + Vector2(0, CELL * 0.4), Vector2(CELL, CELL * 0.2)) if across_x \
			else Rect2(r.position + Vector2(CELL * 0.4, 0), Vector2(CELL * 0.2, CELL))
		draw_rect(bar, col)
	elif def.get("solid", false):
		draw_rect(r, col)
		draw_rect(r.grow(-3), col.lightened(0.12))
	else:
		draw_rect(r, col)
		draw_rect(r.grow(-1), col.lightened(0.05), false, 1.0)
