extends "res://tests/base_test.gd"
## The repairs track: the breath budget (a crew member takes a job in bad air only if they can finish it on one breath, and leaves one they cannot),
## lost rooms in a fight, repairs under fire, orders for several crew, the spread key and the slow-down.

const Ship = preload("res://scripts/ship/ship.gd")
const Fixture = preload("res://tests/fixture_ship.gd")
const Jobs = preload("res://scripts/crew/jobs.gd")
const CrewMember = preload("res://scripts/crew/crew_member.gd")
const Pathfinder = preload("res://scripts/crew/pathfinder.gd")
const Evacuate = preload("res://scripts/crew/evacuate.gd")
const Posts = preload("res://scripts/crew/posts.gd")
const ShipSim = preload("res://scripts/sim/ship_sim.gd")
const BuildMode = preload("res://scripts/build/build_mode.gd")
const CrewView = preload("res://scripts/crew/crew_view.gd")
const CrewBar = preload("res://scripts/ui/crew_bar.gd")
const SlowDown = preload("res://scripts/crew/slow_down.gd")
const TimeScale = preload("res://scripts/crew/time_scale.gd")
const SlowBanner = preload("res://scripts/ui/slow_banner.gd")
const BreachPrompt = preload("res://scripts/ui/breach_prompt.gd")
const STEP := 0.1


func _npc(p_name: String, x: int, y: int, species := "human") -> CrewMember:
	return CrewMember.new(p_name, Pathfinder.centre_of(Vector2i(x, y), 1 if species == "drone" else 2), species)


func _run(jobs: Jobs, ship: Ship, seconds: float, fight := false) -> void:
	for i in roundi(seconds / STEP):
		ship.refresh()
		jobs.tick(ship, STEP, fight)


## The room ship cut in two by a wall at x 15 with a 2-cell door at y 12..13: the west room (x 9..14) and the east room (x 16..21).
func _two_rooms() -> Ship:
	var ship := Fixture.room_ship()
	for y in range(9, 17):
		ship.grid.force_tile(Vector2i(15, y), "wall")
	ship.grid.place_door("door", Vector2i(15, 12), Vector2i.DOWN)
	ship.mark_dirty()
	ship.refresh()
	return ship


func _west(ship: Ship) -> int:
	return ship.atmosphere.room_at(Vector2i(10, 12))


func _east(ship: Ship) -> int:
	return ship.atmosphere.room_at(Vector2i(18, 12))


func _types(m: CrewMember) -> String:
	return str(m.job.get("type", "")) if not m.job.is_empty() else ""


## The two rooms, a broken engine in the east room (12 s of work) and its air gone.
func _airless_engine() -> Dictionary:
	var ship := _two_rooms()
	var engine := Fixture.put(ship, "engine_mk1", 17, 10)
	ship.components.instances[engine]["status"] = "malfunction"
	ship.atmosphere.pressure[_east(ship)] = 0.0
	return {"ship": ship, "engine": engine}


# --- the breath budget ---------------------------------------------------------------------------------

func test_a_crew_member_refuses_a_job_in_bad_air_that_takes_longer_than_one_breath() -> void:
	var d := _airless_engine()
	var ship: Ship = d["ship"]
	var ada := _npc("Ada", 11, 13)
	ship.crew.append(ada)
	var jobs := Jobs.new()
	_run(jobs, ship, 3.0)
	check(_types(ada) != "repair_component", "twelve seconds of work do not fit in the twelve she has before hurt_below")
	eq(ship.atmosphere.room_at(ada.cell()), _west(ship), "she stays in the room with air")
	eq(ada.hp, ada.max_hp, "and loses no hp")


func test_a_crew_member_takes_a_short_job_in_bad_air() -> void:
	var ship := _two_rooms()
	ship.grid.hp[Vector2i(22, 12)] = 3.0  # one hp missing from the east wall: 1.5 s of work
	ship.atmosphere.pressure[_east(ship)] = 0.0
	var ada := _npc("Ada", 19, 12)
	ship.crew.append(ada)
	var jobs := Jobs.new()
	_run(jobs, ship, 1.5)
	eq(_types(ada), "repair_block", "a quick wall fits on one breath")
	_run(jobs, ship, 6.0)
	check(not ship.grid.hp.has(Vector2i(22, 12)), "and she mends it")
	check(ada.hp > ada.max_hp * 0.4, "well above hurt_below")


