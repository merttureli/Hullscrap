extends "res://tests/base_test.gd"
## The crew trait library (data/traits.json, docs/CONTENT_PLAN.md section 2) and its resolver
## (scripts/crew/traits.gd): one test for every key, each through the system it changes, the three old
## traits as bags of keys, and the six species of the races_1 pack (spawned and drawn).
## Traits the data has no use for yet are made up in the library for the test (`_trait`) and removed again.

const Abilities = preload("res://scripts/sim/abilities.gd")
const Arena = preload("res://scripts/combat/arena.gd")
const Art = preload("res://scripts/view/art.gd")
const Campaign = preload("res://scripts/space/campaign.gd")
const Content = preload("res://scripts/data/content.gd")
const CrewMember = preload("res://scripts/crew/crew_member.gd")
const Damage = preload("res://scripts/combat/damage.gd")
const Fixture = preload("res://tests/fixture_ship.gd")
const BuildSession = preload("res://scripts/ship/build_session.gd")
const Jobs = preload("res://scripts/crew/jobs.gd")
const Pathfinder = preload("res://scripts/crew/pathfinder.gd")
const PersonDrawer = preload("res://scripts/crew/person_drawer.gd")
const Ship = preload("res://scripts/ship/ship.gd")
const ShipSim = preload("res://scripts/sim/ship_sim.gd")
const TraitSet = preload("res://scripts/crew/traits.gd")

const STEP := 0.1
const LEGACY_ROOT := "res://tests/fixtures/traits_legacy"
## The races_1 pack: species -> [hp, speed, traits, sidearm].
const RACES := {
	"kett": [80.0, 1.0, ["swarm"], "sting_pistol"],
	"mire": [100.0, 1.0, ["firefighter", "dries_out"], "bubble_rifle"],
	"sporeling": [100.0, 0.8, ["aura_spores", "flammable"], "spore_puffer"],
	"gauntling": [100.0, 1.0, ["mechanical", "half_lungs", "ion_prone", "tinkerer"], "rivet_fist"],
	"prismatic": [100.0, 1.0, ["crystal_conduit", "crystal_body"], "lens_pistol"],
	"grundl": [180.0, 0.7, ["hauler", "clumsy"], "freight_hammer"],
}


func near(got: float, want: float, msg: String, eps := 1e-6) -> void:
	check(absf(got - want) <= eps, "%s: expected %s, got %s" % [msg, want, got])


## A made-up trait for a test; `_done` forgets it.
func _trait(id: String, bag: Dictionary) -> void:
	var e := {"name": id}
	e.merge(bag)
	TraitSet.library()[id] = e


func _done() -> void:
	TraitSet.reset()
	CrewMember.config()["traits"].erase("Tank")
	Content.root = Content.DATA_ROOT
	Art.root = Art.DEFAULT_ROOT
	Art.clear_cache()


## A person on the body anchor (x, y). A player is never given a job.
func _person(p_name: String, species: String, x: int, y: int, player := false) -> CrewMember:
	var m := CrewMember.new(p_name, Pathfinder.centre_of(Vector2i(x, y)), species)
	m.is_player = player
	return m


## The sealed room of the fixture ship plus a second one under it (y 19..25).
func _two_rooms() -> Ship:
	var ship := Fixture.room_ship()
	BuildSession.new(ship).apply(BuildSession.room_changes(Vector2i(8, 18), Vector2i(22, 26), "wall", "floor"))
	ship.refresh()
	for i in ship.atmosphere.pressure.size():
		ship.atmosphere.pressure[i] = 1.0  # a new room starts empty
	return ship


func _jobs_run(ship: Ship, jobs: Jobs, seconds: float) -> void:
	var t := 0.0
	while t < seconds - 1e-9:
		jobs.tick(ship, STEP)
		t += STEP


## Seconds until `done` is true, running the jobs of `ship` in STEP steps (60 at most).
func _seconds_until(ship: Ship, jobs: Jobs, done: Callable) -> float:
	var t := 0.0
	while not done.call() and t < 60.0:
		jobs.tick(ship, STEP)
		t += STEP
	return t


# --- the library and the resolver ----------------------------------------------------------------------

func test_the_three_old_traits_are_bags_of_keys() -> void:
	var lib := TraitSet.library()
	for id in ["no_breath", "heat_resistant", "fast_repair", "suit"]:
		check(lib.has(id), id + " is in the library (data/traits.json)")
	var human := TraitSet.of(CrewMember.new("X"))
	near(human["o2_use"], 1.0, "a human breathes normally")
	near(human["damage_taken"]["fire"], 1.0, "and burns normally")
	near(human["work_mult"]["repair"], 1.0, "and repairs at the normal speed")
	check(not human["mechanical"], "and is not a machine")
	var basalt := TraitSet.of(CrewMember.new("X", Vector2.ZERO, "basalt"))
	near(basalt["o2_use"], 0.0, "no_breath: o2_use 0")
	near(basalt["work_mult"]["heal_others"], 0.5, "the Basalt species entry carries heal_others 0.5 inline")
	near(TraitSet.of(CrewMember.new("X", Vector2.ZERO, "emberkin"))["damage_taken"]["fire"], 0.25, "heat_resistant: fire damage x0.25")
	var fenn := TraitSet.of(CrewMember.new("X", Vector2.ZERO, "fenn"))
	near(fenn["work_mult"]["repair"], 1.0 / 0.6, "fast_repair: repair work 1 / 0.6 as fast", 1e-6)
	near(fenn["work_mult"]["breach"], 1.0 / 0.6, "and breach patching too", 1e-6)
	check(TraitSet.library()["suit"].get("o2_use") == null, "suit is only a label")
	_done()


