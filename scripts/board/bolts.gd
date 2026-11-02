extends RefCounted
## What a shot looks like on a boarding site (docs/BOARDING.md, B4; data/boarding.json `bolts`). Pure logic: the session puts the resolved look into its
## shot events and works out when the bolt arrives; board_view.gd flies it.
## A look is built in layers, each setting only the keys it changes: default, the weapon's class, its culture (hand_weapons.json), the weapon's own id.

const Site = preload("res://scripts/board/site.gd")
const Content = preload("res://scripts/data/content.gd")


static func cfg() -> Dictionary:
	return Site.config()["bolts"]


## The look of hand weapon `id`: {color, core, len, width, speed, light_r, energy, kind, impact, shake, ...}, `size` times wider and brighter (an Overcharge Coil).
static func look(id: String, size := 1.0) -> Dictionary:
	var c := cfg()
	var e := Content.entry("hand_weapons", id)
	var out: Dictionary = c["default"].duplicate()
	out.merge(c["class"].get(str(e.get("class", "")), {}), true)
	out.merge(c["culture"].get(str(e.get("culture", "")), {}), true)
	out.merge(c["weapon"].get(id, {}), true)
	return _grown(out, size)


## The look of a foe's shot: by the foe's kind; a hacked sentry (`mine`) fires in the colour of `own` (the soldier's weapon look).
static func foe_look(kind: String, mine := false, own := {}) -> Dictionary:
	var c := cfg()
	var out: Dictionary = c["default"].duplicate()
	out.merge(c["foe"].get(kind, {}), true)
	if mine and not own.is_empty():
		out["color"] = own["color"]
		out["core"] = own["core"]
	return out


static func _grown(l: Dictionary, size: float) -> Dictionary:
	if size != 1.0:
		l["width"] = float(l["width"]) * size
		l["energy"] = float(l["energy"]) * size
		l["light_r"] = float(l["light_r"]) * (1.0 + (size - 1.0) * 0.5)
		l["size"] = size
	return l


## Seconds a bolt of `look` takes to cover `dist` cells (0 for a swing or an instant line).
static func travel(l: Dictionary, dist: float) -> float:
	var v := float(l.get("speed", 0.0))
	return dist / v if v > 0.0 and str(l.get("kind", "bolt")) != "swing" else 0.0
