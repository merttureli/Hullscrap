extends RefCounted
## Everyone hostile aboard (docs/BOARDING.md, stage B2). Pure logic: the session (boarding.gd) owns one and ticks it.

var s  ## the session (boarding.gd)
var list: Array = []  ## the foes: {id, kind, m (a CrewMember: pos, hp, facing, path), ...}


func _init(p_session = null) -> void:
	s = p_session


## What a shot can hit: [{pos, r, ref}].
func bodies() -> Array:
	return []


func hurt(_foe, _amount: float, _at: Vector2) -> void:
	pass


func noise(_at: Vector2, _radius: float) -> void:
	pass
