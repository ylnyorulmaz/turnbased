class_name HudChrome
extends Control

## Lightweight procedural framing behind the HUD panels.


func _ready() -> void:
	resized.connect(queue_redraw)
	queue_redraw()


func _draw() -> void:
	var viewport_size := size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return

	draw_rect(Rect2(Vector2.ZERO, Vector2(viewport_size.x, 86.0)), Color(0.01, 0.025, 0.034, 0.24))
	draw_rect(
		Rect2(Vector2(0.0, viewport_size.y - 62.0), Vector2(viewport_size.x, 62.0)),
		Color(0.01, 0.025, 0.034, 0.28),
	)
	draw_line(
		Vector2(0.0, 86.0),
		Vector2(viewport_size.x, 86.0),
		Color(0.30, 0.86, 0.72, 0.10),
		1.0,
	)
	draw_line(
		Vector2(0.0, viewport_size.y - 62.0),
		Vector2(viewport_size.x, viewport_size.y - 62.0),
		Color(0.30, 0.86, 0.72, 0.10),
		1.0,
	)

	_draw_corner(Vector2(12.0, 12.0), Vector2.RIGHT, Vector2.DOWN)
	_draw_corner(Vector2(viewport_size.x - 12.0, 12.0), Vector2.LEFT, Vector2.DOWN)
	_draw_corner(Vector2(12.0, viewport_size.y - 12.0), Vector2.RIGHT, Vector2.UP)
	_draw_corner(
		Vector2(viewport_size.x - 12.0, viewport_size.y - 12.0), Vector2.LEFT, Vector2.UP
	)


func _draw_corner(origin: Vector2, horizontal: Vector2, vertical: Vector2) -> void:
	var color := Color(0.42, 0.96, 0.80, 0.34)
	draw_line(origin, origin + horizontal * 24.0, color, 2.0, true)
	draw_line(origin, origin + vertical * 24.0, color, 2.0, true)
