extends Node2D
## Build mode and play mode on the player's ship (from ShipSim.player_ship()). B switches.
## Build mode edits three layers through BuildSession, which pays, refunds and keeps the undo history.
## Tab cycles the palette (Tiles, Systems, Cables). Tiles: 1-3 pick one. Systems: 1-9 pick a system
## from the cargo, R rotates it. A weapon or engine is a hull mount (docs/CONTENT.md 4f): point at the cell where
## its OUTSIDE half goes, in space against the outer wall face (outward is up at 0 degrees, R turns it); the
## game walks inward through the wall and puts the inside half on the floor behind it, and the ghost shows both
## halves and the wall between them. Cables: nothing to pick. A door is a piece of two cells (a crew body
## is 2x2): with Door selected the ghost is that piece, turned to fit the wall (R flips it), LMB
## places it as one step and RMB on either cell removes it all. LMB paints (a whole stroke is one undo
## step; a system is placed on release), Shift+LMB draws a straight line, Ctrl+LMB a rectangle (a
## wall makes a room); RMB does the same but removes. The ghost shows the pending edit: green = it
## would apply, red = not (the reason is in the HUD). Edits happen on mouse release.
## A wall can take a shape: T cycles the wall tool full > slope45 > slope2 > round2 (shapes.gd pieces), R turns the
## piece and Shift+R mirrors it. A piece goes down on release with its top-left cell under the mouse as one undo
## step, and its ghost is the real outline of each cell (green = it will apply, red = not, the reason in the HUD).
## Play mode has no ghost and LMB/RMB do nothing yet. Both modes: E opens/closes the door piece under the
## mouse, O shows oxygen, P shows power, Ctrl+S saves to user://ship.json, Ctrl+L loads it, wheel zooms.
## Build mode only: Ctrl+Z undo, Ctrl+Y / Ctrl+Shift+Z redo, Esc cancels a drag, F sends the nearest
## crew member to repair the system under the mouse. Play mode only: N asks the ship picker (ship_picker.gd) for another ship,
## M opens the map of the Drift (map_view.gd; the campaign is saved and loaded with the ship). H (both modes) opens the Shields tab
## (shield_panel.gd), where the shield balance of the ship is set. Esc (when it has nothing to cancel) asks the front door
## (front_door.gd) for the pause menu; F1 (How to play) is the help panel's own.
## W, A, S, D are reserved for player movement: do not bind them without a modifier.

const ShipGrid = preload("res://scripts/ship/ship_grid.gd")
const Rooms = preload("res://scripts/sim/rooms.gd")
const BuildSession = preload("res://scripts/ship/build_session.gd")
const Ship = preload("res://scripts/ship/ship.gd")
const Shapes = preload("res://scripts/ship/shapes.gd")
const Mounts = preload("res://scripts/ship/mounts.gd")
const ShipSim = preload("res://scripts/sim/ship_sim.gd")
const Visuals = preload("res://scripts/view/visuals.gd")
const TileArt = preload("res://scripts/view/tile_art.gd")
const GlowLayer = preload("res://scripts/view/glow_layer.gd")
const MapView = preload("res://scripts/ui/map_view.gd")
const ShieldPanel = preload("res://scripts/ui/shield_panel.gd")
const CELL := 32
const SAVE_PATH := "user://ship.json"
const OK_TINT := Color(0.35, 1, 0.45)
const BAD_TINT := Color(1, 0.35, 0.35)
const CABLE_COLOR := Color("#d98a4e")
const O2_EMPTY := Color("#ff3b3b")
const O2_FULL := Color("#3b7bff")
const BREACH_COLOR := Color("#ffb020")
const NET_TINTS: Array[Color] = [Color("#4ad1b8"), Color("#e8c13a"), Color("#c06bff"), Color("#ff7a59"), Color("#6bb5ff"), Color("#9be564")]
const HUD_EVENTS := 3  ## chronicle lines the HUD shows
const QUIET_REASONS: Array[String] = ["already there", "already a cable", "nothing to remove"]  ## not worth a message

## The palette groups Tab cycles through.
enum Group { TILES, SYSTEMS, CABLES }
const GROUP_NAMES: Array[String] = ["Tiles", "Systems", "Cables"]

