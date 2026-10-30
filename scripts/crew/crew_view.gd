extends Node2D
## Crew on the ship: the player's soldier (WASD) and one NPC, Ada (middle-click to send her).
## Rules live in scripts/crew/*; this node reads input and draws (PersonDrawer, about 3 cells across).
## A body is 2x2 cells: the soldier spawns, and Ada walks, on whole-cell body anchors (see Pathfinder).
## The ship comes from the sibling ShipSim (player_ship(), read every frame); cell size and cell
## positions from the sibling BuildMode. Crew are kept in ship.crew, which the simulation reads
## (doors, breathing).

const CrewMember = preload("res://scripts/crew/crew_member.gd")
const Pathfinder = preload("res://scripts/crew/pathfinder.gd")
const PersonDrawer = preload("res://scripts/crew/person_drawer.gd")
const PLAYER_LOOK := {"suit": "#33c6d6", "hair": "#2b2320", "tool": "#d7dce4"}
const ADA_LOOK := {"suit": "#e8913a", "hair": "#c2331f", "tool": "#f1d36b"}
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


func _ready() -> void:
	build = get_node_or_null("../BuildMode")
	sim = get_node_or_null("../ShipSim")


## The ship the player is on (null until the scene is wired).
func _ship():
	return sim.player_ship() if sim != null and build != null else null


func _process(dt: float) -> void:
	var ship = _ship()
	if ship == null:
		return
	var grid = ship.grid
	_spawn(ship)
	for m: CrewMember in _crew():
		m.resolve(grid, door_passable)
	if player != null:
		player.move_input(grid, _wasd(), dt, door_passable)
	if ada != null:
		ada.step(dt)
	for m: CrewMember in _crew():
		_animate(m, dt)
	queue_redraw()


func _unhandled_input(e: InputEvent) -> void:
	if ada == null or _ship() == null:
		return
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_MIDDLE:
		var p: Vector2 = (make_input_local(e).position - _world(Vector2.ZERO)) / build.CELL
		var a := Pathfinder.nearest_walkable(_ship().grid, p, door_passable)  # where a body can stand nearest the click
		if a != Pathfinder.NO_CELL and (Pathfinder.centre_of(a) - p).length() <= 1.5:
			ada.go_to(_ship().grid, a, door_passable)


func _crew() -> Array[CrewMember]:
	var out: Array[CrewMember] = []
	for m in [player, ada]:
		if m != null:
			out.append(m)
	return out


## WASD by keycode (any layout). Ctrl/Cmd held means a shortcut like Ctrl+S, not walking.
func _wasd() -> Vector2:
	if Input.is_key_pressed(KEY_CTRL) or Input.is_key_pressed(KEY_META):
		return Vector2.ZERO
	return Vector2(
		float(Input.is_key_pressed(KEY_D)) - float(Input.is_key_pressed(KEY_A)),
		float(Input.is_key_pressed(KEY_S)) - float(Input.is_key_pressed(KEY_W)))


## Put the soldier, then Ada, on the body spots (2x2 clear cells) nearest the grid centre once they exist.
func _spawn(ship) -> void:
	var grid = ship.grid
	var mid := Vector2(grid.size) / 2.0
	if player == null:
		var c := Pathfinder.nearest_walkable(grid, mid, door_passable)
		if c != Pathfinder.NO_CELL:
			player = CrewMember.new("Soldier", Pathfinder.centre_of(c))
			ship.crew.append(player)
	if player != null and ada == null:
		var c := Pathfinder.nearest_walkable(grid, mid, door_passable, player.anchor())
		if c != Pathfinder.NO_CELL:
			ada = CrewMember.new("Ada", Pathfinder.centre_of(c))
			ship.crew.append(ada)


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
	if _ship() == null:
		return
	if ada != null:
		for c in ada.path:
			draw_circle(_world(Pathfinder.centre_of(c)), 3.0, Color(1, 0.65, 0.2, 0.35))
		_draw_person(ada, ADA_LOOK)
	if player != null:
		_draw_person(player, PLAYER_LOOK)


func _draw_person(m: CrewMember, look: Dictionary) -> void:
	var a: Dictionary = _anim.get(m, {"phase": 0.0, "angle": m.facing.angle(), "moving": false})
	PersonDrawer.draw_person(self, _world(m.pos), a["angle"], a["phase"], a["moving"], look, build.CELL)
