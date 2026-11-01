extends "res://tests/base_test.gd"
## Debris drifting past the ship (scripts/space/drift_debris.gd, view and mode gate in scripts/view/debris_view.gd):
## the seeded spawner and its cap, the current, collecting at an intake's mouth (the yield, a crate's roll, ice's air),
## the hull bounce, the pull radius, a full hold, play mode only, the income of a Net Mouth over a minute, and the data.

const Wall = preload("res://tests/fixture_wall.gd")
const DriftDebris = preload("res://scripts/space/drift_debris.gd")
const DebrisView = preload("res://scripts/view/debris_view.gd")
const BuildMode = preload("res://scripts/build/build_mode.gd")
const ShipSim = preload("res://scripts/sim/ship_sim.gd")
const Ship = preload("res://scripts/ship/ship.gd")
const Content = preload("res://scripts/data/content.gd")

const RUSTBUCKET := "res://data/ships/starter_rustbucket.json"


## A DriftDebris whose current runs straight south with no wobble, so a test knows where a piece goes.
func _dd(seed_value := 1) -> DriftDebris:
	var cfg: Dictionary = Content.read(DriftDebris.PATH).duplicate(true)
	cfg["current"]["angle"] = 90
	cfg["current"]["wobble_deg"] = 0
	cfg["current"]["speed_wobble"] = 0
	return DriftDebris.new(seed_value, cfg)


## The wall fixture (31x31, the wall along y = 15, space above it) with intake `id` through it, outside half facing up.
## Mk1 gets a reactor behind the wall and a cable to it. Returns {ship, uid, mouth (the mouth's rect in world px)}.
func _rig(id := "net_mouth_scrap", power := true) -> Dictionary:
	var ship := Wall.wall_ship(1, 0)
	var depth: int = ship.components.by_id[id]["mount"]["outside"][1]
	var uid := ship.components.place_mount(ship.grid, id, Wall.out_anchor(0, depth), 0)
	if power:
		ship.components.place(ship.grid, "reactor_mk1", Wall.corner(0, 2, 5, 1, 4), 0)
		for c in [Wall.at(0, 1, 1), Wall.at(0, 2, 1)]:
			ship.cables.place(ship.grid, c)
	ship.refresh()
	var mouths := _dd().intakes(ship)
	return {"ship": ship, "uid": uid, "mouth": mouths[0]["rect"] if not mouths.is_empty() else Rect2()}


func _run(d: DriftDebris, ship, seconds: float) -> void:
	for i in roundi(seconds / 0.05):
		d.step(ship, 0.05)


## `d` (id -> number) with whole numbers as ints, for comparing with what JSON parsed into floats.
func _ints(d: Dictionary) -> Dictionary:
	var out := {}
	for k in d:
		out[k] = int(d[k])
	return out


func near(got: float, want: float, msg: String, eps := 1e-3) -> void:
	check(absf(got - want) <= eps, "%s: expected %s, got %s" % [msg, str(want), str(got)])


## A Net Mouth on the upstream side of the starter: the outside half facing up (the current runs from the north), at the
## spot nearest the middle of the top edge.
func _starter_with_a_net() -> Ship:
	var ship: Ship = Ship.from_design(RUSTBUCKET)
	ship.refresh()
	var best := Vector2i(-1, -1)
	var best_rot := 0
	var best_score := 1.0e9
	for rot in [0, 1, 3]:  # facing up (the bow, upstream) is best; a side wall works when the bow is full of guns and slopes
		for y in ship.grid.size.y:
			for x in ship.grid.size.x:
				if ship.components.can_place_mount(ship.grid, "net_mouth_scrap", Vector2i(x, y), rot) != "":
					continue
				var score := float(y) * 100.0 + absf(float(x) - float(ship.grid.size.x) / 2.0) + (0.0 if rot == 0 else 2000.0)
				if score < best_score:
					best_score = score
					best = Vector2i(x, y)
					best_rot = rot
	check(best.x >= 0, "the starter has a spot for a Net Mouth on an outer wall")
	if best.x >= 0:
		check(ship.components.place_mount(ship.grid, "net_mouth_scrap", best, best_rot) >= 0, "and it goes in")
	ship.refresh()
	return ship


