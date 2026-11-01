extends "res://tests/base_test.gd"
## Species in play (docs/CONTENT.md section 9; data/species.json, data/hand_weapons.json): stats, traits
## and what they change (air, fire, repairs, reviving), the starting crews of the designs, the sidearm
## and the art each species needs.

const Fixture = preload("res://tests/fixture_ship.gd")
const Abilities = preload("res://scripts/sim/abilities.gd")
const Art = preload("res://scripts/view/art.gd")
const Content = preload("res://scripts/data/content.gd")
const CrewMember = preload("res://scripts/crew/crew_member.gd")
const Jobs = preload("res://scripts/crew/jobs.gd")
const Pathfinder = preload("res://scripts/crew/pathfinder.gd")
const PersonDrawer = preload("res://scripts/crew/person_drawer.gd")
const Ship = preload("res://scripts/ship/ship.gd")
const ShipSim = preload("res://scripts/sim/ship_sim.gd")

const STARTERS := ["res://data/ships/starter_rustbucket.json", "res://data/ships/starter_courier.json", "res://data/ships/starter_prism.json"]
const PIRATE := "res://data/ships/pirate_raider.json"
const HAND_WEAPONS := "res://data/hand_weapons.json"
const STEP := 0.1
## Section 9: name -> species of the starting crews.
const CREWS := {
	"res://data/ships/starter_rustbucket.json": {"Soldier": "human", "Ada": "human", "Rook": "basalt", "Juno": "fenn"},
	"res://data/ships/starter_courier.json": {"Soldier": "human", "Ada": "human", "Bram": "basalt"},
	"res://data/ships/starter_prism.json": {"Soldier": "human", "Tess": "emberkin", "Quill": "fenn", "Wren": "basalt"},
}
## Section 9: species -> [hp, speed, traits].
const TABLE := {
	"human": [100.0, 1.0, []],
	"basalt": [140.0, 0.75, ["no_breath"]],
	"emberkin": [90.0, 1.0, ["heat_resistant"]],
	"fenn": [75.0, 1.15, ["fast_repair"]],
}
## The class figures of the hand weapons: damage, rate, range.
const CLASSES := {
	"pistol": [10.0, 1.5, 300.0], "rifle": [14.0, 2.0, 500.0], "heavy": [30.0, 0.6, 350.0],
	"melee": [25.0, 1.2, 40.0], "tool": [6.0, 1.0, 60.0],
}
const CULTURES := ["concord", "clans", "lumen", "basalt", "emberkin", "fenn"]
## Race wave 2: their art (claude/art-race2) may not be on this branch yet. Until art/crew/<id>/ exists the art checks skip them.
const ART_PENDING := ["vellum", "oorth", "drakkin", "wisp", "hullkin", "lantern"]


func near(got: float, want: float, msg: String, eps := 1e-6) -> void:
	check(absf(got - want) <= eps, "%s: expected %s, got %s" % [msg, want, got])


func _person(p_name: String, species: String, x: int, y: int, player := false) -> CrewMember:
	var m := CrewMember.new(p_name, Pathfinder.centre_of(Vector2i(x, y)), species)
	m.is_player = player  # a player is never given a job
	return m


func _weapons() -> Array:
	var data = JSON.parse_string(FileAccess.get_file_as_string(HAND_WEAPONS))
	return data["weapons"] if data is Dictionary else []


func _default_art() -> void:
	Art.root = Art.DEFAULT_ROOT
	Art.clear_cache()


# --- stats ---------------------------------------------------------------------------------------

func test_species_set_hp_speed_and_traits() -> void:
	for id in TABLE:
		var want: Array = TABLE[id]
		var m := CrewMember.new("X", Vector2.ZERO, id)
		eq(m.species, id, id + ": the species is kept")
		near(m.max_hp, want[0], id + ": max hp")
		near(m.hp, want[0], id + ": and full hp")
		near(m.speed, CrewMember.BASE_SPEED * want[1], id + ": walk speed")
		eq(m.traits(), want[2], id + ": species traits")
	var plain := CrewMember.new("Plain")
	eq(plain.species, "human", "the default is human")
	near(plain.max_hp, 100.0, "100 hp")
	near(plain.speed, 3.0, "3 cells a second, as before")
	plain.set_species("basalt")
	near(plain.max_hp, 140.0, "a species change re-reads the body")
	near(plain.hp, 140.0, "with full hp")
	near(plain.speed, 2.25, "and the slower walk")
	var odd := CrewMember.new("Odd", Vector2.ZERO, "nobody_knows")
	near(odd.max_hp, 100.0, "an unlisted species has the crew.json hp")
	near(odd.speed, 3.0, "and the normal speed")
	eq(odd.traits(), [], "and no traits")


