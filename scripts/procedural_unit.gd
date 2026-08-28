class_name ProceduralUnit
extends Node2D

## Asset-free unit renderer and the small amount of state a turn system needs.

enum UnitKind {
	SETTLER,
	WARRIOR,
}

var unit_kind := UnitKind.SETTLER
var grid_coord := Vector2i.ZERO
var owner_id := 1
var display_name := "Settler"
var movement_max := 2
var movement_left := 2
var health_max := 1
var health := 1
var attack_damage := 0
var selected := false

var team_color := Color("43d9b5")


func configure(kind: int, coord: Vector2i, player_id: int = 1) -> void:
	unit_kind = kind
	grid_coord = coord
	owner_id = player_id
	match unit_kind:
		UnitKind.SETTLER:
			display_name = "Settler"
			movement_max = 2
			health_max = 1
			attack_damage = 0
		UnitKind.WARRIOR:
			display_name = "Warrior"
			movement_max = 3
			health_max = 3
			attack_damage = 1
	movement_left = movement_max
	health = health_max
	team_color = Color("43d9b5") if owner_id == 1 else Color("ef735c")
	queue_redraw()


func set_selected(value: bool) -> void:
	selected = value
	queue_redraw()


func reset_for_new_turn() -> void:
	movement_left = movement_max
	queue_redraw()


func spend_movement(amount: int) -> void:
	movement_left = maxi(0, movement_left - amount)
	queue_redraw()


func take_damage(amount: int) -> bool:
	health = maxi(0, health - amount)
	queue_redraw()
	return health <= 0


func can_attack() -> bool:
	return unit_kind == UnitKind.WARRIOR and attack_damage > 0 and movement_left > 0


func movement_cost(terrain: int) -> int:
	match terrain:
		MapGenerator.Terrain.SEA:
			return -1
		MapGenerator.Terrain.PLAINS:
			return 1
		MapGenerator.Terrain.HILLS:
			return 2
		MapGenerator.Terrain.MOUNTAINS:
			return 2 if unit_kind == UnitKind.WARRIOR else -1
		_:
			return -1


func _draw() -> void:
	# The ellipse reads as a footprint on the flattened isometric tile.
	draw_colored_polygon(
		_ellipse_points(Vector2(0.0, 2.0), Vector2(20.0, 7.5)), Color(0.0, 0.0, 0.0, 0.34)
	)
	if selected:
		draw_polyline(
			_closed(_ellipse_points(Vector2(0.0, 1.0), Vector2(24.0, 10.0))),
			Color(1.0, 0.78, 0.23, 0.98),
			2.7,
			true
		)

	match unit_kind:
		UnitKind.SETTLER:
			_draw_settler()
		UnitKind.WARRIOR:
			_draw_warrior()

	_draw_movement_pips()
	_draw_health_pips()


func _draw_settler() -> void:
	# Walking staff, pack, cloak, head and bedroll; all vector primitives.
	draw_line(Vector2(12.0, -29.0), Vector2(15.0, 0.0), Color("6b482d"), 2.5, true)
	draw_line(Vector2(11.0, -29.0), Vector2(16.0, -29.0), Color("d8c5a2"), 1.2, true)

	draw_colored_polygon(
		PackedVector2Array(
			[
				Vector2(-11.0, -19.0),
				Vector2(-16.0, -7.0),
				Vector2(-10.0, -1.0),
				Vector2(-4.0, -5.0),
				Vector2(-4.0, -18.0),
			]
		),
		Color("6f4932")
	)
	draw_circle(Vector2(-11.0, -13.0), 4.2, Color("c98c45"))
	draw_line(Vector2(-14.0, -13.0), Vector2(-8.0, -13.0), Color("754827"), 1.0, true)

	var cloak := PackedVector2Array(
		[
			Vector2(-6.5, -20.0),
			Vector2(5.5, -20.0),
			Vector2(11.5, -2.0),
			Vector2(-11.0, -2.0),
		]
	)
	draw_colored_polygon(cloak, Color("d9b66f"))
	draw_colored_polygon(
		PackedVector2Array(
			[
				Vector2(0.0, -20.0),
				Vector2(5.5, -20.0),
				Vector2(11.5, -2.0),
				Vector2(2.0, -2.0),
			]
		),
		Color("bc8f4f")
	)
	draw_line(Vector2(-10.0, -2.0), Vector2(11.0, -2.0), Color("6b4930"), 1.5, true)

	draw_circle(Vector2(0.0, -26.0), 6.2, Color("d7a070"))
	draw_arc(Vector2(0.0, -27.0), 6.5, PI, TAU, 12, Color("4a3026"), 4.0, true)
	draw_line(Vector2(-3.0, -24.5), Vector2(4.5, -24.5), Color("8b573c"), 1.0, true)

	# Small faction pennant keeps ownership visible at any zoom.
	draw_line(Vector2(-14.0, -27.0), Vector2(-14.0, -9.0), Color("25363a"), 1.8, true)
	draw_colored_polygon(
		PackedVector2Array(
			[
				Vector2(-14.0, -27.0),
				Vector2(-4.0, -23.0),
				Vector2(-14.0, -19.0),
			]
		),
		team_color
	)


