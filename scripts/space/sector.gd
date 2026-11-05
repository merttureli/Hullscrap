extends RefCounted
## A sector: the open, real-time region of space a Drift node turns into (docs/CONTENT.md section 11, tuning in
## data/sectors.json). Pure logic, no nodes. It holds the generated layout (the current, the debris density, 2 to 6
## points of interest), the ship's place in it and the rules that tie them: triggers, the point-mass flight, the
## ambient encounters and the save format. Radar visibility is radar.gd; the jump spool is campaign.gd.
## - Generated from the campaign seed and the node alone (generate()), never from the campaign's rng or the jump
##   counter: the same seed and node make the same sector, and a sector made late equals one made at the start.
## - Positions are px in the sector, x right and y down, (0, 0) the top-left corner of the 24,000 px square. The square only frames the
##   generated layout: space has no walls and the ship may fly on for ever.
## - A POI is {id, type, name, pos, visibility (beacon, signal, hidden), event_type, state (new, done), enemy ("" or a
##   ship design id), main (the node's own arrival event happens here)}; an ambient contact is a POI with `ambient`
##   true, a `vel` and a `ttl`; the wreck a won fight leaves is a POI with `wreck` true (add_wreck). All are in all_pois().
## - Far POIs (data/sectors.json `far`): past the layout space is cut into chunks, and each chunk rolls a few POIs of its own from
##   the sector seed mixed with its (x, y). The chunks near the ship are live: their POIs (id f<x>_<y>_<i>, `far` true) are in
##   all_pois(). Only the far POIs that are not new are saved (far_seen), and a done one stays done when its chunk comes back.
## - A `quest` POI is only made in a region that has a quest event of its own (has_quest: the homeland tech quests of
##   data/packs/regions_1 ask for their region by the flag in_<id>): no quest site where there is no quest. A sector made
##   with no region data (a test's) may roll any POI type.
## - Only the POI states (and the far ones that are not new), the ship's place, the wrecks and the ambient clock are saved (to_save):
##   the layout is regenerated.
## - Ambient rolls and fight spawn points use the sector's own rng (saved), so real-time play never moves the
##   campaign's rng, which events and loot use.
## - The Hollow tide (docs/MECHANICS_REVIEW.md P1): the campaign tells the sector it is `hollow` (set_hollow, the one
##   setter; the sector never reads the tide). Then its debris thins, ghosts come for the ship (ambient `hollow` in
##   data/sectors.json) and every POI but a station or store runs a `hollow` event. Not saved: the campaign sets it again on a load.
## - The tide's pressure (tide.gd pressure, set_pressure, the one setter, also from the campaign, not saved): 0 to 1, how near the tide is to this place.
##   The debris thins by lerp(1, 0.4, pressure) before the Hollow multiplier, and the sector view creeps a fog in (hollow_fog.gd).

const Content = preload("res://scripts/data/content.gd")
const Radar = preload("res://scripts/space/radar.gd")
const Flight = preload("res://scripts/sim/flight.gd")
const Stats = preload("res://scripts/sim/stats.gd")
const Abilities = preload("res://scripts/sim/abilities.gd")
const Boarding = preload("res://scripts/board/boarding.gd")
const Flagships = preload("res://scripts/space/flagships.gd")

const PATH := "res://data/sectors.json"
const NEW := "new"
const DONE := "done"
const VISIBILITIES: Array[String] = ["beacon", "signal", "hidden"]
const FAR_NONE := Vector2i(1 << 30, 1 << 30)  ## no chunk

static var _cfg := {}
static var _quest_for := {}  # region id or events tag -> true for the regions with a quest event; "*" when a quest asks for no region
static var _quest_key := ""

var cfg: Dictionary
var seed_value := 0  ## this sector's own seed (seed_for)
var node_id := ""
var node_type := ""  ## the Drift node's type: the sector's theme
var region := ""  ## the id of the region the node is in (data/regions)
var size := 24000.0  ## px, the sector is a square
var arrival := Vector2.ZERO  ## where the ship arrives, near one edge
var current_angle := 0.0  ## the debris current's direction in degrees (0 east, 90 south on the screen, as in data/debris.json)
var current_speed := 40.0  ## px/s
var streams: Array = []  ## the debris' side streams: [{angle (degrees, as current_angle), speed (px/s), share (of the pieces)}]; the main current carries the rest
var density := 1.0  ## the debris density: x the base spawn rate and cap of data/debris.json
var debris_mult := {}  ## debris type id -> weight multiplier: the theme of the node type times the region's `debris`
var pois: Array = []  ## the generated POIs, main first
var ambient: Array = []  ## the passing ships now about (transient; not generated)
var wrecks: Array = []  ## the wrecks won fights left here (add_wreck); saved
var boarded := {}  ## POI id -> what the soldier did aboard it: {kind, name, parts, opened, unlocked, keys, left, cleared} (boarding.gd memory); saved
var wreck_ships := {}  ## wreck id -> {ship: the enemy Ship.to_dict as the fight left it, fight: "won" or "captured"}: the wreck is boarded as that ship (wreck_site.gd); saved. A wreck with none (an older save) is boarded as a generated site
var hostiles: Array = []  ## positions (Vector2, px) of the hostile ships about; the fight in place keeps this list for the jump block
var ship_pos := Vector2.ZERO
var ship_vel := Vector2.ZERO
var ship_angle := 0.0  ## the ship's heading (flight.gd: 0 up, clockwise); it arrives facing the middle of the sector
var accel := 0.0  ## px/s^2 at full thrust: set_flight() reads it from the ship, 0 = the ship cannot fly
var max_speed := 600.0
var damping := 0.25  ## per second
var clock := 0.0  ## seconds spent in the sector (tick)
var rng := RandomNumberGenerator.new()  ## ambient rolls and spawn points
var ambient_weights := {}  ## kind (trader, patrol, pirate) -> weight of the passing ships: the region's `ambient`
var far_seen := {}  ## far POI id -> state, for the far POIs that are not new: remembered when their chunk is not live, and saved
var pressure := 0.0  ## how hard the Hollow tide presses on this place, 0 to 1 (set_pressure)
var hollow := false  ## the Hollow tide has taken this place (set_hollow): ghosts come for the ship and the debris thins
var _poi_mults := {}  # the region's POI weight multipliers (_build): the far POIs use them too
var _far := {}  # live chunk (Vector2i) -> its far POIs
var _far_list: Array = []  # the live far POIs in chunk order
var _far_at := FAR_NONE  # the ship's chunk the live ones were made for
var _amb_t := 0.0  # seconds since the last ambient roll
var _ghost_due := false  # the place fell to the tide with the ship in it: the next tick brings a ghost at once
var _next_amb := 1
var _next_wreck := 1
var _engaged := {}  # POI id -> true while its event is open (or, for a station, until the ship has left); not saved
var _greeted := {}  # station and store POI ids that have greeted this visit; not saved
var _flags := {}  # the campaign's flags, kept at the last trigger(): a boss POI (add_boss) is done once its flag is set; not saved