func test_a_slow_species_covers_less_ground() -> void:
	var ship := Fixture.room_ship()
	var runner := _person("Fast", "fenn", 9, 9)
	var walker := _person("Slow", "basalt", 9, 13)
	for m in [runner, walker]:
		ship.crew.append(m)
		m.go_to(ship.grid, Vector2i(19, m.anchor().y))
		m.step(1.0)
	near(runner.pos.x - Pathfinder.centre_of(Vector2i(9, 9)).x, 3.45, "a Fenn: 1.15 x 3 cells", 1e-4)
	near(walker.pos.x - Pathfinder.centre_of(Vector2i(9, 13)).x, 2.25, "a Basalt: 0.75 x 3 cells", 1e-4)


# --- traits ----------------------------------------------------------------------------------------

func test_traits_merge_species_personal_and_gear() -> void:
	var rook := CrewMember.new("Rook", Vector2.ZERO, "basalt")  # crew.json gives Rook a suit
	eq(rook.traits(), ["no_breath", "suit"], "species first, then personal")
	var suited := CrewMember.new("Zed")
	suited.gear_traits = ["suit"]
	eq(suited.traits(), ["suit"], "gear counts")
	suited.gear_traits = ["suit", "no_breath"]
	var twice := CrewMember.new("Zed", Vector2.ZERO, "basalt")
	twice.gear_traits = ["no_breath", "suit"]
	eq(twice.traits(), ["no_breath", "suit"], "a trait from two sources is listed once")
	check(Abilities.meets(rook, ["no_breath|suit"]), "a Basalt meets no_breath|suit")
	check(Abilities.meets(rook, ["no_breath", "suit"]), "and both, with a suit on top")
	check(Abilities.meets(suited, ["no_breath|suit"]), "a suited human meets no_breath|suit")
	check(Abilities.meets(CrewMember.new("Bram", Vector2.ZERO, "basalt"), ["no_breath|suit"]), "so does a bare Basalt")
	check(not Abilities.meets(CrewMember.new("Plain"), ["no_breath|suit"]), "a human with no suit does not")
	check(not Abilities.meets(CrewMember.new("Tess", Vector2.ZERO, "emberkin"), ["no_breath|suit"]), "nor an Emberkin")
	eq(Abilities.traits_of(rook), rook.traits(), "abilities.gd reads the merged list")


func test_a_basalt_can_work_the_afterburner_and_an_unsuited_human_cannot() -> void:
	var ship := Fixture.room_ship()
	Fixture.put(ship, "reactor_mk1", 10, 10)
	var burner := Fixture.put(ship, "afterburner", 15, 10)
	Fixture.wire(ship, [Vector2i(11, 11), Vector2i(12, 11), Vector2i(13, 11), Vector2i(14, 11), Vector2i(15, 11)])
	ship.refresh()
	var human := CrewMember.new("Pike", Vector2(12.0, 12.0))
	var basalt := CrewMember.new("Bram", Vector2(12.0, 12.0), "basalt")
	ship.crew.append_array([human, basalt])
	ship.manned[burner] = "Pike"
	check(Abilities.can_trigger(ship, burner) != "", "a human with no suit cannot")
	ship.manned[burner] = "Bram"
	eq(Abilities.can_trigger(ship, burner), "", "a Basalt can")


# --- what the traits change ----------------------------------------------------------------------

func test_no_breath_takes_no_damage_without_air_and_a_human_does() -> void:
	var ship := Fixture.room_ship()
	var basalt := _person("Bram", "basalt", 12, 11, true)
	var human := _person("Pike", "human", 17, 11, true)
	var fenn := _person("Quill", "fenn", 12, 14, true)
	ship.crew.append_array([basalt, human, fenn])
	var room := ship.atmosphere.room_at(basalt.cell())
	eq(ship.atmosphere.room_at(human.cell()), room, "all in the one room")
	ship.atmosphere.pressure[room] = 0.0
	Jobs.new().tick(ship, 1.0)
	near(basalt.hp, 140.0, "the Basalt takes nothing")
	near(human.hp, 95.0, "the human takes 5 a second")
	near(fenn.hp, 70.0, "so does the Fenn")