# --- the spawner -------------------------------------------------------------------------------------------

func test_spawning_is_deterministic_for_a_seed_and_stays_under_the_cap() -> void:
	var ship := Wall.wall_ship(1, 0)
	var a := DriftDebris.new(7)
	var b := DriftDebris.new(7)
	var c := DriftDebris.new(8)
	for d in [a, b, c]:
		d.prewarm(ship)
	var cap := int(a.cfg["spawn"]["max_alive"])
	var most := 0
	for i in 1200:  # 60 s
		for d in [a, b, c]:
			d.step(ship, 0.05)
		most = maxi(most, a.pieces.size())
	check(a.pieces.size() > 5, "pieces are drifting (%d)" % a.pieces.size())
	check(most <= cap, "never more than the cap: %d of %d" % [most, cap])
	eq(a.pieces.map(func(p): return [p["type"], p["pos"]]), b.pieces.map(func(p): return [p["type"], p["pos"]]), "the same seed gives the same debris")
	check(a.pieces.map(func(p): return p["pos"]) != c.pieces.map(func(p): return p["pos"]), "another seed gives other debris")


func test_pieces_appear_upstream_just_outside_the_view() -> void:
	var ship := Wall.wall_ship(1, 0)
	var d := _dd()
	d.view_half = Vector2(800.0, 450.0)
	d.step(ship, 1.5)  # the first spawn
	check(not d.pieces.is_empty(), "something spawned")
	for p in d.pieces:
		check(p["pos"].y < -450.0, "north of the view, upstream of a current that runs south: %s" % [p["pos"]])


# --- a steady flow at any speed, and the streams -------------------------------------------------------------

## The pieces within the view round `d.view_centre`.
func _in_view(d: DriftDebris) -> int:
	return d.pieces.filter(func(p): return absf(p["pos"].x - d.view_centre.x) <= d.view_half.x and absf(p["pos"].y - d.view_centre.y) <= d.view_half.y).size()


## `d` flies `ship` at `vel` px/s for `seconds` the way the sector view does (the frame and the view centre follow the ship):
## the mean number of pieces within the view over the last `sample` seconds.
func _flown_count(d: DriftDebris, ship, vel: Vector2, seconds: float, sample := 30.0) -> float:
	var off := Vector2(20000.0, 20000.0)
	d.frame_vel = vel
	d.frame = Transform2D(0.0, off)
	d.view_centre = d.frame * ship.world_pos
	d.prewarm(ship)
	var sum := 0.0
	var n := 0
	var steps := roundi(seconds / 0.05)
	for i in steps:
		off += vel * 0.05
		d.frame = Transform2D(0.0, off)
		d.view_centre = d.frame * ship.world_pos
		d.step(ship, 0.05)
		if i >= steps - roundi(sample / 0.05) and i % 20 == 0:
			sum += _in_view(d)
			n += 1
	return sum / float(n)


func test_a_ship_five_times_as_fast_as_the_current_flying_upstream_still_sees_a_full_screen() -> void:
	var ship := Wall.wall_ship(1, 0)
	var rest := _flown_count(_dd(), ship, Vector2.ZERO, 150.0)
	var fast := _flown_count(_dd(), ship, Vector2(0.0, -200.0), 150.0)  # the current runs south at 40: upstream is north, 5 x its speed
	var slow := _flown_count(_dd(), ship, Vector2(0.0, -80.0), 150.0)
	print("drift_debris: pieces in view at rest %.1f, at 2 x the current upstream %.1f, at 5 x %.1f" % [rest, slow, fast])
	check(rest > 20.0, "at rest the view has a good many pieces (%.1f)" % rest)
	check(fast >= 0.6 * rest, "at 5 x the current's speed upstream at least 60%% of that stay (%.1f of %.1f)" % [fast, rest])
	check(slow >= 0.6 * rest, "and at 2 x (%.1f of %.1f)" % [slow, rest])


