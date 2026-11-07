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
const Structure = preload("res://scripts/ship/structure.gd")
const Shapes = preload("res://scripts/ship/shapes.gd")
const Mounts = preload("res://scripts/ship/mounts.gd")
const ShipSim = preload("res://scripts/sim/ship_sim.gd")
const Visuals = preload("res://scripts/view/visuals.gd")
const TileArt = preload("res://scripts/view/tile_art.gd")
const Art = preload("res://scripts/view/art.gd")
const GlowLayer = preload("res://scripts/view/glow_layer.gd")
const MapView = preload("res://scripts/ui/map_view.gd")
const ShieldPanel = preload("res://scripts/ui/shield_panel.gd")
const DroneView = preload("res://scripts/combat/drone_view.gd")
const BayPanel = preload("res://scripts/ui/bay_panel.gd")
const Palette = preload("res://scripts/build/palette.gd")
const Hud = preload("res://scripts/ui/hud.gd")
const Layout = preload("res://scripts/ship/layout.gd")
const FireDock = preload("res://scripts/ui/fire_dock.gd")
const RedAlert = preload("res://scripts/sim/red_alert.gd")
const BeltArt = preload("res://scripts/view/belt_art.gd")
const ArmFx = preload("res://scripts/view/arm_fx.gd")
const Ammo = preload("res://scripts/sim/ammo.gd")
const Audio = preload("res://scripts/audio/audio.gd")
const Weapons = preload("res://scripts/combat/weapons.gd")
const GunBadges = preload("res://scripts/ui/gun_badges.gd")
const Workshop = preload("res://scripts/craft/workshop.gd")
const UiKit = preload("res://scripts/ui/ui_kit.gd")
const CELL := 32
const ARC_COLORS := {"fixed": Color("#ff7a5a"), "swivel": Color("#ffc966"), "turret": Color("#6cc4ff")}  ## the firing arc wedge by aim class
const ARC_REACH := 0.25  ## the wedge's radius is this share of the gun's range ...
const ARC_MIN := 3.0  ## ... but at least this many cells ...
const ARC_MAX := 9.0  ## ... and at most this many
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
var save_block := ""  ## why the game cannot be saved now ("" = it can): the soldier is aboard another vessel (board_view.gd)
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
var _weapons: Weapons = null  # the weapon stats, read once (the arc wedge of a gun ghost)
var _tab_pick := {}  # palette tab -> the key of the card last picked on it
var _clock := 0.0  # seconds, for the loops of the art
var _glow: Node2D  # additive layer for the glow art
var bay_panel: Control  ## the kit choice of a drone bay (bay_panel.gd), made on first use
var _glow_quads: Array = []  # the glow art of this frame, handed to _glow at the end of _draw
var _doors := {}  # a door piece's first cell -> TileArt.door_progress() state
var _door_open := {}  # a door piece's first cell -> whether it was open when last drawn (a flip is heard: the door sound)
var _frame_key := -1  # hull.hash() the cached frame art below was made for
var _frame_rects: Array[Rect2] = []  # the frame as long row runs (px from the grid's corner)
var _frame_lines := PackedVector2Array()  # its grid lines, as long segments in pairs of points
var _tiles: Node2D  # the frame and every tile but the doors, drawn behind this node and only again when they change (_sync_tiles)
var _tiles_key := []  # what _tiles was drawn from
var _door_cells: Array[Vector2i] = []  # the door cells, in tile order: _draw draws the doors every frame (they slide and are heard)

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
			_session.auto_floor = true
		return _session

