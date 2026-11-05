extends "res://tests/base_test.gd"
## Enemy identity (Beta 3, track enemy-variety, step A): the style system (data/ship_styles.json, `style` of the factions in
## data/enemy_tables.json, a pack's own ship_styles.json), race ships in their home regions, the livery on a built ship, and the threat parity of
## the race ships with the faction they are built on.

const Shipgen = preload("res://scripts/space/shipgen.gd")
const Threat = preload("res://scripts/space/threat.gd")
const Campaign = preload("res://scripts/space/campaign.gd")
const Regions = preload("res://scripts/space/regions.gd")
const Content = preload("res://scripts/data/content.gd")
const Session = preload("res://scripts/combat/combat_session.gd")
const ShipView = preload("res://scripts/view/ship_view.gd")
const TileArt = preload("res://scripts/view/tile_art.gd")
const Dressing = preload("res://scripts/view/dressing.gd")

const RACES: Array[String] = ["kett", "prismatic", "grundl"]
const GANGS: Array[String] = ["rustfangs", "clans", "lumen", "wardens"]
const BASE := {"kett": "clans", "prismatic": "lumen", "grundl": "concord", "revenant": "hollow", "choir": "wardens", "human": "concord"}


func test_the_styles_load_and_every_prototype_has_a_look() -> void:
	var T: Dictionary = Shipgen.tables()["factions"]
	for id in RACES + GANGS:
		check(T.has(id), id + " is a faction of the tables")
		var st = T.get(id, {}).get("style")
		check(st is Dictionary, id + " has a style")
		if not st is Dictionary:
			continue
		for k in ["label", "roles", "palette", "emblem"]:
			check(st.has(k), "%s style has %s" % [id, k])
		for k in ["tint", "accent", "lamp", "glow"]:
			check(Color.html_is_valid(str(st["palette"].get(k, ""))), "%s palette %s is a colour" % [id, k])
		check(st["emblem"]["prims"].size() >= 1, id + " has an emblem")
		for size in ["small", "medium", "large"]:
			check(str(st["roles"].get(size, "")) != "", "%s has a %s role noun" % [id, size])
	for id in RACES:
		eq(T[id].get("race"), id, id + " is a race")
		eq(T[id]["crew"]["species"], [id], id + " is crewed by its own race")
		eq(T[id]["lines_as"], BASE[id], id + " says its base faction's lines")
	check(not T["rustfangs"].has("race") and not T["clans"].has("race"), "the gangs are not races")


func test_the_race_kit_is_made_of_its_own_parts() -> void:
	var T: Dictionary = Shipgen.tables()["factions"]
	var comps = Shipgen._comps()
	for id in RACES:
		var own := 0
		for cat in ["weapons", "shields", "engines"]:
			for m in T[id]["parts"][cat]:
				check(comps.has(str(m["id"])) or comps.def(str(m["id"])) != {}, "%s buys a real part: %s" % [id, m["id"]])
				own += int(str(m["id"]).begins_with(id + "_"))
		check(own >= 3, "%s's menu holds its signature parts (%d)" % [id, own])


func test_a_pack_can_add_a_race_style() -> void:
	Content.packs_root = "res://tests/fixtures/packs/styles"
	var T: Dictionary = Shipgen.tables()["factions"]
	check(T.has("tinkerfolk"), "the pack's race is a faction")
	check(T.has("kett"), "the base styles stay")
	var ship = Shipgen.build("tinkerfolk", "medium", 3, 60.0)
	check(ship != null, "a pack race builds")
	if ship != null:
		eq(ship.get_meta("style")["line"], "Tinker " + str(ship.get_meta("shipgen")["role"]), "the pack's name line")
	Content.packs_root = ""
	check(not Shipgen.tables()["factions"].has("tinkerfolk"), "and it is gone with the pack")


func test_a_built_ship_carries_its_livery_crew_and_name_line() -> void:
	for size in ["small", "medium", "large"]:
		var ship = Shipgen.build("kett", size, 11, 120.0, {"stage": 3})
		check(ship != null, "a kett " + size)
		if ship == null:
			continue
		var look: Dictionary = ship.get_meta("style")
		eq(look["line"], "Kett " + str(ship.get_meta("shipgen")["role"]), "the name line of a kett " + size + " is its people and its role")
		check(look["emblem"]["prims"].size() > 0, "the emblem is on the ship")
		check(look["palette"]["tint"] is Color and look["palette"]["tint"] != Color.WHITE, "the tint is on the ship")
		check(ship.crew_plan.size() > 0 and ship.crew_plan.all(func(m): return m["species"] == "kett"), "crewed by kett")
		eq(ship.get_meta("ai")["faction"], "clans", "it says its base faction's lines")
	for id in GANGS:
		var s = Shipgen.build(id, "medium", 5, 90.0)
		check(s != null and s.get_meta("style", {}).get("id") == id, id + " has its livery")
	for id in Shipgen.factions():  # every faction and every race has a look
		check(Shipgen.style_of(id, "medium").has("emblem"), id + " has a livery")


