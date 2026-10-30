extends Node2D
## An additive layer for glow art. A view (build mode, a ship in a fight) puts one of these as a
## child at the origin, collects the glow quads Visuals.draw_component() hands it through
## opts["glow_out"] during its own _draw(), and gives them over with show(). Quads are
## {"tex", "rect", "src", "xf" (Transform2D), "mod"} in the parent's coordinates.

var quads: Array = []


func _init() -> void:
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = mat


## Draw `list` (replacing the last frame's quads) on the next redraw.
func show_quads(list: Array) -> void:
	quads = list
	queue_redraw()


func _draw() -> void:
	for q in quads:
		draw_set_transform_matrix(q["xf"])
		draw_texture_rect_region(q["tex"], q["rect"], q["src"], q["mod"])
	draw_set_transform_matrix(Transform2D.IDENTITY)
