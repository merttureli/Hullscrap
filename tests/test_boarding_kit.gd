extends "res://tests/base_test.gd"
## Boarding, stage B4 (docs/BOARDING.md, scripts/board/kit.gd, mods.gd, bolts.gd, board_fx.gd, board_cards.gd, board_loadout.gd): light bolts (the look of a shot, the flare
## that burns where it stuck), body gear, the three mods (Spotter Cam, Salvage Rig, Overcharge Coil) and where they come from, loadouts that leave the hold and stay on the person.

const Site = preload("res://scripts/board/site.gd")
const Loot = preload("res://scripts/board/loot.gd")
const Boarding = preload("res://scripts/board/boarding.gd")
const Arms = preload("res://scripts/board/arms.gd")
const Foes = preload("res://scripts/board/foes.gd")
const Kit = preload("res://scripts/board/kit.gd")
const Mods = preload("res://scripts/board/mods.gd")
const Bolts = preload("res://scripts/board/bolts.gd")
const BoardView = preload("res://scripts/board/board_view.gd")
const CrewMember = preload("res://scripts/crew/crew_member.gd")
const Campaign = preload("res://scripts/space/campaign.gd")
const Shops = preload("res://scripts/space/shops.gd")
const Ship = preload("res://scripts/ship/ship.gd")
const Jobs = preload("res://scripts/crew/jobs.gd")
const Describe = preload("res://scripts/ui/describe.gd")
const Mortality = preload("res://scripts/crew/mortality.gd")
const Content = preload("res://scripts/data/content.gd")

const RUSTBUCKET := "res://data/ships/starter_rustbucket.json"


func _ship(rounds := 80) -> Ship:
	var s: Ship = Ship.from_design(RUSTBUCKET)
	Jobs.spawn_crew(s)
	s.crew.append(CrewMember.new("Rook", Vector2(10, 10), "human"))
	s.crew.append(CrewMember.new("Tess", Vector2(12, 10), "fenn"))
	s.inventory.add("hand_ammo", rounds - s.inventory.count("hand_ammo"))  # (a starter comes with some)
	return s


func _src(ship: Ship) -> CrewMember:
	for m in ship.crew:
		if m.is_player:
			return m
	return null


func _crew(ship: Ship, name: String) -> CrewMember:
	for m in ship.crew:
		if m.name == name:
			return m
	return null


## A visit to a station with nobody on it (no foes, no people), the soldier at the airlock.
func _visit(ship = null, seed_value := 31, kind := "station"):
	var sh = ship if ship != null else _ship()
	var s = Boarding.start(null, null, "k%d" % seed_value, {"kind": kind}, sh)
	s.site = Site.make(seed_value, kind, {"faction": "clans", "gen": "classic"})  # (the fights are staged on the classic bands; module stations: test_stations.gd)
	s.soldier.pos = s.site.airlock["spawn"]
	s.foes = Foes.new(s)
	s.foes.spawn_site({})
	s.foes.list.clear()
	s.foes.vents.clear()
	s.people.list.clear()
	s._arm()
	return s


## A direction from `from` with `len` clear cells and no cover on it.
func _free_dir(s, from: Vector2, len: float) -> float:
	for k in 32:
		var a := TAU * float(k) / 32.0
		var to := from + Vector2.from_angle(a) * len
		if s.site.clear_line(from, to) and s.site.cover_between(from, to) == 0:
			return a
	return NAN


## A foe of `kind` with a lot of health, standing at `at`.
func _foe(s, at: Vector2, kind := "pirate") -> Dictionary:
	var f: Dictionary = s.foes.add(kind, at, -1, false)
	f["m"].max_hp = 1000.0
	f["m"].hp = 1000.0
	return f


func _wear(s, items: Array, body := "") -> void:
	## the soldier of the visit wears mods and body gear (his kit is set on the copy the visit walks)
	var k := {"weapons": [s.soldier.sidearm(), ""], "body": body, "mods": ["", ""]}
	for i in items.size():
		k["mods"][i] = items[i]
	s.soldier.kit = k
	s._arm()


# --- the bolts ---------------------------------------------------------------------------------------------------------

