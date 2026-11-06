extends SceneTree
## Not a test: prints where a limpet thrown at different angles and ranges lands (magnet tuning). godot --headless --path . --script res://tests/tool_limpet_tune.gd
const Arena = preload("res://scripts/combat/arena.gd")
const Drones = preload("res://scripts/combat/drones.gd")
const Limpets = preload("res://scripts/combat/limpets.gd")
const Ship = preload("res://scripts/ship/ship.gd")
const ShipGrid = preload("res://scripts/ship/ship_grid.gd")
const TileDefs = preload("res://scripts/ship/tile_defs.gd")

func _ship() -> Ship:
	var defs := TileDefs.new()
	defs.load_file("res://data/tiles.json")
	var g := ShipGrid.new(Vector2i(31, 31), defs)
	g.fill_circle_hull(15.0)
	for c in g.hull:
		var edge := false
		for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			edge = edge or not g.hull.has(c + d)
		g.force_tile(c, "wall" if edge else "floor")
	return Ship.new("t", g)

func _init() -> void:
	for kit in ["fire_limpet_mk1"]:
		var spec: Dictionary = Drones.kit(kit)["drone"]
		for kv in OS.get_cmdline_user_args():
			var q := str(kv).split("=")
			spec["magnet"][q[0]] = float(q[1])
		for dist in [500.0, 900.0, 1400.0, 1900.0]:
			var line := "%s dist %d: " % [kit, int(dist)]
			for deg in [0, 8, 16, 24, 32, 40, 50, 60, 75, 90]:
				var a := Arena.new(7)
				var p := _ship()
				a.add_ship(p, Vector2.ZERO, 0.0)
				a.add_ship(_ship(), Vector2(0.0, -dist), PI)
				var hatch := a.local_to_world(0, Vector2(15.5, 4.5))
				var aim := hatch + Vector2.from_angle(-PI / 2.0 + deg_to_rad(float(deg))) * 800.0
				var r := Limpets.predict(a, 0, hatch, aim, spec, 6, 6.0)
				var cell: Vector2i = r["cell"]
				var side := ""
				if r["end"] == "hit":
					var w: Vector2 = a.local_to_world(1, Vector2(cell) + Vector2(0.5, 0.5)) - a.ships[1].flight.pos
					side = "%d" % absi(int(rad_to_deg((a.ships[0].flight.pos - a.ships[1].flight.pos).angle_to(w))))
				line += " %d:%s%s" % [deg, r["end"].substr(0, 1), side]
			print(line)
	quit()