var sim: Node  ## the ShipSim that owns the ships
var crew: Node  ## the crew view, for the player's position
var picker: Node  ## the ship picker (ship_picker.gd): while it is open this node ignores input
var drift: Node  ## the map of the Drift (map_view.gd), made in _ready if the scene has none; M opens it
var shields: Node  ## the Shields tab (shield_panel.gd), made in _ready if the scene has none; H opens it
var front: Node  ## the front door (front_door.gd), if the scene has one: Esc asks it for the pause menu
var build_on := true  ## false = play mode
var combat := false  ## a fight is on (combat_view.gd): this node ignores input and does not draw
var group: int = Group.TILES
var selected := ""  ## tile id
var sel_component := ""  ## system id
var rot := 0  ## quarter turns of the system being placed
var door_flip := false  ## R: put the door piece across the way it would fit by itself
var wall_piece := Shapes.FULL  ## T: the shape the wall tool builds (a piece id of shapes.gd)
var shape_rot := 0  ## quarter turns of that piece (R)
var shape_mirror := false  ## and whether it is mirrored (Shift+R)
var show_o2 := false
var show_power := false
var hover := Vector2i(-1, -1)
var message := ""
var dragging := false
var drag_button := 0
var drag_mode: int = BuildSession.Mode.PAINT
var drag_start := Vector2i.ZERO
var drag_path: Array = []  # cells a PAINT stroke went over
var ghost: Array = []  # session.preview() of the pending edit: the changes, each with a "reason"
var materials: Array[String] = []  # cargo ids shown first in the HUD, in tile-cost order
var _session: BuildSession
var _pal: Array[String] = []  # the numbered systems, see _palette()
var _clock := 0.0  # seconds, for the loops of the art
var _glow: Node2D  # additive layer for the glow art
var _glow_quads: Array = []  # the glow art of this frame, handed to _glow at the end of _draw
var _doors := {}  # a door piece's first cell -> TileArt.door_progress() state

var ship: Ship:
	get:
		return sim.player_ship() if sim != null else null
var grid: ShipGrid:
	get:
		return ship.grid if ship != null else null
var session: BuildSession:
	get:
		if _session == null or _session.ship != ship:
			_session = BuildSession.new(ship)
		return _session

@onready var hud: Label = get_node_or_null("../HUD/Label")
@onready var cam: Camera2D = get_node_or_null("../Camera2D")


func _ready() -> void:
	_glow = GlowLayer.new()
	add_child(_glow)
	sim = get_node_or_null("../ShipSim")
	crew = get_node_or_null("../Crew")
	picker = get_node_or_null("../PickerLayer/ShipPicker")
	drift = get_node_or_null("../DriftLayer/MapView")
	if drift == null and get_parent() != null:
		_make_drift()
	front = get_node_or_null("../FrontDoor")
	shields = get_node_or_null("../ShieldLayer/ShieldPanel")
	if shields == null and get_parent() != null:
		_make_shields()
	selected = grid.defs.ids()[0]
	for id in grid.defs.ids():
		_add_material(grid.cost_of(id))
	_add_material(session.cable_cost)
	_fix_component()
	_refresh_ghost()
	_update_hud()


## The Drift map and its panels, in a canvas layer of their own (above the crafting panel, under the picker).
func _make_drift() -> void:
	var layer := CanvasLayer.new()
	layer.name = "DriftLayer"
	layer.layer = 4
	drift = MapView.new()
	drift.name = "MapView"
	layer.add_child(drift)
	get_parent().add_child.call_deferred(layer)


## The Shields tab, in a canvas layer of its own (above the crafting panel, under the picker).
func _make_shields() -> void:
	var layer := CanvasLayer.new()
	layer.name = "ShieldLayer"
	layer.layer = 4
	shields = ShieldPanel.new()
	shields.name = "ShieldPanel"
	shields.sim = sim
	layer.add_child(shields)
	get_parent().add_child.call_deferred(layer)


func _process(dt: float) -> void:
	_clock += dt
	if combat:
		return
	queue_redraw()
	_update_hud()


func cell_at(world: Vector2) -> Vector2i:
	var p := (world - _origin()) / CELL
	return Vector2i(floori(p.x), floori(p.y))


func cell_rect(c: Vector2i) -> Rect2:
	return Rect2(_origin() + Vector2(c * CELL), Vector2(CELL, CELL))


func _origin() -> Vector2:
	return ship.world_pos - Vector2(grid.size * CELL) / 2.0


func _cell_of(e: InputEventMouse) -> Vector2i:
	return cell_at((make_input_local(e) as InputEventMouse).position)


func _add_material(cost: Dictionary) -> void:
	for m in cost:
		if not materials.has(m):
			materials.append(m)