func test_the_bolt_look_resolves_by_id_then_culture_then_class_then_default() -> void:
	var d := Bolts.look("no_such_weapon")
	eq(d, Bolts.cfg()["default"], "an unknown weapon looks like the default")
	var pistol := Bolts.look("service_pistol")  # concord culture, pistol class
	eq(pistol["color"], "#8fc8ff", "the Concord pistol is a blue-white laser (the culture's colour)")
	eq(float(pistol["len"]), 1.7, "the culture's length wins over the class's")
	eq(float(pistol["energy"]), float(Bolts.cfg()["default"]["energy"]), "what neither sets stays the default")
	var carbine := Bolts.look("carbine")
	eq(carbine["color"], pistol["color"], "the carbine is Concord blue too")
	eq(float(carbine["energy"]), 0.9, "and takes the rifle class's light")
	var flare := Bolts.look("flare_gun")  # clans culture, its own id on top
	eq([flare["kind"], flare["impact"], flare["sound"]], ["flare", "flare", "flare_pop"], "the flare gun is a flare, by its own id")
	eq(flare["color"], "#ff6a3a", "in the flare's own colour, not the clans' orange")
	eq(Bolts.look("doorbuster")["color"], "#ff9a3c", "a Clan gun with no entry of its own throws the clans' orange tracer")
	var lance := Bolts.look("gatekeepers_lance")
	eq([lance["kind"], float(lance["hold"])], ["beam", 0.15], "the lance is a beam held for 0.15 s")
	eq(Bolts.look("spark_pistol")["kind"], "arc", "the spark pistol throws an arc")
	eq(Bolts.look("torchgun")["kind"], "flame", "the torchgun is a flame")
	eq(Bolts.look("slugthrower")["color"], "#ffb02e", "the slugthrower fires a heavy amber tracer")
	eq(Bolts.look("quarry_hammer")["kind"], "swing", "a melee weapon is a swing (the class)")
	eq(float(Bolts.look("quarry_hammer")["energy"]), 0.0, "and gives no light")
	check(float(Bolts.look("slugthrower")["shake"]) > 0.0 and float(Bolts.look("service_pistol")["shake"]) == 0.0, "heavy weapons shake the screen a little, pistols do not")
	for w in Content.list("hand_weapons"):
		var l := Bolts.look(str(w["id"]))
		if l["kind"] != "swing":
			check(float(l["speed"]) >= 35.0 and float(l["speed"]) <= 60.0, "%s flies at 35-60 cells a second (%s)" % [w["id"], l["speed"]])
			check(float(l["light_r"]) > 0.0 and float(l["energy"]) > 0.0, "%s carries a light" % w["id"])
	var scav := Bolts.foe_look("scavenger")
	var pirate := Bolts.foe_look("pirate")
	var sentry := Bolts.foe_look("sentry")
	check(scav["color"] != pirate["color"] and pirate["color"] != sentry["color"] and scav["color"] != sentry["color"], "scavengers, pirates and sentries fire in three colours")
	eq(Bolts.foe_look("sentry", true, pirate)["color"], pirate["color"], "a hacked sentry fires in the colour of the soldier's weapon")
	var big := Bolts.look("service_pistol", 1.75)
	check(float(big["width"]) > float(pistol["width"]) and float(big["energy"]) > float(pistol["energy"]), "an Overcharge Coil makes a bolt wider and brighter")
	check(Bolts.travel(pistol, 11.6) > 0.15 and Bolts.travel(pistol, 11.6) < 0.25, "a bolt takes a fifth of a second to cross a room")
	eq(Bolts.travel(Bolts.look("quarry_hammer"), 3.0), 0.0, "a swing is there at once")


func test_a_shot_event_carries_the_bolt_and_the_hit_waits_for_it() -> void:
	var s = _visit()
	var from: Vector2 = s.soldier.pos
	var a := _free_dir(s, from, 7.0)
	check(not is_nan(a), "the airlock has an open line")
	var f := _foe(s, from + Vector2.from_angle(a) * 6.0)
	s.take_events()
	s.fire(a)
	var evs: Array = s.take_events()
	var shot: Dictionary = evs.filter(func(e): return e["type"] == "shot")[0]
	eq(shot["weapon"], "service_pistol", "the shot says which weapon")
	eq(shot["look"]["color"], "#8fc8ff", "and how it looks")
	check(float(shot["t"]) > 0.05 and float(shot["t"]) < 0.2, "and how long the bolt flies (%s)" % shot["t"])
	var hit: Dictionary = evs.filter(func(e): return e["type"] == "hit")[0]
	check(float(hit["delay"]) > 0.05 and absf(float(hit["delay"]) - float(shot["t"])) < 0.1, "the hit is shown when the bolt arrives (%s)" % hit["delay"])
	eq(hit["tint"], "#8fc8ff", "in the colour of the bolt")
	check(f["m"].hp < 1000.0, "while the logic hit at once")


func test_the_view_queues_hits_until_the_bolt_arrives_and_keeps_to_twelve_lights() -> void:
	var s = _visit()
	var b = BoardView.new()
	b.ask_party = false
	b.enter(s)
	var from: Vector2 = s.soldier.pos
	var a := _free_dir(s, from, 7.0)
	_foe(s, from + Vector2.from_angle(a) * 6.0)
	s.take_events()
	s.fire(a)
	b._play(s.take_events())
	check(b._later.any(func(q): return q["e"]["type"] == "hit"), "the hit waits in the view's queue")
	b.step(0.4)
	check(b._later.is_empty(), "and is played when it is time")
	# a crowd of shots: never more than 12 lights, the budget of the lights is the pool's
	for i in 40:
		b._play([{"type": "shot", "from": from, "to": from + Vector2(5, 0), "who": "foe", "class": "pistol", "kind": "wall", "look": Bolts.foe_look("pirate"), "t": 0.1, "weapon": ""}])
	check(b.fx.counts()["pool"] <= 12 and b.fx.lights_in_use() <= 12, "at most 12 bolt lights (%s)" % str(b.fx.counts()))
	b.step(0.05)
	for i in 30:
		b.step(0.05)
	eq(b.fx.counts()["bolts"], 0, "the bolts are spent")
	check(b.fx.scorch.size() > 0, "and a wall they hit is scorched")
	b.leave()


func test_a_flare_lights_its_radius_for_foe_sight_and_goes_out_after_six_seconds() -> void:
	var s = _visit()
	var rid := -1
	for r in s.site.rooms:
		if not r["corridor"] and r["purpose"] != "gone" and not s.foes._red.has(r["id"]) and r["rect"].size.x >= 7:
			rid = r["id"]
			break
	check(rid >= 0, "a room with no red light")
	var rect: Rect2i = s.site.rooms[rid]["rect"]
	var p := Vector2(rect.position) + Vector2(2.5, 2.5)
	var far := p + Vector2(5.0, 0.0)
	var dark := float(Site.config()["combat"]["sight"]["dark"])
	var red := float(Site.config()["combat"]["sight"]["red"])
	eq(s.foes._sight({"pos": p, "ref": null}, far), dark, "in the dark a foe sees %s cells" % dark)
	s._flare(p, 0.0)
	check(s.flare_lit(p) and s.flare_lit(p + Vector2(3.0, 0.0)), "the flare lights the spot and 3 cells round it")
	check(not s.flare_lit(far), "but not 5 cells off")
	eq(s.foes._sight({"pos": p + Vector2(2.0, 0.0), "ref": null}, far), red, "a target in its light is seen from as far as in an emergency light")
	eq(s.foes._sight({"pos": far, "ref": null}, far), dark, "one outside it is not")
	check(s.foes.lit(p), "and what is lit counts for the soldier's eyes too")
	s.take_events()
	s._tick_flares(5.9)
	check(s.flare_lit(p), "it still burns after 5.9 s")
	s._tick_flares(0.2)
	check(not s.flare_lit(p) and s.flares.is_empty(), "and is out after 6 s")
	eq(s.foes._sight({"pos": p, "ref": null}, far), dark, "the dark is back")
	check(s.take_events().any(func(e): return e["type"] == "flare_out"), "the view is told it went out")
	# a wall stops it
	var cell := Vector2i(-1, -1)
	for c in s.site.room_of:
		var w := Vector2i(c.x + 1, c.y)
		var f := Vector2i(c.x + 2, c.y)
		if s.site.room_of.has(c) and s.site.opaque(w) and s.site.room_of.has(f) and s.site.room_of[c] != s.site.room_of[f]:
			cell = c
			break
	check(cell.x >= 0, "two rooms with one wall between")
	var here := Vector2(cell) + Vector2(0.5, 0.5)
	var there := here + Vector2(2.0, 0.0)
	s._flare(here, 0.0)
	check(s.flare_lit(here) and not s.flare_lit(there), "a wall keeps the light of a flare in its room")


