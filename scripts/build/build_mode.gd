extends Node2D
## Build mode and play mode on the player's ship (from ShipSim.player_ship()). B switches.
## Build mode edits three layers through BuildSession, which pays, refunds and keeps the undo history.
## The HUD (scripts/ui/hud.gd, made here) shows the palette: Tab and Shift+Tab cycle its category tabs (Structure,
## Shapes, Systems, Weapons, Engines, Utility, Cargo: scripts/build/palette.gd) and 1-9 or a click pick a card,
## which sets the tool: a tile (group TILES, `selected`, a shape in `wall_piece`), the cable (CABLES), the conveyor belt
## (BELTS: a floor overlay laid like a cable, once a belt drive is aboard) or a system (SYSTEMS, `sel_component`, placed from the cargo). R rotates a system. A weapon or engine is a hull mount (docs/CONTENT.md 4f): point at the cell where
## its OUTSIDE half goes, in space against the outer wall face (outward is up at 0 degrees, R turns it); the
## game walks inward through the wall and puts the inside half on the floor behind it, and the ghost shows both
## halves and the wall between them. Cables: nothing to pick. A door is a piece of two cells (a crew body
## is 2x2): with Door selected the ghost is that piece, turned to fit the wall (R flips it), LMB
## places it as one step and RMB on either cell removes it all. LMB paints (a whole stroke is one undo
## step; a system is placed on release), Shift+LMB draws a straight line, Ctrl+LMB a rectangle (a
## wall makes a room); RMB does the same but removes. The ghost shows the pending edit: green = it
## would apply, red = not (the reason at the cursor, and while dragging what the stroke costs). Edits happen on mouse release.
## A wall can take a shape: T cycles the wall tool full > slope45 > slope2 > round2 (shapes.gd pieces), R turns the
## piece and Shift+R mirrors it. A piece goes down on release with its top-left cell under the mouse as one undo
## step, and its ghost is the real outline of each cell (green = it will apply, red = not, the reason at the cursor).
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
const Palette = preload("res://scripts/build/palette.gd")
const Hud = preload("res://scripts/ui/hud.gd")
const RedAlert = preload("res://scripts/sim/red_alert.gd")
const BeltArt = preload("res://scripts/view/belt_art.gd")
const Ammo = preload("res://scripts/sim/ammo.gd")
const CELL := 32
const SAVE_PATH := "user://ship.json"
const OK_TINT := Color(0.35, 1, 0.45)
const BAD_TINT := Color(1, 0.35, 0.35)
const CABLE_COLOR := Color("#d98a4e")
const BELT_COLOR := Color("#c9b878")
const FRAME_FILL := Color("#141922")  ## the empty hull frame you can build in (build mode)
const FRAME_LINE := Color(1, 1, 1, 0.08)
const O2_EMPTY := Color("#ff3b3b")
const O2_FULL := Color("#3b7bff")
const BREACH_COLOR := Color("#ffb020")
const NET_TINTS: Array[Color] = [Color("#4ad1b8"), Color("#e8c13a"), Color("#c06bff"), Color("#ff7a59"), Color("#6bb5ff"), Color("#9be564")]
const QUIET_REASONS: Array[String] = ["already there", "already a cable", "already a belt", "nothing to remove"]  ## not worth a message

## The kinds of tool a palette card puts in hand.
enum Group { TILES, SYSTEMS, CABLES, BELTS }

var sim: Node:  ## the ShipSim that owns the ships
	set(v):
		sim = v
		_sync_pause()
var crew: Node  ## the crew view, for the player's position
var picker: Node  ## the ship picker (ship_picker.gd): while it is open this node ignores input
var drift: Node  ## the map of the Drift (map_view.gd), made in _ready if the scene has none; M opens it
var shields: Node  ## the Shields tab (shield_panel.gd), made in _ready if the scene has none; H opens it
var front: Node  ## the front door (front_door.gd), if the scene has one: Esc asks it for the pause menu
var hud: Control  ## the HUD (hud.gd), made in _ready when the scene has room for it
var hostiles_source: Callable  ## () -> Array of hostile ship positions (px, the frame of ship.world_pos) for the red alert; sector space sets it
var mount_fx := {}  ## uid -> {aim (a unit vector in the ship's frame)}: tractor beams that are on, for their emitters; debris_view.gd sets it while Q is held
var build_on := true:  ## false = play mode. Build mode pauses the world (ShipSim.set_paused)
	set(v):
		build_on = v
		_sync_pause()
