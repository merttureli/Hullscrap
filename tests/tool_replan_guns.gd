extends SceneTree
## One-time tool (gun rework G1a, docs/GUNS.md 8): bring the shipped ship designs to components version 6, where the guns have new outside
## halves. Kept in the repo so the step can be repeated or checked:
##   godot --headless --path . --script res://tests/tool_replan_guns.gd
## Reads data/ships/*.json and data/packs/*/ships/*.json (not the flagship_* files: tests/tool_flagships.gd make draws those again). A
## design whose components are below version 6 is loaded (Components.load_dict re-plans every reshaped mount from its inside half). A gun
## whose new outside half does not fit there goes back to the cargo; this tool then moves it to the nearest other spot on the hull that
## has room (the same turn first), wires it, and says so. Only the "components", "cables", "belts" and "cargo" lines are rewritten (the
## files keep one top-level key per line). Then every part is checked powered and every mount whole. Exits 1 on a problem.

const Ship = preload("res://scripts/ship/ship.gd")
const Mounts = preload("res://scripts/ship/mounts.gd")
const Shipgen = preload("res://scripts/space/shipgen.gd")
const Components = preload("res://scripts/ship/components.gd")

const KEYS := ["components", "cables", "belts", "cargo"]


func _init() -> void:
	var bad := 0
	var done := 0
	for path in _designs():
		var text := FileAccess.get_file_as_string(path)
		var d = JSON.parse_string(text)
		if not (d is Dictionary) or not (d.get("components") is Dictionary) or int(d["components"].get("version", 0)) >= Components.VERSION:
			continue
		var ship = Ship.from_design(path)
		if ship == null:
			printerr("%s: does not load" % path)
			bad += 1
			continue
		for r in ship.components.returned.duplicate():
			if _relocate(ship, r):
				ship.inventory.spend({str(r["id"]): 1})
				print("%s: MOVED %s from %s to the nearest spot with room" % [path, r["id"], str(r["anchor"])])
			else:
				printerr("%s: %s has nowhere to go (it is in the hold)" % [path, r["id"]])
				bad += 1
		var saved: Dictionary = ship.to_dict()
		var lines := text.split("\n")
		for i in lines.size():
			for k in KEYS:
				if lines[i].begins_with("\"%s\": " % k) and saved.has(k):
					lines[i] = "\"%s\": %s%s" % [k, JSON.stringify(saved[k], "", true), "," if lines[i].ends_with(",") else ""]
		var f := FileAccess.open(path, FileAccess.WRITE)
		f.store_string("\n".join(lines))
		f.close()
		var back = Ship.from_design(path)
		var dark := []
		for uid in back.components.instances:
			var inst: Dictionary = back.components.instances[uid]
			if not back.power_state["powered"].get(uid, false) and back.components.instances.values().any(func(i): return str(back.components.def(i["id"]).get("family", "")) == "reactor"):  # (the blank frame has no reactor)
				dark.append(inst["id"])
			if Mounts.is_mount(back.components.def(inst["id"])) and not (back.components.has_outside(uid) and back.components.link_intact(back.grid, uid)):
				dark.append(str(inst["id"]) + " (not whole)")
		print("%s: re-planned, %d parts%s" % [path, back.components.instances.size(), "" if dark.is_empty() else ", PROBLEM: " + str(dark)])
		bad += dark.size()
		done += 1
	print("%d designs re-planned, %d problems" % [done, bad])
	quit(1 if bad > 0 else 0)


## Put the gun of returned record `r` on the free floor nearest its old place where a mount through a wall works (its own turn first,
## then the others), and wire it. False when there is no such place.
func _relocate(ship, r: Dictionary) -> bool:
	var comps = ship.components
	var def: Dictionary = comps.def(str(r["id"]))
	var from: Vector2i = r["anchor"]
	var best := {}
	var best_score := INF
	for y in ship.grid.size.y:
		for x in ship.grid.size.x:
			var p := Vector2i(x, y)
			if not comps.free_floor(ship.grid, p):
				continue
			for turn in 4:
				var rot := posmod(int(r["rot"]) + turn, 4)
				var plan: Dictionary = Mounts.from_inside(ship.grid, comps, def, p, rot)
				if plan["why"] != "":
					continue
				var score := float(p.distance_to(from)) + (0.0 if turn == 0 else 8.0 * turn)
				if score < best_score:
					best_score = score
					best = {"out": plan["out"], "rot": rot}
	if best.is_empty():
		return false
	if comps.place_mount(ship.grid, str(r["id"]), best["out"], best["rot"]) < 0:
		return false
	return Shipgen._wire(ship)


## Every design file: data/ships/*.json and the ships/ folder of each pack (the flagships excluded).
func _designs() -> Array[String]:
	var out: Array[String] = []
	_add(out, "res://data/ships/")
	for p in DirAccess.get_directories_at("res://data/packs"):
		_add(out, "res://data/packs/%s/ships/" % p)
	return out


func _add(out: Array[String], dir: String) -> void:
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".json") and not f.begins_with("flagship_"):
			out.append(dir + f)
