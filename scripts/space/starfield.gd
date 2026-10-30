extends Node2D
## Screen-space starfield drifting past the ship: the ship stays centred and space moves (Raft-style).
## Later the drift comes from the ship's real velocity.

@export var drift := Vector2(-22, 7)  # pixels per second for the nearest stars
@export var count := 260

var stars: Array = []  # [unit position, depth 0.2..1, radius]
var t := 0.0


func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7  # visual only; fixed so the sky looks the same every run
	for i in count:
		stars.append([Vector2(rng.randf(), rng.randf()), rng.randf_range(0.2, 1.0), rng.randf_range(0.6, 1.8)])


func _process(delta: float) -> void:
	t += delta
	queue_redraw()


func _draw() -> void:
	var vp := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, vp), Color("#05070c"))
	for s in stars:
		var depth: float = s[1]
		var p: Vector2 = s[0] * vp + drift * t * depth
		p = Vector2(fposmod(p.x, vp.x), fposmod(p.y, vp.y))
		draw_circle(p, s[2] * depth, Color(1, 1, 1, 0.3 + 0.6 * depth))
