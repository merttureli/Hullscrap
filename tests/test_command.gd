extends "res://tests/base_test.gd"
## Commanding the crew (playtest 2, K1-K3): station posts (scripts/crew/posts.gd, jobs.gd, the station bar), the breach alert and
## abandoning a room (breach_alert.gd, evacuate.gd, door locks), and hurt crew walking out of airless rooms (jobs.gd).

const Fixture = preload("res://tests/fixture_ship.gd")
const Fx = preload("res://tests/fixture_ammo.gd")
const Jobs = preload("res://scripts/crew/jobs.gd")
const Posts = preload("res://scripts/crew/posts.gd")
const Evacuate = preload("res://scripts/crew/evacuate.gd")
const BreachAlert = preload("res://scripts/crew/breach_alert.gd")
const CrewMember = preload("res://scripts/crew/crew_member.gd")
const CrewView = preload("res://scripts/crew/crew_view.gd")
const Pathfinder = preload("res://scripts/crew/pathfinder.gd")
const Ammo = preload("res://scripts/sim/ammo.gd")
const Ship = preload("res://scripts/ship/ship.gd")
const ShipGrid = preload("res://scripts/ship/ship_grid.gd")
const ShipSim = preload("res://scripts/sim/ship_sim.gd")
const TileDefs = preload("res://scripts/ship/tile_defs.gd")
const BuildMode = preload("res://scripts/build/build_mode.gd")
const Hud = preload("res://scripts/ui/hud.gd")
const StationBar = preload("res://scripts/ui/station_bar.gd")
const BreachPrompt = preload("res://scripts/ui/breach_prompt.gd")
const STEP := 0.1


func _npc(p_name: String, x: int, y: int, species := "human") -> CrewMember:
	return CrewMember.new(p_name, Pathfinder.centre_of(Vector2i(x, y), 1 if species == "drone" else 2), species)


func _run(jobs: Jobs, ship: Ship, seconds: float) -> void:
	for i in roundi(seconds / STEP):
		ship.refresh()
		jobs.tick(ship, STEP)


## The room ship cut in two by a wall at x 15 with a 2-cell door at y 12..13: the west room (x 9..14) and the east room (x 16..21), both full of air.
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


## Let the air of a ship with a breach drain for `seconds`, the alert looking on every step.
func _vent(ship: Ship, alert: BreachAlert, seconds: float) -> void:
	for i in roundi(seconds / STEP):
		ship.atmosphere.tick(STEP, {})
		alert.update(ship, STEP)


func _types(m: CrewMember) -> String:
	return str(m.job.get("type", "")) if not m.job.is_empty() else ""


# --- K1: posts ------------------------------------------------------------------------------------

func test_a_posted_crew_member_goes_to_the_post_and_stays_while_other_jobs_come_up() -> void:
	var ship := Fixture.room_ship()
	var helm := Fixture.put(ship, "helm", 19, 10)
	var laser := Fixture.put(ship, "laser_mk1", 15, 10)
	var radiator := Fixture.put(ship, "radiator", 10, 10)
	var ada := _npc("Ada", 12, 14)
	ship.crew.append(ada)
	eq(Posts.post(ship, ada, laser), "Ada is posted at %s" % Posts.name_of(ship, laser), "posted to the laser")
	var jobs := Jobs.new()
	_run(jobs, ship, 6.0)
	eq(_types(ada), "man_station", "at a station")
	eq(ada.job["uid"], laser, "the laser, not the helm (nobody else is posted there)")
	eq(ship.manned.get(laser, ""), "Ada", "and she mans it")
	ship.components.instances[radiator]["status"] = "malfunction"  # a repair (80) and a station (the helm, 50) come up, a fire in the room too
	ship.fires[Vector2i(12, 15)] = 0.2
	_run(jobs, ship, 20.0)
	eq(ada.job.get("uid"), laser, "she is back at her post after the fire, whatever else is on the board")
	check(ship.fires.is_empty(), "(the fire went out)")
	eq(ship.components.instances[radiator]["status"], "malfunction", "the repair waits")
	eq(ship.manned.get(helm, ""), "", "and nobody mans the helm: she holds one post")


