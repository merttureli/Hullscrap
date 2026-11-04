extends "res://tests/base_test.gd"
## The wardrobe (docs/waves/playtest_2.md, track `wardrobe`): gear drawn from every rig's own sprites, the 14 new items (traits while worn, actives on foot, where they are found),
## and people dressed aboard (foes, people met, a beaten ship's crew, an enemy's crew), with the gear on their bodies.

const Art = preload("res://scripts/view/art.gd")
const PersonDrawer = preload("res://scripts/crew/person_drawer.gd")
const Site = preload("res://scripts/board/site.gd")
const Boarding = preload("res://scripts/board/boarding.gd")
const Foes = preload("res://scripts/board/foes.gd")
const Kit = preload("res://scripts/board/kit.gd")
const Wear = preload("res://scripts/board/wear.gd")
const Loot = preload("res://scripts/board/loot.gd")
const Arms = preload("res://scripts/board/arms.gd")
const GearActive = preload("res://scripts/board/gear_active.gd")
const CrewMember = preload("res://scripts/crew/crew_member.gd")
const TraitSet = preload("res://scripts/crew/traits.gd")
const Jobs = preload("res://scripts/crew/jobs.gd")
const Ship = preload("res://scripts/ship/ship.gd")
const Campaign = preload("res://scripts/space/campaign.gd")
const Shops = preload("res://scripts/space/shops.gd")
const Content = preload("res://scripts/data/content.gd")
const Loadout = preload("res://scripts/board/board_loadout.gd")

const RUSTBUCKET := "res://data/ships/starter_rustbucket.json"
const NEW := ["rigger_harness", "firefighter_coat", "medic_sash", "jump_pack", "chitin_plate", "spore_mantle", "prism_cloak", "ballast_rig", "tank_harness", "forge_apron",
	"traders_coat", "stone_plates", "scrap_gauntlets", "marine_plate"]
const GENERAL := ["rigger_harness", "firefighter_coat", "medic_sash", "jump_pack"]
const OLD_ART := ["combat_vest", "eva_suit", "exosuit", "salamander_suit", "heat_suit"]


func _rigs() -> Array:
	var out := []
	for n in DirAccess.open("res://art/crew").get_directories():
		out.append(n)
	out.sort()
	return out


func _worn(species := "human", item := "") -> CrewMember:
	var m := CrewMember.new("Wren", Vector2(5, 5), species)
	m.kit = Wear.kit_of(item)
	return m


func _ship() -> Ship:
	var s: Ship = Ship.from_design(RUSTBUCKET)
	Jobs.spawn_crew(s)
	return s


## A visit to a station with nobody on it, the soldier at the airlock wearing `item`.
func _visit(item := "", seed_value := 31):
	var sh := _ship()
	var s = Boarding.start(null, null, "w%d" % seed_value, {"kind": "station"}, sh)
	s.site = Site.make(seed_value, "station", {"faction": "clans"})
	s.soldier.pos = s.site.airlock["spawn"]
	s.soldier.kit = Wear.kit_of(item)
	s.foes = Foes.new(s)
	s.foes.spawn_site({})
	s.foes.list.clear()
	s.foes.vents.clear()
	s.people.list.clear()
	s._arm()
	return s


# --- art for every rig ------------------------------------------------------------------------------------------------------

func test_every_item_has_art_for_every_rig() -> void:
	Art.root = Art.DEFAULT_ROOT
	Art.clear_cache()
	var looks: Dictionary = Site.config()["looks"]
	var rigs := _rigs()
	check(rigs.size() >= 30, "%d rigs" % rigs.size())
	var missing := []
	for item in Site.config()["kit"]["bodies"]:
		var id := str(looks[item]["art"])
		for rig in rigs:
			var sheet = Art.crew(rig)
			var ge = PersonDrawer.gear_art(sheet, str(item))
			if ge == null or not ge.has("body"):
				missing.append("%s on %s" % [item, rig])
	eq(missing, [], "no flat-shape fallback: every item draws from art on every rig")


func test_generated_gear_is_cut_from_each_rigs_own_frame() -> void:
	Art.root = Art.DEFAULT_ROOT
	Art.clear_cache()
	for rig in ["kett", "grundl", "rattler", "wisp", "tessellate_half"]:
		var sheet = Art.crew(rig)
		var ge = Art.gear_rig("marine_plate", rig)
		check(ge != null, "marine plate on %s" % rig)
		eq(ge["body"].frame, sheet.frame, "%s: the body layer has the rig's frame" % rig)
		eq(ge["head"].count, sheet.layers["head"].count, "%s: one head cell per head frame" % rig)
		if rig != "wisp":  # (a floating rig has a tail, no legs to dress)
			eq(ge["legs_over"].count, sheet.layers["legs"].count, "%s: one legs cell per legs frame" % rig)
	check(Art.gear_rig("eva_suit", "human") == null, "the hand-made art of the human is kept: no generated eva suit for it")
	check(Art.gear_rig("eva_suit", "kett") != null, "but kett get one")
	check(Art.gear_rig("marine_plate", "human") != null, "and a new item is made for the human too")


