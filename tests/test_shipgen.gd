extends "res://tests/base_test.gd"
## Procedural enemy ships (scripts/space/shipgen.gd, hullgen.gd, threat.gd; data/enemy_tables.json): a 500 seed sweep over
## every faction and size class (power, sealed rooms, crew paths, mounts by the real rules, flight, a silhouette that is no
## box, the same ship for the same seed), the tables name real things, the budget and the threat rating behave, the campaign
## and the combat session build the ships, and a generated ship fights.

const Structure = preload("res://scripts/ship/structure.gd")
const StructureUtil = preload("res://tests/structure_util.gd")
const Shipgen = preload("res://scripts/space/shipgen.gd")
const Threat = preload("res://scripts/space/threat.gd")
const Hullgen = preload("res://scripts/space/hullgen.gd")
const Ship = preload("res://scripts/ship/ship.gd")
const Arena = preload("res://scripts/combat/arena.gd")
const Mounts = preload("res://scripts/ship/mounts.gd")
const Session = preload("res://scripts/combat/combat_session.gd")
const PilotAI = preload("res://scripts/combat/pilot_ai.gd")
const Campaign = preload("res://scripts/space/campaign.gd")
const Content = preload("res://scripts/data/content.gd")
const Regions = preload("res://scripts/space/regions.gd")
const HullOutline = preload("res://scripts/ship/hull_outline.gd")
const Shapes = preload("res://scripts/ship/shapes.gd")
const Components = preload("res://scripts/ship/components.gd")

const SIZES: Array[String] = ["small", "medium", "large"]
const BUDGETS: Array[float] = [30.0, 45.0, 60.0, 90.0, 130.0, 200.0, 320.0, 520.0]  ## from a jump 0 pirate to a jump 35 ship of the Hollow
const SWEEP := 500
const MAX_FILL := 0.85  ## the solid area of a hull over its bounding box, at most (docs/CONTENT.md 4c)
const MIN_SHAPED := 4  ## cells that are slopes or curves
const FIRST_TRY := 0.9  ## the share of ships the first roll must give, so the retries do not hide a bad generator


func _helm_of(ship: Ship) -> int:
	for uid in ship.components.instances:
		if ship.components.def(ship.components.instances[uid]["id"]).get("family", "") == "helm":
			return uid
	return -1