func test_a_posted_crew_member_ignores_repairs_and_unposted_ones_do_them() -> void:
	var ship := Fixture.room_ship()
	var laser := Fixture.put(ship, "laser_mk1", 15, 10)
	var radiator := Fixture.put(ship, "radiator", 10, 10)
	ship.components.instances[radiator]["status"] = "malfunction"
	var ada := _npc("Ada", 12, 14)
	ship.crew.append(ada)
	Posts.post(ship, ada, laser)
	var jobs := Jobs.new()
	_run(jobs, ship, 20.0)
	eq(ship.components.instances[radiator]["status"], "malfunction", "nobody repaired the radiator")
	eq(ada.job.get("uid"), laser, "she stayed at the laser")
	Posts.unpost(ship, laser)
	_run(jobs, ship, 30.0)
	eq(ship.components.instances[radiator]["status"], "ok", "unposted, she repaired it")


func test_a_posted_crew_member_leaves_for_a_fire_in_the_room_and_goes_back() -> void:
	var ship := Fixture.room_ship()
	var laser := Fixture.put(ship, "laser_mk1", 15, 10)
	var ada := _npc("Ada", 12, 14)
	ship.crew.append(ada)
	Posts.post(ship, ada, laser)
	var jobs := Jobs.new()
	_run(jobs, ship, 5.0)
	eq(ada.job.get("uid"), laser, "at the post")
	ship.fires[Vector2i(10, 15)] = 0.9
	var seen := {}
	for i in 400:
		ship.refresh()
		jobs.tick(ship, STEP)
		seen[_types(ada)] = true
	check(seen.has("extinguish"), "she went for the fire")
	check(ship.fires.is_empty(), "the fire is out")
	eq(ada.job.get("uid"), laser, "and she is back at the post")
	eq(ship.manned.get(laser, ""), "Ada", "manning it")


func test_a_posted_crew_member_leaves_a_fire_in_another_room_alone() -> void:
	var ship := _two_rooms()
	var laser := Fixture.put(ship, "laser_mk1", 16, 10)
	var ada := _npc("Ada", 17, 14)
	ship.crew.append(ada)
	Posts.post(ship, ada, laser)
	ship.fires[Vector2i(10, 12)] = 0.9  # in the west room
	var jobs := Jobs.new()
	_run(jobs, ship, 12.0)
	check(ship.fires.has(Vector2i(10, 12)), "the west fire still burns")
	eq(ada.job.get("uid"), laser, "she stayed at the post in the east room")
	ship.fires[Vector2i(19, 15)] = 0.9
	_run(jobs, ship, 20.0)
	check(not ship.fires.has(Vector2i(19, 15)), "but the fire in her own room went out")
	eq(ada.job.get("uid"), laser, "and she is back")


func test_a_posted_gunner_leaves_to_restock_the_rack_that_feeds_the_gun_and_goes_back() -> void:
	var f := Fx.with_rack()
	var ship: Ship = f["ship"]
	ship.inventory.add("missile", 40)
	var ada := _npc("Ada", 18, 18)
	ship.crew.append(ada)
	ship.atmosphere.pressure.fill(1.0)  # (this rig is open to space, and Jobs alone does not tick the air)
	eq(Posts.feeds(ship, f["gun"]), [f["rack"]], "the rack of the gun's room feeds it")
	Posts.post(ship, ada, f["gun"])
	var jobs := Jobs.new()
	var seen := {}
	for i in 900:
		ship.refresh()
		jobs.tick(ship, STEP)
		seen[_types(ada)] = true
	check(seen.has("restock") and seen.has("man_station"), "she restocked and manned the gun: %s" % str(seen.keys()))
	eq(Ammo.count_in(ship, f["rack"]), Ammo.capacity(ship, f["rack"]), "the rack is full")
	eq(ada.job.get("uid"), f["gun"], "and she is at the gun again")


func test_the_belt_rig_rack_feeds_the_gun_over_a_belt() -> void:
	var f := Fx.belts()
	var ship: Ship = f["ship"]
	eq(Posts.feeds(ship, f["gun"]).has(f["rack"]), true, "a rack on a belt that reaches the gun feeds it too")


