extends RefCounted
## What the player is told about an enemy before the fight (Beta 3: no skulls, no numbers: the ship says it). Given a design (a generated spec
## or a design file) it gives the ship itself, its name line ("Kett lancer", "Rustfang raider"), its emblem and colours (Shipgen.style_of), and,
## for the Ledger, a sentence in words when she outguns you. Threat itself stays (budgets, the AI, the advisor): this only never shows it.

const Shipgen = preload("res://scripts/space/shipgen.gd")
const Threat = preload("res://scripts/space/threat.gd")
const Session = preload("res://scripts/combat/combat_session.gd")

const CACHE_CAP := 24
static var _ships := {}  # design -> Ship, so a card does not rebuild the ship every frame


## The enemy ship of `design` (built as the fight builds it), null when it does not load. Kept per design.
static func ship_of(design: String):
	if not _ships.has(design):
		if _ships.size() >= CACHE_CAP:
			_ships.clear()
		_ships[design] = Session.load_ship(design)
	return _ships[design]


## {ship, line (the name line), emblem ({} for an authored design), palette ({}), race (a race ship: its people's name, else "")} of `design`; {} when it does not load.
static func of(design: String) -> Dictionary:
	var foe = ship_of(design)
	if foe == null:
		return {}
	var look: Dictionary = foe.get_meta("style", {})
	if look.is_empty():
		return {"ship": foe, "line": str(foe.name), "emblem": {}, "palette": {}, "race": ""}
	return {"ship": foe, "line": str(look["line"]), "emblem": look["emblem"], "palette": look["palette"], "race": str(look["race"])}


## The Ledger's sentence about an enemy that outguns `mine`, in words and with no number; "" when she does not. Only a big mismatch speaks.
static func mismatch_words(foe, mine) -> String:
	if foe == null or mine == null:
		return ""
	var e := Threat.power(foe, float(foe.get_meta("ai", {}).get("aim_skill", 0.6)))
	var p := Threat.power(mine, float(Threat.config()["player_aim"]))
	if float(e["power"]) < 1.6 * float(p["power"]):
		return ""
	return "She carries more guns than you." if float(e["dps"]) / maxf(float(p["dps"]), 0.01) >= float(e["ehp"]) / maxf(float(p["ehp"]), 0.01) else "Her hull is thicker than yours."
