@tool
extends Node2D
class_name TileMapper

enum CellDrawState {
	CANVAS_ITEM,
	QUADRANT,
	NONE
}

@export var tile_set: TileSet:
	set = set_tileset,
	get = get_tileset
@export var quadrant_size: int = 64:
	set = set_quadrant_size,
	get = get_quadrant_size
@export var collision_type: PhysicsServer2D.BodyMode = PhysicsServer2D.BODY_MODE_STATIC:
	set = set_collision_type,
	get = get_collision_type
@export_enum("Default", "Force Show", "Force Hide") var collision_visibility: int = 0:
	set = set_collision_visibility,
	get = get_collision_visibility

var _tiles: Array[MapperCellData] = []
var _quadrants: Array[Quadrant]
var _current_quadrant: Quadrant


func _set_cell_to_use_canvas_item(cell_data: MapperCellData) -> void:
	cell_data.canvas_rid = RenderingServer.canvas_item_create()
	cell_data.current_quadrant.cells.erase(cell_data)
	_draw_quadrant(cell_data.current_quadrant)
	cell_data.current_quadrant = null
	_draw_tile(cell_data)
	_update_canvas_item_cell(cell_data)


func _set_cell_to_use_quadrant(cell_data: MapperCellData, quadrant: Quadrant) -> void:
	RenderingServer.free_rid(cell_data.canvas_rid)
	cell_data.canvas_rid = RID()
	quadrant.cells.append(cell_data)
	_draw_quadrant_cell(cell_data, quadrant)


func _set_cell_transform(cell_data: MapperCellData, new_transform: Transform2D) -> void:
	cell_data.transform = new_transform

	match _get_cell_draw_state(cell_data):
		CellDrawState.CANVAS_ITEM:
			RenderingServer.canvas_item_set_transform(cell_data.canvas_rid, cell_data.transform)
		CellDrawState.QUADRANT:
			_draw_quadrant(cell_data.current_quadrant)

	for body in cell_data.physics_bodies_rid:
		PhysicsServer2D.body_set_state(body, PhysicsServer2D.BODY_STATE_TRANSFORM, cell_data.transform)


func _draw_quadrant_cell(cell_data: MapperCellData, quadrant: Quadrant) -> void:
	var size_rect: Rect2i = _get_texture_region_from_cell_data(cell_data)
	var texture_rect: Rect2i = Rect2i(size_rect.position + cell_data.tile_data.texture_origin, size_rect.size)

	RenderingServer.canvas_item_add_set_transform(quadrant.canvas_item, cell_data.transform)
	RenderingServer.canvas_item_add_texture_rect_region(quadrant.canvas_item,
		texture_rect,
		cell_data.texture.get_rid(),
		size_rect,
		cell_data.tile_data.modulate,
		cell_data.tile_data.transpose)


func _draw_quadrant(quadrant: Quadrant) -> void:
	RenderingServer.canvas_item_clear(quadrant.canvas_item)
	for cell_data in quadrant.cells:
		if cell_data.canvas_rid:
			continue
		_draw_quadrant_cell(cell_data, quadrant)
		_draw_debug(cell_data)


func _draw_tile(cell_data: MapperCellData) -> void:
	var size_rect: Rect2i = _get_texture_region_from_cell_data(cell_data)
	var texture_rect: Rect2i = Rect2i(size_rect.position + cell_data.tile_data.texture_origin, size_rect.size)

	RenderingServer.canvas_item_clear(cell_data.canvas_rid)
	RenderingServer.canvas_item_add_texture_rect_region(cell_data.canvas_rid,
		texture_rect,
		cell_data.texture.get_rid(),
		size_rect,
		cell_data.tile_data.modulate,
		cell_data.tile_data.transpose)
	RenderingServer.canvas_item_set_parent(cell_data.canvas_rid, get_canvas_item())

	if cell_data.tile_data.material:
		RenderingServer.canvas_item_set_material(cell_data.canvas_rid, cell_data.tile_data.material.get_rid())