func test_traits_merge_species_personal_and_gear() -> void:
	_trait("t_wet", {"damage_taken": {"fire": 0.5}, "aura": {"heal_per_s": 1.0, "work_mult": 1.5}, "ion_stun": 2.0})
	_trait("t_wetter", {"damage_taken": {"fire": 0.5}, "aura": {"heal_per_s": 0.5, "work_mult": 1.2}, "ion_stun": 3.0, "mechanical": true})
	var m := CrewMember.new("X", Vector2.ZERO, "emberkin")  # fire x0.25
	m.gear_traits = ["t_wet", "t_wetter"]
	var t := TraitSet.of(m)
	near(t["damage_taken"]["fire"], 0.25 * 0.5 * 0.5, "factors multiply")
	near(t["aura"]["heal_per_s"], 1.5, "amounts add")
	near(t["aura"]["work_mult"], 1.5 * 1.2, "an aura's work factor multiplies")
	near(t["ion_stun"], 3.0, "the longest stun")
	check(t["mechanical"], "mechanical if any trait says so")
	check(TraitSet.of(CrewMember.new("X", Vector2.ZERO, "emberkin")) != t, "another set of traits is another result")
	var rook := CrewMember.new("Rook", Vector2.ZERO, "basalt")  # crew.json gives Rook a suit
	near(TraitSet.of(rook)["o2_use"], 0.0, "personal traits join the species': a Basalt in a suit")
	var odd := CrewMember.new("Odd", Vector2.ZERO, "nobody_knows")
	near(TraitSet.of(odd)["hp_mult"], 1.0, "an unlisted species has no keys")
	_done()


func test_hp_mult_and_speed_mult_scale_the_body() -> void:
	_trait("t_tough", {"hp_mult": 1.5, "speed_mult": 0.5})
	CrewMember.config()["traits"]["Tank"] = ["t_tough"]
	var tank := CrewMember.new("Tank", Vector2.ZERO, "fenn")  # 75 hp, 1.15
	near(tank.max_hp, 112.5, "hp x1.5")
	near(tank.hp, 112.5, "full")
	near(tank.speed, CrewMember.BASE_SPEED * 1.15 * 0.5, "speed x0.5")
	var plain := CrewMember.new("Plain", Vector2.ZERO, "fenn")
	near(plain.max_hp, 75.0, "others are as before")
	_done()


func test_o2_use_scales_the_air_a_person_breathes() -> void:
	var used := {}
	for species in ["human", "gauntling", "basalt"]:
		var ship := Fixture.room_ship()
		var m := _person("Wren", species, 12, 11, true)
		ship.crew.append(m)
		var room := ship.atmosphere.room_at(m.cell())
		var before: float = ship.atmosphere.oxygen_of(room)
		var sim := ShipSim.new()
		sim.ships = [ship]
		sim._step_ship(ship, 1.0)
		used[species] = before - ship.atmosphere.oxygen_of(room)
	check(used["human"] > 0.0, "a human uses the room's air")
	near(used["gauntling"], used["human"] * 0.5, "a Gauntling (o2_use 0.5) half as much", 1e-9)
	near(used["basalt"], 0.0, "a Basalt (o2_use 0) none")
	_done()


func test_suffocation_follows_no_air_damage_and_suffocate_mult_and_o2_use_zero_never_suffocates() -> void:
	_trait("t_thin", {"damage_taken": {"no_air": 0.5}})
	_trait("t_gasp", {"suffocate_mult": 2.0})
	var ship := Fixture.room_ship()
	var people := {}
	var x := 10
	for pair in [["human", []], ["gauntling", []], ["basalt", []], ["human", ["t_thin"]], ["human", ["t_gasp"]]]:
		var m := _person("P%d" % x, pair[0], x, 11, true)
		m.gear_traits = pair[1]
		ship.crew.append(m)
		people[x] = m
		x += 2
	ship.atmosphere.pressure[ship.atmosphere.room_at(people[10].cell())] = 0.0
	Jobs.new().tick(ship, 1.0)
	near(people[10].hp, 95.0, "a human takes 5 a second")
	near(people[12].hp, 95.0, "a Gauntling breathes less, but suffocates like anyone")
	near(people[14].max_hp - people[14].hp, 0.0, "a Basalt (o2_use 0) cannot suffocate")
	near(people[16].hp, 97.5, "damage_taken.no_air 0.5")
	near(people[18].hp, 90.0, "suffocate_mult 2")
	_done()


