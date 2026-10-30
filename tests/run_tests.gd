extends SceneTree
## Headless test runner:  godot --headless --path . --script res://tests/run_tests.gd
## Runs every test_* method in tests/test_*.gd; exits 1 if any fail.


func _init() -> void:
	var passed := 0
	var failed := 0
	for f in DirAccess.get_files_at("res://tests"):
		if not (f.begins_with("test_") and f.ends_with(".gd")):
			continue
		var script: GDScript = load("res://tests/" + f)
		if script == null:
			printerr("FAIL %s: does not load" % f)
			failed += 1
			continue
		for m in script.get_script_method_list():
			var name: String = m["name"]
			if not name.begins_with("test_"):
				continue
			var t = script.new()
			t.call(name)
			if t.failures.is_empty():
				passed += 1
			else:
				failed += 1
				for msg in t.failures:
					printerr("FAIL %s::%s: %s" % [f, name, msg])
	print("%d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)
