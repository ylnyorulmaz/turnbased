class_name TurnBasedGame
extends Node2D

const PLAYER_ID := 1
const AI_ID := 2
const MAP_WIDTH := 18
const MAP_HEIGHT := 13
const INITIAL_SEED := 42_082_026
const MIN_CITY_DISTANCE := 3
const UNIT_SCRIPT := preload("res://scripts/procedural_unit.gd")
const CITY_SCRIPT := preload("res://scripts/procedural_city.gd")
const EFFECT_SCRIPT := preload("res://scripts/procedural_effect.gd")
const PLAYER_CITY_NAMES := ["Haven", "Aurora", "Stonegate", "Greenwatch"]
const AI_CITY_NAMES := ["Ashen Hold", "Red Spire", "Iron Hollow", "Emberfall"]

var units: Array[ProceduralUnit] = []
var cities: Array[ProceduralCity] = []
var selected_unit: ProceduralUnit = null
var reachable_paths: Dictionary = {}
var reachable_costs: Dictionary = {}
var attack_targets: Dictionary = {}
var current_turn := 1
var current_seed := INITIAL_SEED
var active_player_id := PLAYER_ID
var movement_locked := false
var ai_running := false
var randomizer := RandomNumberGenerator.new()
var _turn_banner_tween: Tween = null

@onready var hex_map: HexMap = $World/HexMap
@onready var cities_layer: Node2D = $World/Cities
@onready var units_layer: Node2D = $World/Units
@onready var effects_layer: Node2D = $World/Effects
@onready var strategy_camera: StrategyCamera = $StrategyCamera

@onready var turn_label: Label = $HUD/Root/TopLeftPanel/Margin/VBox/TurnLabel
@onready var seed_label: Label = $HUD/Root/TopLeftPanel/Margin/VBox/SeedLabel
@onready var tile_info_label: Label = $HUD/Root/TileInfoPanel/Margin/TileInfoLabel
@onready var unit_name_label: Label = $HUD/Root/UnitPanel/Margin/VBox/UnitNameLabel
@onready var unit_stats_label: Label = $HUD/Root/UnitPanel/Margin/VBox/UnitStatsLabel
@onready var status_label: Label = $HUD/Root/ControlsPanel/Margin/VBox/StatusLabel
@onready var found_city_button: Button = $HUD/Root/ControlsPanel/Margin/VBox/FoundCityButton
@onready var end_turn_button: Button = $HUD/Root/ControlsPanel/Margin/VBox/EndTurnButton
@onready var new_map_button: Button = $HUD/Root/ControlsPanel/Margin/VBox/NewMapButton
@onready var turn_banner: PanelContainer = $HUD/Root/TurnBanner
@onready var turn_banner_label: Label = $HUD/Root/TurnBanner/Margin/Label


func _ready() -> void:
	randomizer.randomize()
	hex_map.tile_clicked.connect(_on_tile_clicked)
	hex_map.tile_hovered.connect(_on_tile_hovered)
	hex_map.selection_cancelled.connect(_clear_selection)
	found_city_button.pressed.connect(_on_found_city_pressed)
	end_turn_button.pressed.connect(_on_end_turn_pressed)
	new_map_button.pressed.connect(_on_new_map_pressed)
	_start_new_game(INITIAL_SEED)