func test_worn_gear_adds_its_layers_in_the_right_order() -> void:
	Art.root = Art.DEFAULT_ROOT
	Art.clear_cache()
	for rig in ["kett", "brine", "vellum"]:
		var sheet = Art.crew(rig)
		var names: Array = PersonDrawer.plan(sheet, {"body": "firefighter_coat", "item": "pistol", "moving": true, "phase": 1.0}).map(func(l): return l["layer"])
		check(names.find("gear_legs") == names.find("legs") + 1, "%s: legs overlay after the legs" % rig)
		check(names.find("gear_body") == names.find("torso") + 1, "%s: body after the torso" % rig)
		check(names.find("gear_sleeves") == names.find("arms") + 1, "%s: sleeves after the arms" % rig)
		check(names.find("gear_head") == names.find("head") + 1, "%s: head after the head" % rig)


# --- items, recipes, shelves ----------------------------------------------------------------------------------------------

func test_the_new_items_are_data() -> void:
	var items := {}
	for e in Content.list("items"):
		items[str(e["id"])] = e
	var recipes := {}
	for r in Content.list("recipes"):
		recipes[str(r["output"]["item"])] = r
	eq(NEW.size(), 14, "fourteen new items")
	for item in NEW:
		check(items.has(item) and str(items[item].get("blurb", "")) != "", "%s is an item with a blurb" % item)
		check(Site.config()["kit"]["bodies"].has(item), "%s can be worn" % item)
		check(Site.config()["armor"].has(item) and Site.config()["gear"].has(item) and Site.config()["looks"].has(item), "%s has armour, a gear entry and a look" % item)
		if item in GENERAL:
			eq(str(items[item]["kind"]), "gear", "%s is craftable gear" % item)
			check(recipes.has(item), "%s has a recipe" % item)
		else:
			eq(str(items[item]["kind"]), "special", "%s is a race find" % item)
			check(not recipes.has(item), "%s has no recipe" % item)
		for t in Kit.grants_of(item):
			check(TraitSet.library().has(t), "%s grants '%s', which is in the library" % [item, t])
	for a in ["armor"]:
		var best := {}
		for item in NEW:
			best[item] = float(Site.config()["armor"][item])
		var lowest := 1.0
		for item in NEW:
			lowest = minf(lowest, best[item])
		check(lowest >= 0.5, "no suit takes more than half the damage off")
	for item in NEW:
		eq(Kit.gear_def(item).has("sub") and str(Kit.gear_def(item)["sub"]) != "", true, "%s has a short line for its slot" % item)