func _unhandled_input(e: InputEvent) -> void:
	if ship == null or combat or (picker != null and picker.visible):
		return
	if e is InputEventMouseMotion:
		hover = _cell_of(e)
		_extend_path()
	elif e is InputEventMouseButton:
		hover = _cell_of(e)
		if e.pressed:
			match e.button_index:
				MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT:
					if build_on:
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
				if build_on:
					if e.shift_pressed:
						_redo()
					else:
						_undo()
			KEY_Y:
				if build_on:
					_redo()
			KEY_S:
				if not e.echo:
					_save()
			KEY_L:
				if not e.echo:
					_load()
	elif not e.echo:
		match e.keycode:
			KEY_E:
				_toggle_door()
			KEY_B:
				build_on = not build_on
				message = ""
				_fix_component()
			KEY_F:
				if build_on:
					_repair_under_mouse()
			KEY_O:
				show_o2 = not show_o2
			KEY_P:
				show_power = not show_power
			KEY_N:
				if not build_on and picker != null:
					picker.ask()
			KEY_M:
				if build_on:
					message = "M: switch to play mode (B) to open the map"
				elif drift != null:
					drift.open()
			KEY_H:
				if shields != null:
					shields.open()
			KEY_ESCAPE:
				if front != null:
					front.open_pause()
			_:
				if build_on:
					_build_key(e.keycode, e.shift_pressed)


## Palette keys: Tab changes group, T the wall shape, R rotates (Shift+R mirrors a shape), 1-9 pick a tile or a system.
func _build_key(code: Key, shift := false) -> void:
	message = ""
	if code == KEY_TAB:
		group = (group + 1) % GROUP_NAMES.size()
		_fix_component()
	elif code == KEY_T:
		_cycle_piece()
	elif code == KEY_R:
		if group != Group.TILES:
			rot = (rot + 1) % 4
		elif grid.tile_flag(selected, "solid"):
			if shift:
				shape_mirror = not shape_mirror
			else:
				shape_rot = (shape_rot + 1) % 4
		else:
			door_flip = not door_flip
	else:
		var i: int = code - KEY_1
		if group == Group.TILES and i >= 0 and i < grid.defs.ids().size():
			selected = grid.defs.ids()[i]
		elif group == Group.SYSTEMS and i >= 0 and i < _palette().size():
			sel_component = _palette()[i]


## T: the next shape for the wall tool (the pieces of data/shapes.json in order, full first).
func _cycle_piece() -> void:
	var ids := Shapes.piece_ids()
	wall_piece = ids[(ids.find(wall_piece) + 1) % ids.size()]
	message = "wall shape: " + wall_piece
	if not grid.tile_flag(selected, "solid"):
		message += " (pick a wall to build it)"


## Is the wall tool set to build a shaped piece: a wall tile selected in the Tiles palette and a shape other than full?
func _shaped_wall() -> bool:
	return group == Group.TILES and wall_piece != Shapes.FULL and grid.tile_flag(selected, "solid")


## The systems the number keys pick, in a fixed order: those in the cargo when the list was last
## rebuilt (switching group, mode or loading), plus any that arrived since. A system that runs out
## stays in the list (x0), so the numbers don't shift while you place things.
func _palette() -> Array[String]:
	for id in ship.components.ids():
		if ship.inventory.count(id) > 0 and not _pal.has(id):
			_pal.append(id)
	return _pal


## Rebuild the numbered list and keep a valid system selected (the first in the cargo if none is).
func _fix_component() -> void:
	if ship == null:
		return
	if not ship.components.has(sel_component):
		sel_component = ""
	_pal.clear()
	for id in ship.components.ids():
		if ship.inventory.count(id) > 0 or id == sel_component:
			_pal.append(id)
	if sel_component == "" and not _pal.is_empty():
		sel_component = _pal[0]


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
	elif r["skipped"] > 0 and not r["reason"] in QUIET_REASONS:
		message = "%d done, %d skipped: %s" % [r["applied"], r["skipped"], r["reason"]]


## The pending edit: the drag in progress, or just the cell under the mouse.
func _plan() -> Dictionary:
	var remove := dragging and drag_button == MOUSE_BUTTON_RIGHT
	var mode: int = drag_mode if dragging else BuildSession.Mode.PAINT
	var start := drag_start if dragging else hover
	var path: Array = drag_path if dragging else [hover]
	if group == Group.TILES and not remove and grid.tile_flag(selected, "door"):
		return session.plan_door(selected, hover, _door_axis())
	if not remove and _shaped_wall():
		return session.plan_piece(wall_piece, selected, hover, shape_rot, shape_mirror)
	match group:
		Group.SYSTEMS:
			if remove:
				return session.plan_component_removal(hover)
			if sel_component == "":
				return {"changes": [], "error": "no systems in cargo"}
			return session.plan_component(sel_component, hover, rot)
		Group.CABLES:
			return session.plan_cables(mode, remove, start, hover, path)
	return session.plan(mode, selected, remove, start, hover, path)


## The direction of the door piece under the mouse: the way the walls round it allow, or across that when flipped.
func _door_axis() -> Vector2i:
	var axis := grid.door_axis_at(hover)
	if door_flip:
		return Vector2i.DOWN if axis == Vector2i.RIGHT else Vector2i.RIGHT
	return axis