func test_unposting_frees_them() -> void:
	var ship := Fixture.room_ship()
	var laser := Fixture.put(ship, "laser_mk1", 15, 10)
	var radiator := Fixture.put(ship, "radiator", 10, 10)
	ship.components.instances[radiator]["status"] = "malfunction"
	var ada := _npc("Ada", 12, 14)
	ship.crew.append(ada)
	Posts.post(ship, ada, laser)
	var jobs := Jobs.new()
	_run(jobs, ship, 5.0)
	eq(Posts.unpost(ship, laser), "Ada leaves the post at %s" % Posts.name_of(ship, laser), "taken off")
	eq(ada.post, -1, "no post")
	eq(Posts.unpost(ship, laser), "", "nobody there any more")
	_run(jobs, ship, 3.0)
	eq(_types(ada), "repair_component", "she is on the job board again and goes for the repair")


func test_the_soldier_and_drones_cannot_be_posted() -> void:
	var ship := Fixture.room_ship()
	var helm := Fixture.put(ship, "helm", 19, 10)
	var soldier := _npc("Soldier", 12, 14)
	soldier.is_player = true
	var drone := _npc("Drone", 12, 12, "drone")
	ship.crew.append_array([soldier, drone])
	check(Posts.post(ship, soldier, helm) != "Soldier is posted at Helm", "the soldier is refused")
	eq(soldier.post, -1, "no post for the soldier")
	check(Posts.refusal(soldier).contains("by hand"), "with a line: " + Posts.refusal(soldier))
	eq(Posts.post(ship, drone, helm), "Drone cannot man a station", "the drone is refused")
	eq(drone.post, -1, "no post for the drone")
	eq(Posts.holder(ship, helm), null, "the helm is empty")


func test_a_crew_member_has_one_post_and_a_station_holds_one() -> void:
	var ship := Fixture.room_ship()
	var helm := Fixture.put(ship, "helm", 19, 10)
	var laser := Fixture.put(ship, "laser_mk1", 15, 10)
	var ada := _npc("Ada", 12, 14)
	var rook := _npc("Rook", 14, 14)
	ship.crew.append_array([ada, rook])
	Posts.post(ship, ada, helm)
	Posts.post(ship, ada, laser)
	eq([ada.post, Posts.holder(ship, helm)], [laser, null], "moved from the helm to the laser")
	eq(Posts.post(ship, rook, laser), "Rook is posted at %s (Ada is relieved)" % Posts.name_of(ship, laser), "Rook takes it over")
	eq([ada.post, rook.post], [-1, laser], "Ada is off")


func test_an_unposted_crew_member_leaves_a_held_post_alone() -> void:
	var ship := Fixture.room_ship()
	var helm := Fixture.put(ship, "helm", 19, 10)
	var ada := _npc("Ada", 12, 14)
	var rook := _npc("Rook", 14, 14)
	ship.crew.append_array([ada, rook])
	Posts.post(ship, ada, helm)
	ada.hold = 1000.0  # on a long manual order: away from the helm
	var jobs := Jobs.new()
	_run(jobs, ship, 10.0)
	check(not ship.manned.has(helm), "nobody mans the helm")
	check(rook.job.is_empty() or rook.job.get("uid", -1) != helm, "Rook leaves Ada's post alone")


func test_a_post_is_dropped_when_the_part_is_removed() -> void:
	var ship := Fixture.room_ship()
	var helm := Fixture.put(ship, "helm", 19, 10)
	var ada := _npc("Ada", 12, 14)
	ship.crew.append(ada)
	Posts.post(ship, ada, helm)
	ship.components.remove_uid(helm)
	var jobs := Jobs.new()
	_run(jobs, ship, 2.0)
	eq(ada.post, -1, "the post went with the part")
	check(not jobs.board.has("post:%d" % helm), "and it is not on the board")