## Everything a valid enemy ship has, asked independently of Shipgen.validate(). Returns the problems.
func _problems(ship: Ship) -> Array:
	var bad: Array = []
	var g = ship.grid
	var comps = ship.components
	for uid in comps.instances:
		if not ship.power_state["powered"].get(uid, false):
			bad.append("%s is not powered" % comps.instances[uid]["id"])
	for n in ship.power_state["networks"]:
		if float(n["supply"]) + 0.0001 < float(n["demand"]):
			bad.append("supply %s under demand %s" % [str(n["supply"]), str(n["demand"])])
	if ship.atmosphere.rooms.size() < 2:
		bad.append("fewer than two rooms")
	for r in ship.atmosphere.rooms:
		if not r["sealed"]:
			bad.append("room %d is open to space" % r["id"])
	var lost := HullOutline.pockets(ship)
	if not lost.is_empty():
		bad.append("%d floor cells no crew body reaches from the helm" % lost.size())
	for d in ship.atmosphere.doors:
		if g.door_piece(d["cell"]).size() != 2:
			bad.append("the door at %s is not 2 cells wide" % str(d["cell"]))
	var arena := Arena.new(1)
	arena.add_ship(ship)
	var co = arena.ships[0]
	if co.flight.can_fly(comps, co.powered) != "":
		bad.append("cannot fly: " + co.flight.can_fly(comps, co.powered))
	var guns := 0
	var rear := 0
	var uids: Array = comps.instances.keys()
	uids.sort()
	for uid in uids:
		var inst: Dictionary = comps.instances[uid].duplicate(true)
		var def: Dictionary = comps.def(inst["id"])
		if not Mounts.is_mount(def):
			continue
		var name := "%s at %s" % [inst["id"], str(inst["anchor"])]
		if not (comps.has_outside(uid) and comps.link_intact(g, uid)):
			bad.append(name + " has no whole mount")
			continue
		for c in inst["link"]:
			if not Mounts.flat_wall(g, c):
				bad.append("%s: the link cell %s is not a flat wall" % [name, str(c)])
		for c in inst["out_cells"]:
			if g.get_tile(c) != "":
				bad.append("%s: the outside cell %s is not open space" % [name, str(c)])
		for c in inst["cells"]:
			if g.get_tile(c) != "floor":
				bad.append("%s: the inside cell %s is not floor" % [name, str(c)])
		# the real placement rules, asked again with the part lifted out: they put it back exactly where it is
		comps.remove_uid(uid)
		var plan: Dictionary = comps.plan_mount(g, inst["id"], inst["out_anchor"], inst["rot"])
		if plan["why"] != "" or plan["anchor"] != inst["anchor"] or plan["link"] != inst["link"]:
			bad.append("%s: the mount rules say '%s'" % [name, plan["why"]])
		var out := Mounts.outward(inst["rot"])
		if str(def["family"]) == "weapon":
			guns += 1
		else:
			rear += int(out == Vector2i.DOWN)
			if out == Vector2i.UP:
				bad.append(name + ": an engine pushes backwards")
	if guns == 0:
		bad.append("no weapon")
	if rear == 0:
		bad.append("no engine on the stern")
	var lo := Vector2i(1 << 20, 1 << 20)
	var hi := Vector2i(-(1 << 20), -(1 << 20))
	var area := 0.0
	for c in g.tiles:
		lo = lo.min(c)
		hi = hi.max(c)
		area += g.area_at(c)
	var box := float((hi.x - lo.x + 1) * (hi.y - lo.y + 1))
	if area >= (float(Shipgen.tables()["factions"][str(ship.get_meta("shipgen", {}).get("faction", ""))]["hull"].get("max_fill", MAX_FILL - 0.01)) + 0.01 if ship.has_meta("shipgen") else MAX_FILL) * box:
		bad.append("its solid cells fill %.0f%% of their bounding box" % (100.0 * area / box))
	if g.shapes.size() < MIN_SHAPED:
		bad.append("only %d shaped cells" % g.shapes.size())
	for c in g.shapes:
		if not Shapes.has_shape(str(g.shapes[c]["shape"])) or not g.tile_flag(g.get_tile(c), "solid"):
			bad.append("the shaped cell %s is not a wall of a known shape" % str(c))
	return bad


# --- the sweep -------------------------------------------------------------------------------------

func test_the_sweep_of_500_seeds_gives_valid_deterministic_ships() -> void:
	var factions := Shipgen.factions()
	var first_try := 0
	var seen := {}
	for i in SWEEP:
		var faction: String = factions[i % factions.size()]
		var size: String = SIZES[(i / factions.size()) % SIZES.size()]
		var budget: float = BUDGETS[(i * 7 + i / 3) % BUDGETS.size()]
		var name := "%s %s seed %d budget %.0f" % [faction, size, i, budget]
		var ship := Shipgen.build(faction, size, i, budget)
		check(ship != null, name + ": a ship")
		if ship == null:
			continue
		var meta: Dictionary = ship.get_meta("shipgen")
		first_try += int(meta["attempts"] == 1)
		check(float(meta["spent"]) <= budget + 1e-6, "%s: spent %.1f of it" % [name, float(meta["spent"])])
		seen["%s/%s" % [faction, size]] = true
		var bad := _problems(ship)
		eq(bad, [], name)
		if i % 5 == 0:  # the same arguments make the same ship, cell for cell, part for part, name and crew too
			var one := Shipgen.build(faction, size, i, budget)
			var two := Shipgen.build(faction, size, i, budget)
			eq(JSON.stringify(one.to_dict()), JSON.stringify(two.to_dict()), name + ": deterministic")
			eq([one.name, one.crew_plan, one.get_meta("ai"), one.get_meta("shipgen")], [two.name, two.crew_plan, two.get_meta("ai"), two.get_meta("shipgen")], name + ": the same name, crew, pilot and loadout")
	eq(seen.size(), factions.size() * SIZES.size(), "every faction in every size class was built")
	check(float(first_try) >= FIRST_TRY * SWEEP, "the first roll gives a ship for %d of %d seeds (at least %.0f%%)" % [first_try, SWEEP, 100.0 * FIRST_TRY])


