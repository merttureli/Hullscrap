extends RefCounted
## The fight slow-down (repairs track): in a ship fight the player can slow the game down with a key (Tab) to give orders in the heat of
## the moment, as FTL's pause does but without stopping it: the game runs at crew.json slow.scale until the key is pressed again or the
## fight ends (update with fight false). There is no limit on its use. Boarding (on foot) is another mode: the key does nothing there.
## This is the logic; slow_banner.gd is the node that reads the key, draws the banner and puts time_scale() on the engine through TimeScale
## (which also holds the breach prompt's slow-down: the slower one wins).

const CrewMember = preload("res://scripts/crew/crew_member.gd")
const TimeScale = preload("res://scripts/crew/time_scale.gd")

var on := false  ## the slow-down is running


static func scale() -> float:
	return float(CrewMember.config().get("slow", {}).get("scale", 0.25))


## The key was pressed: `fight` says a ship fight is on (not boarding). Returns whether the slow-down runs now.
func toggle(fight: bool) -> bool:
	on = fight and not on
	return on


## Every frame: the slow-down ends with the fight (a win, an escape, a loss, the soldier going aboard another vessel).
func update(fight: bool) -> void:
	if not fight:
		on = false


## The speed this asks the game to run at.
func time_scale() -> float:
	return scale() if on else 1.0


## Ask the engine for it (TimeScale merges it with the breach prompt's). `source`: who asks.
func apply(source) -> float:
	return TimeScale.request(source, time_scale())