func _start_new_game(seed_value: int) -> void:
	_clear_selection()
	for unit in units:
		if is_instance_valid(unit):
			unit.queue_free()
	for city in cities:
		if is_instance_valid(city):
			city.queue_free()
	units.clear()
	cities.clear()
	for effect in effects_layer.get_children():
		effect.queue_free()

	current_seed = seed_value
	current_turn = 1
	active_player_id = PLAYER_ID
	movement_locked = false
	ai_running = false
	var generated_cells := MapGenerator.generate(MAP_WIDTH, MAP_HEIGHT, current_seed)
	hex_map.set_map(generated_cells, MAP_WIDTH, MAP_HEIGHT, current_seed)

	var player_settler_coord := hex_map.get_center_coord()
	var player_warrior_coord := _first_open_neighbor(player_settler_coord)
	var player_settler := _spawn_unit(
		ProceduralUnit.UnitKind.SETTLER, player_settler_coord, PLAYER_ID
	)
	_spawn_unit(ProceduralUnit.UnitKind.WARRIOR, player_warrior_coord, PLAYER_ID)

	var ai_settler_coord := _find_ai_spawn_coord(player_settler_coord)
	_spawn_unit(ProceduralUnit.UnitKind.SETTLER, ai_settler_coord, AI_ID)
	var ai_warrior_coord := _first_open_neighbor(ai_settler_coord)
	_spawn_unit(ProceduralUnit.UnitKind.WARRIOR, ai_warrior_coord, AI_ID)

	_update_turn_ui()
	_set_controls_locked(false)
	_set_status("Your turn. Found a city or move a unit; Space ends the turn.")
	_select_unit(player_settler)
	_show_turn_banner("PLAYER TURN", Color("43d9b5"))
	call_deferred("_focus_camera_on_map")


func _spawn_unit(kind: int, coord: Vector2i, owner_id: int) -> ProceduralUnit:
	var unit := UNIT_SCRIPT.new() as ProceduralUnit
	unit.configure(kind, coord, owner_id)
	units_layer.add_child(unit)
	unit.position = hex_map.get_unit_anchor(coord)
	_update_unit_z_index(unit)
	units.append(unit)
	return unit


func _spawn_city(coord: Vector2i, owner_id: int) -> ProceduralCity:
	var city := CITY_SCRIPT.new() as ProceduralCity
	city.configure(coord, owner_id, _next_city_name(owner_id))
	cities_layer.add_child(city)
	city.position = hex_map.get_unit_anchor(coord) + Vector2(0.0, 1.0)
	city.z_index = clampi(int(city.position.y) + 50, -4000, 4000)
	cities.append(city)
	return city


func _next_city_name(owner_id: int) -> String:
	var owned_count := 0
	for city in cities:
		if is_instance_valid(city) and city.owner_id == owner_id:
			owned_count += 1
	var names := PLAYER_CITY_NAMES if owner_id == PLAYER_ID else AI_CITY_NAMES
	return names[owned_count % names.size()]


func _first_open_neighbor(origin: Vector2i) -> Vector2i:
	for coord in hex_map.get_neighbors(origin):
		var terrain := int(hex_map.get_cell(coord)["terrain"])
		if (
			terrain in [MapGenerator.Terrain.PLAINS, MapGenerator.Terrain.HILLS]
			and _unit_at(coord) == null
		):
			return coord
	for coord in hex_map.cells:
		var terrain := int(hex_map.get_cell(coord)["terrain"])
		if (
			terrain in [MapGenerator.Terrain.PLAINS, MapGenerator.Terrain.HILLS]
			and _unit_at(coord) == null
		):
			return coord
	return origin


func _find_ai_spawn_coord(player_coord: Vector2i) -> Vector2i:
	var best_coord := HexMap.INVALID_COORD
	var best_score := -INF
	var fallback_coord := HexMap.INVALID_COORD
	var fallback_score := -INF
	for coord in hex_map.cells:
		var cell := hex_map.get_cell(coord)
		var terrain := int(cell["terrain"])
		if terrain not in [MapGenerator.Terrain.PLAINS, MapGenerator.Terrain.HILLS]:
			continue
		if _unit_at(coord) != null:
			continue
		var distance := _hex_distance(coord, player_coord)
		var open_neighbors := 0
		for neighbor in hex_map.get_neighbors(coord):
			if int(hex_map.get_cell(neighbor)["terrain"]) != MapGenerator.Terrain.SEA:
				open_neighbors += 1
		var score := float(distance * 10 + open_neighbors * 3) + float(cell["moisture"])
		if score > fallback_score:
			fallback_score = score
			fallback_coord = coord
		if distance < 6:
			continue
		if score > best_score:
			best_score = score
			best_coord = coord
	return fallback_coord if best_coord == HexMap.INVALID_COORD else best_coord