func _draw_warrior() -> void:
	# Spear sits behind the body.
	draw_line(Vector2(11.0, -37.0), Vector2(7.0, 0.0), Color("704b2d"), 2.4, true)
	draw_colored_polygon(
		PackedVector2Array(
			[
				Vector2(11.0, -40.0),
				Vector2(7.5, -34.0),
				Vector2(13.0, -35.0),
			]
		),
		Color("dfe6e2")
	)

	draw_line(Vector2(-4.5, -9.0), Vector2(-6.0, 0.0), Color("3b2b25"), 3.2, true)
	draw_line(Vector2(4.5, -9.0), Vector2(6.0, 0.0), Color("3b2b25"), 3.2, true)

	var body := PackedVector2Array(
		[
			Vector2(-9.0, -23.0),
			Vector2(8.0, -23.0),
			Vector2(10.0, -8.0),
			Vector2(0.0, -4.0),
			Vector2(-10.0, -8.0),
		]
	)
	draw_colored_polygon(body, Color("8b3940"))
	draw_line(Vector2(-8.0, -16.0), Vector2(8.0, -16.0), Color("d4b56a"), 2.0, true)
	draw_line(Vector2(-5.0, -22.0), Vector2(4.0, -8.0), Color("c6a45a"), 2.3, true)

	draw_circle(Vector2(0.0, -28.0), 6.0, Color("d5a078"))
	draw_colored_polygon(
		PackedVector2Array(
			[
				Vector2(-7.0, -29.0),
				Vector2(-4.0, -35.0),
				Vector2(5.0, -35.0),
				Vector2(7.0, -28.0),
			]
		),
		Color("4e5a5c")
	)
	draw_line(Vector2(-7.0, -28.5), Vector2(7.0, -28.5), Color("d0b25f"), 2.0, true)
	draw_line(Vector2(0.0, -35.0), Vector2(0.0, -39.0), team_color, 2.2, true)

	# Shield in front of the torso.
	draw_colored_polygon(
		_ellipse_points(Vector2(-9.0, -14.0), Vector2(8.5, 10.5), 24), Color("334c57")
	)
	draw_polyline(
		_closed(_ellipse_points(Vector2(-9.0, -14.0), Vector2(8.5, 10.5), 24)),
		Color("d3b35f"),
		2.0,
		true
	)
	draw_line(Vector2(-15.0, -14.0), Vector2(-3.0, -14.0), team_color, 2.0, true)
	draw_line(Vector2(-9.0, -21.0), Vector2(-9.0, -7.0), team_color, 2.0, true)


func _draw_movement_pips() -> void:
	var gap := 6.0
	var start_x := -float(movement_max - 1) * gap * 0.5
	for index in range(movement_max):
		var color := team_color if index < movement_left else Color(0.18, 0.22, 0.23, 0.72)
		draw_circle(Vector2(start_x + float(index) * gap, 8.5), 2.1, color)


func _draw_health_pips() -> void:
	var gap := 6.0
	var start_x := -float(health_max - 1) * gap * 0.5
	for index in range(health_max):
		var color := Color("f06b62") if index < health else Color(0.16, 0.18, 0.19, 0.82)
		draw_circle(Vector2(start_x + float(index) * gap, -45.0), 2.2, color)


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
