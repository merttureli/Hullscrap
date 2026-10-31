extends RefCounted
## What the ship sees of a sector (docs/CONTENT.md section 11, "Radar and beacons"). Pure logic, no nodes.
## - A `beacon` POI is always on the radar, with its type, from anywhere in the sector.
## - A `signal` POI shows within the best radar's range (never less than the visual range).
## - A `hidden` POI shows only within the visual range (data/sectors.json radar.visual, 1,500 px).
## - The type is known for a beacon, within an identifying radar's range, or within the visual range; else the
##   contact is just "contact".
## Radar parts do not exist yet: any working part with stats.radar_range (px) is a radar, and stats.identify (more
## than 0) makes it name what it sees. A powered helm has a built-in Mk0 radar (radar.helm, 3,000 px, no
## identification). A part works when it is not disabled and, if it draws power, is powered (as an intake does).

const Content = preload("res://scripts/data/content.gd")
const CrewFx = preload("res://scripts/crew/crew_fx.gd")

const PATH := "res://data/sectors.json"
const CONTACT := "contact"  ## known_type of a contact whose type is not known yet

static var _radar := {}


## data/sectors.json "radar" (visual, helm), read once.
static func config() -> Dictionary:
	if _radar.is_empty():
		var data = Content.read(PATH)
		assert(data is Dictionary and data.get("radar") is Dictionary, "bad sector data: " + PATH)
		_radar = data["radar"]
	return _radar


## {range, identify_range} of the ship's working radars, in px: the farthest any of them sees, and the farthest one
## that identifies sees (0 when none does). A ship with no working helm and no radar part has {0, 0}.
static func ranges(ship) -> Dictionary:
	var cfg: Dictionary = config()
	var best := 0.0
	var ident := 0.0
	if ship == null:
		return {"range": 0.0, "identify_range": 0.0}
	ship.refresh()
	var off: Dictionary = ship.disabled_uids()
	var powered: Dictionary = ship.power_state.get("powered", {})
	var uids: Array = ship.components.instances.keys()
	uids.sort()
	for uid in uids:
		if off.has(uid):
			continue
		var def: Dictionary = ship.components.def(ship.components.instances[uid]["id"])
		if int(def.get("power", 0)) < 0 and not powered.get(uid, false):
			continue
		var stats: Dictionary = def.get("stats", {})
		var r := float(stats.get("radar_range", 0.0))
		if str(def.get("family", "")) == "helm":
			r = maxf(r, float(cfg["helm"]))  # the helm's built-in Mk0
		best = maxf(best, r)
		if float(stats.get("identify", 0.0)) > 0.0:
			ident = maxf(ident, r)
	return {"range": best, "identify_range": ident}


## How far out `ship` finds things by radar or by eye, in px: the best radar range, never less than the visual range.
static func reach(ship) -> float:
	return maxf(float(ranges(ship)["range"]), float(config()["visual"]))


## The contacts the ship at the sector's `ship_pos` has now, nearest first: [{poi, bearing, distance, known_type, via}].
## `poi` is the sector's POI dictionary (an ambient contact too; a `done` POI stays listed, it is the HUD's call to
## dim it), `bearing` the direction to it in radians in flight.gd's convention (0 up, clockwise on screen, so
## `bearing - flight.angle` is the turn needed), `distance` in px, `known_type` the POI's type or CONTACT, and `via`
## how it is seen: "beacon", "radar" or "visual". While a crew member's scan ability runs (CrewFx.scan_left) the
## radar also finds the hidden contacts within its range, and names what every contact is.
static func contacts(sector, ship) -> Array:
	var r := ranges(ship)
	return contacts_for(sector, float(r["range"]), float(r["identify_range"]), ship != null and CrewFx.scan_left(ship) > 0.0)


## contacts() for given radar numbers (px), so a test or a HUD can ask without a ship. `reveal`: a scan is running.
static func contacts_for(sector, radar_range: float, identify_range: float, reveal := false) -> Array:
	var visual := float(config()["visual"])
	var out := []
	for poi in sector.all_pois():
		var d: float = sector.ship_pos.distance_to(poi["pos"])
		var via := ""
		match str(poi["visibility"]):
			"beacon":
				via = "beacon"
			"signal":
				if d <= maxf(radar_range, visual):
					via = "radar" if d > visual else "visual"
			_:  # hidden
				if d <= visual:
					via = "visual"
				elif reveal and d <= radar_range:
					via = "radar"
		if via == "":
			continue
		var known: bool = via == "beacon" or d <= identify_range or d <= visual or reveal
		out.append({"poi": poi, "bearing": wrapf((poi["pos"] - sector.ship_pos).angle() + PI / 2.0, -PI, PI), "distance": d,
			"known_type": str(poi["type"]) if known else CONTACT, "via": via})
	out.sort_custom(func(a, b): return a["distance"] < b["distance"] or (a["distance"] == b["distance"] and str(a["poi"]["id"]) < str(b["poi"]["id"])))
	return out