func test_no_breath_crew_use_no_air() -> void:
	var used := {}
	for species in ["basalt", "human"]:
		var ship := Fixture.room_ship()
		var m := _person("Wren", species, 12, 11, true)
		ship.crew.append(m)
		var room := ship.atmosphere.room_at(m.cell())
		var before: float = ship.atmosphere.oxygen_of(room)
		var sim := ShipSim.new()
		sim.ships = [ship]
		sim._step_ship(ship, 1.0)
		used[species] = before - ship.atmosphere.oxygen_of(room)
	near(used["basalt"], 0.0, "a Basalt breathes nothing")
	check(used["human"] > 0.0, "a human uses the room's air")


func test_heat_resistant_takes_a_quarter_of_the_fire_damage() -> void:
	var ship := Fixture.room_ship()
	ship.fires[Vector2i(15, 12)] = 0.5
	ship.fires[Vector2i(11, 12)] = 0.5
	ship.fires[Vector2i(19, 12)] = 0.5
	var ember := _person("Tess", "emberkin", 14, 11, true)  # the body covers 14..15 x 11..12
	var human := _person("Pike", "human", 10, 11, true)
	var basalt := _person("Bram", "basalt", 18, 11, true)
	ship.crew.append_array([ember, human, basalt])
	Jobs.new().tick(ship, 1.0)
	near(ember.hp, 90.0 - 2.5, "an Emberkin: 10 x 0.25 a second")
	near(human.hp, 90.0, "a human: 10 a second")
	near(basalt.hp, 130.0, "a Basalt burns like anyone")


func test_fast_repair_finishes_in_six_tenths_of_the_time() -> void:
	var times := {}
	for species in ["human", "fenn"]:
		var ship := Fixture.room_ship()
		var uid := Fixture.put(ship, "engine_mk1", 15, 10)
		var inst: Dictionary = ship.components.instances[uid]
		inst["status"] = "malfunction"
		inst["hp"] = 1
		ship.crew.append(_person("A", species, 13, 10))
		var jobs := Jobs.new()
		var t := 0.0
		while inst["status"] != "ok" and t < 60.0:
			jobs.tick(ship, STEP)
			t += STEP
		times[species] = t
	var part := float(Jobs.jcfg()["repair_component"]["seconds"])  # data/crew.json: 12 s
	near(times["human"], part, "a human repair takes the job's time", 0.15)
	near(times["fenn"], part * 0.6, "a Fenn's takes 0.6 of it", 0.15)
	near(times["fenn"] / times["human"], 0.6, "0.6 of the time", 0.03)


func test_fast_repair_patches_breaches_in_six_tenths_of_the_time_too() -> void:
	var times := {}
	for species in ["human", "fenn"]:
		var ship := Fixture.room_ship()
		ship.grid.breach(Vector2i(15, 8))
		ship.mark_dirty()
		ship.crew.append(_person("A", species, 14, 9))
		var jobs := Jobs.new()
		var t := 0.0
		while not ship.grid.breached.is_empty() and t < 60.0:
			jobs.tick(ship, STEP)
			t += STEP
		times[species] = t
	var breach := float(Jobs.jcfg()["repair_breach"]["seconds"])  # 14 s
	near(times["human"], breach, "a human seals a breach in the job's time", 0.15)
	near(times["fenn"], breach * 0.6, "a Fenn in 0.6 of it", 0.15)


func test_the_player_with_fast_repair_works_faster_by_hand_too() -> void:
	var ship := Fixture.room_ship()
	var uid := Fixture.put(ship, "engine_mk1", 15, 10)
	ship.components.instances[uid]["status"] = "malfunction"
	var fenn := _person("Soldier", "fenn", 13, 10, true)
	ship.crew.append(fenn)
	var jobs := Jobs.new()
	jobs.build_board(ship)
	jobs.hand_work(ship, fenn, 1.0)
	near(jobs.progress["fix:%d" % uid], 1.0 / 0.6, "one second of E is 1 / 0.6 seconds of work")