func test_posts_survive_a_save_and_load() -> void:
	var ship := Fixture.room_ship()
	var helm := Fixture.put(ship, "helm", 19, 10)
	var ada := _npc("Ada", 12, 14)
	var rook := _npc("Rook", 14, 14)
	ship.crew.append_array([ada, rook])
	Posts.post(ship, ada, helm)
	var d := ship.to_dict()
	var again := Ship.new_starter()
	eq(again.load_dict(JSON.parse_string(JSON.stringify(d))), "", "loads")
	var back: Array = again.crew.filter(func(m): return m.name == "Ada")
	eq(back.size(), 1, "Ada is aboard")
	eq(back[0].post, helm, "and still posted to the helm")
	eq(again.crew.filter(func(m): return m.name == "Rook")[0].post, -1, "Rook has none")
	var jobs := Jobs.new()
	_run(jobs, again, 8.0)
	eq(again.manned.get(helm, ""), "Ada", "and she mans it again")


func test_the_stations_are_the_helm_the_weapons_the_shields_the_medbay_and_other_manned_parts_in_that_order() -> void:
	var ship := Fixture.room_ship()
	var medbay := Fixture.put(ship, "medbay", 10, 10)
	var shield := Fixture.put(ship, "shield_mk1", 12, 10)
	var laser := Fixture.put(ship, "laser_mk1", 15, 10)
	var helm := Fixture.put(ship, "helm", 19, 10)
	var reactor := Fixture.put(ship, "reactor_mk1", 19, 12)
	eq(Posts.stations(ship), [helm, laser, shield, medbay], "bar order; the reactor is no station")
	check(not Posts.is_station(ship, reactor), "a reactor cannot be posted to")
	var ada := _npc("Ada", 12, 14)
	ship.crew.append(ada)
	Posts.post(ship, ada, shield)
	var jobs := Jobs.new()
	_run(jobs, ship, 6.0)
	eq(ship.manned.get(shield, ""), "Ada", "a shield (manned: false in the data) can be manned by a post")


func test_the_station_bar_posts_selects_and_unposts_through_the_crew_view() -> void:
	var defs := TileDefs.new()
	defs.load_file("res://data/tiles.json")
	var ship := Fixture.room_ship()
	var helm := Fixture.put(ship, "helm", 19, 10)
	var laser := Fixture.put(ship, "laser_mk1", 15, 10)
	var ada := _npc("Ada", 12, 14)
	var soldier := _npc("Soldier", 14, 14)
	soldier.is_player = true
	ship.crew.append_array([ada, soldier])
	var sim := ShipSim.new()
	sim.ships = [ship]
	var b := BuildMode.new()
	b.sim = sim
	b.hud = Hud.new()
	b.hud.setup(b)
	var view := CrewView.new()
	view.build = b
	view.sim = sim
	b.crew = view
	b.build_on = false
	b.hud.sync(Vector2(1600, 900))
	var bar: StationBar = b.hud.station_bar
	eq(bar.count(), 2, "two buttons: the helm and the laser")
	check(bar.visible and b.hud.panel_rects().has("station_bar"), "the bar is on show in play mode")
	check(Rect2(Vector2.ZERO, Vector2(1600, 900)).encloses(b.hud.panel_rects()["station_bar"]), "on screen")
	eq(bar.uid_at(0), helm, "the helm first")
	eq(bar.click(1), "Select a crew member first, then click a station", "nobody selected, nobody posted")
	view.select(ada)
	eq(bar.click(1), "Ada is posted at %s" % Posts.name_of(ship, laser), "the selected crew member is posted")
	view.select(null)
	check(bar.tip_for(1).contains("Posted: Ada"), "the tip says who: " + bar.tip_for(1))
	bar.click(1)
	check(view.selected == ada, "with nobody selected a click selects the one posted there")
	view.select(soldier)
	check(bar.click(0).contains("by hand"), "the soldier is refused")
	eq(bar.click(1, true), "Ada leaves the post at %s" % Posts.name_of(ship, laser), "a right click unposts")
	eq(ada.post, -1, "unposted")
	b.build_on = true
	b.hud.sync(Vector2(1600, 900))
	check(not b.hud.panel_rects().has("station_bar"), "no bar in build mode")
	for n in [view, b.hud, sim, b]:
		n.free()


func test_the_station_bar_wraps_into_columns_that_fit_the_height() -> void:
	var one := StationBar.size_for(1, 600.0)
	var many := StationBar.size_for(30, 300.0)
	check(many.y <= 300.0, "never taller than the room it has: %s" % str(many))
	check(many.x > one.x, "a second column starts")
	var last := StationBar.button_rect(29, 30, many)
	check(Rect2(Vector2.ZERO, many).encloses(last), "every button is inside the strip")
	eq(StationBar.size_for(0, 600.0), Vector2.ZERO, "nothing to show, nothing drawn")


