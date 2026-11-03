extends SceneTree
## Not a test. Dumps the merged content (core + packs) as JSON for the content audit scripts:
##   godot --headless --path . --script res://tests/tool_audit_content_dump.gd -- <out dir>
const Content = preload("res://scripts/data/content.gd")
const Events = preload("res://scripts/space/events.gd")


func _init() -> void:
	var out: String = OS.get_cmdline_user_args()[0]
	for kind in Content.KINDS:
		_w(out, kind, Content.list(kind))
	for kind in Content.FOLDER_KINDS:
		_w(out, kind, Content.list(kind))
	var ev := Events.new()
	_w(out, "logs", ev.logs)
	_w(out, "validate", ev.validate())
	_w(out, "content_errors", Content.errors())
	_w(out, "names", Content.names())
	quit(0)


func _w(dir: String, name: String, v) -> void:
	var f := FileAccess.open(dir + "/" + name + ".json", FileAccess.WRITE)
	f.store_string(JSON.stringify(v))
