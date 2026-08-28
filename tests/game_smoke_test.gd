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
	_check(game.units.size() == 4, "game did not spawn two units per faction")
	_check(game.selected_unit != null, "game did not select the initial Settler")
	_check(
		game.selected_unit.owner_id == TurnBasedGame.PLAYER_ID,
		"the initially selected unit does not belong to the player",
	)
	_check(not game.reachable_paths.is_empty(), "initial Settler has no reachable tile")
	_check(game.found_city_button.disabled == false, "initial Settler cannot found a city")

	var player_settler := game.selected_unit
	if player_settler != null and not game.reachable_paths.is_empty():
		var start := player_settler.grid_coord
		var destinations := game.reachable_paths.keys()
		var destination: Vector2i = destinations[0]
		game._on_tile_clicked(destination)
		await create_timer(0.7).timeout
		_check(player_settler.grid_coord != start, "selected Settler did not move")
		_check(player_settler.grid_coord == destination, "Settler reached the wrong tile")
		_check(
			player_settler.movement_left < player_settler.movement_max,
			"movement did not spend movement points",
		)

		game._on_found_city_pressed()
		await process_frame
		_check(game.cities.size() == 1, "player city was not created")
		_check(game.cities[0].owner_id == TurnBasedGame.PLAYER_ID, "city has the wrong owner")
		_check(
			(
				game._first_unit_for_owner(TurnBasedGame.PLAYER_ID, ProceduralUnit.UnitKind.SETTLER)
				== null
			),
			"founding did not consume the Settler",
		)

	var ai_warrior := game._first_unit_for_owner(
		TurnBasedGame.AI_ID, ProceduralUnit.UnitKind.WARRIOR
	)
	var ai_start := ai_warrior.grid_coord
	game._on_end_turn_pressed()
	_check(game.active_player_id == TurnBasedGame.AI_ID, "end turn did not start the AI phase")
	await create_timer(2.5).timeout

	_check(game.current_turn == 2, "AI phase did not advance the round counter")
	_check(
		game.active_player_id == TurnBasedGame.PLAYER_ID,
		"control did not return to the player",
	)
	_check(not game.ai_running, "AI phase did not finish")
	_check(game.cities.size() == 2, "AI Settler did not found a city")
	_check(
		game._first_unit_for_owner(TurnBasedGame.AI_ID, ProceduralUnit.UnitKind.SETTLER) == null,
		"AI founding did not consume its Settler",
	)
	_check(ai_warrior.grid_coord != ai_start, "AI Warrior did not advance")

	var player_warrior := game._first_unit_for_owner(
		TurnBasedGame.PLAYER_ID, ProceduralUnit.UnitKind.WARRIOR
	)
	_check(player_warrior != null, "player Warrior disappeared")
	if player_warrior != null:
		_check(
			player_warrior.movement_left == player_warrior.movement_max,
			"player movement was not restored after the AI phase",
		)
		var attack_coord := HexMap.INVALID_COORD
		for neighbor in game.hex_map.get_neighbors(player_warrior.grid_coord):
			if (
				game._unit_at(neighbor) == null
				and game._city_at(neighbor) == null
				and ai_warrior.movement_cost(int(game.hex_map.get_cell(neighbor)["terrain"])) >= 0
			):
				attack_coord = neighbor
				break
		_check(attack_coord != HexMap.INVALID_COORD, "no valid adjacent combat tile found")
		if attack_coord != HexMap.INVALID_COORD:
			ai_warrior.grid_coord = attack_coord
			ai_warrior.position = game.hex_map.get_unit_anchor(attack_coord)
			game._update_unit_z_index(ai_warrior)
			game._select_unit(player_warrior)
			_check(game.attack_targets.has(attack_coord), "adjacent enemy was not attackable")
			var health_before := ai_warrior.health
			game._on_tile_clicked(attack_coord)
			await create_timer(0.6).timeout
			_check(ai_warrior.health == health_before - 1, "Warrior attack dealt no damage")
			_check(
				player_warrior.movement_left == player_warrior.movement_max - 1,
				"Warrior attack spent the wrong movement amount",
			)
			var player_health_before := player_warrior.health
			game._on_end_turn_pressed()
			await create_timer(1.5).timeout
			_check(
				player_warrior.health == player_health_before - 1,
				"adjacent AI Warrior did not attack during its phase",
			)
			_check(game.current_turn == 3, "second AI phase did not complete")

	game.queue_free()
	await process_frame
	if _failed:
		quit(1)
	else:
		print("Game, city founding, AI turn, and combat smoke test passed.")
		quit(0)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error(message)