var combat := false:  ## a fight is on (combat_view.gd): this node ignores input and does not draw
	set(v):
		combat = v
		_sync_pause()
var group: int = Group.TILES
var tab: int = Palette.Tab.STRUCTURE  ## the palette tab on show
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
var hover_pt := Vector2.INF  ## the pointer in grid coordinates (a hull mount snaps to a sloped face near it); only used while it is inside `hover`
var message := ""
var dragging := false
var drag_button := 0
var drag_mode: int = BuildSession.Mode.PAINT
var drag_start := Vector2i.ZERO
var drag_path: Array = []  # cells a PAINT stroke went over
var ghost: Array = []  # session.preview() of the pending edit: the changes, each with a "reason"
var _session: BuildSession
var _tab_pick := {}  # palette tab -> the key of the card last picked on it
var _clock := 0.0  # seconds, for the loops of the art
var _glow: Node2D  # additive layer for the glow art
var _glow_quads: Array = []  # the glow art of this frame, handed to _glow at the end of _draw
var _doors := {}  # a door piece's first cell -> TileArt.door_progress() state
var _frame_key := -1  # hull.hash() the cached frame art below was made for
var _frame_rects: Array[Rect2] = []  # the frame as long row runs (px from the grid's corner)
var _frame_lines := PackedVector2Array()  # its grid lines, as long segments in pairs of points

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
	_fix_component()
	_refresh_ghost()
	if get_parent() != null:
		_make_hud()


## The HUD, in a canvas layer of its own (over the world and the crew, under the panels and the picker).
func _make_hud() -> void:
	var layer := CanvasLayer.new()
	layer.name = "HudLayer"
	layer.layer = 3
	hud = Hud.new()
	hud.name = "Hud"
	hud.setup(self)
	layer.add_child(hud)
	get_parent().add_child.call_deferred(layer)


## Build mode pauses the sim (crew, fires, air, heat, crafting...); play mode and fights run it. Leaving build mode
## makes ShipSim recompute the rooms and move crew out of the new walls.
func _sync_pause() -> void:
	if sim != null and sim.has_method("set_paused"):
		sim.set_paused(build_on and not combat, "build mode")


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


func cell_at(world: Vector2) -> Vector2i:
	var p := (world - _origin()) / CELL
	return Vector2i(floori(p.x), floori(p.y))


func cell_rect(c: Vector2i) -> Rect2:
	return Rect2(_origin() + Vector2(c * CELL), Vector2(CELL, CELL))


func _origin() -> Vector2:
	return ship.world_pos - Vector2(grid.size * CELL) / 2.0


func _cell_of(e: InputEventMouse) -> Vector2i:
	return cell_at((make_input_local(e) as InputEventMouse).position)


func _point_of(e: InputEventMouse) -> Vector2:
	return ((make_input_local(e) as InputEventMouse).position - _origin()) / CELL


## The pointer in grid coordinates: the exact point while it is inside the hovered cell, else that cell's middle.
func pointer() -> Vector2:
	return hover_pt if hover_pt != Vector2.INF and Vector2i(hover_pt.floor()) == hover else Vector2(hover) + Vector2(0.5, 0.5)


func _unhandled_input(e: InputEvent) -> void:
	if ship == null or combat or (picker != null and picker.visible):
		return
	if e is InputEventMouseMotion:
		hover = _cell_of(e)
		hover_pt = _point_of(e)
		_extend_path()
	elif e is InputEventMouseButton:
		hover = _cell_of(e)
		hover_pt = _point_of(e)
		if e.pressed:
			match e.button_index:
				MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT:
					if build_on:
						_begin_drag(e)
				MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
					wheel(e)
		elif dragging and e.button_index == drag_button:
			_extend_path()
			_end_drag()
	elif e is InputEventKey and e.pressed:
		_on_key(e)
	_refresh_ghost()
	queue_redraw()


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
				set_build(not build_on)
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


