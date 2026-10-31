extends RefCounted
## What the weapon effects look like (effects.gd logs them as "effect" arena events). combat_view.gd draws; nothing here
## draws. An event goes in, effect entries come out in the view's own format ({k: flash | ring | spark | puff | streak,
## pos, life, ...}, world px; "stick": a ship index when the entry rides on that hull), so the rules for them are tested
## headless. The scatter is seeded from the event (its tick and ship), so the same fight shows the same clouds. These are
## code-drawn placeholders: the art agents' sprites for a weapon (art/projectiles/<weapon id>_impact) replace the impact itself.

const COLORS := {
	"acid": Color("#9be34a"), "spores": Color("#c9d94a"), "shard": Color("#dff2ff"), "sonic": Color("#9fe8ff"),
	"magnetic": Color("#c58bff"), "frost": Color("#bfeaff"), "corrode": Color("#b8a23a"),
	"o2": Color("#d8f0ff"), "heat": Color("#ff8a3a"), "shock": Color("#ffe14a"),
}


static func _rng(e: Dictionary) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = int(e["tick"]) * 131 + int(e["ship"])
	return r


static func _puff(rng: RandomNumberGenerator, pos: Vector2, col: Color, spread: float, life: float, radius: float, grow: float, rise := 0.0) -> Dictionary:
	var off := Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(0.0, spread)
	return {"k": "puff", "pos": pos + off, "vel": Vector2(rng.randf_range(-12.0, 12.0), -rise * rng.randf_range(0.5, 1.0)), "life": life * rng.randf_range(0.8, 1.2),
		"r": radius, "grow": grow, "color": col, "tint": true}


static func _sparks(rng: RandomNumberGenerator, pos: Vector2, col: Color, n: int, toward := Vector2.ZERO, speed := 220.0) -> Array:
	var out := []
	for i in n:
		var d := Vector2.from_angle(rng.randf() * TAU) if toward == Vector2.ZERO else toward.rotated(rng.randf_range(-0.5, 0.5))
		out.append({"k": "spark", "pos": pos, "vel": d * rng.randf_range(0.6, 1.0) * speed, "life": rng.randf_range(0.25, 0.5), "color": col})
	return out


## The entries for the "effect" event `e` of `arena` (`e["kind"]`: acid, corrode, spores, sonic, shard, frost, magnetic, split or self_room).
static func of(arena, e: Dictionary) -> Array:
	var rng := _rng(e)
	var idx: int = e["ship"]
	var pos: Vector2 = e["pos"]
	var out := []
	match str(e["kind"]):
		"acid":
			var col: Color = COLORS["acid"]
			out.append({"k": "flash", "pos": pos, "stick": idx, "life": 0.4, "r": 26.0, "color": col})
			for i in 6:
				var p := _puff(rng, pos, Color(col, 0.85), 16.0, 1.2, 14.0, 20.0, 30.0)
				p["stick"] = idx
				out.append(p)
			out.append_array(_sparks(rng, pos, col, 3, Vector2.ZERO, 120.0))
		"corrode":
			var col: Color = COLORS["corrode"]
			out.append({"k": "flash", "pos": pos, "stick": idx, "life": 0.4, "r": 26.0, "color": col})
			for i in 5:
				var p := _puff(rng, pos, Color(col, 0.8), 14.0, 1.2, 14.0, 20.0, 20.0)
				p["stick"] = idx
				out.append(p)
		"spores":
			var at: Vector2 = e.get("room_pos", pos)
			var reach := 16.0 * sqrt(float(e.get("room_size", 20.0)))
			for i in 9:
				var p := _puff(rng, at, Color(COLORS["spores"], 0.55), reach, 1.8, 22.0, 40.0, 8.0)
				p["stick"] = idx
				out.append(p)
		"sonic":
			var at: Vector2 = e.get("room_pos", pos)
			for i in 3:
				out.append({"k": "ring", "pos": at, "stick": idx, "life": 0.5 + 0.18 * i, "r": 120.0 + 70.0 * i, "color": COLORS["sonic"]})
			out.append({"k": "flash", "pos": pos, "stick": idx, "life": 0.2, "r": 12.0, "color": COLORS["sonic"]})
		"shard":
			var col: Color = COLORS["shard"]
			for t in e.get("targets", []):
				var d: Vector2 = t - pos
				if d.length() < 1.0:
					continue
				out.append({"k": "streak", "pos": pos, "dir": d.normalized(), "len": d.length(), "life": 0.28, "color": col})
				out.append({"k": "flash", "pos": t, "stick": idx, "life": 0.2, "r": 8.0, "color": col})
			out.append_array(_sparks(rng, pos, col, 4))
		"frost":
			var col: Color = COLORS["frost"]
			out.append({"k": "flash", "pos": pos, "stick": idx, "life": 0.3, "r": 16.0, "color": col})
			out.append({"k": "ring", "pos": pos, "stick": idx, "life": 0.5, "r": 140.0, "color": col})
			for p in e.get("at", []):
				out.append({"k": "ring", "pos": p, "stick": idx, "life": 0.6, "r": 110.0, "color": col})
			out.append_array(_sparks(rng, pos, col, 6, Vector2.ZERO, 140.0))
			for i in 4:
				var p := _puff(rng, pos, Color(col, 0.7), 14.0, 1.1, 14.0, 22.0)
				p["stick"] = idx
				out.append(p)
		"magnetic":
			var col: Color = COLORS["magnetic"]
			var toward: Vector2 = (Vector2(e.get("toward", pos)) - pos).normalized()
			out.append({"k": "ring", "pos": pos, "stick": idx, "life": 0.5, "r": 130.0, "color": col})
			out.append({"k": "streak", "pos": pos, "dir": toward, "len": 220.0, "life": 0.4, "color": col})
			out.append_array(_sparks(rng, pos, col, 6, toward, 420.0))
		"split":
			var col: Color = COLORS["shard"]
			out.append({"k": "flash", "pos": pos, "stick": idx, "life": 0.25, "r": 20.0, "color": col})
			for d in e.get("dirs", []):
				out.append({"k": "streak", "pos": e.get("origin", pos), "dir": d, "len": 110.0, "life": 0.3, "color": col})
			out.append_array(_sparks(rng, pos, col, 5))
		"self_room":
			var at: Vector2 = e.get("room_pos", pos)
			var has: Array = e.get("has", [])
			if "o2" in has:
				for i in 4:
					var p := _puff(rng, at, Color(COLORS["o2"], 0.5), 40.0, 1.0, 16.0, 28.0, 20.0)
					p["stick"] = idx
					out.append(p)
			if "heat" in has or "scorch" in has:
				out.append({"k": "flash", "pos": at, "stick": idx, "life": 0.35, "r": 34.0, "color": COLORS["heat"]})
			if "shock" in has:
				out.append_array(_sparks(rng, at, COLORS["shock"], 7, Vector2.ZERO, 160.0))
	return out


## The entries for a "hit" event `e` that a damage over time dealt (e["dot"] names it, "acid"): a wisp of its colour.
static func dot(e: Dictionary) -> Array:
	var rng := _rng(e)
	var p := _puff(rng, e["pos"], Color(COLORS.get(str(e["dot"]), Color.WHITE), 0.75), 10.0, 0.8, 12.0, 14.0, 24.0)
	p["stick"] = int(e["ship"])
	return [p]
