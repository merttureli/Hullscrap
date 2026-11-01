extends "res://tests/base_test.gd"
## The first two rare factions (docs/CONTENT.md section 18; data/packs/faction_barons, data/packs/faction_leviathans): their
## shipgen tables come from the packs, a rare faction is built far above the stage and rates 4-5 skulls, events name them
## ("gen:barons") and every fight in them has a way out, the Barons are 5% of the pirate encounters of Clan space and the
## Boneyard, the Leviathans have a rare region and a 1% roamer, `relic` parts are held to a quirk or a cost instead of the
## bands, and the Starwhale Fin's `self_repair` mends a part and its mount.

const Abilities = preload("res://scripts/sim/abilities.gd")
const Balance = preload("res://scripts/data/balance.gd")
const Campaign = preload("res://scripts/space/campaign.gd")
const Characters = preload("res://scripts/crew/characters.gd")
const Content = preload("res://scripts/data/content.gd")
const CrewAbilities = preload("res://scripts/crew/crew_abilities.gd")
const Events = preload("res://scripts/space/events.gd")
const Fixture = preload("res://tests/fixture_ship.gd")
const Jobs = preload("res://scripts/crew/jobs.gd")
const PartEffects = preload("res://scripts/sim/part_effects.gd")
const Regions = preload("res://scripts/space/regions.gd")
const Salvage = preload("res://scripts/space/salvage.gd")
const Ship = preload("res://scripts/ship/ship.gd")
const Shipgen = preload("res://scripts/space/shipgen.gd")
const Stats = preload("res://scripts/sim/stats.gd")
const Unlocks = preload("res://scripts/space/unlocks.gd")
const Wardens = preload("res://scripts/space/wardens.gd")

const STARTERS: Array[String] = ["res://data/ships/starter_rustbucket.json", "res://data/ships/starter_courier.json", "res://data/ships/starter_prism.json"]
const BARON_REGIONS: Array[String] = ["clan_space", "boneyard"]
const GILDED: Array[String] = ["gilded_lance", "baron_tithe_gun", "sovereign_turret"]


func near(got: float, want: float, msg: String, eps := 0.01) -> void:
	check(absf(got - want) <= eps, "%s: expected %s, got %s" % [msg, str(want), str(got)])


## A campaign in `region` at stage `stage`, `jumps` jumps in.
func _camp(region: String, stage: int, jumps: int, seed_value := 5) -> Campaign:
	var c := Campaign.new(seed_value)
	c.enter_region(region)
	c.stage = stage
	c.jumps = jumps
	return c


## The events of the packs `pack_ids` (in file order).
func _events_of(pack_ids: Array) -> Array:
	var out := []
	for e in Content.events():
		if pack_ids.has(Content.origin("events", str(e["id"]))):
			out.append(e)
	return out


## The `fight` values of an event: its outcomes' and their after_win effects'.
func _fights(ev: Dictionary) -> Array:
	var out := []
	for ch in ev.get("choices", []):
		for o in ch.get("outcomes", []):
			for eff in [o.get("effects", {}), o.get("after_win", {}).get("effects", {}), ev.get("after_win", {}).get("effects", {})]:
				if str(eff.get("fight", "")) != "":
					out.append(str(eff["fight"]))
	return out


## The share (0..1) of the weight of the events of `type` that can happen now in `region` whose id starts with `prefix`.
func _share(region: String, stage: int, jumps: int, type: String, prefix: String) -> float:
	var c := _camp(region, stage, jumps)
	var ship := Ship.from_design(STARTERS[0])
	Jobs.spawn_crew(ship)
	var node := {"id": "n3", "type": type, "place": ""}
	var total := 0.0
	var mine := 0.0
	for id in c.events.order:
		var ev: Dictionary = c.events.events[id]
		var w := float(ev.get("weight", 10.0))
		if str(ev.get("type", "")) != type or c.events.is_page(id) or w <= 0.0 or not c.events.eligible(ev, c, node, ship):
			continue
		total += w
		mine += w if id.begins_with(prefix) else 0.0
	return mine / maxf(total, 1.0)


func _list(v) -> Array:
	return v if v is Array else ([] if v == null else [v])


# --- the tables -------------------------------------------------------------------------------------