## data/sectors.json, read once.
static func config() -> Dictionary:
	if _cfg.is_empty():
		var data = Content.read(PATH)
		assert(data is Dictionary and data.get("nodes") is Dictionary, "bad sector data: " + PATH)
		_cfg = data
	return _cfg


## The seed of node `node_id`'s sector in a campaign of seed `campaign_seed` (FNV-1a of the id, mixed with the seed).
static func seed_for(campaign_seed: int, id: String) -> int:
	var h := 2166136261
	for b in id.to_utf8_buffer():
		h = ((h ^ int(b)) * 16777619) & 0xFFFFFFFF
	return (campaign_seed * 1000003) ^ h


## A new sector for `node` (a Drift node dictionary) in region `region_id`. `p_cfg` is data/sectors.json by default.
## `region_data` (the region's file, regions.gd) lays its `debris` and `pois` multipliers over the node type's theme and
## mix and gives the passing ships' `ambient` weights; without it they come from data/sectors.json `regions` by id.
## The ship starts at the arrival point.
static func generate(campaign_seed: int, node: Dictionary, region_id: String, p_cfg: Dictionary = {}, region_data: Dictionary = {}):
	var s = new()
	s.cfg = p_cfg if not p_cfg.is_empty() else config()
	s.node_id = str(node["id"])
	s.node_type = str(node["type"])
	s.region = region_id
	var table: Dictionary = s.cfg["regions"]
	s.ambient_weights = region_data["ambient"] if region_data.get("ambient") is Dictionary else table.get(region_id, table["boneyard"])["ambient"]
	s.seed_value = seed_for(campaign_seed, s.node_id)
	var r := RandomNumberGenerator.new()
	r.seed = s.seed_value
	s._build(r, node, region_data)
	s.rng.seed = s.seed_value + 7919
	s.enter()
	return s


# --- generation ------------------------------------------------------------------------------------------

func _build(r: RandomNumberGenerator, node: Dictionary, region_data: Dictionary) -> void:
	size = float(cfg["size"])
	var a: Dictionary = cfg["arrival"]
	var along := size * (0.5 + r.randf_range(-1.0, 1.0) * float(a["spread"]))
	var inset := float(a["inset"])
	match r.randi() % 4:
		0:
			arrival = Vector2(along, inset)
		1:
			arrival = Vector2(size - inset, along)
		2:
			arrival = Vector2(along, size - inset)
		_:
			arrival = Vector2(inset, along)
	var c: Dictionary = cfg["current"]
	current_angle = r.randf() * 360.0
	current_speed = r.randf_range(float(c["speed"][0]), float(c["speed"][1]))
	var n := _node_cfg()
	density = float(n["density"]) * r.randf_range(0.85, 1.15)
	debris_mult = n.get("debris", {}).duplicate()
	var over: Dictionary = region_data.get("debris", {})
	for k in over:
		debris_mult[k] = float(debris_mult.get(k, 1.0)) * float(over[k])
	_poi_mults = region_data.get("pois", {})
	var types := _mix(r, n, _poi_mults, region_data.is_empty() or has_quest(region, str(region_data.get("events", ""))))
	var pc: Dictionary = cfg["poi"]
	var types_cfg: Dictionary = cfg["poi_types"]
	for i in types.size():
		var type: String = types[i]
		var t: Dictionary = types_cfg[type]
		var pos := _place(r, pc)
		var vis := _roll(r, t["visibility"])
		var ev := node_type if i == 0 else _roll(r, t["event"])
		if i == 0 and node_type == "station":
			vis = "beacon"  # a station always broadcasts
		var label := str(t["label"])
		pois.append({"id": "p%d" % i, "type": type, "name": str(node.get("name", "")) if i == 0 and str(node.get("name", "")) != "" else label,
			"pos": pos, "visibility": vis, "event_type": ev, "state": NEW, "enemy": str(t.get("enemy", "")), "main": i == 0})
	var sc: Dictionary = cfg["streams"]  # rolled last, so the layout above is what it always was
	for k in r.randi_range(int(sc["count"][0]), int(sc["count"][1])) - 1:
		var off := r.randf_range(float(sc["angle_off"][0]), float(sc["angle_off"][1])) * (1.0 if r.randf() < 0.5 else -1.0)
		streams.append({"angle": fposmod(current_angle + off, 360.0), "speed": r.randf_range(float(c["speed"][0]), float(c["speed"][1])),
			"share": r.randf_range(float(sc["share"][0]), float(sc["share"][1]))})