func test_a_basalt_revives_at_half_speed() -> void:
	var rates := {}
	for species in ["human", "basalt"]:
		var ship := Fixture.room_ship()
		var down := _person("Soldier", "human", 18, 14, true)
		down.hurt(1000.0)
		var medic := _person("Ada", species, 16, 14)
		ship.crew.append_array([down, medic])
		var jobs := Jobs.new()
		jobs.build_board(ship)
		jobs.work(ship, medic, jobs.board["revive:Soldier"], 1.0)
		rates[species] = jobs.progress["revive:Soldier"]
	near(rates["human"], 1.0, "a human: a second of work a second")
	near(rates["basalt"], 0.5, "a Basalt: half a second")


# --- crews -----------------------------------------------------------------------------------------

func test_the_starters_start_with_the_soldier_alone() -> void:  # playtest 2, A1
	for path in CREWS:
		var ship := Ship.from_design(path)
		eq(ship.crew_plan, [{"name": "Soldier", "species": "human"}], path + ": the crew list")
		Jobs.spawn_crew(ship)
		eq(ship.crew.size(), 1, path + ": one spawned")


func test_a_listed_crew_spawns_with_their_species_and_hp() -> void:
	for path in CREWS:
		var ship := Ship.from_design(path)
		var want: Dictionary = CREWS[path]
		ship.crew_plan = want.keys().map(func(n): return {"name": n, "species": want[n]})  # (the old starting crews)
		eq(ship.crew_plan.map(func(e): return e["name"]), want.keys(), path + ": the crew list")
		Jobs.spawn_crew(ship)
		eq(ship.crew.size(), want.size(), path + ": all spawned")
		for m in ship.crew:
			eq(m.species, want.get(m.name), "%s: %s's species" % [path, m.name])
			near(m.max_hp, TABLE[m.species][0], "%s: %s has their species' hp" % [path, m.name])
	var pirate := Ship.from_design(PIRATE)
	var made := Jobs.spawn_enemy_crew(pirate)
	eq(made.map(func(m): return m.species), ["human", "human", "basalt"], "the raider: 2 humans and a Basalt")
	eq(made.size(), 3, "three of them")
	check(made.all(func(m): return m.look == made[0].look), "in the enemy colours")


func test_every_ship_with_an_afterburner_has_a_qualified_operator() -> void:
	var needs: Array = Ship.new().components.def("afterburner")["abilities"][0]["operator_needs"]
	eq(needs, ["no_breath|suit"], "the afterburner asks for a breathless or suited operator")
	var carrying := 0
	for path in STARTERS + [PIRATE]:
		var ship := Ship.from_design(path)
		var has := int(ship.inventory.to_dict().get("afterburner", 0)) > 0
		for uid in ship.components.instances:
			has = has or ship.components.instances[uid]["id"] == "afterburner"
		if not has:
			continue
		carrying += 1
		if ship.crew_plan.size() <= 1:  # the soldier alone: the operator (a Basalt or a suited hand) is a crewmate found on the way
			continue
		var crew: Array = ship.crew_plan.map(func(e): return CrewMember.new(e["name"], Vector2.ZERO, e["species"]))
		check(crew.any(func(m): return Abilities.meets(m, needs)), path + ": somebody aboard can work an afterburner")
	check(carrying >= 2, "the Courier and the Prism carry one (found %d)" % carrying)


func test_the_crew_spawn_with_their_species_and_unlisted_names_are_human() -> void:
	var ship := Ship.from_design(STARTERS[0])
	ship.crew_plan = CREWS[STARTERS[0]].keys().map(func(n): return {"name": n, "species": CREWS[STARTERS[0]][n]})
	Jobs.spawn_crew(ship)
	var rook: CrewMember = ship.crew.filter(func(m): return m.name == "Rook")[0]
	eq(rook.species, "basalt", "Rook is a Basalt")
	near(rook.max_hp, 140.0, "with 140 hp")
	check(Abilities.meets(rook, ["no_breath", "suit"]), "and keeps the suit crew.json gives him")
	var plain := Ship.from_design(STARTERS[0])
	plain.crew_plan = []
	Jobs.spawn_crew(plain)
	check(plain.crew.all(func(m): return m.species == "human"), "a design with no crew list has all-human defaults")


