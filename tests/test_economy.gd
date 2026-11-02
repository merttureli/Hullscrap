extends "res://tests/base_test.gd"
## Playtest 2, the economy round: rare debris (data/debris.json `rare` types, drift_debris.gd, radar.gd), fuel that is scarce
## (stations, stocks, trader events) and the small shops of the traders (shops.gd). Fuel numbers: tests/tool_fuel_rate.gd.

const DriftDebris = preload("res://scripts/space/drift_debris.gd")
const Radar = preload("res://scripts/space/radar.gd")
const Content = preload("res://scripts/data/content.gd")
const Wall = preload("res://tests/fixture_wall.gd")

const RARE: Array[String] = ["crystal_shard", "titanium_plate", "silicon_wafer"]


func near(got: float, want: float, msg: String, eps := 1e-3) -> void:
	check(absf(got - want) <= eps, "%s: expected %s, got %s" % [msg, str(want), str(got)])


## A spawner with the file's numbers and a still, northerly current (so pieces are easy to place).
func _dd(seed_value := 1) -> DriftDebris:
	var cfg: Dictionary = Content.read(DriftDebris.PATH).duplicate(true)
	cfg["current"]["angle"] = 90
	cfg["current"]["wobble_deg"] = 0
	cfg["current"]["speed_wobble"] = 0
	return DriftDebris.new(seed_value, cfg)


# --- rare debris -------------------------------------------------------------------------------------------

func test_rare_types_are_in_the_data_and_very_rare() -> void:
	var d := _dd()
	var weights := {}
	var total := 0.0
	for t in d.types:
		weights[str(t["id"])] = float(t["weight"])
		total += float(t["weight"])
	for id in RARE:
		check(weights.has(id), "%s is a debris type" % id)
		check(weights.get(id, 99.0) <= 0.5 and weights.get(id, 0.0) > 0.0, "%s is very rare (weight %s, scrap is 40)" % [id, str(weights.get(id))])
		check(bool(d.type_of({"type": id}).get("rare", false)), "%s is flagged rare" % id)
	eq(RARE.map(func(id): return int(d.type_of({"type": id})["yield"].values()[0])), [2, 3, 2], "what each gives: crystal 2, titanium 3, silicon 2")
	eq(RARE.map(func(id): return d.type_of({"type": id})["yield"].keys()[0]), ["crystal", "titanium", "silicon"], "and which material")
	near(float(weights["fuel_canister"]), 0.5, "fuel is a rare find too (down from 3)")
	check(total > 80.0 and total < 100.0, "the flow is still mostly scrap, copper and polymer (total weight %s)" % str(total))


func test_rare_pieces_spawn_about_their_weight_share() -> void:
	var ship := Wall.wall_ship(1, 0)
	var d := _dd(7)
	var n := 40000
	var seen := {}
	var total := 0.0
	for t in d.types:
		total += float(t["weight"])
	for i in n:
		d.pieces.clear()
		var p := d._spawn(ship)
		seen[p["type"]] = int(seen.get(p["type"], 0)) + 1
	for id in RARE:
		var want := float(d.type_of({"type": id})["weight"]) / total
		var got := float(seen.get(id, 0)) / n
		check(got > want * 0.7 and got < want * 1.3, "%s is %.3f%% of the flow, want about %.3f%%" % [id, got * 100.0, want * 100.0])
	check(not seen.has("ice_chunk_s"), "no ice")


func test_the_radar_lists_rare_pieces_within_range() -> void:
	var d := _dd()
	var here := Vector2(1000.0, 1000.0)
	d.add_piece("crystal_shard", here + Vector2(0.0, -800.0), Vector2.ZERO)  # due north
	d.add_piece("scrap_chunk_s", here + Vector2(100.0, 0.0), Vector2.ZERO)
	d.add_piece("titanium_plate", here + Vector2(2500.0, 0.0), Vector2.ZERO)
	var near_list := Radar.rare_pieces(d, here, 1500.0)
	eq(near_list.map(func(r): return r["type"]), ["crystal_shard"], "one rare piece in 1,500 px; scrap is no rare piece, titanium is too far")
	near(float(near_list[0]["bearing"]), 0.0, "straight up is bearing 0")
	near(float(near_list[0]["distance"]), 800.0, "the distance")
	var far_list := Radar.rare_pieces(d, here, 3000.0)
	eq(far_list.map(func(r): return r["type"]), ["crystal_shard", "titanium_plate"], "a 3,000 px radar sees both, nearest first")
	near(float(far_list[1]["bearing"]), PI / 2.0, "east is a quarter turn clockwise")
	eq(Radar.rare_pieces(null, here, 3000.0), [], "no debris, no list")


func test_a_rare_piece_announces_itself_once_when_it_comes_into_view() -> void:
	var ship := Wall.wall_ship(1, 0)
	var d := _dd()
	d.view_centre = Vector2.ZERO
	d.view_half = Vector2(800.0, 450.0)
	var p := d.add_piece("crystal_shard", Vector2(3000.0, 0.0), Vector2.ZERO)
	d._note_rare()
	eq(d.take_events(), [], "out of view: nothing yet")
	p["pos"] = Vector2(100.0, 100.0)
	d._note_rare()
	d._note_rare()
	var ev := d.take_events()
	eq(ev.map(func(e): return [e["kind"], e["text"]]), [["rare", "Rare drift: crystal shard"]], "once, with its name")
	d.add_piece("scrap_chunk_s", Vector2(50.0, 50.0), Vector2.ZERO)
	d._note_rare()
	eq(d.take_events(), [], "ordinary debris says nothing")
	check(ship != null, "fixture")


func test_collecting_a_rare_piece_gives_its_material() -> void:
	var ship := Wall.wall_ship(1, 0)
	var d := _dd()
	var before := ship.inventory.count("crystal")
	var t := d.type_of({"type": "crystal_shard"})
	check(d._store(ship, t, d._gains(t, ship)), "the hold takes it")
	eq(ship.inventory.count("crystal"), before + 2, "crystal 2")
	check(d.hud_line().contains("+2 crystal"), "the HUD lists it: " + d.hud_line())
