extends SceneTree
## One-time tool (playtest 2, P2): bring the shipped ship designs to ship save version 7, where the tier 1-2 weapons, engines,
## reactors, shields and the medbay take less room inside. Kept in the repo so the step can be repeated or checked:
##   godot --headless --path . --script res://tests/tool_migrate_parts.gd
## Reads data/ships/*.json and data/packs/*/ships/*.json. A design below version 7 is loaded (Ship.load_dict runs MigrateParts on
## it), and only its "components", "cables", "belts" and "version" lines are rewritten (the files keep one top-level key per line, so
## the diff shows just the moved parts and the re-joined cables). Then it checks every part of the result is powered. Exits 1 on a problem.

const Ship = preload("res://scripts/ship/ship.gd")

const KEYS := ["components", "cables", "belts", "version"]


func _init() -> void:
	var bad := 0
	var done := 0
	for path in _designs():
		var text := FileAccess.get_file_as_string(path)
		var d = JSON.parse_string(text)
		if not (d is Dictionary) or int(d.get("version", 0)) >= Ship.VERSION:
			continue
		var ship = Ship.from_design(path)
		if ship == null:
			printerr("%s: does not load" % path)
			bad += 1
			continue
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
			if not back.power_state["powered"].get(uid, false):
				dark.append(back.components.instances[uid]["id"])
		print("%s: migrated, %d parts%s" % [path, back.components.instances.size(), "" if dark.is_empty() else ", NOT POWERED: " + str(dark)])
		bad += dark.size()
		done += 1
	print("%d designs migrated, %d problems" % [done, bad])
	quit(1 if bad > 0 else 0)


## Every design file: data/ships/*.json and the ships/ folder of each pack.
func _designs() -> Array[String]:
	var out: Array[String] = []
	_add(out, "res://data/ships/")
	for p in DirAccess.get_directories_at("res://data/packs"):
		_add(out, "res://data/packs/%s/ships/" % p)
	return out


func _add(out: Array[String], dir: String) -> void:
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".json"):
			out.append(dir + f)