func test_damage_taken_by_fire_ion_and_the_kept_melee_and_ranged() -> void:
	var ship := Fixture.room_ship()
	for x in [11, 15, 19]:
		ship.fires[Vector2i(x, 12)] = 0.5
	var spore := _person("Spore", "sporeling", 10, 11, true)  # fire x1.5
	var mire := _person("Mire", "mire", 14, 11, true)  # fire x0.5
	var human := _person("Pike", "human", 18, 11, true)
	ship.crew.append_array([spore, mire, human])
	Jobs.new().tick(ship, 1.0)
	near(spore.hp, 100.0 - 15.0 + 1.0, "a Sporeling burns x1.5 (and its own spores heal it 1 hp)")
	near(mire.hp, 100.0 - 5.0 + 1.0, "a Mire x0.5 (the spores heal the whole room)")
	near(human.hp, 100.0 - 10.0 + 1.0, "a human 10 a second")
	_trait("t_hide", {"damage_taken": {"melee": 0.5, "ranged": 2.0}})
	var m := CrewMember.new("X")
	m.gear_traits = ["t_hide"]
	near(TraitSet.of(m)["damage_taken"]["melee"], 0.5, "melee damage_taken is kept for the on-foot fights")
	near(TraitSet.of(m)["damage_taken"]["ranged"], 2.0, "and ranged")
	_done()


func test_ion_hurts_and_stuns_the_crew_in_the_room_it_hits() -> void:
	var ship := _two_rooms()
	var prism := _person("Glint", "prismatic", 12, 11, true)  # ion x2
	var human := _person("Pike", "human", 16, 11, true)
	var gaunt := _person("Rivet", "gauntling", 12, 14, true)  # stunned 3 s
	var far := _person("Far", "gauntling", 12, 21, true)  # the other room
	ship.crew.append_array([prism, human, gaunt, far])
	var hp: float = CrewMember.config()["ion_hp"]
	Jobs.ion_hit(ship, Vector2i(8, 12), 1.0)  # the west wall of the first room
	near(human.hp, 100.0 - hp, "a human takes ion_hp a point")
	near(prism.hp, 100.0 - 2.0 * hp, "a Prismatic twice that")
	near(gaunt.stun, 3.0, "a Gauntling is stunned for 3 s")
	near(human.stun, 0.0, "a human is not")
	near(far.hp, 100.0, "nobody in the other room is touched")
	near(far.stun, 0.0, "or stunned")
	_done()


func test_an_ion_shot_through_the_arena_reaches_the_crew() -> void:
	var ship := Fixture.room_ship()
	var gaunt := _person("Rivet", "gauntling", 12, 11, true)
	ship.crew.append(gaunt)
	var arena := Arena.new(1)
	var idx := arena.add_ship(ship)
	var cell := Vector2i(8, 12)
	var obj := Damage.solid_at(arena.ships[idx], cell)
	check(not obj.is_empty(), "a wall stands there")
	Damage.apply(arena, idx, cell, obj, 1.0, "energy")
	near(gaunt.stun, 0.0, "an energy hit stuns nobody")
	Damage.apply(arena, idx, cell, obj, 1.0, "ion")
	near(gaunt.stun, 3.0, "an ion hit through Damage.apply stuns the Gauntling")
	_done()


func test_a_stunned_crew_member_neither_walks_nor_works_until_it_wears_off() -> void:
	var ship := Fixture.room_ship()
	var uid := Fixture.put(ship, "engine_mk1", 15, 10)
	ship.components.instances[uid]["status"] = "malfunction"
	var gaunt := _person("Rivet", "gauntling", 13, 14)
	var soldier := _person("Soldier", "gauntling", 10, 14, true)
	ship.crew.append_array([gaunt, soldier])
	var jobs := Jobs.new()
	jobs.build_board(ship)
	jobs.assign(ship)
	check(not gaunt.job.is_empty(), "the Gauntling has a repair to walk to")
	var start := gaunt.pos
	Jobs.ion_hit(ship, Vector2i(8, 12), 1.0)
	soldier.move_input(ship.grid, Vector2.RIGHT, 0.5)
	eq(soldier.pos, Pathfinder.centre_of(Vector2i(10, 14)), "a stunned player does not move")
	check(jobs.hand_work(ship, soldier, 0.5) == "", "or work by hand")
	_jobs_run(ship, jobs, 2.9)
	eq(gaunt.pos, start, "stunned for 3 s: still where they were after 2.9")
	_jobs_run(ship, jobs, 0.5)
	check(gaunt.pos != start, "then on their way")
	near(gaunt.stun, 0.0, "the stun is over")
	_done()