## The POI types of the sector in order: the node's main one, the ones it always has (`also`), then others rolled by the
## node's weights (times the region's `pois` multipliers), within each type's `max`, until the count (rolled in the node's
## range, kept within the sector's) is reached. `quests`: the region has a quest, so a `quest` POI may be rolled.
func _mix(r: RandomNumberGenerator, n: Dictionary, mults: Dictionary = {}, quests := true) -> Array:
	var pc: Dictionary = cfg["poi"]
	var count := clampi(r.randi_range(int(n["count"][0]), int(n["count"][1])), int(pc["count"][0]), int(pc["count"][1]))
	var types: Array = [str(n["main"])]
	var made := {types[0]: 1}
	for t in n.get("also", []):
		types.append(str(t))
		made[str(t)] = int(made.get(str(t), 0)) + 1
	count = maxi(count, types.size())
	var weights: Dictionary = n.get("weights", {})
	while types.size() < count:
		var open := {}
		for t in weights:
			var w := float(weights[t]) * float(mults.get(t, 1.0))
			if t == "quest" and not quests:
				continue
			if w > 0.0 and int(made.get(t, 0)) < int(cfg["poi_types"][t].get("max", 3)):
				open[t] = w
		if open.is_empty():
			break
		var pick := _pick(r, open)
		types.append(pick)
		made[pick] = int(made.get(pick, 0)) + 1
	return types


## Does region `region_id` (its events tag `tag`) have a quest event of its own: a `quest` event that asks for it by
## `requires.region` (its id or tag) or by the flag in_<id> (set while the run is in it), or one that asks for no region at
## all? Read from the events (data/events and the packs), so a region that gets a quest gets quest sites with it.
static func has_quest(region_id: String, tag := "") -> bool:
	var key := "%s|%s|%d" % [Content.root, Content.packs_root, Content.ids("events").size()]
	if key != _quest_key:
		_quest_key = key
		_quest_for = {}
		for ev in Content.events():
			if str(ev.get("type", "")) != "quest":
				continue
			var req: Dictionary = ev["requires"] if ev.get("requires") is Dictionary else {}
			var names := []
			for k in ["region", "flag"]:
				var v = req.get(k, [])
				for x in (v if v is Array else [v]):
					if k == "region" or str(x).begins_with("in_"):
						names.append(str(x).trim_prefix("in_") if k == "flag" else str(x))
			if names.is_empty():
				_quest_for["*"] = true
			for nm in names:
				_quest_for[nm] = true
	return _quest_for.has("*") or _quest_for.has(region_id) or (tag != "" and _quest_for.has(tag))


## A spot 3,000 to 12,000 px from the arrival point, inside the margin, at least `gap` from the others (the gap
## shrinks when a sector is crowded).
func _place(r: RandomNumberGenerator, pc: Dictionary) -> Vector2:
	var gap := float(pc["gap"])
	var margin := float(pc["margin"])
	var lo := float(pc["dist"][0])
	var hi := float(pc["dist"][1])
	for attempt in 400:
		if attempt > 0 and attempt % 100 == 0:
			gap *= 0.7
		var p := arrival + Vector2.from_angle(r.randf() * TAU) * r.randf_range(lo, hi)
		if p.x < margin or p.y < margin or p.x > size - margin or p.y > size - margin:
			continue
		if pois.all(func(q): return q["pos"].distance_to(p) >= gap):
			return p
	return arrival + (Vector2(size, size) / 2.0 - arrival).normalized() * (lo + hi) / 2.0


## Add a boss POI (flagships.gd poi_of: a `boss` race and the `flag` that says it is beaten): placed like the others, from a rng of its own, so the layout of the
## other POIs is what it always was. It is saved with the others' states (its id is "flagship").
func add_boss(poi: Dictionary) -> void:
	var r := RandomNumberGenerator.new()
	r.seed = seed_value ^ 0x5F1A6B
	poi["pos"] = _place(r, cfg["poi"])
	pois.append(poi)


## `v` itself when it is a string, else one key of the weighted object `v`.
static func _roll(r: RandomNumberGenerator, v) -> String:
	return v if v is String else _pick(r, v)


static func _pick(r: RandomNumberGenerator, weights: Dictionary) -> String:
	var keys: Array = weights.keys()
	keys.sort()
	var total := 0.0
	for k in keys:
		total += float(weights[k])
	var x := r.randf() * total
	for k in keys:
		x -= float(weights[k])
		if x < 0.0:
			return str(k)
	return str(keys[-1])


## The node type's entry of data/sectors.json `nodes` (the `empty` one for a type it does not have).
func _node_cfg() -> Dictionary:
	var nodes: Dictionary = cfg["nodes"]
	return nodes[node_type] if nodes.has(node_type) else nodes["empty"]


# --- the far POIs ----------------------------------------------------------------------------------------

