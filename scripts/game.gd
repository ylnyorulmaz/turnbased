class_name TurnBasedGame
extends Node2D

const MAP_WIDTH := 18
const MAP_HEIGHT := 13
const INITIAL_SEED := 42_082_026
const UNIT_SCRIPT := preload("res://scripts/procedural_unit.gd")

var units: Array[ProceduralUnit] = []
var selected_unit: ProceduralUnit = null
var reachable_paths: Dictionary = {}
var reachable_costs: Dictionary = {}
var current_turn := 1
var current_seed := INITIAL_SEED
var movement_locked := false
var randomizer := RandomNumberGenerator.new()

@onready var hex_map: HexMap = $World/HexMap
@onready var units_layer: Node2D = $World/Units
@onready var strategy_camera: StrategyCamera = $StrategyCamera

@onready var turn_label: Label = $HUD/Root/TopLeftPanel/Margin/VBox/TurnLabel
@onready var seed_label: Label = $HUD/Root/TopLeftPanel/Margin/VBox/SeedLabel
@onready var tile_info_label: Label = $HUD/Root/TileInfoPanel/Margin/TileInfoLabel
@onready var unit_name_label: Label = $HUD/Root/UnitPanel/Margin/VBox/UnitNameLabel
@onready var unit_stats_label: Label = $HUD/Root/UnitPanel/Margin/VBox/UnitStatsLabel
@onready var status_label: Label = $HUD/Root/ControlsPanel/Margin/VBox/StatusLabel
@onready var end_turn_button: Button = $HUD/Root/ControlsPanel/Margin/VBox/EndTurnButton
@onready var new_map_button: Button = $HUD/Root/ControlsPanel/Margin/VBox/NewMapButton


func _ready() -> void:
	randomizer.randomize()
	hex_map.tile_clicked.connect(_on_tile_clicked)
	hex_map.tile_hovered.connect(_on_tile_hovered)
	hex_map.selection_cancelled.connect(_clear_selection)
	end_turn_button.pressed.connect(_on_end_turn_pressed)
	new_map_button.pressed.connect(_on_new_map_pressed)
	_start_new_game(INITIAL_SEED)


func _start_new_game(seed_value: int) -> void:
	_clear_selection()
	for unit in units:
		if is_instance_valid(unit):
			unit.queue_free()
	units.clear()

	current_seed = seed_value
	current_turn = 1
	var generated_cells := MapGenerator.generate(MAP_WIDTH, MAP_HEIGHT, current_seed)
	hex_map.set_map(generated_cells, MAP_WIDTH, MAP_HEIGHT, current_seed)

	var settler_coord := hex_map.get_center_coord()
	var warrior_coord := _first_open_neighbor(settler_coord)
	var settler := _spawn_unit(ProceduralUnit.UnitKind.SETTLER, settler_coord)
	_spawn_unit(ProceduralUnit.UnitKind.WARRIOR, warrior_coord)

	_update_turn_ui()
	_set_status("Select a highlighted hex to move. Space ends the turn.")
	_select_unit(settler)
	call_deferred("_focus_camera_on_map")


func _spawn_unit(kind: int, coord: Vector2i) -> ProceduralUnit:
	var unit := UNIT_SCRIPT.new() as ProceduralUnit
	unit.configure(kind, coord, 1)
	units_layer.add_child(unit)
	unit.position = hex_map.get_unit_anchor(coord)
	_update_unit_z_index(unit)
	units.append(unit)
	return unit


func _first_open_neighbor(origin: Vector2i) -> Vector2i:
	for coord in hex_map.get_neighbors(origin):
		var terrain := int(hex_map.get_cell(coord)["terrain"])
		if terrain == MapGenerator.Terrain.PLAINS or terrain == MapGenerator.Terrain.HILLS:
			return coord
	return origin


func _on_tile_clicked(coord: Vector2i) -> void:
	if movement_locked:
		return

	var clicked_unit := _unit_at(coord)
	if clicked_unit != null:
		_select_unit(clicked_unit)
		return

	if selected_unit != null and reachable_paths.has(coord):
		_move_selected_unit(coord)
		return

	_clear_selection()
	_set_status("Select the Settler or Warrior.")


func _select_unit(unit: ProceduralUnit) -> void:
	if selected_unit != null and is_instance_valid(selected_unit):
		selected_unit.set_selected(false)
	selected_unit = unit
	selected_unit.set_selected(true)
	hex_map.set_selected_coord(unit.grid_coord)
	_refresh_reachability()
	_update_unit_ui()
	if unit.movement_left > 0:
		_set_status("%s selected. Green hexes are reachable." % unit.display_name)
	else:
		_set_status("%s has no movement left this turn." % unit.display_name)