## Palette keys: Tab (Shift+Tab back) changes the palette tab, T the wall shape, R rotates (Shift+R mirrors a shape),
## 1-9 pick a card of the tab.
func _build_key(code: Key, shift := false) -> void:
	message = ""
	if code == KEY_TAB:
		set_tab(posmod(tab + (-1 if shift else 1), Palette.TAB_NAMES.size()))
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
		var cards := Palette.entries(tab, ship, session.cable_cost)
		if i >= 0 and i < mini(9, cards.size()):
			pick(cards[i])


## T: the next shape for the wall tool (the pieces of data/shapes.json in order, full first). With a wall in hand the
## palette follows: Structure for a full wall, Shapes for a shaped one.
func _cycle_piece() -> void:
	var ids := Shapes.piece_ids()
	wall_piece = ids[(ids.find(wall_piece) + 1) % ids.size()]
	message = "wall shape: " + wall_piece
	if not grid.tile_flag(selected, "solid"):
		message += " (pick a wall to build it)"
	elif group == Group.TILES:
		tab = Palette.Tab.STRUCTURE if wall_piece == Shapes.FULL else Palette.Tab.SHAPES
		_tab_pick[tab] = tool_key()


## Is the wall tool set to build a shaped piece: a wall tile selected in the Tiles palette and a shape other than full?
func _shaped_wall() -> bool:
	return group == Group.TILES and wall_piece != Shapes.FULL and grid.tile_flag(selected, "solid")


## Keep a valid system selected: the one chosen if this ship knows it, else the first one in the cargo.
func _fix_component() -> void:
	if ship == null:
		return
	if not ship.components.has(sel_component):
		sel_component = ""
	for id in ship.components.ids():
		if sel_component == "" and ship.inventory.count(id) > 0:
			sel_component = id


## The palette key (palette.gd) of the tool in hand.
func tool_key() -> String:
	match group:
		Group.CABLES:
			return "cable"
		Group.BELTS:
			return "belt"
		Group.SYSTEMS:
			return "part:" + sel_component
	return "piece:%s:%s" % [wall_piece, selected] if _shaped_wall() else "tile:" + selected


## The palette card of the tool in hand ({} with no system to place).
func selected_entry() -> Dictionary:
	match group:
		Group.CABLES:
			return Palette.cable_entry(ship, session.cable_cost)
		Group.BELTS:
			return Palette.belt_entry(ship)
		Group.SYSTEMS:
			return Palette.part_entry(ship, sel_component) if ship.components.has(sel_component) else {}
	return Palette.piece_entry(ship, wall_piece, selected) if _shaped_wall() else Palette.tile_entry(ship, selected)


## Take palette card `e` in hand (a cargo item that is not a part picks nothing).
func pick(e: Dictionary) -> void:
	match e.get("kind", ""):
		"tile", "piece":
			group = Group.TILES
			selected = e["id"]
			wall_piece = e["piece"]
		"cable":
			group = Group.CABLES
		"belt":
			group = Group.BELTS
		"part":
			group = Group.SYSTEMS
			sel_component = e["id"]
		_:
			return
	message = ""
	_tab_pick[tab] = e["key"]
	_refresh_ghost()


## Show palette tab `i` and take its card in hand: the one last picked there, else its first.
func set_tab(i: int) -> void:
	tab = i
	var cards := Palette.entries(tab, ship, session.cable_cost)
	var want: String = _tab_pick.get(tab, "")
	for e in cards:
		if e["key"] == want:
			pick(e)
			return
	for e in cards:
		if e["kind"] != "item":
			pick(e)
			return


## Build mode on or off (B, the mode bar). Entering it is refused on red alert (can_build()), with the reason as the message.
func set_build(on: bool) -> void:
	if on and not build_on:
		var why := can_build()
		if why != "":
			message = why
			return
	build_on = on
	message = ""
	dragging = false
	_fix_component()
	_refresh_ghost()


## "" when build mode may be entered, else why not (red_alert.gd: a hostile ship too near).
func can_build() -> String:
	return RedAlert.can_build(build_world()) if ship != null else ""