func _on_tile_clicked(coord: Vector2i) -> void:
	if movement_locked or ai_running or active_player_id != PLAYER_ID:
		return

	var clicked_unit := _unit_at(coord)
	if clicked_unit != null:
		if clicked_unit.owner_id == PLAYER_ID:
			_select_unit(clicked_unit)
		elif selected_unit != null and attack_targets.has(coord):
			_player_attack(clicked_unit)
		else:
			_set_status(
				"Enemy %s. Move a Warrior next to it to attack." % clicked_unit.display_name
			)
		return

	if selected_unit != null and reachable_paths.has(coord):
		_move_selected_unit(coord)
		return

	var city := _city_at(coord)
	if city != null:
		var faction := "Your" if city.owner_id == PLAYER_ID else "Enemy"
		_set_status("%s city: %s." % [faction, city.city_name])
		return

	_clear_selection()
	_set_status("Select one of your cyan units.")


func _select_unit(unit: ProceduralUnit) -> void:
	if unit == null or unit.owner_id != PLAYER_ID or active_player_id != PLAYER_ID or ai_running:
		return
	if selected_unit != null and is_instance_valid(selected_unit):
		selected_unit.set_selected(false)
	selected_unit = unit
	selected_unit.set_selected(true)
	hex_map.set_selected_coord(unit.grid_coord)
	_refresh_reachability()
	_update_unit_ui()
	if _can_found_city(unit):
		_set_status("Settler selected. Found a city here or move to a green hex.")
	elif unit.movement_left > 0:
		_set_status("%s selected. Green: move; red: attack." % unit.display_name)
	else:
		_set_status("%s has no movement left this round." % unit.display_name)


func _clear_selection() -> void:
	if selected_unit != null and is_instance_valid(selected_unit):
		selected_unit.set_selected(false)
	selected_unit = null
	reachable_paths.clear()
	reachable_costs.clear()
	attack_targets.clear()
	if is_instance_valid(hex_map):
		hex_map.clear_interaction_highlights()
	_update_unit_ui()
	_update_found_city_button()


func _refresh_reachability() -> void:
	reachable_paths.clear()
	reachable_costs.clear()
	attack_targets.clear()
	hex_map.set_reachable_tiles([])
	hex_map.set_attack_tiles([])
	if selected_unit == null:
		_update_found_city_button()
		return

	if selected_unit.can_attack():
		for neighbor in hex_map.get_neighbors(selected_unit.grid_coord):
			var enemy := _unit_at(neighbor)
			if enemy != null and enemy.owner_id != selected_unit.owner_id:
				attack_targets[neighbor] = enemy
	hex_map.set_attack_tiles(attack_targets.keys())

	if selected_unit.movement_left <= 0:
		_update_found_city_button()
		return

	var start := selected_unit.grid_coord
	var frontier: Array[Vector2i] = [start]
	var costs: Dictionary = {start: 0}
	var previous: Dictionary = {}

	while not frontier.is_empty():
		var current := _lowest_cost_coord(frontier, costs)
		frontier.erase(current)
		for neighbor in hex_map.get_neighbors(current):
			var occupant := _unit_at(neighbor)
			if occupant != null and occupant != selected_unit:
				continue

			var step_cost := selected_unit.movement_cost(int(hex_map.get_cell(neighbor)["terrain"]))
			if step_cost < 0:
				continue
			var new_cost := int(costs[current]) + step_cost
			if new_cost > selected_unit.movement_left:
				continue
			if not costs.has(neighbor) or new_cost < int(costs[neighbor]):
				costs[neighbor] = new_cost
				previous[neighbor] = current
				if not frontier.has(neighbor):
					frontier.append(neighbor)

	for destination in costs:
		if destination == start:
			continue
		var path: Array[Vector2i] = []
		var cursor: Vector2i = destination
		while cursor != start:
			path.push_front(cursor)
			cursor = previous[cursor]
		reachable_paths[destination] = path
		reachable_costs[destination] = costs[destination]

	hex_map.set_reachable_tiles(reachable_paths.keys())
	_update_found_city_button()