# --- K2: the breach alert -------------------------------------------------------------------------

func test_a_breach_with_crew_present_raises_one_prompt_and_slows_time() -> void:
	var ship := _two_rooms()
	Fixture.put(ship, "helm", 10, 10)
	ship.crew.append(_npc("Ada", 10, 13))
	var alert := BreachAlert.new()
	alert.update(ship, STEP)
	eq(alert.queue.size(), 0, "calm: no prompt")
	eq(alert.time_scale(), 1.0, "full speed")
	ship.grid.breach(Vector2i(8, 12))
	ship.mark_dirty()
	ship.refresh()
	_vent(ship, alert, 2.0)
	eq(alert.queue.size(), 1, "one prompt")
	eq(alert.current()["name"], "bridge", "for the room with the helm")
	eq(alert.time_scale(), float(BreachAlert.cfg()["time_scale"]), "time is slowed")
	eq(alert.slowed_total, 1, "once")
	_vent(ship, alert, 1.5)  # the 3 s run out with no answer: Repair
	eq(alert.queue.size(), 0, "no answer is repair: the prompt is gone")
	eq(alert.time_scale(), 1.0, "and time is back")
	_vent(ship, alert, 5.0)
	eq(alert.queue.size(), 0, "the same breach does not raise it again")


func test_the_prompt_waits_three_real_seconds_and_repair_answers_it() -> void:
	var ship := _two_rooms()
	ship.crew.append(_npc("Ada", 10, 13))
	var alert := BreachAlert.new()
	alert.update(ship, STEP)
	ship.grid.breach(Vector2i(8, 12))
	ship.mark_dirty()
	ship.refresh()
	_vent(ship, alert, 1.0)
	check(not alert.current().is_empty(), "the prompt is up")
	check(float(alert.current()["left"]) <= 3.0 and float(alert.current()["left"]) > 1.5, "with seconds left: %s" % str(alert.current()["left"]))
	check(alert.respond(ship, "repair").begins_with("Crew sealing the breach"), "Repair says so")
	eq(alert.time_scale(), 1.0, "time is back at once")
	eq(Evacuate.rooms(ship), [], "nothing was abandoned")


func test_no_prompt_without_crew_or_for_a_room_that_never_had_air() -> void:
	var ship := _two_rooms()
	var alert := BreachAlert.new()
	alert.update(ship, STEP)
	ship.grid.breach(Vector2i(8, 12))
	ship.mark_dirty()
	ship.refresh()
	_vent(ship, alert, 3.0)
	eq(alert.queue.size(), 0, "nobody in or heading for the room: no prompt")
	var open := Fixture.room_ship()
	open.grid.breach(Vector2i(8, 12))
	open.mark_dirty()
	open.refresh()
	open.atmosphere.pressure[0] = 0.0  # it was an empty, open room all along
	open.crew.append(_npc("Ada", 10, 13))
	var other := BreachAlert.new()
	other.update(open, STEP)
	_vent(open, other, 2.0)
	eq(other.queue.size(), 0, "a room that never held air raises nothing")


func test_crew_on_the_way_count() -> void:
	var ship := _two_rooms()
	var ada := _npc("Ada", 18, 14)  # in the east room
	ship.crew.append(ada)
	var alert := BreachAlert.new()
	alert.update(ship, STEP)
	ship.grid.breach(Vector2i(8, 12))
	ship.mark_dirty()
	ship.refresh()
	_vent(ship, alert, 1.0)
	eq(alert.queue.size(), 0, "nobody is in the west room")
	ada.job = {"key": "breach:8,12", "type": "repair_breach", "spot": Vector2i(10, 12), "priority": 90}
	alert.update(ship, STEP)
	eq(alert.queue.size(), 1, "but she is on her way there")


