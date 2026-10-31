extends RefCounted
## The map of the Drift (docs/CONTENT.md section 8, tuning in data/drift.json). Pure data and logic:
## the fixed places first (Rusthold, Meridian, the Prism, three Dead Gates), then random nodes with a
## minimum spacing, each given a type by weight; then lanes between near neighbours, 2 to 4 per node,
## always one connected graph. Everything random comes from the RandomNumberGenerator the caller
## passes (the campaign's), so the same seed makes the same map.
## A node is {id, name, type, place ("" for random nodes), faction, hidden_until, beacon (always on the map), start, clan, pos}.
## `map.nodes` is the count of nodes in all, or [least, most] to roll it; a region's map (regions.gd) has one node of type
## `exit`, its exit beacon.

var nodes: Array = []  ## node dictionaries, fixed places first
var lanes: Array = []  ## [a, b] node ids with a < b
var _index := {}  # id -> index in nodes
var _adj := {}  # id -> Array of neighbour ids (sorted)


## A new map from `cfg` (data/drift.json) rolled with `rng`.
static func generate(rng: RandomNumberGenerator, cfg: Dictionary):
	var d = new()
	d._place_nodes(rng, cfg)
	d._link(rng, cfg)
	return d


func node(id: String) -> Dictionary:
	return nodes[_index[id]] if _index.has(id) else {}


func has(id: String) -> bool:
	return _index.has(id)


func neighbours(id: String) -> Array:
	return _adj.get(id, [])


func linked(a: String, b: String) -> bool:
	return _adj.get(a, []).has(b)


func degree(id: String) -> int:
	return _adj.get(id, []).size()


func ids() -> Array:
	return nodes.map(func(n): return n["id"])


## The id of the node where the campaign starts.
func start_id() -> String:
	for n in nodes:
		if n.get("start", false):
			return n["id"]
	return nodes[0]["id"] if not nodes.is_empty() else ""


## The id of the region's exit beacon (the node of type `exit`), "" when the map has none.
func exit_id() -> String:
	for n in nodes:
		if n["type"] == "exit":
			return n["id"]
	return ""


## Is every node reachable from every other along the lanes?
func connected() -> bool:
	return _components().size() <= 1


## The smallest distance between two nodes (INF with fewer than two).
func min_distance() -> float:
	var best := INF
	for i in nodes.size():
		for j in range(i + 1, nodes.size()):
			best = minf(best, nodes[i]["pos"].distance_to(nodes[j]["pos"]))
	return best


# --- save format --------------------------------------------------------------------------------------

func to_dict() -> Dictionary:
	var out_nodes := []
	for n in nodes:
		var e: Dictionary = n.duplicate()
		e["pos"] = [n["pos"].x, n["pos"].y]
		out_nodes.append(e)
	return {"nodes": out_nodes, "lanes": lanes.duplicate(true)}


## A map from a saved dictionary, or null when it is malformed.
static func from_dict(data: Dictionary):
	if not (data.get("nodes") is Array and data.get("lanes") is Array):
		return null
	var d = new()
	for n in data["nodes"]:
		if not (n is Dictionary and n.get("id") is String and n.get("type") is String and n.get("pos") is Array and n["pos"].size() == 2):
			return null
		var e: Dictionary = n.duplicate()
		e["pos"] = Vector2(float(n["pos"][0]), float(n["pos"][1]))
		if d._index.has(e["id"]):
			return null
		d._add(e)
	for l in data["lanes"]:
		if not (l is Array and l.size() == 2 and d._index.has(str(l[0])) and d._index.has(str(l[1]))):
			return null
		d._lane(str(l[0]), str(l[1]))
	return d


# --- making the map -----------------------------------------------------------------------------------

func _add(n: Dictionary) -> void:
	_index[n["id"]] = nodes.size()
	nodes.append(n)
	_adj[n["id"]] = []


func _spaced(p: Vector2, spacing: float) -> bool:
	for n in nodes:
		if n["pos"].distance_to(p) < spacing:
			return false
	return true


func _place_nodes(rng: RandomNumberGenerator, cfg: Dictionary) -> void:
	var m: Dictionary = cfg["map"]
	var size := Vector2(float(m["size"][0]), float(m["size"][1]))
	var spacing := float(m["min_spacing"])
	var margin := float(m["margin"])
	for p in cfg["places"]:
		var pos := Vector2(float(p["pos"][0]), float(p["pos"][1]))
		var jitter := float(p.get("jitter", 0.0))
		if jitter > 0.0:
			for t in 20:
				var q := pos + Vector2(rng.randf_range(-jitter, jitter), rng.randf_range(-jitter, jitter))
				if _spaced(q, spacing):
					pos = q
					break
		_add({"id": str(p["id"]), "name": str(p["name"]), "type": str(p["type"]), "place": str(p["id"]), "faction": str(p.get("faction", "")),
			"hidden_until": str(p.get("hidden_until", "")), "beacon": bool(p.get("beacon", false)), "start": bool(p.get("start", false)), "clan": false, "pos": pos})
	var weights: Dictionary = cfg["node_weights"]
	var keys: Array = weights.keys()
	keys.sort()
	var attempts := int(m.get("attempts", 400))
	var count: int = rng.randi_range(int(m["nodes"][0]), int(m["nodes"][1])) if m["nodes"] is Array else int(m["nodes"])
	var k := 1
	var tries := 0
	var sp := spacing
	while nodes.size() < count:
		var q := Vector2(rng.randf_range(margin, size.x - margin), rng.randf_range(margin, size.y - margin))
		tries += 1
		if _spaced(q, sp):
			var type := _roll_type(rng, weights, keys)
			var clan: bool = type == "trader" and rng.randf() < float(m.get("clan_trader", 0.0))
			_add({"id": "n%02d" % k, "name": "", "type": type, "place": "", "faction": "", "hidden_until": "", "beacon": false, "start": false, "clan": clan, "pos": q})
			k += 1
			tries = 0
		elif tries >= attempts:  # crowded: relax the spacing (never happens with the shipped numbers)
			sp *= 0.9
			tries = 0


