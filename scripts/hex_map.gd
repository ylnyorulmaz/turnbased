class_name HexMap
extends Node2D

signal tile_clicked(coord: Vector2i)
signal tile_hovered(coord: Vector2i, cell: Dictionary)
signal selection_cancelled

const HEX_SIZE := 48.0
const ISO_Y_SCALE := 0.58
const SQRT_3 := 1.7320508075688772
const TILE_DEPTH := 8.0
const TEXTURE_SIZE := 64
const INVALID_COORD := Vector2i(1_000_000, 1_000_000)

var cells: Dictionary = {}
var map_width := 0
var map_height := 0
var map_seed := 0
var render_order: Array[Vector2i] = []
var reachable_tiles: Dictionary = {}
var selected_coord := INVALID_COORD
var hovered_coord := INVALID_COORD
var terrain_textures: Dictionary = {}

var _top_uvs := PackedVector2Array(
	[
		Vector2(1.0, 0.5),
		Vector2(0.75, 1.0),
		Vector2(0.25, 1.0),
		Vector2(0.0, 0.5),
		Vector2(0.25, 0.0),
		Vector2(0.75, 0.0),
	]
)


func set_map(new_cells: Dictionary, width: int, height: int, seed_value: int) -> void:
	cells = new_cells
	map_width = width
	map_height = height
	map_seed = seed_value
	reachable_tiles.clear()
	selected_coord = INVALID_COORD
	hovered_coord = INVALID_COORD
	_build_render_order()
	_build_terrain_textures(seed_value)
	queue_redraw()


func get_cell(coord: Vector2i) -> Dictionary:
	if cells.has(coord):
		return cells[coord]
	return {}


func has_cell(coord: Vector2i) -> bool:
	return cells.has(coord)