func test_a_second_breach_within_ten_seconds_queues_without_slowing_again() -> void:
	var ship := _two_rooms()
	ship.crew.append_array([_npc("Ada", 10, 13), _npc("Rook", 18, 13)])
	var alert := BreachAlert.new()
	alert.update(ship, STEP)
	ship.grid.breach(Vector2i(8, 12))
	ship.grid.breach(Vector2i(22, 12))
	ship.mark_dirty()
	ship.refresh()
	_vent(ship, alert, 1.0)
	eq(alert.queue.size(), 2, "two prompts, one for each room")
	eq(alert.slowed_total, 1, "only the first slowed time")
	check(bool(alert.queue[0]["slow"]) and not bool(alert.queue[1]["slow"]), "the second does not")
	alert.respond(ship, "repair")
	eq(alert.queue.size(), 1, "the second comes up")
	eq(alert.time_scale(), 1.0, "at normal speed")
	eq(alert.slowed_total, 1, "still one slow-down")
	alert.respond(ship, "repair")
	# after ten real seconds a new breach slows time again
	ship.grid.repair(Vector2i(8, 12))
	ship.mark_dirty()
	ship.refresh()
	ship.atmosphere.pressure[_west(ship)] = 1.0
	for i in 120:
		alert.update(ship, STEP)
	ship.grid.breach(Vector2i(8, 12))
	ship.mark_dirty()
	ship.refresh()
	_vent(ship, alert, 1.0)
	eq(alert.slowed_total, 2, "twelve seconds later it slows time again")


func test_the_slow_down_can_be_turned_off_in_the_data() -> void:
	var cfg: Dictionary = CrewMember.config()["breach"]
	cfg["slow_down"] = false
	var ship := _two_rooms()
	ship.crew.append(_npc("Ada", 10, 13))
	var alert := BreachAlert.new()
	alert.update(ship, STEP)
	ship.grid.breach(Vector2i(8, 12))
	ship.mark_dirty()
	ship.refresh()
	_vent(ship, alert, 1.0)
	cfg["slow_down"] = true
	eq(alert.queue.size(), 1, "the prompt still comes")
	eq(alert.time_scale(), 1.0, "but time is not slowed")
	eq(alert.slowed_total, 0, "and no slow-down is counted")


func test_evacuate_removes_the_jobs_locks_the_doors_and_sends_the_crew_out_and_reopening_restores_them() -> void:
	var ship := _two_rooms()
	var ada := _npc("Ada", 10, 13)
	var rook := _npc("Rook", 18, 13)
	ship.crew.append_array([ada, rook])
	ship.fires[Vector2i(11, 10)] = 0.5
	var jobs := Jobs.new()
	jobs.build_board(ship)
	check(jobs.board.has("fire:11,10"), "the fire is on the board")
	var west := _west(ship)
	eq(Evacuate.abandon(ship, west), ["Ada"], "Ada walks out")
	check(Evacuate.is_abandoned(ship, west) and not Evacuate.is_abandoned(ship, _east(ship)), "the west room is abandoned")
	check(ship.grid.door_locked.has(Vector2i(15, 12)) and ship.grid.door_locked.has(Vector2i(15, 13)), "its door is locked, both cells")
	check(not ada.path.is_empty() and Evacuate.room_at_anchor(ship, ada.path.back(), 2) == _east(ship), "her path ends in the east room")
	jobs.build_board(ship)
	check(not jobs.board.has("fire:11,10") and jobs.closed.has("fire:11,10"), "no job in the room is on the board any more")
	_run(jobs, ship, 12.0)
	eq(ship.atmosphere.room_at(ada.cell()), _east(ship), "Ada is in the east room")
	check(ship.fires.has(Vector2i(11, 10)), "and nobody went back for the fire")
	var west_spot := Vector2i(11, 12)
	check(Pathfinder.find_path(ship.grid, ada.anchor(), west_spot, Callable(), 2).is_empty(), "crew's paths avoid the locked door")
	var soldier_door := func(_c: Vector2i) -> bool: return true
	check(not Pathfinder.find_path(ship.grid, ada.anchor(), west_spot, soldier_door, 2).is_empty(), "the soldier, who passes his own door callable, can still walk in")
	var soldier := _npc("Soldier", 12, 10)
	soldier.is_player = true
	ship.crew.append(soldier)
	eq(jobs.hand_work(ship, soldier, 0.1), "fire:11,10", "and put out a fire there by hand")
	check(Evacuate.reopen(ship, west), "reopened")
	check(ship.grid.door_locked.is_empty() and not Evacuate.is_abandoned(ship, west), "unlocked")
	jobs.build_board(ship)
	check(jobs.board.has("fire:11,10") and jobs.closed.is_empty(), "the jobs are back on the board")
	_run(jobs, ship, 30.0)
	check(ship.fires.is_empty(), "and the crew went back in and put the fire out")