func _draw_debug_cell_for_shape(cell_data: MapperCellData, body: RID, shape_index: int, debug_color: Color) -> void:
	var shape: RID = PhysicsServer2D.body_get_shape(body, shape_index)
	var shape_type: PhysicsServer2D.ShapeType = PhysicsServer2D.shape_get_type(shape)
	var shape_transform: Transform2D = PhysicsServer2D.body_get_shape_transform(body, shape_index)

	assert(shape_type == PhysicsServer2D.SHAPE_CONVEX_POLYGON, "Wrong shape type for a tile, should be SHAPE_CONVEX_POLYGON.")

	_draw_cell_shape(_get_draw_rid_from_cell(cell_data), shape, debug_color, cell_data.transform * shape_transform)


func _draw_debug_cell(cell_data: MapperCellData, debug_color: Color) -> void:
	for body in cell_data.physics_bodies_rid:
		for shape_index in PhysicsServer2D.body_get_shape_count(body):
			_draw_debug_cell_for_shape(cell_data, body, shape_index, debug_color)


func _draw_debug(cell_data: MapperCellData) -> void:
	if _should_draw_debug_shapes():
		_draw_debug_cell(cell_data, ProjectSettings.get("debug/shapes/collision/shape_color"))


func _draw_cell_shape(draw_rid: RID, shape: RID, color: Color, body_transform: Transform2D) -> void:
	RenderingServer.canvas_item_add_set_transform(draw_rid, body_transform)
	RenderingServer.canvas_item_add_polygon(draw_rid, PhysicsServer2D.shape_get_data(shape), [color])


func _get_texture_region_from_cell_data(cell_data: MapperCellData) -> Rect2i:
	return _get_texture_region_from_atlas_source(cell_data.source_id, cell_data.atlas_coords)


func _get_texture_region_from_atlas_source(source_id: int, atlas_coords: Vector2i) -> Rect2i:
	var source: TileSetSource = tile_set.get_source(source_id)
	if source is TileSetAtlasSource:
		return source.get_tile_texture_region(atlas_coords)

	return Rect2i()


func _get_texture_from_source_id(source_id: int) -> Texture:
	var source: TileSetSource = tile_set.get_source(source_id)
	return source.texture if source is TileSetAtlasSource else null


func _get_quadrant() -> Quadrant:
	return _current_quadrant if _current_quadrant is Quadrant else _create_new_quadrant()


func _get_draw_rid_from_cell(cell_data: MapperCellData) -> RID:
	assert(_is_cell_valid(cell_data), "Invalid cell.")
	var draw_state: CellDrawState = _get_cell_draw_state(cell_data)
	if draw_state == CellDrawState.CANVAS_ITEM:
		return cell_data.canvas_rid

	return cell_data.current_quadrant.canvas_item


func _get_cell_draw_state(cell_data: MapperCellData) -> CellDrawState:
	if cell_data is MapperCellData and cell_data.canvas_rid is RID and cell_data.canvas_rid != RID():
		return CellDrawState.CANVAS_ITEM

	if cell_data.current_quadrant is Quadrant:
		return CellDrawState.QUADRANT

	return CellDrawState.NONE


func _create_convex_shape(points: PackedVector2Array) -> RID:
	var shape: RID = PhysicsServer2D.convex_polygon_shape_create()
	PhysicsServer2D.shape_set_data(shape, points)
	return shape


func _create_shape_with_points(points: PackedVector2Array) -> RID:
	return _create_convex_shape(points)


func _create_physics_bodies_for_cell(cell_data: MapperCellData) -> Array[RID]:
	var bodies: Array[RID] = []

	for layer in tile_set.get_physics_layers_count():
		var body: RID = _for_cell_body_physics_layer(cell_data, layer)
		if body != RID():
			bodies.append(body)

	return bodies


func _create_new_quadrant() -> Quadrant:
	var new_quadrant: Quadrant = Quadrant.new()
	new_quadrant.canvas_item = RenderingServer.canvas_item_create()
	RenderingServer.canvas_item_set_parent(new_quadrant.canvas_item, get_canvas_item())

	if material:
		RenderingServer.canvas_item_set_material(new_quadrant.canvas_item, material.get_rid())

	_quadrants.append(new_quadrant)
	return new_quadrant


func _for_cell_body_polygon_point(cell_data: MapperCellData, layer: int, polygon_index: int) -> RID:
	var points: PackedVector2Array = cell_data.tile_data.get_collision_polygon_points(layer, polygon_index)
	return _create_shape_with_points(points) if points.size() > 3 else RID()