func test_the_packs_add_their_factions_to_the_enemy_tables() -> void:
	var core = JSON.parse_string(FileAccess.get_file_as_string("res://data/enemy_tables.json"))
	var fac_ids := {}
	for f in Content.list("factions"):
		fac_ids[f["id"]] = f
	for id in ["barons", "leviathans"]:
		check(Shipgen.tables()["factions"].has(id), id + " has a table")
		check(not core["factions"].has(id), id + " is in its pack, not in the core file")
		check(Shipgen.factions().has(id), id + " is a shipgen faction")
		check(fac_ids.has(id) and bool(fac_ids[id]["hostile"]), id + " is a hostile faction (no reputation bar)")
		check(not Campaign.rep_factions().has(id), id + " has no reputation bar")
	for p in ["faction_barons", "faction_leviathans"]:
		check(Content.packs().any(func(x): return x["id"] == p), p + " is a pack")
	eq(Content.errors(), [], "the packs load without a problem")


func test_a_rare_faction_is_built_far_above_the_stage() -> void:
	var tables: Dictionary = Shipgen.tables()["factions"]
	var order := ["small", "medium", "large"]
	for pair in [["barons", "clan_space", 1, "medium"], ["barons", "boneyard", 2, "medium"], ["leviathans", "leviathan_deep", 5, "large"]]:
		var faction: String = pair[0]
		var f: Dictionary = tables[faction]
		for jumps in [3, 14, 30]:
			for seed_value in range(1, 5):
				var c := _camp(pair[1], pair[2], jumps, seed_value)
				var spec := c.gen_spec("gen:" + faction, "pirate")
				var p := spec.trim_prefix("gen:").split(":")
				var budget := float(p[3]) / 100.0
				var stage_budget := maxf(Shipgen.budget_for(c.tier(), jumps, Shipgen.danger_of(c.region_data), "normal", c.stage), float(f["budget_floor"]))
				var where := "%s at jump %d (seed %d)" % [faction, jumps, seed_value]
				check(budget >= stage_budget * float(f["budget_mult"][0]) - 0.01 and budget <= stage_budget * float(f["budget_mult"][1]) + 0.01,
					"%s: budget %.1f is %s-%s times the stage's %.1f" % [where, budget, str(f["budget_mult"][0]), str(f["budget_mult"][1]), stage_budget])
				check(budget >= float(f["budget_floor"]) * float(f["budget_mult"][0]) - 0.01, "%s: never under the floor times the least factor" % where)
				check(order.find(p[1]) >= order.find(pair[3]), "%s: a %s hull is at least %s" % [where, p[1], pair[3]])
				var ship := Shipgen.from_spec(spec)
				check(ship != null and Shipgen.validate(ship).is_empty(), where + ": a valid ship")
	near(Shipgen.budget_floor("barons", "easy"), 0.8 * Shipgen.budget_floor("barons"), "the floor follows the difficulty", 0.001)
	near(Shipgen.budget_floor("rustfangs"), 0.0, "the others have no floor", 0.001)
	# the others are rolled as before: the stage's budget, and no random number spent on a factor
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var state := rng.state
	near(Shipgen.budget_mult("rustfangs", rng), 1.0, "a plain faction has no budget factor", 0.0001)
	eq(rng.state, state, "and asking for it rolls nothing")
	var c := _camp("clan_space", 1, 6)
	near(float(c.gen_spec("gen:rustfangs", "pirate").trim_prefix("gen:").split(":")[3]) / 100.0, Shipgen.budget_for(c.tier(), 6, 1.0, "normal", c.stage), "a Rustfang fight is the stage's budget")
	eq(Shipgen.at_least("rustfangs", "small"), "small", "no minimum hull for the others")
	eq(Shipgen.at_least("barons", "small"), "medium", "Barons are medium at least")
	eq(Shipgen.at_least("leviathans", "medium"), "large", "Leviathans are large")
	eq(Shipgen.at_least("leviathans", "large"), "large", "and nothing shrinks a bigger hull")