func test_work_mult_scales_repair_breach_and_extinguish() -> void:
	var times := {}
	for species in ["human", "gauntling", "grundl"]:
		var ship := Fixture.room_ship()
		var uid := Fixture.put(ship, "engine_mk1", 15, 10)
		var inst: Dictionary = ship.components.instances[uid]
		inst["status"] = "malfunction"
		inst["hp"] = 1
		ship.crew.append(_person("A", species, 13, 10))
		var jobs := Jobs.new()
		times[species] = _seconds_until(ship, jobs, func(): return inst["status"] == "ok")
	var part := float(Jobs.jcfg()["repair_component"]["seconds"])  # data/crew.json: 12 s
	near(times["human"], part, "a human repair takes the job's time", 0.15)
	near(times["gauntling"], part * 0.8, "a Gauntling (tinkerer, time x0.8)", 0.15)
	near(times["grundl"], part * 1.3, "a Grundl (clumsy, time x1.3)", 0.15)
	var seal := {}
	for species in ["human", "gauntling", "grundl"]:
		var ship := Fixture.room_ship()
		ship.grid.breach(Vector2i(15, 8))
		ship.mark_dirty()
		ship.crew.append(_person("A", species, 14, 9))
		seal[species] = _seconds_until(ship, Jobs.new(), func(): return ship.grid.breached.is_empty())
	var breach := float(Jobs.jcfg()["repair_breach"]["seconds"])  # 14 s
	near(seal["human"], breach, "a breach takes a human the job's time", 0.15)
	near(seal["gauntling"], breach * 0.8, "a Gauntling x0.8", 0.15)
	near(seal["grundl"], breach * 1.3, "a Grundl x1.3", 0.15)
	var left := {}
	for species in ["human", "mire"]:
		var ship := Fixture.room_ship()
		ship.fires[Vector2i(15, 12)] = 0.5
		var m := _person("A", species, 11, 12, true)
		ship.crew.append(m)
		var jobs := Jobs.new()
		jobs.build_board(ship)
		jobs.work(ship, m, jobs.board["fire:15,12"], 0.25)
		left[species] = ship.fires[Vector2i(15, 12)]
	near(left["human"], 0.5 - 0.125, "a human takes 0.5 a second off a fire")
	near(left["mire"], 0.5 - 0.25, "a Mire (extinguish x2) twice that")
	_done()


func test_man_restock_and_craft_work_mult_and_manned_mult() -> void:
	var ship := Fixture.room_ship()
	var helm := Fixture.put(ship, "helm", 12, 10)
	_trait("t_gunner", {"work_mult": {"man": 2.0}})
	_trait("t_steady", {"station": {"manned_mult": 1.5}})
	var ada := _person("Ada", "human", 12, 13)
	ship.crew.append(ada)
	ship.manned[helm] = "Ada"
	var base: float = CrewMember.config()["manned"]["helm_evasion"]
	var cool: float = CrewMember.config()["manned"]["weapon_cooldown"]
	near(Jobs.evasion_bonus(ship), base, "a plain operator: the data's helm evasion")
	ada.gear_traits = ["t_gunner"]
	near(Jobs.evasion_bonus(ship), base * 2.0, "work_mult.man x2 doubles what the post gives")
	ada.gear_traits = ["t_steady"]
	near(Jobs.evasion_bonus(ship), base * 1.5, "station.manned_mult x1.5")
	ada.gear_traits = ["t_gunner", "t_steady"]
	near(Jobs.evasion_bonus(ship), base * 3.0, "and they multiply")
	var gun := Fixture.put(ship, "laser_mk1", 15, 10)
	ship.manned[gun] = "Ada"
	near(Jobs.cooldown_mult(ship, gun), 1.0 - cool * 3.0, "a manned weapon cools down by the factor too")
	ada.gear_traits = []
	near(Jobs.cooldown_mult(ship, gun), 1.0 - cool, "as before without the traits")
	var grundl := _person("Bulk", "grundl", 17, 13)
	ship.crew.append(grundl)
	near(TraitSet.work_rate(ship, grundl, "restock"), 2.0, "a Grundl restocks twice as fast (kept: no job restocks yet)")
	_trait("t_craft", {"work_mult": {"craft": 1.5}})
	ada.gear_traits = ["t_craft"]
	near(TraitSet.work_rate(ship, ada, "craft"), 1.5, "craft is kept too")
	near(TraitSet.work_rate(ship, ada, "no_such_job"), 1.0, "a job nobody scales runs at 1")
	_done()


func test_heal_mult_and_mechanical_crew_are_not_healed_by_beds() -> void:
	var ship := Fixture.room_ship()
	var bed_a := Fixture.put(ship, "bed", 10, 9)
	var bed_b := Fixture.put(ship, "bed", 14, 9)
	var bed_c := Fixture.put(ship, "bed", 18, 9)
	_trait("t_numb", {"heal_mult": {"bed": 0.5}})
	var human := _person("Pike", "human", 10, 10, true)
	var gaunt := _person("Rivet", "gauntling", 14, 10, true)
	var numb := _person("Numb", "human", 18, 10, true)
	numb.gear_traits = ["t_numb"]
	ship.crew.append_array([human, gaunt, numb])
	for m in [human, gaunt, numb]:
		m.hp = 50.0
	Jobs.new().tick(ship, 1.0)
	near(human.hp, 55.0, "a bed heals a human 5 a second")
	near(gaunt.hp, 50.0, "and a Gauntling (mechanical) not at all")
	near(numb.hp, 52.5, "heal_mult.bed 0.5: half")
	check(bed_a >= 0 and bed_b >= 0 and bed_c >= 0, "the beds stand")
	# a medbay that is on, with a heal_mult of its own
	var medbay := Fixture.put(ship, "medbay", 10, 13)
	check(medbay >= 0, "the medbay fits")
	ship.power_state["powered"][medbay] = true
	_trait("t_cold", {"heal_mult": {"medbay": 0.0}})
	var cold := _person("Cold", "human", 10, 13, true)  # both lie in the 2x4 medbay (x 10..11, y 13..16)
	cold.gear_traits = ["t_cold"]
	var warm := _person("Warm", "human", 10, 15, true)
	ship.crew.append_array([cold, warm])
	cold.hp = 50.0
	warm.hp = 50.0
	Jobs.new().tick(ship, 1.0)
	near(warm.hp, 65.0, "a powered medbay heals 15 a second")
	near(cold.hp, 50.0, "heal_mult.medbay 0: nothing")
	_done()