func test_another_seed_makes_another_ship() -> void:
	for faction in Shipgen.factions():
		var seen := {}
		for i in 5:
			seen[JSON.stringify(Shipgen.build(faction, "medium", 100 + i, 120.0).to_dict()["tiles"])] = true
		check(seen.size() >= 4, "%s: five seeds give %d different hulls" % [faction, seen.size()])


# --- the factions look like themselves ---------------------------------------------------------------

func _cells_of(ship: Ship) -> Array:
	var out: Array = ship.grid.tiles.keys()
	return out


func test_the_hulls_follow_the_faction_grammar() -> void:
	var sym_ok := 0
	var asym := 0
	var arcs := 0
	var facets_ok := true
	var ram_plated := 0
	for i in 12:
		var concord := Shipgen.build("concord", "medium", 300 + i, 150.0)
		var cells := _cells_of(concord)
		var lo := Vector2i(1 << 20, 1 << 20)
		var hi := Vector2i(-(1 << 20), -(1 << 20))
		for c in cells:
			lo = lo.min(c)
			hi = hi.max(c)
		var mirrored := true
		for c in cells:
			mirrored = mirrored and concord.grid.tiles.has(Vector2i(lo.x + hi.x - c.x, c.y))
		sym_ok += int(mirrored)
		for faction in ["lumen", "wardens"]:
			var ship := Shipgen.build(faction, "medium", 300 + i, 150.0)
			for c in ship.grid.shapes:
				facets_ok = facets_ok and str(ship.grid.shapes[c]["shape"]) == "tri"
		var hollow := Shipgen.build("hollow", "medium", 300 + i, 150.0)
		var hc := _cells_of(hollow)
		var hlo := Vector2i(1 << 20, 1 << 20)
		var hhi := Vector2i(-(1 << 20), -(1 << 20))
		for c in hc:
			hlo = hlo.min(c)
			hhi = hhi.max(c)
		var same := true
		for c in hc:
			same = same and hollow.grid.tiles.has(Vector2i(hlo.x + hhi.x - c.x, c.y))
		asym += int(not same)
		for c in hollow.grid.shapes:
			arcs += int(str(hollow.grid.shapes[c]["shape"]).begins_with("round2"))
		var ram := Shipgen.build("rustfangs", "medium", 300 + i, 100.0, {"ram": true})
		ram_plated += int(ram.grid.tiles.values().has("ram_plating") and ram.get_meta("ai")["style"] == "rammer")
	eq(sym_ok, 12, "a Concord hull is the same on both sides")
	check(facets_ok, "a Lumen or Warden hull has 45 degree facets and nothing else")
	check(asym >= 9, "a Hollow hull is lopsided (%d of 12)" % asym)
	check(arcs > 0, "and has curves")
	eq(ram_plated, 12, "a Rustfang rammer has a ram plated bow and the rammer style")


func test_a_ram_bow_is_a_v_of_slopes_with_a_gun_in_its_tip() -> void:
	for size in SIZES:
		var ship := Shipgen.build("rustfangs", size, 5, 90.0, {"ram": true})
		var g = ship.grid
		var top := 1 << 20
		for c in g.tiles:
			top = mini(top, c.y)
		var slopes := 0
		for c in g.shapes:
			slopes += int(c.y < top + 6 and g.get_tile(c) == "ram_plating")
		check(slopes >= 4, "%s: the ram bow is made of slopes (%d)" % [size, slopes])
		var bow_guns := 0
		for uid in ship.components.instances:
			var inst: Dictionary = ship.components.instances[uid]
			bow_guns += int(ship.components.def(inst["id"])["family"] == "weapon" and inst["rot"] == 0)
		eq(bow_guns, 1, size + ": one gun on the tip of the V")