## The chunk (data/sectors.json `far`) that point `p` is in.
func chunk_of(p: Vector2) -> Vector2i:
	var c := float(cfg["far"]["chunk"])
	return Vector2i(floori(p.x / c), floori(p.y / c))


## The seed of chunk `ck`'s own rng: the sector's seed mixed with the chunk's (x, y) (FNV-1a over their bytes, then a scramble).
func chunk_seed(ck: Vector2i) -> int:
	var h := 2166136261
	for v in [seed_value & 0xFFFFFFFF, (seed_value >> 32) & 0xFFFFFFFF, ck.x & 0xFFFFFFFF, ck.y & 0xFFFFFFFF]:
		for k in 4:
			h = ((h ^ ((v >> (8 * k)) & 0xFF)) * 16777619) & 0xFFFFFFFF
	h = ((h ^ (h >> 16)) * 0x85EBCA6B) & 0xFFFFFFFF
	h = ((h ^ (h >> 13)) * 0xC2B2AE35) & 0xFFFFFFFF
	return h ^ (h >> 16)


## The far POIs chunk `ck` rolls: `far.count` of them, of the node's own weights (times the region's) limited to `far.types`
## (times the type's multiplier there), within each type's `max` for the chunk, from the chunk's own rng, so the same chunk
## always gives the same ones. A chunk that touches the layout's square (0 to `size`) rolls none. A POI the save or an
## earlier visit remembers as done (far_seen) is done.
func far_pois(ck: Vector2i) -> Array:
	var out := []
	var f: Dictionary = cfg.get("far", {})
	if f.is_empty():
		return out
	var c := float(f["chunk"])
	var lo := Vector2(ck) * c
	if lo.x < size and lo.y < size and lo.x + c > 0.0 and lo.y + c > 0.0:
		return out
	var weights: Dictionary = _node_cfg().get("weights", {})
	var open := {}
	for t in f["types"]:
		var w := float(weights.get(t, 0.0)) * float(f["types"][t]) * float(_poi_mults.get(t, 1.0))
		if w > 0.0:
			open[t] = w
	var r := RandomNumberGenerator.new()
	r.seed = chunk_seed(ck)
	var made := {}
	for i in r.randi_range(int(f["count"][0]), int(f["count"][1])):
		var pick := {}
		for t in open:
			if int(made.get(t, 0)) < int(cfg["poi_types"][t].get("max", 3)):
				pick[t] = open[t]
		if pick.is_empty():
			break
		var type := _pick(r, pick)
		made[type] = int(made.get(type, 0)) + 1
		var t: Dictionary = cfg["poi_types"][type]
		var id := "f%d_%d_%d" % [ck.x, ck.y, i]
		var pos := _far_place(r, ck, out)
		out.append({"id": id, "type": type, "name": str(t["label"]), "pos": pos, "visibility": _roll(r, t["visibility"]), "event_type": _roll(r, t["event"]),
			"state": str(far_seen.get(id, NEW)), "enemy": str(t.get("enemy", "")), "main": false, "far": true})
	return out


## A spot inside chunk `ck`, `poi.margin` in from its edges, at least `poi.gap` from the far POIs `made` already and from the
## placed ones (the gap shrinks when it cannot be kept).
func _far_place(r: RandomNumberGenerator, ck: Vector2i, made: Array) -> Vector2:
	var pc: Dictionary = cfg["poi"]
	var inset := float(pc["margin"])
	var lo := Vector2(ck) * float(cfg["far"]["chunk"]) + Vector2(inset, inset)
	var span := float(cfg["far"]["chunk"]) - 2.0 * inset
	var gap := float(pc["gap"])
	var p := lo
	for attempt in 200:
		if attempt > 0 and attempt % 50 == 0:
			gap *= 0.7
		p = lo + Vector2(r.randf(), r.randf()) * span
		if made.all(func(q): return q["pos"].distance_to(p) >= gap) and pois.all(func(q): return q["pos"].distance_to(p) >= gap):
			return p
	return p


## Make the live chunks the ones within `far.live` chunks of the ship's: new ones roll their POIs, the ones left behind drop
## out and keep their states in far_seen. Cheap while the ship stays in its chunk.
func _far_sync() -> void:
	if not cfg.has("far"):
		return
	var here := chunk_of(ship_pos)
	if here == _far_at:
		return
	_far_at = here
	var live := int(cfg["far"]["live"])
	var fresh := {}
	for dy in range(-live, live + 1):
		for dx in range(-live, live + 1):
			var ck := here + Vector2i(dx, dy)
			fresh[ck] = _far[ck] if _far.has(ck) else far_pois(ck)
	for ck in _far:
		if not fresh.has(ck):
			for p in _far[ck]:
				if p["state"] != NEW:
					far_seen[p["id"]] = p["state"]
	_far = fresh
	var keys: Array = _far.keys()
	keys.sort_custom(func(a, b): return a.y < b.y or (a.y == b.y and a.x < b.x))
	_far_list = []
	for ck in keys:
		_far_list.append_array(_far[ck])


# --- the POIs --------------------------------------------------------------------------------------------

## Every POI the sector has now: the generated ones, the wrecks, the passing ships, then the far ones of the live chunks.
func all_pois() -> Array:
	_far_sync()
	return pois + wrecks + ambient + _far_list


## The POI with id `id`, {} when there is none.
func find(id: String) -> Dictionary:
	for p in pois:
		if p["id"] == id:
			return p
	_far_sync()
	for p in wrecks + ambient + _far_list:
		if p["id"] == id:
			return p
	return {}