func test_only_the_flare_gun_leaves_a_flare_and_at_most_twelve_burn() -> void:
	var s = _visit()
	var from: Vector2 = s.soldier.pos
	var a := _free_dir(s, from, 7.0)
	s.guns = [Arms.make_gun("flare_gun", true)]
	s.cur = 0
	s.take_events()
	s.fire(a)
	eq(s.flares.size(), 1, "a flare gun leaves a flare where it lands")
	var ev: Array = s.take_events().filter(func(e): return e["type"] == "flare")
	check(not ev.is_empty() and float(ev[0]["delay"]) > 0.0, "the view is told, when it lands")
	check(s.flares[0]["pos"].distance_to(from) > 5.0, "at the end of the line")
	s.guns = [Arms.make_gun("service_pistol", true)]
	s.fire(a)
	eq(s.flares.size(), 1, "a pistol leaves none")
	# a scavenger's flare gun is a gun, not a flare
	var f := _foe(s, from + Vector2.from_angle(a) * 6.0, "scavenger")
	f["cd"] = 0.0
	s.foes._shoot(f, {"pos": from, "moving": false})
	eq(s.flares.size(), 1, "a scavenger's shot leaves none")
	for i in 20:
		s._flare(from + Vector2(float(i), 0.0), 0.0)
	eq(s.flares.size(), 12, "at most 12 burn: the oldest goes out")


# --- body gear and mods aboard ----------------------------------------------------------------------------------------------

func test_body_gear_takes_damage_off_aboard() -> void:
	var want := {"": 10.0, "basic_armor": 8.0, "exosuit": 6.5, "salamander_suit": 9.0, "eva_suit": 10.0, "heat_suit": 10.0}
	for body in want:
		var s = _visit()
		_wear(s, [], body)
		s.hurt_member(s.soldier, 10.0, Vector2.ZERO)
		check(absf((s.soldier.max_hp - s.soldier.hp) - float(want[body])) < 0.001, "%s: 10 damage costs %s (%s)" % [body if body != "" else "nothing", want[body], s.soldier.max_hp - s.soldier.hp])
	eq(Kit.body_line("eva_suit"), "Sealed: breathe with no air.", "an EVA suit takes no damage off but says it is sealed")
	eq(Kit.body_line("exosuit"), "Takes 35% less damage. Sealed.", "and an exosuit how much it takes off, and that it is sealed")


func test_overcharge_hits_harder_by_tier_and_mk3_goes_through_the_first_body() -> void:
	var base := 0.0
	for tier in 4:
		var s = _visit()
		_wear(s, [] if tier == 0 else [Mods.item_id("overcharge_coil", tier)])
		var from: Vector2 = s.soldier.pos
		var a := _free_dir(s, from, 7.0)
		var f := _foe(s, from + Vector2.from_angle(a) * 3.0)
		s.fire(a)
		var dealt: float = 1000.0 - f["m"].hp
		if tier == 0:
			base = dealt
			eq(base, 10.0, "a pistol hits for 10")
		else:
			check(absf(dealt - base * (1.0 + 0.15 * float(tier))) < 0.001, "Mk %d: +%d%% damage (%s)" % [tier, 15 * tier, dealt])
	for tier in [2, 3]:  # two foes in a line: only Mk III goes on to the second
		var s = _visit()
		_wear(s, [Mods.item_id("overcharge_coil", tier)])
		var from: Vector2 = s.soldier.pos
		var a := _free_dir(s, from, 6.5)
		check(not is_nan(a), "a clear line of 6 cells")
		var f1 := _foe(s, from + Vector2.from_angle(a) * 2.5)
		var f2 := _foe(s, from + Vector2.from_angle(a) * 4.5)
		s.take_events()
		s.fire(a)
		check(f1["m"].hp < 1000.0, "Mk %d: the first is hit" % tier)
		eq(f2["m"].hp < 1000.0, tier == 3, "Mk %d: the second %s" % [tier, "is hit too" if tier == 3 else "is not"])
		var shot: Dictionary = s.take_events().filter(func(e): return e["type"] == "shot")[0]
		check(float(shot["look"]["width"]) > Bolts.look("service_pistol")["width"], "and the bolt is wider")
	# melee: damage only
	var s2 = _visit()
	_wear(s2, [Mods.item_id("overcharge_coil", 3)])
	s2.guns = [Arms.make_gun("quarry_hammer", true)]
	s2.cur = 0
	var f3 := _foe(s2, s2.soldier.pos + Vector2(1.6, 0.0))
	s2.fire(0.0)
	check(absf((1000.0 - f3["m"].hp) - 30.0 * 1.45) < 0.001, "a hammer hits for 43.5 (%s)" % (1000.0 - f3["m"].hp))
	# only the wearer's: a follower with no coil does the plain damage
	var sh := _ship()
	var s3 = _visit(sh)
	_wear(s3, [Mods.item_id("overcharge_coil", 3)])
	eq(Mods.damage_mult(s3.soldier), 1.45, "the wearer")
	eq(Mods.damage_mult(_crew(sh, "Rook")), 1.0, "and nobody else")