# --- the tables --------------------------------------------------------------------------------------

func test_the_tables_name_real_things() -> void:
	var t := Shipgen.tables()
	var comps := Components.new()
	comps.load_defs(Ship.COMPONENTS_PATH)
	var weapons = Content.read("res://data/weapons.json")["weapons"]  # with the packs' weapons (the rare factions use some)
	var tiles := Content.ids("tiles")
	var fac_ids: Array = []
	for f in Content.list("factions"):
		fac_ids.append(f["id"])
	for fid in t["factions"]:
		var f: Dictionary = t["factions"][fid]
		check(fac_ids.has(fid) or f.has("race"), fid + " is a faction of factions.json (or a race style)")
		for sp in f["crew"]["species"]:
			check(Content.has("species", str(sp)), "%s: the crew species %s exists" % [fid, sp])
		for tile in f["armour"]["tiles"]:
			check(tiles.has(tile), "%s: the tile %s exists" % [fid, tile])
		if f["armour"].has("ram"):
			check(tiles.has(f["armour"]["ram"]), "%s: the ram tile exists" % fid)
		if str(f.get("name_pool", "")) != "":
			check(Content.names().has(f["name_pool"]), "%s: the name pool %s exists" % [fid, f["name_pool"]])
		else:
			check(f.get("ship_names") is Array and not f["ship_names"].is_empty(), fid + " names its ships")
		for kind in f["parts"]["base"]:
			check(comps.has(f["parts"]["base"][kind]), "%s: the base %s exists" % [fid, kind])
		for cat in ["weapons", "shields", "engines", "reactors", "systems"]:
			check(not f["parts"][cat].is_empty(), "%s buys %s" % [fid, cat])
			for m in f["parts"][cat]:
				check(comps.has(str(m["id"])), "%s: %s exists" % [fid, m["id"]])
				check(float(m["cost"]) > 0.0, "%s: %s has a cost" % [fid, m["id"]])
				for need in m.get("needs", {}):
					check(comps.has(str(need)), "%s: %s needs %s, which exists" % [fid, m["id"], need])
				if cat == "weapons":
					check(weapons.has(m["id"]), "%s: %s has weapon stats" % [fid, m["id"]])
					check(Mounts.is_mount(comps.def(m["id"])), "%s: %s is a hull mount" % [fid, m["id"]])
				if cat == "engines":
					check(Mounts.is_mount(comps.def(m["id"])), "%s: %s is a hull mount" % [fid, m["id"]])
		for size in SIZES:
			check(f["layer_cost"].has(size), "%s: a layer costs something on a %s ship" % [fid, size])
		for kind in ["gun", "bridge", "core", "aux", "engine"]:
			check(f["hull"]["band"].has(kind), "%s: the grammar widens the %s deck" % [fid, kind])
	for r in Regions.all():
		for kind in ["pirate", "patrol"]:
			check(t["factions"].has(Shipgen.faction_for(r, kind)), "region %s: a %s fight has a faction with a table" % [r["id"], kind])
	for sid in t["sizes"]:
		check(Shipgen.tables()["sizes"][sid]["max"]["reactor"] >= 1, sid + " holds a reactor")
	eq(t["threat"]["cuts"].size(), 4, "four cuts make five skulls")


func test_the_cheapest_ship_of_every_faction_is_powered() -> void:
	for fid in Shipgen.factions():
		for size in SIZES:
			var ship := Shipgen.build(fid, size, 1, 1.0)
			check(ship != null and Shipgen.validate(ship).is_empty(), "%s %s with nothing to spend is a ship" % [fid, size])


