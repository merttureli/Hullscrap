extends Node2D
## Build mode: place floors, walls and doors on the ship grid, paid for from the ship's cargo.
## All edits go through BuildSession (cost, refunds, undo); this node only reads input and draws.
## LMB paints (a whole stroke is one undo step), Shift+LMB draws a straight line, Ctrl+LMB a rectangle
## (a wall makes a room); RMB does the same but removes. The ghost cells preview the pending edit:
## green = it would apply, red = not (the reason is in the HUD). Edits happen on mouse release.
## 1-9 pick a tile, E opens/closes the door under the mouse, Ctrl+Z undo, Ctrl+Y / Ctrl+Shift+Z redo,
## Ctrl+S save to user://ship.json, Ctrl+L load it, wheel zoom, Esc cancels a drag.
## W, A, S, D are reserved for player movement: do not bind them without a modifier.

const ShipGrid = preload("res://scripts/ship/ship_grid.gd")
const TileDefs = preload("res://scripts/ship/tile_defs.gd")
const Inventory = preload("res://scripts/ship/inventory.gd")
const BuildSession = preload("res://scripts/ship/build_session.gd")
const CELL := 32
const SAVE_PATH := "user://ship.json"
const OK_TINT := Color(0.35, 1, 0.45)
const BAD_TINT := Color(1, 0.35, 0.35)

var defs: TileDefs
var grid: ShipGrid
var inventory: Inventory
var session: BuildSession
var selected := ""
var hover := Vector2i(-1, -1)
var message := ""
var dragging := false
var drag_button := 0
var drag_mode: int = BuildSession.Mode.PAINT
var drag_start := Vector2i.ZERO
var drag_path: Array = []  # cells a PAINT stroke went over
var ghost: Array = []  # session.preview() of the pending edit: [{cell, to, reason}]
var materials: Array[String] = []  # cargo ids shown in the HUD, in tile-cost order

@onready var hud: Label = get_node_or_null("../HUD/Label")
@onready var cam: Camera2D = get_node_or_null("../Camera2D")


func _ready() -> void:
	defs = TileDefs.new()
	defs.load_file("res://data/tiles.json")
	grid = ShipGrid.new(Vector2i(31, 31), defs)
	grid.fill_circle_hull(14.0)
	inventory = Inventory.new()
	inventory.load_dict(BuildSession.start_cargo())
	session = BuildSession.new(grid, inventory)
	selected = defs.ids()[0]
	for id in defs.ids():
		for m in grid.cost_of(id):
			if not materials.has(m):
				materials.append(m)
	_refresh_ghost()
	_update_hud()


func cell_at(world: Vector2) -> Vector2i:
	var p := (world - _origin()) / CELL
	return Vector2i(floori(p.x), floori(p.y))


func cell_rect(c: Vector2i) -> Rect2:
	return Rect2(_origin() + Vector2(c * CELL), Vector2(CELL, CELL))


func _origin() -> Vector2:
	return -Vector2(grid.size * CELL) / 2.0


func _cell_of(e: InputEventMouse) -> Vector2i:
	return cell_at((make_input_local(e) as InputEventMouse).position)


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventMouseMotion:
		hover = _cell_of(e)
		_extend_path()
	elif e is InputEventMouseButton:
		hover = _cell_of(e)
		if e.pressed:
			match e.button_index:
				MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT:
					_begin_drag(e)
				MOUSE_BUTTON_WHEEL_UP:
					_zoom(1.1)
				MOUSE_BUTTON_WHEEL_DOWN:
					_zoom(1.0 / 1.1)
		elif dragging and e.button_index == drag_button:
			_extend_path()
			_end_drag()
	elif e is InputEventKey and e.pressed:
		_on_key(e)
	_refresh_ghost()
	queue_redraw()
	_update_hud()


func _on_key(e: InputEventKey) -> void:
	if e.keycode == KEY_ESCAPE and dragging:
		dragging = false
		message = ""
	elif dragging:
		return
	elif e.ctrl_pressed:
		match e.keycode:
			KEY_Z:
				if e.shift_pressed:
					_redo()
				else:
					_undo()
			KEY_Y:
				_redo()
			KEY_S:
				if not e.echo:
					_save()
			KEY_L:
				if not e.echo:
					_load()
	elif not e.echo:
		if e.keycode == KEY_E:
			_toggle_door()
		else:
			var i: int = e.keycode - KEY_1
			if i >= 0 and i < defs.ids().size():
				selected = defs.ids()[i]
				message = ""


func _begin_drag(e: InputEventMouseButton) -> void:
	if dragging:
		return
	dragging = true
	drag_button = e.button_index
	if e.ctrl_pressed:
		drag_mode = BuildSession.Mode.RECT
	elif e.shift_pressed:
		drag_mode = BuildSession.Mode.LINE
	else:
		drag_mode = BuildSession.Mode.PAINT
	drag_start = hover
	drag_path = [hover]


## Keep a PAINT stroke unbroken even when the mouse skips cells between two events.
func _extend_path() -> void:
	if dragging and drag_mode == BuildSession.Mode.PAINT:
		drag_path.append_array(BuildSession.trace_cells(drag_path.back(), hover).slice(1))