## Where the ship is and where the hostiles are, for the red alert: the enemy of a fight that is on (until it is
## wrecked), plus what hostiles_source reports.
func build_world() -> Dictionary:
	var at := ship.world_pos
	var hostiles := []
	var fight := get_node_or_null("../Combat")
	if fight != null and fight.get("active") and fight.get("session") != null:
		var ships: Array = fight.session.arena.ships
		if not ships[1].wrecked:
			hostiles.append(at + ships[1].flight.pos - ships[0].flight.pos)
	if hostiles_source.is_valid():
		hostiles.append_array(hostiles_source.call())
	return {"at": at, "hostiles": hostiles}


## The map (M in play mode, the mode bar anywhere: it leaves build mode first). Returns "map" when it opened.
func open_map() -> String:
	if drift == null:
		return ""
	if build_on:
		set_build(false)
	drift.open()
	return "map"


## A stroke whose release landed on a HUD panel ends as if it landed in the world.
func finish_drag() -> void:
	_end_drag()
	_refresh_ghost()


## The note next to the cursor: {text, bad}. While dragging, how many cells the stroke builds or clears and what it
## costs or gives back (and why some are refused); otherwise why the edit under the mouse would do nothing.
func cursor_note() -> Dictionary:
	if not build_on or ghost.is_empty():
		return {"text": "", "bad": false}
	var n := 0
	for g in ghost:
		if g["reason"] == "":
			n += 1
	if n == 0 or not dragging:
		var why := _ghost_note()
		return {"text": "can't: " + why if why != "" else "", "bad": n == 0}
	var pay := {}
	var back := {}
	for id in session.last_preview_cost:
		if ship.components.has(id):
			continue  # a part from the cargo, not a material
		var v := int(session.last_preview_cost[id])
		if v > 0:
			pay[id] = v
		elif v < 0:
			back[id] = -v
	var words: Array[String] = ["%d %s" % [n, "cell" if n == 1 else "cells"]]
	if not pay.is_empty():
		words.append("costs " + Palette.cost_text(pay))
	if not back.is_empty():
		words.append("gives back " + Palette.cost_text(back))
	var refused := ghost.size() - n
	var why := ""
	for g in ghost:
		if g["reason"] != "" and not g["reason"] in QUIET_REASONS:
			why = g["reason"]
			break
	if refused > 0 and why != "":
		words.append("%d refused: %s" % [refused, why])
	return {"text": ", ".join(words), "bad": refused > 0 and why != ""}


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
			return session.plan_component(sel_component, hover, rot, pointer())
		Group.CABLES:
			return session.plan_cables(mode, remove, start, hover, path)
		Group.BELTS:
			return session.plan_belts(mode, remove, start, hover, path)
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


## A wheel step on the world zooms the camera. Over a panel it never does (the panel scrolls, or nothing happens);
## the panels swallow the event themselves, and this also covers the HUD's rects.
func wheel(e: InputEventMouseButton) -> void:
	if hud != null and hud.over_ui(e.position):
		return
	_zoom(1.1 if e.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.1)


func _zoom(f: float) -> void:
	if cam:
		cam.zoom = (cam.zoom * f).clamp(Vector2(0.06, 0.06), Vector2(3, 3))  # far out: the ship in the sector


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


# --- HUD (scripts/ui/hud.gd draws it; these are the words and numbers it reads) ---

## A power figure: whole numbers plain, line-adjusted ones (5.4) with one decimal.
func _num(v: float) -> String:
	return Palette.num(v)


## The air where the soldier stands: {pressure: 0..1, or -1 in a doorway or with no soldier yet; breach: the room is open to space}.
func player_o2() -> Dictionary:
	var player = crew.get("player") if crew != null else null
	var room: int = ship.atmosphere.room_at(player.cell()) if player != null else -1
	if room < 0:
		return {"pressure": -1.0, "breach": false}
	return {"pressure": ship.atmosphere.pressure_of(room), "breach": _breached(room)}