func test_generated_ships_carry_a_morale_style_a_pilot_and_a_crew() -> void:
	var styles: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/morale.json"))["styles"]
	for faction in Shipgen.factions():
		for size in SIZES:
			var ship := Shipgen.build(faction, size, 21, 200.0)
			var ai: Dictionary = ship.get_meta("ai")
			check(styles.has(ai["morale"]), "%s %s: the morale style %s exists" % [faction, size, ai["morale"]])
			check(float(ai["aim_skill"]) >= 0.0 and float(ai["aim_skill"]) <= 1.0, "%s: a pilot's aim skill" % faction)
			eq(ship.crew_plan.size(), int(ship.get_meta("shipgen")["crew"]), "%s %s: the crew the budget bought" % [faction, size])
			var names := {}
			for e in ship.crew_plan:
				names[e["name"]] = true
				check(Content.has("species", str(e["species"])), "%s: the crew species %s exists" % [faction, e["species"]])
			eq(names.size(), ship.crew_plan.size(), "%s %s: no two crew share a name" % [faction, size])
			check(ship.name != "" and ship.name != "Ship", "%s: a name" % faction)
	eq(Shipgen.build("rustfangs", "medium", 3, 100.0, {"ram": true}).get_meta("ai")["morale"], "ram", "a rammer breaks like one")
	eq(Shipgen.build("concord", "small", 3, 60.0).get_meta("ai")["morale"], "concord", "the Concord breaks like the Concord")


# --- the budget --------------------------------------------------------------------------------------

func test_the_budget_follows_section_14() -> void:
	var base: Dictionary = Shipgen.tables()["budget"]["tier_base"]  # the tier bases are tuned by the balance harness (docs/BALANCE_REPORT.md)
	var t1 := float(base["1"])
	near(Shipgen.budget_for(1, 0, 1.0), t1, "tier 1, no jumps, danger 1")
	near(Shipgen.budget_for(1, 10, 1.0), t1 * 1.4, "+4% a jump")
	near(Shipgen.budget_for(2, 10, 1.1), float(base["2"]) * 1.4 * 1.1, "the region's danger")
	near(Shipgen.budget_for(3, 25, 1.6, "hard"), float(base["3"]) * 2.0 * 1.6 * 1.2, "the Hollow on hard")
	near(Shipgen.budget_for(1, 0, 1.0, "easy"), t1 * 0.8, "easy")
	check(t1 < float(base["2"]) and float(base["2"]) < float(base["3"]), "each tier's base is above the one before")


func test_the_first_three_stages_fight_with_70_percent_of_the_budget() -> void:
	var full := Shipgen.budget_for(2, 15, 1.1)
	for stage in [1, 2, 3]:
		near(Shipgen.budget_for(2, 15, 1.1, "normal", stage), full * 0.7, "stage %d: 70%%" % stage)
	near(Shipgen.budget_for(2, 15, 1.1, "normal", 4), full, "stage 4 and later: all of it")
	near(Shipgen.budget_for(2, 15, 1.1, "normal", 0), full, "an unknown stage: all of it")
	near(Shipgen.budget_for(3, 35, 1.0, "hard", 8), Shipgen.budget_for(3, 35, 1.0, "hard"), "the late game is unchanged")


## The share of 6 factions x `n` seeds whose enemy of run stage `stage` carries a shield.
func _shield_share(stage: int, n: int) -> float:
	var jumps: int = [5, 15, 25, 35][stage - 1]
	var tier: int = [1, 2, 3, 3][stage - 1]
	var with_shield := 0
	var total := 0
	for faction in ["rustfangs", "concord", "lumen", "wardens", "clans", "hollow"]:
		for i in n:
			var budget := Shipgen.budget_for(tier, jumps, 1.0, "normal", stage)
			var rng := RandomNumberGenerator.new()
			rng.seed = 1000 + i
			var ship := Shipgen.build(faction, Shipgen.pick_size(budget, rng), 5000 + i * 13, budget, {"stage": stage})
			total += 1
			if ship != null and not ship.get_meta("shipgen")["shields"].is_empty():
				with_shield += 1
	return float(with_shield) / float(total)


func test_an_early_enemy_carries_a_shield_at_most_25_40_and_55_percent_of_the_time() -> void:
	var caps := [0.25, 0.40, 0.55]
	for k in 3:
		near(Shipgen.shield_cap(k + 1), caps[k], "stage %d cap" % (k + 1))
		var share := _shield_share(k + 1, 30)
		check(share <= caps[k] + 1e-9, "stage %d: %.0f%% of the enemies have a shield, the cap is %.0f%%" % [k + 1, share * 100.0, caps[k] * 100.0])
	near(Shipgen.shield_cap(4), 1.0, "later stages are not capped")
	check(_shield_share(4, 10) > 0.9, "and by then nearly every enemy has one")