func test_the_budget_has_a_margin_and_a_suit_or_no_breath_ignore_it() -> void:
	var ship := _two_rooms()
	ship.atmosphere.pressure[_east(ship)] = 0.0
	var spot := Vector2i(19, 12)
	var plain := _npc("Ada", 11, 13)
	check(Jobs._lasts(ship, plain, spot, [], 6.0, 1.25), "6 s of work and a short walk out: 12 s is enough")
	check(not Jobs._lasts(ship, plain, spot, [], 8.5, 1.25), "8.5 s of work is not, with the margin")
	plain.hp = 55.0
	check(not Jobs._lasts(ship, plain, spot, [], 6.0, 1.25), "hurt, the same job is too much")
	var suited := _npc("Rook", 11, 13)
	suited.equip("suit")
	check(Jobs._lasts(ship, suited, spot, [], 100.0, 1.25), "a suit lasts for ever")
	check(Jobs._lasts(ship, _npc("Bram", 11, 13, "basalt"), spot, [], 100.0, 1.25), "so does a Basalt, who does not breathe")


func test_a_crew_member_who_can_no_longer_finish_leaves_before_hurt_below() -> void:
	CrewMember.config()["air"]["breath_margin"] = 0.0  # let her take the engine job, then switch the budget on
	var d := _airless_engine()
	var ship: Ship = d["ship"]
	var ada := _npc("Ada", 18, 13)
	ship.crew.append(ada)
	var jobs := Jobs.new()
	_run(jobs, ship, 2.0)
	eq(_types(ada), "repair_component", "(setup) she is at the engine")
	CrewMember.config()["air"]["breath_margin"] = 1.25
	var low := ada.hp
	_run(jobs, ship, 6.0)
	check(ada.hp >= ada.max_hp * 0.4, "she never fell under hurt_below (%.1f)" % ada.hp)
	check(low > ada.hp - 1.0 and ada.hp < ada.max_hp, "(she did breathe some bad air)")
	eq(ship.atmosphere.room_at(ada.cell()), _west(ship), "she walked out")
	check(jobs.board.has("fix:%d" % d["engine"]), "the job is still on the board for the next")
	check(jobs.progress.get("fix:%d" % d["engine"], 0.0) > 0.0, "with her work kept")


func test_an_order_overrides_the_budget_with_a_line_and_the_person_leaves_when_it_is_no_longer_safe() -> void:
	var d := _airless_engine()
	var ship: Ship = d["ship"]
	var ada := _npc("Ada", 11, 13)
	ship.crew.append(ada)
	var jobs := Jobs.new()
	_run(jobs, ship, 1.0)
	check(Jobs.order_move(ship, ada, Vector2i(19, 13)), "the order is given")
	eq(Jobs.order_warning(ship, ada, 12.0), "Ada won't last in there", "the line under it says so")
	check(ada.hold > 0.0 and not ada.path.is_empty(), "and the order stands")
	ada.hold = 60.0  # (a long order: it is the breath rule that ends it, not the clock)
	_run(jobs, ship, 3.0)
	check(ada.hold > 0.0 or ship.atmosphere.room_at(ada.cell()) != _east(ship), "she carries it out")
	var east_seen := false
	for i in 120:
		_run(jobs, ship, 0.1)
		east_seen = east_seen or ship.atmosphere.room_at(ada.cell()) == _east(ship)
		check(ada.hp >= ada.max_hp * 0.4 - 0.01, "never under hurt_below")
	check(east_seen, "she did go in")
	eq(ship.atmosphere.room_at(ada.cell()), _west(ship), "and came out again")
	check(ship.events.any(func(e): return str(e["text"]).contains("leaves their order")), "the log says she left the order")


func test_the_budget_is_off_with_a_margin_of_zero() -> void:
	CrewMember.config()["air"]["breath_margin"] = 0.0
	var d := _airless_engine()
	var ship: Ship = d["ship"]
	var ada := _npc("Ada", 11, 13)
	ship.crew.append(ada)
	_run(Jobs.new(), ship, 3.0)
	eq(_types(ada), "repair_component", "no budget, she goes for the engine")
	CrewMember.config()["air"]["breath_margin"] = 1.25