func get_neighbors(coord: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for neighbor in MapGenerator.neighbors(coord):
		if cells.has(neighbor):
			result.append(neighbor)
	return result


func set_reachable_tiles(coords: Array) -> void:
	reachable_tiles.clear()
	for coord in coords:
		reachable_tiles[coord] = true
	queue_redraw()


func set_selected_coord(coord: Vector2i) -> void:
	selected_coord = coord
	queue_redraw()


func clear_interaction_highlights() -> void:
	reachable_tiles.clear()
	selected_coord = INVALID_COORD
	queue_redraw()


func axial_to_world(coord: Vector2i) -> Vector2:
	var x := HEX_SIZE * 1.5 * float(coord.x)
	var y := HEX_SIZE * SQRT_3 * (float(coord.y) + float(coord.x) * 0.5) * ISO_Y_SCALE
	return Vector2(x, y)


func get_tile_top_center(coord: Vector2i) -> Vector2:
	var center := axial_to_world(coord)
	if cells.has(coord):
		center.y -= float(cells[coord]["elevation_px"])
	return center


func get_unit_anchor(coord: Vector2i) -> Vector2:
	return get_tile_top_center(coord) + Vector2(0.0, -3.0)


func get_world_bounds() -> Rect2:
	if cells.is_empty():
		return Rect2(Vector2.ZERO, Vector2.ONE)

	var minimum := Vector2(INF, INF)
	var maximum := Vector2(-INF, -INF)
	var half_height := HEX_SIZE * SQRT_3 * 0.5 * ISO_Y_SCALE
	for coord in cells:
		var center := get_tile_top_center(coord)
		var elevation := float(cells[coord]["elevation_px"])
		minimum.x = minf(minimum.x, center.x - HEX_SIZE)
		minimum.y = minf(minimum.y, center.y - half_height)
		maximum.x = maxf(maximum.x, center.x + HEX_SIZE)
		maximum.y = maxf(maximum.y, center.y + half_height + TILE_DEPTH + elevation * 0.45)
	return Rect2(minimum, maximum - minimum)


func get_center_coord() -> Vector2i:
	return MapGenerator.offset_to_axial(Vector2i(map_width / 2, map_height / 2))


func _draw() -> void:
	for coord in render_order:
		_draw_tile(coord, cells[coord])


func _draw_tile(coord: Vector2i, cell: Dictionary) -> void:
	var terrain := int(cell["terrain"])
	var elevation := float(cell["elevation_px"])
	var center := get_tile_top_center(coord)
	var polygon := _hex_points(center)
	var depth := TILE_DEPTH + elevation * 0.45
	var down := Vector2(0.0, depth)
	var side_base := _terrain_base_color(terrain)

	# Three downward-facing faces sell the isometric height without any sprites.
	draw_colored_polygon(
		PackedVector2Array(
			[
				polygon[0],
				polygon[1],
				polygon[1] + down,
				polygon[0] + down,
			]
		),
		side_base.darkened(0.34)
	)
	draw_colored_polygon(
		PackedVector2Array(
			[
				polygon[1],
				polygon[2],
				polygon[2] + down,
				polygon[1] + down,
			]
		),
		side_base.darkened(0.44)
	)
	draw_colored_polygon(
		PackedVector2Array(
			[
				polygon[2],
				polygon[3],
				polygon[3] + down,
				polygon[2] + down,
			]
		),
		side_base.darkened(0.28)
	)

	var moisture := float(cell["moisture"])
	var tint_strength := 0.90 + moisture * 0.10
	var tint := Color(tint_strength, tint_strength, 0.94 + moisture * 0.06, 1.0)
	var texture: Texture2D = terrain_textures.get(terrain)
	draw_colored_polygon(polygon, tint, _top_uvs, texture)

	var outline := _closed_polygon(polygon)
	draw_polyline(outline, Color(0.025, 0.045, 0.055, 0.78), 1.25, true)
	_draw_terrain_details(coord, center, terrain)

	if reachable_tiles.has(coord):
		draw_colored_polygon(polygon, Color(0.16, 0.90, 0.72, 0.20))
		draw_polyline(outline, Color(0.32, 1.0, 0.78, 0.92), 2.2, true)
	if coord == hovered_coord:
		draw_colored_polygon(polygon, Color(1.0, 1.0, 1.0, 0.10))
		draw_polyline(outline, Color(0.92, 0.97, 1.0, 0.95), 2.0, true)
	if coord == selected_coord:
		draw_polyline(outline, Color(1.0, 0.78, 0.23, 1.0), 3.4, true)


func _draw_terrain_details(coord: Vector2i, center: Vector2, terrain: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = abs(coord.x * 73_856_093 ^ coord.y * 19_349_663 ^ map_seed * 83_492_791)

	match terrain:
		MapGenerator.Terrain.SEA:
			for index in range(3):
				var wave_y := center.y - 9.0 + float(index) * 8.0 + rng.randf_range(-1.5, 1.5)
				var wave_x := center.x + rng.randf_range(-17.0, -8.0)
				draw_polyline(
					PackedVector2Array(
						[
							Vector2(wave_x, wave_y),
							Vector2(wave_x + 7.0, wave_y - 2.0),
							Vector2(wave_x + 14.0, wave_y),
							Vector2(wave_x + 21.0, wave_y - 2.0),
						]
					),
					Color(0.62, 0.91, 0.97, 0.48),
					1.2,
					true
				)
		MapGenerator.Terrain.PLAINS:
			for index in range(5):
				var grass := (
					center + Vector2(rng.randf_range(-25.0, 25.0), rng.randf_range(-11.0, 12.0))
				)
				draw_line(
					grass, grass + Vector2(-2.0, -4.0), Color(0.18, 0.34, 0.14, 0.55), 1.1, true
				)
				draw_line(
					grass, grass + Vector2(2.5, -3.3), Color(0.18, 0.34, 0.14, 0.48), 1.1, true
				)
		MapGenerator.Terrain.HILLS:
			for index in range(2):
				var hill_center := (
					center + Vector2(-11.0 + float(index) * 20.0, 5.0 - float(index) * 3.0)
				)
				draw_arc(
					hill_center,
					11.0,
					PI + 0.12,
					TAU - 0.12,
					12,
					Color(0.28, 0.31, 0.15, 0.62),
					1.7,
					true
				)
				draw_line(
					hill_center + Vector2(-10.0, 0.0),
					hill_center + Vector2(10.0, 0.0),
					Color(0.28, 0.31, 0.15, 0.40),
					1.0,
					true
				)
		MapGenerator.Terrain.MOUNTAINS:
			var peak := center + Vector2(0.0, -13.0)
			var mountain := PackedVector2Array(
				[
					peak + Vector2(-18.0, 18.0),
					peak,
					peak + Vector2(18.0, 18.0),
				]
			)
			draw_colored_polygon(mountain, Color(0.20, 0.23, 0.24, 0.72))
			draw_colored_polygon(
				PackedVector2Array(
					[
						peak,
						peak + Vector2(-6.0, 6.2),
						peak + Vector2(0.0, 4.0),
						peak + Vector2(6.0, 7.0),
					]
				),
				Color(0.88, 0.92, 0.90, 0.88)
			)
			draw_line(peak + Vector2(-18.0, 18.0), peak, Color(0.70, 0.75, 0.72, 0.40), 1.2, true)


func _hex_points(center: Vector2) -> PackedVector2Array:
	var half_height := HEX_SIZE * SQRT_3 * 0.5 * ISO_Y_SCALE
	return PackedVector2Array(
		[
			center + Vector2(HEX_SIZE, 0.0),
			center + Vector2(HEX_SIZE * 0.5, half_height),
			center + Vector2(-HEX_SIZE * 0.5, half_height),
			center + Vector2(-HEX_SIZE, 0.0),
			center + Vector2(-HEX_SIZE * 0.5, -half_height),
			center + Vector2(HEX_SIZE * 0.5, -half_height),
		]
	)


func _closed_polygon(polygon: PackedVector2Array) -> PackedVector2Array:
	var result := polygon.duplicate()
	result.append(polygon[0])
	return result


func _build_render_order() -> void:
	render_order.clear()
	for coord in cells:
		render_order.append(coord)
	render_order.sort_custom(_sort_coords)


func _sort_coords(a: Vector2i, b: Vector2i) -> bool:
	var a_position := axial_to_world(a)
	var b_position := axial_to_world(b)
	if is_equal_approx(a_position.y, b_position.y):
		return a_position.x < b_position.x
	return a_position.y < b_position.y


func _build_terrain_textures(seed_value: int) -> void:
	terrain_textures.clear()
	for terrain in range(MapGenerator.Terrain.size()):
		var image := Image.create_empty(TEXTURE_SIZE, TEXTURE_SIZE, false, Image.FORMAT_RGBA8)
		var grain_noise := FastNoiseLite.new()
		grain_noise.seed = seed_value + terrain * 1013
		grain_noise.noise_type = FastNoiseLite.TYPE_PERLIN
		grain_noise.frequency = 0.105 + float(terrain) * 0.012
		grain_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
		grain_noise.fractal_octaves = 3

		var base := _terrain_base_color(terrain)
		for y in range(TEXTURE_SIZE):
			for x in range(TEXTURE_SIZE):
				var grain := grain_noise.get_noise_2d(float(x), float(y)) * 0.12
				var pattern := 0.0
				match terrain:
					MapGenerator.Terrain.SEA:
						pattern = sin(float(y) * 0.42 + sin(float(x) * 0.16)) * 0.035
					MapGenerator.Terrain.PLAINS:
						pattern = sin(float(x + y) * 0.29) * 0.018
					MapGenerator.Terrain.HILLS:
						pattern = sin(float(x) * 0.18 + float(y) * 0.31) * 0.045
					MapGenerator.Terrain.MOUNTAINS:
						pattern = (
							absf(grain_noise.get_noise_2d(float(x) * 1.7, float(y) * 1.7)) * -0.08
						)

				var variation := clampf(grain + pattern, -0.18, 0.18)
				var pixel := (
					base.lightened(variation) if variation >= 0.0 else base.darkened(-variation)
				)
				image.set_pixel(x, y, pixel)

		image.generate_mipmaps()
		terrain_textures[terrain] = ImageTexture.create_from_image(image)


func _terrain_base_color(terrain: int) -> Color:
	match terrain:
		MapGenerator.Terrain.SEA:
			return Color("277c91")
		MapGenerator.Terrain.PLAINS:
			return Color("87a85a")
		MapGenerator.Terrain.HILLS:
			return Color("a49a55")
		MapGenerator.Terrain.MOUNTAINS:
			return Color("687274")
		_:
			return Color.MAGENTA


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_update_hover(_pick_tile(to_local(get_global_mouse_position())))
	elif event is InputEventMouseButton and event.pressed:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT:
			var picked := _pick_tile(to_local(get_global_mouse_position()))
			if picked != INVALID_COORD:
				tile_clicked.emit(picked)
				get_viewport().set_input_as_handled()
		elif mouse_event.button_index == MOUSE_BUTTON_RIGHT:
			selection_cancelled.emit()
			get_viewport().set_input_as_handled()


func _update_hover(coord: Vector2i) -> void:
	if coord == hovered_coord:
		return
	hovered_coord = coord
	if coord == INVALID_COORD:
		tile_hovered.emit(coord, {})
	else:
		tile_hovered.emit(coord, cells[coord])
	queue_redraw()


func _pick_tile(point: Vector2) -> Vector2i:
	for index in range(render_order.size() - 1, -1, -1):
		var coord := render_order[index]
		if _point_in_polygon(point, _hex_points(get_tile_top_center(coord))):
			return coord
	return INVALID_COORD


func _point_in_polygon(point: Vector2, polygon: PackedVector2Array) -> bool:
	var inside := false
	var previous := polygon.size() - 1
	for current in range(polygon.size()):
		var a := polygon[current]
		var b := polygon[previous]
		if (a.y > point.y) != (b.y > point.y):
			var intersection_x := (b.x - a.x) * (point.y - a.y) / (b.y - a.y) + a.x
			if point.x < intersection_x:
				inside = not inside
		previous = current
	return inside
