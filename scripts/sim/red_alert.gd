extends RefCounted
## Red alert (a rule of the mechanics director, approved by the lead): build mode pauses the world, so it may not be
## entered while a hostile ship is near; otherwise a fight could be frozen and its breaches rebuilt. One check, fed by
## whoever knows where the hostiles are: build_mode.gd hands it the fight now, and sector space can add its contacts.
## Static and pure.

const BUILD_PATH := "res://data/build.json"
const DEFAULT_RANGE := 2500.0  ## px, when data/build.json has no red_alert_px
const REASON := "Red alert: hostiles too close to build"


## "" when build mode may be entered, else why not. `world`: {"at": the player ship's position, "hostiles": [the
## positions of hostile ships]}, in the same px. `range_px` below 0 reads red_alert_px from data/build.json.
static func can_build(world: Dictionary, range_px := -1.0) -> String:
	var reach := range_px if range_px >= 0.0 else alert_range()
	var at: Vector2 = world.get("at", Vector2.ZERO)
	for h in world.get("hostiles", []):
		if at.distance_to(h) <= reach:
			return REASON
	return ""


## How near a hostile ship puts the ship on red alert (px).
static func alert_range(path := BUILD_PATH) -> float:
	var d = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
	return float(d.get("red_alert_px", DEFAULT_RANGE)) if d is Dictionary else DEFAULT_RANGE