func test_a_crew_list_is_read_loosely() -> void:
	var ship := Ship.from_design(PIRATE)
	eq(ship.crew_plan, [{"name": "Grub", "species": "human"}, {"name": "Skab", "species": "human"}, {"name": "Vex", "species": "basalt"}], "name and species")
	var empty := Ship.new_starter()
	eq(empty.crew_plan, [], "a ship with no design has no list")


# --- art and weapons -----------------------------------------------------------------------------------

func test_every_species_has_its_rig_and_sidearm_art() -> void:
	_default_art()
	var table: Dictionary = CrewMember.species_table()["species"]
	for id in TABLE:
		check(table.has(id), id + ": one of the four species of the notes")
	check(table.size() >= TABLE.size(), "and the species of the packs come on top")
	var ids: Array = Content.ids("hand_weapons")  # the base file and the packs (the race wave 1 sidearms live in the tech packs)
	for id in table:
		var def: Dictionary = table[id]
		var m := CrewMember.new("X", Vector2.ZERO, id)
		eq(m.rig(), def["rig"], id + ": the rig")
		if bool(def.get("drone", false)):
			continue  # a repair drone is drawn in code (PersonDrawer.draw_drone): it has no rig art
		if ART_PENDING.has(id) and Art.crew(m.rig()) == null:
			continue
		check(Art.crew(m.rig()) != null, "%s: art/crew/%s/ is there" % [id, m.rig()])
		check(Art.crew(m.rig()).layers.has("arms") and Art.crew(m.rig()).layers.has("head"), id + ": with arms and a head")
		if m.sidearm() == "":
			continue  # a species may carry none (the Wisp)
		check(ids.has(m.sidearm()), "%s: the sidearm %s is a hand weapon" % [id, m.sidearm()])
		check(Art.item(m.sidearm()) != null, "%s: art/items/%s.png is there" % [id, m.sidearm()])
		var cls: String = Art.item(m.sidearm()).pose
		check(Art.crew(m.rig()).poses.has(cls) and Art.crew(m.rig()).poses[cls]["mount"] != null, "%s: the rig has an arm pose for %s" % [id, cls])
	eq(Art.crew_rig("basalt"), "basalt", "a rig that exists is used")
	eq(Art.crew_rig("not_drawn_yet"), "human", "a missing one falls back to human")
	_default_art()


func test_the_hand_weapons_all_have_art_and_sensible_numbers() -> void:
	_default_art()
	var list := _weapons()
	eq(list.size(), 12, "the twelve weapons with art")
	var seen := {}
	for w in list:
		var id: String = w["id"]
		check(not seen.has(id), id + ": listed once")
		seen[id] = true
		check(FileAccess.file_exists("res://art/items/%s.png" % w["art"]), id + ": art/items/%s.png exists" % w["art"])
		var art = Art.item(w["art"])
		check(art != null, id + ": the art loads")
		check(CULTURES.has(w["culture"]), "%s: culture %s" % [id, w["culture"]])
		check(CLASSES.has(w["class"]), "%s: class %s" % [id, w["class"]])
		var js := Art.read_json("res://art/items/%s.json" % w["art"])
		eq(w["class"], js.get("class"), id + ": the class of the art")
		eq(w["culture"], "clans" if js.get("culture") == "scrap" else js.get("culture"), id + ": the culture of the art")
		var base: Array = CLASSES[w["class"]]
		var changed := false
		for i in 3:
			var got := float(w[["damage", "rate", "range"][i]])
			check(got >= base[i] * 0.8 - 1e-6 and got <= base[i] * 1.2 + 1e-6, "%s: %s is within 20%% of the %s figure" % [id, ["damage", "rate", "range"][i], w["class"]])
			changed = changed or absf(got - base[i]) > 1e-6
		check(str(w.get("notes", "")) != "", id + ": has a note")
		if changed:
			check(str(w["notes"]).contains("%"), id + ": a shifted figure says by how much")
	var dir := DirAccess.open("res://art/items")
	for f in dir.get_files():
		if f.ends_with(".json"):
			var js := Art.read_json("res://art/items/" + f)
			if js.has("culture"):
				check(seen.has(f.get_basename()) or Content.has("hand_weapons", f.get_basename()), "%s: a cultured item in art/items is a hand weapon" % f)  # the base file or a pack


