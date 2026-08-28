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
const REDRAW_INTERVAL := 1.0 / 18.0
const EDGE_BY_DIRECTION: Array[Vector2i] = [
	Vector2i(0, 1),
	Vector2i(5, 0),
	Vector2i(4, 5),
	Vector2i(3, 4),
	Vector2i(2, 3),
	Vector2i(1, 2),
]

var cells: Dictionary = {}
var map_width := 0
var map_height := 0
var map_seed := 0
var render_order: Array[Vector2i] = []
var reachable_tiles: Dictionary = {}
var attack_tiles: Dictionary = {}
var preview_path: Array[Vector2i] = []
var selected_coord := INVALID_COORD
var hovered_coord := INVALID_COORD
var terrain_textures: Dictionary = {}
var visual_time := 0.0
var _redraw_accumulator := 0.0

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
	attack_tiles.clear()
	preview_path.clear()
	selected_coord = INVALID_COORD
	hovered_coord = INVALID_COORD
	_build_render_order()
	_build_terrain_textures(seed_value)
	queue_redraw()


func _process(delta: float) -> void:
	visual_time = fmod(visual_time + delta, TAU * 100.0)
	_redraw_accumulator += delta
	if _redraw_accumulator >= REDRAW_INTERVAL:
		_redraw_accumulator = 0.0
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


func set_attack_tiles(coords: Array) -> void:
	attack_tiles.clear()
	for coord in coords:
		attack_tiles[coord] = true
	queue_redraw()


func set_preview_path(path: Array) -> void:
	preview_path.clear()
	for coord in path:
		preview_path.append(coord)
	queue_redraw()


func set_selected_coord(coord: Vector2i) -> void:
	selected_coord = coord
	queue_redraw()


func clear_interaction_highlights() -> void:
	reachable_tiles.clear()
	attack_tiles.clear()
	preview_path.clear()
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
	_draw_map_backdrop()
	for coord in render_order:
		_draw_tile(coord, cells[coord])
	_draw_preview_path()


func _draw_map_backdrop() -> void:
	if cells.is_empty():
		return
	var bounds := get_world_bounds()
	var center := bounds.get_center() + Vector2(0.0, 34.0)
	var radii := bounds.size * Vector2(0.53, 0.39)
	for layer in range(4, 0, -1):
		var spread := float(layer) * 18.0
		var alpha := 0.035 + float(4 - layer) * 0.018
		draw_colored_polygon(
			_ellipse_points(center, radii + Vector2(spread * 1.6, spread), 72),
			Color(0.0, 0.0, 0.0, alpha),
		)


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
	if terrain == MapGenerator.Terrain.SEA:
		tint_strength += sin(visual_time * 0.75 + float(coord.x - coord.y) * 0.52) * 0.025
	var tint := Color(tint_strength, tint_strength, 0.94 + moisture * 0.06, 1.0)
	var texture: Texture2D = terrain_textures.get(terrain)
	draw_colored_polygon(polygon, tint, _top_uvs, texture)

	var outline := _closed_polygon(polygon)
	draw_polyline(outline, Color(0.025, 0.045, 0.055, 0.78), 1.25, true)
	draw_polyline(
		PackedVector2Array([polygon[3], polygon[4], polygon[5], polygon[0]]),
		Color(0.88, 0.98, 0.94, 0.13),
		1.0,
		true,
	)
	_draw_terrain_details(coord, center, terrain)
	if terrain == MapGenerator.Terrain.SEA:
		_draw_coast_foam(coord, polygon)

	if reachable_tiles.has(coord):
		var pulse := 0.5 + 0.5 * sin(visual_time * 4.2 + float(coord.x + coord.y) * 0.65)
		draw_colored_polygon(polygon, Color(0.10, 0.95, 0.70, 0.12 + pulse * 0.08))
		draw_polyline(outline, Color(0.38, 1.0, 0.80, 0.72 + pulse * 0.25), 2.0, true)
		draw_circle(center, 3.0 + pulse * 1.3, Color(0.72, 1.0, 0.89, 0.72))
	if attack_tiles.has(coord):
		var attack_pulse := 0.5 + 0.5 * sin(visual_time * 6.0)
		draw_colored_polygon(polygon, Color(0.98, 0.13, 0.10, 0.18 + attack_pulse * 0.10))
		draw_polyline(outline, Color(1.0, 0.36, 0.27, 0.86 + attack_pulse * 0.14), 2.6, true)
		draw_arc(center, 10.0 + attack_pulse * 3.0, 0.0, TAU, 24, Color(1.0, 0.72, 0.52, 0.88), 1.8, true)
	if coord == hovered_coord:
		draw_colored_polygon(polygon, Color(1.0, 1.0, 1.0, 0.10))
		draw_polyline(outline, Color(0.92, 0.97, 1.0, 0.95), 2.0, true)
		draw_polyline(
			_closed_polygon(_scaled_polygon(polygon, center, 0.78)),
			Color(0.91, 0.98, 1.0, 0.42),
			1.0,
			true,
		)
	if coord == selected_coord:
		var selection_pulse := 0.5 + 0.5 * sin(visual_time * 4.8)
		draw_polyline(outline, Color(1.0, 0.76, 0.20, 1.0), 3.2 + selection_pulse, true)
		draw_polyline(
			_closed_polygon(_scaled_polygon(polygon, center, 0.86)),
			Color(1.0, 0.91, 0.55, 0.48 + selection_pulse * 0.35),
			1.4,
			true,
		)