func test_a_downed_crew_member_is_revived_in_bad_air_only_when_they_could_walk_out() -> void:
	var ship := _two_rooms()
	var ada := _npc("Ada", 18, 13)
	ada.hp = 0.0
	ship.crew.append(ada)
	ship.atmosphere.pressure[_east(ship)] = 0.0
	var jobs := Jobs.new()
	_run(jobs, ship, 1.2)
	check(jobs.board.has("revive:Ada"), "the west room has air and the door is near: she can walk out on 20 hp")
	ship.atmosphere.pressure[_west(ship)] = 0.0  # no air anywhere
	_run(jobs, ship, 1.2)
	check(not jobs.board.has("revive:Ada") and jobs.closed.has("revive:Ada"), "nowhere to walk to: nobody is sent, the player's hand may still do it")
	ship.atmosphere.pressure[_west(ship)] = 1.0
	ada.hp = 0.0
	ship.atmosphere.pressure[_east(ship)] = 0.0
	ada.pos = Pathfinder.centre_of(Vector2i(16, 12))
	check(Jobs._revivable(ship, ada), "beside the door she is revivable")
	var soldier := _npc("Soldier", 16, 12)
	soldier.is_player = true
	soldier.hp = 0.0
	check(not Jobs._revivable(ship, soldier), "nobody revives the soldier into bad air: they walk only when the player says so")


# --- lost rooms ------------------------------------------------------------------------------------------

## Shoot `n` of the east wall's cells open (the room's boundary is 28 cells: a fifth of it is 6).
func _open_east_wall(ship: Ship, n := 6) -> void:
	for y in range(9, 9 + n):
		ship.grid.breach(Vector2i(22, y))
	ship.mark_dirty()
	ship.refresh()


func test_a_room_with_enough_of_its_boundary_shot_open_is_lost_in_a_fight_and_posts_no_jobs() -> void:
	var ship := _two_rooms()
	var ada := _npc("Ada", 18, 13)
	var rook := _npc("Rook", 11, 13)
	ship.crew.append_array([ada, rook])
	_open_east_wall(ship, 5)
	var jobs := Jobs.new()
	_run(jobs, ship, 1.2, true)
	check(ship.lost_rooms.is_empty(), "five holes of a boundary of 28 are not enough")
	check(jobs.board.has("breach:22,9"), "the breaches are on the board")
	_open_east_wall(ship, 6)
	_run(jobs, ship, 1.2, true)
	eq(ship.lost_rooms, [_east(ship)], "six holes lose the east room")
	check(not jobs.board.has("breach:22,9") and jobs.closed.has("breach:22,9"), "its jobs are closed")
	for key in jobs.board:
		check(not (jobs.board[key]["cells"] as Array).any(func(c): return Evacuate.is_lost(ship, ship.atmosphere.room_at(c))), "no job in the lost room: " + key)
	_run(jobs, ship, 6.0, true)
	eq(ship.atmosphere.room_at(ada.cell()), _west(ship), "Ada walked out to the room with air")


func test_the_soldiers_hand_still_works_in_a_lost_room_and_the_jobs_come_back_after_the_fight() -> void:
	var ship := _two_rooms()
	var player := _npc("Soldier", 20, 11)
	player.is_player = true
	ship.crew.append(player)
	_open_east_wall(ship)
	var jobs := Jobs.new()
	_run(jobs, ship, 1.2, true)
	eq(ship.lost_rooms.size(), 1, "(setup) lost")
	check(jobs.closed.has("breach:22,9"), "(setup) closed")
	player.pos = Pathfinder.centre_of(Vector2i(20, 9))
	var key := jobs.hand_work(ship, player, STEP)
	check(key != "", "the player's hand reaches a job of the lost room (%s)" % key)
	_run(jobs, ship, 1.2, false)
	check(ship.lost_rooms.is_empty(), "the fight is over: the room is not lost")
	check(jobs.board.has("breach:22,9"), "and its jobs are back on the board")


func test_the_share_and_the_minimum_of_open_cells_come_from_the_data() -> void:
	var ship := _two_rooms()
	_open_east_wall(ship, 6)
	var cfg: Dictionary = CrewMember.config()["lost"]
	var share: float = cfg["share"]
	cfg["share"] = 0.9  # 90 percent of a boundary of 28 cells is far more than six
	eq(Evacuate.lost_rooms(ship), [], "a higher share keeps it open")
	cfg["share"] = share
	eq(Evacuate.lost_rooms(ship), [_east(ship)], "back to the default")


