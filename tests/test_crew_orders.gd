extends "res://tests/base_test.gd"
## Manual orders hold, the "Back to posts" recall, revives first when safe, and Tab zooming to your ship.

const Fixture = preload("res://tests/fixture_ship.gd")
const Jobs = preload("res://scripts/crew/jobs.gd")
const CrewMember = preload("res://scripts/crew/crew_member.gd")
const Pathfinder = preload("res://scripts/crew/pathfinder.gd")
const Posts = preload("res://scripts/crew/posts.gd")
const Shields = preload("res://scripts/combat/shields.gd")
const Ship = preload("res://scripts/ship/ship.gd")
const Session = preload("res://scripts/combat/combat_session.gd")
const CombatView = preload("res://scripts/combat/combat_view.gd")
const StationBar = preload("res://scripts/ui/station_bar.gd")
const STEP := 0.1


func _npc(p_name: String, x: int, y: int) -> CrewMember:
	return CrewMember.new(p_name, Pathfinder.centre_of(Vector2i(x, y)))


func _run(jobs: Jobs, ship: Ship, seconds: float) -> void:
	for i in roundi(seconds / STEP):
		ship.refresh()
		jobs.tick(ship, STEP)


## A ship with a posted Ada (laser), her at her post after 6 s.
func _posted() -> Dictionary:
	var ship := Fixture.room_ship()
	var laser := Fixture.put(ship, "laser_mk1", 15, 10)
	var ada := _npc("Ada", 12, 14)
	ship.crew.append(ada)
	Posts.post(ship, ada, laser)
	var jobs := Jobs.new()
	_run(jobs, ship, 6.0)
	return {"ship": ship, "laser": laser, "ada": ada, "jobs": jobs}


func test_a_manual_order_holds_and_the_crew_member_is_not_sent_back() -> void:
	var d := _posted()
	var ship: Ship = d["ship"]
	var ada: CrewMember = d["ada"]
	var jobs: Jobs = d["jobs"]
	eq(ada.job.get("type"), "man_station", "at the post first")
	check(Jobs.order_move(ship, ada, Vector2i(10, 15)), "ordered to the corner")
	check(ada.held, "an order holds")
	_run(jobs, ship, 40.0)
	check(ada.held, "still held")
	check(Pathfinder.centre_of(Vector2i(10, 15)).distance_to(ada.pos) < 2.0, "she stays where she was sent: %s" % str(ada.pos))
	check(ada.job.get("type", "") != "man_station", "no walk back to the post")


func test_healing_to_full_does_not_send_a_held_crew_member_back() -> void:
	var d := _posted()
	var ship: Ship = d["ship"]
	var ada: CrewMember = d["ada"]
	var jobs: Jobs = d["jobs"]
	ada.hurt(20.0)
	Jobs.order_move(ship, ada, Vector2i(10, 15))
	_run(jobs, ship, 20.0)
	ada.heal(100.0)
	_run(jobs, ship, 30.0)
	check(ada.pos.distance_to(Pathfinder.centre_of(Vector2i(10, 15))) < 2.0, "full health, still where she was sent")
	check(ada.held, "and held")


func test_back_to_posts_sends_them_back_and_clears_the_hold() -> void:
	var d := _posted()
	var ship: Ship = d["ship"]
	var ada: CrewMember = d["ada"]
	var jobs: Jobs = d["jobs"]
	var bob := _npc("Bob", 10, 14)
	ship.crew.append(bob)
	Jobs.order_move(ship, ada, Vector2i(10, 15))
	_run(jobs, ship, 20.0)
	eq(jobs.recall(ship), 1, "one was held")
	check(not ada.held, "the hold is cleared")
	_run(jobs, ship, 15.0)
	eq(ada.job.get("uid"), d["laser"], "Ada is back at her laser")
	eq(jobs.recall(ship), 0, "nobody is held now")


func test_recall_one_leaves_the_other_held() -> void:
	var d := _posted()
	var ship: Ship = d["ship"]
	var ada: CrewMember = d["ada"]
	var jobs: Jobs = d["jobs"]
	var bob := _npc("Bob", 10, 14)
	ship.crew.append(bob)
	bob.held = true
	ada.held = true
	eq(jobs.recall(ship, ada), 1, "just Ada")
	check(bob.held and not ada.held, "Bob stays held")


func test_a_held_crew_member_still_flees_a_burning_room() -> void:
	var d := _posted()
	var ship: Ship = d["ship"]
	var ada: CrewMember = d["ada"]
	var jobs: Jobs = d["jobs"]
	Jobs.order_move(ship, ada, Vector2i(10, 15))
	_run(jobs, ship, 10.0)
	ship.fires[ada.cell()] = 0.2
	var hp := ada.hp
	_run(jobs, ship, 6.0)
	check(ada.held, "held")
	check(ship.fires.is_empty() or ada.hp > hp - 10.0, "she dealt with the fire as any crew does (put it out): hp %s" % ada.hp)


func test_the_hold_is_saved_and_old_saves_load_as_not_held() -> void:
	var m := _npc("Ada", 12, 14)
	m.held = true
	check(CrewMember.from_dict(m.to_dict()).held, "round trip")
	var old := m.to_dict()
	old.erase("held")
	check(not CrewMember.from_dict(old).held, "an old save is not held")


# --- revives -----------------------------------------------------------------------------------