func _lowest_cost_coord(frontier: Array[Vector2i], costs: Dictionary) -> Vector2i:
	var best := frontier[0]
	var best_cost := int(costs[best])
	for coord in frontier:
		var candidate_cost := int(costs[coord])
		if candidate_cost < best_cost:
			best = coord
			best_cost = candidate_cost
	return best


func _move_selected_unit(destination: Vector2i) -> void:
	var unit := selected_unit
	var path: Array = reachable_paths[destination]
	var cost := int(reachable_costs[destination])
	movement_locked = true
	_set_controls_locked(true)
	hex_map.set_selected_coord(destination)
	await _animate_unit_path(unit, path, cost)
	movement_locked = false
	_set_controls_locked(false)
	if selected_unit == unit:
		_refresh_reachability()
		_update_unit_ui()
	_set_status(
		"%s moved for %d movement point%s." % [unit.display_name, cost, "" if cost == 1 else "s"]
	)


func _animate_unit_path(unit: ProceduralUnit, path: Array, cost: int) -> void:
	if path.is_empty() or not is_instance_valid(unit):
		return
	unit.spend_movement(cost)
	_spawn_effect(ProceduralEffect.EffectKind.MOVE_DUST, unit.position, unit.team_color)
	unit.grid_coord = path.back()
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_IN_OUT)
	for step in path:
		tween.tween_property(unit, "position", hex_map.get_unit_anchor(step), 0.14)
	await tween.finished
	if is_instance_valid(unit):
		_update_unit_z_index(unit)
		_spawn_effect(ProceduralEffect.EffectKind.MOVE_DUST, unit.position, unit.team_color)


func _player_attack(target: ProceduralUnit) -> void:
	if selected_unit == null or not attack_targets.has(target.grid_coord):
		return
	var attacker := selected_unit
	movement_locked = true
	_set_controls_locked(true)
	var defeated := await _perform_attack(attacker, target)
	movement_locked = false
	_set_controls_locked(false)
	if defeated:
		_set_status("Enemy %s defeated." % target.display_name)
	else:
		_set_status("Enemy %s now has %d health." % [target.display_name, target.health])
	if selected_unit == attacker and is_instance_valid(attacker):
		_refresh_reachability()
		_update_unit_ui()


func _perform_attack(attacker: ProceduralUnit, target: ProceduralUnit) -> bool:
	if (
		not is_instance_valid(attacker)
		or not is_instance_valid(target)
		or not attacker.can_attack()
	):
		return false
	attacker.spend_movement(1)
	var origin := attacker.position
	var strike_position := origin.lerp(target.position, 0.34)
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_QUAD)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(attacker, "position", strike_position, 0.10)
	tween.tween_property(attacker, "position", origin, 0.13)
	await tween.finished
	var strike_direction := target.position - attacker.position
	_spawn_effect(
		ProceduralEffect.EffectKind.IMPACT,
		target.position + Vector2(0.0, -18.0),
		attacker.team_color,
		strike_direction,
	)
	_spawn_effect(
		ProceduralEffect.EffectKind.DAMAGE_TEXT,
		target.position,
		Color("ff8b70"),
		Vector2.ZERO,
		"-%d" % attacker.attack_damage,
	)
	strategy_camera.kick_shake(5.5)
	var defeated := target.take_damage(attacker.attack_damage)
	if defeated:
		_remove_unit(target)
	return defeated


func _remove_unit(unit: ProceduralUnit) -> void:
	if unit == null:
		return
	if selected_unit == unit:
		_clear_selection()
	units.erase(unit)
	if is_instance_valid(unit):
		unit.queue_free()


func _on_found_city_pressed() -> void:
	if selected_unit == null or not _can_found_city(selected_unit):
		_set_status("A Settler can found only on valid Plains or Hills.")
		return
	var settler := selected_unit
	var city := _found_city(settler)
	_set_status("%s founded. The Settler was consumed." % city.city_name)
	var next_unit := _first_unit_for_owner(PLAYER_ID)
	if next_unit != null:
		_select_unit(next_unit)