func test_the_stage_rides_in_the_spec_and_the_ship_is_the_same_every_time() -> void:
	var stage_spec := Shipgen.spec("concord", "medium", 77, 60.0, false, 2)
	check(stage_spec.ends_with(":s2"), "a stage with a cap is in the spec: " + stage_spec)
	check(Shipgen.spec("concord", "medium", 77, 60.0, false, 5) == Shipgen.spec("concord", "medium", 77, 60.0), "a later stage is not")
	check(Shipgen.spec("rustfangs", "medium", 77, 60.0, true, 1).ends_with(":s1:ram"), ":ram stays last")
	var a := Shipgen.from_spec(stage_spec)
	var b := Shipgen.from_spec(stage_spec)
	check(a != null and b != null, "the spec builds")
	eq(a.get_meta("shipgen")["shields"], b.get_meta("shipgen")["shields"], "the same spec, the same shields")
	var ram := Shipgen.from_spec(Shipgen.spec("rustfangs", "medium", 77, 90.0, true, 1))
	check(ram != null and bool(ram.get_meta("shipgen")["ram"]), "a stage and a ram together")
	var shieldless := 0
	for i in 40:  # the roll is the seed's: some seeds of a stage-1 concord ship have no shield at all, whatever the budget
		var s := Shipgen.build("concord", "medium", 900 + i, 120.0, {"stage": 1})
		shieldless += 1 if s.get_meta("shipgen")["shields"].is_empty() else 0
	check(shieldless >= 25, "at stage 1 most ships have none even with a big budget (%d of 40)" % shieldless)
	var rare := Shipgen.build("barons", "medium", 5, 300.0, {"stage": 1})
	check(rare != null and not rare.get_meta("shipgen")["shields"].is_empty(), "a rare faction ignores the cap")
	near(Shipgen.danger_of(Regions.get_region("gate_approaches")), 1.4, "the Gate approaches' danger comes from the region")
	near(Shipgen.danger_of({}), 1.0, "a region with none is plain")
	eq(Shipgen.faction_for(Regions.get_region("clan_space"), "pirate"), "rustfangs", "Clan space is raided by Rustfangs")
	eq(Shipgen.faction_for(Regions.get_region("clan_space"), "patrol"), "concord", "and patrolled by the Concord")
	eq(Shipgen.faction_for(Regions.get_region("lumen_space"), "pirate"), "wardens", "the Lumen's guards are the Wardens")
	eq(Shipgen.faction_for(Regions.get_region("lumen_space"), "patrol"), "wardens", "who patrol it too")
	eq(Shipgen.faction_for({}, "pirate"), "rustfangs", "an unknown region has Rustfangs")
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	eq(Shipgen.pick_size(20.0, rng), "small", "a small budget is a small ship")
	eq(Shipgen.pick_size(400.0, rng), "large", "a big one is large")
	var sizes := {}
	for i in 40:
		sizes[Shipgen.pick_size(75.0, rng)] = true
	check(sizes.has("small") and sizes.has("medium"), "on the line between sizes the seed decides")


func near(got: float, want: float, msg: String) -> void:
	check(absf(got - want) < 0.01, "%s: expected %s, got %s" % [msg, str(want), str(got)])


func test_a_bigger_budget_buys_more() -> void:
	for faction in Shipgen.factions():
		var total_spent := [0.0, 0.0, 0.0]
		for i in 5:
			for k in 3:
				var budget: float = [40.0, 120.0, 360.0][k]
				var ship := Shipgen.build(faction, "medium", 700 + i, budget)
				var meta: Dictionary = ship.get_meta("shipgen")
				check(float(meta["spent"]) <= budget + 1e-6, "%s: spent %.1f of %.0f" % [faction, float(meta["spent"]), budget])
				total_spent[k] += float(meta["spent"])
		check(total_spent[0] < total_spent[1] and total_spent[1] < total_spent[2], "%s: more budget, more spent (%s)" % [faction, str(total_spent)])