@onready var cam: Camera2D = get_node_or_null("../Camera2D")
const FOCUS_HOLD := 3.0  ## seconds the camera holds on the damaged block the wrench pointed at
var _focus_cell := Vector2i(-1, -1)  # the damaged block the camera is on
var _focus_t := 0.0  # seconds it still holds there
var _focus_on := false  # the camera's offset is this node's to move (it eases back to 0 when the hold is over)
const PAN_SPEED := 700.0  ## px/s of world the arrow keys pan the build view at (at zoom 1: the speed on screen follows the zoom)
const PAN_KEYS: Array[Key] = [KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN]
var pan := Vector2.ZERO  ## the build view's offset from where the camera sits (world px): MMB drag, arrow keys, Home resets
var _panning := false  # the middle button is held on the world
var _pan_held := {}  # arrow key -> true: pressed on the world (a key a panel took never gets here); Input says when it was let go
var upgrade_uid := -1  ## the fabricator whose upgrade card is open (a click or U on it opens it, a second one pays): -1 for none
var upgrade_flash := 0.0  # seconds the flash over an upgraded fabricator still runs
var _focus_seen := {}  # damaged cells the wrench has already shown, so pressing it again goes on to the next


func _ready() -> void:
	_tiles = Node2D.new()
	_tiles.show_behind_parent = true
	_tiles.draw.connect(_draw_tiles)
	add_child(_tiles)
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
	var dock := FireDock.new()  # the fire groups of the placed guns, drag a chip to another section
	dock.name = "FireDock"
	dock.bind(self)
	layer.add_child(dock)
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
		_focus_t = 0.0
		_focus_on = false
		_panning = false
		return
	_follow_focus(dt)
	_pan_keys(dt)
	upgrade_flash = maxf(0.0, upgrade_flash - dt)
	queue_redraw()


## The wrench in the top bar was clicked: the camera centres on the damaged block nearest to where it looks, and on the
## next one each time it is pressed again. False when nothing is damaged (or there is no camera).
func focus_damaged() -> bool:
	var list := Structure.damaged(ship)
	if list.is_empty() or cam == null:
		return false
	var eye: Vector2 = transform.affine_inverse() * (cam.position + cam.offset)  # where the camera looks, in this node's own coordinates
	var best := -1
	for pass_no in 2:
		var near := INF
		for i in list.size():
			var c: Vector2i = list[i]["cell"]
			var d := eye.distance_squared_to(cell_rect(c).get_center())
			if d < near and not _focus_seen.has(c):
				near = d
				best = i
		if best >= 0:
			break
		_focus_seen.clear()  # every damaged block has had its turn: start over
	_focus_cell = list[best]["cell"]
	_focus_seen[_focus_cell] = true
	_focus_t = FOCUS_HOLD
	_focus_on = true
	return true


## Ease the camera onto the block the wrench pointed at, hold it there a moment, then ease back.
func _follow_focus(dt: float) -> void:
	if cam == null or not _focus_on:
		return
	if _focus_t > 0.0:
		_focus_t -= dt
		var want: Vector2 = transform * cell_rect(_focus_cell).get_center() - cam.position
		cam.offset = cam.offset.lerp(want, minf(dt * 8.0, 1.0))
	else:
		cam.offset = cam.offset.lerp(pan, minf(dt * 5.0, 1.0))  # back to where the pan has the view
		if cam.offset.distance_to(pan) < 1.0:
			cam.offset = pan
			_focus_on = false


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
	if pan_input(e):
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
					if e.button_index == MOUSE_BUTTON_RIGHT and build_on and chip_click((make_input_local(e) as InputEventMouse).position):
						get_viewport().set_input_as_handled()
						return
					if build_on and e.button_index == MOUSE_BUTTON_LEFT and e.alt_pressed and open_bay_panel(hover):
						pass  # Alt+click on a drone bay: its kit choice
					elif build_on and e.button_index == MOUSE_BUTTON_LEFT and _fab_click(e):
						get_viewport().set_input_as_handled()
					elif build_on:
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


## Open the kit choice of the drone bay at cell `c` (K over it, or Alt+click). False when there is no bay there.
func open_bay_panel(c: Vector2i) -> bool:
	var uid: int = ship.components.any_at(c)
	if uid < 0 or str(ship.components.def(ship.components.instances[uid]["id"]).get("family", "")) != "drone_bay":
		return false
	if bay_panel == null and hud != null:
		bay_panel = BayPanel.new()
		bay_panel.name = "BayPanel"
		hud.add_child(bay_panel)
	if bay_panel == null:
		return false
	bay_panel.open(ship, uid, get_viewport().get_mouse_position() if is_inside_tree() else Vector2(400, 300))
	return true


