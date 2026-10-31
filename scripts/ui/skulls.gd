extends RefCounted
## The skull rating of a threat or a danger (1-5): the five skulls the region cards and the enemy's schematic draw, the
## colour bands the threat tags and the fight banner use (1-2 dim, 3 amber, 4-5 red) and the tag text of a choice that
## may start a fight. Static helpers, no state.

const Threat = preload("res://scripts/space/threat.gd")

const COUNT := 5
const STEP := 18.0  ## px between two skulls at scale 1
const OFF := Color("#3a4350")  ## a skull not lit
const EYE := Color("#10151c")
const DIM := Color("#97a3b3")
const AMBER := Color("#e1a136")
const RED := Color("#e0413b")


## The colour of a rating: 1-2 dim, 3 amber, 4-5 red.
static func color(n: int) -> Color:
	return RED if n >= 4 else (AMBER if n == 3 else DIM)


## The width in px of the row of five skulls at scale `k`.
static func width(k := 1.0) -> float:
	return (STEP * (COUNT - 1) + 14.0) * k


## `n` of 5 skulls on canvas `cv`, from `at` (their row's left middle), `k` times full size; lit ones in `on`.
static func draw(cv: CanvasItem, at: Vector2, n: int, on := RED, k := 1.0) -> void:
	for i in COUNT:
		var col := on if i < n else OFF
		var o := at + Vector2((STEP * i + 7.0) * k, 0.0)
		cv.draw_circle(o, 7.0 * k, col)
		cv.draw_rect(Rect2(o + Vector2(-4.0, 4.0) * k, Vector2(8.0, 5.0) * k), col)
		cv.draw_circle(o + Vector2(-2.5, 0.0) * k, 1.8 * k, EYE)
		cv.draw_circle(o + Vector2(2.5, 0.0) * k, 1.8 * k, EYE)


## The tag after a choice's text: "[Threat 4/5]", or "[may fight: Threat 4/5]" when only some outcomes fight.
static func tag(n: int, may := false) -> String:
	return "[%s%s]" % ["may fight: " if may else "", Threat.label(n)]