func test_the_rare_factions_wear_their_prizes() -> void:
	var gilded := {}
	var offered := {}
	var fins := 0
	var engines := 0
	var bone := 0
	for seed_value in range(1, 13):
		var baron := Shipgen.build("barons", "large", seed_value, 330.0)
		for uid in baron.components.instances:
			var id := str(baron.components.instances[uid]["id"])
			if GILDED.has(id) or id == "sovereign_aegis":
				gilded[id] = true
		for id in Salvage.parts(baron):
			offered[id] = true
		var whale := Shipgen.build("leviathans", "large", seed_value, 400.0)
		for uid in whale.components.instances:
			var id := str(whale.components.instances[uid]["id"])
			if str(whale.components.def(id).get("family", "")) == "engine":
				engines += 1
				fins += int(id == "starwhale_fin")
		for c in whale.grid.tiles:
			bone += int(whale.grid.tiles[c] == "bone_armour")
	for id in GILDED:
		check(gilded.has(id), "the Barons carry the " + id)
		check(offered.has(id), "and a won fight can offer it")
	check(engines >= 12 and fins == engines, "every Leviathan engine is a Starwhale Fin (%d of %d)" % [fins, engines])
	check(bone > 100, "Leviathans are plated in Bone Armour (%d cells)" % bone)


# --- fights named by events -------------------------------------------------------------------------

func test_an_event_can_name_a_faction_to_fight() -> void:
	var c := _camp("clan_space", 1, 6)
	var path := c.fight_path("gen:barons", "pirate")
	check(Shipgen.is_spec(path) and path.split(":").size() >= 4, "a faction in, a full spec out: " + path)
	eq(path.split(":")[1], "barons", "of that faction")
	eq(c.fight_path("gen:barons", "pirate"), path, "the same ship every time it is asked (the event panel rates the one that attacks)")
	eq(c.fight_path("gen:leviathans", "pirate").split(":")[1], "leviathans", "another faction, another ship")
	check(c.fight_path("gen:rustfangs:ram", "pirate").ends_with(":ram"), "a :ram entry keeps its ram")
	eq(c.fight_path(path, "pirate"), path, "a full spec is handed on as it is")
	eq(c.fight_path("tier", "pirate"), c.foe_for(c.current, "pirate"), "tier still rolls the node's table")
	for ok in ["gen:barons", "gen:leviathans", "gen:rustfangs:ram"]:
		check(Events._is_foe(ok), ok + " is a fight an event may name")
	for bad in ["gen:", "gen:nobody", "gen:barons:medium", "barons", "tier", "gen:barons:ram:x"]:
		check(not Events._is_foe(bad), bad + " is not")
	eq(Events.shared().validate(), [], "every event of the game passes the validator")


func test_a_rare_fight_rates_four_or_five_skulls() -> void:
	var players := []
	for st in STARTERS:
		players.append(Ship.from_design(st))
	for pair in [["barons", "clan_space", 1, 0.5], ["barons", "boneyard", 2, 0.5], ["leviathans", "leviathan_deep", 5, 0.85]]:
		var fives := 0
		var n := 0
		for jumps in [3, 15, 25]:
			for seed_value in range(1, 5):
				var c := _camp(pair[1], pair[2], jumps, seed_value)
				var foe := Shipgen.from_spec(c.fight_path("gen:" + str(pair[0]), "pirate"))
				for p in players:
					var skulls := int(Shipgen.threat(foe, p)["skulls"])
					check(skulls >= 4, "%s at jump %d (seed %d) rates %d against a starter" % [pair[0], jumps, seed_value, skulls])
					fives += int(skulls == 5)
					n += 1
		check(float(fives) / n >= float(pair[3]), "%s in %s: %d of %d ratings are 5 skulls (at least %d%%)" % [pair[0], pair[1], fives, n, int(100.0 * float(pair[3]))])


func test_every_fight_in_a_rare_event_has_a_free_way_out() -> void:
	var seen := 0
	for ev in _events_of(["faction_barons", "faction_leviathans"]):
		var fights := _fights(ev)
		for f in fights:
			check(f == "gen:barons" or f == "gen:leviathans", "%s: its fight names its faction (%s)" % [ev["id"], f])
		if fights.is_empty():
			continue
		seen += 1
		var out := false
		for ch in ev["choices"]:
			var free: bool = not ch.has("requires") and not ch.get("outcomes", []).is_empty()
			for o in ch.get("outcomes", []):
				free = free and o.get("effects", {}).is_empty()
			out = out or free
		check(out, "%s: a choice with no price and no effects lets you leave" % ev["id"])
	check(seen >= 8, "%d events with a fight were checked" % seen)


# --- the Barons ------------------------------------------------------------------------------------