## Is the room open to space: not sealed, or with an open door to space?
func _breached(room_id: int) -> bool:
	if not ship.atmosphere.rooms[room_id]["sealed"]:
		return true
	for d in ship.atmosphere.doors:
		if grid.is_door_open(d["cell"]) and (d["a"] == room_id and d["b"] == Rooms.SPACE or d["b"] == room_id and d["a"] == Rooms.SPACE):
			return true
	return false


## The key hints of the mode (the HUD shows them over the mode bar).
func _controls_text() -> String:
	if not build_on:
		var tractor := "   Q hold: tractor" if ship != null and ship.components.instances.values().any(func(i): return str(ship.components.def(i["id"]).get("family", "")) == "tractor") else ""
		return "WASD walk   click a marker: course   E at the helm: fly%s   middle-click: send crew   E door   O oxygen   P power   K fight (Shift+K rammer)   M map   N new ship   B build   Ctrl+S/L save/load   wheel zoom" % tractor
	var how := "LMB paint   Shift+LMB line   Ctrl+LMB rectangle   RMB remove"
	if group == Group.TILES:
		how = "LMB paint   Shift+LMB line   Ctrl+LMB rectangle (wall = room)   RMB remove" + ("   T shape" if grid.tile_flag(selected, "solid") else "")
		if _shaped_wall():
			how = "LMB place %s (top-left cell on the mouse)   RMB remove   T shape   R rotate   Shift+R mirror" % wall_piece
		elif grid.tile_flag(selected, "door"):
			how = "LMB place a 2-cell door in a wall   RMB remove   R flip"
	elif group == Group.SYSTEMS:
		how = "LMB place (a weapon or engine: its outside half on the mouse)   RMB remove   R rotate   F repair"
	elif group == Group.BELTS:
		how = "LMB lay belt   Shift+LMB line   Ctrl+LMB rectangle   RMB remove (belts touch racks, guns and drives by an edge)"
	return "%s   E door   O oxygen   P power\nTab / Shift+Tab palette tab   1-9 pick   Ctrl+Z undo   Ctrl+Y redo   Ctrl+S/L save/load   wheel zoom" % how


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
	if build_on:  # the empty frame you can build in shows only in build mode, not while flying
		_draw_frame()
	var open_doors := ShipSim.open_door_cells(ship)  # doors someone opened, and doors a body is in
	for c in grid.tiles:
		_draw_tile(c, grid.tiles[c], open_doors)
	if build_on or show_power:
		_draw_cables(_network_tints() if show_power else {})
	BeltArt.draw(self, ship, _origin(), CELL, _clock)  # the conveyor belts and the ammo riding them
	Visuals.draw_wrecks(self, ship.components.wrecks, _origin(), CELL)
	_draw_components()
	if show_o2:
		_draw_oxygen()
	if show_power:
		_draw_power()
	if hud == null or not hud.over_ui(get_viewport().get_mouse_position()):  # no ghost while the mouse is on a panel
		for g in ghost:
			_draw_ghost(g)
	if _glow != null:
		_glow.show_quads(_glow_quads)


## The empty frame: a few long row runs and grid lines made once per hull (a round frame has 2600 cells), moved to the grid.
func _draw_frame() -> void:
	var key := grid.hull.hash()
	if key != _frame_key:
		_frame_key = key
		_make_frame_art()
	draw_set_transform(_origin())
	for r in _frame_rects:
		draw_rect(r, FRAME_FILL)
	if not _frame_lines.is_empty():
		draw_multiline(_frame_lines, FRAME_LINE, 1.0)
	draw_set_transform(Vector2.ZERO)


## Runs [from, to) of consecutive ints in `xs`.
static func _runs(xs: Array) -> Array:
	xs.sort()
	var out := []
	var i := 0
	while i < xs.size():
		var j := i
		while j + 1 < xs.size() and xs[j + 1] == xs[j] + 1:
			j += 1
		out.append([xs[i], xs[j] + 1])
		i = j + 1
	return out