# --- repairs under fire ----------------------------------------------------------------------------------

func test_a_part_hit_in_the_last_seconds_is_repaired_at_half_speed_and_so_is_a_wall() -> void:
	var ship := _two_rooms()
	var engine := Fixture.put(ship, "engine_mk1", 17, 10)
	ship.components.instances[engine]["status"] = "malfunction"
	var ada := _npc("Ada", 17, 13)
	ship.crew.append(ada)
	var jobs := Jobs.new()
	_run(jobs, ship, 2.0)
	var key := "fix:%d" % engine
	var calm: float = jobs.progress[key]
	ship.hit_at[engine] = ship.clock
	var before: float = jobs.progress[key]
	_run(jobs, ship, 1.0)
	var fired: float = jobs.progress[key] - before
	ship.clock += 5.0  # no longer under fire
	before = jobs.progress[key]
	_run(jobs, ship, 1.0)
	var after: float = jobs.progress[key] - before
	check(fired < after * 0.6 and fired > after * 0.4, "under fire %.2f s of work a second, after %.2f" % [fired, after])
	check(Jobs._fire_mult(ship, {"type": "repair_block", "cell": Vector2i(3, 3)}) == 1.0, "a wall never hit is not slowed")
	ship.hit_at[Vector2i(3, 3)] = ship.clock
	eq(Jobs._fire_mult(ship, {"type": "repair_block", "cell": Vector2i(3, 3)}), 0.5, "a wall just hit is")


# --- several crew: selection, group orders, the spread key ------------------------------------------------

## The crew view of a ship (no scene), in play mode.
func _view(ship: Ship) -> Dictionary:
	var sim := ShipSim.new()
	sim.ships = [ship]
	var b := BuildMode.new()
	b.sim = sim
	var view := CrewView.new()
	view.build = b
	view.sim = sim
	b.crew = view
	b.build_on = false
	return {"view": view, "sim": sim, "b": b}


func _free(d: Dictionary) -> void:
	for k in ["view", "sim", "b"]:
		d[k].free()


func test_shift_click_adds_and_removes_and_a_plain_click_selects_one() -> void:
	var ship := _two_rooms()
	var ada := _npc("Ada", 10, 13)
	var rook := _npc("Rook", 12, 13)
	var soldier := _npc("Soldier", 11, 15)
	soldier.is_player = true
	ship.crew.append_array([ada, rook, soldier])
	var d := _view(ship)
	var view: CrewView = d["view"]
	view.select(ada)
	view.toggle(rook)
	eq(view.selection().size(), 2, "Shift+click adds Rook")
	check(view.is_selected(ada) and view.is_selected(rook), "both are selected")
	view.toggle(ada)
	eq(view.selection(), [rook], "and takes Ada off")
	eq(view.selected, rook, "the last one picked is the one G uses")
	view.select(ada)
	eq(view.selection(), [ada], "a plain pick selects just one")
	var bar := CrewBar.new()
	bar.view = view
	bar.size = Vector2(1600, 900)
	var cards := CrewBar.card_rects(3, bar.size)
	eq(bar.click(cards[1].get_center(), true), "toggle", "Shift+click on a card toggles")
	eq(view.selection().size(), 2, "the bar adds Rook")
	bar.click(cards[1].get_center(), true)
	eq(view.selection(), [ada], "and removes him")
	eq(bar.click(cards[1].get_center()), "select", "a plain click selects")
	eq(view.selection(), [rook], "just him")
	bar.free()
	_free(d)


func test_a_drag_box_selects_the_crew_inside_it_but_not_the_soldier() -> void:
	var ship := _two_rooms()
	var ada := _npc("Ada", 10, 13)
	var rook := _npc("Rook", 12, 13)
	var far := _npc("Juno", 19, 13)
	var soldier := _npc("Soldier", 11, 14)
	soldier.is_player = true
	ship.crew.append_array([ada, rook, far, soldier])
	var d := _view(ship)
	var view: CrewView = d["view"]
	view.select_box(Rect2(Vector2(8, 11), Vector2(8, 5)))
	check(view.is_selected(ada) and view.is_selected(rook), "the two inside")
	check(not view.is_selected(soldier) and not view.is_selected(far), "not the soldier, not the one outside")
	view.select_box(Rect2(Vector2(18, 11), Vector2(4, 5)), true)
	check(view.is_selected(far) and view.is_selected(ada), "Shift adds to what was selected")
	_free(d)


