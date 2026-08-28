class_name MapGenerator
extends RefCounted

## Deterministic island generator for a rectangular, odd-q offset hex map.
## Every returned cell is keyed by axial coordinates (q, r).

enum Terrain {
	SEA,
	PLAINS,
	HILLS,
	MOUNTAINS,
}

const AXIAL_DIRECTIONS: Array[Vector2i] = [
	Vector2i(1, 0),
	Vector2i(1, -1),
	Vector2i(0, -1),
	Vector2i(-1, 0),
	Vector2i(-1, 1),
	Vector2i(0, 1),
]


static func generate(width: int, height: int, map_seed: int) -> Dictionary:
	var elevation_noise := FastNoiseLite.new()
	elevation_noise.seed = map_seed
	elevation_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	elevation_noise.frequency = 0.085
	elevation_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	elevation_noise.fractal_octaves = 5
	elevation_noise.fractal_lacunarity = 2.05
	elevation_noise.fractal_gain = 0.52

	var detail_noise := FastNoiseLite.new()
	detail_noise.seed = map_seed + 7919
	detail_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	detail_noise.frequency = 0.19
	detail_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	detail_noise.fractal_octaves = 3
	detail_noise.fractal_gain = 0.46

	var moisture_noise := FastNoiseLite.new()
	moisture_noise.seed = map_seed - 3571
	moisture_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	moisture_noise.frequency = 0.12
	moisture_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	moisture_noise.fractal_octaves = 4

	var cells: Dictionary = {}

	for column in range(width):
		for row in range(height):
			var coord := offset_to_axial(Vector2i(column, row))
			var nx := (float(column) - float(width - 1) * 0.5) / maxf(float(width) * 0.5, 1.0)
			var ny := (float(row) - float(height - 1) * 0.5) / maxf(float(height) * 0.5, 1.0)
			var radial_distance := sqrt(nx * nx + ny * ny)
			var island_mask := clampf(1.0 - pow(radial_distance, 1.65), 0.0, 1.0)

			var continental := (elevation_noise.get_noise_2d(float(column), float(row)) + 1.0) * 0.5
			var detail := detail_noise.get_noise_2d(float(column), float(row)) * 0.09
			var elevation_score := continental * 0.58 + island_mask * 0.62 + detail - 0.20

			# A guaranteed ocean rim makes the generated landmass read as an island.
			if column == 0 or row == 0 or column == width - 1 or row == height - 1:
				elevation_score -= 0.40

			var moisture := clampf(
				(moisture_noise.get_noise_2d(float(column), float(row)) + 1.0) * 0.5, 0.0, 1.0
			)
			var terrain := _terrain_from_height(elevation_score)
			cells[coord] = {
				"terrain": terrain,
				"height": elevation_score,
				"moisture": moisture,
				"elevation_px": _visual_elevation(terrain, elevation_score),
			}

	_ensure_spawn_clearing(cells, width, height)
	_ensure_terrain_presence(cells, width, height)
	return cells


static func offset_to_axial(offset: Vector2i) -> Vector2i:
	var q := offset.x
	var r := offset.y - int((offset.x - (offset.x & 1)) / 2)
	return Vector2i(q, r)


static func axial_to_offset(coord: Vector2i) -> Vector2i:
	var column := coord.x
	var row := coord.y + int((coord.x - (coord.x & 1)) / 2)
	return Vector2i(column, row)


static func neighbors(coord: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for direction in AXIAL_DIRECTIONS:
		result.append(coord + direction)
	return result


static func terrain_name(terrain: int) -> String:
	match terrain:
		Terrain.SEA:
			return "Sea"
		Terrain.PLAINS:
			return "Plains"
		Terrain.HILLS:
			return "Hills"
		Terrain.MOUNTAINS:
			return "Mountains"
		_:
			return "Unknown"


static func _terrain_from_height(value: float) -> int:
	if value < 0.40:
		return Terrain.SEA
	if value < 0.64:
		return Terrain.PLAINS
	if value < 0.78:
		return Terrain.HILLS
	return Terrain.MOUNTAINS


static func _visual_elevation(terrain: int, height_value: float) -> float:
	match terrain:
		Terrain.SEA:
			return 0.0
		Terrain.PLAINS:
			return 4.0 + clampf((height_value - 0.40) * 12.0, 0.0, 3.0)
		Terrain.HILLS:
			return 12.0 + clampf((height_value - 0.64) * 24.0, 0.0, 5.0)
		Terrain.MOUNTAINS:
			return 25.0 + clampf((height_value - 0.78) * 30.0, 0.0, 8.0)
		_:
			return 0.0


static func _ensure_spawn_clearing(cells: Dictionary, width: int, height: int) -> void:
	var center_offset := Vector2i(width / 2, height / 2)
	var center := offset_to_axial(center_offset)
	var clearing: Array[Vector2i] = [center]
	clearing.append_array(neighbors(center))

	for coord in clearing:
		if not cells.has(coord):
			continue
		var cell: Dictionary = cells[coord]
		cell["terrain"] = Terrain.PLAINS
		cell["height"] = maxf(float(cell["height"]), 0.54)
		cell["elevation_px"] = _visual_elevation(Terrain.PLAINS, float(cell["height"]))
		cells[coord] = cell


static func _ensure_terrain_presence(cells: Dictionary, width: int, height: int) -> void:
	var counts := {
		Terrain.SEA: 0,
		Terrain.PLAINS: 0,
		Terrain.HILLS: 0,
		Terrain.MOUNTAINS: 0,
	}
	for coord in cells:
		counts[int(cells[coord]["terrain"])] += 1

	var center := offset_to_axial(Vector2i(width / 2, height / 2))
	var protected: Dictionary = {center: true}
	for neighbor in neighbors(center):
		protected[neighbor] = true

	if int(counts[Terrain.MOUNTAINS]) == 0:
		var peak := _best_terrain_candidate(cells, protected, Terrain.MOUNTAINS)
		_set_terrain(cells, peak, Terrain.MOUNTAINS)
		counts[Terrain.MOUNTAINS] = 1

	if int(counts[Terrain.HILLS]) == 0:
		var hill := _best_terrain_candidate(cells, protected, Terrain.HILLS)
		_set_terrain(cells, hill, Terrain.HILLS)

	# The rim normally guarantees sea; this fallback protects tiny custom maps.
	if int(counts[Terrain.SEA]) == 0:
		var ocean := _best_terrain_candidate(cells, protected, Terrain.SEA)
		_set_terrain(cells, ocean, Terrain.SEA)


static func _best_terrain_candidate(
	cells: Dictionary, protected: Dictionary, terrain: int
) -> Vector2i:
	var best := Vector2i.ZERO
	var best_score := -INF
	for coord in cells:
		if protected.has(coord):
			continue
		var cell: Dictionary = cells[coord]
		var current_terrain := int(cell["terrain"])
		if terrain == Terrain.HILLS and current_terrain in [Terrain.SEA, Terrain.MOUNTAINS]:
			continue
		var height_value := float(cell["height"])
		var score := height_value
		if terrain == Terrain.HILLS:
			score = -absf(height_value - 0.70)
		elif terrain == Terrain.SEA:
			score = -height_value
		if score > best_score:
			best_score = score
			best = coord
	return best


static func _set_terrain(cells: Dictionary, coord: Vector2i, terrain: int) -> void:
	if not cells.has(coord):
		return
	var cell: Dictionary = cells[coord]
	cell["terrain"] = terrain
	cell["elevation_px"] = _visual_elevation(terrain, float(cell["height"]))
	cells[coord] = cell
