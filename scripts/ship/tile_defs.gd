extends RefCounted
## Tile definitions loaded from data/*.json. Content is data, not code.

var by_id := {}
var order: Array[String] = []


func load_file(path: String) -> void:
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	assert(data is Dictionary and data.has("tiles"), "bad tile data: " + path)
	for t in data["tiles"]:
		by_id[t["id"]] = t
		order.append(t["id"])


func ids() -> Array[String]:
	return order


func has(id: String) -> bool:
	return by_id.has(id)


func get_def(id: String) -> Dictionary:
	return by_id.get(id, {})


func color(id: String) -> Color:
	return Color(get_def(id).get("color", "#ff00ff"))


func cost(id: String) -> int:
	return int(get_def(id).get("cost", 0))
