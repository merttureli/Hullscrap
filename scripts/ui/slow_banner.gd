extends Control
## The fight slow-down on screen (repairs track): Tab in a ship fight toggles it (slow_down.gd), and this node shows it: a small "SLOW" banner
## at the top and a light blue tint over the screen. The logic is in slow_down.gd; this node reads the key and the fight, and applies the
## speed through TimeScale (the breach prompt's slow-down is merged there). The speed goes back when the slow-down ends, the fight ends or this node leaves the tree.
## Lives in the crew view's canvas layer, so a fight (which puts the crew view away) keeps it. A window that swallows every key keeps Tab to itself.

const SlowDown = preload("res://scripts/crew/slow_down.gd")
const TimeScale = preload("res://scripts/crew/time_scale.gd")
const UiKit = preload("res://scripts/ui/ui_kit.gd")

const TINT := Color(0.25, 0.5, 1.0, 0.10)
const EDGE := Color("#5fd4ff")
const BANNER := Vector2(150.0, 28.0)
const TOP := 48.0  ## y of the banner (under the top bar, over the breach card's place)

var view  ## the crew view (crew_view.gd)
var slow := SlowDown.new()


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _exit_tree() -> void:
	TimeScale.clear(get_instance_id())


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		TimeScale.clear(get_instance_id())


func _process(_dt: float) -> void:
	tick()


## Is a ship fight on (not an on-foot fight)?
func fight_on() -> bool:
	return view != null and view.has_method("fight_on") and view.fight_on()


## Every frame: end the slow-down with the fight, set the speed, show or hide the banner.
func tick() -> void:
	slow.update(fight_on())
	slow.apply(get_instance_id())
	if visible != slow.on:
		visible = slow.on
	if visible:
		queue_redraw()


## Tab (a plain press) toggles it in a fight. Returns true when it did something.
func press() -> bool:
	if not fight_on():
		return false
	slow.toggle(true)
	slow.apply(get_instance_id())
	visible = slow.on
	queue_redraw()
	return true


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo and e.keycode == KEY_TAB and not (e.ctrl_pressed or e.meta_pressed or e.alt_pressed or e.shift_pressed):
		if press() and is_inside_tree():
			get_viewport().set_input_as_handled()


func _draw() -> void:
	if not slow.on:
		return
	var screen := size if size != Vector2.ZERO else get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, screen), TINT)
	var r := Rect2(Vector2(screen.x / 2.0 - BANNER.x / 2.0, TOP), BANNER)
	UiKit.bar(self, r, 0.9)
	draw_rect(r, EDGE, false, 1.5)
	UiKit.text(self, "SLOW", r.position + Vector2(0.0, 19.0), 15, EDGE, HORIZONTAL_ALIGNMENT_CENTER, BANNER.x, UiKit.bold())
	UiKit.text(self, "Tab: normal speed", r.position + Vector2(0.0, BANNER.y + 12.0), 10, UiKit.DIM_TEXT, HORIZONTAL_ALIGNMENT_CENTER, BANNER.x)