func test_the_barons_are_about_five_percent_of_the_pirate_encounters_of_clan_space_and_the_boneyard() -> void:
	for pair in [["clan_space", 1], ["boneyard", 2]]:
		for jumps in [4, 8, 20]:
			var s := _share(pair[0], pair[1], jumps, "pirate", "baron_")
			check(s >= 0.03 and s <= 0.08, "%s at jump %d: the Barons are %.1f%% of the pirate events" % [pair[0], jumps, 100.0 * s])
	var ids := _events_of(["faction_barons"]).map(func(e): return e["id"])
	eq(ids.size(), 6, "six events: " + str(ids))
	for id in ["baron_toll", "baron_duel", "baron_gilded_wreck", "baron_recruit", "baron_feast", "baron_bounty"]:
		check(ids.has(id), id + " exists")
	for ev in _events_of(["faction_barons"]):
		var r = ev["requires"]["region"]
		check(r is Array and r.size() == 2 and r.has("clan_space") and r.has("boneyard"), "%s only happens in Clan space and the Boneyard" % ev["id"])
	for r in Regions.all():
		if BARON_REGIONS.has(str(r["id"])):
			continue
		for type in ["pirate", "wreck_field", "distress", "trader"]:
			check(_share(str(r["id"]), int(r["stages"][0]), 20, type, "baron_") == 0.0, "%s (%s): no Baron event" % [r["id"], type])


func test_the_baron_crew_and_the_yacht_unlock() -> void:
	for id in ["pomfrey", "sterling"]:
		var c := Characters.entry(id)
		check(not c.is_empty() and str(c["species"]) == "human", id + " is a human character")
		eq(Content.origin("characters", id), "faction_barons", id + " is in the Barons pack")
	eq(CrewAbilities.problems(), [], "the ability vocabulary and every character pass")
	var u := Unlocks.entry("ship_barons_yacht")
	check(not u.is_empty() and bool(u.get("pending", false)), "the Baron's Yacht is a pending starter")
	eq(Unlocks.validate(), [], "the unlock catalogue passes")
	var duel: Dictionary = Events.shared().get_event("baron_duel")
	var after: Dictionary = duel["choices"][0]["outcomes"][0]["after_win"]["effects"]
	check(_list(after.get("unlock")).has("ship_barons_yacht"), "winning the duel earns the yacht")
	eq(after["recruit"], {"character": "sterling"}, "and Sterling")
	var wreck: Dictionary = Events.shared().get_event("baron_gilded_wreck")
	var prizes := {}
	for o in wreck["choices"][0]["outcomes"]:
		for id in o["effects"].get("items", {}):
			prizes[id] = true
	for id in GILDED:
		check(prizes.has(id), "the gilded wreck can hold the " + id)


func test_the_gilded_parts_and_the_aegis_are_found_not_built() -> void:
	var table := Balance.load_table()
	var lines := Stats.load_lines()
	for id in GILDED + ["sovereign_aegis"]:
		var d := Content.entry("components", id)
		check(bool(d.get("unique", false)) and str(d.get("quirk", "")) != "", id + " is unique and has a quirk")
		check(not Content.has("recipes", id), id + " has no recipe")
		check(Content.has("weapons", id) == (str(d["family"]) == "weapon"), id + " has weapon stats if it is a weapon")
	eq(Balance.check(table, Content.entry("components", "sovereign_aegis"), lines)["status"], "relic", "the Aegis is a relic")


# --- the Leviathans ---------------------------------------------------------------------------------

