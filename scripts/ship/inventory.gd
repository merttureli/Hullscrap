extends RefCounted
## The ship's cargo: how many of each material or item it holds. Plain data, no nodes.

var counts := {}  # id -> int; materials and items share it, zero counts are not stored


func count(id: String) -> int:
	return int(counts.get(id, 0))


## Add `n` of `id`. `n` may be negative; a count never drops below 0.
func add(id: String, n: int) -> void:
	var v := maxi(count(id) + n, 0)
	if v == 0:
		counts.erase(id)
	else:
		counts[id] = v


func can_afford(cost: Dictionary) -> bool:
	for id in cost:
		if count(id) < int(cost[id]):
			return false
	return true


## Pay `cost` (id -> count) in full, or change nothing and return false.
func spend(cost: Dictionary) -> bool:
	if not can_afford(cost):
		return false
	for id in cost:
		add(id, -int(cost[id]))
	return true


func refund(cost: Dictionary) -> void:
	for id in cost:
		add(id, int(cost[id]))


## What is short to pay `cost`: id -> how many more are needed. Empty when it is affordable.
func missing(cost: Dictionary) -> Dictionary:
	var short := {}
	for id in cost:
		var n := int(cost[id]) - count(id)
		if n > 0:
			short[id] = n
	return short


func to_dict() -> Dictionary:
	return counts.duplicate()


## Replace the cargo with a saved one. Returns "" on success, else the reason (nothing changes then).
func load_dict(d: Dictionary) -> String:
	var fresh := {}
	for id in d:
		var v = d[id]
		if not (v is int or v is float) or v < 0 or v != floorf(v):
			return "bad cargo count for " + str(id)
		if int(v) > 0:
			fresh[str(id)] = int(v)
	counts = fresh
	return ""