## Fills _frame_rects and _frame_lines from the hull: each row's runs of cells, and every cell edge once, joined into long lines.
func _make_frame_art() -> void:
	var rows := {}  # y -> {x: true}: the cells
	var across := {}  # y -> {x: true}: the unit edges along the line y (cell x to x + 1)
	var down := {}  # x -> {y: true}: the unit edges along the line x
	for c in grid.hull:
		for m in [[rows, c.y, c.x], [across, c.y, c.x], [across, c.y + 1, c.x], [down, c.x, c.y], [down, c.x + 1, c.y]]:
			if not m[0].has(m[1]):
				m[0][m[1]] = {}
			m[0][m[1]][m[2]] = true
	_frame_rects = []
	_frame_lines = PackedVector2Array()
	for y in rows:
		for r in _runs(rows[y].keys()):
			_frame_rects.append(Rect2(Vector2(r[0], y) * CELL, Vector2(r[1] - r[0], 1) * CELL))
	for y in across:
		for r in _runs(across[y].keys()):
			_frame_lines.append(Vector2(r[0], y) * CELL)
			_frame_lines.append(Vector2(r[1], y) * CELL)
	for x in down:
		for r in _runs(down[x].keys()):
			_frame_lines.append(Vector2(x, r[0]) * CELL)
			_frame_lines.append(Vector2(x, r[1]) * CELL)


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
		var opts := {"powered": powered.get(uid, false), "time": _clock, "glow_out": _glow_quads}
		opts.merge(Ammo.draw_opts(ship, uid))
		if mount_fx.has(uid):
			opts["fired_ago"] = fmod(_clock, 0.3)  # a beam that is on pulses its strip
		Visuals.draw_component(self, _cells_rect(inst["cells"]), ship.components.def(inst["id"]), inst, CELL, opts)
	for uid in uids:  # the outside half and barrel of each hull mount, over the edge of the wall
		var inst: Dictionary = ship.components.instances[uid]
		if not inst["out_cells"].is_empty():
			var def: Dictionary = ship.components.def(inst["id"])
			var opts := {"powered": powered.get(uid, false), "time": _clock, "glow_out": _glow_quads}
			if mount_fx.has(uid):
				opts["fired_ago"] = fmod(_clock, 0.3)
			var out_rect := Visuals.slope_rect(def, inst, _origin(), CELL) if Mounts.is_angled(inst) else _cells_rect(inst["out_cells"])
			Visuals.draw_mount_out(self, def, inst, out_rect, _origin() + Vector2(Mounts.barrel_of(def, inst)["pivot"]) * CELL, CELL,
				mount_fx.get(uid, {}).get("aim", Vector2.ZERO), opts)


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
		"belt":
			_draw_ghost_cell(g["cell"], Color.TRANSPARENT if g.get("remove", false) else Color(BELT_COLOR, 0.45), tint)
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
		draw_rect(r, Color(tint, 0.2))
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
	draw_rect(r, Color(tint, 0.14))
	Visuals.draw_component(self, _cells_rect(cells), ship.components.def(id), {"rot": g["rot"]}, CELL, {"alpha": 0.6})
	draw_rect(r, tint, false, 2.0)
	_draw_facing(r.get_center(), g["rot"], tint)


## A hull mount about to be placed with its outside half on g["anchor"]: the outside half and barrel there, and, when the
## placement rule finds a spot behind the wall, the inside half, with the wall between them lit.
func _draw_ghost_mount(g: Dictionary, tint: Color) -> void:
	var id: String = g["id"]
	var def: Dictionary = ship.components.def(id)
	var slope: Dictionary = ship.components.plan_mount_at(grid, id, g["anchor"], g["rot"], g.get("point", Vector2.INF))
	if slope.has("angle"):  # snapped to a sloped hull face
		_draw_ghost_slope(def, slope, tint)
		return
	var out_cells := Mounts.rect_cells(Rect2i(g["anchor"], Mounts.turned(def["mount"]["outside"], g["rot"])))
	var out_rect := _cells_rect(out_cells)
	draw_rect(out_rect.grow(-1), Color(tint, 0.14))
	Visuals.draw_mount_out(self, def, {"rot": g["rot"]}, out_rect, _pivot_px(def, g["anchor"], g["rot"]), CELL, Vector2.ZERO, {"alpha": 0.6})
	draw_rect(out_rect.grow(-1), tint, false, 2.0)
	_draw_facing(out_rect.get_center(), g["rot"], tint)
	var plan: Dictionary = ship.components.plan_mount(grid, id, g["anchor"], g["rot"])
	var in_cells: Array = plan.get("cells", [])
	if plan["why"] != "":  # no spot behind a wall: show where the inside half would sit behind a one-cell wall
		var lay := Mounts.layout(def, g["anchor"], g["rot"], 1)
		in_cells = Mounts.rect_cells(lay["inside"])
		for c in lay["link"]:
			draw_rect(cell_rect(c).grow(-5), Color(tint, 0.25))
	else:
		for c in plan["link"]:
			draw_rect(cell_rect(c).grow(-5), Color(tint, 0.35))
	var in_rect := _cells_rect(in_cells)
	draw_rect(in_rect.grow(-1), Color(tint, 0.14))
	Visuals.draw_component(self, in_rect, def, {"rot": g["rot"]}, CELL, {"alpha": 0.6 if plan["why"] == "" else 0.35})
	draw_rect(in_rect.grow(-1), tint, false, 2.0)