func test_the_salvage_rig_adds_to_resources_only_by_tier_and_is_deterministic() -> void:
	var items := {"scrap": 10, "copper": 6, "titanium": 2, "hand_ammo": 8, "credits": 20, "rifle": 1, "missile": 2, "radiator": 1, "fuel": 1}
	var sums := {}
	var n := 400
	for tier in [1, 2, 3]:
		var total := 0.0
		for seed_value in n:
			var rng := RandomNumberGenerator.new()
			rng.seed = seed_value
			var b := Mods.salvage(items, tier, rng)
			for id in ["rifle", "missile", "radiator", "fuel"]:
				check(not b.has(id), "Mk %d: %s is never multiplied" % [tier, id])
			total += float(b.get("scrap", 0)) + float(b.get("hand_ammo", 0)) + float(b.get("credits", 0))
		sums[tier] = total / float(n) / 38.0
	check(absf(sums[1] - 0.25) < 0.03, "Mk I adds about 25%% of a stack (%.3f)" % sums[1])
	check(absf(sums[2] - 0.5) < 0.03, "Mk II adds about 50%% (%.3f)" % sums[2])
	check(absf(sums[3] - 1.0) < 0.03, "Mk III doubles it (%.3f)" % sums[3])
	var extra := 0
	for seed_value in 900:
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value
		var b := Mods.salvage({"scrap": 4}, 3, rng)
		for k in b:
			if k in Mods.def("salvage_rig")["rare"]:
				extra += 1
	check(extra > 250 and extra < 350, "Mk III adds a rare material to about 1 container in 3 (%d of 900)" % extra)
	var r1 := RandomNumberGenerator.new()
	var r2 := RandomNumberGenerator.new()
	r1.seed = 5
	r2.seed = 5
	eq(Mods.salvage(items, 3, r1), Mods.salvage(items, 3, r2), "the same seed gives the same bonus")
	eq(Mods.salvage(items, 0, r1), {}, "without a rig nothing is added")
	check(not Mods.is_resource("rifle") and not Mods.is_resource("missile") and Mods.is_resource("scrap") and Mods.is_resource("credits") and Mods.is_resource("hand_ammo"), "materials, rounds and credits are resources, guns and parts are not")


func test_an_opened_container_shows_the_rigs_share_and_the_best_rig_counts_once() -> void:
	var sh := _ship()
	var s = _visit(sh)
	var plain = _visit(_ship())
	var id := -1
	for c in s.site.containers():
		if Loot.resolve(s.site, c, {"tier": 1, "stage": 1})["items"].keys().any(func(k): return Mods.is_resource(str(k))):
			id = c
			break
	var base: Dictionary = plain.open(id)["items"].duplicate()
	_wear(s, [Mods.item_id("salvage_rig", 3)])
	var got: Dictionary = s.open(id)
	var rows: Array = s.entries(id)
	var bonus := 0
	for r in rows:
		if r.has("bonus"):
			bonus += 1
			check(str(r["bonus"]).begins_with("+"), "the row says what the rig added: %s" % r["bonus"])
			eq(r["color"], Mods.color("salvage_rig"), "in the mod's colour")
	check(bonus >= 1, "the list shows a bonus row")
	for item in base:
		if Mods.is_resource(str(item)):
			check(int(got["items"][item]) >= int(base[item]) * 2, "Mk III at least doubles %s (%d then %d)" % [item, base[item], got["items"][item]])
		else:
			eq(got["items"][item], base[item], "%s is not multiplied" % item)
	# the same container in another visit gives the same
	var again = _visit(_ship())
	_wear(again, [Mods.item_id("salvage_rig", 3)])
	eq(again.open(id)["items"], got["items"], "the same container gives the same with the same rig")
	# taking the stack takes the bonus with it
	var key: String = str(rows[0]["key"])
	var before: int = sh.inventory.count(key.trim_prefix("item:"))
	s.take(id, key)
	check(sh.inventory.count(key.trim_prefix("item:")) - before >= int(base.get(key.trim_prefix("item:"), 0)), "the stack comes with its bonus")
	check(not s.left.has(id) or not s.left[id].get("bonus", {}).has(key.trim_prefix("item:")), "and the bonus is spent")
	# no stacking: the best rig in the party counts
	var party = _visit(_ship())
	party.party = [{"m": CrewMember.new("A", Vector2.ZERO), "src": null, "temp": false}, {"m": CrewMember.new("B", Vector2.ZERO), "src": null, "temp": false}]
	party.party[0]["m"].kit = {"weapons": [], "body": "", "mods": ["salvage_rig_mk1", ""]}
	party.party[1]["m"].kit = {"weapons": [], "body": "", "mods": ["salvage_rig_mk2", ""]}
	party.soldier.kit = {"weapons": [], "body": "", "mods": ["salvage_rig_mk1", "spotter_cam_mk1"]}
	eq(Mods.party_tier(party, "salvage_rig"), 2, "three rigs in the party: the best one, Mk II, counts")
	eq(Mods.party_tier(party, "spotter_cam"), 1, "and the cam of the soldier is the party's")
	party.party[0]["temp"] = true
	party.party[0]["m"].kit = {"weapons": [], "body": "", "mods": ["salvage_rig_mk3", ""]}
	eq(Mods.party_tier(party, "salvage_rig"), 2, "a person met aboard wears nothing that counts")


