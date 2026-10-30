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
		if script == null or not script.can_instantiate():
			printerr("FAIL %s: does not load (parse error?)" % f)
			failed += 1
			continue
		var found := 0
		for m in script.get_script_method_list():
			var name: String = m["name"]
			if not name.begins_with("test_"):
				continue
			found += 1
			var t = script.new()
			t.call(name)
			if t.failures.is_empty():
				passed += 1
			else:
				failed += 1
				for msg in t.failures:
					printerr("FAIL %s::%s: %s" % [f, name, msg])
		if found == 0:
			printerr("FAIL %s: no test_ methods found (parse error?)" % f)
			failed += 1
	print("%d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)
