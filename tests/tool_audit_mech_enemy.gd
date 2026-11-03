extends SceneTree
## Not a test. Mechanics audit: prints what a generated stage-1/2 pirate (spec) carries: weapons, aim_skill, morale, shields, structure.
##   godot --headless --path . --script res://tests/tool_audit_mech_enemy.gd -- spec=gen:concord:small:8051:1823:s1 [spec=...]
const Shipgen = preload("res://scripts/space/shipgen.gd")
const Structure = preload("res://scripts/ship/structure.gd")
const Threat = preload("res://scripts/space/threat.gd")
const Weapons = preload("res://scripts/combat/weapons.gd")


func _initialize() -> void:
	var w := Weapons.new()
	for a in OS.get_cmdline_user_args():
		var kv := str(a).split("=", true, 1)
		if kv[0] != "spec":
			continue
		var s = Shipgen.from_spec(kv[1])
		var ids := []
		for uid in s.components.instances:
			var id := str(s.components.instances[uid]["id"])
			ids.append(id + ("(T)" if w.has(id) and bool(w.def(id)["turret"]) else ""))
		var ai: Dictionary = s.get_meta("ai", {})
		print(kv[1], " aim=", ai.get("aim_skill"), " morale=", ai.get("morale"), " struct=", Structure.totals(s), " parts=", ids)
	quit()