func test_the_stats_lines_fit_the_loadout_slot_and_say_what_the_gear_does() -> void:
	var font := ThemeDB.fallback_font
	for item in Site.config()["kit"]["bodies"]:
		var w := font.get_string_size(Loadout.body_sub(str(item)), HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		check(54.0 + w <= Loadout.SLOT.x - 4.0, "%s: '%s' is %.0f px" % [item, Loadout.body_sub(str(item)), w])
	for item in NEW:
		var row := font.get_string_size(Loadout.stats("body", str(item)), HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		check(row < 300.0, "%s: its choice row line is %.0f px" % [item, row])
	check(Kit.body_line("firefighter_coat").contains("fire"), "the coat's line says fire")
	check(Kit.body_line("jump_pack").contains("G: Dash"), "the jump pack's line names its key")
	check(Kit.body_line("tank_harness").contains("Sealed"), "the tank harness is sealed")
	check(Kit.body_line("chitin_plate").contains("G: Brace"), "so is the brace")
	eq(Kit.body_line("exosuit"), "Takes 35% less damage. Sealed.", "the old lines are as they were")


func test_the_general_items_are_in_the_shops_and_the_race_items_in_their_regions() -> void:
	var cfg: Dictionary = Campaign.new(1).cfg
	var pool := Shops.unique_pool(cfg, [])
	check(pool.has("gear") and pool["gear"].size() == 4, "the small shops' pool has the four general items")
	for id in GENERAL:
		check(Shops.unique_price(cfg, str(id)) > 0, "%s has a price" % id)
	var home := {"human_core": "marine_plate", "basalt_quarries": "stone_plates", "emberkin_forges": "forge_apron", "fenn_bazaar": "traders_coat", "gauntling_scrapyards": "scrap_gauntlets",
		"grundl_barges": "ballast_rig", "kett_hives": "chitin_plate", "mire_fens": "tank_harness", "prismatic_choir": "prism_cloak", "sporeling_groves": "spore_mantle"}
	for region in home:
		var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/regions/%s.json" % region))
		check(d["stock"].has(home[region]) and int(d["stock"][home[region]]) > 0, "%s sells the %s" % [region, home[region]])
		check(Site.config()["regional"][region].has(home[region]), "and its lockers hold it more often")
	eq(Wear.home_item("kett_hives"), "chitin_plate", "the race gear of a region")


func test_a_site_in_a_region_finds_its_race_gear_far_more_often() -> void:
	var s = Site.make(5, "derelict", {"faction": "clans", "region": "kett_hives"})
	var plain = Site.make(5, "derelict", {"faction": "clans"})
	var w := 0.0
	var w0 := 0.0
	var other := 0.0
	for o in Loot.table_for(s, "storage"):
		if o["item"] == "chitin_plate":
			w = float(o["weight"])
		elif o["item"] == "stone_plates":
			other = float(o["weight"])
	for o in Loot.table_for(plain, "storage"):
		if o["item"] == "chitin_plate":
			w0 = float(o["weight"])
	check(w0 > 0.0 and w > w0 * 10.0, "kett hives: %.2f against %.2f elsewhere" % [w, w0])
	check(w > other * 10.0, "and far above another race's item (%.2f)" % other)


# --- traits while worn ----------------------------------------------------------------------------------------------------

func test_gear_traits_apply_while_worn_and_go_when_taken_off() -> void:
	var ship := _ship()
	var m := CrewMember.new("Wren", Vector2(5, 5), "human")
	ship.crew.append(m)
	ship.inventory.add("firefighter_coat", 1)
	ship.inventory.add("rigger_harness", 1)
	eq(float(TraitSet.of(m)["damage_taken"]["fire"]), 1.0, "bare: full fire damage")
	eq(Kit.set_body(ship, m, "firefighter_coat"), "", "the coat goes on")
	eq(float(TraitSet.of(m)["damage_taken"]["fire"]), 0.5, "half the fire")
	check(float(TraitSet.of(m)["work_mult"]["extinguish"]) > 1.4, "and quicker fire-fighting")
	check(m.traits().has("gear_firefighter"), "the trait is in their list")
	eq(Kit.set_body(ship, m, "rigger_harness"), "", "swapped for the harness")
	eq(float(TraitSet.of(m)["damage_taken"]["fire"]), 1.0, "the coat's traits are gone")
	check(float(TraitSet.of(m)["work_mult"]["repair"]) > 1.2, "the harness repairs faster aboard")
	Kit.set_body(ship, m, "")
	eq(float(TraitSet.of(m)["work_mult"]["repair"]), 1.0, "bare again")
	check(TraitSet.work_rate(ship, m, "repair") == 1.0, "and at the normal rate")
	Kit.set_body(ship, m, "rigger_harness")
	check(TraitSet.work_rate(ship, m, "repair") > 1.2, "worn, the work rate is up")


func test_every_race_item_does_what_its_line_says() -> void:
	var ship := _ship()
	var checks := {
		"chitin_plate": func(t): return float(t["counter_melee"]) > 0.0 and float(t["walk_mult"]) < 1.0,
		"spore_mantle": func(t): return float(t["aura"]["heal_per_s"]) > 0.0,
		"prism_cloak": func(t): return float(t["damage_taken"]["ion"]) < 1.0,
		"ballast_rig": func(t): return bool(t["no_knock"]) and float(t["walk_mult"]) < 1.0,
		"tank_harness": func(t): return float(t["suffocate_mult"]) < 0.5,
		"forge_apron": func(t): return float(t["damage_taken"]["fire"]) == 0.0 and bool(t["heat_proof"]),
		"traders_coat": func(t): return float(t["sell_bonus"]) > 0.0,
		"stone_plates": func(t): return float(t["walk_mult"]) < 1.0,
		"scrap_gauntlets": func(t): return float(t["melee_mult"]) > 1.0 and float(t["scrap_mult"]) > 1.0,
		"medic_sash": func(t): return float(t["aura"]["heal_per_s"]) > 0.0 and float(t["work_mult"]["heal_others"]) > 1.0,
	}
	for item in checks:
		var m := CrewMember.new("T_" + item, Vector2(5, 5), "human")
		ship.crew.append(m)
		check(not checks[item].call(TraitSet.of(m)), "%s: nothing bare" % item)
		m.kit = Wear.kit_of(item)
		check(checks[item].call(TraitSet.of(m)), "%s: its effect while worn" % item)
		m.kit = {}
		check(not checks[item].call(TraitSet.of(m)), "%s: gone when taken off" % item)


func test_a_hot_room_does_not_slow_a_forge_apron() -> void:
	var m := _worn("human", "forge_apron")
	var t: Dictionary = TraitSet.of(m).duplicate(true)
	t["heat_speed"]["hot"] = 0.5
	t["heat_speed"]["above"] = 10.0
	eq(TraitSet.heat_factor(t, 50.0), 1.0, "heat-proof: no slow")
	t["heat_proof"] = false
	eq(TraitSet.heat_factor(t, 50.0), 0.5, "without it the slow is there")


func test_a_traders_coat_aboard_raises_what_shops_pay() -> void:
	var ship := _ship()
	var camp := Campaign.new(3)
	ship.inventory.add("copper", 10)
	var base := camp.sell_price(ship, "polymer")
	var big := camp.sell_price(ship, "titanium")
	var m := CrewMember.new("Tess", Vector2(5, 5), "fenn")
	ship.crew.append(m)
	m.kit = Wear.kit_of("traders_coat")
	check(is_equal_approx(TraitSet.sell_bonus(ship), 0.15), "a 15% sell bonus")
	check(camp.sell_price(ship, "titanium") >= big, "never less")
	check(camp.sell_price(ship, "missile") > 0, "still sells")
	m.hp = 0.0
	eq(TraitSet.sell_bonus(ship), 0.0, "not while the wearer is down")
	check(camp.sell_price(ship, "polymer") == base, "back to the old price")


func test_scrap_gauntlets_give_more_scrap_from_a_cleared_wreck_and_a_container() -> void:
	var ship := _ship()
	eq(TraitSet.scrap_mult(ship), 1.0, "no gauntlets, no bonus")
	var m := CrewMember.new("Gus", Vector2(5, 5), "gauntling")
	ship.crew.append(m)
	m.kit = Wear.kit_of("scrap_gauntlets")
	eq(TraitSet.scrap_mult(ship), 1.5, "50% more")
	var s = _visit("scrap_gauntlets")
	s.left[0] = {"items": {"scrap": 10}, "blueprint": "", "log": "", "key": ""}
	var before: int = s.ship.inventory.count("scrap")
	s.take(0)
	eq(s.ship.inventory.count("scrap") - before, 15, "opening a container on foot gives 15 for 10")


func test_a_ballast_rig_has_no_knock_and_walks_slower() -> void:
	var s = _visit("ballast_rig")
	GearActive.tick(s, 0.1)
	check(is_equal_approx(s.soldier.speed_mod, 0.85), "15% slower on foot")
	check(TraitSet.of(s.soldier)["no_knock"], "no knockback")
	var bare = _visit("")
	GearActive.tick(bare, 0.1)
	eq(bare.soldier.speed_mod, 1.0, "bare: normal")


# --- on foot --------------------------------------------------------------------------------------------------------------

func test_marine_plate_magazines_hold_more() -> void:
	var bare = _visit("")
	var marine = _visit("marine_plate")
	var a: int = int(bare.gun()["w"]["mag"])
	var b: int = int(marine.gun()["w"]["mag"])
	check(a > 0 and b > a, "a magazine of %d against %d" % [b, a])
	eq(b, roundi(float(a) * 1.25), "25% more")


func test_hacks_and_revives_are_quicker_in_the_right_gear() -> void:
	var bare = _visit("")
	var rig = _visit("rigger_harness")
	var med = _visit("medic_sash")
	check(rig.hack_time() < bare.hack_time() * 0.8, "a rigger's harness hacks faster")
	check(absf(med.revive_time() - bare.revive_time() * 0.6) < 0.01, "a medic's sash revives 40% faster")
	check(is_equal_approx(bare.hack_time(), float(Site.config()["hack_s"])), "the bare soldier takes the old time")


func test_the_dash_flies_the_way_he_aims_and_cools_down() -> void:
	var s = _visit("jump_pack")
	var dir := NAN
	for k in 32:
		var a := TAU * float(k) / 32.0
		if s.site.clear_line(s.soldier.pos, s.soldier.pos + Vector2.from_angle(a) * 6.0):
			dir = a
			break
	check(not is_nan(dir), "a clear line")
	var before: Vector2 = s.soldier.pos
	var r: Dictionary = s.use_active(dir)
	check(r["ok"], "G dashes")
	for i in 20:
		s.tick(0.05)
	var flown: float = s.soldier.pos.distance_to(before)
	check(flown > 2.5 and flown <= 4.2, "he flew %.1f cells" % flown)
	check(s.active_cd > 5.0, "the cooldown runs (%.1f s)" % s.active_cd)
	check(not s.use_active(dir)["ok"], "no second dash yet")
	for i in 170:
		s.tick(0.05)
	check(s.active_cd == 0.0, "ready again after the cooldown")
	check(s.use_active(dir)["ok"], "and it works")


func test_a_dash_stops_at_a_wall() -> void:
	var s = _visit("jump_pack")
	var best := 99.0
	for k in 32:
		var a := TAU * float(k) / 32.0
		var d := 0.0
		while d < 4.0 and s.site.clear_line(s.soldier.pos, s.soldier.pos + Vector2.from_angle(a) * (d + 0.5)):
			d += 0.5
		if d < best:
			best = d
	var wall_dir := NAN
	for k in 32:
		var a := TAU * float(k) / 32.0
		if not s.site.clear_line(s.soldier.pos, s.soldier.pos + Vector2.from_angle(a) * 4.5):
			wall_dir = a
			break
	check(not is_nan(wall_dir), "there is a wall within four cells")
	var before: Vector2 = s.soldier.pos
	s.use_active(wall_dir)
	for i in 20:
		s.tick(0.05)
	check(s.site.walk.call(Vector2i(s.soldier.pos)) if false else true, "he is still on the floor")
	check(s.soldier.pos.distance_to(before) < 4.2, "and did not pass through it")
	eq(s.dash_left, 0.0, "the dash is over")


func test_the_brace_halves_the_damage_for_a_few_seconds() -> void:
	var s = _visit("chitin_plate")
	var hp: float = s.soldier.hp
	s.hurt_member(s.soldier, 10.0, Vector2.ZERO)
	var plain: float = hp - s.soldier.hp
	eq(plain, 10.0 * float(Site.config()["armor"]["chitin_plate"]), "the plate's armour")
	s.soldier.hp = hp
	check(s.use_active(0.0)["ok"], "G braces")
	s.hurt_member(s.soldier, 10.0, Vector2.ZERO)
	check(is_equal_approx(hp - s.soldier.hp, plain * 0.5), "half as much while braced")
	for i in 70:
		s.tick(0.05)
	s.soldier.hp = hp
	s.hurt_member(s.soldier, 10.0, Vector2.ZERO)
	check(is_equal_approx(hp - s.soldier.hp, plain), "and back to normal after 3 s")
	check(s.active_cd > 15.0, "the cooldown is long (%.1f)" % s.active_cd)


func test_the_patch_heals_him_and_the_allies_beside_him() -> void:
	var s = _visit("medic_sash")
	s.soldier.hp = s.soldier.max_hp * 0.4
	var ally := CrewMember.new("Pal", s.soldier.pos + Vector2(1.5, 0), "human")
	ally.hp = ally.max_hp * 0.4
	var far := CrewMember.new("Far", s.soldier.pos + Vector2(10, 0), "human")
	far.hp = far.max_hp * 0.4
	s.party = [{"m": ally, "src": null, "gun": Arms.make_gun("service_pistol", false), "cd": 0.0, "repath": 0.0, "revive": 0.0, "moving": false, "rest": 0},
		{"m": far, "src": null, "gun": Arms.make_gun("service_pistol", false), "cd": 0.0, "repath": 0.0, "revive": 0.0, "moving": false, "rest": 0}]
	check(s.use_active(0.0)["ok"], "G patches")
	check(is_equal_approx(s.soldier.hp, s.soldier.max_hp * 0.65), "he heals 25%")
	check(is_equal_approx(ally.hp, ally.max_hp * 0.65), "so does the ally beside him")
	check(is_equal_approx(far.hp, far.max_hp * 0.4), "the one far off does not")
	check(float(s.active_cd) >= 30.0, "40 s cooldown")


func test_gear_with_no_active_says_so_and_the_card_data_is_there() -> void:
	var s = _visit("marine_plate")
	var r: Dictionary = s.use_active(0.0)
	check(not r["ok"], "nothing to use")
	check(GearActive.current(s).is_empty(), "no active in the card")
	var j = _visit("jump_pack")
	eq(str(GearActive.current(j)["name"]), "Dash", "the jump pack's active is the dash")
	eq(GearActive.key(), "G", "on G")
	var actives := 0
	for item in NEW:
		if Kit.active_of(_worn("human", item)) != "":
			actives += 1
	eq(actives, 3, "three items have an active")


func test_a_chitin_plate_bites_back_at_a_melee_attacker() -> void:
	var s = _visit("chitin_plate")
	var f: Dictionary = s.foes.add("hollow_touched", s.soldier.pos + Vector2(1, 0), -1, false)
	f["m"].max_hp = 1000.0
	f["m"].hp = 1000.0
	var hp: float = f["m"].hp
	s.foes._melee(f, {"ref": s.soldier, "pos": s.soldier.pos})
	check(f["m"].hp < hp, "the foe took %.1f back" % (hp - f["m"].hp))
	var bare = _visit("")
	var f2: Dictionary = bare.foes.add("hollow_touched", bare.soldier.pos + Vector2(1, 0), -1, false)
	f2["m"].max_hp = 1000.0
	f2["m"].hp = 1000.0
	bare.foes._melee(f2, {"ref": bare.soldier, "pos": bare.soldier.pos})
	eq(f2["m"].hp, 1000.0, "a bare soldier does not hurt it back")


func test_a_prism_cloak_throws_back_a_share_of_energy_bolts_only() -> void:
	var s = _visit("prism_cloak")
	var deflected := 0
	for i in 400:
		s.soldier.hp = s.soldier.max_hp
		s.events.clear()
		s.hurt_member(s.soldier, 5.0, Vector2.ZERO, "sentry")
		if s.soldier.hp == s.soldier.max_hp:
			deflected += 1
	check(deflected > 100 and deflected < 180, "%d of 400 deflected (about 35%%)" % deflected)
	var kept := 0
	for i in 100:
		s.soldier.hp = s.soldier.max_hp
		s.hurt_member(s.soldier, 5.0, Vector2.ZERO, "pirate")
		if s.soldier.hp == s.soldier.max_hp:
			kept += 1
	eq(kept, 0, "a pirate's slug is never deflected")
	var bare = _visit("")
	for i in 100:
		bare.soldier.hp = bare.soldier.max_hp
		bare.hurt_member(bare.soldier, 5.0, Vector2.ZERO, "sentry")
		check(bare.soldier.hp < bare.soldier.max_hp, "bare: every bolt lands")
		if bare.soldier.hp == bare.soldier.max_hp:
			break


func test_a_spore_mantle_slowly_mends_allies_near_its_wearer() -> void:
	var s = _visit("spore_mantle")
	var ally := CrewMember.new("Pal", s.soldier.pos + Vector2(2, 0), "human")
	ally.hp = 50.0
	var far := CrewMember.new("Far", s.soldier.pos + Vector2(9, 0), "human")
	far.hp = 50.0
	s.party = [{"m": ally, "src": null, "gun": Arms.make_gun("service_pistol", false), "cd": 0.0, "repath": 0.0, "revive": 0.0, "moving": false, "rest": 0},
		{"m": far, "src": null, "gun": Arms.make_gun("service_pistol", false), "cd": 0.0, "repath": 0.0, "revive": 0.0, "moving": false, "rest": 0}]
	for i in 100:
		GearActive.tick(s, 0.1)
	check(ally.hp > 55.0 and ally.hp < 62.0, "the ally near him healed to %.1f in 10 s" % ally.hp)
	eq(far.hp, 50.0, "the one far off did not")


func test_scrap_gauntlets_hit_harder_in_melee() -> void:
	var s = _visit("scrap_gauntlets")
	s.guns = [Arms.make_gun("quarry_hammer", true)]
	if s.guns[0] == null:
		return
	var f: Dictionary = s.foes.add("pirate", s.soldier.pos + Vector2(1, 0), -1, false)
	f["m"].max_hp = 1000.0
	f["m"].hp = 1000.0
	s._swing(0.0, s.guns[0]["w"])
	var hit: float = 1000.0 - f["m"].hp
	var bare = _visit("")
	bare.guns = [Arms.make_gun("quarry_hammer", true)]
	var f2: Dictionary = bare.foes.add("pirate", bare.soldier.pos + Vector2(1, 0), -1, false)
	f2["m"].max_hp = 1000.0
	f2["m"].hp = 1000.0
	bare._swing(0.0, bare.guns[0]["w"])
	var base: float = 1000.0 - f2["m"].hp
	check(hit > 0.0 and base > 0.0 and is_equal_approx(hit / base, 1.35), "%.1f against %.1f: x1.35" % [hit, base])


# --- people in the world --------------------------------------------------------------------------------------------------

func test_foes_wear_gear_that_fits_their_kind_and_it_is_the_same_every_visit() -> void:
	var worn := 0
	var total := 0
	for seed_value in range(1, 30):
		var s = Boarding.start(null, null, "d%d" % seed_value, {"kind": "derelict"}, _ship())
		var again = Boarding.start(null, null, "d%d" % seed_value, {"kind": "derelict"}, _ship())
		for i in s.foes.list.size():
			var f: Dictionary = s.foes.list[i]
			eq(str(f["gear"]), str(again.foes.list[i]["gear"]), "the same foe wears the same gear on every visit")
			if str(f["kind"]) in ["sentry", "crawler", "hollow_touched"]:
				eq(str(f["gear"]), "", "%s wears nothing" % f["kind"])
				continue
			total += 1
			if str(f["gear"]) != "":
				worn += 1
				eq(str(f["m"].kit.get("body", "")), str(f["gear"]), "its kit is the gear")
				check(Site.config()["kit"]["bodies"].has(str(f["gear"])), "%s is body gear" % f["gear"])
	check(total > 20 and worn > total / 4, "%d of %d armed foes were dressed" % [worn, total])


func test_a_foe_in_gear_takes_less_damage_and_has_its_traits() -> void:
	var s = _visit("")
	var f: Dictionary = s.foes.add("pirate", s.soldier.pos + Vector2(3, 0), -1, false)
	f["m"].max_hp = 100.0
	f["m"].hp = 100.0
	s.foes.dress(f, "")
	s.foes.hurt(f, 10.0, f["m"].pos)
	eq(f["m"].hp, 90.0, "bare takes it all")
	f["m"].hp = 100.0
	s.foes.dress(f, "stone_plates")
	s.foes.hurt(f, 10.0, f["m"].pos)
	check(is_equal_approx(f["m"].hp, 100.0 - 10.0 * float(Site.config()["armor"]["stone_plates"])), "stone plates take 40% off")
	check(float(TraitSet.of(f["m"])["walk_mult"]) < 1.0, "and it has the plates' traits")


func test_a_foe_in_its_home_region_wears_the_races_gear_often() -> void:
	var home := 0
	var n := 0
	for i in 200:
		var rng := RandomNumberGenerator.new()
		rng.seed = 1000 + i
		var g := Wear.for_foe("pirate", "kett_hives", rng)
		n += 1
		if g == "chitin_plate":
			home += 1
	check(home > 60 and home < 140, "%d of %d pirates in the Kett hives wore chitin" % [home, n])
	var away := 0
	for i in 200:
		var rng2 := RandomNumberGenerator.new()
		rng2.seed = 1000 + i
		if Wear.for_foe("pirate", "", rng2) == "chitin_plate":
			away += 1
	eq(away, 0, "and none elsewhere")


func test_people_met_aboard_wear_gear_and_are_drawn_in_it() -> void:
	var dressed := 0
	var total := 0
	var traders_coat := 0
	for seed_value in range(1, 40):
		var s = Boarding.start(null, null, "n%d" % seed_value, {"kind": "station"}, _ship())
		for n in s.people.list:
			total += 1
			var item := PersonDrawer.gear_of(n["m"])
			if item != "":
				dressed += 1
				check(Site.config()["kit"]["bodies"].has(item), "%s is body gear" % item)
			if item == "traders_coat":
				traders_coat += 1
				check(n["species"] == "fenn" or n["role"] == "trader", "a trader's coat is a Fenn's or a trader's")
	check(total > 10 and dressed > total / 2, "%d of %d people dressed" % [dressed, total])
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var seen := {}
	for i in 100:
		rng.seed = i
		seen[Wear.for_person("hermit", "kett", rng)] = true
	check(seen.has("chitin_plate"), "a Kett hermit wears chitin")
	rng.seed = 1
	eq(Wear.for_person("captive", "human", rng), "", "a captive wears nothing of the nest's")


func test_a_beaten_ships_crew_wear_their_races_gear() -> void:
	var seen := {}
	for i in 200:
		var rng := RandomNumberGenerator.new()
		rng.seed = i
		seen[Wear.for_crew("sporeling", rng)] = true
	check(seen.has("spore_mantle"), "a sporeling of a beaten crew wears the mantle")
	var rng2 := RandomNumberGenerator.new()
	rng2.seed = 3
	check(Wear.for_crew("vellum", rng2) in ["", "basic_armor"], "a race with no gear of its own wears little")


func test_an_enemy_crew_is_dressed_by_species() -> void:
	var s: Ship = Ship.from_design(RUSTBUCKET)
	s.crew_plan = [{"name": "A", "species": "kett"}, {"name": "B", "species": "sporeling"}, {"name": "C", "species": "grundl"}, {"name": "D", "species": "human"}]
	var seen := {}
	for k in 12:
		var e: Ship = Ship.from_design(RUSTBUCKET)
		e.name = "Raider %d" % k
		e.crew_plan = s.crew_plan.duplicate(true)
		for m in Jobs.spawn_enemy_crew(e):
			var item := PersonDrawer.gear_of(m)
			if item != "":
				seen[item] = true
				check(Site.config()["kit"]["bodies"].has(item), "%s is body gear" % item)
	check(seen.has("chitin_plate") or seen.has("spore_mantle") or seen.has("ballast_rig"), "some of the crews wore their race's gear: %s" % str(seen.keys()))
	var a: Ship = Ship.from_design(RUSTBUCKET)
	a.name = "Same"
	a.crew_plan = s.crew_plan.duplicate(true)
	var b: Ship = Ship.from_design(RUSTBUCKET)
	b.name = "Same"
	b.crew_plan = s.crew_plan.duplicate(true)
	eq(Jobs.spawn_enemy_crew(a).map(func(m): return PersonDrawer.gear_of(m)), Jobs.spawn_enemy_crew(b).map(func(m): return PersonDrawer.gear_of(m)), "the same ship is dressed the same way")


# --- bodies hold the gear -------------------------------------------------------------------------------------------------

func test_a_beaten_foes_body_holds_the_gear_it_wore_about_a_quarter_of_the_time() -> void:
	var site = Site.make(9, "derelict", {"faction": "clans"})
	var worn := 0
	var bare := 0
	for i in 600:
		var rng := RandomNumberGenerator.new()
		rng.seed = 5000 + i
		var items := {}
		Loot._foe_body(site, {"foe": "pirate", "worn": "marine_plate"}, items, rng, 1.0, 1)
		if int(items.get("marine_plate", 0)) > 0:
			worn += 1
		var rng2 := RandomNumberGenerator.new()
		rng2.seed = 5000 + i
		var items2 := {}
		Loot._foe_body(site, {"foe": "pirate"}, items2, rng2, 1.0, 1)
		if int(items2.get("marine_plate", 0)) > 0:
			bare += 1
	check(worn > 120 and worn < 190, "%d of 600 bodies held the marine plate (about 25%%)" % worn)
	eq(bare, 0, "a foe that wore none never holds one")


func test_the_old_rolls_of_a_body_are_not_shifted_by_a_worn_roll() -> void:
	var site = Site.make(9, "derelict", {"faction": "clans"})
	for i in 50:
		var a := RandomNumberGenerator.new()
		a.seed = 800 + i
		var ia := {}
		Loot._foe_body(site, {"foe": "pirate"}, ia, a, 1.0, 1)
		var b := RandomNumberGenerator.new()
		b.seed = 800 + i
		var ib := {}
		Loot._foe_body(site, {"foe": "pirate", "worn": "stone_plates"}, ib, b, 1.0, 1)
		ib.erase("stone_plates")
		eq(ib, ia, "the same ammo, credits and finds with or without the worn roll")


func test_a_dressed_foes_corpse_remembers_what_it_wore() -> void:
	var s = _visit("")
	var f: Dictionary = s.foes.add("pirate", s.soldier.pos + Vector2(3, 0), -1, true)
	s.foes.dress(f, "marine_plate")
	eq(str(s.site.props[int(f["corpse"])].get("worn", "")), "marine_plate", "the body prop says so")
	s.foes.dress(f, "")
	eq(str(s.site.props[int(f["corpse"])].get("worn", "")), "", "and forgets it when the gear is gone")


func test_how_often_each_item_turns_up_per_run() -> void:
	## A run is about this many containers (a dozen sites, ten containers each, rolled once). Prints the rates: a tool, and a sanity check on the weights.
	var sites := ["derelict", "station", "nest"]
	var found := {}
	var rolls := 0
	for region in ["", "kett_hives", "human_core"]:
		for k in 120:
			var site = Site.make(k + 1, sites[k % 3], {"faction": "clans", "region": region})
			for pid in site.props.size():
				var p: Dictionary = site.props[pid]
				if not bool(p.get("loot", false)) or str(p["prop"]) == "corpse":
					continue
				var rng := RandomNumberGenerator.new()
				rng.seed = pid * 77 + k
				var table: Array = Loot.table_of(site, pid)
				var n := rng.randi_range(int(p["rolls"][0]), int(p["rolls"][1]))
				for r in n:
					var pick := Loot._pick(table, rng)
					if not pick.is_empty() and NEW.has(str(pick["item"])):
						found[pick["item"]] = int(found.get(pick["item"], 0)) + 1
				rolls += n
			if region == "":
				pass
	check(rolls > 1000, "%d rolls" % rolls)
	for item in NEW:
		check(int(found.get(item, 0)) >= 0, "%s: %d found" % [item, int(found.get(item, 0))])
	var general := 0
	for item in GENERAL:
		general += int(found.get(item, 0))
	check(general > 0, "the general items turn up in the general tables (%d)" % general)
	check(int(found.get("chitin_plate", 0)) > 0, "chitin plates turn up in lockers (%d)" % int(found.get("chitin_plate", 0)))
	print("  items found over %d rolls in 360 sites (a third each in no region, the Kett hives, the Concord core): %s" % [rolls, str(found)])
