extends SceneTree
## Not a test. One sheet per species (or faction pack) that has race-specific parts: those parts' art side by side, as the build palette draws them.
##   xvfb-run -a godot --path . --script res://tests/tool_race_parts.gd [-- out=/home/user/hs/shots]
## Writes <out>/race_parts_<name>.png for every data/packs/tech_<name>/ and faction_<name>/ pack that has components.

const Shipgen = preload("res://scripts/space/shipgen.gd")
const Thumbs = preload("res://scripts/ui/thumbs.gd")

const CELL_W := 150.0
const CELL_H := 170.0


class Sheet extends Node2D:
	var ids: Array = []
	var ship
	var name_of := {}
	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, Vector2(150.0 * ids.size(), 170.0)), Color("#0b0e14"))
		for i in ids.size():
			var r := Rect2(Vector2(150.0 * i + 6.0, 8.0), Vector2(138.0, 120.0))
			Thumbs.draw(self, {"kind": "part", "id": ids[i]}, ship, r, 0.0)
			var def: Dictionary = ship.components.def(ids[i])
			draw_string(ThemeDB.fallback_font, Vector2(150.0 * i + 6.0, 144.0), str(ids[i]).left(22), HORIZONTAL_ALIGNMENT_LEFT, 140.0, 11, Color("#c8d4e8"))
			draw_string(ThemeDB.fallback_font, Vector2(150.0 * i + 6.0, 158.0), "%s  %s" % [def.get("family", ""), def.get("line", "")], HORIZONTAL_ALIGNMENT_LEFT, 140.0, 10, Color("#8696b0"))


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var out := "/home/user/hs/shots"
	for a in OS.get_cmdline_user_args():
		if str(a).begins_with("out="):
			out = str(a).substr(4)
	var ship = Shipgen.build("rustfangs", "small", 1, 20.0)
	for dir in DirAccess.get_directories_at("res://data/packs"):
		if not (dir.begins_with("tech_") or dir.begins_with("faction_")):
			continue
		var path := "res://data/packs/%s/components.json" % dir
		if not FileAccess.file_exists(path):
			continue
		var data = JSON.parse_string(FileAccess.get_file_as_string(path))
		var list: Array = data["components"] if data is Dictionary else data
		var ids: Array = list.map(func(c): return str(c["id"]))
		var name := dir.substr(dir.find("_") + 1)
		var vp := SubViewport.new()
		vp.size = Vector2i(int(CELL_W) * ids.size(), int(CELL_H))
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(vp)
		var s := Sheet.new()
		s.ids = ids
		s.ship = ship
		vp.add_child(s)
		for i in 5:
			await process_frame
		vp.get_texture().get_image().save_png("%s/race_parts_%s.png" % [out, name])
		print("race_parts_", name, ": ", ids)
		vp.queue_free()
		await process_frame
	quit(0)