func test_a_lost_cell_drops_its_dressing_and_the_rest_stays_put() -> void:
	var ship = Shipgen.build("kett", "medium", 11, 120.0, {"stage": 3})
	var plan: Array = Dressing.plan(ship, ship.get_meta("style")["dressing"])
	check(plan.size() > 1, "the kett ship wears dressing")
	eq(Dressing.kept(plan, ship.grid).size(), plan.size(), "an intact hull keeps every piece")
	var lost := Vector2i((Vector2(plan[0]["at"]) - Vector2(plan[0]["n"]) * 0.5).floor())
	check(ship.grid.tiles.has(lost), "a piece sits on a hull cell")
	ship.grid.tiles.erase(lost)
	var after: Array = Dressing.kept(plan, ship.grid)
	check(after.size() < plan.size(), "the piece on the lost cell is gone")
	for p in after:
		check(plan.has(p), "every other piece stays exactly where it was")


func test_the_emblem_has_a_spot_on_the_hull_and_draws() -> void:
	var ship = Shipgen.build("prismatic", "medium", 2, 100.0)
	var plan := TileArt.skin_plan(ship.grid, {})
	var at := ShipView.emblem_spot(plan)
	check(at.x > -1.0e8, "a plate for the emblem")
	for id in RACES + GANGS:  # every emblem is made of known primitives inside the unit box
		for prim in Shipgen.tables()["factions"][id]["style"]["emblem"]["prims"]:
			check(prim.has("poly") or prim.has("circle") or prim.has("line"), id + ": a known primitive")
			var nums: Array = []
			for k in ["poly", "circle", "line"]:
				if prim.has(k):
					nums = prim[k].duplicate()
					nums = nums.reduce(func(acc, v): return acc + (v if v is Array else [v]), [])
			check(nums.all(func(v): return float(v) >= 0.0 and float(v) <= 1.0), id + ": inside the unit box")


func test_the_same_seed_gives_the_same_race_ship() -> void:
	for id in RACES:
		var a = Shipgen.build(id, "medium", 77, 100.0, {"stage": 3})
		var b = Shipgen.build(id, "medium", 77, 100.0, {"stage": 3})
		eq(a.grid.tiles, b.grid.tiles, id + ": the same tiles")
		eq(a.get_meta("shipgen")["weapons"], b.get_meta("shipgen")["weapons"], id + ": the same guns")
		eq(a.name, b.name, id + ": the same name")


func test_old_specs_still_build() -> void:
	for spec in ["gen:rustfangs:medium:123:15000:s3", "gen:concord:small:9:3000", "gen:lumen:large:5:40000:s1", "gen:hollow:large:4:30000:warden", "gen:rustfangs:large:8:20000:ram"]:
		check(Shipgen.from_spec(spec) != null, "loads " + spec)
		check(Session.load_ship(spec) != null, "fights " + spec)
	check(Shipgen.from_spec("gen:kett:medium:7:12000:s3") != null, "a race spec loads too")


func test_a_race_region_sends_its_own_ships_for_the_race_share() -> void:
	var c := Campaign.new(4)
	c.region_data = Regions.get_region("kett_hives")
	var roll := RandomNumberGenerator.new()
	roll.seed = 99
	var own := 0
	var n := 300
	for i in n:
		var spec := c.gen_spec("gen:", "pirate", roll)
		if spec.begins_with("gen:kett:"):
			own += 1
		else:
			check(spec.begins_with("gen:" + Shipgen.faction_for(c.region_data, "pirate") + ":"), "the rest are the region's faction: " + spec)
	var share := float(own) / n
	check(absf(share - Shipgen.RACE_SHARE) < 0.08, "about the race share of the fights are Kett: %.2f" % share)
	eq(c.gen_spec("gen:", "patrol", roll).split(":")[1], "concord", "a patrol is still Concord's")
	c.region_data = Regions.get_region("clan_space")
	for i in 40:
		eq(c.gen_spec("gen:", "pirate", roll).split(":")[1], "rustfangs", "a region with no race style meets its faction")
	c.region_data = Regions.get_region("sporeling_groves")  # every race has a style now: its home region sends it too
	var spor := 0
	for i in 100:
		spor += int(c.gen_spec("gen:", "pirate", roll).begins_with("gen:sporeling:"))
	check(spor > 40 and spor < 80, "a Sporeling grove meets Sporelings about as often as the share: %d of 100" % spor)


func _mean_power(faction: String, budget: float, stage: int, seeds: int) -> float:
	var sum := 0.0
	var n := 0
	for k in seeds:
		var rng := RandomNumberGenerator.new()
		rng.seed = 5000 + k
		var ship = Shipgen.build(faction, Shipgen.pick_size(budget, rng), 5000 + k * 31, budget, {"stage": stage})
		if ship != null:
			sum += float(Threat.power(ship, float(ship.get_meta("ai", {}).get("aim_skill", 0.6)))["power"])
			n += 1
	return sum / maxf(n, 1)


