extends RefCounted
## The blocked-room sweep of generated ships (scripts/space/lanes.gd): shared by the test and tests/tool_lanes.gd.

const Shipgen = preload("res://scripts/space/shipgen.gd")
const Lanes = preload("res://scripts/space/lanes.gd")

const JUMPS: Array[int] = [5, 12, 20, 26, 31, 35]  ## the jumps of a stage 1 to 6 fight
const TIERS: Array[int] = [1, 1, 2, 2, 3, 3]


## {ships, blocked (ships with a room cut off), rooms (rooms cut off in all)} for `n` seeds of run stage `stage`.
static func sweep(stage: int, n: int) -> Dictionary:
	var out := {"ships": 0, "blocked": 0, "rooms": 0}
	var factions := Shipgen.factions()
	var budget := Shipgen.budget_for(TIERS[stage - 1], JUMPS[stage - 1], 1.0, "normal", stage)
	for i in n:
		var rng := RandomNumberGenerator.new()
		rng.seed = 7000 + i
		var ship := Shipgen.build(factions[i % factions.size()], Shipgen.pick_size(budget, rng), 9000 + i * 17 + stage, snappedf(budget * rng.randf_range(0.8, 1.2), 0.01), {"stage": stage})
		if ship == null:
			continue
		var k := Lanes.blocked(ship)
		out["ships"] += 1
		out["blocked"] += int(k > 0)
		out["rooms"] += k
	return out