func test_the_spawn_rate_follows_how_fast_the_flow_passes_the_ship_from_1_to_6_times() -> void:
	var d := _dd()
	near(d.stream_vel(0).length(), 40.0, "the test current is 40 px/s")
	for row in [[Vector2.ZERO, 1.0], [Vector2(0.0, 40.0), 1.0], [Vector2(0.0, 20.0), 1.0], [Vector2(0.0, -40.0), 2.0], [Vector2(0.0, -80.0), 3.0],
			[Vector2(0.0, -200.0), 6.0], [Vector2(0.0, -2000.0), 6.0], [Vector2(300.0, 40.0), 300.0 / 40.0 if false else 6.0]]:
		d.frame_vel = row[0]
		var total := 0.0
		for w in d._stream_weights():
			total += w
		near(total, row[1], "the ship at %s: the spawn rate is x%.0f" % [str(row[0]), row[1]])


func test_flying_downstream_at_the_currents_speed_pieces_still_spawn() -> void:
	var ship := Wall.wall_ship(1, 0)
	var d := _dd()
	var off := Vector2(20000.0, 20000.0)
	var vel := Vector2(0.0, 40.0)  # with the current: the flow past the ship is nil
	d.frame_vel = vel
	var seen := 0
	for i in 1200:  # 60 s
		off += vel * 0.05
		d.frame = Transform2D(0.0, off)
		d.view_centre = d.frame * ship.world_pos
		var before := d.pieces.size()
		d.step(ship, 0.05)
		seen += maxi(d.pieces.size() - before, 0)
	check(seen >= 20, "pieces keep spawning (%d in a minute)" % seen)
	check(d.pieces.size() >= 10, "and are about (%d)" % d.pieces.size())
	for p in d.pieces:
		check(p["pos"].y < d.view_centre.y + 1.0, "upstream of the ship, to the north")
		break


func test_every_cargo_type_flows() -> void:
	var ship := Wall.wall_ship(1, 0)
	var d := _dd(3)
	var seen := {}
	for i in 800:
		d.pieces.clear()
		var p := d._spawn(ship)
		seen[p["type"]] = true
	var want: Array = ["scrap_chunk_s", "scrap_chunk_m", "copper_coil", "polymer_barrel", "ice_chunk_s", "fuel_canister", "sealed_crate"]
	for t in want:
		check(seen.has(t), "%s turns up in the flow" % t)
	eq(d.cfg["spawn"]["every"], 1.1, "a piece about every 1.1 s")
	eq(d.cfg["spawn"]["max_alive"], 70, "up to 70 about")


## `_dd()` with two side streams: one at 90 degrees off the main current, 0.3 of the pieces, one at 70 degrees the other way, 0.25.
func _streamed(seed_value := 1) -> DriftDebris:
	var cfg: Dictionary = Content.read(DriftDebris.PATH).duplicate(true)
	cfg["current"]["angle"] = 90  # south
	cfg["current"]["wobble_deg"] = 0
	cfg["current"]["speed_wobble"] = 0
	cfg["streams"] = [{"angle": 180.0, "speed": 30.0, "share": 0.3}, {"angle": 20.0, "speed": 55.0, "share": 0.25}]
	return DriftDebris.new(seed_value, cfg)


func test_pieces_are_picked_into_the_streams_by_share_and_drift_with_their_own() -> void:
	var ship := Wall.wall_ship(1, 0)
	var d := _streamed()
	eq(d.stream_count(), 3, "the main current and two side streams")
	near(d.stream_vel(1).x, -30.0, "side stream 1 runs west at 30 px/s", 1e-3)
	near(d.stream_vel(2).length(), 55.0, "side stream 2 at 55 px/s", 1e-3)
	var counts := [0, 0, 0]
	for i in 3000:
		counts[d._pick_stream()] += 1
	near(counts[1] / 3000.0, 0.3, "30%% of the pieces in the first side stream", 0.03)
	near(counts[2] / 3000.0, 0.25, "25%% in the second", 0.03)
	near(counts[0] / 3000.0, 0.45, "the main current carries the rest", 0.03)
	var made := [0, 0, 0]
	for i in 300:
		d.pieces.clear()
		var p := d._spawn(ship)
		made[p["stream"]] += 1
		var v: Vector2 = d.stream_vel(p["stream"])
		check(p["vel"].length() >= 0.89 * v.length() and p["vel"].length() <= 1.11 * v.length() and p["vel"].normalized().dot(v.normalized()) > 0.999, "a piece starts moving with its stream")
		var up: Vector2 = -d.stream_flow(p["stream"])
		check((p["pos"] - d.view_centre).dot(up) > 0.0, "and upstream of that stream's flow")
	check(made[0] > 0 and made[1] > 0 and made[2] > 0, "pieces come from every stream (%s)" % str(made))
	d.prewarm(ship)
	_run(d, ship, 20.0)
	var by := [0, 0, 0]
	for p in d.pieces:
		by[p["stream"]] += 1
		if d.time - p["age"] < 0.0:
			continue
	check(by[0] > 0 and by[1] > 0 and by[2] > 0, "all three are drifting (%s)" % str(by))
	for p in d.pieces:
		if p["stream"] == 1 and p["age"] > 15.0 and not p["no_pull"]:
			check(p["vel"].x < -15.0, "a piece of the west stream goes west: %s" % str(p["vel"]))
			break
	check(d.hud_line().ends_with("current: south"), "the HUD names the main current: %s" % d.hud_line())