func _for_cell_body_physics_layer(cell_data: MapperCellData, layer: int) -> RID:
	var shapes: Dictionary = {}

	for polygon_index in cell_data.tile_data.get_collision_polygons_count(layer):
		var shape: RID = _for_cell_body_polygon_point(cell_data, layer, polygon_index)
		if shape != RID():
			# Storing collision data like this prevents having to loop through all polygon points later
			shapes[shape] = {"one_way": cell_data.tile_data.is_collision_polygon_one_way(layer, polygon_index),
				"margin": cell_data.tile_data.get_collision_polygon_one_way_margin(layer, polygon_index)}

	if shapes.size() == 0:
		return RID()

	var physics_material: PhysicsMaterial = tile_set.get_physics_layer_physics_material(layer)
	var body: RID = PhysicsServer2D.body_create()
	var cell_size: Vector2 = _get_texture_region_from_cell_data(cell_data).size

	PhysicsServer2D.body_set_mode(body, collision_type)
	PhysicsServer2D.body_set_space(body, get_world_2d().space)
	PhysicsServer2D.body_set_state(body, PhysicsServer2D.BODY_STATE_TRANSFORM, cell_data.transform)
	PhysicsServer2D.body_set_collision_layer(body, tile_set.get_physics_layer_collision_layer(layer))
	PhysicsServer2D.body_set_collision_mask(body, tile_set.get_physics_layer_collision_mask(layer))
	PhysicsServer2D.body_set_constant_torque(body, cell_data.tile_data.get_constant_angular_velocity(layer))
	PhysicsServer2D.body_set_constant_force(body, cell_data.tile_data.get_constant_linear_velocity(layer))

	var i: int = 0
	for shape in shapes:
		PhysicsServer2D.body_add_shape(body, shape, Transform2D(0, cell_size / 2))
		PhysicsServer2D.body_set_shape_as_one_way_collision(body, i, shapes[shape]["one_way"], shapes[shape]["margin"])
		i += 1

	if physics_material:
		PhysicsServer2D.body_set_param(body, PhysicsServer2D.BODY_PARAM_BOUNCE, physics_material.bounce)
		PhysicsServer2D.body_set_param(body, PhysicsServer2D.BODY_PARAM_FRICTION, physics_material.friction)


	return body


func _general_cell_update(cell_data: MapperCellData) -> void:
	match _get_cell_draw_state(cell_data):
		CellDrawState.CANVAS_ITEM:
			_draw_tile(cell_data)
			_update_canvas_item_cell(cell_data)
		CellDrawState.QUADRANT:
			_draw_quadrant(cell_data.current_quadrant)


func _update_canvas_item_cell(cell_data: MapperCellData) -> void:
	RenderingServer.canvas_item_set_transform(cell_data.canvas_rid, cell_data.transform)
	RenderingServer.canvas_item_set_z_index(cell_data.canvas_rid, cell_data.tile_data.z_index)
	RenderingServer.canvas_item_set_default_texture_filter(cell_data.canvas_rid, int(texture_filter))
	RenderingServer.canvas_item_set_default_texture_repeat(cell_data.canvas_rid, int(texture_repeat))
	RenderingServer.canvas_item_set_light_mask(cell_data.canvas_rid, get_light_mask())


func _is_cell_valid(cell_data: MapperCellData) -> bool:
	return true if _get_cell_draw_state(cell_data) != CellDrawState.NONE else false


func _should_draw_debug_shapes() -> bool:
	return true if (get_tree().debug_collisions_hint and collision_visibility == 0) or collision_visibility == 1 else false


func set_transform_of_cell(cell_data: MapperCellData, new_transform: Transform2D) -> void:
	_set_cell_transform(cell_data, new_transform)


func set_cell_scale(cell_data: MapperCellData, new_scale: Vector2) -> void:
	var new_transform: Transform2D = cell_data.transform.scaled_local(cell_data.transform.get_scale()).scaled_local(new_scale)
	_set_cell_transform(cell_data, new_transform)


func set_cell_position(cell_data: MapperCellData, new_position: Vector2) -> void:
	var new_transform: Transform2D = cell_data.transform
	new_transform.origin = new_position
	_set_cell_transform(cell_data, new_transform)


func update_cell_with_tile_data(cell_data: MapperCellData, tile_data: TileData) -> void:
	cell_data.tile_data = tile_data
	_general_cell_update(cell_data)


