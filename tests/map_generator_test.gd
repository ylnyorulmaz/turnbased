extends SceneTree

const GENERATOR := preload("res://scripts/map_generator.gd")
const WIDTH := 18
const HEIGHT := 13

var _failed := false


func _init() -> void:
	var seeds := [1, 42_082_026, 987_654_321]
	for map_seed in seeds:
		_validate_seed(map_seed)

	if _failed:
		quit(1)
	else:
		print("Map generator smoke tests passed for %d seeds." % seeds.size())
		quit(0)


func _validate_seed(map_seed: int) -> void:
	var cells: Dictionary = GENERATOR.generate(WIDTH, HEIGHT, map_seed)
	_check(cells.size() == WIDTH * HEIGHT, "seed %d returned the wrong cell count" % map_seed)

	var terrain_counts := {
		GENERATOR.Terrain.SEA: 0,
		GENERATOR.Terrain.PLAINS: 0,
		GENERATOR.Terrain.HILLS: 0,
		GENERATOR.Terrain.MOUNTAINS: 0,
	}
	for coord in cells:
		var terrain := int(cells[coord]["terrain"])
		terrain_counts[terrain] += 1

	for terrain in terrain_counts:
		_check(
			int(terrain_counts[terrain]) > 0,
			"seed %d did not generate %s" % [map_seed, GENERATOR.terrain_name(terrain)]
		)

	var center := GENERATOR.offset_to_axial(Vector2i(WIDTH / 2, HEIGHT / 2))
	_check(cells.has(center), "seed %d has no center cell" % map_seed)
	_check(
		int(cells[center]["terrain"]) == GENERATOR.Terrain.PLAINS,
		"seed %d center spawn is not plains" % map_seed
	)

	for neighbor in GENERATOR.neighbors(center):
		if not cells.has(neighbor):
			continue
		_check(
			GENERATOR.neighbors(neighbor).has(center),
			"seed %d produced a non-reciprocal neighbor" % map_seed
		)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error(message)