func test_a_hurt_mechanical_crew_member_gets_a_repair_job_that_any_other_crew_member_does() -> void:
	var ship := Fixture.room_ship()
	Fixture.put(ship, "bed", 10, 10)
	var gaunt := _person("Rivet", "gauntling", 18, 13)
	gaunt.hp = 40.0
	ship.crew.append(gaunt)
	var jobs := Jobs.new()
	jobs.build_board(ship)
	jobs.assign(ship)
	check(jobs.board.has("mend:Rivet"), "the hurt Gauntling is on the board")
	eq(jobs.board["mend:Rivet"]["type"], "repair_crew", "as a repair_crew job")
	eq(jobs.board["mend:Rivet"]["priority"], 75, "at priority 75")
	check(gaunt.job.is_empty(), "nobody else aboard: they are not sent to the bed, and do not mend themselves")
	_jobs_run(ship, jobs, 3.0)
	near(gaunt.hp, 40.0, "and stay hurt")
	var player := _person("Soldier", "human", 16, 13, true)
	ship.crew.append(player)
	jobs.build_board(ship)
	near(float(jobs.hand_work(ship, player, 1.0) == "mend:Rivet"), 1.0, "the player mends by hand (E)")
	var rate := float(Jobs.jcfg()["repair_crew"]["rate"])  # data/crew.json: 4 hp a second
	near(gaunt.hp, 40.0 + rate, "the job's hp a second")
	ship.crew.erase(player)
	var ada := _person("Ada", "human", 11, 13)
	ship.crew.append(ada)
	var t := _seconds_until(ship, jobs, func(): return gaunt.hp >= gaunt.max_hp)
	check(t < 30.0, "a crewmate walks over and mends them (took %s s)" % t)
	near(gaunt.hp, gaunt.max_hp, "back to full")
	check(not jobs.board.has("mend:Rivet") or gaunt.hp >= gaunt.max_hp, "and the job is done")
	_done()


func test_a_downed_mechanical_crew_member_is_revived_first() -> void:
	var ship := Fixture.room_ship()
	var gaunt := _person("Rivet", "gauntling", 18, 13)
	gaunt.hurt(1000.0)
	ship.crew.append(gaunt)
	var jobs := Jobs.new()
	jobs.build_board(ship)
	check(jobs.board.has("revive:Rivet") and not jobs.board.has("mend:Rivet"), "down: a revive job, not a repair_crew one")
	_done()


func test_an_aura_adds_air_and_heals_the_room_it_stands_in() -> void:
	var ship := _two_rooms()
	var spore := _person("Spore", "sporeling", 12, 11, true)
	var hurt_here := _person("Pike", "human", 16, 11, true)
	var hurt_there := _person("Pell", "human", 12, 21, true)
	hurt_here.hp = 50.0
	hurt_there.hp = 50.0
	ship.crew.append_array([spore, hurt_here, hurt_there])
	Jobs.new().tick(ship, 1.0)
	near(hurt_here.hp, 51.0, "a Sporeling heals everyone in the room 1 hp a second")
	near(hurt_there.hp, 50.0, "but not the other room")
	near(spore.hp, 100.0, "(they are whole)")
	var air := {}
	for species in ["human", "sporeling"]:
		var s := Fixture.room_ship()
		var m := _person("Wren", species, 12, 11, true)
		s.crew.append(m)
		var room := s.atmosphere.room_at(m.cell())
		s.atmosphere.pressure[room] = 0.5
		var before: float = s.atmosphere.oxygen_of(room)
		var sim := ShipSim.new()
		sim.ships = [s]
		sim._step_ship(s, 1.0)
		air[species] = s.atmosphere.oxygen_of(room) - before
	near(air["sporeling"] - air["human"], 0.5, "a Sporeling's room gains 0.5 a second more air than a human's", 1e-9)
	spore.hurt(1000.0)
	near(float(TraitSet.room_auras(ship).size()), 0.0, "a downed Sporeling gives nothing")
	_done()


func test_an_aura_work_mult_speeds_up_the_others_only() -> void:
	_trait("t_pep", {"aura": {"work_mult": 1.5}})
	var ship := _two_rooms()
	var uid := Fixture.put(ship, "engine_mk1", 15, 10)
	ship.components.instances[uid]["status"] = "malfunction"
	var lead := _person("Lead", "human", 12, 11)
	lead.gear_traits = ["t_pep"]
	var mate := _person("Mate", "human", 16, 13)
	var away := _person("Away", "human", 12, 21)
	ship.crew.append_array([lead, mate, away])
	near(TraitSet.work_rate(ship, lead, "repair"), 1.0, "the bearer works at the normal speed")
	near(TraitSet.work_rate(ship, mate, "repair"), 1.5, "a crewmate in the room x1.5")
	near(TraitSet.work_rate(ship, away, "repair"), 1.0, "one in the other room x1")
	var jobs := Jobs.new()
	jobs.build_board(ship)
	jobs.work(ship, mate, jobs.board["fix:%d" % uid], 1.0)
	near(jobs.progress["fix:%d" % uid], 1.5, "a second of the mate's work is 1.5 seconds of repair")
	_done()


