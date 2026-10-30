extends RefCounted
## What a collision or a bounce looks like and says. combat_view.gd draws it; nothing here draws.
## An arena event goes in, effect entries come out in the view's own format ({k: art | spark | debris
## | ring | flash, pos, life, ...}, world px), with a screen shake in screen px and a chronicle line,
## so the rules for them are tested headless. The scatter is seeded from the event (its tick and
## place in the list), so the same fight shows the same impacts.

const POWER_DIV := 5000.0  ## sqrt(impact energy) at which a ram's effects are full size
const SHAKE_DIV := 220.0  ## sqrt(impact energy) per screen px of shake
const SHAKE_MIN := 2.0
const SHAKE_MAX := 26.0
const SPARK := Color("#ffe9a8")
const BLAST := Color("#ff9a4a")
const DEBRIS: Array[Color] = [Color("#8a8f99"), Color("#b9bfc9"), Color("#5b6577"), Color("#c9a37a")]


## How big the effects of an impact of `energy` are, 0.2 (a bump) to 1 (a hard ram).
static func power(energy: float) -> float:
	return clampf(sqrt(maxf(energy, 0.0)) / POWER_DIV, 0.2, 1.0)


## The screen shake of an impact of `energy`, in screen px.
static func shake(energy: float) -> float:
	return clampf(sqrt(maxf(energy, 0.0)) / SHAKE_DIV, SHAKE_MIN, SHAKE_MAX)


## What the ram event `events[index]` did to each ship: {ship: {"hull": wall and door hp lost, "parts":
## system hp lost}}, from the ram hits Collisions logs right after it (in the same tick, up to the next ram).
static func ram_damage(events: Array, index: int) -> Dictionary:
	var ram: Dictionary = events[index]
	var out := {}
	for i in range(index + 1, events.size()):
		var e: Dictionary = events[i]
		if e["tick"] != ram["tick"] or e["type"] == "ram":
			break
		if e["type"] == "hit" and e.get("ram", false) and e["ship"] in [ram["a"], ram["b"]]:
			var rec: Dictionary = out.get(e["ship"], {"hull": 0.0, "parts": 0.0})
			rec["parts" if e["kind"] == "component" else "hull"] += float(e["dealt"])
			out[e["ship"]] = rec
	return out


## The effects of the ram event `arena.events[index]`: {"fx": entries, "line": the chronicle line, "shake"
## (screen px), "damage" (ram_damage)}. Sparks, debris and a small blast at every contact point, a blast
## and (for a hard one) a ring where the ships met. The line, "Rammed the pirate: 14 hull damage (took 6)",
## is also written to ship `player`'s chronicle; it is "" when `player` is in neither ship of the collision.
static func ram(arena, index: int, player := 0, label := "pirate") -> Dictionary:
	var e: Dictionary = arena.events[index]
	var energy := float(e["energy"])
	var pw := power(energy)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(e["tick"]) * 131 + index
	var along: Vector2 = Vector2(e.get("n", Vector2.DOWN)).rotated(PI / 2.0)  # the contact faces slide along this line
	var fx := []
	for p in e.get("points", [e["pos"]]):
		fx.append({"k": "art", "name": "sparks", "pos": p, "life": 0.35, "scale": 1.1 + 1.5 * pw, "r": 16.0 + 14.0 * pw, "color": SPARK})
		for i in 2 + int(3.0 * pw):
			var d := along.rotated(rng.randf_range(-0.8, 0.8)) * (1.0 if rng.randf() < 0.5 else -1.0)
			fx.append({"k": "spark", "pos": p, "vel": d * rng.randf_range(120.0, 360.0), "life": rng.randf_range(0.25, 0.55), "color": SPARK})
		for i in 1 + int(2.0 * pw):
			fx.append({"k": "debris", "pos": p, "vel": Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(50.0, 190.0), "life": rng.randf_range(0.7, 1.3),
				"size": rng.randf_range(3.0, 6.0), "spin": rng.randf_range(-8.0, 8.0), "color": DEBRIS[rng.randi() % DEBRIS.size()]})
	fx.append({"k": "art", "name": "explosion", "pos": e["pos"], "life": 0.5, "scale": 0.35 + 0.9 * pw, "r": 18.0 + 30.0 * pw, "color": BLAST})
	if pw > 0.5:
		fx.append({"k": "ring", "pos": e["pos"], "life": 0.5, "r": 60.0 + 140.0 * pw, "color": BLAST})
	var dmg := ram_damage(arena.events, index)
	var line := ""
	if player in [e["a"], e["b"]]:
		var other: int = e["b"] if e["a"] == player else e["a"]
		line = "Rammed the %s: %s (took %s)" % [label, _hull_text(dmg.get(other, {}).get("hull", 0.0)), _hull_text(dmg.get(player, {}).get("hull", 0.0), true)]
		arena.ships[player].ship.log_event(line)
	return {"fx": fx, "line": line, "shake": shake(energy), "damage": dmg}


## The effects of a ricochet or a deflection event `e`: a small spark at the bounce point and two more
## flying off the way the shot leaves.
static func bounce(e: Dictionary) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(e["tick"]) * 131 + int(e["ship"])
	var out := [{"k": "art", "name": "sparks", "pos": e["pos"], "life": 0.22, "scale": 0.45, "r": 8.0, "color": SPARK}]
	var way: Vector2 = Vector2(e.get("new_dir", Vector2.ZERO))
	for i in 2:
		var d := way.rotated(rng.randf_range(-0.5, 0.5)) if way != Vector2.ZERO else Vector2.from_angle(rng.randf() * TAU)
		out.append({"k": "spark", "pos": e["pos"], "vel": d * rng.randf_range(140.0, 260.0), "life": rng.randf_range(0.15, 0.3), "color": SPARK})
	return out


## "14 hull damage" (one decimal below 10, "no hull damage" for none); `bare` leaves the "hull damage" off.
static func _hull_text(hp: float, bare := false) -> String:
	if hp <= 0.0:
		return "nothing" if bare else "no hull damage"
	var n := "%d" % roundi(hp) if hp >= 10.0 else "%.1f" % hp
	return n if bare else n + " hull damage"
