extends RefCounted
## The unlock catalogue (data/unlocks.json and the unlocks.json of every pack, docs/CONTENT.md sections 13 and 19),
## read through the content loader. An unlock is something a landmark or an ending opens for the next runs: a starter
## ship, a starting species, a starting blueprint, a map variant or a hull skin. Which ones a player has is the
## profile's (profile.gd); the event effect `unlock` earns one (events.gd). Entry: {id, kind, name, how, payload}.
## No nodes, no drawing.

const Content = preload("res://scripts/data/content.gd")

## kind -> the payload key it needs.
const KINDS := {"starter_ship": "ship", "species_start": "species", "blueprint": "blueprint", "map_variant": "variant", "skin": "skin"}
## How each kind is called on the ending screen.
const LABELS := {"starter_ship": "starter ship", "species_start": "starting species", "blueprint": "starting blueprint", "map_variant": "map variant", "skin": "hull skin"}
const KEYS: Array[String] = ["id", "kind", "name", "how", "payload", "override", "reason"]


static func all() -> Array:
	return Content.list("unlocks")


static func has(id: String) -> bool:
	return Content.has("unlocks", id)


## The entry of `id`, {} when there is none.
static func entry(id: String) -> Dictionary:
	return Content.entry("unlocks", id)


## What the player is told it is: its name, else its id.
static func name_of(id: String) -> String:
	return str(entry(id).get("name", id))


## How it is earned (the hangar's hint on a locked ship), "" when unknown.
static func how_of(id: String) -> String:
	return str(entry(id).get("how", ""))


## The id of the starter_ship unlock that opens design `ship_id`, "" when none does.
static func for_ship(ship_id: String) -> String:
	for u in all():
		if str(u.get("kind", "")) == "starter_ship" and u.get("payload") is Dictionary and str(u["payload"].get("ship", "")) == ship_id:
			return str(u["id"])
	return ""


## Every problem in the catalogue, one message each naming the file and the unlock. Empty when it is sound.
static func validate() -> Array[String]:
	var out: Array[String] = []
	for u in all():
		var id := str(u["id"])
		var file := Content.file_of("unlocks", id)
		var bad := func(msg: String) -> void: out.append("%s: unlock '%s': %s" % [file if file != "" else "(inline data)", id, msg])
		for k in u:
			if not KEYS.has(k):
				bad.call("unknown key '%s' (known: %s)" % [k, ", ".join(KEYS)])
		var kind := str(u.get("kind", ""))
		if not KINDS.has(kind):
			bad.call("unknown kind '%s' (known: %s)" % [kind, ", ".join(KINDS.keys())])
		for k in ["name", "how"]:
			if not (u.get(k) is String and u[k] != ""):
				bad.call("%s must be a non-empty string" % k)
		if not u.get("payload") is Dictionary:
			bad.call("payload must be an object")
			continue
		if KINDS.has(kind):
			var key: String = KINDS[kind]
			var value = u["payload"].get(key)
			if not (value is String and value != ""):
				bad.call("payload needs \"%s\" (a %s id)" % [key, kind])
			elif kind == "starter_ship" and not Content.has("ships", value):
				bad.call("payload ship '%s' is not a design in data/ships or a pack's ships/" % value)
			elif kind == "species_start" and not Content.has("species", value):
				bad.call("payload species '%s' is unknown" % value)
			elif kind == "blueprint" and not Content.has("recipes", value):
				bad.call("payload blueprint '%s' is not a recipe" % value)
	return out