# --- moving ------------------------------------------------------------------------------------------------

func test_pieces_move_with_the_current() -> void:
	var ship := Wall.wall_ship(1, 0)
	var d := _dd()
	var p := d.add_piece("scrap_chunk_s", Vector2(900.0, -300.0), Vector2.ZERO)
	var start: Vector2 = p["pos"]
	d.step(ship, 0.0)  # nothing happens in no time
	_run(d, ship, 4.0)
	var moved: Vector2 = p["pos"] - start
	check(moved.y > 20.0 and absf(moved.x) < 1.0, "it drifts south, with the current: %s" % [moved])
	check(moved.length() < 40.0 * 4.0 + 1.0, "and not faster than the current")
	var still := d.add_piece("scrap_chunk_s", Vector2(900.0, -300.0), Vector2(0, 40))
	_run(d, ship, 10.0)
	near(still["pos"].y, -300.0 + 400.0, "a piece at the current's speed keeps it (10 s at 40 px/s)", 1.0)
	check(d.current_vel().is_equal_approx(Vector2(0, 40)), "the test current is 40 px/s south")
	var wobbly := DriftDebris.new(3)
	var dirs := {}
	for i in 100:
		wobbly.time = i * 2.0
		dirs[snappedf(wobbly.current_dir().angle(), 0.01)] = true
	check(dirs.size() > 5, "the real current wobbles slowly")


# --- collecting --------------------------------------------------------------------------------------------

## Put piece `type_id` above the mouth, moving down onto it, and let it fall for a few seconds.
func _drop(rig: Dictionary, d: DriftDebris, type_id: String, x_off := 0.0) -> Dictionary:
	var m: Rect2 = rig["mouth"]
	var p := d.add_piece(type_id, Vector2(m.get_center().x + x_off, m.position.y - 120.0), Vector2(0, 40))
	_run(d, rig["ship"], 6.0)
	return p


func test_a_piece_that_reaches_the_mouth_lands_in_cargo_with_its_yield() -> void:
	var rig := _rig()
	check(rig["mouth"] != Rect2(), "the Net Mouth works with no power")
	var ship: Ship = rig["ship"]
	for t in [["scrap_chunk_s", "scrap", 2], ["scrap_chunk_m", "scrap", 4], ["copper_coil", "copper", 2], ["polymer_barrel", "polymer", 2], ["fuel_canister", "fuel", 1]]:
		var d := _dd()
		var before: int = ship.inventory.count(t[1])
		var p := _drop(rig, d, t[0])
		eq(ship.inventory.count(t[1]) - before, t[2], "%s gives %d %s" % [t[0], t[2], t[1]])
		eq(d.picked, 1, t[0] + ": counted")
		eq(d.collected, {t[1]: t[2]}, t[0] + ": counted by material")
		check(not d.pieces.has(p), t[0] + ": the piece is gone")
		var e: Array = d.take_events()
		eq(e.size(), 1, t[0] + ": one pop")
		if e.size() == 1:
			eq(e[0]["text"], "+%d %s" % [t[2], t[1]], t[0] + ": the pop says what came in")
			check(rig["mouth"].has_point(e[0]["pos"]), t[0] + ": at the mouth")


