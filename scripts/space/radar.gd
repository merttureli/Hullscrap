extends RefCounted
## What the ship sees of a sector (docs/CONTENT.md section 11, "Radar and beacons"). Pure logic, no nodes.
## - A `beacon` POI is always on the radar, with its type, from anywhere in the sector (a far one only while its chunk is live, sector.gd).
## - A `signal` POI shows within the best radar's range (never less than the visual range).
## - A `hidden` POI shows only within the visual range (data/sectors.json radar.visual, 1,500 px), or within the range
##   of a radar with stats.see_hidden (the Mk3).
## - The type is known for a beacon, within an identifying radar's range, or within the visual range; else the
##   contact is just "contact".
## Any working part with stats.radar_range (px) is a radar (the Radar Mk1 to Mk3 are hull mounts: an inside console and an
## outside dish), stats.identify (more than 0) makes it name what it sees and rate a ship's threat (threat()), and
## stats.see_hidden (more than 0) lets it see the hidden contacts in its range. A powered helm has a built-in Mk0 radar
## (radar.helm, 3,000 px, no identification). A part works when it is not disabled (a dish shot off, which is the outside
## half of the mount, or a cut link blinds its console) and, if it draws power, is powered (as an intake does).

const Content = preload("res://scripts/data/content.gd")
const CrewFx = preload("res://scripts/crew/crew_fx.gd")
const Shipgen = preload("res://scripts/space/shipgen.gd")

const PATH := "res://data/sectors.json"
const CONTACT := "contact"  ## known_type of a contact whose type is not known yet
## The event types of a passing ship (or a nest) that may fight, and the enemy table they roll from (Campaign.fight_path), and what
## an identified passing ship is called.
const FIGHTERS := {"pirate": "pirate", "patrol": "patrol"}
const SHIP_NAMES := {"pirate": "Pirate ship", "patrol": "Patrol ship", "trader": "Trader"}

static var _radar := {}


## data/sectors.json "radar" (visual, helm), read once.
static func config() -> Dictionary:
	if _radar.is_empty():
		var data = Content.read(PATH)
		assert(data is Dictionary and data.get("radar") is Dictionary, "bad sector data: " + PATH)
		_radar = data["radar"]
	return _radar


## {range, identify_range, hidden_range} of the ship's working radars, in px: the farthest any of them sees, the farthest one
## that identifies sees and the farthest one that sees hidden contacts sees (0 when none does). A ship with no working helm
## and no radar part has all 0.
static func ranges(ship) -> Dictionary:
	var cfg: Dictionary = config()
	var best := 0.0
	var ident := 0.0
	var hidden := 0.0
	if ship == null:
		return {"range": 0.0, "identify_range": 0.0, "hidden_range": 0.0}
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
		if float(stats.get("see_hidden", 0.0)) > 0.0:
			hidden = maxf(hidden, r)
	return {"range": best, "identify_range": ident, "hidden_range": hidden}


## How far out `ship` finds things by radar or by eye, in px: the best radar range, never less than the visual range.
static func reach(ship) -> float:
	return maxf(float(ranges(ship)["range"]), float(config()["visual"]))


## The contacts the ship at the sector's `ship_pos` has now, nearest first: [{poi, bearing, distance, known_type, via}].
## `poi` is the sector's POI dictionary (an ambient contact too; a `done` POI stays listed, it is the HUD's call to
## dim it), `bearing` the direction to it in radians in flight.gd's convention (0 up, clockwise on screen, so
## `bearing - flight.angle` is the turn needed), `distance` in px, `known_type` the POI's type or CONTACT, `via`
## how it is seen: "beacon", "radar" or "visual", and `scanned`: an identifying radar covers it (Mk2 and up: a ship's threat
## can be rated, threat()). While a crew member's scan ability runs (CrewFx.scan_left) the radar also finds the hidden
## contacts within its range, and names and scans every contact.
static func contacts(sector, ship) -> Array:
	var r := ranges(ship)
	return contacts_for(sector, float(r["range"]), float(r["identify_range"]), ship != null and CrewFx.scan_left(ship) > 0.0, float(r["hidden_range"]))


## contacts() for given radar numbers (px), so a test or a HUD can ask without a ship. `reveal`: a scan is running.
## `hidden_range`: how far a radar that sees hidden contacts sees (the Mk3).
static func contacts_for(sector, radar_range: float, identify_range: float, reveal := false, hidden_range := 0.0) -> Array:
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
				elif (reveal and d <= radar_range) or d <= hidden_range:
					via = "radar"
		if via == "":
			continue
		var scanned: bool = d <= identify_range or reveal
		var known: bool = via == "beacon" or scanned or d <= visual
		out.append({"poi": poi, "bearing": wrapf((poi["pos"] - sector.ship_pos).angle() + PI / 2.0, -PI, PI), "distance": d,
			"known_type": str(poi["type"]) if known else CONTACT, "via": via, "scanned": scanned})
	out.sort_custom(func(a, b): return a["distance"] < b["distance"] or (a["distance"] == b["distance"] and str(a["poi"]["id"]) < str(b["poi"]["id"])))
	return out


# --- what a contact is called, and how dangerous it is -----------------------------------------------------------

## The enemy table ("pirate" or "patrol") of the ship behind POI `poi` when it may fight, else "": a passing pirate or patrol
## ship, or a pirate nest. A trader, an unknown ship (it could be anything) or a checkpoint says nothing.
static func fighter_kind(poi: Dictionary) -> String:
	if bool(poi.get("ambient", false)):
		return str(FIGHTERS.get(str(poi.get("event_type", "")), ""))
	return "pirate" if str(poi.get("type", "")) == "pirate_nest" else ""


## What the HUD calls contact `ct` of contacts(): "Contact" while its type is not known, a passing ship by its kind once it is
## (Pirate ship, Patrol ship, Trader), else the POI's own name.
static func title(ct: Dictionary) -> String:
	if ct["known_type"] == CONTACT:
		return "Contact"
	var poi: Dictionary = ct["poi"]
	if bool(poi.get("ambient", false)):
		return str(SHIP_NAMES.get(str(poi.get("event_type", "")), poi["name"]))
	return str(poi["name"])


## The threat of the ship behind contact `ct` of contacts() against `ship`, 1 to 5 skulls (Shipgen.threat_of, docs/CONTENT.md
## section 14), 0 when it shows none: only an identifying radar (Mk2 and up, or a scan) rates, and only a ship that may fight
## (fighter_kind). `c` is the campaign: the ship rated is the one a fight here would send (the tier table of the kind, as
## Campaign.fight_path rolls it); its rng is put back as it was, so looking at a contact moves nothing.
static func threat(c, ship, ct: Dictionary) -> int:
	var design := design_of(c, ship, ct)
	return 0 if design == "" else int(Shipgen.threat_of(design, ship).get("skulls", 0))


## The design (a generated spec) of the ship behind contact `ct`, "" when it shows none: the same rule as threat(), for the card and the marker
## that show her ship instead of a rating. The campaign's rng is put back as it was.
static func design_of(c, ship, ct: Dictionary) -> String:
	var kind := fighter_kind(ct["poi"])
	if kind == "" or not bool(ct.get("scanned", false)) or c == null or ship == null:
		return ""
	var at = c.rng.state
	var design: String = c.fight_path("tier", kind)
	c.rng.state = at
	return design