func _downed_ship() -> Dictionary:
	var ship := Fixture.room_ship()
	var down := _npc("Down", 18, 14)
	down.hurt(1000.0)
	var near := _npc("Near", 14, 14)
	var far := _npc("Far", 10, 10)
	ship.crew.append_array([down, near, far])
	return {"ship": ship, "down": down, "near": near, "far": far}


func test_the_nearest_safe_crew_member_revives_and_only_one_goes() -> void:
	var d := _downed_ship()
	var ship: Ship = d["ship"]
	var jobs := Jobs.new()
	jobs.tick(ship, STEP)
	var n := 0
	for m in [d["near"], d["far"]]:
		if m.job.get("key") == "revive:Down":
			n += 1
	eq(n, 1, "one rescuer")
	eq(d["near"].job.get("key"), "revive:Down", "the nearest")


func test_a_posted_and_held_crew_member_go_to_revive_and_return() -> void:
	var d := _downed_ship()
	var ship: Ship = d["ship"]
	var laser := Fixture.put(ship, "laser_mk1", 15, 10)
	var near: CrewMember = d["near"]
	Posts.post(ship, near, laser)
	near.held = true
	var jobs := Jobs.new()
	jobs.tick(ship, STEP)
	eq(near.job.get("key"), "revive:Down", "held and posted, still goes")
	_run(jobs, ship, 15.0)
	check(not d["down"].is_down(), "revived")
	check(near.held, "still held")
	check(near.pos.distance_to(Pathfinder.centre_of(Vector2i(14, 14))) < 2.0, "back at the held spot: %s" % str(near.pos))


func test_no_one_goes_into_fire_or_with_a_hostile_in_the_room() -> void:
	var d := _downed_ship()
	var ship: Ship = d["ship"]
	ship.fires[Vector2i(19, 15)] = 0.2
	var jobs := Jobs.new()
	jobs.tick(ship, STEP)
	check(d["near"].job.get("key") != "revive:Down" and d["far"].job.get("key") != "revive:Down", "not into a burning room")
	ship.fires.clear()
	var Intruders = load("res://scripts/crew/intruders.gd")
	var robot = Intruders.spawn(ship, "boarding_robot_mk1", Vector2(19, 12))
	check(robot != null, "a robot boards")
	d["near"].job = {}
	jobs._since = 1.0e9
	jobs.tick(ship, STEP)
	check(d["near"].job.get("key") != "revive:Down" and d["far"].job.get("key") != "revive:Down", "not with a hostile in the room")


func test_a_rescuer_taking_damage_does_not_go() -> void:
	var d := _downed_ship()
	var ship: Ship = d["ship"]
	d["near"].hurt_at = ship.clock
	d["far"].hurt_at = ship.clock
	var jobs := Jobs.new()
	jobs.tick(ship, STEP)
	check(d["near"].job.get("key") != "revive:Down" and d["far"].job.get("key") != "revive:Down", "both were just hurt")
	ship.clock += 3.0
	jobs._since = 1.0e9
	jobs.tick(ship, STEP)
	check(d["near"].job.get("key") == "revive:Down" or d["far"].job.get("key") == "revive:Down", "a few seconds on, one goes")


func test_no_air_and_no_suit_means_no_rescue() -> void:
	var d := _downed_ship()
	var ship: Ship = d["ship"]
	var jobs := Jobs.new()
	jobs.build_board(ship)
	var job: Dictionary = jobs.board.get("revive:Down", {})
	check(not job.is_empty(), "the revive is on the board")
	var room: int = ship.atmosphere.room_at(d["down"].cell())
	check(jobs._safe_rescue(ship, d["near"], job), "safe with air")
	ship.atmosphere.pressure[room] = 0.0
	check(not jobs._safe_rescue(ship, d["near"], job), "an airless room is unsafe without a suit")


# --- Tab zoom ----------------------------------------------------------------------------------

func test_the_slow_down_frames_your_ship_and_normal_frames_both() -> void:
	var s := Session.new()
	s.start(Session.load_ship("res://data/ships/pirate_raider.json"), Session.load_ship("res://data/ships/pirate_raider.json"), 3)
	var view := Vector2(1600.0, 900.0)
	var both := s.framing(view)
	var own := s.framing(view, 0.2, true)
	eq(own["center"], s.arena.ships[Session.PLAYER].flight.pos, "centred on your ship")
	check(own["zoom"] > both["zoom"], "closer than the two-ship view")
	var h: float = 2.0 * (Shields.reach(s.arena.ships[Session.PLAYER]) + 1.0) * s.arena.CELL * own["zoom"]
	check(absf(h - 900.0 * Session.SLOW_FILL) < 1.0 or own["zoom"] >= 2.0 or own["zoom"] <= 0.05, "the hull fills about 70 percent of the height: %s" % h)
	eq(CombatView.blend_framing(both, own, 0.0)["center"], both["center"], "t 0 is the normal framing")
	check(CombatView.blend_framing(both, own, 1.0)["center"].is_equal_approx(own["center"]), "t 1 is your ship")


func test_the_station_bar_has_a_back_to_posts_row() -> void:
	var strip := StationBar.size_for(3, 600.0)
	check(strip.x >= StationBar.MIN_W, "wide enough for the button")
	var head := StationBar.head_rect(strip)
	check(StationBar.button_rect(0, 3, strip).position.y >= head.end.y, "the buttons start under it")