func test_the_leviathans_have_a_rare_region_a_warden_and_a_roamer() -> void:
	var r := Regions.get_region("leviathan_deep")
	eq([r["stages"], r["rarity"], r["faction"], r["enemies"], r["home_species"]], [[4.0, 8.0], "rare", "leviathans", "leviathans", ""], "the region")
	check(float(r["weight"]) <= 5.0, "with a low weight")
	eq(Regions.problems(), [], "and passes the region rules")
	var cfg := Campaign.config()
	var seen_at := {}
	for seed_value in range(1, 301):
		for stage in range(1, 8):
			if Regions.offers(seed_value, stage, ["clan_space"], cfg).has("leviathan_deep"):
				seen_at[stage + 1] = int(seen_at.get(stage + 1, 0)) + 1
	for s in [4, 5, 6, 7, 8]:
		check(int(seen_at.get(s, 0)) > 0, "it is offered for stage %d now and then" % s)
	for s in [2, 3]:
		check(not seen_at.has(s), "never before stage 4")
	check(int(seen_at.get(5, 0)) < 60, "and rarely (%d of 300 offers at stage 5)" % int(seen_at.get(5, 0)))
	var w := Wardens.for_region(3, 5, r, 20)
	eq(w["faction"], "leviathans", "its exit warden is a Leviathan")
	check(Shipgen.from_spec(w["spec"]) != null, "and builds")
	eq(Wardens.problems(), [], "wardens.json passes")
	var roam: Dictionary = Events.shared().get_event("leviathan_surfaces")
	check(not roam.is_empty() and not roam["requires"].has("region"), "the roamer is not tied to a region")
	for pair in [["concord_space", 4], ["lumen_space", 6], ["boneyard", 4]]:
		var s := _share(pair[0], pair[1], 20, "empty", "leviathan_surfaces")
		check(s >= 0.005 and s <= 0.02, "%s: the roamer is %.2f%% of the empty-space events" % [pair[0], 100.0 * s])
	near(_share("concord_space", 3, 20, "empty", "leviathan_surfaces"), 0.0, "not before stage 4", 0.0001)
	check(_share("leviathan_deep", 5, 20, "anomaly", "leviathan_deep_") > 0.1, "in the deep its own events are common")
	eq(_events_of(["faction_leviathans"]).size(), 7, "six events and the roamer")


func test_the_leviathan_quest_gives_the_fin() -> void:
	var c := _camp("leviathan_deep", 5, 20)
	var ship := Ship.from_design(STARTERS[0])
	Jobs.spawn_crew(ship)
	ship.inventory.add("scrap", 30)
	var calf: Dictionary = c.events.get_event("leviathan_deep_calf")
	var mother: Dictionary = c.events.get_event("leviathan_deep_mother")
	var distress := {"id": "n5", "type": "distress", "place": ""}
	var anomaly := {"id": "n6", "type": "anomaly", "place": ""}
	check(not c.events.eligible(mother, c, anomaly, ship), "the mother does not come before the calf is freed")
	var r := c.events.choose(calf, 0, c, ship, distress)
	check(r["ok"] and c.flags.has("leviathan_calf_freed"), "the calf is freed")
	check(c.events.eligible(mother, c, anomaly, ship), "and then the mother comes")
	r = c.events.choose(mother, 0, c, ship, anomaly)
	check(r["ok"] and ship.inventory.count("starwhale_fin") == 1 and ship.inventory.count("leviathan_bone") >= 4, "the Fin and bone are the thanks")
	var hunted := _camp("leviathan_deep", 5, 20)
	hunted.flags["leviathan_calf_freed"] = true
	hunted.flags["leviathan_calf_hunted"] = true
	check(not hunted.events.eligible(mother, hunted, anomaly, ship), "a calf that was hunted has no mother to thank you")


# --- relics -----------------------------------------------------------------------------------------

func test_a_relic_is_held_to_a_quirk_or_a_cost_not_to_the_bands() -> void:
	var table := {"tolerance": 0.2, "bands": {"engine": {"1": {"thrust": 10, "power": -2, "hp": 6}}}, "waivers": {}}
	var lines := Stats.load_lines()
	var engine := {"id": "r", "family": "engine", "line": "standard", "tier": 1, "power": -2, "hp": 6, "stats": {"thrust": 10}}
	var with := func(over: Dictionary) -> Dictionary:
		var d: Dictionary = engine.duplicate(true)
		d.merge(over, true)
		return d
	eq(Balance.check(table, engine, lines)["status"], "ok", "a plain part on the band is ok")
	eq(Balance.check(table, with.call({"stats": {"thrust": 30}}), lines)["status"], "fail", "a plain part far off the band fails")
	eq(Balance.check(table, with.call({"stats": {"thrust": 30}, "relic": true, "quirk": "grows back"}), lines)["status"], "relic", "a relic with a quirk may leave the bands")
	eq(Balance.check(table, with.call({"stats": {"thrust": 30}, "relic": true, "cost": "eats fuel"}), lines)["status"], "relic", "so may one with a cost text")
	eq(Balance.check(table, with.call({"stats": {"thrust": 30}, "relic": true, "cost": {"fuel": 1}}), lines)["status"], "relic", "or a cost object")
	var bare: Dictionary = Balance.check(table, with.call({"stats": {"thrust": 30}, "relic": true}), lines)
	eq(bare["status"], "fail", "a relic with neither fails")
	check(str(bare["problems"][0]).contains("quirk or a cost"), "and says what it lacks: " + str(bare["problems"]))
	eq(Balance.check(table, with.call({"stats": {"thrust": 10}, "relic": true}), lines)["status"], "fail", "even on the band")
	eq(Balance.check(table, with.call({"relic": true, "cost": "", "quirk": "  "}), lines)["status"], "fail", "an empty cost and a blank quirk are neither")
	eq(Balance.check(table, with.call({"family": "shield", "relic": true, "quirk": "x"}), lines)["status"], "relic", "a family without bands still counts the relic")
	eq(Balance.check(table, with.call({"relic": true, "unique": true, "quirk": "x", "stats": {"thrust": 40}}), lines)["status"], "relic", "relic wins over unique")
	eq(Balance.check(table, with.call({"relic": false, "stats": {"thrust": 30}}), lines)["status"], "fail", "relic false is not a relic")
	var real := Balance.load_table()
	var relics := 0
	for c in Content.list("components"):
		if bool(c.get("relic", false)):
			relics += 1
			eq(Balance.check(real, c, lines)["status"], "relic", "%s is an excused relic" % c["id"])
	check(relics >= 2, "the data holds %d relic parts" % relics)
	var tile := Content.entry("tiles", "bone_armour")
	check(bool(tile.get("relic", false)) and not tile["cost"].is_empty(), "Bone Armour is a relic tile that costs Leviathan Bone")
	check(Content.has("materials", "leviathan_bone"), "and the bone is a material")