## West room with a breach (cell 15,9 in the wall), a broken engine and a damaged wall: three jobs. Returns the ship.
func _three_jobs() -> Ship:
	var ship := _two_rooms()
	ship.grid.breach(Vector2i(9, 8))  # the north wall of the west room
	var engine := Fixture.put(ship, "engine_mk1", 10, 10)
	ship.components.instances[engine]["status"] = "malfunction"
	ship.grid.hp[Vector2i(14, 8)] = 2.0
	ship.mark_dirty()
	ship.refresh()
	return ship


func test_a_group_order_gives_the_jobs_of_the_room_one_each_in_board_order() -> void:
	var ship := _three_jobs()
	var crew := [_npc("Ada", 10, 14), _npc("Rook", 12, 14), _npc("Juno", 13, 14)]
	ship.crew.append_array(crew)
	var jobs := Jobs.new()
	_run(jobs, ship, 0.2)
	var lines := jobs.order_group(ship, crew, Vector2(11.0, 12.0))
	var types := {}
	for m in crew:
		check(not m.job.is_empty(), "%s has a job" % m.name)
		types[_types(m)] = true
		check(bool(m.job.get("ordered", false)), "%s's job is an order" % m.name)
		eq(m.hold, 8.0, "%s holds it as long as a single order" % m.name)
	eq(types.keys().size(), 3, "three different jobs: " + str(types.keys()))
	check(types.has("repair_breach") and types.has("repair_component") and types.has("repair_block"), "a breach, a part and a block")
	check(lines.size() >= 3, "the lines say who does what: " + str(lines))


func test_extra_people_stack_on_the_top_job_or_stand_by_when_it_is_full() -> void:
	var ship := _three_jobs()
	var crew := [_npc("Ada", 10, 14), _npc("Rook", 12, 14), _npc("Juno", 13, 14), _npc("Pike", 11, 14), _npc("Bram", 9, 14)]
	ship.crew.append_array(crew)
	var jobs := Jobs.new()
	_run(jobs, ship, 0.2)
	var lines := jobs.order_group(ship, crew, Vector2(11.0, 12.0))
	var idle: Array = crew.filter(func(m): return m.job.is_empty())
	eq(idle.size(), 2, "five people, three one-slot jobs: two stand by")
	for m in idle:
		check(m.hold > 0.0 and (not m.path.is_empty() or Pathfinder.centre_of(m.anchor()).distance_to(m.pos) < 3.0), "%s was told to stand by" % m.name)
	check(str(lines).contains("standing by"), "and the line says so")
	var fire := _three_jobs()
	fire.fires[Vector2i(11, 12)] = 1.0  # a fire has two places
	var crew2 := [_npc("Ada", 10, 14), _npc("Rook", 12, 14), _npc("Juno", 13, 14), _npc("Pike", 11, 14)]
	fire.crew.append_array(crew2)
	var jobs2 := Jobs.new()
	_run(jobs2, fire, 0.2)
	jobs2.order_group(fire, crew2, Vector2(11.0, 12.0))
	var on_fire: Array = crew2.filter(func(m): return _types(m) == "extinguish")
	eq(on_fire.size(), 2, "with four jobs' worth of people the extras take the free place on the fire")


func test_with_nobody_selected_a_middle_click_still_sends_one_crew_member() -> void:
	var ship := _two_rooms()
	var ada := _npc("Ada", 10, 14)
	ship.crew.append(ada)
	var d := _view(ship)
	var view: CrewView = d["view"]
	eq(view.selection().size(), 0, "nobody selected")
	eq(view.order_target(), ada, "Ada gets the order, as ever")
	_free(d)