# --- the threat --------------------------------------------------------------------------------------

func test_threat_rises_with_the_budget() -> void:
	var player := Ship.from_design("res://data/ships/starter_courier.json")
	for faction in ["rustfangs", "concord", "wardens", "hollow"]:
		var means: Array = []
		var rises := 0
		var pairs := 0
		for budget in [40.0, 90.0, 200.0, 450.0]:
			var sum := 0.0
			for i in 6:
				var size := "small" if budget < 60.0 else ("medium" if budget < 250.0 else "large")
				sum += Threat.rate(Shipgen.build(faction, size, 800 + i, budget), player)["ratio"]
			means.append(sum / 6.0)
		for k in 3:
			check(means[k] < means[k + 1], "%s: threat %s rises with the budget (%s)" % [faction, str(k), str(means)])
		for i in 6:  # the same seed with four times the budget is the stronger ship, nearly always
			var weak: float = Threat.power(Shipgen.build(faction, "medium", 820 + i, 60.0), 0.6)["power"]
			var strong: float = Threat.power(Shipgen.build(faction, "medium", 820 + i, 240.0), 0.6)["power"]
			rises += int(strong > weak)
			pairs += 1
		# (Wardens and the Hollow field a gun or two whatever the budget, and a hull of the same size has about the same block hp:
		# one pair in two is all the single seeds can show; the means above are the real check.)
		check(rises >= (3 if faction in ["wardens", "hollow"] else 5), "%s: four times the budget is the stronger ship (%d of %d)" % [faction, rises, pairs])


func test_threat_is_one_to_five_skulls_against_the_players_ship() -> void:
	var courier := Ship.from_design("res://data/ships/starter_courier.json")
	var skulls := {}
	for budget in [30.0, 60.0, 120.0, 250.0, 500.0]:
		for faction in ["rustfangs", "concord"]:
			var r := Shipgen.threat(Shipgen.build(faction, "medium", 77, budget), courier)
			check(r["skulls"] >= 1 and r["skulls"] <= 5, "%s %.0f: %d skulls" % [faction, budget, r["skulls"]])
			skulls[r["skulls"]] = true
	check(skulls.size() >= 3, "the table of budgets spreads over several skulls: " + str(skulls.keys()))
	# the same enemy is a bigger threat to a smaller ship
	var enemy := Shipgen.build("concord", "medium", 5, 150.0)
	var small_fry := Shipgen.build("clans", "small", 6, 30.0)
	check(Shipgen.threat(enemy, small_fry)["ratio"] > Shipgen.threat(enemy, courier)["ratio"], "a weaker player ship sees more threat")
	var by_design := Shipgen.threat_of("gen:concord:medium:5:15000", courier)
	eq(by_design["skulls"], Shipgen.threat(enemy, courier)["skulls"], "the radar's call by design path gives the same skulls")
	check(Shipgen.threat_of("res://data/ships/pirate_raider.json", courier)["skulls"] >= 1, "and works for a design file")
	check(Shipgen.threat_of("res://nothing.json", courier).is_empty(), "and says nothing for one that does not load")
	eq(Threat.label(3), "Threat 3/5", "the label for the radar")
	eq(Threat.label(9), "Threat 5/5", "and it stays on the scale")


# --- the campaign and the combat session -------------------------------------------------------------