func _clear_selection() -> void:
	if selected_unit != null and is_instance_valid(selected_unit):
		selected_unit.set_selected(false)
	selected_unit = null
	reachable_paths.clear()
	reachable_costs.clear()
	if is_instance_valid(hex_map):
		hex_map.clear_interaction_highlights()
	_update_unit_ui()


func _refresh_reachability() -> void:
	reachable_paths.clear()
	reachable_costs.clear()
	if selected_unit == null or selected_unit.movement_left <= 0:
		hex_map.set_reachable_tiles([])
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

			var cell := hex_map.get_cell(neighbor)
			var step_cost := selected_unit.movement_cost(int(cell["terrain"]))
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
	unit.spend_movement(cost)
	unit.grid_coord = destination
	hex_map.set_selected_coord(destination)
	movement_locked = true
	end_turn_button.disabled = true
	new_map_button.disabled = true

	var tween := create_tween()
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_IN_OUT)
	for step in path:
		tween.tween_property(unit, "position", hex_map.get_unit_anchor(step), 0.14)
	tween.finished.connect(_on_move_finished.bind(unit, cost))


func _on_move_finished(unit: ProceduralUnit, cost: int) -> void:
	if not is_instance_valid(unit):
		return
	_update_unit_z_index(unit)
	movement_locked = false
	end_turn_button.disabled = false
	new_map_button.disabled = false
	if selected_unit == unit:
		_refresh_reachability()
		_update_unit_ui()
	_set_status(
		"%s moved for %d movement point%s." % [unit.display_name, cost, "" if cost == 1 else "s"]
	)


func _unit_at(coord: Vector2i) -> ProceduralUnit:
	for unit in units:
		if is_instance_valid(unit) and unit.grid_coord == coord:
			return unit
	return null


func _update_unit_z_index(unit: ProceduralUnit) -> void:
	unit.z_index = clampi(int(unit.position.y) + 100, -4000, 4000)


func _on_end_turn_pressed() -> void:
	if movement_locked:
		return
	current_turn += 1
	for unit in units:
		if is_instance_valid(unit):
			unit.reset_for_new_turn()
	_clear_selection()
	_update_turn_ui()
	_set_status("Turn %d started. All movement points restored." % current_turn)


func _on_new_map_pressed() -> void:
	if movement_locked:
		return
	var next_seed := randomizer.randi_range(1, 2_000_000_000)
	_start_new_game(next_seed)
	_set_status("New procedural world generated.")


func _on_tile_hovered(coord: Vector2i, cell: Dictionary) -> void:
	if coord == HexMap.INVALID_COORD or cell.is_empty():
		tile_info_label.text = "Hover a hex to inspect terrain"
		return
	var offset := MapGenerator.axial_to_offset(coord)
	var terrain_name := MapGenerator.terrain_name(int(cell["terrain"]))
	var height_value := float(cell["height"])
	tile_info_label.text = (
		"%s  ·  tile %d,%d  ·  elevation %.2f"
		% [
			terrain_name,
			offset.x,
			offset.y,
			height_value,
		]
	)


func _update_turn_ui() -> void:
	turn_label.text = "TURN %02d" % current_turn
	seed_label.text = "WORLD SEED  %d" % current_seed


func _update_unit_ui() -> void:
	if not is_instance_valid(unit_name_label):
		return
	if selected_unit == null or not is_instance_valid(selected_unit):
		unit_name_label.text = "NO UNIT SELECTED"
		unit_stats_label.text = "Click a unit to inspect it.\nRight-click or Esc clears selection."
		return

	var cell := hex_map.get_cell(selected_unit.grid_coord)
	unit_name_label.text = selected_unit.display_name.to_upper()
	unit_stats_label.text = (
		"Movement  %d / %d\nStanding on  %s"
		% [
			selected_unit.movement_left,
			selected_unit.movement_max,
			MapGenerator.terrain_name(int(cell["terrain"])),
		]
	)


func _set_status(message: String) -> void:
	status_label.text = message


func _focus_camera_on_map() -> void:
	strategy_camera.focus_on(hex_map.get_world_bounds())


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var key_event := event as InputEventKey
		if key_event.keycode == KEY_ESCAPE:
			_clear_selection()
			_set_status("Selection cleared.")
			get_viewport().set_input_as_handled()
		elif key_event.keycode == KEY_SPACE:
			_on_end_turn_pressed()
			get_viewport().set_input_as_handled()