func test_an_ordered_crew_member_does_not_leave_for_an_auto_job_but_an_unordered_one_does() -> void:
	var ship := _two_rooms()
	ship.grid.hp[Vector2i(10, 8)] = 3.0  # a damaged wall: priority 65 out of a fight
	var ada := _npc("Ada", 10, 10)
	var rook := _npc("Rook", 12, 10)
	ship.crew.append_array([ada, rook])
	var jobs := Jobs.new()
	_run(jobs, ship, 0.2)
	jobs.order_group(ship, [ada], Vector2(10.5, 9.0))
	ada.hold = 0.0  # the order's hold is over
	rook.hold = 0.0
	rook.job = ada.job.duplicate()
	rook.job.erase("ordered")
	eq(_types(ada), "repair_block", "(setup) Ada has the wall")
	ship.fires[Vector2i(13, 14)] = 1.0  # a fire: 100
	_run(jobs, ship, 3.0)
	check(_types(ada) == "repair_block" or not jobs.board.has("block:10,8"), "Ada stays on her order")
	eq(_types(rook), "extinguish", "Rook, who was on the same job by himself, went for the fire")


func test_an_ordered_crew_member_in_bad_air_leaves_with_a_line_when_it_is_no_longer_safe() -> void:
	var d := _airless_engine()
	var ship: Ship = d["ship"]
	var ada := _npc("Ada", 18, 13)
	ship.crew.append(ada)
	var jobs := Jobs.new()
	_run(jobs, ship, 0.2)
	jobs.order_group(ship, [ada, _npc("Dummy", 11, 13)], Vector2(18.0, 12.0))
	eq(_types(ada), "repair_component", "(setup) the order stands in bad air")
	_run(jobs, ship, 12.0)
	check(ada.hp >= ada.max_hp * 0.4 - 0.01, "she did not go under hurt_below (%.1f)" % ada.hp)
	eq(ship.atmosphere.room_at(ada.cell()), _west(ship), "she walked out")
	check(ship.events.any(func(e): return str(e["text"]).contains("leaves their order")), "with a line in the log")


func test_the_spread_key_posts_the_selected_crew_to_the_damaged_rooms_and_leaves_posted_ones() -> void:
	var ship := _two_rooms()
	var engine := Fixture.put(ship, "engine_mk1", 17, 10)  # east room
	ship.components.instances[engine]["status"] = "malfunction"
	var laser := Fixture.put(ship, "laser_mk1", 10, 10)  # a post in the west room
	ship.grid.hp[Vector2i(12, 8)] = 3.0  # a damaged wall in the west room
	var ada := _npc("Ada", 10, 14)
	var rook := _npc("Rook", 12, 14)
	var juno := _npc("Juno", 13, 14)
	ship.crew.append_array([ada, rook, juno])
	Posts.post(ship, juno, laser)
	var jobs := Jobs.new()
	_run(jobs, ship, 0.2)
	ada.hold = 5.0  # a held order to drop
	var lines := jobs.spread(ship, [ada, rook, juno])
	eq(juno.post, laser, "Juno keeps her post")
	check(not str(lines).contains("Juno"), "and gets no room")
	eq(ada.hold, 0.0, "the held order is dropped")
	var rooms := {}
	for m in [ada, rook]:
		check(not m.job.is_empty(), "%s has a job" % m.name)
		rooms[ship.atmosphere.room_at(m.job["cells"][0])] = true
	eq(rooms.keys().size(), 2, "one in each damaged room: " + str(lines))
	var east: Array = [ada, rook].filter(func(m): return _types(m) == "repair_component")
	eq(east.size(), 1, "the engine, the highest job, is taken by one of them")
	check(bool(east[0].job.get("ordered", false)), "for good")


func test_the_spread_key_through_the_crew_view_says_what_it_did() -> void:
	var ship := _two_rooms()
	var ada := _npc("Ada", 10, 14)
	ship.crew.append(ada)
	var d := _view(ship)
	var view: CrewView = d["view"]
	check(view.press_spread().begins_with("Select crew first"), "nobody selected: it says so")
	view.select(ada)
	check(view.press_spread().begins_with("nothing to repair"), "nothing damaged: it says so")
	_free(d)


# --- the fight slow-down ------------------------------------------------------------------------------------

class FakeView:
	var fight := false
	var ship: Ship = null
	var sim = null

	func fight_on() -> bool:
		return fight

	func ship_now():
		return ship

	func say(_t: String) -> void:
		pass


func _banner(fight := true) -> Array:
	TimeScale.reset()
	var v := FakeView.new()
	v.fight = fight
	var b := SlowBanner.new()
	b.view = v
	return [b, v]