func test_the_spotter_cam_shows_rooms_by_depth_and_mk2_pings_still_foes() -> void:
	var s = _visit(null, 31)
	var site = s.site
	# rooms_near is a walk over the doors
	var any_two := false
	for r in site.rooms:
		if r["purpose"] == "gone":
			continue
		var one: Array = site.rooms_near(r["id"], 1)
		var by_hand := {}
		for did in r["doors"]:
			var d: Dictionary = site.doors[did]
			if d["lock"] == "gone":
				continue
			for x in d["rooms"]:
				if x != r["id"]:
					by_hand[x] = true
		var want: Array = by_hand.keys()
		want.sort()
		eq(one, want, "room %d: depth 1 is the rooms its doors join" % r["id"])
		check(not one.has(r["id"]), "and not the room itself")
		var two: Array = site.rooms_near(r["id"], 2)
		check(one.all(func(x): return two.has(x)) and two.size() >= one.size(), "depth 2 holds depth 1")
		if two.size() > one.size():
			any_two = true
		eq(site.rooms_near(r["id"], 0), [], "depth 0 shows nothing")
	check(any_two, "some room has a room two doors off")
	# the tracker rule
	var start: int = site.room_at(s.soldier.pos)
	var near: Array = site.rooms_near(start, 1)
	var far: Array = site.rooms_near(start, 2).filter(func(x): return not near.has(x))
	check(not near.is_empty() and not far.is_empty(), "the airlock room has a room next door and one beyond")
	var in_near: int = near[0]
	var in_far: int = far[0]
	var f1 := _foe(s, Vector2(site.rooms[in_near]["rect"].position) + Vector2(site.rooms[in_near]["rect"].size) / 2.0)
	var f2 := _foe(s, Vector2(site.rooms[in_far]["rect"].position) + Vector2(site.rooms[in_far]["rect"].size) / 2.0)
	var moving := func(f: Dictionary) -> Variant:
		for c in s.contacts():
			if c["pos"] == f["m"].pos:
				return c["moving"]
		return null
	s.tick(0.05)
	eq(moving.call(f1), false, "without a cam a still foe does not ping")
	for tier in [1, 2, 3]:
		_wear(s, [Mods.item_id("spotter_cam", tier)])
		s.tick(0.05)
		eq(s.spotted, site.rooms_near(start, 1 if tier < 3 else 2), "Mk %d shows %s door(s) deep" % [tier, "1" if tier < 3 else "2"])
		eq(moving.call(f1), tier >= 2, "Mk %d: a still foe next door %s" % [tier, "pings the tracker" if tier >= 2 else "stays quiet"])
		eq(moving.call(f2), tier == 3, "Mk %d: a still foe two doors off %s" % [tier, "pings" if tier == 3 else "stays quiet"])
	_wear(s, [])
	s.tick(0.05)
	eq(s.spotted, [], "without the cam nothing is shown")
	check(Mods.numbers("spotter_cam", 2)["glow"] > Mods.numbers("spotter_cam", 1)["glow"], "Mk II is brighter than Mk I")
	# a camera is not a lamp: it changes what foes see by nothing
	var dark := float(Site.config()["combat"]["sight"]["dark"])
	_wear(s, [Mods.item_id("spotter_cam", 3)])
	s.tick(0.05)
	eq(s.foes._sight({"pos": Vector2(site.rooms[in_near]["rect"].position) + Vector2(2.5, 2.5), "ref": null}, Vector2.ZERO), dark if not s.foes._red.has(in_near) else float(Site.config()["combat"]["sight"]["red"]), "foes do not see better for it")


# --- loadouts -----------------------------------------------------------------------------------------------------------------

func test_equipping_moves_items_out_of_the_hold_and_taking_them_off_puts_them_back() -> void:
	var sh := _ship()
	for item in ["basic_armor", "exosuit", "rifle", "overcharge_coil_mk2", "spotter_cam_mk1"]:
		sh.inventory.add(item, 1)
	var m := _src(sh)
	eq(Kit.set_body(sh, m, "basic_armor"), "", "armour goes on")
	eq(sh.inventory.count("basic_armor"), 0, "and leaves the hold")
	eq(Kit.set_body(sh, m, "exosuit"), "", "another suit replaces it")
	eq([sh.inventory.count("basic_armor"), sh.inventory.count("exosuit")], [1, 0], "the first goes back, the second leaves")
	eq(Kit.set_body(sh, m, ""), "", "taken off")
	eq(sh.inventory.count("exosuit"), 1, "it is back in the hold")
	eq(Kit.set_weapon(sh, m, 1, "carbine"), "", "a rifle in the second hand (the hold's rifle item is the carbine)")
	eq(sh.inventory.count("rifle"), 0, "it leaves the hold")
	eq(Kit.set_weapon(sh, m, 0, "service_pistol"), "", "his own sidearm needs no item")
	eq(Kit.set_weapon(sh, m, 1, ""), "", "and the rifle comes off")
	eq(sh.inventory.count("rifle"), 1, "back to the hold")
	eq(Kit.set_mod(sh, m, 0, "overcharge_coil_mk2"), "", "a mod goes in a slot")
	eq(sh.inventory.count("overcharge_coil_mk2"), 0, "and leaves the hold")
	check(Kit.set_mod(sh, m, 1, "overcharge_coil_mk2") != "", "the hold has no second one")
	sh.inventory.add("overcharge_coil_mk1", 1)
	check(Kit.set_mod(sh, m, 1, "overcharge_coil_mk1").contains("Already"), "one Overcharge Coil each: they do not stack on a person")
	eq(Kit.set_mod(sh, m, 1, "spotter_cam_mk1"), "", "another mod goes in the other slot")
	check(Kit.set_weapon(sh, m, 1, "carbine") == "" and Kit.set_weapon(sh, m, 0, "carbine").contains("Already"), "the same weapon cannot be in both hands")
	check(Kit.set_weapon(sh, m, 1, "slugthrower") != "", "a weapon the hold lacks is refused")
	Kit.strip(sh, m)
	eq([sh.inventory.count("rifle"), sh.inventory.count("overcharge_coil_mk2"), sh.inventory.count("spotter_cam_mk1")], [1, 1, 1], "stripped: everything is back in the hold")
	eq(m.kit, {}, "and the kit is empty")