## A left click in build mode on the fabricator (any palette tab, a part or nothing in hand): the first opens its upgrade card, a second
## one pays for the next level. True when the click was used up. A click elsewhere closes the card and goes on as usual.
func _fab_click(e: InputEventMouseButton) -> bool:
	var uid := ship.components.at(hover)
	var is_fab: bool = uid >= 0 and ship.components.instances[uid]["id"] == Workshop.FAB
	if is_fab and not e.ctrl_pressed and not e.shift_pressed:  # (whatever the palette tab: the default one is Tiles, which used to let the click through to a drag)
		_fab_use(uid)
		return true
	upgrade_uid = -1
	return false


## The upgrade card of fabricator `uid` (click or U): opens it, and pays the next level when it is already open. Not a fabricator: nothing.
func _fab_use(uid: int) -> void:
	if uid < 0 or not ship.components.instances.has(uid) or ship.components.instances[uid]["id"] != Workshop.FAB:
		return
	if upgrade_uid != uid:
		upgrade_uid = uid
		message = ""
		Audio.fx(self, "click")
		return
	var why := Workshop.upgrade(ship, uid)
	if why != "":
		message = why
		Audio.fx(self, "invalid")
		return
	message = "Fabricator upgraded to level %d" % int(ship.components.instances[uid]["fab_level"])
	upgrade_flash = 0.7
	Audio.fx(self, "unlock")
	ship.mark_dirty()


## The build view's own input: a middle-button drag, the arrow keys and Home. True when the event was a middle click or one of those keys (it is used up);
## a mouse move that drags the view is not (the hover still follows it). Play mode has none of it: the middle button sends crew there.
func pan_input(e: InputEvent) -> bool:
	if e is InputEventMouseMotion:
		if _panning:
			if build_on:
				pan_by(-(e as InputEventMouseMotion).relative / (cam.zoom.x if cam != null else 1.0))
			else:
				_panning = false
	elif e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_MIDDLE:
		_panning = e.pressed and build_on and (hud == null or not hud.over_ui(e.position))  # (a drag moves the view)
		return build_on
	elif e is InputEventKey and e.pressed and build_on and not dragging and not e.ctrl_pressed and (e.keycode in PAN_KEYS or e.keycode == KEY_HOME):
		if e.keycode == KEY_HOME:
			reset_pan()
		else:
			_pan_held[e.keycode] = true
		return true
	return false


func _on_key(e: InputEventKey) -> void:
	if e.keycode == KEY_ESCAPE and upgrade_uid >= 0 and not dragging:
		upgrade_uid = -1
	elif e.keycode == KEY_ESCAPE and dragging:
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
			KEY_U:
				if build_on:
					_fab_use(ship.components.at(hover))
			KEY_O:
				show_o2 = not show_o2
			KEY_P:
				show_power = not show_power
			KEY_N:
				if not build_on and picker != null:
					picker.ask()
			KEY_M:
				if build_on:
					message = "Press B for play mode, then M for the map"
				elif drift != null:
					drift.open()
			KEY_H:
				if shields != null:
					shields.open()
			KEY_K:
				if build_on:
					open_bay_panel(hover)
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
		Audio.fx(self, "rotate")
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
			Audio.fx(self, "click")


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


## The degrees of the sloped hull face the mount in hand would snap to under the pointer, -1 when it is not over one (or has no mount).
func held_angle() -> float:
	if not build_on or group != Group.SYSTEMS or sel_component == "" or not ship.components.is_mount(sel_component):
		return -1.0
	var plan: Dictionary = ship.components.plan_mount_at(grid, sel_component, hover, rot, pointer())
	return float(plan["angle"]) if plan.has("angle") else -1.0


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
			Audio.fx(self, "invalid")
			return
	if on != build_on:
		Audio.fx(self, "open" if on else "close")
	build_on = on
	upgrade_uid = -1
	if not on:  # the pan belongs to build mode: play mode starts from where the camera sits
		pan = Vector2.ZERO
		_panning = false
		_pan_held.clear()
		if cam != null and not _focus_on:
			cam.offset = Vector2.ZERO
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
		if why == "" and n > 0:
			return {"text": _gun_hint(), "bad": false}
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
		Audio.fx(self, "invalid")
		return
	var r := session.apply(pl["changes"])
	message = ""
	if r["applied"] == 0:
		message = r["reason"]
		if not r["reason"] in QUIET_REASONS:
			Audio.fx(self, "invalid")
	else:
		Audio.fx(self, _edit_sound(pl["changes"]))
	if r["applied"] > 0 and r["skipped"] > 0 and not r["reason"] in QUIET_REASONS:
		message = "%d done, %d skipped: %s" % [r["applied"], r["skipped"], r["reason"]]
	if r.get("fill_note", "") != "":
		message = r["fill_note"]


