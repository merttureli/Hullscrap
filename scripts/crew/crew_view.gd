extends Node2D
## Crew on the ship: the player's soldier (WASD; hold E next to a fire, breach, broken part or
## downed crewmate to work on it), Ada (middle-click to send her) and the other NPCs, who find their
## own jobs (jobs.gd, run by ShipSim, also during a fight). This node reads input, draws the people
## (PersonDrawer, about 3 cells across), the fires and health bars, and the HUD crew line.
## A body is 2x2 cells: people stand on whole-cell body anchors (see Pathfinder).
## The ship comes from the sibling ShipSim (player_ship(), read every frame); cell size and cell
## positions from the sibling BuildMode. Crew are kept in ship.crew, which the simulation reads
## (doors, breathing, jobs).

const CrewMember = preload("res://scripts/crew/crew_member.gd")
const Pathfinder = preload("res://scripts/crew/pathfinder.gd")
const PersonDrawer = preload("res://scripts/crew/person_drawer.gd")
const Jobs = preload("res://scripts/crew/jobs.gd")
const ShipView = preload("res://scripts/view/ship_view.gd")
const Art = preload("res://scripts/view/art.gd")
const AIM_DEAD_ZONE := 0.3  ## cells: with the mouse this close to the player, the aim stays where it was

## Callable(cell) -> bool for doors. Auto doors: crew walk through every door and it closes behind
## them (the simulation counts a door piece as open while a body overlaps it), so there are no locks yet.
var door_passable: Callable = func(_cell: Vector2i) -> bool: return true
var player: CrewMember
var ada: CrewMember
var build: Node
var sim: Node
## Scripts and tests aim the player here (a world point) instead of with the mouse.
var aim_override: Variant = null
var _anim := {}  # CrewMember -> PersonDrawer.new_state(): {last, phase, angle, aim, moving}, for drawing only
var _clock := 0.0  # for the flicker of the fires
var _layer: CanvasLayer  # the HUD crew line
var _line: Label


func _ready() -> void:
	build = get_node_or_null("../BuildMode")
	sim = get_node_or_null("../ShipSim")
	_layer = CanvasLayer.new()
	_layer.layer = 2
	_line = Label.new()
	_line.anchor_top = 1.0
	_line.anchor_bottom = 1.0
	_line.offset_left = 14.0
	_line.offset_top = -36.0
	_line.offset_right = 1500.0
	_line.offset_bottom = -10.0
	_line.add_theme_color_override("font_color", Color(0.85, 0.9, 1))
	_line.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_line.add_theme_constant_override("outline_size", 6)
	_layer.add_child(_line)
	add_child(_layer)
	visibility_changed.connect(func(): _layer.visible = is_visible_in_tree())  # put away during a fight


## The ship the player is on (null until the scene is wired).
func _ship():
	return sim.player_ship() if sim != null and build != null else null


func _process(dt: float) -> void:
	var ship = _ship()
	if ship == null:
		return
	_clock += dt
	_spawn(ship)
	var frozen: bool = sim != null and bool(sim.get("paused"))  # build mode: nobody walks (ShipSim.relocate_crew sorts them out on leaving it)
	if not frozen:
		for m: CrewMember in ship.crew:
			m.resolve(ship.grid, door_passable)  # the ship changed under them (a wall built on a body)
	if player != null and not frozen:
		player.move_input(ship.grid, _wasd(), dt, door_passable)
		if Input.is_key_pressed(KEY_E) and not Input.is_key_pressed(KEY_CTRL) and sim.has_method("jobs_of"):
			sim.jobs_of(ship).hand_work(ship, player, dt)  # E held: work on what is in reach
	for m: CrewMember in ship.crew:
		_animate(m, dt)
	if _line != null:
		_line.text = Jobs.crew_line(ship)
	queue_redraw()


func _unhandled_input(e: InputEvent) -> void:
	if ada == null or _ship() == null:
		return
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_MIDDLE:
		var p: Vector2 = (make_input_local(e).position - _world(Vector2.ZERO)) / build.CELL
		var a := Pathfinder.nearest_walkable(_ship().grid, p, door_passable)  # where a body can stand nearest the click
		if a != Pathfinder.NO_CELL and (Pathfinder.centre_of(a) - p).length() <= 1.5:
			Jobs.order_move(_ship(), ada, a, door_passable)  # she leaves the job board alone for a while