func test_a_person_who_cannot_wear_a_suit_is_refused_with_the_reason() -> void:
	var sh := _ship()
	sh.inventory.add("exosuit", 1)
	var q := CrewMember.new("Vik", Vector2(14, 10), "quillback")
	sh.crew.append(q)
	var why := Kit.set_body(sh, q, "exosuit")
	check(why.contains("cannot wear a suit or armour"), "no_suit says why: %s" % why)
	eq(sh.inventory.count("exosuit"), 1, "the suit stays in the hold")
	eq(str(q.kit.get("body", "")), "", "and is not worn")
	var opts := Kit.options(sh, q, "body", 0)
	check(opts.any(func(o): return o["id"] == "exosuit" and o["why"] != ""), "the loadout screen lists it with a reason")
	eq(Kit.set_body(sh, _src(sh), "exosuit"), "", "anyone else may wear it")
	check(Kit.set_body(sh, _src(sh), "pistol") != "", "gear that is not body gear is refused")


func test_a_kit_is_saved_with_the_person_and_old_saves_load_with_none() -> void:
	var sh := _ship()
	sh.inventory.add("basic_armor", 1)
	sh.inventory.add("spotter_cam_mk2", 1)
	var m := _src(sh)
	Kit.set_body(sh, m, "basic_armor")
	Kit.set_mod(sh, m, 1, "spotter_cam_mk2")
	var d := m.to_dict()
	var back: CrewMember = CrewMember.from_dict(JSON.parse_string(JSON.stringify(d)))
	eq(back.kit, m.kit, "the kit comes back through JSON")
	eq(Kit.of(back)["mods"], ["", "spotter_cam_mk2"], "slot by slot")
	var old := d.duplicate(true)
	old.erase("kit")
	var o: CrewMember = CrewMember.from_dict(old)
	eq(o.kit, {}, "an old save has an empty kit")
	eq(Kit.weapons_of(o), [o.sidearm()], "and he carries his sidearm")
	var plain := CrewMember.new("Plain", Vector2.ZERO).to_dict()
	check(not plain.has("kit"), "a person with no kit adds nothing to a save")
	# a ship saved and loaded keeps what its crew wear
	var sh2: Ship = Ship.from_design(RUSTBUCKET)
	eq(sh2.load_dict(JSON.parse_string(JSON.stringify(sh.to_dict()))), "", "the ship loads")
	check(_src(sh2) != null and _src(sh2).kit == m.kit, "the ship's save keeps the kit of its soldier")


func test_the_kit_arms_the_soldier_and_the_follower_fights_with_the_first_weapon() -> void:
	var sh := _ship()
	sh.inventory.add("rifle", 1)
	var src := _src(sh)
	Kit.set_weapon(sh, src, 1, "carbine")
	var s = _visit(sh)
	s.rearm(src)
	eq(s.guns.map(func(g): return g["id"]), ["service_pistol", "carbine"], "his kit is what he carries, in the order of the slots")
	eq(s.guns[1]["mag"], 20, "loaded from the hold's rounds")
	# the second slot empty: just the sidearm
	Kit.set_weapon(sh, src, 1, "")
	s.rearm(src)
	eq(s.guns.map(func(g): return g["id"]), ["service_pistol"], "an empty slot is an empty hand")
	# a follower
	var tess := _crew(sh, "Tess")
	sh.inventory.add("rifle", 1)
	Kit.set_weapon(sh, tess, 0, "carbine")
	var s2 = _visit(sh)
	s2.join_party(["Tess"])
	eq(s2.party[0]["gun"]["id"], "carbine", "a follower fights with the first weapon of their kit")
	eq(s2.party[0]["m"].kit, tess.kit, "and the copy that walks carries the kit")
	# nothing set: as before B4
	var plain = _visit(_ship())
	plain.soldier.kit = {}
	plain._arm()
	eq(plain.guns[0]["id"], "service_pistol", "with no kit: the sidearm, as before")


func test_a_crew_member_lost_aboard_takes_the_kit_with_them_and_the_confirm_says_so() -> void:
	var sh := _ship()
	sh.inventory.add("exosuit", 1)
	sh.inventory.add("overcharge_coil_mk1", 1)
	var rook := _crew(sh, "Rook")
	Kit.set_body(sh, rook, "exosuit")
	Kit.set_mod(sh, rook, 0, "overcharge_coil_mk1")
	var s = _visit(sh)
	s.join_party(["Rook"])
	var text: String = s.lost_kit("Rook")
	check(text.contains("Exosuit") and text.contains("Overcharge Coil Mk I"), "the visit knows what Rook carries: %s" % text)
	eq(s.lost_kit("Tess"), "", "and that Tess carries nothing")
	var b = BoardView.new()
	b.ask_party = false
	b.enter(s)
	check(b.lost_note(["Rook"]).contains("kit") and b.lost_note(["Rook"]).contains("Exosuit"), "the leave confirm names the kit: %s" % b.lost_note(["Rook"]))
	eq(b.lost_note(["Tess"]), "", "nothing to say for a bare sidearm")
	s.party[0]["m"].hp = 0.0
	var res: Dictionary = s.leave()
	eq(res["lost"], ["Rook"], "Rook is lost")
	check(not sh.crew.has(rook), "gone from the crew")
	eq([sh.inventory.count("exosuit"), sh.inventory.count("overcharge_coil_mk1")], [0, 0], "and the kit with them: nothing goes back to the hold")
	# one who comes home keeps it
	var sh2 := _ship()
	sh2.inventory.add("basic_armor", 1)
	var tess := _crew(sh2, "Tess")
	Kit.set_body(sh2, tess, "basic_armor")
	var s2 = _visit(sh2)
	s2.join_party(["Tess"])
	s2.leave()
	eq(tess.kit["body"], "basic_armor", "a crew member who comes home still wears it")
	eq(sh2.inventory.count("basic_armor"), 0, "and the hold does not have it")
	b.leave()