func _refresh_ghost() -> void:
	if not build_on:
		ghost = []
		return
	var pl := _plan()
	ghost = session.preview(pl["changes"])
	if ghost.is_empty() and pl["error"] != "" and _shaped_wall() and not (dragging and drag_button == MOUSE_BUTTON_RIGHT):
		ghost = [{"layer": "piece", "piece": wall_piece, "tile": selected, "anchor": hover, "rot": shape_rot, "mirror": shape_mirror, "reason": pl["error"]}]  # plan_piece refused: show the piece red
	if dragging:
		message = pl["error"]


func _toggle_door() -> void:
	if not grid.tile_flag(grid.get_tile(hover), "door"):
		message = "no door under the mouse"
		return
	var open := not grid.is_door_open(hover)
	grid.set_door_open(hover, open)
	message = "door opened" if open else "door closed"


func _repair_under_mouse() -> void:
	var uid := ship.components.any_at(hover)  # either half of a hull mount
	if uid < 0:
		message = "no system under the mouse"
		return
	message = sim.jobs_of(ship).order_repair(ship, uid)  # the nearest crew member goes and fixes it


## The player's ship was replaced (the picker loaded a design): forget the old ship's edit state.
func ship_replaced(text: String) -> void:
	dragging = false
	drag_path = []
	_fix_component()
	_refresh_ghost()
	message = text
	if drift != null:
		drift.new_game()  # a new ship, a new run of the Drift


func _undo() -> void:
	message = "undone" if session.undo() else "nothing to undo"


func _redo() -> void:
	message = "redone" if session.redo() else "nothing to redo"


func _zoom(f: float) -> void:
	if cam:
		cam.zoom = (cam.zoom * f).clamp(Vector2(0.2, 0.2), Vector2(3, 3))


func _save() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		message = "could not write " + ProjectSettings.globalize_path(SAVE_PATH)
		return
	f.store_string(JSON.stringify(session.to_dict(), "  "))
	message = "saved to " + ProjectSettings.globalize_path(SAVE_PATH)
	if drift != null:
		drift.save_campaign()


func _load() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		message = "no saved ship yet (Ctrl+S saves)"
		return
	var d = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	message = session.load_dict(d) if d is Dictionary else "save file is not valid JSON"
	if message == "":
		message = "ship loaded"
		_fix_component()
		if drift != null and drift.load_campaign() != "":
			message = "ship loaded (no saved campaign: a new one begins)"


# --- HUD ---

func _update_hud() -> void:
	if hud != null:
		hud.text = hud_text()
		hud.visible = picker == null or not picker.visible  # the picker has the screen


## The whole HUD: mode, palette, selection and cost, cargo, power, the oxygen where the player
## stands, the last message.
func hud_text() -> String:
	if ship == null:
		return "HULLSCRAP"
	var lines: Array[String] = ["HULLSCRAP  %s mode (B: %s)    %s    %s" % [
		"BUILD" if build_on else "PLAY", "play" if build_on else "build", _power_text(), _o2_text()]]
	if build_on:
		lines.append("palette  " + "   ".join(_marked(GROUP_NAMES, group, false)) + "   (Tab)")
		lines.append(_choices_text())
		lines.append(_selection_text())
	lines.append("cargo  " + _cargo_text())
	lines.append(_controls_text())
	var why := _ghost_note()
	if why != "":
		lines.append("can't: " + why)
	if message != "":
		lines.append(message)
	for e in ship.events.slice(-HUD_EVENTS):
		lines.append("[%d:%02d] %s" % [floori(e["t"] / 60.0), floori(e["t"]) % 60, e["text"]])
	return "\n".join(lines)


## `labels`, the chosen one wrapped in "> <"; `numbered` puts [1], [2]... in front.
func _marked(labels: Array, chosen: int, numbered: bool) -> Array[String]:
	var out: Array[String] = []
	for i in labels.size():
		var s: String = ("[%d] " % (i + 1) if numbered else "") + str(labels[i])
		out.append("> %s <" % s if i == chosen else s)
	return out


func _power_text() -> String:
	var supply := 0.0
	var demand := 0.0
	for n in ship.power_state.get("networks", []):
		supply += n["supply"]
		demand += n["demand"]
	return "power %s supply / %s demand" % [_num(supply), _num(demand)]


## A power figure: whole numbers plain, line-adjusted ones (5.4) with one decimal.
func _num(v: float) -> String:
	return "%d" % roundi(v) if is_equal_approx(v, roundf(v)) else "%.1f" % v


## Oxygen in the room the player stands in ("--" in a doorway or with no player yet).
func _o2_text() -> String:
	var player = crew.get("player") if crew != null else null
	var room: int = ship.atmosphere.room_at(player.cell()) if player != null else -1
	if room < 0:
		return "O2 --"
	return "O2 %d%%%s" % [roundi(ship.atmosphere.pressure_of(room) * 100.0), " (breach)" if _breached(room) else ""]