func _roll_type(rng: RandomNumberGenerator, weights: Dictionary, keys: Array) -> String:
	var total := 0.0
	for t in keys:
		total += float(weights[t])
	var r := rng.randf() * total
	for t in keys:
		r -= float(weights[t])
		if r < 0.0:
			return str(t)
	return str(keys[-1])


func _lane(a: String, b: String) -> void:
	if a == b or linked(a, b):
		return
	_adj[a].append(b)
	_adj[b].append(a)
	_adj[a].sort()
	_adj[b].sort()
	lanes.append([a, b] if a < b else [b, a])


func _pos(id: String) -> Vector2:
	return nodes[_index[id]]["pos"]


func _dist(a: String, b: String) -> float:
	return _pos(a).distance_to(_pos(b))


## The other node ids, nearest to `id` first (ties by id).
func _nearest(id: String) -> Array:
	var out: Array = ids().filter(func(o): return o != id)
	out.sort_custom(func(x, y):
		var dx := _dist(id, x)
		var dy := _dist(id, y)
		return dx < dy or (dx == dy and x < y))
	return out


static func _cross(o: Vector2, a: Vector2, b: Vector2) -> float:
	return (a - o).cross(b - o)


## Do segments a-b and c-d cross (segments that share an end do not)?
static func _segments_cross(a: Vector2, b: Vector2, c: Vector2, d: Vector2) -> bool:
	if a == c or a == d or b == c or b == d:
		return false
	var d1 := _cross(a, b, c)
	var d2 := _cross(a, b, d)
	var d3 := _cross(c, d, a)
	var d4 := _cross(c, d, b)
	return (d1 > 0.0) != (d2 > 0.0) and (d3 > 0.0) != (d4 > 0.0)


## Would a lane a-b cross a lane that exists, or pass within `clearance` of another node?
func _bad_lane(a: String, b: String, clearance: float) -> bool:
	var pa := _pos(a)
	var pb := _pos(b)
	for l in lanes:
		if _segments_cross(pa, pb, _pos(l[0]), _pos(l[1])):
			return true
	for n in nodes:
		if n["id"] == a or n["id"] == b:
			continue
		var closest := Geometry2D.get_closest_point_to_segment(n["pos"], pa, pb)
		if closest.distance_to(n["pos"]) < clearance:
			return true
	return false


func _link(rng: RandomNumberGenerator, cfg: Dictionary) -> void:
	var m: Dictionary = cfg["map"]
	var lane_min := int(m["lane_min"])
	var lane_max := int(m["lane_max"])
	var clearance := float(m["clearance"])
	var length := float(m["lane_length"])
	# 1. every node asks for 2 lanes, sometimes 3 or 4, to its nearest neighbours that can take one
	for n in nodes:
		var id: String = n["id"]
		var want := lane_min
		if rng.randf() < float(m["lane_third"]):
			want += 1
			if rng.randf() < float(m["lane_fourth"]):
				want += 1
		want = mini(want, lane_max)
		for o in _nearest(id):
			if degree(id) >= want:
				break
			if linked(id, o) or degree(o) >= lane_max or _dist(id, o) > length or _bad_lane(id, o, clearance):
				continue
			_lane(id, o)
	# 2. nobody keeps fewer than lane_min
	for n in nodes:
		var id: String = n["id"]
		for strict in [true, false]:
			for o in _nearest(id):
				if degree(id) >= lane_min:
					break
				if linked(id, o) or degree(o) >= lane_max or (strict and _bad_lane(id, o, clearance)):
					continue
				_lane(id, o)
	# 3. one connected graph: join the closest pair across components, until there is one
	while true:
		var comps := _components()
		if comps.size() <= 1:
			break
		var pair := _closest_pair(comps[0], clearance, lane_max)
		_lane(pair[0], pair[1])


## The connected components, each a sorted array of ids, the one holding the first node first.
func _components() -> Array:
	var seen := {}
	var out := []
	for n in nodes:
		if seen.has(n["id"]):
			continue
		var comp := []
		var stack: Array = [n["id"]]
		seen[n["id"]] = true
		while not stack.is_empty():
			var cur: String = stack.pop_back()
			comp.append(cur)
			for o in _adj[cur]:
				if not seen.has(o):
					seen[o] = true
					stack.append(o)
		comp.sort()
		out.append(comp)
	return out


## The shortest lane that joins component `comp` to the rest: [a, b]. It prefers one that crosses
## nothing and leaves both ends at lane_max or fewer; failing that, any (a fixed place may end up
## with more than lane_max, which keeps the graph connected).
func _closest_pair(comp: Array, clearance: float, lane_max: int) -> Array:
	var inside := {}
	for id in comp:
		inside[id] = true
	for level in 3:
		var best := []
		var best_d := INF
		for a in comp:
			for n in nodes:
				var b: String = n["id"]
				if inside.has(b):
					continue
				if level < 2 and (degree(a) >= lane_max or degree(b) >= lane_max):
					continue
				if level < 1 and _bad_lane(a, b, clearance):
					continue
				var d := _dist(a, b)
				if d < best_d or (d == best_d and [a, b] < best):
					best_d = d
					best = [a, b]
		if not best.is_empty():
			return best
	return [comp[0], ids().filter(func(o): return not inside.has(o))[0]]
