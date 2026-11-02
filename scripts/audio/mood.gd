extends RefCounted
## Which music state the game is in now: menu, explore, combat, hollow or build. Pure logic, fed once a frame by audio.gd with what
## the game is doing; the rules are here so they are tested headless. Priority: a menu screen, then a fight or a hostile in range
## (it is kept COMBAT_HOLD seconds after it ends, then back to explore), then build mode, then the Hollow (tide pressure from
## HOLLOW_PRESSURE or a place the tide has taken), else explore. A change other than into combat or a menu waits SETTLE seconds, so a
## flicker (build mode toggled, the tide pressure at its edge) does not make the music jump about. Also which piece (data/music.json v2) a
## place plays: lookup, piece_for and accent_for.

const COMBAT_HOLD := 4.0  ## seconds combat music goes on after the last hostile or fight is over
const HOLLOW_PRESSURE := 0.6  ## tide pressure from which the music turns to the Hollow's
const SETTLE := 0.75  ## seconds a new state (not combat, not a menu) must hold before the music follows

var state := "menu"  ## the state the music should be in
var _hold := 0.0  # seconds of combat music left after the fight
var _want := "menu"
var _want_t := 0.0


## The state `inp` asks for, before the hold and the settle: {menu, fight, hostile, build, hollow (bool), pressure (float)}.
static func raw(inp: Dictionary) -> String:
	if bool(inp.get("menu", false)):
		return "menu"
	if bool(inp.get("fight", false)) or bool(inp.get("hostile", false)):
		return "combat"
	if bool(inp.get("build", false)):
		return "build"
	if bool(inp.get("hollow", false)) or float(inp.get("pressure", 0.0)) >= HOLLOW_PRESSURE:
		return "hollow"
	return "explore"


## Advance by `dt` seconds with the game's inputs; returns the state the music should be in.
func update(inp: Dictionary, dt: float) -> String:
	var want := raw(inp)
	if want == "combat":
		_hold = COMBAT_HOLD
	elif want != "menu" and _hold > 0.0:
		_hold -= dt
		if _hold > 0.0:
			want = "combat"  # the fight is over: combat music runs on, then explore
	else:
		_hold = 0.0
	if want == "menu" or want == "combat":
		state = want
		_want = want
		_want_t = 0.0
		return state
	if want != _want:
		_want = want
		_want_t = 0.0
	_want_t += dt
	if want == state or _want_t >= SETTLE or state == "combat" or state == "menu":  # (leaving combat has waited its hold, leaving a menu was a click)
		state = want
	return state


## The entry of `table` (data/music.json v2 `regions` or `accents`) for a place: `region:<id>` first, then `faction:<faction>`, then
## `default`. A Hollow place (`hollow`) has only the Hollow's, `faction:hollow`. Null when none names one.
static func lookup(table: Dictionary, region_id: String, faction: String, hollow := false):
	var keys := ["faction:hollow"] if hollow else ["region:" + region_id, "faction:" + faction, "default"]
	for k in keys:
		if table.has(k):
			return table[k]
	return null


## The piece id a place plays (`regions`), "" when none is named (and for a Hollow place, while there is no Hollow piece).
static func piece_for(regions: Dictionary, region_id: String, faction: String, hollow := false) -> String:
	var piece = lookup(regions, region_id, faction, hollow)
	return piece if piece is String else ""


## The accent a place has over its piece (`accents`: {stem, db}), {} for none.
static func accent_for(accents: Dictionary, region_id: String, faction: String, hollow := false) -> Dictionary:
	var a = lookup(accents, region_id, faction, hollow)
	return a if a is Dictionary else {}