func add_cell(coords: Vector2, source_id: int, atlas_coords: Vector2 = Vector2.ZERO, alternative_tile: int = 0) -> MapperCellData:
	var cell_data: MapperCellData = MapperCellData.new()
	var source: TileSetSource = tile_set.get_source(source_id) if tile_set is TileSet else null

	cell_data.texture = _get_texture_from_source_id(source_id)
	cell_data.atlas_coords = atlas_coords
	cell_data.transform = Transform2D(0, coords)
	cell_data.tile_data = source.get_tile_data(atlas_coords, alternative_tile)
	cell_data.physics_bodies_rid = _create_physics_bodies_for_cell(cell_data)
	cell_data.source_id = source_id

	var quadrant: Quadrant = _get_quadrant()

	if quadrant.cells.size() >= quadrant_size:
		_current_quadrant = _create_new_quadrant()

	quadrant.cells.append(cell_data)
	_tiles.append(cell_data)

	cell_data.current_quadrant = quadrant
	_draw_quadrant_cell(cell_data, quadrant)
	_draw_debug(cell_data)

	return cell_data


func use_canvas_item_for_cell(cell_data: MapperCellData) -> void:
	if _get_cell_draw_state(cell_data) != CellDrawState.QUADRANT:
		_set_cell_to_use_canvas_item(cell_data)


func use_quadrant_for_cell(cell_data: MapperCellData) -> void:
	if _get_cell_draw_state(cell_data) != CellDrawState.CANVAS_ITEM:
		_set_cell_to_use_quadrant(cell_data, _get_quadrant())


func set_quadrant_for_cell(cell_data: MapperCellData, quadrant: Quadrant, clear_previous_quadrant: bool = true, overwrite_canvas_item: bool = false) -> void:
	var draw_state: CellDrawState = _get_cell_draw_state(cell_data)

	if clear_previous_quadrant and cell_data.current_quadrant:
		cell_data.current_quadrant.cells.erase(cell_data)
		redraw_quadrant(cell_data.current_quadrant)
		_current_quadrant = cell_data.current_quadrant

	if not overwrite_canvas_item and draw_state == CellDrawState.CANVAS_ITEM:
		return

	cell_data.current_quadrant = quadrant
	_draw_quadrant_cell(cell_data, quadrant)


func redraw_quadrant(quadrant: Quadrant) -> void:
	_draw_quadrant(quadrant)


func update_cell(cell_data: MapperCellData) -> void:
	_general_cell_update(cell_data)


func destroy_cell(cell_data: MapperCellData) -> void:
	if cell_data.canvas_rid:
		RenderingServer.free_rid(cell_data.canvas_rid)

	if cell_data.current_quadrant:
		cell_data.current_quadrant.cells.erase(cell_data)
		_current_quadrant = cell_data.current_quadrant
		redraw_quadrant(cell_data.current_quadrant)

	for body in cell_data.physics_bodies_rid:
		PhysicsServer2D.free_rid(body)

	cell_data.physics_bodies_rid.clear()
	_tiles.erase(cell_data)


func get_used_tiles() -> Array[MapperCellData]:
	return _tiles


func get_cell_draw_state(cell_data: MapperCellData) -> CellDrawState:
	return _get_cell_draw_state(cell_data)


func set_tileset(value: TileSet) -> void:
	tile_set = value


func get_tileset() -> TileSet:
	return tile_set


func set_collision_type(type: PhysicsServer2D.BodyMode) -> void:
	collision_type = type


func get_collision_type() -> PhysicsServer2D.BodyMode:
	return collision_type


func set_quadrant_size(value: int) -> void:
	assert(value > 0, "Quadrant size can not be below 1.")
	quadrant_size = value


func get_quadrant_size() -> int:
	return quadrant_size


func set_collision_visibility(value: int) -> void:
	collision_visibility = value


func get_collision_visibility() -> int:
	return collision_visibility


class MapperCellData:
	var canvas_rid: RID
	var current_quadrant: Quadrant
	var physics_bodies_rid: Array[RID] = []
	var atlas_coords: Vector2i = Vector2i.ZERO
	var transform: Transform2D = Transform2D()
	var texture: Texture
	var tile_data: TileData
	var source_id: int = 0


class Quadrant:
	var cells: Array[MapperCellData]
	var canvas_item: RID