func test_every_pack_hand_weapon_has_matching_art_and_the_flashes_name_real_weapons() -> void:
	_default_art()
	var ids: Array[String] = Content.ids("hand_weapons")
	check(ids.size() >= 24, "the base weapons and the race packs' (%d)" % ids.size())
	for id in ids:
		var w: Dictionary = Content.entry("hand_weapons", id)
		var art = Art.item(str(w["art"]))
		check(art != null, "%s: art/items/%s.png loads" % [id, w["art"]])
		if art == null:
			continue
		eq(art.pose, w["class"], id + ": the art's arm pose is the weapon's class")
		check(art.anchors.has("grip") and art.anchors.has("muzzle"), id + ": the art has a grip and a muzzle")
		check(art.anchors["grip"].y > art.anchors["muzzle"].y and art.anchors["grip"].x < art.frame.x, id + ": the grip is below the muzzle, inside the frame")
	var seen_for := {}
	for f in DirAccess.get_files_at("res://art/items/fx"):
		if not f.ends_with(".json"):
			continue
		var js := Art.read_json("res://art/items/fx/" + f)
		var fr: Array = js["frame"]
		var m: Array = js["anchors"]["muzzle"]
		check(m[0] >= 0 and m[0] < fr[0] and m[1] >= 0 and m[1] < fr[1], f + ": the muzzle anchor is inside the frame")
		check(js["anims"].has("play"), f + ": plays")
		for it in js.get("for_item", []):
			check(Content.has("hand_weapons", it), "%s: names the hand weapon %s" % [f, it])
			seen_for[it] = true
	for id in ["sting_pistol", "bubble_rifle", "spore_puffer", "rivet_fist", "arc_welder", "lens_pistol", "shard_lance", "chain_gun"]:
		check(seen_for.has(id), id + ": has a muzzle flash")


# --- drawing ------------------------------------------------------------------------------------------

func test_the_sidearm_comes_out_when_idle_in_a_fight() -> void:
	var bram := CrewMember.new("Bram", Vector2(5, 5), "basalt")
	eq(PersonDrawer.item_for(bram, 0.0), "", "holstered when there is no fight")
	eq(PersonDrawer.item_for(bram, 0.0, true), "quarry_hammer", "drawn in a fight")
	bram.job = {"type": "repair_component", "key": "fix:1"}
	eq(PersonDrawer.item_for(bram, 0.0, true), "wrench", "tools at work")
	bram.job = {"type": "man_station", "key": "post:1"}
	eq(PersonDrawer.item_for(bram, 0.0, true), "", "holstered at a station")
	bram.job = {}
	bram.hurt(1000.0)
	eq(PersonDrawer.item_for(bram, 0.0, true), "", "and when down")
	var soldier := CrewMember.new("Soldier", Vector2(5, 5), "fenn")
	soldier.is_player = true
	eq(PersonDrawer.item_for(soldier, 0.0), "pistol", "the player keeps the pistol")
	eq(PersonDrawer.item_for(soldier, 0.0, true), "pistol", "in a fight too")
	for pair in [["human", "service_pistol"], ["emberkin", "ember_knife"], ["fenn", "spark_pistol"]]:
		eq(PersonDrawer.item_for(CrewMember.new("N", Vector2.ZERO, pair[0]), 0.0, true), pair[1], pair[0] + ": its culture's sidearm")


func test_the_drawing_plan_uses_the_species_rig_and_the_sidearm() -> void:
	_default_art()
	for id in TABLE:
		var m := CrewMember.new("N", Vector2.ZERO, id)
		var plan := PersonDrawer.plan(Art.crew(Art.crew_rig(m.rig())), {"species": m.rig(), "item": m.sidearm(), "aim": 0.0})
		var item := {}
		for l in plan:
			if l["layer"] == "item":
				item = l
		check(not item.is_empty() and item["id"] == m.sidearm(), "%s: the %s is in hand" % [id, m.sidearm()])
		check(plan.size() == 5, id + ": legs, torso, arms, item and head")
	check(Art.crew("basalt") != Art.crew("human"), "the Basalt has a rig of its own")
	_default_art()