func test_the_starwhale_fin_heals_itself_and_its_mount() -> void:
	var fin := Content.entry("components", "starwhale_fin")
	eq(PartEffects.problems(fin["abilities"][0]), [], "the Fin's ability passes the validator")
	check(PartEffects.SIDE_EFFECTS.has("self_repair"), "self_repair is a side effect")
	check(not PartEffects.problems({"id": "x", "type": "passive", "effects": {}, "side_effects": [{"type": "self_repair", "rate": -1}]}).is_empty(), "and a negative rate is refused")
	var ship := Fixture.room_ship()
	var reactor := Fixture.put(ship, "reactor_mk1", 10, 10)
	var part := Fixture.put(ship, "starwhale_fin", 15, 10, 2)
	var plain := Fixture.put(ship, "engine_mk1", 15, 14, 2)
	check(reactor >= 0 and part >= 0 and plain >= 0, "the parts fit the test room")
	ship.refresh()
	var inst: Dictionary = ship.components.instances[part]
	var other: Dictionary = ship.components.instances[plain]
	var top := float(ship.effective("starwhale_fin")["hp"])
	near(top, 12.0, "the Fin has 12 hp", 0.001)
	inst["hp"] = 4.0
	other["hp"] = 2.0
	Abilities.tick(ship, 4.0)
	near(float(inst["hp"]), 6.0, "0.5 hp a second: 2 hp in 4 s", 0.001)
	near(float(other["hp"]), 2.0, "a plain engine does not heal", 0.001)
	Abilities.tick(ship, 100.0)
	near(float(inst["hp"]), top, "and it stops at its full hp", 0.001)
	# it needs neither power nor a working part: knocked out, it comes back by itself
	inst["hp"] = 0.0
	inst["status"] = "disabled"
	ship.cables.cells.clear()
	ship.mark_dirty()
	ship.refresh()
	check(not ship.power_state["powered"].get(part, false), "unpowered")
	Abilities.tick(ship, 1.0)
	near(float(inst["hp"]), 0.5, "it still grows", 0.001)
	eq(inst["status"], "ok", "and a disabled Fin is ok again once it has hp")
	# the outside half of its mount grows back too
	inst["out_cells"] = [Vector2i(1, 1)]
	inst["out_hp"] = 0.0
	Abilities.tick(ship, 4.0)
	near(float(inst["out_hp"]), 2.0, "the outside half mends at the same rate", 0.001)
	Abilities.tick(ship, 100.0)
	near(float(inst["out_hp"]), float(ship.components.outside_hp_max("starwhale_fin")), "up to its mount's hp", 0.001)
	eq(ship.components.outside_hp_max("starwhale_fin"), 9, "which is 9")
	other["out_cells"] = []
	Abilities.tick(ship, 5.0)
	near(float(other["hp"]), 2.0, "still no healing for a plain engine", 0.001)