## WASD by keycode (any layout). Ctrl/Cmd held means a shortcut like Ctrl+S, not walking, and so
## does the crafting panel (C) being open, whose keys must not walk the soldier about.
func _wasd() -> Vector2:
	if Input.is_key_pressed(KEY_CTRL) or Input.is_key_pressed(KEY_META):
		return Vector2.ZERO
	var craft := get_node_or_null("../CraftLayer/CraftingPanel")
	if craft != null and craft.visible:
		return Vector2.ZERO
	return Vector2(
		float(Input.is_key_pressed(KEY_D)) - float(Input.is_key_pressed(KEY_A)),
		float(Input.is_key_pressed(KEY_S)) - float(Input.is_key_pressed(KEY_W)))


## Put the starting crew on the ship once there is floor for it (Jobs.spawn_crew: the design's crew
## list, else the soldier and Ada on the body spots nearest the grid centre and two more at the beds),
## and find the soldier and Ada among them (a design may leave Ada out).
func _spawn(ship) -> void:
	var ada_name: String = CrewMember.config()["ada"]["name"]
	var wants_ada: bool = ship.crew_plan.is_empty() or ship.crew_plan.any(func(e): return e["name"] == ada_name)
	if player != null and ship.crew.has(player) and (not wants_ada or (ada != null and ship.crew.has(ada))):
		return
	Jobs.spawn_crew(ship)
	player = null
	ada = null
	for m in ship.crew:
		if m.is_player:
			player = m
		elif m.name == ada_name:
			ada = m


## Screen position of a point given in cell units.
func _world(p: Vector2) -> Vector2:
	return build.cell_rect(Vector2i.ZERO).position + p * build.CELL


## Drawing state of one person: the walk phase grows with the distance walked (the breathing
## phase with time when standing), the legs turn smoothly toward the way they move and the torso
## toward the aim (PersonDrawer.animate).
func _animate(m: CrewMember, dt: float) -> void:
	var a: Dictionary = _anim.get(m, PersonDrawer.new_state(m))
	PersonDrawer.animate(a, m, dt, _aim_of(m, a))
	_anim[m] = a


## The angle (radians, 0 = right) `m` aims at. The player aims at the mouse; the others at what
## their job is about once they stand at it, else the way they walk.
func _aim_of(m: CrewMember, a: Dictionary) -> float:
	if m.is_player:
		var at: Variant = aim_override
		if at == null and is_inside_tree():
			at = get_global_mouse_position()
		if at != null:
			var d: Vector2 = at - _world(m.pos)
			if d.length() > AIM_DEAD_ZONE * build.CELL:
				return d.angle()
		return a["aim"]
	return PersonDrawer.job_aim(m)


func _draw() -> void:
	var ship = _ship()
	if ship == null:
		return
	ShipView.draw_fire(self, ship.fires, _world(Vector2.ZERO), build.CELL, _clock)
	if ada != null:
		for c in ada.path:
			draw_circle(_world(Pathfinder.centre_of(c)), 3.0, Color(1, 0.65, 0.2, 0.35))
	for m: CrewMember in ship.crew:
		if not m.is_player:
			_draw_person(m)
	if player != null:
		_draw_person(player)


## The palette of `m`: their own, else one picked by name; darker while down.
func look_of(m: CrewMember) -> Dictionary:
	var look: Dictionary = m.look if not m.look.is_empty() else ShipView.LOOKS.get(m.name, ShipView.OTHER_LOOK)
	if m.is_down():
		look = look.duplicate()
		for k in ["suit", "hair"]:
			look[k] = Color(look[k]).darkened(0.5)
	return look


func _draw_person(m: CrewMember) -> void:
	var a: Dictionary = _anim.get(m, PersonDrawer.new_state(m))
	var clock: float = _ship().clock
	var fight: bool = sim != null and sim.has_method("jobs_of") and sim.jobs_of(_ship()).combat
	var pose := {"species": Art.crew_rig(m.rig()), "move": a["angle"], "aim": a["aim"], "phase": a["phase"], "moving": a["moving"],
		"item": PersonDrawer.item_for(m, clock, fight), "down": m.is_down(), "work": PersonDrawer.is_working(m, clock), "t": _clock}
	PersonDrawer.draw(self, _world(m.pos), pose, look_of(m), build.CELL)
	ShipView.draw_health(self, _world(m.pos), m.hp / m.max_hp, m.is_down(), build.CELL)