## The sound of an edit that went through: a part placed, something removed, else a tile placed.
func _edit_sound(changes: Array) -> String:
	var out := "place_tile"
	for ch in changes:
		var layer := str(ch.get("layer", "tile"))
		if layer == "component" and ch.has("id"):
			return "place_part"
		if bool(ch.get("remove", false)) or (layer == "tile" and str(ch.get("to", "x")) == "") or (layer == "component" and not ch.has("id")):
			out = "remove"
	return out


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
		Audio.fx(self, "invalid")
		return
	var open := not grid.is_door_open(hover)
	grid.set_door_open(hover, open)
	message = "door opened" if open else "door closed"


func _repair_under_mouse() -> void:
	var uid := ship.components.any_at(hover)  # either half of a hull mount
	if uid < 0:
		message = "no system under the mouse"
		Audio.fx(self, "invalid")
		return
	message = sim.jobs_of(ship).order_repair(ship, uid)  # the nearest crew member goes and fixes it


## The player's ship was replaced (the picker loaded a design): forget the old ship's edit state.
func ship_replaced(text: String) -> void:
	_door_open.clear()
	dragging = false
	drag_path = []
	_fix_component()
	_refresh_ghost()
	message = text
	if drift != null:
		drift.new_game()  # a new ship, a new run of the Drift


func _undo() -> void:
	var ok := session.undo()
	message = "undone" if ok else "nothing to undo"
	Audio.fx(self, "click" if ok else "invalid")


func _redo() -> void:
	var ok := session.redo()
	message = "redone" if ok else "nothing to redo"
	Audio.fx(self, "click" if ok else "invalid")


## A wheel step on the world zooms the camera. Over a panel it never does (the panel scrolls, or nothing happens);
## the panels swallow the event themselves, and this also covers the HUD's rects.
func wheel(e: InputEventMouseButton) -> void:
	if hud != null and hud.over_ui(e.position):
		return
	_zoom(1.1 if e.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.1, e.position)


func _zoom(f: float, at := Vector2.INF) -> void:
	if cam:
		var before := cam.zoom
		cam.zoom = (cam.zoom * f).clamp(Vector2(0.06, 0.06), Vector2(3, 3))  # far out: the ship in the sector
		if build_on and at != Vector2.INF and is_inside_tree():  # towards the cursor: the world point under it stays under it
			var mid := get_viewport_rect().size / 2.0
			pan_by((at - mid) * (Vector2.ONE / before - Vector2.ONE / cam.zoom))


## The area the build view's centre may move over: the grid (the hull frame you can build in), in world px.
func pan_area() -> Rect2:
	return Rect2(_origin(), Vector2(grid.size * CELL)) if ship != null else Rect2()


## Move the build view by `d` world px, keeping its centre inside pan_area() so the ship cannot be lost off screen.
func pan_by(d: Vector2) -> void:
	if cam == null or ship == null or not build_on:
		return
	var a := pan_area()
	var centre := (cam.position + pan + d).clamp(a.position, a.end)
	pan = centre - cam.position
	if not _focus_on:
		cam.offset = pan