func test_a_sealed_crate_rolls_scrap_copper_or_a_missile() -> void:
	var seen := {}
	for seed_value in 40:
		var rig := _rig()
		var ship: Ship = rig["ship"]
		var before := {"scrap": ship.inventory.count("scrap"), "copper": ship.inventory.count("copper"), "missile": ship.inventory.count("missile")}
		var d := _dd(seed_value)
		_drop(rig, d, "sealed_crate")
		var got := {}
		for id in before:
			var n: int = ship.inventory.count(id) - before[id]
			if n != 0:
				got[id] = n
		eq(got.size(), 1, "a crate gives one thing: %s" % [got])
		for id in got:
			seen[id] = true
			var lo: int = {"scrap": 6, "copper": 3, "missile": 1}[id]
			var hi: int = {"scrap": 12, "copper": 5, "missile": 1}[id]
			check(got[id] >= lo and got[id] <= hi, "%s %d is within %d-%d" % [id, got[id], lo, hi])
	eq(seen.size(), 3, "over 40 crates all three come up: %s" % [seen.keys()])


func test_ice_refills_the_air_by_five_percent() -> void:
	var rig := _rig()
	var ship: Ship = rig["ship"]
	check(not ship.atmosphere.rooms.is_empty(), "the fixture has a room")
	for i in ship.atmosphere.pressure.size():
		ship.atmosphere.pressure[i] = 0.5
	var d := _dd()
	_drop(rig, d, "ice_chunk_s")
	for i in ship.atmosphere.pressure.size():
		near(ship.atmosphere.pressure[i], 0.55, "room %d gained 5%%" % i, 1e-4)
	eq(d.picked, 1, "the ice was taken")
	eq(d.take_events().map(func(e): return e["text"]), ["+5% O2"], "and says so")
	for i in ship.atmosphere.pressure.size():
		ship.atmosphere.pressure[i] = 0.99
	_drop(rig, d, "ice_chunk_s")
	check(ship.atmosphere.pressure.all(func(v): return v <= 1.0), "air never goes past full")


func test_a_full_hold_refuses_and_the_piece_bounces() -> void:
	var rig := _rig()
	var ship: Ship = rig["ship"]
	var d := _dd()
	var held := 0
	for id in ship.inventory.counts:
		held += int(ship.inventory.counts[id])
	d.cfg["cargo_limit"] = held + 3  # room for 3 more units: a 4-unit chunk will not fit
	var scrap: int = ship.inventory.count("scrap")
	var p := _drop(rig, d, "scrap_chunk_m")
	eq(ship.inventory.count("scrap"), scrap, "nothing was taken")
	eq(d.picked, 0, "nothing counted")
	check(d.pieces.has(p), "the piece is still drifting")
	check(not rig["mouth"].grow(p["r"] - 0.5).has_point(p["pos"]), "outside the mouth, not inside it")
	_drop(rig, d, "scrap_chunk_s")
	eq(ship.inventory.count("scrap"), scrap + 2, "a piece that fits is still taken")


# --- the hull ----------------------------------------------------------------------------------------------

func test_a_piece_that_touches_plain_hull_bounces_and_is_not_collected() -> void:
	var rig := _rig()
	var ship: Ship = rig["ship"]
	var d := _dd()
	var m: Rect2 = rig["mouth"]
	var p := d.add_piece("scrap_chunk_m", Vector2(m.end.x + 200.0, m.position.y - 20.0), Vector2(0, 60))
	var cargo: Dictionary = ship.inventory.counts.duplicate()
	var wall_top := m.end.y  # the wall row starts where the mouth ends
	var bounced := false
	for i in 200:
		d.step(ship, 0.05)
		if p["vel"].y < 0.0:
			bounced = true
		check(p["pos"].y + p["r"] <= wall_top + 0.5, "never inside the wall (y %s)" % [p["pos"].y])
	check(bounced, "it turned back off the wall")
	check(d.pieces.has(p), "and keeps drifting")
	eq(ship.inventory.counts, cargo, "nothing was collected")
	eq(d.picked, 0, "nothing counted")