## A hull mount about to be placed against a sloped face (`plan`: Components.plan_mount_at): the outside half turned to the
## face, the wall cells it is mounted through lit, and, when the breech fits behind it, the inside half on the grid.
func _draw_ghost_slope(def: Dictionary, plan: Dictionary, tint: Color) -> void:
	var ok: bool = plan["why"] == ""
	var ghost_inst := {"rot": plan["rot"], "angle": plan["angle"], "out_at": plan["at"]}
	var corners := Mounts.out_polygon(plan["at"], float(plan["angle"]), float(def["mount"]["outside"][0]), float(def["mount"]["outside"][1]))
	var px_poly := PackedVector2Array()
	for v in corners:
		px_poly.append(_origin() + v * CELL)
	draw_colored_polygon(px_poly, Color(tint, 0.14))
	Visuals.draw_mount_out(self, def, ghost_inst, Visuals.slope_rect(def, ghost_inst, _origin(), CELL), _origin() + Vector2(Mounts.barrel_of(def, ghost_inst)["pivot"]) * CELL, CELL, Vector2.ZERO, {"alpha": 0.6})
	px_poly.append(px_poly[0])
	draw_polyline(px_poly, tint, 2.0)
	_draw_arrow(_origin() + (corners[0] + corners[1] + corners[2] + corners[3]) / 4.0 * CELL, Mounts.dir_of(ghost_inst), tint)
	if not ok:
		return
	for c in plan["link"]:
		draw_rect(cell_rect(c).grow(-5), Color(tint, 0.35))
	var in_rect := _cells_rect(plan["cells"])
	draw_rect(in_rect.grow(-1), Color(tint, 0.14))
	Visuals.draw_component(self, in_rect, def, {"rot": plan["rot"]}, CELL, {"alpha": 0.6})
	draw_rect(in_rect.grow(-1), tint, false, 2.0)


## The arrow on a system's ghost: the way it faces (a mount's outward side), turned with R.
func _draw_facing(at: Vector2, rot: int, tint: Color) -> void:
	_draw_arrow(at, Vector2(Mounts.outward(rot)), tint)


## The same arrow along any unit vector `d` (a mount on a slope faces its true direction).
func _draw_arrow(at: Vector2, d: Vector2, tint: Color) -> void:
	var side := Vector2(-d.y, d.x)
	var tip := at + d * CELL * 0.75
	var pts := PackedVector2Array([tip, tip - d * CELL * 0.45 + side * CELL * 0.32, tip - d * CELL * 0.45 - side * CELL * 0.32])
	draw_line(at - d * CELL * 0.4, tip - d * CELL * 0.3, Color(0, 0, 0, 0.7), 7.0)
	draw_colored_polygon(pts, Color(0, 0, 0, 0.7))
	draw_line(at - d * CELL * 0.4, tip - d * CELL * 0.3, tint, 4.0)
	var inner := PackedVector2Array([tip - d * 3.0, pts[1] + (at - pts[1]).normalized() * 3.0, pts[2] + (at - pts[2]).normalized() * 3.0])
	draw_colored_polygon(inner, tint)