## The middle of the ship's hull (its built tiles' bounding box) in world px; the plate's middle for an empty one.
func hull_centre() -> Vector2:
	var lo := Vector2i(1 << 30, 1 << 30)
	var hi := Vector2i(-(1 << 30), -(1 << 30))
	for c in grid.tiles:
		lo = Vector2i(mini(lo.x, c.x), mini(lo.y, c.y))
		hi = Vector2i(maxi(hi.x, c.x), maxi(hi.y, c.y))
	return ship.world_pos if hi.x < lo.x else _origin() + (Vector2(lo) + Vector2(hi) + Vector2.ONE) * CELL / 2.0


## Home: centre the view on the ship (the middle of its hull; the grid's middle for an empty one).
func reset_pan() -> void:
	if cam == null or ship == null:
		return
	var mid := hull_centre()
	pan = Vector2.ZERO
	pan_by(mid - cam.position)


## The arrow keys held on the world pan the view while build mode is on.
func _pan_keys(dt: float) -> void:
	for k in _pan_held.keys():
		if not Input.is_key_pressed(k):
			_pan_held.erase(k)
	if _pan_held.is_empty() or not build_on or cam == null:
		return
	var dir := pan_dir(_pan_held)
	if dir != Vector2.ZERO:
		pan_by(dir.normalized() * PAN_SPEED * dt / cam.zoom.x)


## The direction the held arrow keys point (screen-up is negative y).
static func pan_dir(held: Dictionary) -> Vector2:
	return Vector2(float(held.has(KEY_RIGHT)) - float(held.has(KEY_LEFT)), float(held.has(KEY_DOWN)) - float(held.has(KEY_UP)))


func _save() -> void:
	if save_block != "":
		message = save_block
		Audio.fx(self, "error")
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		message = "could not write " + ProjectSettings.globalize_path(SAVE_PATH)
		return
	f.store_string(JSON.stringify(session.to_dict(), "  "))
	message = "saved to " + ProjectSettings.globalize_path(SAVE_PATH)
	if drift != null:
		drift.save_campaign()


## The layout buttons: "save" stores the ship as its reference layout; "hull", "parts" and "both" rebuild what is missing (layout.gd).
func layout_action(id: String) -> void:
	if ship == null or combat:
		return
	if id == "save":
		ship.layout = Layout.capture(ship)
		message = "Layout saved: %d cells, %d parts" % [ship.layout["tiles"].size(), ship.layout["parts"].size()]
		if drift != null:
			drift.save_campaign()
	elif ship.layout.is_empty():
		message = "Save a layout first"
	else:
		message = Layout.rebuild(session, ship.layout, id)["text"]


func _load() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		message = "No saved ship (Ctrl+S saves)"
		return
	var d = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	message = session.load_dict(d) if d is Dictionary else "save file is not valid JSON"
	if message == "":
		message = "ship loaded"
		_fix_component()
		if drift != null and drift.load_campaign() != "":
			message = "Ship loaded. No saved run: a new one begins"


# --- HUD (scripts/ui/hud.gd draws it; these are the words and numbers it reads) ---

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
		var tractor := "   Hold Q: tractor" if ship != null and ship.components.instances.values().any(func(i): return str(ship.components.def(i["id"]).get("family", "")) == "tractor") else ""
		return "WASD walk   E at the helm: fly   Click a marker: course%s   MMB send crew   E door   O oxygen   P power   M map   B build   K fight   N new ship   Ctrl+S/L save/load   Wheel zoom" % tractor
	var how := "LMB paint   Shift line   Ctrl rectangle   RMB remove"
	if group == Group.TILES:
		how = "LMB paint   Shift line   Ctrl rectangle (wall: a room)   RMB remove" + ("   T shape" if grid.tile_flag(selected, "solid") else "")
		if _shaped_wall():
			how = "LMB place %s   RMB remove   T shape   R rotate   Shift+R mirror" % wall_piece
		elif grid.tile_flag(selected, "door"):
			how = "LMB place door   RMB remove   R flip"
	elif group == Group.SYSTEMS:
		how = "LMB place   RMB remove   R rotate   F repair"
	elif group == Group.BELTS:
		how = "LMB lay belt   Shift line   Ctrl rectangle   RMB remove"
	return "%s   E door   O oxygen   P power\nTab palette   1-9 pick   Ctrl+Z undo   Ctrl+Y redo   Ctrl+S/L save/load   Wheel zoom (to the cursor)   MMB drag or arrows pan   Home centre" % how


