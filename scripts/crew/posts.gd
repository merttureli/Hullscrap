extends RefCounted
## Station posts (playtest 2, K1). A crew member can be posted to a crewable part (CrewMember.post = its uid): the helm, every
## part with manned: true (weapons, the afterburner, smelters) and the families of data/crew.json posts.families (shields, the
## medbay). A posted crew member mans their post for good. Jobs.assign gives them only what allows() lets through: a fire or a
## breach in the room of the post, repairing the post itself, and restocking an ammo rack that feeds their own gun; unposted crew
## use the job board as ever, but leave a held post alone. A crew member has one post and a station holds one crew member;
## the soldier and the repair drones cannot be posted. Posts are saved with the crew (CrewMember.to_dict) and dropped when the
## part is gone (prune). Static functions over a Ship: no nodes.

const Ammo = preload("res://scripts/sim/ammo.gd")
const CrewMember = preload("res://scripts/crew/crew_member.gd")

const FAMILY_ORDER: Array[String] = ["helm", "weapon", "shield", "engine", "medbay", "smelter"]  ## the order of the station bar


static func cfg() -> Dictionary:
	return CrewMember.config().get("posts", {})


## Can part `uid` be posted to? The helm, a part with manned: true, or one of the posts.families.
static func is_station(ship, uid: int) -> bool:
	if not ship.components.instances.has(uid):
		return false
	var def: Dictionary = ship.components.def(ship.components.instances[uid]["id"])
	var family := str(def.get("family", ""))
	return family == "helm" or bool(def.get("manned", false)) or family in cfg().get("families", [])


## The uids of every crewable part of `ship`, in bar order: the helm, weapons, shields, engines, the medbay, smelters, the rest; by uid within.
static func stations(ship) -> Array:
	var out := []
	for uid in ship.components.instances:
		if is_station(ship, uid):
			out.append(uid)
	out.sort_custom(func(a, b):
		var ra := _rank(ship, a)
		var rb := _rank(ship, b)
		return ra < rb or (ra == rb and a < b))
	return out


static func _rank(ship, uid: int) -> int:
	var i := FAMILY_ORDER.find(str(ship.components.def(ship.components.instances[uid]["id"]).get("family", "")))
	return i if i >= 0 else FAMILY_ORDER.size()


## The crew member posted to part `uid`, or null.
static func holder(ship, uid: int):
	for m in ship.crew:
		if m.post == uid:
			return m
	return null


## Part uid -> name of the crew member posted there.
static func holders(ship) -> Dictionary:
	var out := {}
	for m in ship.crew:
		if m.post >= 0:
			out[m.post] = m.name
	return out


## The name of a part, for the bar and the log.
static func name_of(ship, uid: int) -> String:
	if not ship.components.instances.has(uid):
		return "?"
	var id: String = ship.components.instances[uid]["id"]
	return str(ship.components.def(id).get("name", id))


## "" when `m` can be posted, else why not (a short line for the log).
static func refusal(m) -> String:
	if m.is_player:
		return "%s works by hand: no post" % m.name
	if m.is_drone():
		return "%s cannot man a station" % m.name
	return ""


## Post `m` to part `uid` (taking over from whoever held it). Returns what to tell the player.
static func post(ship, m, uid: int) -> String:
	var why := refusal(m)
	if why != "":
		return why
	if not is_station(ship, uid):
		return "%s is not a station" % name_of(ship, uid)
	var prev = holder(ship, uid)
	var line := "%s is posted at %s" % [m.name, name_of(ship, uid)]
	if prev != null and prev != m:
		prev.post = -1
		line += " (%s is relieved)" % prev.name
	m.post = uid
	m.hold = 0.0  # back to work at once
	return line


## Take whoever is posted to part `uid` off it. Returns what to tell the player ("" when nobody was).
static func unpost(ship, uid: int) -> String:
	var m = holder(ship, uid)
	if m == null:
		return ""
	m.post = -1
	return "%s leaves the post at %s" % [m.name, name_of(ship, uid)]


## Forget the posts of parts that are gone, and of crew who cannot hold one.
static func prune(ship) -> void:
	for m in ship.crew:
		if m.post >= 0 and (not is_station(ship, m.post) or refusal(m) != ""):
			m.post = -1


# --- what a posted crew member may leave the post for -------------------------------------------

## The ids of the rooms the post of `m` stands in.
static func rooms_of(ship, uid: int) -> Array:
	var out := []
	if not ship.components.instances.has(uid):
		return out
	for c in ship.components.instances[uid]["cells"]:
		var r: int = ship.atmosphere.room_at(c)
		if r >= 0 and not out.has(r):
			out.append(r)
	return out


## Does the posted crew member `m` take `job` from the board? Their own post (man_station), a fire or a breach in the room of the
## post, repairing the post itself and restocking a rack that feeds their gun: nothing else.
static func allows(ship, m, job: Dictionary) -> bool:
	var uid: int = m.post
	match job["type"]:
		"man_station", "repair_component":
			return int(job["uid"]) == uid
		"extinguish":
			return rooms_of(ship, uid).has(ship.atmosphere.room_at(job["cell"]))
		"repair_breach":
			var mine := rooms_of(ship, uid)
			for d in [Vector2i.ZERO, Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				if mine.has(ship.atmosphere.room_at(job["cell"] + d)):
					return true
			return false
		"restock":
			return feeds(ship, uid).has(int(job["uid"]))
	return false


## The ammo racks that feed weapon `uid`: the usable ones in its room, and the ones on a belt network that reaches it. [] for anything but a weapon.
static func feeds(ship, uid: int) -> Array:
	if not ship.components.instances.has(uid) or Ammo.family_of(ship, uid) != "weapon":
		return []
	var out: Array = Ammo.room_racks(ship, uid).duplicate()
	if not ship.belts.cells.is_empty():
		var plan: Dictionary = ship.belts.analyze(ship)
		for rack in plan.get("touch", {}):
			for net_id in plan["touch"][rack]:
				if plan["nets"][net_id]["weapons"].has(uid) and not out.has(rack):
					out.append(rack)
	return out