func _found_city(settler: ProceduralUnit) -> ProceduralCity:
	var city := _spawn_city(settler.grid_coord, settler.owner_id)
	_spawn_effect(ProceduralEffect.EffectKind.CITY_BURST, city.position, city.team_color)
	strategy_camera.kick_shake(2.6)
	_remove_unit(settler)
	return city


func _can_found_city(settler: ProceduralUnit) -> bool:
	return (
		is_instance_valid(settler)
		and settler.unit_kind == ProceduralUnit.UnitKind.SETTLER
		and _can_found_city_at(settler.grid_coord)
	)


func _can_found_city_at(coord: Vector2i) -> bool:
	if not hex_map.has_cell(coord) or _city_at(coord) != null:
		return false
	var terrain := int(hex_map.get_cell(coord)["terrain"])
	if terrain not in [MapGenerator.Terrain.PLAINS, MapGenerator.Terrain.HILLS]:
		return false
	for city in cities:
		if is_instance_valid(city) and _hex_distance(coord, city.grid_coord) < MIN_CITY_DISTANCE:
			return false
	return true


func _on_end_turn_pressed() -> void:
	if movement_locked or ai_running or active_player_id != PLAYER_ID:
		return
	_clear_selection()
	active_player_id = AI_ID
	ai_running = true
	movement_locked = true
	for unit in units:
		if is_instance_valid(unit) and unit.owner_id == AI_ID:
			unit.reset_for_new_turn()
	_update_turn_ui()
	_set_controls_locked(true)
	_set_status("AI turn: the red faction is acting...")
	_show_turn_banner("AI TURN", Color("ef735c"))
	_run_ai_turn()


func _run_ai_turn() -> void:
	await get_tree().create_timer(0.25).timeout
	var ai_settler := _first_unit_for_owner(AI_ID, ProceduralUnit.UnitKind.SETTLER)
	if ai_settler != null and is_instance_valid(ai_settler):
		if _can_found_city(ai_settler):
			var ai_city := _found_city(ai_settler)
			_set_status("AI founded %s." % ai_city.city_name)
			await get_tree().create_timer(0.30).timeout
		else:
			await _run_ai_settler(ai_settler)

	var ai_warriors: Array[ProceduralUnit] = []
	for unit in units:
		if (
			is_instance_valid(unit)
			and unit.owner_id == AI_ID
			and unit.unit_kind == ProceduralUnit.UnitKind.WARRIOR
		):
			ai_warriors.append(unit)
	for warrior in ai_warriors:
		if is_instance_valid(warrior):
			await _run_ai_warrior(warrior)

	await get_tree().create_timer(0.25).timeout
	_start_player_turn()


func _run_ai_settler(settler: ProceduralUnit) -> void:
	var city_site := _best_city_site(settler)
	if city_site == HexMap.INVALID_COORD:
		return
	var path := _find_path_to_exact(settler, city_site)
	var budget := _path_within_budget(settler, path)
	var move_path: Array = budget["path"]
	var move_cost := int(budget["cost"])
	if not move_path.is_empty():
		await _animate_unit_path(settler, move_path, move_cost)
		await get_tree().create_timer(0.18).timeout
	if is_instance_valid(settler) and _can_found_city(settler):
		var city := _found_city(settler)
		_set_status("AI founded %s." % city.city_name)


func _run_ai_warrior(warrior: ProceduralUnit) -> void:
	var target_unit := _nearest_unit_for_owner(warrior.grid_coord, PLAYER_ID)
	var target_coord := HexMap.INVALID_COORD
	if target_unit != null:
		target_coord = target_unit.grid_coord
	else:
		var target_city := _nearest_city_for_owner(warrior.grid_coord, PLAYER_ID)
		if target_city != null:
			target_coord = target_city.grid_coord
	if target_coord == HexMap.INVALID_COORD:
		return

	if target_unit != null and _hex_distance(warrior.grid_coord, target_coord) == 1:
		_set_status("AI Warrior attacks your %s." % target_unit.display_name)
		await _perform_attack(warrior, target_unit)
		await get_tree().create_timer(0.22).timeout
		return

	var path := _find_path_to_adjacent(warrior, target_coord)
	var budget := _path_within_budget(warrior, path)
	var move_path: Array = budget["path"]
	var move_cost := int(budget["cost"])
	if not move_path.is_empty():
		_set_status("AI Warrior advances toward your territory.")
		await _animate_unit_path(warrior, move_path, move_cost)
		await get_tree().create_timer(0.16).timeout

	if (
		target_unit != null
		and is_instance_valid(target_unit)
		and warrior.can_attack()
		and _hex_distance(warrior.grid_coord, target_unit.grid_coord) == 1
	):
		_set_status("AI Warrior attacks your %s." % target_unit.display_name)
		await _perform_attack(warrior, target_unit)
		await get_tree().create_timer(0.22).timeout


