extends "res://tests/base_test.gd"
## Beta 3 known issue 5 (QA saw the ship slow from 283 to 84 px/s for about 15 s far out with W held). Flown through the helm in a
## sector, the speed does not depend on where the ship is, the current, the tide, the cargo or passing contacts; what cuts it is an
## engine out of action (overheated until it cools, or a malfunction until it is mended): the speed then settles at the share
## of the thrust that is left.

const Helm = preload("res://scripts/space/helm.gd")
const Jobs = preload("res://scripts/crew/jobs.gd")
const Sector = preload("res://scripts/space/sector.gd")
const Ship = preload("res://scripts/ship/ship.gd")

const RUSTBUCKET := "res://data/ships/starter_rustbucket.json"
const DT := 0.05


func _ship() -> Ship:
	var s: Ship = Ship.from_design(RUSTBUCKET)
	Jobs.spawn_crew(s)
	return s


## The speed a ship settles at holding W toward `dir` for `seconds` from `at`, in a generated boneyard sector, with `rig` called on
## the ship first. Returns {v, mass, fwd}.
func _hold_w(at: Vector2, dir: Vector2, seconds: float, rig := Callable(), hostile := false) -> Dictionary:
	var ship := _ship()
	if rig.is_valid():
		rig.call(ship)
	var sector: Sector = Sector.generate(3, {"id": "t0", "name": "", "type": "empty", "place": ""}, "boneyard")
	var helm := Helm.new()
	helm.refresh(ship)
	helm.place(at, Vector2.ZERO, dir.angle() + PI / 2.0)
	helm.manual = true
	for i in roundi(seconds / DT):
		helm.step(DT, sector, true, {"throttle": 1.0, "side": 0.0, "cursor": helm.flight.pos + dir * 3000.0}, hostile, [])
		if i % 20 == 0:
			helm.refresh(ship)
	return {"v": helm.flight.vel.length(), "mass": helm.mass, "fwd": float(helm.thrusts["fwd"])}


func test_the_speed_holding_w_is_the_same_wherever_the_ship_is() -> void:
	var base := _hold_w(Vector2(22800.0, 15000.0), Vector2.UP, 40.0)
	check(float(base["v"]) > 100.0, "(setup) it flies: %.0f px/s" % float(base["v"]))
	for where in [[Vector2(22800.0, -15000.0), Vector2.UP], [Vector2(-90000.0, 15000.0), Vector2.LEFT], [Vector2(150000.0, 150000.0), Vector2(1.0, 1.0).normalized()], [Vector2(5000.0, 400000.0), Vector2.DOWN]]:
		var got := _hold_w(where[0], where[1], 40.0)
		check(absf(float(got["v"]) - float(base["v"])) < 1.0, "from %s: %.1f px/s, as at y 15000 (%.1f)" % [where[0], float(got["v"]), float(base["v"])])
		eq(got["mass"], base["mass"], "the mass is the same")


func test_the_cruise_numbers_drop_to_the_real_ones_only_with_a_hostile_in_range() -> void:
	var cruise := _hold_w(Vector2(22800.0, 15000.0), Vector2.UP, 40.0)
	var real := _hold_w(Vector2(22800.0, 15000.0), Vector2.UP, 40.0, Callable(), true)
	var ratio := float(real["v"]) / float(cruise["v"])
	check(absf(ratio - 1.0 / float(Helm.new().cfg["cruise"])) < 0.02, "a fight in place (a hostile within real_within) is the one thing that takes the cruise bonus: %.2f of it" % ratio)


func test_an_engine_out_of_action_is_what_cuts_the_speed() -> void:
	var whole := _hold_w(Vector2(22800.0, 15000.0), Vector2.UP, 60.0)
	var one_out := _hold_w(Vector2(22800.0, 15000.0), Vector2.UP, 60.0, func(ship: Ship) -> void:
		for uid in ship.components.instances:
			if str(ship.components.def(ship.components.instances[uid]["id"]).get("family", "")) == "engine":
				ship.components.instances[uid]["status"] = "overheated"
				return)
	check(float(one_out["fwd"]) < float(whole["fwd"]) - 0.01, "one engine overheated: less forward thrust (%.1f of %.1f)" % [float(one_out["fwd"]), float(whole["fwd"])])
	var share := float(one_out["fwd"]) / float(whole["fwd"])
	check(absf(float(one_out["v"]) / float(whole["v"]) - share) < 0.03, "and the speed settles at that share of it: %.2f of the speed for %.2f of the thrust" % [float(one_out["v"]) / float(whole["v"]), share])