## Is the room open to space: not sealed, or with an open door to space?
func _breached(room_id: int) -> bool:
	if not ship.atmosphere.rooms[room_id]["sealed"]:
		return true
	for d in ship.atmosphere.doors:
		if grid.is_door_open(d["cell"]) and (d["a"] == room_id and d["b"] == Rooms.SPACE or d["b"] == room_id and d["a"] == Rooms.SPACE):
			return true
	return false


func _choices_text() -> String:
	var names: Array[String] = []
	var chosen := -1
	match group:
		Group.SYSTEMS:
			var pal := _palette()
			if pal.is_empty():
				return "(no systems in cargo)"
			for i in pal.size():
				names.append("%s x%d" % [ship.components.def(pal[i]).get("name", pal[i]), ship.inventory.count(pal[i])])
				if pal[i] == sel_component:
					chosen = i
		Group.CABLES:
			return "cable: LMB lays, RMB removes"
		_:
			var ids: Array[String] = grid.defs.ids()
			for i in ids.size():
				names.append(str(grid.defs.get_def(ids[i]).get("name", ids[i])))
				if ids[i] == selected:
					chosen = i
	return "   ".join(_marked(names, chosen, true))


func _selection_text() -> String:
	match group:
		Group.SYSTEMS:
			if sel_component == "":
				return "selected: nothing"
			var last: Vector2i = ship.components.footprint(sel_component, Vector2i.ZERO, rot).back()
			var line := "selected: %s (1 from cargo, %d held)   %dx%d   rotation %d deg" % [
				ship.components.def(sel_component).get("name", sel_component), ship.inventory.count(sel_component),
				last.x + 1, last.y + 1, rot * 90]
			if ship.components.is_mount(sel_component):
				var out := Mounts.turned(ship.components.def(sel_component)["mount"]["outside"], rot)
				line += "   + outside half %dx%d, pointing %s: put it in space against the wall" % [out.x, out.y, ["up", "right", "down", "left"][rot]]
			return line
		Group.CABLES:
			return "selected: Cable (cost %s per cell)   cables %d" % [_cost_text(session.cable_cost), ship.cables.cells.size()]
	if grid.tile_flag(selected, "door"):
		return "selected: %s piece, 2 cells (cost %s per cell)   tiles %d" % [grid.defs.get_def(selected).get("name", selected), _cost_text(grid.cost_of(selected)), grid.tiles.size()]
	if _shaped_wall():
		var size := Shapes.piece_size(wall_piece, shape_rot)
		return "selected: %s %s (%dx%d), turned %d deg%s (cost %s)   tiles %d" % [grid.defs.get_def(selected).get("name", selected), wall_piece,
			size.x, size.y, shape_rot * 90, ", mirrored" if shape_mirror else "", _cost_text(_piece_cost()), grid.tiles.size()]
	return "selected: %s (cost %s)   tiles %d" % [grid.defs.get_def(selected).get("name", selected), _cost_text(grid.cost_of(selected)), grid.tiles.size()]


## What the wall tool's piece costs: each cell by its solid area (rounded up per cell).
func _piece_cost() -> Dictionary:
	var sum := {}
	for pc in Shapes.piece_cells(wall_piece, Vector2i.ZERO, shape_rot, shape_mirror):
		var cost := grid.cost_of(selected, Shapes.area_of(pc))
		for m in cost:
			sum[m] = int(sum.get(m, 0)) + int(cost[m])
	return sum


func _cost_text(cost: Dictionary) -> String:
	var parts := []
	for m in cost:
		parts.append("%d %s" % [cost[m], m])
	return " + ".join(parts) if not parts.is_empty() else "free"


## Materials first (tile and cable costs in that order, then any other raw ids), then the systems held as items.
func _cargo_text() -> String:
	var mats: Array = materials.duplicate()
	var items := []
	var ids: Array = ship.inventory.counts.keys()
	ids.sort()
	for id in ids:
		if ship.components.has(id):
			items.append("%s x%d" % [ship.components.def(id).get("name", id), ship.inventory.count(id)])
		elif not mats.has(id):
			mats.append(id)
	var parts := []
	for id in mats:
		parts.append("%s %d" % [id, ship.inventory.count(id)])
	return "  ".join(parts) + (("   |   " + "  ".join(items)) if not items.is_empty() else "")