## A hint for the gun about to be placed: a broadside battery or a gun strip is built for a side wall ("" for anything else).
func _gun_hint() -> String:
	for g in ghost:
		if g.get("layer", "") == "component" and g["reason"] == "":
			var def: Dictionary = ship.components.def(str(g.get("id", "")))
			if Mounts.is_mount(def) and str(def.get("shape", "")) in _aim().aim_classes.get("fixed", {}).get("wide", []):
				return "best on a side wall"
	return ""


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
	_sync_tiles()
	var open_doors := ShipSim.open_door_cells(ship)  # doors someone opened, and doors a body is in
	for c in _door_cells:
		var piece := grid.door_piece(c)
		if piece[0] == c:  # the piece is drawn once, from its first cell
			_draw_door(piece, grid.defs.color(grid.tiles[c]), open_doors.has(c))
	if build_on or show_power:
		_draw_cables(_network_tints() if show_power else {})
	BeltArt.draw(self, ship, _origin(), CELL, _clock)  # the conveyor belts and the ammo riding them
	Visuals.draw_wrecks(self, ship.components.wrecks, _origin(), CELL)
	_draw_components()
	for ch in gun_chips():
		GunBadges.draw_chip(self, ch["at"], ch["h"], ch["sty"], ch["key"])
	if show_o2:
		_draw_oxygen()
	if show_power:
		_draw_power()
	if hud == null or not hud.over_ui(get_viewport().get_mouse_position()):  # no ghost while the mouse is on a panel
		for g in ghost:
			_draw_ghost(g)
	_draw_upgrade_card()
	if _focus_t > 0.0:  # the damaged block the wrench pointed at
		draw_rect(cell_rect(_focus_cell).grow(2.0 + 3.0 * (0.5 + 0.5 * sin(_clock * 8.0))), Color("#e1a136"), false, 2.0)
	if _glow != null:
		_glow.show_quads(_glow_quads)


## The fabricator's upgrade card beside it: the next level, what it opens, its cost (red when short) and what a click does; a flash
## over the fabricator for a moment after an upgrade. Drawn at screen size whatever the zoom.
func _draw_upgrade_card() -> void:
	if upgrade_uid < 0 or not ship.components.instances.has(upgrade_uid):
		return
	var rect := _cells_rect(ship.components.instances[upgrade_uid]["cells"])
	if upgrade_flash > 0.0:
		var a := upgrade_flash / 0.7
		draw_rect(rect.grow(3.0 * (1.0 - a)), Color(0.55, 1.0, 0.8, 0.55 * a))
		draw_rect(rect.grow(2.0 + 10.0 * (1.0 - a)), Color(0.55, 1.0, 0.8, a), false, 2.0)
	var inf := Workshop.upgrade_info(ship, upgrade_uid)
	var k := 1.0 / maxf(get_global_transform_with_canvas().get_scale().x, 0.01)  # (the camera zooms and this node is scaled: the card keeps its screen size)
	var w := 280.0
	var lines := UiKit.wrap(str(inf["text"]), w - 20.0, 13)
	var h := 12.0 + 24.0 + lines.size() * 17.0 + (28.0 if int(inf["next"]) > 0 else 0.0) + 30.0
	var o := Vector2(rect.end.x + 10.0 * k, rect.position.y)  # the card's corner; sizes below are screen px times k
	UiKit.panel(self, Rect2(o, Vector2(w, h) * k))
	var fs := maxi(1, roundi(13.0 * k))
	var y := 24.0
	UiKit.text(self, "Fabricator, level %d" % int(inf["level"]), o + Vector2(10, y) * k, maxi(1, roundi(15.0 * k)), UiKit.AMBER, HORIZONTAL_ALIGNMENT_LEFT, -1.0, UiKit.bold())
	y += 8.0
	for l in lines:
		y += 17.0
		UiKit.text(self, l, o + Vector2(10, y) * k, fs, UiKit.TEXT if int(inf["next"]) > 0 else UiKit.GOOD)
	if int(inf["next"]) > 0:
		y += 26.0
		UiKit.text(self, "Cost", o + Vector2(10, y) * k, fs, UiKit.DIM_TEXT)
		var x := 50.0
		for m in inf["cost"]:
			UiKit.icon(self, m, Rect2(o + Vector2(x, y - 12.0) * k, Vector2(14, 14) * k))
			x += 16.0
			var t := str(inf["cost"][m])
			UiKit.text(self, t, o + Vector2(x, y) * k, fs, UiKit.BAD.lightened(0.2) if inf["short"].has(m) else UiKit.TEXT)
			x += UiKit.text_width(t, 13) + 10.0
		y += 22.0
		UiKit.text(self, "Click again to upgrade" if inf["can"] else "Not enough materials yet", o + Vector2(10, y) * k, maxi(1, roundi(12.0 * k)), UiKit.GOOD if inf["can"] else UiKit.DIM_TEXT)


