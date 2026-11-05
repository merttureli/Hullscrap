extends RefCounted
## Can the ship leave? The build-your-own start (docs/CONTENT.md section 19, design field `build_first`) holds the ship at its first
## node until it can fly. Nothing here is a new rule: it reads the checks the game already has, flight.gd can_fly (a powered helm and a
## powered engine, which the ship must have, wired to a reactor) and the rooms of atmosphere.gd (every room sealed, so the crew have air),
## and says in plain words what is missing, each reason on its own.
## No nodes, no drawing, no randomness.



## What stops `ship` from flying, one plain sentence each. Empty when it can fly and its rooms are sealed.
static func problems(ship) -> Array[String]:
	var out: Array[String] = []
	if ship == null:
		return out
	ship.refresh()
	var powered: Dictionary = ship.power_state.get("powered", {})
	var helm := false  # flight.gd can_fly asks for both, a powered helm and a powered engine: each one is named when it is missing
	var engine := false
	for uid in ship.components.instances:
		if powered.get(uid, false):
			var family = ship.components.def(ship.components.instances[uid]["id"]).get("family", "")
			helm = helm or family == "helm"
			engine = engine or family == "engine"
	if not helm:
		out.append("no powered helm")
	if not engine:
		out.append("no powered engine")
	var open := 0
	for r in ship.atmosphere.rooms:
		open += int(not r["sealed"])
	if open > 0:
		out.append("%d room%s open to space (the crew need sealed air)" % [open, "s are" if open > 1 else " is"])
	return out


## The same as one line for the map: "Can't launch yet: no powered helm; no powered engine." "" when the ship may go.
static func why_not(ship) -> String:
	var list := problems(ship)
	return "" if list.is_empty() else "Can't launch yet: " + "; ".join(list) + "."
