extends RefCounted
## What the player is told about an enemy before the fight (Beta 3: no skulls, no numbers: the ship says it). Given a design (a generated spec
## or a design file) it gives the ship itself, its name line ("Kett lancer", "Rustfang raider"), its emblem and colours (Shipgen.style_of).
## Threat itself stays (budgets, the AI, the advisor): this never shows it.

const Session = preload("res://scripts/combat/combat_session.gd")
const Flagships = preload("res://scripts/space/flagships.gd")

const CACHE_CAP := 24
static var _ships := {}  # design -> Ship, so a card does not rebuild the ship every frame


## The enemy ship of `design` (built as the fight builds it), null when it does not load. Kept per design.
static func ship_of(design: String):
	if not _ships.has(design):
		if _ships.size() >= CACHE_CAP:
			_ships.clear()
		_ships[design] = Session.load_ship(design)
	return _ships[design]


## {ship, line (the name line), emblem ({} for an authored design), palette ({}), race (a race ship: its people's name, else ""), boss ({title, name, captain, line, race} of
## a race flagship, flagships.gd card_of; {} for any other ship)} of `design`; {} when it does not load.
static func of(design: String) -> Dictionary:
	var foe = ship_of(design)
	if foe == null:
		return {}
	var look: Dictionary = foe.get_meta("style", {})
	var boss := Flagships.card_of(design)
	if look.is_empty():
		return {"ship": foe, "line": str(foe.name), "emblem": {}, "palette": {}, "race": "", "boss": boss}
	return {"ship": foe, "line": str(look["line"]), "emblem": look["emblem"], "palette": look["palette"], "race": str(look["race"]), "boss": boss}