func test_a_crew_member_who_dies_anywhere_but_aboard_leaves_their_kit_in_the_hold() -> void:
	var sh := _ship()
	for item in ["exosuit", "overcharge_coil_mk1", "rifle"]:
		sh.inventory.add(item, 1)
	var rook := _crew(sh, "Rook")
	Kit.set_body(sh, rook, "exosuit")
	Kit.set_mod(sh, rook, 0, "overcharge_coil_mk1")
	Kit.set_weapon(sh, rook, 1, "carbine")
	eq([sh.inventory.count("exosuit"), sh.inventory.count("overcharge_coil_mk1"), sh.inventory.count("rifle")], [0, 0, 0], "worn: the hold has none of it")
	# bleeding out on the ship
	rook.pos = Vector2(0.5, 0.5)
	rook.hp = 0.0
	rook.down_t = Mortality.bleed_out_s()
	var tess := _crew(sh, "Tess")
	tess.pos = Vector2(1.5, 0.5)
	tess.hp = 0.0
	tess.down_t = Mortality.bleed_out_s()
	var lines := Mortality.tick(sh, 0.1)
	check(lines.has("Rook has died."), "Rook bled out")
	check(lines.has("Rook's kit is back in the hold."), "and the chronicle says the kit is back: %s" % str(lines))
	check(not lines.any(func(l): return str(l).begins_with("Tess's kit")), "Tess carried nothing but a sidearm: no line for her")
	check(not sh.crew.has(rook) and sh.dead_crew.has("Rook"), "he is gone from the crew")
	eq([sh.inventory.count("exosuit"), sh.inventory.count("overcharge_coil_mk1"), sh.inventory.count("rifle")], [1, 1, 1], "the exosuit, the coil and the rifle are in the hold again")
	# an event that takes a crew member
	var sh2 := _ship()
	sh2.crew.erase(_crew(sh2, "Tess"))
	sh2.inventory.add("basic_armor", 1)
	var vik := _crew(sh2, "Rook")
	Kit.set_body(sh2, vik, "basic_armor")
	var c := Campaign.new(5)
	var said := []
	eq(c.lose_crew(sh2, said), "Rook", "the event takes Rook")
	eq(said, ["Rook's kit is back in the hold."], "and says the kit is back")
	eq(sh2.inventory.count("basic_armor"), 1, "in the hold")
	# lost aboard a site: the kit goes with them (the leave test above), whatever the kit
	var sh3 := _ship()
	sh3.inventory.add("exosuit", 1)
	var lost := _crew(sh3, "Rook")
	Kit.set_body(sh3, lost, "exosuit")
	Mortality.lose(sh3, lost)
	eq(sh3.inventory.count("exosuit"), 0, "lost aboard a site: the kit is lost with them")


func test_the_loadout_screen_sets_kits_before_going_aboard() -> void:
	var sh := _ship()
	for item in ["basic_armor", "overcharge_coil_mk2", "spotter_cam_mk1", "salvage_rig_mk3"]:
		sh.inventory.add(item, 1)
	sh.inventory.add("exosuit", 1)
	var s = _visit(sh)
	var b = BoardView.new()
	b.ask_party = true
	b.enter(s)
	check(b.picking, "the screen opens for a crew to take")
	var src := _src(sh)
	eq(Kit.slot_value(src, "weapon", 0), "service_pistol", "the soldier starts with his sidearm")
	b.toggle_pick(0)
	eq(b.loadout_people().map(func(m): return m.name), [src.name, "Rook"], "the people it sets: the soldier, then who is picked")
	b.loadout_focus(0)
	b.loadout_open("mod", 0)
	var names: Array = b.loadout_options().map(func(o): return o["name"])
	check(names.has("Overcharge Coil Mk II") and names.has("Salvage Rig Mk III") and names.has("Spotter Cam Mk I"), "a mod slot lists the mods the hold has: %s" % str(names))
	eq(b.loadout_choose(names.find("Overcharge Coil Mk II")), "", "and takes one")
	eq(sh.inventory.count("overcharge_coil_mk2"), 0, "it leaves the hold")
	b.loadout_focus(1)
	b.loadout_open("body", 0)
	eq(b.loadout_choose(1) == "", true, "Rook puts armour on")
	b.confirm_party()
	check(not b.picking, "going aboard closes it")
	eq(Mods.self_tier(s.soldier, "overcharge_coil"), 2, "the soldier of the visit wears what was set")
	check(s.guns.size() >= 1 and Mods.damage_mult(s.soldier) > 1.0, "and shoots with it")
	eq(s.party[0]["m"].kit["body"], "basic_armor", "and the crew mate carries his")
	b.leave()
	# nobody to take and nothing in the hold to wear: the screen still opens (it is how you choose to go alone)
	var bare := _ship()
	for m in bare.crew:
		if not m.is_player:
			m.post = 0
	var s2 = _visit(bare)
	var b2 = BoardView.new()
	b2.ask_party = true
	b2.enter(s2)
	check(b2.picking and b2.pick_rows().is_empty(), "with nobody to take the screen still opens, with nobody on it")
	b2.go_alone()
	check(not b2.picking, "going alone closes it")
	b2.leave()


# --- where mods come from ----------------------------------------------------------------------------------------------------