func test_evacuate_through_the_prompt_abandons_the_room_and_logs_it() -> void:
	var ship := _two_rooms()
	var ada := _npc("Ada", 10, 13)
	ship.crew.append(ada)
	var alert := BreachAlert.new()
	alert.update(ship, STEP)
	ship.grid.breach(Vector2i(8, 12))
	ship.mark_dirty()
	ship.refresh()
	_vent(ship, alert, 1.0)
	var line := alert.respond(ship, "evacuate")
	check(line.contains("abandoned") and line.contains("Ada"), "says so: " + line)
	eq(Evacuate.rooms(ship), [_west(ship)], "the west room")
	eq(alert.time_scale(), 1.0, "time is back")
	eq(alert.queue.size(), 0, "no prompt")
	_vent(ship, alert, 5.0)
	eq(alert.queue.size(), 0, "an abandoned room raises no more prompts")


func test_abandoned_rooms_are_saved_and_come_back_locked() -> void:
	var ship := _two_rooms()
	Evacuate.abandon(ship, _west(ship))
	var d: Dictionary = JSON.parse_string(JSON.stringify(ship.to_dict()))
	eq(d["abandoned"].map(func(p): return [int(p[0]), int(p[1])]), [[9, 9]], "the key cell of the room is saved")
	var again := Ship.new_starter()
	eq(again.load_dict(d), "", "loads")
	check(Evacuate.is_abandoned(again, _west(again)) and not Evacuate.is_abandoned(again, _east(again)), "the same room is abandoned")
	check(again.grid.door_locked.has(Vector2i(15, 12)), "and its door is locked")
	var plain := _two_rooms()
	check(not plain.to_dict().has("abandoned"), "a ship that gave up nothing saves no list")
	eq(again.load_dict(plain.to_dict()), "", "loading a ship without the list")
	eq(again.abandoned.size(), 0, "clears it")
	check(again.grid.door_locked.is_empty(), "and the locks")


func test_the_breach_prompt_node_sets_the_game_speed_and_puts_it_back() -> void:
	var ship := _two_rooms()
	ship.crew.append(_npc("Ada", 10, 13))
	var sim := ShipSim.new()
	sim.ships = [ship]
	var b := BuildMode.new()
	b.sim = sim
	var view := CrewView.new()
	view.build = b
	view.sim = sim
	sim.set_paused(false)  # (a build mode that is on pauses the world)
	var prompt := BreachPrompt.new()
	prompt.view = view
	prompt.tick(STEP)
	ship.grid.breach(Vector2i(8, 12))
	ship.mark_dirty()
	ship.refresh()
	for i in 15:
		ship.atmosphere.tick(STEP, {})
		prompt.tick(STEP)
	check(prompt.visible, "the card is up")
	eq(Engine.time_scale, 0.25, "the engine runs at a quarter")
	var card := prompt.card_rect(Vector2(1600, 900))
	check(Rect2(Vector2.ZERO, Vector2(1600, 900)).encloses(card), "the card is on screen")
	var evac := InputEventKey.new()
	evac.keycode = KEY_V
	evac.pressed = true
	prompt._input(evac)
	eq(Engine.time_scale, 1.0, "V answers it and speeds up")
	check(not prompt.visible, "the card is gone")
	eq(Evacuate.rooms(ship).size(), 1, "the room is abandoned")
	Engine.time_scale = 1.0
	for n in [prompt, view, sim, b]:
		n.free()


# --- K3: crew leave airless rooms --------------------------------------------------------------------

## The two rooms with a broken engine in the east room, and its air gone.
func _airless_east() -> Dictionary:
	var ship := _two_rooms()
	var engine := Fixture.put(ship, "engine_mk1", 17, 10)
	ship.components.instances[engine]["status"] = "malfunction"
	ship.atmosphere.pressure[_east(ship)] = 0.0
	return {"ship": ship, "engine": engine}