func _start_player_turn() -> void:
	active_player_id = PLAYER_ID
	current_turn += 1
	ai_running = false
	movement_locked = false
	for unit in units:
		if is_instance_valid(unit) and unit.owner_id == PLAYER_ID:
			unit.reset_for_new_turn()
	_update_turn_ui()
	_set_controls_locked(false)
	_set_status("Round %d: your units are ready." % current_turn)
	_show_turn_banner("ROUND %02d  ·  PLAYER" % current_turn, Color("43d9b5"))
	var first_player_unit := _first_unit_for_owner(PLAYER_ID)
	if first_player_unit != null:
		_select_unit(first_player_unit)


func _best_city_site(settler: ProceduralUnit) -> Vector2i:
	var best_coord := HexMap.INVALID_COORD
	var best_score := -INF
	for coord in hex_map.cells:
		if not _can_found_city_at(coord) or _unit_at(coord) != null:
			continue
		var land_neighbors := 0
		for neighbor in hex_map.get_neighbors(coord):
			if int(hex_map.get_cell(neighbor)["terrain"]) != MapGenerator.Terrain.SEA:
				land_neighbors += 1
		var distance := _hex_distance(settler.grid_coord, coord)
		var moisture := float(hex_map.get_cell(coord)["moisture"])
		var score := float(land_neighbors * 3 - distance * 2) + moisture
		if score > best_score:
			best_score = score
			best_coord = coord
	return best_coord


func _find_path_to_exact(unit: ProceduralUnit, destination: Vector2i) -> Array[Vector2i]:
	var goals: Dictionary = {destination: true}
	return _find_path_to_any(unit, goals)


func _find_path_to_adjacent(unit: ProceduralUnit, target: Vector2i) -> Array[Vector2i]:
	var goals: Dictionary = {}
	for neighbor in hex_map.get_neighbors(target):
		if (
			_unit_at(neighbor) == null
			and unit.movement_cost(int(hex_map.get_cell(neighbor)["terrain"])) >= 0
		):
			goals[neighbor] = true
	return _find_path_to_any(unit, goals)


func _find_path_to_any(unit: ProceduralUnit, goals: Dictionary) -> Array[Vector2i]:
	var empty_path: Array[Vector2i] = []
	if goals.is_empty() or goals.has(unit.grid_coord):
		return empty_path
	var start := unit.grid_coord
	var frontier: Array[Vector2i] = [start]
	var costs: Dictionary = {start: 0}
	var previous: Dictionary = {}
	var goal := HexMap.INVALID_COORD

	while not frontier.is_empty():
		var current := _lowest_cost_coord(frontier, costs)
		frontier.erase(current)
		if goals.has(current):
			goal = current
			break
		for neighbor in hex_map.get_neighbors(current):
			var occupant := _unit_at(neighbor)
			if occupant != null and occupant != unit:
				continue
			var step_cost := unit.movement_cost(int(hex_map.get_cell(neighbor)["terrain"]))
			if step_cost < 0:
				continue
			var new_cost := int(costs[current]) + step_cost
			if not costs.has(neighbor) or new_cost < int(costs[neighbor]):
				costs[neighbor] = new_cost
				previous[neighbor] = current
				if not frontier.has(neighbor):
					frontier.append(neighbor)

	if goal == HexMap.INVALID_COORD:
		return empty_path
	var path: Array[Vector2i] = []
	var cursor := goal
	while cursor != start:
		path.push_front(cursor)
		cursor = previous[cursor]
	return path