func test_a_prismatic_at_a_station_gives_it_a_point_of_power() -> void:
	var ship := Fixture.room_ship()
	var reactor := Fixture.put(ship, "reactor_mk1", 10, 9)  # +8
	var shield := Fixture.put(ship, "shield_mk1", 15, 9)  # -3
	var lasers := [Fixture.put(ship, "laser_mk1", 10, 13), Fixture.put(ship, "laser_mk1", 15, 13), Fixture.put(ship, "laser_mk1", 10, 15)]  # -2 each
	Fixture.wire(ship, [Vector2i(11, 9), Vector2i(11, 10), Vector2i(11, 11), Vector2i(11, 12), Vector2i(11, 13), Vector2i(11, 14), Vector2i(11, 15), Vector2i(11, 16),
		Vector2i(12, 10), Vector2i(13, 10), Vector2i(14, 10), Vector2i(15, 10), Vector2i(15, 11), Vector2i(15, 12), Vector2i(15, 13)])
	ship.refresh()
	var off := func() -> int:
		var n := 0
		for uid in ship.power_state["powered"]:
			n += 0 if ship.power_state["powered"][uid] else 1
		return n
	check(reactor >= 0 and shield >= 0 and not lasers.has(-1), "everything is placed")
	eq(ship.power_state["networks"].size(), 1, "one network")
	near(float(ship.power_state["networks"][0]["supply"]), 8.0, "8 in")
	near(float(ship.power_state["networks"][0]["demand"]), 9.0, "9 asked for")
	eq(off.call(), 1, "so one part is dark")
	var human := _person("Pike", "human", 15, 14)
	var prism := _person("Glint", "prismatic", 17, 14)
	ship.crew.append_array([human, prism])
	ship.manned[shield] = "Pike"
	ship.refresh()
	eq(off.call(), 1, "a human at the shield changes nothing")
	ship.manned[shield] = "Glint"
	check(ship.refresh(), "a Prismatic at the shield makes the ship solve its power again")
	near(float(ship.power_state["networks"][0]["demand"]), 8.0, "the shield asks for 2 instead of 3")
	eq(off.call(), 0, "and everything is powered")
	ship.manned.clear()
	ship.refresh()
	eq(off.call(), 1, "the bonus goes when they leave the post")
	prism.hurt(1000.0)
	ship.manned[shield] = "Glint"
	ship.refresh()
	eq(off.call(), 1, "and a downed Prismatic gives none")
	_done()


func test_power_solve_adds_the_bonus_to_a_part_figure() -> void:
	var ship := Fixture.room_ship()
	var reactor := Fixture.put(ship, "reactor_mk1", 10, 10)
	var shield := Fixture.put(ship, "shield_mk1", 15, 10)
	Fixture.wire(ship, [Vector2i(11, 11), Vector2i(12, 11), Vector2i(13, 11), Vector2i(14, 11), Vector2i(15, 11)])
	var Power = load("res://scripts/sim/power.gd")
	var plain: Dictionary = Power.solve(ship.components, ship.cables)
	near(float(plain["networks"][0]["demand"]), 3.0, "the shield asks for 3")
	var boosted: Dictionary = Power.solve(ship.components, ship.cables, {}, {"bonus": {shield: 1.0}})
	near(float(boosted["networks"][0]["demand"]), 2.0, "with a bonus of 1, for 2")
	var more: Dictionary = Power.solve(ship.components, ship.cables, {}, {"bonus": {reactor: 2.0}})
	near(float(more["networks"][0]["supply"]), 10.0, "a producer's figure goes up too")
	_done()


func test_melee_mult_and_ranged_mult_are_kept_for_the_on_foot_fights() -> void:
	near(TraitSet.of(CrewMember.new("G", Vector2.ZERO, "grundl"))["melee_mult"], 2.0, "a Grundl hits x2 in a brawl")
	near(TraitSet.of(CrewMember.new("P", Vector2.ZERO, "prismatic"))["melee_mult"], 0.5, "a Prismatic x0.5")
	_trait("t_marksman", {"ranged_mult": 1.5})
	var m := CrewMember.new("X")
	m.gear_traits = ["t_marksman"]
	near(TraitSet.of(m)["ranged_mult"], 1.5, "ranged_mult resolves")
	near(TraitSet.of(CrewMember.new("X"))["ranged_mult"], 1.0, "and defaults to 1")
	_done()