func _draw_terrain_details(coord: Vector2i, center: Vector2, terrain: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = abs(coord.x * 73_856_093 ^ coord.y * 19_349_663 ^ map_seed * 83_492_791)

	match terrain:
		MapGenerator.Terrain.SEA:
			for index in range(3):
				var wave_y := center.y - 9.0 + float(index) * 8.0 + rng.randf_range(-1.5, 1.5)
				var phase := visual_time * 1.4 + float(index) * 1.8 + float(coord.x - coord.y)
				var wave_x := center.x + rng.randf_range(-18.0, -9.0) + sin(phase) * 2.5
				draw_polyline(
					PackedVector2Array(
						[
							Vector2(wave_x, wave_y),
							Vector2(wave_x + 7.0, wave_y - 2.0),
							Vector2(wave_x + 14.0, wave_y),
							Vector2(wave_x + 21.0, wave_y - 2.0),
						]
					),
					Color(0.66, 0.94, 1.0, 0.38 + 0.14 * sin(phase)),
					1.35,
					true
				)
		MapGenerator.Terrain.PLAINS:
			var moisture := float(cells[coord]["moisture"])
			for index in range(7):
				var grass := (
					center + Vector2(rng.randf_range(-25.0, 25.0), rng.randf_range(-11.0, 12.0))
				)
				draw_line(
					grass, grass + Vector2(-2.0, -4.0), Color(0.18, 0.34, 0.14, 0.55), 1.1, true
				)
				draw_line(
					grass, grass + Vector2(2.5, -3.3), Color(0.18, 0.34, 0.14, 0.48), 1.1, true
				)
				if moisture > 0.58 and index < 2:
					draw_circle(grass + Vector2(0.5, -4.2), 1.25, Color(0.96, 0.83, 0.42, 0.88))
		MapGenerator.Terrain.HILLS:
			for index in range(3):
				var hill_center := (
					center + Vector2(-18.0 + float(index) * 17.0, 6.0 - float(index % 2) * 5.0)
				)
				draw_arc(
					hill_center,
					10.0 + float(index % 2) * 2.0,
					PI + 0.12,
					TAU - 0.12,
					12,
					Color(0.28, 0.31, 0.15, 0.62),
					1.7,
					true
				)
				draw_line(
					hill_center + Vector2(-9.0, -1.0),
					hill_center + Vector2(9.0, -1.0),
					Color(0.82, 0.78, 0.42, 0.32),
					1.0,
					true
				)
		MapGenerator.Terrain.MOUNTAINS:
			_draw_mountain_peak(center + Vector2(-13.0, -6.0), 0.74)
			_draw_mountain_peak(center + Vector2(13.0, -4.0), 0.66)
			_draw_mountain_peak(center + Vector2(0.0, -13.0), 1.0)


func _draw_mountain_peak(peak: Vector2, scale_value: float) -> void:
	var left := peak + Vector2(-19.0, 20.0) * scale_value
	var right := peak + Vector2(19.0, 20.0) * scale_value
	var foot := peak + Vector2(1.0, 20.0) * scale_value
	draw_colored_polygon(PackedVector2Array([left, peak, foot]), Color(0.38, 0.43, 0.44, 0.96))
	draw_colored_polygon(PackedVector2Array([peak, right, foot]), Color(0.20, 0.25, 0.27, 0.96))
	draw_colored_polygon(
		PackedVector2Array(
			[
				peak,
				peak + Vector2(-6.5, 7.0) * scale_value,
				peak + Vector2(-1.0, 5.0) * scale_value,
				peak + Vector2(4.0, 8.0) * scale_value,
				peak + Vector2(7.0, 7.0) * scale_value,
			]
		),
		Color(0.92, 0.96, 0.94, 0.92),
	)
	draw_line(left, peak, Color(0.78, 0.84, 0.81, 0.44), 1.25, true)


func _draw_coast_foam(coord: Vector2i, polygon: PackedVector2Array) -> void:
	for direction_index in range(MapGenerator.AXIAL_DIRECTIONS.size()):
		var neighbor := coord + MapGenerator.AXIAL_DIRECTIONS[direction_index]
		if not cells.has(neighbor):
			continue
		if int(cells[neighbor]["terrain"]) == MapGenerator.Terrain.SEA:
			continue
		var edge := EDGE_BY_DIRECTION[direction_index]
		var start := polygon[edge.x].lerp(polygon[edge.y], 0.10)
		var finish := polygon[edge.x].lerp(polygon[edge.y], 0.90)
		draw_line(start, finish, Color(0.08, 0.37, 0.46, 0.72), 4.0, true)
		draw_line(start, finish, Color(0.78, 0.97, 1.0, 0.72), 1.5, true)


func _draw_preview_path() -> void:
	if selected_coord == INVALID_COORD or preview_path.is_empty():
		return
	var points := PackedVector2Array([get_tile_top_center(selected_coord)])
	for coord in preview_path:
		if cells.has(coord):
			points.append(get_tile_top_center(coord))
	if points.size() < 2:
		return
	draw_polyline(points, Color(0.015, 0.035, 0.04, 0.82), 6.5, true)
	draw_polyline(points, Color(0.97, 0.88, 0.46, 0.92), 2.4, true)
	for index in range(1, points.size()):
		draw_circle(points[index], 4.1, Color(0.06, 0.12, 0.12, 0.92))
		draw_circle(points[index], 2.3, Color(1.0, 0.91, 0.52, 1.0))


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


func _scaled_polygon(
	polygon: PackedVector2Array, center: Vector2, scale_value: float
) -> PackedVector2Array:
	var result := PackedVector2Array()
	for point in polygon:
		result.append(center + (point - center) * scale_value)
	return result


func _ellipse_points(center: Vector2, radii: Vector2, segments: int = 48) -> PackedVector2Array:
	var points := PackedVector2Array()
	for index in range(segments):
		var angle := TAU * float(index) / float(segments)
		points.append(center + Vector2(cos(angle) * radii.x, sin(angle) * radii.y))
	return points


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
			return Color("247b94")
		MapGenerator.Terrain.PLAINS:
			return Color("82aa58")
		MapGenerator.Terrain.HILLS:
			return Color("a89b53")
		MapGenerator.Terrain.MOUNTAINS:
			return Color("667376")
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