func _path_within_budget(unit: ProceduralUnit, full_path: Array[Vector2i]) -> Dictionary:
	var path: Array[Vector2i] = []
	var total_cost := 0
	for step in full_path:
		var step_cost := unit.movement_cost(int(hex_map.get_cell(step)["terrain"]))
		if step_cost < 0 or total_cost + step_cost > unit.movement_left:
			break
		total_cost += step_cost
		path.append(step)
	return {"path": path, "cost": total_cost}


func _unit_at(coord: Vector2i) -> ProceduralUnit:
	for unit in units:
		if is_instance_valid(unit) and unit.grid_coord == coord:
			return unit
	return null


func _city_at(coord: Vector2i) -> ProceduralCity:
	for city in cities:
		if is_instance_valid(city) and city.grid_coord == coord:
			return city
	return null


func _first_unit_for_owner(owner_id: int, kind: int = -1) -> ProceduralUnit:
	for unit in units:
		if (
			is_instance_valid(unit)
			and unit.owner_id == owner_id
			and (kind < 0 or unit.unit_kind == kind)
		):
			return unit
	return null


func _nearest_unit_for_owner(origin: Vector2i, owner_id: int) -> ProceduralUnit:
	var nearest: ProceduralUnit = null
	var nearest_distance := 1_000_000
	for unit in units:
		if not is_instance_valid(unit) or unit.owner_id != owner_id:
			continue
		var distance := _hex_distance(origin, unit.grid_coord)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest = unit
	return nearest


func _nearest_city_for_owner(origin: Vector2i, owner_id: int) -> ProceduralCity:
	var nearest: ProceduralCity = null
	var nearest_distance := 1_000_000
	for city in cities:
		if not is_instance_valid(city) or city.owner_id != owner_id:
			continue
		var distance := _hex_distance(origin, city.grid_coord)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest = city
	return nearest


func _update_unit_z_index(unit: ProceduralUnit) -> void:
	unit.z_index = clampi(int(unit.position.y) + 100, -4000, 4000)


func _on_new_map_pressed() -> void:
	if movement_locked or ai_running:
		return
	var next_seed := randomizer.randi_range(1, 2_000_000_000)
	_start_new_game(next_seed)
	_set_status("New procedural world generated.")


func _on_tile_hovered(coord: Vector2i, cell: Dictionary) -> void:
	if selected_unit != null and reachable_paths.has(coord):
		hex_map.set_preview_path(reachable_paths[coord])
	else:
		hex_map.set_preview_path([])
	if coord == HexMap.INVALID_COORD or cell.is_empty():
		tile_info_label.text = "Hover a hex to inspect terrain"
		return
	var offset := MapGenerator.axial_to_offset(coord)
	var terrain_name := MapGenerator.terrain_name(int(cell["terrain"]))
	var height_value := float(cell["height"])
	var detail := ""
	var unit := _unit_at(coord)
	var city := _city_at(coord)
	if unit != null:
		detail = " · %s %s" % ["Your" if unit.owner_id == PLAYER_ID else "AI", unit.display_name]
	if city != null:
		detail += " · %s" % city.city_name
	tile_info_label.text = (
		"%s  ·  tile %d,%d  ·  elevation %.2f%s"
		% [terrain_name, offset.x, offset.y, height_value, detail]
	)


func _update_turn_ui() -> void:
	var faction := "PLAYER" if active_player_id == PLAYER_ID else "AI"
	turn_label.text = "ROUND %02d · %s" % [current_turn, faction]
	turn_label.add_theme_color_override(
		"font_color", Color("f2c64f") if active_player_id == PLAYER_ID else Color("ef735c")
	)
	seed_label.text = "WORLD SEED  %d" % current_seed
	end_turn_button.text = "▶  END PLAYER TURN  [SPACE]" if not ai_running else "◆  AI TURN..."