func test_mods_drop_at_about_one_and_a_half_per_station_and_mk3_comes_late_and_from_stations() -> void:
	var mods := 0
	var stations := 60
	for sd in stations:
		var site = Site.make(500 + sd, "station", {"faction": "clans"})
		for id in site.containers():
			var r := Loot.resolve(site, id, {"tier": 1, "stage": 2})
			for item in r["items"]:
				if Mods.is_item(str(item)):
					mods += int(r["items"][item])
					check(Mods.parse(str(item))["tier"] <= 2, "no Mk III before stage 4")
	var rate := float(mods) / float(stations)
	check(rate > 0.8 and rate < 2.2, "about one and a half mods per early station, lockers and cabinets included (%.2f a station)" % rate)
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var tiers := {}
	for stage in [1, 3, 4, 6, 8]:
		for kind in ["station", "nest", "derelict", "wreck"]:
			var t3 := 0
			for i in 1500:
				var item := Mods.roll_drop(kind, stage, rng)
				check(Mods.is_item(item), "a drop is a mod item")
				if str(Mods.parse(item)["tier"]) == "3":
					t3 += 1
			tiers["%d %s" % [stage, kind]] = t3
			if kind != "station" or stage < 4:
				eq(t3, 0, "stage %d %s: no Mk III" % [stage, kind])
	check(tiers["6 station"] > 200 and tiers["6 station"] < 400 and tiers["4 station"] > 60 and tiers["4 station"] < 230, "Mk III is rarer at stage 4 than at 6 (%s, %s of 1500)" % [tiers["4 station"], tiers["6 station"]])
	# a run: one station in each of stages 4 to 8 gives about one run in three a Mk III (lockers and cabinets give Mk I and II only)
	var per_run := 0.0
	for stage in range(4, 9):
		var t3_found := 0
		for sd in stations:
			var site = Site.make(500 + sd, "station", {"faction": "clans"})
			for id in site.containers():
				for item in Loot.resolve(site, id, {"tier": 1, "stage": stage})["items"]:
					if Mods.is_item(str(item)) and int(Mods.parse(str(item))["tier"]) == 3:
						t3_found += 1
		per_run += float(t3_found) / float(stations)
	var chance := 1.0 - exp(-per_run)
	check(chance > 0.22 and chance < 0.45, "about one run in three finds a Mk III (%.0f%%)" % (chance * 100.0))
	# every kind of mod comes up
	var seen := {}
	for i in 600:
		seen[Mods.parse(Mods.roll_drop("station", 6, rng))["mod"]] = true
	eq(seen.size(), 3, "all three mods drop")
	# the nest stash, a command room and an engineering room carry the outcome; the others do not
	var tables: Dictionary = Site.config()["tables"]
	for room in ["command", "engineering"]:
		check(tables[room].any(func(o): return o["item"] == "mod"), "%s rooms can hold a mod" % room)
	check(Site.config()["kinds"]["nest"]["bonus"].any(func(o): return o["item"] == "mod"), "a nest's stashes can")
	check(not tables["quarters"].any(func(o): return o["item"] == "mod"), "quarters cannot")


func test_a_person_aboard_who_trades_may_carry_a_mod_and_the_small_shops_sell_them() -> void:
	var cfg := Campaign.config()
	var in_shop := 0
	var priced := true
	for sd in 400:
		var r := Shops.roll(cfg, sd, "n%d" % sd, "boneyard", [])
		for id in r["unique"]:
			if Mods.is_item(str(id)):
				in_shop += 1
				priced = priced and int(r["stock"][id]) == int(cfg["shops"]["mods"][id])
				eq(int(r["qty"][id]), 1, "one on the shelf")
	check(in_shop >= 10 and in_shop < 220, "the small shops roll the mod kind now and then (%d in 400 shops)" % in_shop)
	check(priced, "and price them by tier")
	var pool: Dictionary = Shops.unique_pool(cfg, [])
	check(pool.has("mod") and pool.has("mod1") and pool["mod"].size() + pool["mod1"].size() == 9, "the mod kinds have all nine items between them (Mk I apart)")
	check(int(cfg["shops"]["mods"]["salvage_rig_mk3"]) > int(cfg["shops"]["mods"]["salvage_rig_mk2"]) and int(cfg["shops"]["mods"]["salvage_rig_mk2"]) > int(cfg["shops"]["mods"]["salvage_rig_mk1"]), "a higher tier costs more")
	eq(float(cfg["shops"]["kinds"]["mod"]), 1.0, "the kind has weight 1")
	# a trader's goods can include one (the room tables carry the outcome)
	var found := 0
	for sd in 120:
		var s = _visit(null, 600 + sd)
		for room in s.site.rooms:
			if room["purpose"] in ["command", "engineering"]:
				var n := {"id": 1, "room": room["id"]}
				for row in s.people.roll_shop(n):
					if Mods.is_item(str(row["item"])):
						found += 1
						check(int(row["price"]) > 0 and int(row["n"]) == 1, "a mod for sale: one, at a price")
	check(found > 0, "a trader aboard carries a mod now and then (%d)" % found)


# --- what they say --------------------------------------------------------------------------------------------------------------

func test_a_mod_item_describes_itself_and_has_a_hover() -> void:
	var sh := _ship()
	for id in Mods.ids():
		for tier in [1, 2, 3]:
			var item := Mods.item_id(id, tier)
			var d := Describe.of(item, sh)
			check(d["what"] != "" and d["what"] == Mods.def(id)["does"], "%s says what it does" % item)
			check(d["keywords"].any(func(k): return k["id"] == "mod"), "%s carries the MOD keyword" % item)
			check(d["stats"].size() == 2 and d["stats"][0][1] != "", "%s shows the numbers of its tier: %s" % [item, str(d["stats"])])
			var h := Mods.hover(item)
			check(h.size() == 3 and str(h[1]).begins_with(Mods.config()["tier_names"][tier - 1]), "%s hovers with its tier line: %s" % [item, str(h)])
			eq(Mods.label(item), "%s %s" % [Mods.def(id)["name"], Mods.config()["tier_names"][tier - 1]], "its name")
	eq(Describe.keyword("mod")["label"], "MOD", "mod is a coloured keyword")
	check(Describe.data()["items"]["mod"].contains("kit slot"), "and an item kind with a line")