func test_a_hurt_crew_member_repairing_in_vacuum_leaves_at_forty_percent_and_returns_over_seventy() -> void:
	var d := _airless_east()
	var ship: Ship = d["ship"]
	var ada := _npc("Ada", 18, 13)
	ship.crew.append(ada)
	var jobs := Jobs.new()
	_run(jobs, ship, 2.0)
	eq(_types(ada), "repair_component", "healthy, she repairs the engine in the airless room")
	check(not ada.winded, "not winded")
	ada.hp = 38.0
	_run(jobs, ship, 6.0)
	check(ada.winded, "under 40 percent she is winded")
	eq(ship.atmosphere.room_at(ada.cell()), _west(ship), "and she walked out to the room with air")
	check(_types(ada) != "repair_component", "no repair in the vacuum")
	ada.hp = 55.0  # between 40 and 70: still out
	_run(jobs, ship, 4.0)
	eq(ship.atmosphere.room_at(ada.cell()), _west(ship), "at 55 percent she stays out")
	ada.hp = 80.0
	_run(jobs, ship, 8.0)
	check(not ada.winded, "over 70 percent she is fit")
	eq(_types(ada), "repair_component", "and she is back at the engine")
	eq(ship.atmosphere.room_at(ada.cell()), _east(ship), "in the east room")


func test_air_recovering_sends_them_back_without_waiting_for_their_health() -> void:
	var d := _airless_east()
	var ship: Ship = d["ship"]
	var ada := _npc("Ada", 18, 13)
	ship.crew.append(ada)
	ada.hp = 30.0
	var jobs := Jobs.new()
	_run(jobs, ship, 5.0)
	eq(ship.atmosphere.room_at(ada.cell()), _west(ship), "out")
	ship.atmosphere.pressure[_east(ship)] = 1.0  # the breach is mended, the air is back
	_run(jobs, ship, 8.0)
	eq(_types(ada), "repair_component", "she goes back to work though she is still at 30 percent")


func test_a_drone_a_suit_wearer_and_a_breathless_crew_member_stay() -> void:
	var d := _airless_east()
	var ship: Ship = d["ship"]
	Fixture.put(ship, "reactor_mk1", 10, 10)
	Fixture.wire(ship, [Vector2i(10, 10)])
	ship.refresh()
	var drone := _npc("Drone", 18, 13, "drone")
	var suited := _npc("Rook", 17, 14)
	suited.equip("suit")
	var basalt := _npc("Bram", 19, 14, "basalt")
	ship.crew.append_array([drone, suited, basalt])
	for m in [drone, suited, basalt]:
		m.hp = m.max_hp * 0.3
	var jobs := Jobs.new()
	_run(jobs, ship, 1.5)
	for m in [drone, suited, basalt]:
		check(not m.winded, "%s is exempt" % m.name)
	_run(jobs, ship, 1.0)
	var in_east: Array = [drone, suited, basalt].filter(func(m): return ship.atmosphere.room_at(m.cell()) == _east(ship))
	eq(in_east.size(), 3, "all three are still in the airless room")
	check(Jobs.air_exempt(drone) and Jobs.air_exempt(suited) and Jobs.air_exempt(basalt), "exempt by the trait library's keys")
	check(not Jobs.air_exempt(_npc("Juno", 12, 14)), "an ordinary crew member is not")


func test_a_posted_crew_member_walks_out_of_bad_air_then_returns_to_the_post() -> void:
	var ship := _two_rooms()
	var laser := Fixture.put(ship, "laser_mk1", 17, 10)
	ship.atmosphere.pressure[_east(ship)] = 0.0
	var ada := _npc("Ada", 18, 13)
	ship.crew.append(ada)
	Posts.post(ship, ada, laser)
	ada.hp = 35.0
	var jobs := Jobs.new()
	_run(jobs, ship, 6.0)
	eq(ship.atmosphere.room_at(ada.cell()), _west(ship), "she left the post for the air")
	ship.atmosphere.pressure[_east(ship)] = 1.0
	_run(jobs, ship, 8.0)
	eq(ada.job.get("uid"), laser, "and went back to it when the air was back")