func _controls_text() -> String:
	if not build_on:
		return "WASD walk   middle-click send Ada   E door   O oxygen   P power   K fight (Shift+K rammer)   M map   N new ship   B build   Ctrl+S/L save/load   wheel zoom"
	var how := "LMB paint   Shift+LMB line   Ctrl+LMB rectangle   RMB remove"
	if group == Group.TILES:
		how = "LMB paint   Shift+LMB line   Ctrl+LMB rectangle (wall = room)   RMB remove" + ("   T shape" if grid.tile_flag(selected, "solid") else "")
		if _shaped_wall():
			how = "LMB place %s (top-left cell on the mouse)   RMB remove   T shape   R rotate   Shift+R mirror" % wall_piece
		elif grid.tile_flag(selected, "door"):
			how = "LMB place a 2-cell door in a wall   RMB remove   R flip"
	elif group == Group.SYSTEMS:
		how = "LMB place (a weapon or engine: its outside half on the mouse)   RMB remove   R rotate   F repair"
	return "%s   E door   O oxygen   P power\nCtrl+Z undo   Ctrl+Y redo   Ctrl+S/L save/load   wheel zoom" % how


## Why the pending edit would do nothing, when every cell of it is refused ("" otherwise).
func _ghost_note() -> String:
	if ghost.is_empty():
		return ""
	for g in ghost:
		if g["reason"] == "":
			return ""
	var why: String = ghost[0]["reason"]
	return "" if why in QUIET_REASONS else why


# --- Drawing ---

func _draw() -> void:
	if ship == null:
		return
	_glow_quads = []
	for c in grid.hull:
		draw_rect(cell_rect(c), Color("#141922"))
		draw_rect(cell_rect(c), Color(1, 1, 1, 0.05), false, 1.0)
	var open_doors := ShipSim.open_door_cells(ship)  # doors someone opened, and doors a body is in
	for c in grid.tiles:
		_draw_tile(c, grid.tiles[c], open_doors)
	if build_on or show_power:
		_draw_cables(_network_tints() if show_power else {})
	Visuals.draw_wrecks(self, ship.components.wrecks, _origin(), CELL)
	_draw_components()
	if show_o2:
		_draw_oxygen()
	if show_power:
		_draw_power()
	for g in ghost:
		_draw_ghost(g)
	if _glow != null:
		_glow.show_quads(_glow_quads)


## Placeholder look: flat shapes until real art lands (see docs/PLAN.md, milestone 8).
func _draw_tile(c: Vector2i, id: String, open_doors: Dictionary) -> void:
	var r := cell_rect(c)
	var col: Color = grid.defs.color(id)
	var def: Dictionary = grid.defs.get_def(id)
	if def.get("door", false):
		var piece := grid.door_piece(c)
		if piece[0] == c:  # the piece is drawn once, from its first cell
			_draw_door(piece, col, open_doors.has(c))
	elif def.get("solid", false):
		TileArt.solid_cell(self, r, grid, c, id, col)
	elif not TileArt.floor_tile(self, r, c):
		draw_rect(r, col)
		draw_rect(r.grow(-1), col.lightened(0.05), false, 1.0)


## A door piece: floor under it, then two leaves that meet in the middle when closed and slide back
## into the walls at both ends when open. The leaves run along the piece (the wall's direction).
func _draw_door(piece: Array[Vector2i], col: Color, open: bool) -> void:
	var floor_col: Color = grid.defs.color("floor") if grid.defs.has("floor") else col.darkened(0.5)
	var rects := []
	for p in piece:
		rects.append(cell_rect(p))
		if not TileArt.floor_tile(self, rects[-1], p):
			draw_rect(rects[-1], floor_col)
	var horizontal: bool = piece[1].x != piece[0].x if piece.size() > 1 \
		else grid._is_solid(piece[0] + Vector2i.LEFT) and grid._is_solid(piece[0] + Vector2i.RIGHT)  # a lone old-save door
	if TileArt.door_piece(self, rects, horizontal, TileArt.door_fraction(_doors, piece[0], open, _clock), _glow_quads):
		return
	var along := Vector2.RIGHT if horizontal else Vector2.DOWN
	var across := Vector2(along.y, along.x)
	var base := cell_rect(piece[0]).position
	var n := float(piece.size())
	var leaves := [[0.0, n * 0.25], [n * 0.75, n]] if open else [[0.0, n * 0.5], [n * 0.5, n]]
	for l in leaves:
		draw_rect(Rect2(base + along * (l[0] * CELL) + across * (CELL * 0.4), along * ((l[1] - l[0]) * CELL) + across * (CELL * 0.2)), col)
	if not open:  # the seam where the leaves meet
		draw_rect(Rect2(base + along * (n * 0.5 * CELL - 1.0) + across * (CELL * 0.4), along * 2.0 + across * (CELL * 0.2)), col.darkened(0.55))


