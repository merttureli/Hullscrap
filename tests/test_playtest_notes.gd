extends "res://tests/base_test.gd"
## Balance and feel notes of the second playtest: the on-foot gun spread by class (arms.gd), half as many guns from loot (loot.gd, boarding.json
## combat.foe_drop and gun_loot), and more stores than beacon traders in a region's sectors (data/sectors.json).

const Arms = preload("res://scripts/board/arms.gd")
const Site = preload("res://scripts/board/site.gd")
const Loot = preload("res://scripts/board/loot.gd")
const Regions = preload("res://scripts/space/regions.gd")
const Sector = preload("res://scripts/space/sector.gd")
const Content = preload("res://scripts/data/content.gd")
const Sfx = preload("res://scripts/audio/audio.gd")


func _deg(rad: float) -> float:
	return rad_to_deg(rad)


func test_on_foot_spread_by_class() -> void:
	var pistol = Arms.make_gun("service_pistol")
	var rifle = Arms.make_gun("carbine")
	var heavy = Arms.make_gun("slugthrower")
	check(absf(_deg(Arms.spread_of(pistol, false)) - 3.0) < 0.01, "pistol +-3 degrees (softened from the 4 asked for: the foot bench): %f" % _deg(Arms.spread_of(pistol, false)))
	check(absf(_deg(Arms.spread_of(rifle, false)) - 3.0) < 0.01, "rifle +-3 degrees at rest")
	var h := _deg(Arms.spread_of(heavy, false))
	check(h >= 0.8 and h <= 2.0, "heavy as before or a little wider: %f" % h)
	check(Arms.make_gun("quarry_hammer")["w"]["spread"] == 0.0, "melee has no spread")


func test_moving_opens_the_spread_by_half() -> void:
	var g = Arms.make_gun("service_pistol")
	check(absf(Arms.spread_of(g, true) / Arms.spread_of(g, false) - 1.5) < 1e-6, "x1.5 while moving")


func test_a_rifle_burst_opens_per_shot_and_closes_after_a_rest() -> void:
	var g = Arms.make_gun("carbine")
	var prev := Arms.spread_of(g, false)
	for i in 3:
		g["cd"] = 0.0
		Arms.spend(g)
		var now := Arms.spread_of(g, false)
		check(now > prev, "shot %d opens it: %f > %f" % [i + 1, _deg(now), _deg(prev)])
		prev = now
	for i in 10:
		g["cd"] = 0.0
		Arms.spend(g)
	check(_deg(Arms.spread_of(g, false)) <= 3.0 + 2.4 + 0.01, "a long burst is capped: %f" % _deg(Arms.spread_of(g, false)))
	Arms.tick(g, 1.0, func(n): return 0)
	check(absf(_deg(Arms.spread_of(g, false)) - 3.0) < 0.01, "a rest closes it again")
	var p = Arms.make_gun("service_pistol")
	for i in 3:
		p["cd"] = 0.0
		Arms.spend(p)
	check(absf(_deg(Arms.spread_of(p, false)) - 3.0) < 0.01, "a pistol does not open per shot")


func _gun_items(contents: Dictionary) -> int:
	var n := 0
	var held: Dictionary = Site.config()["combat"]["hand_items"]
	for it in contents["items"]:
		if held.has(it):
			n += int(contents["items"][it])
	return n


func test_containers_give_about_half_the_guns() -> void:
	var cfg: Dictionary = Site.config()["combat"]
	check(absf(float(cfg["foe_drop"]) - 0.2) < 1e-6, "a foe leaves its gun at 0.2 (was 0.4)")
	var share := float(cfg["gun_loot"])
	check(absf(share - 0.5) < 1e-6, "half of the gun rolls of containers keep the gun")
	var with_cut := 0
	var without := 0
	for sd in 14:
		var site = Site.make(5 + sd * 37, "nest", {"faction": "clans"})
		if site == null or not site.ok:
			continue
		for id in site.props.size():
			if site.props[id]["loot"]:
				with_cut += _gun_items(Loot.resolve(site, id))
		cfg["gun_loot"] = 1.0
		for id in site.props.size():
			if site.props[id]["loot"]:
				without += _gun_items(Loot.resolve(site, id))
		cfg["gun_loot"] = share
	check(without >= 8, "the uncut tables give guns in the sample: %d" % without)
	check(float(with_cut) <= 0.7 * float(without) and float(with_cut) >= 0.3 * float(without), "about half: %d of %d" % [with_cut, without])


func test_most_sectors_have_a_store_and_beacon_traders_are_rare() -> void:
	var cfg: Dictionary = Content.read("res://data/drift.json")
	var nodes := 0
	var stores := 0
	var traders := 0
	for rid in ["boneyard", "concord_space", "clan_space", "lumen_space"]:
		var r: Dictionary = Regions.get_region(rid)
		for i in 10:
			var seed_v := 100 + i * 37
			for n in Regions.make_map(r, cfg, seed_v).nodes:
				nodes += 1
				for p in Sector.generate(seed_v, n, rid, {}, r).pois:
					stores += 1 if p["type"] == "store" else 0
					traders += 1 if p["type"] == "trader" else 0
	var per5 := 5.0 * stores / maxf(nodes, 1)
	check(per5 >= 2.4 and per5 <= 3.6, "about 3 stores to 5 nodes: %.2f" % per5)
	check(traders * 4 <= stores, "beacon traders are few: %d traders, %d stores" % [traders, stores])
	check(traders > 0, "traders still appear (their events still fire)")


func test_the_pickup_clink_is_short_quiet_and_varies_in_pitch() -> void:
	var d: Dictionary = Sfx.table()["collect"]
	check(float(d["volume_db"]) <= -10.0, "the pick-up sits under the music: %f dB" % float(d["volume_db"]))
	check(float(d["pitch_var"]) >= 0.1, "a little random pitch")
	for f in d["files"]:
		var w = load("res://assets/audio/sfx/" + str(f))
		check(w != null and w.get_length() < 0.2, "%s is a short clink" % f)
