class_name StrategyCamera
extends Camera2D

const PAN_SPEED := 620.0
const ZOOM_STEP := 0.12
const MIN_ZOOM := 0.45
const MAX_ZOOM := 1.65

var _dragging := false
var _shake_strength := 0.0
var _shake_time := 0.0
var _shake_random := RandomNumberGenerator.new()


func _ready() -> void:
	position_smoothing_enabled = true
	position_smoothing_speed = 9.0
	_shake_random.randomize()


func _process(delta: float) -> void:
	var direction := Vector2.ZERO
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		direction.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		direction.x += 1.0
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		direction.y -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		direction.y += 1.0

	if direction != Vector2.ZERO:
		position += direction.normalized() * PAN_SPEED * delta / maxf(zoom.x, 0.01)

	if _shake_time > 0.0:
		_shake_time = maxf(0.0, _shake_time - delta)
		var falloff := clampf(_shake_time / 0.24, 0.0, 1.0)
		offset = Vector2(
			_shake_random.randf_range(-1.0, 1.0), _shake_random.randf_range(-1.0, 1.0)
		) * _shake_strength * falloff
	else:
		offset = offset.lerp(Vector2.ZERO, minf(1.0, delta * 18.0))


func kick_shake(strength: float) -> void:
	_shake_strength = maxf(_shake_strength, strength)
	_shake_time = 0.24


func focus_on(bounds: Rect2) -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	var padded_size := bounds.size + Vector2(180.0, 150.0)
	var fit_zoom := minf(
		viewport_size.x / maxf(padded_size.x, 1.0), viewport_size.y / maxf(padded_size.y, 1.0)
	)
	fit_zoom = clampf(fit_zoom, MIN_ZOOM, 1.15)
	zoom = Vector2.ONE * fit_zoom
	position = bounds.get_center() + Vector2(0.0, 18.0)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_MIDDLE:
			_dragging = mouse_event.pressed
			get_viewport().set_input_as_handled()
		elif mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_set_zoom(zoom.x + ZOOM_STEP)
			get_viewport().set_input_as_handled()
		elif mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_set_zoom(zoom.x - ZOOM_STEP)
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _dragging:
		var motion := event as InputEventMouseMotion
		position -= motion.relative / maxf(zoom.x, 0.01)
		get_viewport().set_input_as_handled()


func _set_zoom(value: float) -> void:
	var clamped := clampf(value, MIN_ZOOM, MAX_ZOOM)
	zoom = Vector2.ONE * clamped
