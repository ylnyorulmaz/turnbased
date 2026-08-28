class_name ProceduralCity
extends Node2D

## Small asset-free settlement marker shared by the player and AI factions.

var grid_coord := Vector2i.ZERO
var owner_id := 1
var city_name := "Haven"
var team_color := Color("43d9b5")
var visual_time := 0.0
var _phase_offset := 0.0


func configure(coord: Vector2i, player_id: int, settlement_name: String) -> void:
	grid_coord = coord
	owner_id = player_id
	city_name = settlement_name
	team_color = Color("43d9b5") if owner_id == 1 else Color("ef735c")
	_phase_offset = float(abs(coord.x * 23 + coord.y * 31)) * 0.11
	queue_redraw()


func _process(delta: float) -> void:
	visual_time = fmod(visual_time + delta, TAU * 100.0)
	queue_redraw()


func _draw() -> void:
	var glow := 0.5 + 0.5 * sin(visual_time * 2.2 + _phase_offset)
	draw_colored_polygon(
		_ellipse_points(Vector2(2.0, 5.0), Vector2(34.0, 12.0)),
		Color(0.0, 0.0, 0.0, 0.42),
	)
	draw_colored_polygon(
		_ellipse_points(Vector2(0.0, 1.0), Vector2(31.0, 10.0)),
		Color(team_color.r, team_color.g, team_color.b, 0.12 + glow * 0.05),
	)
	draw_polyline(
		_closed(_ellipse_points(Vector2(0.0, 1.0), Vector2(30.0, 9.5))),
		team_color.lightened(0.08),
		2.4,
		true,
	)

	# Short roads make the settlement sit on the tile instead of floating above it.
	draw_colored_polygon(
		PackedVector2Array(
			[
				Vector2(-5.0, -2.0),
				Vector2(5.0, -2.0),
				Vector2(15.0, 7.0),
				Vector2(-15.0, 7.0),
			]
		),
		Color(0.56, 0.48, 0.34, 0.78),
	)
	_draw_smoke()

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
	draw_rect(Rect2(Vector2(-7.0, -23.0), Vector2(4.0, 4.0)), Color("ffe19b"))
	draw_rect(Rect2(Vector2(3.0, -23.0), Vector2(4.0, 4.0)), Color("ffe19b"))
	draw_line(Vector2(-12.0, -4.0), Vector2(12.0, -4.0), Color("6f593c"), 1.2, true)

	# Banner identifies ownership even when zoomed out.
	draw_line(Vector2(0.0, -34.0), Vector2(0.0, -49.0), Color("28383b"), 2.0, true)
	var flutter := sin(visual_time * 4.0 + _phase_offset) * 2.0
	draw_colored_polygon(
		PackedVector2Array(
			[
				Vector2(0.0, -48.0),
				Vector2(13.0 + flutter, -44.0),
				Vector2(0.0, -39.0),
			]
		),
		team_color,
	)
	_draw_nameplate()


func _draw_smoke() -> void:
	var base := Vector2(17.0, -24.0)
	draw_rect(Rect2(base + Vector2(-2.0, 0.0), Vector2(4.0, 9.0)), Color("594a3d"))
	for index in range(3):
		var cycle := fmod(visual_time * 0.55 + float(index) * 0.33 + _phase_offset, 1.0)
		var puff_position := base + Vector2(sin(cycle * TAU) * 2.0, -5.0 - cycle * 18.0)
		var puff_alpha := (1.0 - cycle) * 0.24
		draw_circle(puff_position, 3.0 + cycle * 3.0, Color(0.78, 0.82, 0.79, puff_alpha))


func _draw_nameplate() -> void:
	var font := ThemeDB.fallback_font
	var font_size := 10
	var text_size := font.get_string_size(city_name, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var plate := Rect2(
		Vector2(-text_size.x * 0.5 - 8.0, -67.0), Vector2(text_size.x + 16.0, 17.0)
	)
	draw_rect(plate, Color(0.025, 0.045, 0.052, 0.91), true)
	draw_rect(plate, Color(team_color.r, team_color.g, team_color.b, 0.82), false, 1.2)
	draw_circle(Vector2(plate.position.x + 6.0, plate.position.y + 8.5), 2.2, team_color)
	draw_string(
		font,
		Vector2(-text_size.x * 0.5 + 3.0, -54.0),
		city_name,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		font_size,
		Color(0.92, 0.96, 0.93, 1.0),
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
	draw_rect(
		Rect2(center + Vector2(-2.0, -size.y + 4.0), Vector2(4.0, 4.0)),
		Color("f7d88a"),
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
