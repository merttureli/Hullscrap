extends RefCounted
## The unlock catalogue (data/unlocks.json and the unlocks.json of every pack, docs/CONTENT.md sections 13 and 19),
## read through the content loader. An unlock is something a landmark or an ending opens for the next runs: a starter
## ship, a starting species, a starting blueprint, a map variant or a hull skin. Which ones a player has is the
## profile's (profile.gd); the event effect `unlock` earns one (events.gd). Entry: {id, kind, name, how, payload}; `pending: true` marks a starter_ship whose design is not built yet (it validates, and the hangar has nothing to show for it until the design lands).
## What each kind does at the start of a run is run_start.gd's; the payload keys it reads are PAYLOAD_KEYS (data/unlocks.json
## `_doc` says what they mean). No nodes, no drawing.

const Content = preload("res://scripts/data/content.gd")

## kind -> the payload key it needs.
const KINDS := {"starter_ship": "ship", "species_start": "species", "blueprint": "blueprint", "map_variant": "variant", "skin": "skin"}
## How each kind is called on the ending screen.
const LABELS := {"starter_ship": "starter ship", "species_start": "starting species", "blueprint": "starting blueprint", "map_variant": "map variant", "skin": "hull skin"}
const KEYS: Array[String] = ["id", "kind", "name", "how", "payload", "override", "reason", "pending"]
## The payload keys of each kind: the first is the one that names the thing (KINDS), the rest tune it. starter_ship: group and
## layout are the hangar's own (hangar.gd reads the design). species_start: name (the soldier's). map_variant: tide_steps (the
## Hollow tide of every region starts that many steps on). skin: tint and lamp (#rrggbb: the multiply tint of the hull skin and the colour of its lamps).
const PAYLOAD_KEYS := {"starter_ship": ["ship", "group", "layout"], "species_start": ["species", "name"], "blueprint": ["blueprint"], "map_variant": ["variant", "tide_steps"], "skin": ["skin", "tint", "lamp"]}


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


## The unlocks of `kind` (a KINDS key), in catalogue order.
static func of_kind(kind: String) -> Array:
	return all().filter(func(u): return str(u.get("kind", "")) == kind)


## The payload of unlock `id` ({} when there is none).
static func payload_of(id: String) -> Dictionary:
	var p = entry(id).get("payload")
	return p if p is Dictionary else {}


## The Hollow tide's head start, in steps, of map variant `variant` (the payload `variant` of a map_variant unlock): 0 for an unknown one.
static func tide_steps(variant: String) -> int:
	for u in of_kind("map_variant"):
		if u.get("payload") is Dictionary and str(u["payload"].get("variant", "")) == variant:
			return maxi(int(u["payload"].get("tide_steps", 0)), 0)
	return 0


## How hull skin `skin` (the payload `skin` of a skin unlock) paints the exterior plating: {tint, lamp} as Colors, each only when
## the payload names it. {} for "" and for a skin that is not in the catalogue (the plain hull).
static func skin_paint(skin: String) -> Dictionary:
	var out := {}
	for u in of_kind("skin"):
		var p = u.get("payload")
		if skin != "" and p is Dictionary and str(p.get("skin", "")) == skin:
			for k in ["tint", "lamp"]:
				if p.get(k) is String and Color.html_is_valid(p[k]):
					out[k] = Color(p[k])
			break
	return out


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
		for k in u["payload"]:
			if KINDS.has(kind) and not PAYLOAD_KEYS[kind].has(k):
				bad.call("payload has an unknown key '%s' (%s takes: %s)" % [k, kind, ", ".join(PAYLOAD_KEYS[kind])])
		if KINDS.has(kind):
			var key: String = KINDS[kind]
			var value = u["payload"].get(key)
			if not (value is String and value != ""):
				bad.call("payload needs \"%s\" (a %s id)" % [key, kind])
			elif kind == "starter_ship" and not Content.has("ships", value) and not u.get("pending", false):
				bad.call("payload ship '%s' is not a design in data/ships or a pack's ships/" % value)
			elif kind == "species_start" and not Content.has("species", value):
				bad.call("payload species '%s' is unknown" % value)
			elif kind == "blueprint" and not Content.has("recipes", value):
				bad.call("payload blueprint '%s' is not a recipe" % value)
			_check_tuning(u["payload"], kind, bad)
	return out


## The optional payload keys that tune a kind (PAYLOAD_KEYS): a soldier's name, a variant's tide_steps, a skin's colours.
static func _check_tuning(payload: Dictionary, kind: String, bad: Callable) -> void:
	if kind == "species_start" and payload.has("name") and not (payload["name"] is String and payload["name"] != ""):
		bad.call("payload name must be a non-empty string")
	if kind == "map_variant":
		var n = payload.get("tide_steps")
		if not ((n is float or n is int) and n >= 1 and n == floorf(n)):
			bad.call("a map variant needs payload tide_steps, a whole number of 1 or more")
	if kind == "skin":
		for k in ["tint", "lamp"]:
			if payload.has(k) and not (payload[k] is String and Color.html_is_valid(payload[k])):
				bad.call("payload %s must be a colour like \"#ffd78a\"" % k)
