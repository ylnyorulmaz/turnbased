class_name ProceduralEffect
extends Node2D

## Short-lived, asset-free feedback for movement, combat, and city founding.

enum EffectKind {
	MOVE_DUST,
	IMPACT,
	CITY_BURST,
	DAMAGE_TEXT,
}

var effect_kind := EffectKind.MOVE_DUST
var effect_color := Color.WHITE
var direction := Vector2.RIGHT
var display_text := ""
var duration := 0.45
var elapsed := 0.0


func configure(
	kind: int,
	color_value: Color,
	direction_value: Vector2 = Vector2.RIGHT,
	text_value: String = "",
) -> void:
	effect_kind = kind
	effect_color = color_value
	direction = (
		direction_value.normalized()
		if direction_value.length_squared() > 0.01
		else Vector2.RIGHT
	)
	display_text = text_value
	match effect_kind:
		EffectKind.MOVE_DUST:
			duration = 0.46
		EffectKind.IMPACT:
			duration = 0.38
		EffectKind.CITY_BURST:
			duration = 0.85
		EffectKind.DAMAGE_TEXT:
			duration = 0.72
	z_index = 4090
	queue_redraw()


func _process(delta: float) -> void:
	elapsed += delta
	if elapsed >= duration:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	var progress := clampf(elapsed / maxf(duration, 0.001), 0.0, 1.0)
	match effect_kind:
		EffectKind.MOVE_DUST:
			_draw_move_dust(progress)
		EffectKind.IMPACT:
			_draw_impact(progress)
		EffectKind.CITY_BURST:
			_draw_city_burst(progress)
		EffectKind.DAMAGE_TEXT:
			_draw_damage_text(progress)


func _draw_move_dust(progress: float) -> void:
	for index in range(5):
		var angle := PI + float(index - 2) * 0.38
		var spread := Vector2(cos(angle) * 14.0, sin(angle) * 5.0) * progress
		var offset := spread + Vector2(float(index - 2) * 2.0, 4.0)
		var radius := 2.4 + progress * (3.5 + float(index % 2))
		draw_circle(offset, radius, Color(0.76, 0.70, 0.56, (1.0 - progress) * 0.25))


func _draw_impact(progress: float) -> void:
	var fade := 1.0 - progress
	var radius := 5.0 + progress * 23.0
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 28, _alpha(effect_color, fade * 0.86), 2.8, true)
	draw_circle(Vector2.ZERO, 7.0 * fade, Color(1.0, 0.92, 0.65, fade * 0.48))
	var base_angle := direction.angle()
	for index in range(8):
		var angle := base_angle + TAU * float(index) / 8.0
		var inner := Vector2.from_angle(angle) * (5.0 + progress * 5.0)
		var outer := Vector2.from_angle(angle) * (13.0 + progress * 19.0)
		draw_line(inner, outer, _alpha(effect_color.lightened(0.25), fade), 2.2, true)


func _draw_city_burst(progress: float) -> void:
	var fade := 1.0 - progress
	for ring in range(2):
		var ring_progress := clampf(progress * 1.25 - float(ring) * 0.16, 0.0, 1.0)
		var radii := Vector2(18.0 + ring_progress * 35.0, 7.0 + ring_progress * 15.0)
		draw_polyline(
			_closed(_ellipse_points(Vector2.ZERO, radii, 40)),
			_alpha(effect_color.lightened(0.18), (1.0 - ring_progress) * 0.78),
			2.4,
			true,
		)
	for index in range(10):
		var angle := TAU * float(index) / 10.0
		var inner := Vector2(cos(angle) * 16.0, sin(angle) * 7.0)
		var outer := Vector2(
			cos(angle) * (25.0 + progress * 26.0),
			sin(angle) * (11.0 + progress * 14.0),
		)
		draw_line(inner, outer, _alpha(effect_color, fade * 0.66), 1.6, true)


func _draw_damage_text(progress: float) -> void:
	var font := ThemeDB.fallback_font
	var font_size := 16
	var text_size := font.get_string_size(display_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var offset := Vector2(-text_size.x * 0.5, -30.0 - progress * 24.0)
	var fade := clampf((1.0 - progress) * 1.7, 0.0, 1.0)
	draw_string(
		font,
		offset + Vector2(1.5, 1.5),
		display_text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		font_size,
		Color(0.02, 0.03, 0.04, fade * 0.88),
	)
	draw_string(
		font,
		offset,
		display_text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		font_size,
		_alpha(effect_color.lightened(0.22), fade),
	)


func _alpha(color_value: Color, alpha_value: float) -> Color:
	return Color(color_value.r, color_value.g, color_value.b, clampf(alpha_value, 0.0, 1.0))


func _ellipse_points(center: Vector2, radii: Vector2, segments: int) -> PackedVector2Array:
	var points := PackedVector2Array()
	for index in range(segments):
		var angle := TAU * float(index) / float(segments)
		points.append(center + Vector2(cos(angle) * radii.x, sin(angle) * radii.y))
	return points


func _closed(points: PackedVector2Array) -> PackedVector2Array:
	var result := points.duplicate()
	result.append(points[0])
	return result
