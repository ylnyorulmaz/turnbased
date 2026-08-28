extends SceneTree

var _failed := false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed_scene := load("res://scenes/main.tscn") as PackedScene
	_check(packed_scene != null, "main scene did not load")
	if packed_scene == null:
		quit(1)
		return

	var game := packed_scene.instantiate() as TurnBasedGame
	root.add_child(game)
	await process_frame
	await process_frame

	_check(game.hex_map.cells.size() == 18 * 13, "game created the wrong map size")
	_check(game.units.size() == 2, "game did not spawn exactly two units")
	_check(game.selected_unit != null, "game did not select the initial Settler")
	_check(not game.reachable_paths.is_empty(), "initial Settler has no reachable tile")

	if game.selected_unit != null and not game.reachable_paths.is_empty():
		var moving_unit := game.selected_unit
		var start := moving_unit.grid_coord
		var destinations := game.reachable_paths.keys()
		var destination: Vector2i = destinations[0]
		game._on_tile_clicked(destination)
		await create_timer(0.7).timeout
		_check(moving_unit.grid_coord != start, "selected unit did not move")
		_check(moving_unit.grid_coord == destination, "selected unit reached the wrong tile")
		_check(
			moving_unit.movement_left < moving_unit.movement_max,
			"movement did not spend movement points",
		)

		game._on_end_turn_pressed()
		_check(game.current_turn == 2, "end turn did not advance the turn counter")
		_check(
			moving_unit.movement_left == moving_unit.movement_max,
			"end turn did not restore movement points",
		)

	game.queue_free()
	await process_frame
	if _failed:
		quit(1)
	else:
		print("Game scene smoke test passed.")
		quit(0)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error(message)
