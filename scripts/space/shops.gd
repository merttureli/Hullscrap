extends RefCounted
## Small shops (playtest 2, economy): the stock of a Trader or Store POI. Pure logic over data/drift.json `shops` (its _doc says what
## every number is). A shop carries 3 to 5 items: some from the common pool (the staples every station sells) and 1 or 2 from the
## unique pool: racial parts of the tech_* packs, tier 2 and 3 parts, rare materials (crystal, silicon, titanium), the repair drone and
## now and then a blueprint. The roll is a pure function of the run's seed, the shop's id and the region, so the same seed gives the
## same shop. A shop never offers as unique anything the station of its own region sells (`skip`).
## Item ids: a part, an item or a material by its id; a blueprint as "bp:<recipe id>" (BLUEPRINT).

const Content = preload("res://scripts/data/content.gd")

const BLUEPRINT := "bp:"


## The unique pool: kind -> sorted ids, without `skip` (the ids the region's station sells). Kinds with nothing left are left out.
static func unique_pool(cfg: Dictionary, skip: Array) -> Dictionary:
	var sc: Dictionary = cfg["shops"]
	var lo := int(sc["tier_range"][0])
	var hi := int(sc["tier_range"][1])
	var racial: Array = []
	var tier: Array = []
	for c in Content.list("components"):
		var id := str(c["id"])
		if bool(c.get("unique", false)):  # a quest reward or an enemy's part is never for sale
			continue
		if Content.origin("components", id).begins_with("tech_"):
			racial.append(id)
		elif int(c.get("tier", 1)) >= lo and int(c.get("tier", 1)) <= hi:
			tier.append(id)
	var pool := {"racial": racial, "tier": tier, "material": sc["materials"].keys(), "drone": sc["drone"].keys(),
		"blueprint": sc["blueprints"].keys().map(func(r): return BLUEPRINT + str(r))}
	var out := {}
	for kind in pool:
		var ids: Array = pool[kind].filter(func(id): return not skip.has(id))
		ids.sort()
		if not ids.is_empty():
			out[kind] = ids
	return out


## What `id` (of the unique pool) costs in a shop.
static func unique_price(cfg: Dictionary, id: String) -> int:
	var sc: Dictionary = cfg["shops"]
	if id.begins_with(BLUEPRINT):
		return int(sc["blueprints"][id.trim_prefix(BLUEPRINT)])
	for kind in ["materials", "drone"]:
		if sc[kind].has(id):
			return int(sc[kind][id])
	var c := Content.entry("components", id)
	var v: Dictionary = cfg["values"]
	var value := float(v["unique"]) if bool(c.get("unique", false)) else float(v["tier"].get(str(int(c.get("tier", 1))), 40))
	return maxi(5, roundi(value * float(sc["part_price"]) / 5.0) * 5)


## Roll the shop `shop_id` of a run: {stock (id -> price), qty (id -> units on the shelf), unique (ids from the unique pool)}.
static func roll(cfg: Dictionary, seed_value: int, shop_id: String, region_id: String, skip: Array) -> Dictionary:
	var sc: Dictionary = cfg["shops"]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_value, shop_id, region_id])
	var total := rng.randi_range(int(sc["items"][0]), int(sc["items"][1]))
	var n_unique := mini(rng.randi_range(int(sc["unique"][0]), int(sc["unique"][1])), total - 1)
	var pool := unique_pool(cfg, skip)
	var stock := {}
	var qty := {}
	var unique: Array = []
	for i in n_unique:
		var kind := _kind(rng, sc["kinds"], pool)
		if kind == "":
			break
		var ids: Array = pool[kind]
		var id: String = ids.pop_at(rng.randi() % ids.size())
		if ids.is_empty():
			pool.erase(kind)
		stock[id] = unique_price(cfg, id)
		qty[id] = rng.randi_range(int(sc["material_qty"][0]), int(sc["material_qty"][1])) if kind == "material" else 1
		unique.append(id)
	var common: Array = sc["common"].keys()
	common.sort()
	while stock.size() < total and not common.is_empty():
		var id: String = common.pop_at(rng.randi() % common.size())
		stock[id] = int(sc["common"][id])
		qty[id] = 1
	return {"stock": stock, "qty": qty, "unique": unique}


## A kind of the unique pool by the weights `kinds`, among those with something left. "" when there are none.
static func _kind(rng: RandomNumberGenerator, kinds: Dictionary, pool: Dictionary) -> String:
	var names: Array = pool.keys()
	names.sort()
	var total := 0.0
	for k in names:
		total += float(kinds.get(k, 1.0))
	if names.is_empty() or total <= 0.0:
		return ""
	var x := rng.randf() * total
	for k in names:
		x -= float(kinds.get(k, 1.0))
		if x < 0.0:
			return str(k)
	return str(names[-1])