func test_swarm_works_faster_with_kin_in_the_room() -> void:
	var ship := _two_rooms()
	var uid := Fixture.put(ship, "engine_mk1", 15, 10)
	ship.components.instances[uid]["status"] = "malfunction"
	var a := _person("Tsk", "kett", 12, 11)
	ship.crew.append(a)
	near(TraitSet.work_rate(ship, a, "repair"), 1.0, "one Kett alone: no bonus")
	var b := _person("Ktik", "kett", 12, 14)
	ship.crew.append(b)
	near(TraitSet.work_rate(ship, a, "repair"), 1.25, "a pair: +25% each")
	var c := _person("Zzik", "kett", 17, 14)
	ship.crew.append(c)
	near(TraitSet.work_rate(ship, a, "repair"), 1.5, "a trio: +50%")
	near(TraitSet.work_rate(ship, c, "extinguish"), 1.5, "for every kind of work")
	for i in 3:
		ship.crew.append(_person("K%d" % i, "kett", 10 + 3 * i, 12))
	near(TraitSet.work_rate(ship, a, "repair"), 1.5, "and no more than +50% however many")
	var far := _person("Far", "kett", 12, 21)
	ship.crew.append(far)
	near(TraitSet.work_rate(ship, far, "repair"), 1.0, "Kett in another room do not count")
	var human := _person("Pike", "human", 17, 11)
	ship.crew.append(human)
	near(TraitSet.work_rate(ship, human, "repair"), 1.0, "a human beside the hive gets nothing")
	b.hurt(1000.0)
	c.hurt(1000.0)
	for m in ship.crew:
		if m.name.begins_with("K") and m.name.length() == 2:
			m.hurt(1000.0)
	near(TraitSet.work_rate(ship, a, "repair"), 1.0, "a downed Kett does not count")
	_done()


func test_a_kett_trio_repairs_faster_than_one_kett() -> void:
	var times := {}
	for n in [1, 3]:
		var ship := Fixture.room_ship()
		var uid := Fixture.put(ship, "engine_mk1", 15, 10)
		var inst: Dictionary = ship.components.instances[uid]
		inst["status"] = "malfunction"
		inst["hp"] = 1
		for i in n:
			var k := _person("Kett%d" % i, "kett", 13, 10 + 2 * i, i > 0)  # the others are only company: they hold no job
			ship.crew.append(k)
		times[n] = _seconds_until(ship, Jobs.new(), func(): return inst["status"] == "ok")
	var part := float(Jobs.jcfg()["repair_component"]["seconds"])
	near(times[1], part, "a lone Kett: the normal time", 0.15)
	near(times[3], part / 1.5, "with two more in the room: a third faster", 0.15)
	_done()


func test_dries_out_costs_hp_in_a_hot_room() -> void:
	var ship := _two_rooms()
	var engine := Fixture.put(ship, "engine_mk1", 15, 10)
	var mire := _person("Bloop", "mire", 11, 11, true)
	var human := _person("Pike", "human", 17, 14, true)
	var other := _person("Glub", "mire", 12, 21, true)  # the other room
	ship.crew.append_array([mire, human, other])
	var inst: Dictionary = ship.components.instances[engine]
	inst["heat"] = 50.0
	Jobs.new().tick(ship, 1.0)
	near(mire.hp, 100.0, "a part at 50: a Mire is fine")
	inst["heat"] = 60.0
	Jobs.new().tick(ship, 1.0)
	near(mire.hp, 100.0, "at 60 exactly: still fine (above 60 hurts)")
	inst["heat"] = 70.0
	Jobs.new().tick(ship, 1.0)
	near(mire.hp, 98.0, "at 70: 2 hp a second")
	near(human.hp, 100.0, "a human does not mind")
	near(other.hp, 100.0, "nor does a Mire in the other room")
	_done()


func test_the_room_heat_is_the_hottest_part_in_it() -> void:
	var ship := _two_rooms()
	var a := Fixture.put(ship, "engine_mk1", 15, 10)
	var b := Fixture.put(ship, "radiator", 10, 10)
	ship.components.instances[a]["heat"] = 40.0
	ship.components.instances[b]["heat"] = 75.0
	var Heat = load("res://scripts/sim/heat.gd")
	var heats: Dictionary = Heat.room_heat(ship)
	eq(heats.size(), 1, "only the room with parts")
	near(float(heats[ship.atmosphere.room_at(Vector2i(12, 12))]), 75.0, "the hottest of its parts")
	_done()


# --- the library as data ------------------------------------------------------------------------------

func test_the_old_place_for_traits_is_still_read() -> void:
	var bag := TraitSet.bag_of({"mult": {"no_air_damage": 0.0, "fire_damage": 0.5, "repair_time": 2.0, "heal_others": 0.25}})
	near(bag["damage_taken"]["no_air"], 0.0, "no_air_damage is damage_taken.no_air")
	near(bag["damage_taken"]["fire"], 0.5, "fire_damage is damage_taken.fire")
	near(bag["work_mult"]["repair"], 0.5, "repair_time 2 is a repair speed of 0.5")
	near(bag["work_mult"]["breach"], 0.5, "and a breach speed")
	near(bag["work_mult"]["heal_others"], 0.25, "heal_others is work_mult.heal_others")
	Content.root = LEGACY_ROOT
	TraitSet.reset()
	var lib := TraitSet.library()
	check(lib.has("old_hardy"), "a trait in the species.json table of a content root is in the library")
	var m := CrewMember.new("X")
	m.gear_traits = ["old_hardy"]
	near(TraitSet.of(m)["damage_taken"]["fire"], 0.5, "and resolves through its old `mult`")
	near(TraitSet.of(m)["work_mult"]["repair"], 0.5, "repair_time 2")
	_done()


