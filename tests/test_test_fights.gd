extends "res://tests/base_test.gd"
## The test-fight page (K in play mode): every enemy it lists can be built, it opens and closes, a test fight ends in a results row, and the run is the same after it.

const TestFights = preload("res://scripts/combat/test_fights.gd")
const TestFightPanel = preload("res://scripts/ui/test_fight_panel.gd")
const CombatView = preload("res://scripts/combat/combat_view.gd")
const Session = preload("res://scripts/combat/combat_session.gd")
const ShipSim = preload("res://scripts/sim/ship_sim.gd")
const BuildMode = preload("res://scripts/build/build_mode.gd")
const Ship = preload("res://scripts/ship/ship.gd")
const Jobs = preload("res://scripts/crew/jobs.gd")
const Flagships = preload("res://scripts/space/flagships.gd")


func _key(code: int, shift := false) -> InputEventKey:
	var k := InputEventKey.new()
	k.keycode = code
	k.pressed = true
	k.shift_pressed = shift
	return k


## A combat view with the page wired in, a sim with the Rustbucket aboard and play mode on.
func _screen() -> Dictionary:
	var ship: Ship = Ship.from_design("res://data/ships/starter_rustbucket.json")
	Jobs.spawn_crew(ship)
	var sim := ShipSim.new()
	sim.ships = [ship]
	var build := BuildMode.new()
	build.sim = sim
	build.build_on = false
	var view := CombatView.new()
	view.sim = sim
	view.build = build
	var page := TestFightPanel.new()
	page.view = view
	view._page = page
	return {"sim": sim, "build": build, "view": view, "page": page, "ship": ship}


func _free(d: Dictionary) -> void:
	for k in ["page", "view", "build", "sim"]:
		d[k].free()


func test_every_enemy_choice_can_be_built() -> void:
	for stage in [5]:
		var list := TestFights.all_choices(stage)
		var generated := 0
		for c in list:
			var ship = Session.load_ship(str(c["path"]))
			check(ship != null, "%s (stage %d) builds" % [c["label"], stage])
			if str(c["id"]).begins_with("stage:"):
				generated += 1
		check(generated > 0, "generated enemies at stage %d" % stage)
	eq(TestFights.all_choices(5).filter(func(c): return str(c["id"]).begins_with("flagship:")).size(), Flagships.races().size(), "a choice for every flagship")
	for stage in [1, 8]:  # (the first and last stage, for the first faction and the last race)
		for f in [TestFights.factions()[0], TestFights.factions()[-1]]:
			var made := 0
			for role in TestFights.roles_of(f):
				var c := TestFights.stage_choice(f, role, stage)
				if not c.is_empty():
					made += 1
					check(Session.load_ship(str(c["path"])) != null, "%s builds" % c["label"])
			check(made > 0, "%s flies something at stage %d" % [f, stage])
	for f in TestFights.factions():
		check(not TestFights.roles_of(f).is_empty(), "%s flies some role" % f)


func test_a_new_seed_is_another_ship_and_the_random_button_picks_a_buildable_one() -> void:
	var a := TestFights.stage_choice("rustfangs", TestFights.roles_of("rustfangs")[0], 3)
	var next := TestFights.next_seed("rustfangs", str(a["role"]), 3, int(a["seed"]) + 1)
	check(next > int(a["seed"]), "the next seed is later")
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for i in 6:
		var c := TestFights.random_choice(rng)
		check(Session.load_ship(str(c["path"])) != null, "random pick %d builds: %s" % [i, c.get("label", "")])


func test_the_page_opens_on_k_and_closes_on_esc() -> void:
	var d := _screen()
	var view: CombatView = d["view"]
	var page: TestFightPanel = d["page"]
	d["build"].build_on = true
	view._unhandled_input(_key(KEY_K))
	check(not page.visible, "K in build mode opens nothing")
	d["build"].build_on = false
	view._unhandled_input(_key(KEY_K))
	check(page.visible and view.testing and not view.active, "K in play mode opens the page")
	eq(page.choices.size(), 7, "the current ship and six test ships")
	check(not page.enemy.is_empty(), "an enemy is picked")
	page._input(_key(KEY_ESCAPE))
	check(not page.visible and not view.testing, "Esc closes it")
	view._unhandled_input(_key(KEY_K, true))
	eq(page.enemy["id"], "rammer", "Shift+K preselects the rammer")
	page.close()
	_free(d)


func test_a_test_fight_ends_in_a_row_and_leaves_the_run_as_it_was() -> void:
	var d := _screen()
	var view: CombatView = d["view"]
	var page: TestFightPanel = d["page"]
	var ship: Ship = d["ship"]
	var before := JSON.stringify(ship.to_dict())
	var sim_ships_before: int = d["sim"].ships.size()
	page.open()
	page.select_ship(0)
	page.pick_fixed("pirate")
	eq(page.fight(), "", "the fight starts")
	check(view.active and not page.visible, "the fight is on")
	check(d["sim"].player_ship() != ship, "the copy fights in the player's place")
	for i in 600:
		view.session.tick(1.0 / 60.0)
	view.session.arena.ships[Session.ENEMY].wrecked = true
	view.leave()
	check(d["sim"].player_ship() == ship, "the real ship is back")
	eq(d["sim"].ships.size(), sim_ships_before, "the enemy left the simulation")
	check(page.visible, "the page is back")
	eq(page.results.size(), 1, "a row")
	eq(page.results[0]["ending"], "won", "it says how it ended")
	eq(page.results[0]["ship"], "Your current ship", "and with which ship")
	eq(JSON.stringify(ship.to_dict()), before, "the run's ship is saved exactly as before")
	page.select_ship(3)
	eq(page.fight(), "", "a test ship fights too")
	view.leave()
	eq(page.results.size(), 2, "a second row")
	eq(page.results[1]["ending"], "you broke away", "leaving early is a break-away")
	eq(JSON.stringify(ship.to_dict()), before, "still the same")
	page.close()
	_free(d)