## The POI of the node's own arrival event.
func main_poi() -> Dictionary:
	return pois[0] if not pois.is_empty() else {}


## The ship arrives (a jump, a tow): at the arrival point, at rest, with no passing ship, hostile or greeting left over.
## The POIs keep what is done.
func enter() -> void:
	ship_pos = arrival
	ship_vel = Vector2.ZERO
	ship_angle = wrapf((Vector2(size, size) / 2.0 - arrival).angle() + PI / 2.0, -PI, PI)
	ambient.clear()
	hostiles.clear()
	_engaged.clear()
	_greeted.clear()
	_amb_t = 0.0
	_ghost_due = false
	_far_at = FAR_NONE  # the live chunks are looked at again from the arrival point


## Is point `p` inside the generated layout's square (grown by `slack` px)? Space itself has no walls.
func contains(p: Vector2, slack := 0.0) -> bool:
	return p.x >= -slack and p.y >= -slack and p.x <= size + slack and p.y <= size + slack


# --- triggers --------------------------------------------------------------------------------------------

## The nearest `new` POI within the trigger distance (800 px) runs its event, once. Returns {} when there is none, else
## {poi, node, refused, event, dock}: what Campaign.arrive() returns for the node's old arrival event (the main POI
## runs exactly that: a dock master's refusal, a debt call, the greeting or the node's event), `event` for any other
## POI one picked from its event type by events.gd ({} when nothing fits), and `dock`: the station menu opens
## (a station or store with a menu, and no refusal), and `shop`: the id of the small shop (campaign.gd shop_id) the menu is when the POI is a
## Trader or Store (data/sectors.json poi_types `shop`), else "". A POI stays engaged until resolve(): it does not fire again. A
## station or store never becomes done: it greets once per visit, later only docks, and docks again after the ship has
## left (1.5 x the trigger distance) and come back.
func trigger(c, ship) -> Dictionary:
	var pc: Dictionary = cfg["poi"]
	var near := float(pc["trigger"])
	var away := near * float(pc["rearm"])
	var best := {}
	var best_d := INF
	_flags = c.flags
	for poi in all_pois():
		if poi.has("boss") and _flags.has(str(poi["flag"])):  # a beaten flagship is done
			poi["state"] = DONE
		if poi["state"] != NEW:
			continue
		var d := ship_pos.distance_to(poi["pos"])
		if _engaged.has(poi["id"]):
			if d > away:
				_engaged.erase(poi["id"])
			continue
		if d <= near and d < best_d:
			best = poi
			best_d = d
	if best.is_empty():
		return {}
	_engaged[best["id"]] = true
	var t: Dictionary = cfg["poi_types"].get(best["type"], {})
	var res: Dictionary
	if bool(t.get("repeat", false)) and _greeted.has(best["id"]):
		res = {"node": c.node(node_id), "refused": "", "event": {}}
	else:
		res = _event_for(c, ship, best)
		if res["refused"] == "" and not hollow and not res["event"].is_empty() and Boarding.kind_for(best) != "":
			res["event"] = Boarding.offer(res["event"], Boarding.kind_for(best))  # a vessel the soldier can board
	_greeted[best["id"]] = true
	res["poi"] = best
	res["shop"] = c.shop_id(node_id, str(best["id"])) if bool(t.get("shop", false)) and res["refused"] == "" and not c.station_cfg(c.shop_id(node_id, str(best["id"]))).is_empty() else ""
	res["dock"] = res["shop"] != "" or (bool(t.get("dock", false)) and res["refused"] == "" and c.dock_block(node_id) == "")
	if bool(t.get("repeat", false)) and res["event"].is_empty() and not res["dock"] and res["refused"] == "":
		return {}
	return res


func _event_for(c, ship, poi: Dictionary) -> Dictionary:
	if poi["main"] and c.current == node_id:
		return c.arrive(ship)
	var kind := str(poi["event_type"])
	if hollow and not bool(cfg["poi_types"].get(poi["type"], {}).get("repeat", false)):
		kind = "hollow"  # the tide has taken the place: every POI but a station or store sends ghosts and dead beacons, no rewards
	elif poi.has("boss"):  # a race flagship: its own page (flagships.gd), not one of the events
		var page := Flagships.event(c, ship, poi)
		c.events_seen += int(not page.is_empty())
		return {"node": c.node(node_id), "refused": "", "event": page}
	var ev: Dictionary = c.HOSTILE_PATROL if kind == "patrol" and c.refuses("concord") else c.events.pick(c, {"id": node_id, "type": kind, "place": ""}, ship)
	if ev.is_empty() and kind == "hollow":  # a ghost always meets the ship (the tide pack has the real events)
		ev = c.HOSTILE_HOLLOW
	c.events_seen += int(not ev.is_empty())
	return {"node": c.node(node_id), "refused": "", "event": ev}


## The event of POI `id` is over: it is done (a station or store stays new, see trigger()). Call it when the event
## panel has no more pages, whatever was chosen. An ambient contact is gone.
func resolve(id: String) -> void:
	var poi := find(id)
	if poi.is_empty():
		return
	if bool(cfg["poi_types"].get(poi["type"], {}).get("repeat", false)):
		return
	if poi.has("boss") and not _flags.has(str(poi["flag"])):  # a flagship that was not beaten stays: it hails again when the ship comes back
		return
	poi["state"] = DONE
	_engaged.erase(id)
	if poi.get("ambient", false):
		ambient.erase(poi)