func test_race_ships_keep_the_threat_of_the_faction_they_are_built_on() -> void:
	for id in ["kett", "prismatic", "grundl", "revenant", "choir", "human"]:  # one style of each base faction (the full tables: tests/tool_enemy_parity.gd)
		var race := _mean_power(id, 165.0, 3, 40)
		var base := _mean_power(BASE[id], 165.0, 3, 40)
		var ratio := race / base
		check(ratio > 0.8 and ratio < 1.25, "%s mean power %.1f against %s %.1f (x%.2f)" % [id, race, BASE[id], base, ratio])


func test_no_two_styles_share_both_a_dominant_colour_and_a_dressing_kind() -> void:
	var seen := {}
	for id in Shipgen.factions():
		var st = Shipgen.tables()["factions"][id].get("style")
		if not st is Dictionary:
			continue
		var tint := Color(str(st["palette"]["tint"]))
		var cls := ("grey%d" % int(tint.v * 3.0)) if tint.s < 0.18 else ("h%d" % int(tint.h * 12.0) + "l%d" % int((tint.v + tint.s * 0.0) * 2.0 * 0.999))
		for e in st["dressing"]:
			var key := "%s/%s" % [cls, e["kind"]]
			check(not seen.has(key), "%s and %s share the colour %s and the dressing %s" % [id, seen.get(key, ""), cls, e["kind"]])
			seen[key] = id


func test_roles_shift_the_split_not_the_budget_and_name_the_ship() -> void:
	for id in ["kett", "rustfangs", "concord", "revenant"]:
		var roles: Array = Shipgen.roles_of(id)
		check(roles.size() >= 2 and roles.size() <= 4, "%s flies 2 to 4 roles: %s" % [id, str(roles)])
		var seen := {}
		for sd in 80:
			var ship = Shipgen.build(id, "medium", sd, 150.0, {"stage": 3})
			var role := str(ship.get_meta("shipgen")["role"])
			seen[role] = true
			check(roles.has(role), "%s: %s is one of its roles" % [id, role])
			check(ship.get_meta("style")["line"].ends_with(role), "the name line carries the role: " + ship.get_meta("style")["line"])
			check(float(ship.get_meta("shipgen")["spent"]) <= 150.0 + 0.01, "a role never adds budget")
		check(seen.size() >= 2, "%s: at least two roles are reachable by seed (%s)" % [id, str(seen.keys())])
	for id in ["kett", "prismatic", "grundl", "rustfangs", "lumen", "concord"]:
		check(Shipgen.roles_of(id).size() >= 2, id + " has roles")


func test_a_roled_ship_is_built_like_its_role() -> void:
	var guns := {"gunboat": 0.0, "hauler": 0.0}
	var armour := {"gunboat": 0.0, "brawler": 0.0}
	var shields := {"escort": 0.0, "gunboat": 0.0}
	var n := {"gunboat": 0, "hauler": 0, "brawler": 0, "escort": 0}
	for sd in 40:
		for role in n:
			var ship = Shipgen.build("concord", "large", 200 + sd, 260.0, {"stage": 4, "role": role})
			var m: Dictionary = ship.get_meta("shipgen")
			n[role] += 1
			if guns.has(role): guns[role] += m["weapons"].size()
			if armour.has(role): armour[role] += int(m["armour"])
			if shields.has(role): shields[role] += m["shields"].size()
	check(guns["gunboat"] > guns["hauler"], "a gunboat carries more guns than a hauler (%.1f vs %.1f)" % [guns["gunboat"] / 40.0, guns["hauler"] / 40.0])
	check(armour["brawler"] > armour["gunboat"], "a brawler wears more armour than a gunboat")
	check(shields["escort"] > shields["gunboat"], "an escort has more shield than a gunboat")


func test_a_higher_budget_looks_stronger_whatever_the_role() -> void:
	for id in ["kett", "rustfangs", "concord"]:
		var lo := {"cells": 0.0, "guns": 0.0, "armour": 0.0}
		var hi := {"cells": 0.0, "guns": 0.0, "armour": 0.0}
		for sd in 30:
			for pair in [[lo, 45.0], [hi, 240.0]]:
				var ship = Shipgen.build(id, "medium", 300 + sd, pair[1], {"stage": 4})
				pair[0]["cells"] += ship.grid.tiles.size()
				pair[0]["guns"] += ship.get_meta("shipgen")["weapons"].size()
				pair[0]["armour"] += int(ship.get_meta("shipgen")["armour"])
		check(hi["guns"] > lo["guns"] and hi["armour"] > lo["armour"] and hi["cells"] >= lo["cells"], "%s: more guns, plating and hull with the budget (%s vs %s)" % [id, str(lo), str(hi)])
	var poor = Shipgen.build("kett", "medium", 3, 30.0)
	var rich = Shipgen.build("kett", "medium", 3, 300.0)
	eq(poor.get_meta("style")["grade"], "patched", "a low budget looks patched")
	eq(rich.get_meta("style")["grade"], "fine", "a high one looks fine")