func test_an_outside_half_that_is_not_a_working_mouth_is_hull_too() -> void:
	var rig := _rig("intake_mk1", false)  # no power: the Mk1 draws 1 and has none
	var ship: Ship = rig["ship"]
	var d := _dd()
	eq(d.intakes(ship).size(), 0, "an unpowered Mk1 is not a working intake")
	var out: Array = ship.components.instances[rig["uid"]]["out_cells"]
	var o := Vector2(-496.0, -496.0)
	var top := Rect2(o + Vector2(out[0]) * 32.0, Vector2(128.0, 64.0))
	var p := d.add_piece("scrap_chunk_s", Vector2(top.get_center().x, top.position.y - 120.0), Vector2(0, 40))
	_run(d, ship, 6.0)
	eq(d.picked, 0, "it took nothing")
	check(d.pieces.has(p) and p["pos"].y < top.position.y, "the piece bounced off the dead mouth")


# --- the pull ----------------------------------------------------------------------------------------------

func test_the_pull_radius_draws_in_a_piece_passing_one_or_two_cells_away() -> void:
	var net := _rig()
	var m: Rect2 = net["mouth"]
	var d := _dd()
	# a piece falling 1 cell (32 px) to the side of the net's edge: inside its 1-cell pull radius
	_drop(net, d, "scrap_chunk_s", m.size.x / 2.0 + 26.0 + 11.0)
	eq(d.picked, 1, "the Net Mouth draws in a piece passing a cell away")
	d = _dd()
	_drop(net, d, "scrap_chunk_s", m.size.x / 2.0 + 70.0 + 11.0)
	eq(d.picked, 0, "but not one passing two cells away")
	var mk1 := _rig("intake_mk1")
	m = mk1["mouth"]
	check(m != Rect2(), "the powered Mk1 works")
	d = _dd()
	_drop(mk1, d, "scrap_chunk_s", m.size.x / 2.0 + 58.0 + 11.0)
	eq(d.picked, 1, "the Mk1 (pull radius 2) draws in a piece passing two cells away")
	d = _dd()
	_drop(mk1, d, "scrap_chunk_s", m.size.x / 2.0 + 100.0 + 11.0)
	eq(d.picked, 0, "but not three and a bit")


func test_a_mouth_shows_pulling_while_it_draws_a_piece_in() -> void:
	var rig := _rig()
	var d := _dd()
	var m: Rect2 = rig["mouth"]
	d.add_piece("scrap_chunk_s", Vector2(m.get_center().x + 60.0, m.position.y - 30.0), Vector2(0, 40))
	d.step(rig["ship"], 0.1)
	check(d.pulling.has(rig["uid"]), "the mouth pulls")
	d.pieces.clear()
	_run(d, rig["ship"], 1.0)
	check(d.pulling.is_empty(), "and stops a moment after")


# --- play mode only ----------------------------------------------------------------------------------------

func test_nothing_runs_in_build_mode_or_in_a_fight() -> void:
	var sim := ShipSim.new()
	var build := BuildMode.new()
	build.sim = sim
	var view := DebrisView.new()
	view.sim = sim
	view.build = build
	check(build.build_on, "the game starts in build mode")
	for i in 60:
		view.frame(0.1)
	check(view.debris == null, "build mode: no debris was even made")
	build.build_on = false
	for i in 10:
		view.frame(0.1)
	check(view.debris != null and view.debris.time > 0.9, "play mode: it runs")
	var t: float = view.debris.time
	var n: int = view.debris.pieces.size()
	check(n > 0, "with pieces in the water")
	build.combat = true
	for i in 30:
		view.frame(0.1)
	near(view.debris.time, t, "a fight: time stands still", 1e-6)
	build.combat = false
	build.build_on = true
	for i in 30:
		view.frame(0.1)
	near(view.debris.time, t, "back in build mode: still", 1e-6)
	view.free()
	build.free()
	sim.free()


# --- what a Net Mouth earns --------------------------------------------------------------------------------

