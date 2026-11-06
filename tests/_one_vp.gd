extends SceneTree
func _init() -> void:
	var passed := 0
	var failed := 0
	for f in OS.get_cmdline_user_args():
		var script: GDScript = load("res://tests/" + f)
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
