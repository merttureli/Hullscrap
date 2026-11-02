extends RefCounted
## The motion tracker (a nod to Alien): a ring on the HUD whose sweep pings anything that moves within RANGE cells, as a blip at its
## bearing and (distance / RANGE) of the way out. Pure logic; board_hud.gd draws it. Stage B1 has nothing on it but the sweep: stage B2
## feeds it the contacts (tick's `contacts`: [{pos (cells), moving}], from the view's `contacts_source`) and plays a ping for each take_pings().

const RANGE := 25.0  ## cells
const SWEEP_S := 3.2  ## seconds one turn of the sweep takes
const BLIP_S := 2.6  ## seconds a blip stays, fading

var angle := 0.0  ## the sweep, radians (0 = right, turning clockwise on the screen)
var blips: Array = []  ## [{angle, dist (0 = at the soldier, 1 = at RANGE), age}]
var _pings := 0


## `dt` seconds pass with the soldier at `origin` (cells): the sweep turns and ticks off the contacts it passes.
func tick(dt: float, origin: Vector2, contacts: Array = []) -> void:
	var from := angle
	angle = fposmod(angle + TAU * dt / SWEEP_S, TAU)
	for b in blips:
		b["age"] += dt
	blips = blips.filter(func(b): return b["age"] < BLIP_S)
	for c in contacts:
		if not bool(c.get("moving", true)):
			continue
		var d: Vector2 = c["pos"] - origin
		if d.length() > RANGE:
			continue
		var a := fposmod(d.angle(), TAU)
		if _passed(from, angle, a):
			blips.append({"angle": a, "dist": d.length() / RANGE, "age": 0.0})
			_pings += 1


## How many blips appeared since the last call (the ping sound plays that many times).
func take_pings() -> int:
	var n := _pings
	_pings = 0
	return n


## Did the sweep, turning from `from` to `to`, pass bearing `a`?
static func _passed(from: float, to: float, a: float) -> bool:
	if from <= to:
		return a > from and a <= to
	return a > from or a <= to