func test_a_net_mouth_on_the_upstream_side_collects_some_scrap_a_minute() -> void:
	var ship := _starter_with_a_net()
	var total := 0
	var first := 0
	var seeds := 8
	for s in seeds:
		var d := DriftDebris.new(s + 1)
		d.prewarm(ship)
		var scrap: int = ship.inventory.count("scrap")
		_run(d, ship, 60.0)
		var got: int = ship.inventory.count("scrap") - scrap
		total += got
		if s == 0:
			first = got
		check(d.mouth_count == 1, "the mouth works")
	check(first >= 5 and first <= 40, "seed 1: %d scrap in 60 s" % first)  # the Mk1 (wider, 3 cells of pull) earns 15-25 idle, so the 2-cell Net Mouth earns less (test_sector3.gd)
	var mean := float(total) / float(seeds)
	check(mean >= 8.0 and mean <= 30.0, "on average %.1f scrap in 60 s (8-30 wanted)" % mean)
	print("drift_debris: a Net Mouth on the starter collected %.1f scrap a minute on average over %d seeds (seed 1: %d)" % [mean, seeds, first])


# --- the data ----------------------------------------------------------------------------------------------

func test_the_intakes_the_recipes_and_ma_gantrys_net_are_in_the_data() -> void:
	var ship := Ship.new_starter()
	var net: Dictionary = ship.components.def("net_mouth_scrap")
	var mk1: Dictionary = ship.components.def("intake_mk1")
	eq([net["family"], net["line"], net["size"], net["mount"]["outside"], net["power"], net["hp"], int(net["stats"]["pull_radius"])], ["intake", "scrap", [2, 2], [2, 2], 0, 4, 2], "Net Mouth")
	eq([mk1["family"], mk1["line"], mk1["size"], mk1["mount"]["outside"], mk1["power"], mk1["hp"], int(mk1["stats"]["pull_radius"])], ["intake", "standard", [4, 2], [4, 2], -1, 6, 3], "Intake Mk1")
	var recipes := {}
	for r in Content.list("recipes"):
		recipes[r["id"]] = r
	eq([_ints(recipes["net_mouth_scrap"]["materials"]), int(recipes["net_mouth_scrap"]["fab_level"])], [{"scrap": 20}, 1], "Net Mouth recipe")
	eq([_ints(recipes["intake_mk1"]["materials"]), int(recipes["intake_mk1"]["fab_level"])], [{"scrap": 30, "copper": 10}, 1], "Intake Mk1 recipe")
	check(ship.crafting.is_known("net_mouth_scrap"), "the Net Mouth is known at the start")
	check(not ship.crafting.is_known("intake_mk1"), "the Intake Mk1 is not")
	var stock: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/drift.json"))["stations"]["meridian"]["stock"]
	eq(stock.get("intake_mk1"), 120, "Meridian sells the Mk1 for 120")
	var intro := {}
	for e in Content.events():
		if e["id"] == "station_debt_intro":
			intro = e
	check(not intro.is_empty(), "Ma's intro event exists")
	for c in intro.get("choices", []):
		for o in c["outcomes"]:
			eq(_ints(o["effects"].get("items", {})), {"net_mouth_scrap": 1}, "every outcome of the intro hands over the net: " + str(o["text"]).left(30))
			check(str(o["text"]).contains("net"), "and Ma says so")


func test_every_debris_type_gives_something_the_hold_knows() -> void:
	var d := DriftDebris.new(1)
	var ship := Ship.new_starter()
	var weight := 0.0
	for t in d.types:
		weight += float(t["weight"])
		check(t.has("yield") or t.has("effect") or t.has("roll"), "%s gives something" % t["id"])
		for id in t.get("yield", {}):
			check(ship.components.has(id) or Content.has("items", id) or Content.has("materials", id), "%s yields '%s', which exists" % [t["id"], id])
		for o in t.get("roll", []):
			check(Content.has("items", o["item"]) or Content.has("materials", o["item"]), "%s rolls '%s', which exists" % [t["id"], o["item"]])
	eq(d.types.size(), 7, "seven kinds")
	near(weight, 100.0, "the weights add up to 100", 1e-6)
	check(d.hud_line().begins_with("Salvage: nothing yet this trip"), "the HUD line before anything: " + d.hud_line())
	d.collected = {"copper": 4, "scrap": 12}
	check(d.hud_line().begins_with("Salvage: +12 scrap, +4 copper this trip"), "the HUD line lists scrap first: " + d.hud_line())
