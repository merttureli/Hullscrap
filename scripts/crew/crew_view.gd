extends Node2D
## Crew on the ship: the player's soldier (WASD) and one NPC, Ada (middle-click a cell to send her).
## Rules live in scripts/crew/*; this node reads input and draws. Grid, cell size and cell
## positions come from the sibling BuildMode node, read every frame (a loaded ship may swap the grid).

const CrewMember = preload("res://scripts/crew/crew_member.gd")
const Pathfinder = preload("res://scripts/crew/pathfinder.gd")

## Callable(cell) -> bool for doors; whoever owns door state sets it. Invalid = every door open.
var door_passable: Callable = Callable()
var player: CrewMember
var ada: CrewMember
var build: Node


func _ready() -> void:
	build = get_node_or_null("../BuildMode")


func _process(dt: float) -> void:
	if build == null or build.grid == null:
		return
	var grid = build.grid
	_spawn(grid)
	for m: CrewMember in _crew():
		m.resolve(grid, door_passable)
	if player != null:
		player.move_input(grid, _wasd(), dt, door_passable)
	if ada != null:
		ada.step(dt)
	queue_redraw()


func _unhandled_input(e: InputEvent) -> void:
	if ada == null or build == null or build.grid == null:
		return
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_MIDDLE:
		var p: Vector2 = (make_input_local(e).position - _world(Vector2.ZERO)) / build.CELL
		ada.go_to(build.grid, Vector2i(floori(p.x), floori(p.y)), door_passable)


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


## Put the soldier, then Ada, on the walkable cells nearest the grid centre once they exist.
func _spawn(grid) -> void:
	var mid := Vector2(grid.size) / 2.0
	if player == null:
		var c := Pathfinder.nearest_walkable(grid, mid, door_passable)
		if c != Pathfinder.NO_CELL:
			player = CrewMember.new("Soldier", Vector2(c) + Vector2(0.5, 0.5))
	if player != null and ada == null:
		var c := Pathfinder.nearest_walkable(grid, mid, door_passable, player.cell())
		if c != Pathfinder.NO_CELL:
			ada = CrewMember.new("Ada", Vector2(c) + Vector2(0.5, 0.5))


## Screen position of a point given in cell units.
func _world(p: Vector2) -> Vector2:
	return build.cell_rect(Vector2i.ZERO).position + p * build.CELL


func _draw() -> void:
	if build == null or build.grid == null:
		return
	if ada != null:
		for c in ada.path:
			draw_circle(_world(Vector2(c) + Vector2(0.5, 0.5)), 2.5, Color(1, 0.65, 0.2, 0.35))
		_draw_person(ada, Color("#ff9a2e"))
	if player != null:
		_draw_person(player, Color("#2ee6e6"))


func _draw_person(m: CrewMember, col: Color) -> void:
	var c := _world(m.pos)
	var r: float = CrewMember.RADIUS * build.CELL
	draw_circle(c, r, col)
	draw_arc(c, r, 0.0, TAU, 20, col.darkened(0.45), 1.5)
	draw_line(c, c + m.facing * r * 1.6, col.darkened(0.45), 2.0)