## Are all the generated POIs done (a station or store counts as done)?
func cleared() -> bool:
	return pois.all(func(p): return p["state"] == DONE or bool(cfg["poi_types"].get(p["type"], {}).get("repeat", false)))


## The design a `fight` effect of `value` at POI `id` sends ("" for an unknown POI): what fight_spawn hands the combat, and
## what the event panel rates before the fight is chosen (it rolls nothing of the sector's own).
func fight_design(c, id: String, value := "tier") -> String:
	var poi := find(id)
	if poi.is_empty():
		return ""
	return c.fight_path(str(poi["enemy"]), "") if value == "tier" and poi["enemy"] != "" and not hollow else c.fight_path(value, str(poi["event_type"]))


## A `fight` effect at POI `id` (`value`: "tier" or a design id, as in events.gd): {design (a res:// path), pos (where
## the enemy appears, 250 to 600 px from the POI), poi (its id)}. The design is the POI's own `enemy` when it has one
## and the effect says "tier", else Campaign.fight_path()'s (the tier tables; a rammer for a pirate after two missed
## payments). {} for an unknown POI. Combat stays the arena for now.
func fight_spawn(c, id: String, value := "tier") -> Dictionary:
	var poi := find(id)
	if poi.is_empty():
		return {}
	var design := fight_design(c, id, value)
	var s: Array = cfg["poi"]["spawn"]
	var pos: Vector2 = poi["pos"] + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(float(s[0]), float(s[1]))
	return {"design": design, "pos": pos, "poi": id}


## A won fight leaves the enemy's wreck at `pos`: a new `wreck` POI (a signal, its event a wreck_field one: the salvage)
## that stays until it is done and is saved with the sector. Returns it.
func add_wreck(pos: Vector2, label := "") -> Dictionary:
	var w := _wreck("w%d" % _next_wreck, pos, label)
	_next_wreck += 1
	wrecks.append(w)
	return w


func _wreck(id: String, pos: Vector2, label: String) -> Dictionary:
	return {"id": id, "type": "wreck", "name": label if label != "" else str(cfg["poi_types"]["wreck"]["label"]), "pos": pos,
		"visibility": "signal", "event_type": "wreck_field", "state": NEW, "enemy": "", "main": false, "wreck": true}


## Where the hostile ships about are (px): the enemy of a fight in place (hostiles) and the passing pirates still to meet.
## Build mode's red alert reads it.
func hostile_ships() -> Array:
	var out := hostiles.duplicate()
	for a in ambient:
		if a["event_type"] in ["pirate", "hollow"] and a["state"] == NEW:
			out.append(a["pos"])
	return out


## Is a hostile ship within `radius` px of the ship (the jump drive does not spool then)?
func hostile_near(radius: float) -> bool:
	return hostiles.any(func(p): return ship_pos.distance_to(p) <= radius)


# --- flying ----------------------------------------------------------------------------------------------

## The flight numbers of `ship` for fly(): {accel (px/s^2 at full thrust: the powered engines' forward thrust x
## thrust_to_accel / mass, 0 when the ship cannot fly), max_speed, damping}, from flight.gd and data/flight.json.
static func flight_numbers(ship) -> Dictionary:
	ship.refresh()
	var f := Flight.new()
	var powered: Dictionary = ship.power_state.get("powered", {})
	var mass := f.mass_of(ship.grid, ship.components, ship.cables, Stats.mass_mults(ship.components, ship.lines))
	var thrust := 0.0
	if f.can_fly(ship.components, powered) == "":
		thrust = float(f.thrusts_of(Stats.view(ship.components, ship.lines), powered, Abilities.thrust_boost(ship))["fwd"])
	return {"accel": thrust * f.thrust_to_accel / mass, "max_speed": f.max_speed, "damping": f.linear_damping}


## Take the flight numbers from `ship`. Call it on arrival and whenever its engines, mass or power change.
func set_flight(ship) -> void:
	var n := flight_numbers(ship)
	accel = float(n["accel"])
	max_speed = float(n["max_speed"])
	damping = float(n["damping"])


## Fly `dt` seconds as a point mass: `thrust` is the wanted thrust as a vector in sector directions (length 0 to 1, the
## fraction of full acceleration; longer is cut to 1), the speed fades with `damping` and is capped at `max_speed`.
## Nothing stops the ship: space has no walls. The current does not push the ship (it moves the debris); an autopilot or a
## drifting helm adds what it wants to `thrust`.
func fly(dt: float, thrust := Vector2.ZERO) -> void:
	if dt <= 0.0:
		return
	ship_vel += thrust.limit_length(1.0) * accel * dt
	ship_vel = (ship_vel * exp(-damping * dt)).limit_length(max_speed)
	ship_pos += ship_vel * dt


# --- the current and the debris --------------------------------------------------------------------------

func current_dir() -> Vector2:
	return Vector2.from_angle(deg_to_rad(current_angle))


func current_vel() -> Vector2:
	return current_dir() * current_speed


## `base` (data/debris.json) with this sector's current, streams, density and theme: the current's direction and speed, its
## side streams, the spawn rate, cap and starting pieces times the density, the type weights times the node type's multipliers.
## drift_debris.gd builds its spawner from it (DriftDebris.for_sector).
func debris_cfg(base: Dictionary) -> Dictionary:
	var out := base.duplicate(true)
	out["current"]["angle"] = current_angle
	out["current"]["speed"] = current_speed
	out["streams"] = streams.duplicate(true)
	var s: Dictionary = out["spawn"]
	var d := density * lerpf(1.0, float(cfg["pressure"]["debris"]), pressure) * (float(cfg["ambient"].get("hollow", {}).get("debris", 1.0)) if hollow else 1.0)  # the tide near thins the current, the Hollow eats it
	s["every"] = float(s["every"]) / d
	s["max_alive"] = maxi(8, roundi(float(s["max_alive"]) * d))
	s["start_alive"] = roundi(float(s["start_alive"]) * d)
	for t in out["types"]:
		t["weight"] = float(t["weight"]) * float(debris_mult.get(t["id"], 1.0))
	return out


