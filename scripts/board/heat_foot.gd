extends RefCounted
## Heat on foot (data/station_modules.json `heat`): a room's static heat (site.heat_of, like its air) hurts and slows the soldier and the party by the traits the
## ship already reads, with the same rules and numbers: dries_out (hp a second above its threshold), heat_speed (the walk speed in a hot or cold room) and
## heat_proof (a Forge Apron: a hot room does not slow them). Shared helpers: TraitSet.heat_hurt and heat_factor. Pure logic; the HUD's HOT line reads line().

const TraitSet = preload("res://scripts/crew/traits.gd")


## The soldier and the party members on their feet.
static func people(s) -> Array:
	var out: Array = [s.soldier]
	for p in s.party:
		out.append(p["m"])
	return out


## `dt` seconds pass: whoever stands in a hot room is hurt (dries_out) and walks by their heat_speed. Run after GearActive.tick, which sets speed_mod to the gear's walk_mult.
static func tick(s, dt: float) -> void:
	for m in people(s):
		if m.is_down():
			continue
		var t := TraitSet.of(m)
		var heat: float = s.site.heat_at(m.pos)
		var hs: Dictionary = t["heat_speed"]
		if float(hs["cold"]) != 1.0 or float(hs["hot"]) != 1.0:
			m.speed_mod *= TraitSet.heat_factor(t, heat)
		var dmg := TraitSet.heat_hurt(t, heat)
		if dmg > 0.0:
			m.hurt(dmg * dt)


## What the heat where `m` stands does to them: "" (nothing), "slows" or "hurts".
static func effect(site, m) -> String:
	var t := TraitSet.of(m)
	var heat: float = site.heat_at(m.pos)
	if TraitSet.heat_hurt(t, heat) > 0.0:
		return "hurts"
	return "slows" if TraitSet.heat_factor(t, heat) < 1.0 else ""
