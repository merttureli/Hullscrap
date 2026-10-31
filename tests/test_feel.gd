extends "res://tests/base_test.gd"
## Flying and controls (the playtest 2 "feel" round): the soldier's screen-relative WASD, the mouse wheel over panels.

const CrewView = preload("res://scripts/crew/crew_view.gd")

const UP := Vector2(0, -1)  ## W on the screen


func _near(got: Vector2, want: Vector2, msg: String) -> void:
	check(got.distance_to(want) < 0.001, "%s: expected %s, got %s" % [msg, str(want), str(got)])


func _key(code: Key, down: bool) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.pressed = down
	Input.parse_input_event(e)
	Input.flush_buffered_events()


func test_screen_up_in_the_ships_frame_follows_the_way_it_is_drawn() -> void:
	_near(CrewView.screen_to_grid(UP, 0.0), Vector2(0, -1), "unturned: up is grid -y")
	_near(CrewView.screen_to_grid(UP, PI), Vector2(0, 1), "bow down the screen: up is grid +y")
	_near(CrewView.screen_to_grid(UP, PI / 2.0), Vector2(-1, 0), "turned a quarter clockwise: up is grid -x")
	_near(CrewView.screen_to_grid(UP, -PI / 2.0), Vector2(1, 0), "turned a quarter the other way: up is grid +x")
	_near(CrewView.screen_to_grid(Vector2(1, 0), PI), Vector2(-1, 0), "right on the screen is grid -x with the ship turned round")
	_near(CrewView.screen_to_grid(Vector2.ZERO, 1.0), Vector2.ZERO, "no keys, no move")
	var diag := CrewView.screen_to_grid(Vector2(1, -1), PI / 4.0)  # W+D, ship turned an eighth: an axis in the grid
	_near(diag.normalized(), Vector2(0, -1), "a diagonal on the screen can be an axis in the grid")


func test_wasd_reads_the_angle_the_view_is_drawn_at() -> void:
	var view := CrewView.new()
	_key(KEY_W, true)
	_near(view._wasd(), Vector2(0, -1), "W, ship unturned (build mode)")
	view.rotation = PI
	_near(view._wasd(), Vector2(0, 1), "W with the ship drawn at PI")
	view.rotation = PI / 2.0
	_near(view._wasd(), Vector2(-1, 0), "W with the ship drawn at PI/2")
	_key(KEY_W, false)
	_key(KEY_D, true)
	view.rotation = PI
	_near(view._wasd(), Vector2(-1, 0), "D with the ship drawn at PI")
	_key(KEY_D, false)
	_near(view._wasd(), Vector2.ZERO, "nothing held")
	view.free()