# --- ambient encounters ----------------------------------------------------------------------------------

## `dt` seconds pass in the sector: the passing ships move and leave when their time is up or they are farther than 3 x the
## radar's reach from the ship, the live far chunks follow the ship, and every `ambient.every` seconds (90) the sector rolls for a new one. `ship` gives the radar's reach (it may be
## null: the visual range then). Returns the contacts made now.
func tick(dt: float, ship) -> Array:
	if dt <= 0.0:
		return []
	clock += dt
	_far_sync()
	var away := Radar.reach(ship) * 3.0 if not ambient.is_empty() else 0.0
	var i := 0
	while i < ambient.size():
		var a: Dictionary = ambient[i]
		a["pos"] += a["vel"] * dt
		a["ttl"] -= dt
		if a["ttl"] <= 0.0 or a["pos"].distance_to(ship_pos) > away:
			_engaged.erase(a["id"])
			ambient.remove_at(i)
		else:
			i += 1
	var amb := _ambient_rule()
	var made := []
	if _ghost_due:
		_ghost_due = false
		made.append(_roll_ambient(ship, true))
	_amb_t += dt
	while _amb_t >= float(amb["every"]):
		_amb_t -= float(amb["every"])
		var c := _roll_ambient(ship)
		if not c.is_empty():
			made.append(c)
	return made


## The ambient numbers in force: data/sectors.json `ambient`, with its `hollow` block laid over them in a Hollow place.
func _ambient_rule() -> Dictionary:
	var amb: Dictionary = cfg["ambient"]
	return amb.merged(amb["hollow"], true) if hollow and amb.get("hollow") is Dictionary else amb


## The Hollow tide's call for this sector (campaign.gd is the only caller: on arrival, on a load, and when a jump, a wait or
## lingering takes the place). `mid_stay`: the ship is in the place as it falls, so one ghost appears at the next tick
## (and the roll's clock starts again). A place that is Hollow already, or a quiet call (arrival, load), brings none.
func set_hollow(h: bool, mid_stay := false) -> void:
	if h and mid_stay and not hollow:
		_ghost_due = true
		_amb_t = 0.0
	hollow = h


## The tide's pressure on this place (campaign.gd, with set_hollow: on arrival, on a load and as the tide or the linger clock moves), kept in 0 to 1.
func set_pressure(p: float) -> void:
	pressure = clampf(p, 0.0, 1.0)


## One ambient roll: with chance `ambient.chance` (and fewer than `max` about) an `unknown` contact appears at
## `edge` x the radar's reach from the ship, in a random direction. Its kind (trader,
## patrol or pirate: the event type it will run) is picked by the region's weights (ambient_weights). In a Hollow place
## the kind is always `hollow` (a ghost) and the `hollow` rolls apply; `force` (the ghost of a place that has just
## fallen) skips the chance and the `max`.
func _roll_ambient(ship, force := false) -> Dictionary:
	var amb: Dictionary = cfg["ambient"]
	var rule := _ambient_rule()
	var lucky := rng.randf() < float(rule["chance"])
	if not force and (not lucky or ambient.size() >= int(amb["max"])):
		return {}
	var kind := "hollow" if hollow else _pick(rng, ambient_weights)
	var dist := Radar.reach(ship) * float(amb["edge"])
	var at := ship_pos + Vector2.from_angle(rng.randf() * TAU) * dist
	var speed := rng.randf_range(float(amb["speed"][0]), float(amb["speed"][1]))
	var to := ship_pos
	if rng.randf() >= float(rule["approach"]):  # it passes by, to one side of the ship
		var side := (ship_pos - at).normalized().orthogonal() * (1.0 if rng.randf() < 0.5 else -1.0)
		to = ship_pos + side * rng.randf_range(1500.0, 3000.0)
	var contact := {"id": "a%d" % _next_amb, "type": "unknown", "name": str(cfg["poi_types"]["unknown"]["label"]), "pos": at, "visibility": "signal",
		"event_type": kind, "state": NEW, "enemy": "", "main": false, "ambient": true, "vel": (to - at).normalized() * speed, "ttl": float(amb["ttl"])}
	_next_amb += 1
	ambient.append(contact)
	return contact


# --- save format -----------------------------------------------------------------------------------------