## Redraw the _tiles layer when what it shows changed: another ship, a tile or a shape, the build mode (and the hull it frames), the art.
func _sync_tiles() -> void:
	var key := [grid, grid.tiles, grid.shapes, build_on, grid.hull if build_on else {}, _origin(), Art.root]
	if key == _tiles_key or _tiles == null:
		return
	_tiles_key = key.duplicate(true)
	_door_cells.clear()
	for c in grid.tiles:
		if grid.defs.get_def(grid.tiles[c]).get("door", false):
			_door_cells.append(c)
	_tiles.queue_redraw()


## The _tiles layer: the empty frame you can build in (only in build mode, not while flying), then the tiles but the doors.
func _draw_tiles() -> void:
	if ship == null:
		return
	if build_on:
		_draw_frame(_tiles)
	for c in grid.tiles:
		_draw_tile(_tiles, c, grid.tiles[c])


## The empty frame: a few long row runs and grid lines made once per hull (a round frame has 2600 cells), moved to the grid.
func _draw_frame(cv: CanvasItem) -> void:
	var key := grid.hull.hash()
	if key != _frame_key:
		_frame_key = key
		_make_frame_art()
	cv.draw_set_transform(_origin())
	for r in _frame_rects:
		cv.draw_rect(r, FRAME_FILL)
	if not _frame_lines.is_empty():
		cv.draw_multiline(_frame_lines, FRAME_LINE, 1.0)
	cv.draw_set_transform(Vector2.ZERO)


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
func _draw_tile(cv: CanvasItem, c: Vector2i, id: String) -> void:
	var r := cell_rect(c)
	var col: Color = grid.defs.color(id)
	var def: Dictionary = grid.defs.get_def(id)
	if def.get("door", false):
		return  # (_draw draws the doors)
	if def.get("solid", false):
		TileArt.solid_cell(cv, r, grid, c, id, col)
	elif not TileArt.floor_tile(cv, r, c):
		cv.draw_rect(r, col)
		cv.draw_rect(r.grow(-1), col.lightened(0.05), false, 1.0)


## A door piece: floor under it, then two leaves that meet in the middle when closed and slide back
## into the walls at both ends when open. The leaves run along the piece (the wall's direction).
func _draw_door(piece: Array[Vector2i], col: Color, open: bool) -> void:
	if _door_open.has(piece[0]) and _door_open[piece[0]] != open:
		Audio.fx(self, "door_open" if open else "door_close")
	_door_open[piece[0]] = open
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
		if Visuals.is_arm(ship.components.def(inst["id"])):
			opts.merge(ArmFx.opts(ship, uid))  # a healing arm points at its patient
		Visuals.draw_component(self, _cells_rect(inst["cells"]), ship.components.def(inst["id"]), inst, CELL, opts)
		if str(ship.components.def(inst["id"]).get("family", "")) == "drone_bay":  # the loaded kit sits on the cradle
			DroneView.draw_docked(self, ship.components.def(inst["id"]), inst, _cells_rect(inst["cells"]), CELL, _clock)
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