## Thin lines between neighbouring cable cells, a dot on every cell. `tint`: cell -> colour (power overlay).
func _draw_cables(tint: Dictionary) -> void:
	var live := {}  # cable cells whose network has power to give: they get the lit art
	for n in ship.power_state.get("networks", []):
		if float(n["supply"]) > 0.0:
			for c in n["cells"]:
				live[c] = true
	for c in ship.cables.cells:
		if TileArt.cable(self, cell_rect(c), ship.cables.has, c, live.has(c)):  # the glow over the lit cable, not on the additive layer: systems cover cables
			continue
		var col: Color = tint.get(c, CABLE_COLOR)
		var mid := cell_rect(c).get_center()
		draw_circle(mid, 3.0, col)
		for d in [Vector2i.RIGHT, Vector2i.DOWN]:
			if ship.cables.has(c + d):
				draw_line(mid, mid + Vector2(d * CELL), col, 2.0)


func _draw_components() -> void:
	var powered: Dictionary = ship.power_state.get("powered", {})
	var uids: Array = ship.components.instances.keys()
	uids.sort()
	for uid in uids:
		var inst: Dictionary = ship.components.instances[uid]
		Visuals.draw_component(self, _cells_rect(inst["cells"]), ship.components.def(inst["id"]), inst, CELL,
			{"powered": powered.get(uid, false), "time": _clock, "glow_out": _glow_quads})
	for uid in uids:  # the outside half and barrel of each hull mount, over the edge of the wall
		var inst: Dictionary = ship.components.instances[uid]
		if not inst["out_cells"].is_empty():
			var def: Dictionary = ship.components.def(inst["id"])
			Visuals.draw_mount_out(self, def, inst, _cells_rect(inst["out_cells"]), _pivot_px(def, inst["out_anchor"], inst["rot"]), CELL, Vector2.ZERO,
				{"powered": powered.get(uid, false), "time": _clock, "glow_out": _glow_quads})


## Where the barrel of mount `def` turns, in the canvas' pixels, for an outside half at `out` turned `rot`.
func _pivot_px(def: Dictionary, out: Vector2i, rot: int) -> Vector2:
	return _origin() + Vector2(Mounts.barrel(def, out, rot)["pivot"]) * CELL


## Each room cell from red (empty) to blue (full); breached rooms get an outline.
func _draw_oxygen() -> void:
	var atmo = ship.atmosphere
	var sides := [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
	for r in atmo.rooms:
		var col: Color = O2_EMPTY.lerp(O2_FULL, atmo.pressure_of(r["id"]))
		for c in r["cells"]:
			draw_rect(cell_rect(c), Color(col, 0.45))
		if not _breached(r["id"]):
			continue
		for c in r["cells"]:
			var q := cell_rect(c)
			var corners := [q.position, q.position + Vector2(CELL, 0), q.end, q.position + Vector2(0, CELL)]
			for i in 4:
				if atmo.room_at(c + sides[i]) != r["id"]:
					draw_line(corners[i], corners[(i + 1) % 4], BREACH_COLOR, 3.0)


## cable cell -> its network's colour.
func _network_tints() -> Dictionary:
	var out := {}
	for n in ship.power_state.get("networks", []):
		for c in n["cells"]:
			out[c] = NET_TINTS[n["id"] % NET_TINTS.size()]
	return out


## Each network gets its own tint on its cables and parts, with supply/demand over its first cable.
func _draw_power() -> void:
	var font := ThemeDB.fallback_font
	for n in ship.power_state.get("networks", []):
		var col: Color = NET_TINTS[n["id"] % NET_TINTS.size()]
		for c in n["cells"]:
			draw_rect(cell_rect(c), Color(col, 0.28))
		for uid in n["members"]:
			draw_rect(_cells_rect(ship.components.instances[uid]["cells"]).grow(-1), col, false, 2.0)
		var at: Vector2 = cell_rect(n["cells"][0]).position + Vector2(0, -4)
		var text := "supply %s / demand %s" % [_num(n["supply"]), _num(n["demand"])]
		draw_string(font, at + Vector2(1, 1), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0, 0, 0, 0.8))
		draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, col.lightened(0.35))


## Bounding rectangle (screen) of a set of grid cells.
func _cells_rect(cells: Array) -> Rect2:
	var lo: Vector2i = cells[0]
	var hi: Vector2i = cells[0]
	for c in cells:
		lo = lo.min(c)
		hi = hi.max(c)
	return Rect2(_origin() + Vector2(lo * CELL), Vector2(hi - lo + Vector2i.ONE) * CELL)


## Pending edit: a placement shows what it would build, a removal a cross; green = applies, red = not.
func _draw_ghost(g: Dictionary) -> void:
	var tint := OK_TINT if g["reason"] == "" else BAD_TINT
	match g.get("layer", "tile"):
		"component":
			_draw_ghost_system(g, tint)
		"cable":
			_draw_ghost_cell(g["cell"], Color.TRANSPARENT if g.get("remove", false) else Color(CABLE_COLOR, 0.45), tint)
		"piece":
			_draw_ghost_piece(g, tint)
		_:
			var fill := Color(grid.defs.color(g["to"]), 0.45) if g["to"] != "" else Color.TRANSPARENT
			for c in _ghost_cells(g):
				_draw_ghost_cell(c, fill, tint)