## What is saved of the sector: the POI states, the far POIs that are not new, the ship's place, speed and heading, the
## wrecks, the ambient clock and the ships about. The layout itself comes from the seed.
func to_save() -> Dictionary:
	var states := {}
	for p in pois:
		states[p["id"]] = p["state"]
	var far := far_seen.duplicate()
	for p in _far_list:
		if p["state"] != NEW:
			far[p["id"]] = p["state"]
	var list := []
	for a in ambient:
		list.append({"id": a["id"], "kind": a["event_type"], "pos": [a["pos"].x, a["pos"].y], "vel": [a["vel"].x, a["vel"].y], "ttl": a["ttl"], "state": a["state"]})
	var hulks := []
	for w in wrecks:
		hulks.append({"id": w["id"], "name": w["name"], "pos": [w["pos"].x, w["pos"].y], "state": w["state"]})
	var out := {"pois": states, "far": far, "ship": [ship_pos.x, ship_pos.y], "vel": [ship_vel.x, ship_vel.y], "angle": ship_angle, "ambient": list, "amb_t": _amb_t,
		"next_amb": _next_amb, "clock": clock, "rng": str(rng.state), "wrecks": hulks, "next_wreck": _next_wreck}
	if not boarded.is_empty():
		out["boarded"] = boarded.duplicate(true)
	if not wreck_ships.is_empty():
		out["wreck_ships"] = wreck_ships.duplicate(true)
	return out


## Replace the POI states, the ship's place, the wrecks and the ambient state with a saved one. Returns "" or why not
## (and nothing changes). A saved POI this layout does not have is ignored; a save from before the heading and the
## wrecks has none of them, nor one from before the far POIs (campaign save version 8) any done far POI.
func load_save(d: Dictionary) -> String:
	if not (d.get("pois") is Dictionary and d.get("ambient") is Array and _vec(d.get("ship")) != null and _vec(d.get("vel")) != null):
		return "bad sector data"
	for id in d["pois"]:
		if not (d["pois"][id] is String and [NEW, DONE].has(d["pois"][id])):
			return "bad sector data"
	if not d.get("far", {}) is Dictionary:
		return "bad sector data"
	for id in d.get("far", {}):
		if not ([NEW, DONE].has(d["far"][id]) and d["far"][id] is String):
			return "bad sector data"
	var contacts := []
	for e in d["ambient"]:
		if not (e is Dictionary and e.get("id") is String and e.get("kind") is String and _vec(e.get("pos")) != null and _vec(e.get("vel")) != null and _is_num(e.get("ttl"))):
			return "bad sector data"
		var state := str(e.get("state", NEW))
		contacts.append({"id": e["id"], "type": "unknown", "name": str(cfg["poi_types"]["unknown"]["label"]), "pos": _vec(e["pos"]), "visibility": "signal",
			"event_type": e["kind"], "state": state if [NEW, DONE].has(state) else NEW, "enemy": "", "main": false, "ambient": true, "vel": _vec(e["vel"]), "ttl": float(e["ttl"])})
	var hulks := []
	if not d.get("wrecks", []) is Array:
		return "bad sector data"
	for e in d.get("wrecks", []):
		if not (e is Dictionary and e.get("id") is String and _vec(e.get("pos")) != null):
			return "bad sector data"
		var w := _wreck(e["id"], _vec(e["pos"]), str(e.get("name", "")))
		w["state"] = str(e.get("state", NEW)) if [NEW, DONE].has(str(e.get("state", NEW))) else NEW
		hulks.append(w)
	var ships := {}  # (a malformed one is dropped: the wreck is boarded as a generated site)
	if d.get("wreck_ships") is Dictionary:
		for id in d["wreck_ships"]:
			var e = d["wreck_ships"][id]
			if e is Dictionary and e.get("ship") is Dictionary:
				ships[str(id)] = {"ship": e["ship"].duplicate(true), "fight": str(e.get("fight", "won"))}
	var memory := {}
	if not d.get("boarded", {}) is Dictionary:
		return "bad sector data"
	for id in d.get("boarded", {}):
		var m = d["boarded"][id]
		if not (m is Dictionary and m.get("kind") is String and Boarding.has_kind(m["kind"]) and m.get("opened", []) is Array and m.get("unlocked", []) is Array and m.get("left", {}) is Dictionary):
			return "bad sector data"
		memory[str(id)] = m.duplicate(true)
		memory[str(id)]["parts"] = m["parts"] if m.get("parts") is Array else []
		memory[str(id)]["name"] = str(m.get("name", ""))
		memory[str(id)]["keys"] = m["keys"] if m.get("keys") is Array else []
	for p in pois:
		if d["pois"].has(p["id"]):
			p["state"] = d["pois"][p["id"]]
	boarded = memory
	wreck_ships = ships
	ship_pos = _vec(d["ship"])
	far_seen = {}
	for id in d.get("far", {}):
		if d["far"][id] != NEW:
			far_seen[str(id)] = d["far"][id]
	_far = {}
	_far_list = []
	_far_at = FAR_NONE
	ship_vel = _vec(d["vel"])
	if _is_num(d.get("angle")):
		ship_angle = wrapf(float(d["angle"]), -PI, PI)
	wrecks = hulks
	_next_wreck = int(d.get("next_wreck", hulks.size() + 1)) if _is_num(d.get("next_wreck")) else hulks.size() + 1
	ambient = contacts
	_amb_t = float(d.get("amb_t", 0.0)) if _is_num(d.get("amb_t")) else 0.0
	_next_amb = int(d.get("next_amb", 1)) if _is_num(d.get("next_amb")) else 1
	clock = float(d.get("clock", 0.0)) if _is_num(d.get("clock")) else 0.0
	if d.get("rng") is String and str(d["rng"]).is_valid_int():
		rng.state = int(str(d["rng"]))
	_engaged.clear()
	_greeted.clear()
	return ""


static func _is_num(v) -> bool:
	return v is float or v is int


## A saved [x, y] as a Vector2, null when it is not one.
static func _vec(v):
	if v is Array and v.size() == 2 and _is_num(v[0]) and _is_num(v[1]):
		return Vector2(float(v[0]), float(v[1]))
	return null
