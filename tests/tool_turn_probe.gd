extends SceneTree
## Not a test (the runner only loads test_*.gd). Range-and-flanking numbers (docs/GUNS.md 13): per ship, its mass, thrust, the time it takes to turn 90 degrees
## (the helm's own steer_toward, from rest), the speed it can fly at, and how long a light ship at that speed needs to orbit 90 degrees round it
## at the distance the pilot holds. Ships: the starters, the player-like builds of each stage, two generated enemies a stage, the flagships.
##   godot --headless --path . --script res://tests/tool_turn_probe.gd [-- stages=1,2,3,4,5,6]

const Session = preload("res://scripts/combat/combat_session.gd")
const Standoff = preload("res://tests/tool_standoff.gd")
const PilotAI = preload("res://scripts/combat/pilot_ai.gd")
const Flight = preload("res://scripts/sim/flight.gd")

var rows: Array = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var dummy = Session.load_ship("res://data/ships/starter_courier.json")
	for k in Standoff.STARTERS:
		_probe(k, Session.load_ship(Standoff.STARTERS[k]), dummy)
	for st in [1, 2, 3, 4, 5, 6]:
		_probe("build %d" % st, Standoff.build_player(st), dummy)
		for e in Standoff.enemies(st, "plain", 2):
			_probe("enemy %d %s" % [st, e["spec"].get_slice(":", 1) if ":" in e["spec"] else ""], Session.load_ship(e["spec"]), dummy)
	for f in DirAccess.get_files_at("res://data/packs/flagships_1/ships"):
		if f.ends_with(".json"):
			_probe(f.trim_suffix(".json"), Session.load_ship("res://data/packs/flagships_1/ships/" + f), dummy)
	var light: Dictionary = rows[0]
	print("| ship | mass | thrust | 90 deg turn s | top speed px/s | hold gap px | light orbit 90 deg s |")
	print("|---|---|---|---|---|---|---|")
	for r in rows:
		print("| %s | %.0f | %.0f | %.1f | %.0f | %.0f | %.1f |" % [r["name"], r["mass"], r["thrust"], r["t90"], r["vmax"], r["hold"], r["orbit"]])
	quit(0)


func _probe(name: String, ship, other) -> void:
	if ship == null:
		return
	var s := Session.new()
	s.start(ship, other, 5)
	var a = s.arena
	var co = a.ships[0]
	var f := Flight.new()
	var t := 0.0
	var dt := 1.0 / 60.0
	var turned := false
	while t < 30.0 and not turned:
		f.step(dt, {"turn": f.steer_toward(PI * 0.5, co.mass, co.thrust)}, co.mass, co.thrust, co.thrusts)
		t += dt
		turned = f.angle >= PI * 0.5 - 0.02
	var fwd := float(co.thrusts.get("fwd", co.thrust))
	var vmax := minf(f.max_speed, fwd * f.thrust_to_accel / maxf(co.mass, 1.0) / f.linear_damping)
	var pilot := PilotAI.new(a, 0, 1, {})
	var hold := pilot.hold_distance(Vector2.UP, pilot._intact())
	rows.append({"name": name, "mass": co.mass, "thrust": co.thrust, "t90": t, "vmax": vmax, "hold": hold, "orbit": 0.0})
	var d := hold  # hold_distance is centre to centre
	rows[-1]["orbit"] = PI * 0.5 * d / maxf(rows[0]["vmax"], 1.0)  # the first row, the lightest starter, is the light orbiter