func test_a_spec_names_the_same_ship_as_build() -> void:
	var spec := Shipgen.spec("concord", "medium", 12345, 123.4, false)
	eq(spec, "gen:concord:medium:12345:12340", "the spec string")
	check(Shipgen.is_spec(spec) and not Shipgen.is_spec("res://data/ships/pirate_raider.json"), "specs and files are told apart")
	var a := Shipgen.from_spec(spec)
	var b := Shipgen.build("concord", "medium", 12345, 123.4, {"ram": false, "bays": true})
	eq(JSON.stringify(a.to_dict()), JSON.stringify(b.to_dict()), "from_spec builds what build builds")
	check(Shipgen.from_spec("gen:nobody:medium:1:100") == null and Shipgen.from_spec("gen:concord") == null, "a bad spec is no ship")
	var ram := Shipgen.from_spec(Shipgen.spec("rustfangs", "medium", 9, 80.0, true))
	eq(ram.get_meta("ai")["style"], "rammer", "a :ram spec is a rammer")
	var loaded: Ship = Session.load_ship(spec)
	check(loaded != null and loaded.get_meta("ai", {}).has("aim_skill"), "the combat session loads a spec like a design file")
	check(Session.load_ship("res://data/ships/pirate_raider.json") != null, "and the fixed designs are still there by path")


func test_the_campaign_rolls_tier_fights_from_the_region() -> void:
	var c := Campaign.new(4)
	var seen := {}
	for i in 30:
		var spec := c.fight_path("tier", "pirate")
		check(Shipgen.is_spec(spec), "a tier fight is a generated ship: " + spec)
		seen[spec.split(":")[1]] = true
	eq(seen.keys(), ["rustfangs"], "Clan space meets Rustfangs and nobody else")
	var patrol := c.fight_path("tier", "patrol")
	check(patrol.begins_with("gen:concord:"), "a Concord patrol: " + patrol)
	eq(c.fight_path("pirate_raider", "pirate"), "res://data/ships/pirate_raider.json", "a design id stays a file")
	eq(c.fight_path("rustfang_rammer", "pirate"), "res://data/ships/rustfang_rammer.json", "the fixed rammer too")
	# the budget grows with the jumps and the tier
	var early := float(c.fight_path("tier", "pirate").split(":")[4]) / 100.0
	c.jumps = 30
	var late := float(c.fight_path("tier", "pirate").split(":")[4]) / 100.0
	check(late > 3.0 * early, "the budget at jump 30 (%.0f) is far above jump 0 (%.0f)" % [late, early])
	c.jumps = 16
	var rammer := c.fight_path("tier", "pirate")
	check(c.misses() >= 2 and rammer.ends_with(":ram"), "two missed payments send a rammer: " + rammer)


# --- a generated ship fights -------------------------------------------------------------------------

func _fight(player: Ship, enemy: Ship, seconds: float, enemy_structure := -1.0) -> Session:
	var s := Session.new()
	s.start(player, enemy, enemy.rng_seed)
	if enemy_structure > 0.0:
		StructureUtil.set_structure(s.arena.ships[Session.ENEMY], enemy_structure)
	var pilot := PilotAI.new(s.arena, Session.PLAYER, Session.ENEMY, player.get_meta("ai", {}))
	var ticks := int(seconds * 60.0)
	var n := 0
	while s.state() == "fighting" and n < ticks:
		pilot.think(Session.STEP)
		s.ai.think(Session.STEP)
		s.arena.step(Session.STEP)
		n += 1
	return s


func test_a_generated_enemy_fights_and_can_be_wrecked() -> void:
	var player := Shipgen.build("concord", "medium", 41, 200.0)
	var enemy := Shipgen.build("rustfangs", "small", 32, 45.0)
	var s := _fight(player, enemy, 120.0, Structure.defeat_below() + 0.02)  # an enemy a hair over the wreck line
	eq(s.state(), "won", "the fight resolves: the enemy is wrecked")
	check(s.arena.ships[Session.ENEMY].wrecked and s.end_text() != "", "and the session says so")


func test_a_generated_enemy_shoots_back() -> void:
	var player := Ship.from_design("res://data/ships/starter_courier.json")
	var enemy := Shipgen.build("concord", "medium", 41, 120.0)
	var s := _fight(player, enemy, 45.0)
	var shots := 0
	for e in s.arena.events:
		shots += int(int(e.get("ship", -1)) == Session.ENEMY and (e["type"] == "shot" or e["type"] == "beam"))
	check(shots > 0, "the enemy fired %d times in 45 seconds" % shots)
	check(not s.arena.ships[Session.ENEMY].wrecked or s.state() == "won", "and the session knows who won")