## A shaped piece: each cell as the real outline of its polygon, inside a faint square showing the footprint.
func _draw_ghost_piece(g: Dictionary, tint: Color) -> void:
	var fill := Color(grid.defs.color(g["tile"]), 0.55)
	for pc in Shapes.piece_cells(g["piece"], g["anchor"], g["rot"], g["mirror"]):
		var r := cell_rect(pc["cell"])
		draw_rect(r.grow(-1), Color(tint, 0.18), false, 1.0)
		var pts := PackedVector2Array()
		for p in Shapes.cell_polygon(pc["shape"], pc["rot"], pc["mirror"]):
			pts.append(r.position + p * CELL)
		draw_colored_polygon(pts, fill)
		pts.append(pts[0])
		draw_polyline(pts, tint, 2.0)


## The cells a tile change touches: a door piece is two cells, so a door placement or the removal
## or replacement of a door cell shows both.
func _ghost_cells(g: Dictionary) -> Array[Vector2i]:
	var c: Vector2i = g["cell"]
	if g["to"] != "" and grid.tile_flag(g["to"], "door"):
		var axis: Vector2i = g.get("axis", grid.door_axis_at(c))
		return [c, c + axis]
	if grid.tile_flag(grid.get_tile(c), "door"):
		return grid.door_piece(c)
	return [c]


## One cell: `fill` for a placement, a cross when `fill` is transparent (a removal).
func _draw_ghost_cell(c: Vector2i, fill: Color, tint: Color) -> void:
	var r := cell_rect(c).grow(-1)
	if fill.a > 0.0:
		draw_rect(r, fill)
	else:
		_draw_cross(r, tint)
	draw_rect(r, tint, false, 2.0)


func _draw_cross(r: Rect2, tint: Color) -> void:
	draw_rect(r, Color(tint, 0.2))
	draw_line(r.position, r.end, tint, 2.0)
	draw_line(Vector2(r.position.x, r.end.y), Vector2(r.end.x, r.position.y), tint, 2.0)


## A system's whole (rotated) footprint; for a removal the footprint of the system under the mouse.
func _draw_ghost_system(g: Dictionary, tint: Color) -> void:
	var id: String = g.get("id", "")
	var cells: Array = []
	if id == "":  # a removal: both halves of a mount
		var uid: int = ship.components.any_at(g["cell"])
		if uid < 0:
			return
		var inst: Dictionary = ship.components.instances[uid]
		for half in [inst["cells"], inst["out_cells"]]:
			if not half.is_empty():
				_draw_cross(_cells_rect(half).grow(-1), tint)
				draw_rect(_cells_rect(half).grow(-1), tint, false, 2.0)
		return
	if ship.components.is_mount(id):
		_draw_ghost_mount(g, tint)
		return
	cells = ship.components.footprint(id, g["anchor"], g["rot"])
	var r := _cells_rect(cells).grow(-1)
	Visuals.draw_component(self, _cells_rect(cells), ship.components.def(id), {"rot": g["rot"]}, CELL, {"alpha": 0.6})
	draw_rect(r, tint, false, 2.0)


## A hull mount about to be placed with its outside half on g["anchor"]: the outside half and barrel there, and, when the
## placement rule finds a spot behind the wall, the inside half, with the wall between them lit.
func _draw_ghost_mount(g: Dictionary, tint: Color) -> void:
	var id: String = g["id"]
	var def: Dictionary = ship.components.def(id)
	var out_cells := Mounts.rect_cells(Rect2i(g["anchor"], Mounts.turned(def["mount"]["outside"], g["rot"])))
	var out_rect := _cells_rect(out_cells)
	Visuals.draw_mount_out(self, def, {"rot": g["rot"]}, out_rect, _pivot_px(def, g["anchor"], g["rot"]), CELL, Vector2.ZERO, {"alpha": 0.6})
	draw_rect(out_rect.grow(-1), tint, false, 2.0)
	var plan: Dictionary = ship.components.plan_mount(grid, id, g["anchor"], g["rot"])
	if plan["why"] != "":
		return
	for c in plan["link"]:
		draw_rect(cell_rect(c).grow(-5), Color(tint, 0.35))
	var in_rect := _cells_rect(plan["cells"])
	Visuals.draw_component(self, in_rect, def, {"rot": g["rot"]}, CELL, {"alpha": 0.6})
	draw_rect(in_rect.grow(-1), tint, false, 2.0)