func _end_drag() -> void:
	var pl := _plan()
	dragging = false
	if pl["error"] != "":
		message = pl["error"]
		return
	var r := session.apply(pl["changes"])
	message = ""
	if r["applied"] == 0:
		message = r["reason"]
	elif r["skipped"] > 0 and not r["reason"] in ["already there", "nothing to remove"]:
		message = "%d done, %d skipped: %s" % [r["applied"], r["skipped"], r["reason"]]


## The pending edit: the drag in progress, or just the cell under the mouse.
func _plan() -> Dictionary:
	if dragging:
		return session.plan(drag_mode, selected, drag_button == MOUSE_BUTTON_RIGHT, drag_start, hover, drag_path)
	return session.plan(BuildSession.Mode.PAINT, selected, false, hover, hover, [hover])


func _refresh_ghost() -> void:
	var pl := _plan()
	ghost = session.preview(pl["changes"])
	if dragging:
		message = pl["error"]


func _toggle_door() -> void:
	if not grid.tile_flag(grid.get_tile(hover), "door"):
		message = "no door under the mouse"
		return
	var open := not grid.is_door_open(hover)
	grid.set_door_open(hover, open)
	message = "door opened" if open else "door closed"


func _undo() -> void:
	message = "undone" if session.undo() else "nothing to undo"


func _redo() -> void:
	message = "redone" if session.redo() else "nothing to redo"


func _zoom(f: float) -> void:
	if cam:
		cam.zoom = (cam.zoom * f).clamp(Vector2(0.3, 0.3), Vector2(3, 3))


func _save() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		message = "could not write " + ProjectSettings.globalize_path(SAVE_PATH)
		return
	f.store_string(JSON.stringify(session.to_dict(), "  "))
	message = "saved to " + ProjectSettings.globalize_path(SAVE_PATH)


func _load() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		message = "no saved ship yet (Ctrl+S saves)"
		return
	var d = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	message = session.load_dict(d) if d is Dictionary else "save file is not valid JSON"
	if message == "":
		message = "ship loaded"


func _cost_text(cost: Dictionary) -> String:
	var parts := []
	for m in cost:
		parts.append("%d %s" % [cost[m], m])
	return " + ".join(parts) if not parts.is_empty() else "free"


func _update_hud() -> void:
	if hud == null:
		return
	var keys := []
	for i in defs.ids().size():
		var id := defs.ids()[i]
		var label := "[%d] %s" % [i + 1, defs.get_def(id).get("name", id)]
		keys.append(("> " + label + " <") if id == selected else label)
	var ids := materials.duplicate()
	var extra := inventory.counts.keys()
	extra.sort()
	for id in extra:
		if not ids.has(id):
			ids.append(id)
	var cargo := []
	for id in ids:
		cargo.append("%s %d" % [id, inventory.count(id)])
	hud.text = "HULLSCRAP  build mode\n%s\ncargo  %s\nselected: %s (cost %s)   tiles %d\n%s\n%s%s" % [
		"   ".join(keys), "  ".join(cargo),
		defs.get_def(selected).get("name", selected), _cost_text(grid.cost_of(selected)), grid.tiles.size(),
		"LMB paint   Shift+LMB line   Ctrl+LMB rectangle (wall = room)   RMB remove   E open/close door",
		"Ctrl+Z undo   Ctrl+Y redo   Ctrl+S save   Ctrl+L load   wheel zoom",
		("\n" + message) if message != "" else ""]


func _draw() -> void:
	for c in grid.hull:
		draw_rect(cell_rect(c), Color("#141922"))
		draw_rect(cell_rect(c), Color(1, 1, 1, 0.05), false, 1.0)
	for c in grid.tiles:
		_draw_tile(c, grid.tiles[c])
	for g in ghost:
		_draw_ghost(g["cell"], g["to"], g["reason"] == "")


## Pending cell: the tile's colour for a placement, a cross for a removal; green = applies, red = not.
func _draw_ghost(c: Vector2i, to: String, ok: bool) -> void:
	var tint := OK_TINT if ok else BAD_TINT
	var r := cell_rect(c).grow(-1)
	if to != "":
		draw_rect(r, Color(defs.color(to), 0.45))
	else:
		draw_rect(r, Color(tint, 0.2))
		draw_line(r.position, r.end, tint, 2.0)
		draw_line(Vector2(r.position.x, r.end.y), Vector2(r.end.x, r.position.y), tint, 2.0)
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
		var bars := [bar]
		if grid.is_door_open(c):  # open: the bar splits to both sides of the cell
			var q := CELL * 0.25
			if across_x:
				bars = [Rect2(bar.position, Vector2(q, bar.size.y)),
					Rect2(bar.position + Vector2(CELL - q, 0), Vector2(q, bar.size.y))]
			else:
				bars = [Rect2(bar.position, Vector2(bar.size.x, q)),
					Rect2(bar.position + Vector2(0, CELL - q), Vector2(bar.size.x, q))]
		for b in bars:
			draw_rect(b, col)
	elif def.get("solid", false):
		draw_rect(r, col)
		draw_rect(r.grow(-3), col.lightened(0.12))
	else:
		draw_rect(r, col)
		draw_rect(r.grow(-1), col.lightened(0.05), false, 1.0)