func test_every_key_is_described_in_the_data_and_in_the_resolver() -> void:
	var doc: Dictionary = Content.read("res://data/traits.json")["_doc"]
	var src := FileAccess.get_file_as_string("res://scripts/crew/traits.gd")
	for k in TraitSet.KEYS:
		check(str(doc["keys"].get(k, "")) != "", "data/traits.json _doc.keys has a line for " + k)
		check(src.contains("## - `%s`" % k), "traits.gd has a ## doc line for " + k)
	for k in doc["keys"]:
		check(TraitSet.KEYS.has(k), "_doc.keys describes only real keys: " + k)
	_done()


func test_the_library_has_the_old_traits_and_the_packs_traits() -> void:
	for id in ["no_breath", "heat_resistant", "fast_repair", "suit"]:
		eq(Content.origin("traits", id), "core", id + " is core")
	for id in ["swarm", "firefighter", "dries_out", "aura_spores", "flammable", "mechanical", "half_lungs", "ion_prone", "tinkerer", "crystal_conduit", "crystal_body", "hauler", "clumsy"]:
		eq(Content.origin("traits", id), "races_1", id + " is the races_1 pack's")
	_done()


# --- the six races of races_1 -------------------------------------------------------------------------

func test_the_six_races_have_their_stats_traits_and_sidearms() -> void:
	for id in RACES:
		var want: Array = RACES[id]
		eq(Content.origin("species", id), "races_1", id + " comes from the pack")
		var m := CrewMember.new("X", Vector2.ZERO, id)
		near(m.max_hp, want[0], id + ": max hp")
		near(m.speed, CrewMember.BASE_SPEED * want[1], id + ": walk speed")
		eq(m.traits(), want[2], id + ": traits")
		eq(m.sidearm(), want[3], id + ": sidearm")
		eq(m.rig(), id, id + ": drawn with art/crew/%s/" % id)
	_done()


func test_the_six_races_can_be_spawned_in_a_ship_and_drawn() -> void:
	Art.root = Art.DEFAULT_ROOT
	Art.clear_cache()
	var ship := Fixture.room_ship()
	var names := {"kett": "Tsk", "mire": "Bloop", "sporeling": "Mallow", "gauntling": "Rivet", "prismatic": "Glint", "grundl": "Bulk"}
	ship.crew_plan = [{"name": "Soldier", "species": "human"}]
	for id in names:
		ship.crew_plan.append({"name": names[id], "species": id})
	var made := Jobs.spawn_crew(ship)
	eq(made.size(), 7, "all seven spawn")
	for m in ship.crew:
		var sheet = Art.crew(Art.crew_rig(m.rig()))
		check(sheet != null and Art.crew_rig(m.rig()) == m.rig(), "%s: the rig %s is drawn, not a fallback" % [m.species, m.rig()])
		var plan := PersonDrawer.plan(sheet, {"species": m.rig(), "item": m.sidearm(), "aim": 0.0})
		var item := {}
		for l in plan:
			if l["layer"] == "item":
				item = l
		check(not item.is_empty() and item["id"] == m.sidearm(), "%s: the %s is in hand" % [m.species, m.sidearm()])
		eq(plan.size(), 5, m.species + ": legs, torso, arms, item and head")
	var grundl = Art.crew("grundl")
	var human = Art.crew("human")
	check(grundl.frame.x > human.frame.x and grundl.frame.y > human.frame.y, "the Grundl is drawn on the large rig (%s against %s)" % [grundl.frame, human.frame])
	var body := CrewMember.new("Bulk", Pathfinder.centre_of(Vector2i(12, 12)), "grundl")
	eq(body.body_cells().size(), 4, "yet the Grundl's body is the normal 2x2")
	_done()


func test_the_race_name_pools_are_twelve_distinct_names_each() -> void:
	var pools: Dictionary = Content.names()["crew"]
	var seen := {}
	for n in CrewMember.config()["names"]:
		seen[n] = "crew.json"
	for species in pools:
		if not RACES.has(species):
			for n in pools[species]:
				seen[n] = species
	for species in RACES:
		var pool: Array = pools.get(species, [])
		eq(pool.size(), 12, species + ": twelve names")
		for n in pool:
			check(not seen.has(n), "%s: '%s' is also used by %s" % [species, n, seen.get(n)])
			seen[n] = species
	_done()


func test_recruits_come_from_the_race_pools_at_their_stations() -> void:
	var cfg := Campaign.config()
	var want := {"rusthold": ["kett", "gauntling"], "meridian": ["mire", "grundl"], "prism": ["sporeling", "prismatic"]}
	for st in want:
		for id in want[st]:
			check(float(cfg["stations"][st]["recruit"].get(id, 0.0)) > 0.0, "%s recruits %s" % [st, id])
	var ship := Ship.from_design("res://data/ships/starter_rustbucket.json")
	Jobs.spawn_crew(ship)
	var c := Campaign.new(1)
	for id in RACES:
		var pool: Array = Content.names()["crew"][id]
		check(pool.has(c.crew_name(id, ship)), id + ": a recruit is named from the pack's pool")
	_done()
