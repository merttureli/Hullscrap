extends RefCounted
## The game speed (Engine.time_scale) asked for by more than one thing: the breach prompt (breach_alert.gd) and the fight slow-down
## (slow_down.gd). Each asks under its own name; the slowest request wins, and when none is left the game runs at 1. Static functions, so
## a node that goes away takes only its own request with it (clear) and nothing is left slowing the game down. Tests can read `current()`.

static var _requests := {}  ## source -> the scale it asks for (only those under 1)


## `source` asks for `scale` (1 or more: it asks for nothing). Returns the speed the game runs at now.
static func request(source, scale: float) -> float:
	if scale >= 1.0:
		_requests.erase(source)
	else:
		_requests[source] = maxf(scale, 0.01)
	return apply()


## `source` withdraws its request.
static func clear(source) -> float:
	_requests.erase(source)
	return apply()


## The slowest request, 1 when there is none.
static func current() -> float:
	var s := 1.0
	for v in _requests.values():
		s = minf(s, float(v))
	return s


## Put `current()` on the engine.
static func apply() -> float:
	var s := current()
	Engine.time_scale = s
	return s


## Forget every request (a new game, a test) and run at normal speed.
static func reset() -> void:
	_requests.clear()
	Engine.time_scale = 1.0
