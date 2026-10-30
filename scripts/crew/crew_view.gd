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
const STRIDE := PI  ## walk phase (radians) per cell walked: one full leg cycle every 2 cells
const IDLE_SPEED := 2.2  ## radians per second of the breathing bob
const TURN_RATE := 14.0  ## how fast the drawn body follows the direction of movement

## Callable(cell) -> bool for doors. Auto doors: crew walk through every door and it closes behind
## them (the simulation counts a door piece as open while a body overlaps it), so there are no locks yet.
var door_passable: Callable = func(_cell: Vector2i) -> bool: return true
var player: CrewMember
var ada: CrewMember
var build: Node
var sim: Node
var _anim := {}  # CrewMember -> {last: Vector2, phase: float, angle: float, moving: bool}, for drawing only
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
	for m: CrewMember in ship.crew:
		m.resolve(ship.grid, door_passable)  # the ship changed under them (a wall built on a body)
	if player != null:
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


## WASD by keycode (any layout). Ctrl/Cmd held means a shortcut like Ctrl+S, not walking.
func _wasd() -> Vector2:
	if Input.is_key_pressed(KEY_CTRL) or Input.is_key_pressed(KEY_META):
		return Vector2.ZERO
	return Vector2(
		float(Input.is_key_pressed(KEY_D)) - float(Input.is_key_pressed(KEY_A)),
		float(Input.is_key_pressed(KEY_S)) - float(Input.is_key_pressed(KEY_W)))


## Put the starting crew on the ship once there is floor for it (Jobs.spawn_crew: the soldier and Ada
## on the body spots nearest the grid centre, two more at the beds), and find the soldier and Ada among them.
func _spawn(ship) -> void:
	if player != null and ada != null and ship.crew.has(player) and ship.crew.has(ada):
		return
	Jobs.spawn_crew(ship)
	player = null
	ada = null
	var ada_name: String = CrewMember.config()["ada"]["name"]
	for m in ship.crew:
		if m.is_player:
			player = m
		elif m.name == ada_name:
			ada = m


## Screen position of a point given in cell units.
func _world(p: Vector2) -> Vector2:
	return build.cell_rect(Vector2i.ZERO).position + p * build.CELL


## Drawing state of one person: the walk phase grows with the distance walked (the breathing
## phase with time when standing), and the drawn direction turns smoothly toward the way they face.
func _animate(m: CrewMember, dt: float) -> void:
	var a: Dictionary = _anim.get(m, {"last": m.pos, "phase": 0.0, "angle": m.facing.angle(), "moving": false})
	var moved: float = (m.pos - a["last"]).length()
	a["moving"] = moved > 0.0005
	a["phase"] += (moved * STRIDE) if a["moving"] else (dt * IDLE_SPEED)
	a["angle"] = lerp_angle(a["angle"], m.facing.angle(), 1.0 - exp(-TURN_RATE * dt))
	a["last"] = m.pos
	_anim[m] = a


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
	var a: Dictionary = _anim.get(m, {"phase": 0.0, "angle": m.facing.angle(), "moving": false})
	PersonDrawer.draw_person(self, _world(m.pos), a["angle"], a["phase"], a["moving"], look_of(m), build.CELL)
	ShipView.draw_health(self, _world(m.pos), m.hp / m.max_hp, m.is_down(), build.CELL)
