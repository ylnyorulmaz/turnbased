class_name ProceduralCity
extends Node2D

## Small asset-free settlement marker shared by the player and AI factions.

var grid_coord := Vector2i.ZERO
var owner_id := 1
var city_name := "Haven"
var team_color := Color("43d9b5")


func configure(coord: Vector2i, player_id: int, settlement_name: String) -> void:
	grid_coord = coord
	owner_id = player_id
	city_name = settlement_name
	team_color = Color("43d9b5") if owner_id == 1 else Color("ef735c")
	queue_redraw()


func _draw() -> void:
	draw_colored_polygon(
		_ellipse_points(Vector2(0.0, 3.0), Vector2(30.0, 10.0)),
		Color(0.0, 0.0, 0.0, 0.36),
	)
	draw_polyline(
		_closed(_ellipse_points(Vector2(0.0, 1.0), Vector2(27.0, 9.0))),
		team_color.darkened(0.12),
		2.2,
		true,
	)

	# Back row.
	_draw_house(Vector2(-14.0, -8.0), Vector2(12.0, 13.0), Color("d0b077"))
	_draw_house(Vector2(13.0, -7.0), Vector2(11.0, 12.0), Color("b99867"))

	# Central hall and tower sit in front to create a tiny isometric skyline.
	draw_colored_polygon(
		PackedVector2Array(
			[
				Vector2(-10.0, -24.0),
				Vector2(9.0, -24.0),
				Vector2(12.0, -4.0),
				Vector2(-12.0, -4.0),
			]
		),
		Color("d6c092"),
	)
	draw_colored_polygon(
		PackedVector2Array(
			[
				Vector2(-13.0, -24.0),
				Vector2(0.0, -34.0),
				Vector2(13.0, -24.0),
			]
		),
		team_color.darkened(0.20),
	)
	draw_colored_polygon(
		PackedVector2Array(
			[
				Vector2(-3.0, -15.0),
				Vector2(3.0, -15.0),
				Vector2(3.0, -4.0),
				Vector2(-3.0, -4.0),
			]
		),
		Color("513a2c"),
	)

	# Banner identifies ownership even when zoomed out.
	draw_line(Vector2(0.0, -34.0), Vector2(0.0, -49.0), Color("28383b"), 2.0, true)
	draw_colored_polygon(
		PackedVector2Array(
			[
				Vector2(0.0, -48.0),
				Vector2(13.0, -44.0),
				Vector2(0.0, -39.0),
			]
		),
		team_color,
	)


func _draw_house(center: Vector2, size: Vector2, wall_color: Color) -> void:
	var half_width := size.x * 0.5
	draw_colored_polygon(
		PackedVector2Array(
			[
				center + Vector2(-half_width, -size.y),
				center + Vector2(half_width, -size.y),
				center + Vector2(half_width, 0.0),
				center + Vector2(-half_width, 0.0),
			]
		),
		wall_color,
	)
	draw_colored_polygon(
		PackedVector2Array(
			[
				center + Vector2(-half_width - 2.0, -size.y),
				center + Vector2(0.0, -size.y - 7.0),
				center + Vector2(half_width + 2.0, -size.y),
			]
		),
		team_color.darkened(0.30),
	)


func _ellipse_points(center: Vector2, radii: Vector2, segments: int = 32) -> PackedVector2Array:
	var points := PackedVector2Array()
	for index in range(segments):
		var angle := TAU * float(index) / float(segments)
		points.append(center + Vector2(cos(angle) * radii.x, sin(angle) * radii.y))
	return points


func _closed(points: PackedVector2Array) -> PackedVector2Array:
	var result := points.duplicate()
	result.append(points[0])
	return result
