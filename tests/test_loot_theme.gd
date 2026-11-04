extends "res://tests/base_test.gd"
## Loot that fits the room (scripts/board/loot.gd roll, data/boarding.json loot_theme): the first roll is today's, so every tier keeps its share in
## every room; within a tier the items that fit the room come up more often; a blueprint the same.

const Site = preload("res://scripts/board/site.gd")
const Loot = preload("res://scripts/board/loot.gd")

const ROLLS := 50000
const TOLERANCE := 0.01


func _site(kind := "derelict"):
	var s = Site.new()
	s.kind = kind
	return s


## The share of each tier in `table` by its weights: what today's single roll gives.
func _base(table: Array) -> Dictionary:
	var total := 0.0
	var out := {}
	for o in table:
		total += float(o["weight"])
	for o in table:
		var t := Loot.tier_of(str(o["item"]))
		out[t] = float(out.get(t, 0.0)) + float(o["weight"]) / total
	return out


func test_every_room_purpose_keeps_each_tiers_share() -> void:
	var site = _site()
	for purpose in Site.config()["rooms"]:
		var table: Array = Loot.table_for(site, Loot.purpose_table(str(purpose)))
		if table.is_empty():
			continue
		var base := _base(table)
		var rng := RandomNumberGenerator.new()
		rng.seed = 99
		var got := {}
		for i in ROLLS:
			var t := Loot.tier_of(str(Loot.roll(table, str(purpose), rng)["item"]))
			got[t] = int(got.get(t, 0)) + 1
		for t in base:
			var share := float(got.get(t, 0)) / float(ROLLS)
			check(absf(share - float(base[t])) < TOLERANCE, "%s: tier %s %.4f, base %.4f" % [purpose, t, share, base[t]])


func test_items_that_fit_the_room_come_up_more_often() -> void:
	var site = _site()
	var table: Array = Loot.table_for(site, "engineering")
	var power := {}
	for purpose in ["reactor", "storage"]:
		var rng := RandomNumberGenerator.new()
		rng.seed = 5
		var n := 0
		var parts := 0
		for i in ROLLS:
			var item := str(Loot.roll(table, purpose, rng)["item"])
			if Loot.tier_of(item) == "part":
				parts += 1
				n += 1 if Loot.item_tags(item).has("power") else 0
		power[purpose] = float(n) / float(maxi(parts, 1))
	check(float(power["reactor"]) > float(power["storage"]) + 0.15, "a reactor room's parts are more often power parts (%s)" % str(power))
	var med: Array = Loot.table_for(site, "medbay")
	var rng := RandomNumberGenerator.new()
	rng.seed = 6
	var sash := {"medbay": 0, "airlock": 0}
	for purpose in sash:
		for i in ROLLS:
			if str(Loot.roll(med, purpose, rng)["item"]) == "medic_sash":
				sash[purpose] += 1
	check(int(sash["medbay"]) > int(sash["airlock"]) * 2, "a medbay's gear is more often medical (%s)" % str(sash))


func test_a_room_with_no_tags_rolls_exactly_as_before() -> void:
	var table: Array = Loot.table_for(_site(), "storage")
	var a := RandomNumberGenerator.new()
	var b := RandomNumberGenerator.new()
	a.seed = 11
	b.seed = 11
	for i in 200:
		eq(Loot.roll(table, "no_such_room", a), Loot._pick(table, b), "the same pick, roll %d" % i)


func test_a_blueprint_found_in_a_room_favours_recipes_that_fit_it() -> void:
	var unknown := ["reactor_mk2", "engine_mk2", "laser_mk2", "shield_mk2", "radar_mk2"]
	var levels := {}
	for rid in unknown:
		levels[rid] = 2
	var hits := {"reactor": 0, "storage": 0}
	for purpose in hits:
		var rng := RandomNumberGenerator.new()
		rng.seed = 3
		for i in 4000:
			if Loot._blueprint({"unknown": unknown, "levels": levels}, 2, rng, purpose) == "reactor_mk2":
				hits[purpose] += 1
	check(Loot.recipe_tags("reactor_mk2").has("power"), "a reactor recipe has the power tag")
	check(int(hits["reactor"]) > int(hits["storage"]) * 3 / 2, "a reactor room's blueprint is more often a power one (%s)" % str(hits))