func _update_unit_ui() -> void:
	if not is_instance_valid(unit_name_label):
		return
	if selected_unit == null or not is_instance_valid(selected_unit):
		unit_name_label.text = "NO UNIT SELECTED"
		unit_stats_label.text = "Click a cyan unit to inspect it.\nRight-click or Esc clears selection."
		return

	var cell := hex_map.get_cell(selected_unit.grid_coord)
	unit_name_label.text = selected_unit.display_name.to_upper()
	unit_stats_label.text = (
		"Health  %d / %d    ·    Movement  %d / %d\nStanding on  %s"
		% [
			selected_unit.health,
			selected_unit.health_max,
			selected_unit.movement_left,
			selected_unit.movement_max,
			MapGenerator.terrain_name(int(cell["terrain"])),
		]
	)


func _update_found_city_button() -> void:
	if not is_instance_valid(found_city_button):
		return
	found_city_button.disabled = (
		movement_locked
		or ai_running
		or active_player_id != PLAYER_ID
		or selected_unit == null
		or not _can_found_city(selected_unit)
	)


func _set_controls_locked(value: bool) -> void:
	if not is_instance_valid(end_turn_button):
		return
	end_turn_button.disabled = value or active_player_id != PLAYER_ID
	new_map_button.disabled = value
	_update_found_city_button()


func _set_status(message: String) -> void:
	status_label.text = message
	status_label.modulate = Color(1.18, 1.18, 1.18, 1.0)
	var tween := create_tween()
	tween.tween_property(status_label, "modulate", Color.WHITE, 0.22)


func _spawn_effect(
	kind: int,
	world_position: Vector2,
	color_value: Color,
	direction: Vector2 = Vector2.RIGHT,
	text_value: String = "",
) -> ProceduralEffect:
	var effect := EFFECT_SCRIPT.new() as ProceduralEffect
	effects_layer.add_child(effect)
	effect.position = world_position
	effect.configure(kind, color_value, direction, text_value)
	return effect


func _show_turn_banner(message: String, color_value: Color) -> void:
	if not is_instance_valid(turn_banner):
		return
	if _turn_banner_tween != null and _turn_banner_tween.is_valid():
		_turn_banner_tween.kill()
	turn_banner.visible = true
	turn_banner_label.text = message
	turn_banner_label.add_theme_color_override("font_color", color_value.lightened(0.18))
	turn_banner.modulate = Color(1.0, 1.0, 1.0, 0.0)
	turn_banner.scale = Vector2(0.88, 0.88)
	turn_banner.pivot_offset = turn_banner.size * 0.5
	_turn_banner_tween = create_tween()
	_turn_banner_tween.set_trans(Tween.TRANS_BACK)
	_turn_banner_tween.set_ease(Tween.EASE_OUT)
	_turn_banner_tween.tween_property(turn_banner, "modulate:a", 1.0, 0.18)
	_turn_banner_tween.parallel().tween_property(turn_banner, "scale", Vector2.ONE, 0.24)
	_turn_banner_tween.tween_interval(0.72)
	_turn_banner_tween.set_trans(Tween.TRANS_SINE)
	_turn_banner_tween.tween_property(turn_banner, "modulate:a", 0.0, 0.30)
	_turn_banner_tween.tween_callback(turn_banner.hide)


func _focus_camera_on_map() -> void:
	strategy_camera.focus_on(hex_map.get_world_bounds())


func _hex_distance(a: Vector2i, b: Vector2i) -> int:
	var delta_q := a.x - b.x
	var delta_r := a.y - b.y
	var delta_s := -a.x - a.y - (-b.x - b.y)
	return int((abs(delta_q) + abs(delta_r) + abs(delta_s)) / 2)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var key_event := event as InputEventKey
		if key_event.keycode == KEY_ESCAPE and active_player_id == PLAYER_ID:
			_clear_selection()
			_set_status("Selection cleared.")
			get_viewport().set_input_as_handled()
		elif key_event.keycode == KEY_C and active_player_id == PLAYER_ID:
			_on_found_city_pressed()
			get_viewport().set_input_as_handled()
		elif key_event.keycode == KEY_SPACE and active_player_id == PLAYER_ID:
			_on_end_turn_pressed()
			get_viewport().set_input_as_handled()