func test_the_toggle_slows_the_game_in_a_fight_and_a_second_press_restores_it() -> void:
	var d := _banner()
	var b: SlowBanner = d[0]
	check(b.press(), "Tab does something in a fight")
	eq(Engine.time_scale, 0.25, "a quarter speed")
	check(b.visible, "the banner shows")
	b.tick()
	eq(Engine.time_scale, 0.25, "it stays while the fight goes on")
	b.press()
	eq(Engine.time_scale, 1.0, "a second press puts the speed back")
	check(not b.visible, "and the banner is gone")
	b.free()


func test_the_slow_down_can_be_used_again_and_again() -> void:
	var d := _banner()
	var b: SlowBanner = d[0]
	for i in 5:
		b.press()
		eq(Engine.time_scale, 0.25, "on, time %d" % i)
		b.press()
		eq(Engine.time_scale, 1.0, "off, time %d" % i)
	b.free()


func test_the_slow_down_resets_when_the_fight_ends_or_the_player_escapes() -> void:
	var d := _banner()
	var b: SlowBanner = d[0]
	var v: FakeView = d[1]
	b.press()
	v.fight = false  # won, escaped or lost: no ship in the sim but the player's
	b.tick()
	eq(Engine.time_scale, 1.0, "the fight is over: normal speed")
	check(not b.slow.on and not b.visible, "and it is off")
	v.fight = true  # the next fight starts at normal speed
	b.tick()
	eq(Engine.time_scale, 1.0, "the next fight does not start slowed")
	b.free()


func test_the_key_does_nothing_outside_a_ship_fight_and_in_boarding() -> void:
	var d := _banner(false)
	var b: SlowBanner = d[0]
	check(not b.press(), "no fight: nothing")
	eq(Engine.time_scale, 1.0, "normal speed")
	check(not SlowDown.new().toggle(false), "the logic says no too (the soldier aboard another vessel is no ship fight)")
	b.free()


func test_the_slow_down_is_withdrawn_when_its_node_goes_away() -> void:
	var d := _banner()
	var b: SlowBanner = d[0]
	b.press()
	eq(Engine.time_scale, 0.25, "(setup)")
	b.free()
	eq(Engine.time_scale, 1.0, "freed: nothing stays slow")


func test_the_breach_prompt_and_the_slow_down_merge_so_the_slower_wins_and_nothing_sticks() -> void:
	var ship := _two_rooms()
	ship.crew.append(_npc("Ada", 10, 13))
	var sim := ShipSim.new()
	sim.ships = [ship]
	var b := BuildMode.new()
	b.sim = sim
	var view := CrewView.new()
	view.build = b
	view.sim = sim
	sim.set_paused(false)
	var d := _banner()
	var banner: SlowBanner = d[0]
	var prompt := BreachPrompt.new()
	prompt.view = view
	prompt.tick(STEP)
	banner.press()
	eq(Engine.time_scale, 0.25, "(setup) slow on")
	ship.grid.breach(Vector2i(8, 12))
	ship.mark_dirty()
	ship.refresh()
	for i in 15:
		ship.atmosphere.tick(STEP, {})
		prompt.tick(STEP)
	check(prompt.visible, "the breach card is up")
	eq(Engine.time_scale, 0.25, "both at a quarter: a quarter")
	var ev := InputEventKey.new()
	ev.keycode = KEY_V
	ev.pressed = true
	prompt._input(ev)
	eq(Engine.time_scale, 0.25, "the prompt answered, the slow-down still runs")
	banner.press()
	eq(Engine.time_scale, 1.0, "and off: normal")
	banner.press()
	var ev2 := InputEventKey.new()
	ev2.keycode = KEY_V
	ev2.pressed = true
	TimeScale.request("test_prompt", 0.1)
	eq(Engine.time_scale, 0.1, "a slower request wins")
	TimeScale.clear("test_prompt")
	eq(Engine.time_scale, 0.25, "and leaves the quarter")
	banner.free()
	prompt.free()
	eq(Engine.time_scale, 1.0, "both nodes gone: normal speed")
	view.free()
	sim.free()
	b.free()


func test_the_slow_speed_comes_from_the_data() -> void:
	var was: float = CrewMember.config()["slow"]["scale"]
	CrewMember.config()["slow"]["scale"] = 0.5
	var s := SlowDown.new()
	s.toggle(true)
	eq(s.time_scale(), 0.5, "the data's scale")
	CrewMember.config()["slow"]["scale"] = was
	TimeScale.reset()