## The placed guns that have an outside half, in key order (as CombatSession.weapons() lists them): [{uid, id, name, group, aim, pd, number}].
func gun_entries() -> Array:
	var out := []
	if ship == null:
		return out
	var uids: Array = ship.components.instances.keys()
	uids.sort()
	var n := 0
	for uid in uids:
		var inst: Dictionary = ship.components.instances[uid]
		if not _aim().has(inst["id"]):
			continue
		n += 1
		if inst["out_cells"].is_empty():
			continue
		var d: Dictionary = _aim().def(inst["id"])
		out.append({"uid": uid, "id": inst["id"], "name": str(ship.components.def(inst["id"]).get("name", inst["id"])), "number": n, "aim": d["aim"],
			"group": _aim().group_in(ship.components, uid), "can_ap": _aim().can_pierce(d), "ap": bool(ship.ap_guns.get(uid, false)) and _aim().can_pierce(d),
			"pd": d["turret"] and d.get("effects") is Dictionary and d["effects"].has("intercept")})
	return out


## The fire-group chips of the placed guns (gun_badges.gd), in the canvas' pixels: [{uid, at, h, sty, key}]; none outside build mode.
## The key is the gun's number in a fight (guns by uid, as CombatSession.weapons() lists them).
func gun_chips() -> Array:
	var out := []
	if not build_on or ship == null:
		return out
	for w in gun_entries():
		out.append({"uid": w["uid"], "at": _cells_rect(ship.components.instances[w["uid"]]["out_cells"]).get_center(), "h": 24.0, "sty": GunBadges.style(w),
			"key": GunBadges.key_of(int(w["number"]) - 1)})
	return out


## A right-click on a gun's chip cycles its group (LMB, RMB, Q, AUTO); true when it hit a chip (the click is used up).
func chip_click(canvas_pos: Vector2) -> bool:
	for ch in gun_chips():
		if canvas_pos.distance_to(ch["at"]) <= ch["h"] * 0.9:
			GunBadges.cycle(ship.components, _aim(), ch["uid"])
			queue_redraw()
			return true
	return false


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
		var text := "supply %s / demand %s" % [Palette.num(n["supply"]), Palette.num(n["demand"])]
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


## The firing arc of gun `id` as a wedge about the barrel's pivot `pivot` (canvas pixels), centred on `dir`: red for a fixed gun (its gimbal),
## yellow for a swivel and blue for a turret (their arc). Its radius is the gun's range scaled down: ARC_REACH of it, between ARC_MIN and
## ARC_MAX cells, so a long gun's wedge reaches further than a short one's without filling the screen.
func _draw_arc(pivot: Vector2, dir: Vector2, id: String) -> void:
	var weapons := _aim()
	if not weapons.has(id):
		return
	var w := weapons.def(id)
	var col: Color = ARC_COLORS[str(w["aim"])]
	var half := minf(deg_to_rad(float(w["arc"]) * 0.5) if w["turret"] else deg_to_rad(float(w["gimbal"])), PI)
	var radius := clampf(float(w["range"]) / 32.0 * ARC_REACH, ARC_MIN, ARC_MAX) * CELL
	var rim := PackedVector2Array()
	var steps := maxi(2, ceili(half * 2.0 / deg_to_rad(6.0)))
	for i in steps + 1:
		rim.append(pivot + Vector2.from_angle(dir.angle() - half + 2.0 * half * i / steps) * radius)
	var fan := PackedVector2Array([pivot])
	fan.append_array(rim)
	if half < PI - 0.01:
		draw_colored_polygon(fan, Color(col, 0.18))
		draw_polyline(PackedVector2Array([rim[0], pivot, rim[rim.size() - 1]]), Color(col, 0.55), 1.5)
	else:
		draw_colored_polygon(rim, Color(col, 0.18))
	draw_polyline(rim, Color(col, 0.7), 1.5)


func _aim() -> Weapons:
	if _weapons == null:
		_weapons = Weapons.new()
	return _weapons


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
	_draw_arc(_pivot_px(def, g["anchor"], g["rot"]), Vector2(Mounts.outward(g["rot"])), id)
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
	_draw_arc(_origin() + Vector2(Mounts.barrel_of(def, ghost_inst)["pivot"]) * CELL, Mounts.dir_of(ghost_inst), str(def["id"]))
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