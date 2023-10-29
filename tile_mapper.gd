@tool
extends Node2D
class_name TileMapper

enum CellDrawState {
	CANVAS_ITEM,
	QUADRANT,
	NONE
}

const EMPTY_RID: RID = RID()

@export var tile_set: TileSet:
	set = set_tileset,
	get = get_tileset
@export_enum("Static", "Kinematic") var collision_type: int = PhysicsServer2D.BODY_MODE_STATIC:
	set = set_collision_type,
	get = get_collision_type
@export var quadrant_size: int = 64:
	set = set_quadrant_size,
	get = get_quadrant_size
@export_enum("Default", "Force Show", "Force Hide") var collsion_visibliy_mode: int = 0

var _tiles: Array[MapperCellData] = []
var _quadrants: Array[Quadrant]
var _current_cell_index: int = 0
var _collision_visible: bool = false


func _show_collision_shapes() -> bool:
	if not is_inside_tree():
		return false

	match collsion_visibliy_mode:
		1:
			return true
		0:
			return ProjectSettings.get("debug/shapes/collision/shape_color") and get_tree().debug_collisions_hint
	return false


func _set_cell_to_use_canvas_item(cell_data: MapperCellData) -> void:
	cell_data.canvas_rid = RenderingServer.canvas_item_create()
	_draw_tile(cell_data)
	_update_canvas_item_cell(cell_data)


func _set_cell_to_use_quadrant(cell_data: MapperCellData, quadrant: Quadrant) -> void:
	RenderingServer.free_rid(cell_data.canvas_rid)
	cell_data.canvas_rid = EMPTY_RID
	quadrant.cells.append(cell_data)
	_draw_quadrant_cell(cell_data, quadrant)


func _set_cell_transform(cell_data: MapperCellData, new_transform: Transform2D) -> void:
	cell_data.transform = new_transform
	var draw_state: CellDrawState = _get_cell_draw_state(cell_data)

	match draw_state:
		CellDrawState.CANVAS_ITEM:
			RenderingServer.canvas_item_set_transform(cell_data.canvas_rid, cell_data.transform)
		CellDrawState.QUADRANT:
			_draw_quadrant(cell_data.current_quadrant)

	for body in cell_data.physics_bodies_rid:
		PhysicsServer2D.body_set_state(body, PhysicsServer2D.BODY_STATE_TRANSFORM, cell_data.transform)


func _draw_quadrant_cell(cell_data: MapperCellData, quadrant: Quadrant) -> void:
	var size_rect: Rect2i = _get_texture_region_from_cell_data(cell_data)
	var texture_rect: Rect2i = size_rect

	texture_rect.position += cell_data.tile_data.texture_origin
	texture_rect.position += Vector2i(cell_data.transform.origin)
	RenderingServer.canvas_item_add_texture_rect_region(quadrant.canvas_item,
		texture_rect,
		cell_data.texture.get_rid(),
		size_rect,
		cell_data.tile_data.modulate,
		cell_data.tile_data.transpose)

	if _show_collision_shapes():
		_draw_collision_shape(quadrant.canvas_item, ProjectSettings.get("debug/shapes/collision/shape_color"), texture_rect)


func _draw_quadrant(quadrant: Quadrant) -> void:
	RenderingServer.canvas_item_clear(quadrant.canvas_item)
	for cell_data in quadrant.cells:
		if cell_data.canvas_rid:
			continue
		_draw_quadrant_cell(cell_data, quadrant)


func _draw_tile(cell_data: MapperCellData) -> void:
	var size_rect: Rect2i = _get_texture_region_from_cell_data(cell_data)
	var texture_rect: Rect2i = size_rect

	texture_rect.position += cell_data.tile_data.texture_origin
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

	if _show_collision_shapes():
		_draw_collision_shape(cell_data.canvas_rid, ProjectSettings.get("debug/shapes/collision/shape_color"), texture_rect)


func _draw_collision_shape(on_canvas: RID, color: Color = Color("0099b36b"), rectangle: Rect2 = Rect2()) -> void:
	RenderingServer.canvas_item_add_rect(on_canvas, rectangle, color)


func _get_texture_region_from_cell_data(cell_data: MapperCellData) -> Rect2i:
	return _get_texture_region_from_atlas_source(cell_data.source_id, cell_data.atlas_coords)


func _get_texture_region_from_atlas_source(source_id: int, atlas_coords: Vector2i) -> Rect2i:
	var source: TileSetSource = tile_set.get_source(source_id)
	if source is TileSetAtlasSource:
		return source.get_tile_texture_region(atlas_coords)

	return Rect2i(NAN, NAN, NAN, NAN)


func _get_texture_from_source_id(source_id: int) -> Texture:
	var source: TileSetSource = tile_set.get_source(source_id)
	return source.texture if source is TileSetAtlasSource else null


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
		bodies.append(body)

	return bodies


func _for_cell_body_polygon_point(cell_data: MapperCellData, layer: int, polgyon_index: int) -> RID:
	var points: PackedVector2Array = cell_data.tile_data.get_collision_polygon_points(layer, polgyon_index)
	return _create_shape_with_points(points) if points.size() > 3 else EMPTY_RID


func _for_cell_body_physics_layer(cell_data: MapperCellData, layer: int) -> RID:
	var shapes: Dictionary = {}

	for polygon_index in cell_data.tile_data.get_collision_polygons_count(layer):
		var shape: RID = _for_cell_body_polygon_point(cell_data, layer, polygon_index)
		if shape != EMPTY_RID:
			# Storing collision data like this prevents having to loop through all polygon points later
			shapes[shape] = {"one_way": cell_data.tile_data.is_collision_polygon_one_way(layer, polygon_index),
				"margin": cell_data.tile_data.get_collision_polygon_one_way_margin(layer, polygon_index)}

	if shapes.size() == 0:
		return EMPTY_RID

	var physics_material: PhysicsMaterial = tile_set.get_physics_layer_physics_material(layer)
	var body: RID = PhysicsServer2D.body_create()

	PhysicsServer2D.body_set_mode(body, collision_type)
	PhysicsServer2D.body_set_space(body, get_world_2d().space)
	PhysicsServer2D.body_set_state(body, PhysicsServer2D.BODY_STATE_TRANSFORM, cell_data.transform)
	PhysicsServer2D.body_set_collision_layer(body, tile_set.get_physics_layer_collision_layer(layer))
	PhysicsServer2D.body_set_collision_mask(body, tile_set.get_physics_layer_collision_mask(layer))
	PhysicsServer2D.body_set_constant_torque(body, cell_data.tile_data.get_constant_angular_velocity(layer))
	PhysicsServer2D.body_set_constant_force(body, cell_data.tile_data.get_constant_linear_velocity(layer))

	var i: int = 0
	for shape in shapes:
		PhysicsServer2D.body_add_shape(body, shape)
		PhysicsServer2D.body_set_shape_as_one_way_collision(body, i, shapes[shape]["one_way"], shapes[shape]["margin"])
		i += 1

	if physics_material:
		PhysicsServer2D.body_set_param(body, PhysicsServer2D.BODY_PARAM_BOUNCE, physics_material.bounce)
		PhysicsServer2D.body_set_param(body, PhysicsServer2D.BODY_PARAM_FRICTION, physics_material.friction)


	return body


func _general_cell_update(cell_data: MapperCellData) -> void:
	if cell_data.canvas_rid:
		_draw_tile(cell_data)
		_update_canvas_item_cell(cell_data)
	elif cell_data.current_quadrant:
		_draw_quadrant(cell_data.current_quadrant)


func _update_canvas_item_cell(cell_data: MapperCellData) -> void:
	RenderingServer.canvas_item_set_transform(cell_data.canvas_rid, cell_data.transform)
	RenderingServer.canvas_item_set_z_index(cell_data.canvas_rid, cell_data.tile_data.z_index)
	RenderingServer.canvas_item_set_default_texture_filter(cell_data.canvas_rid, int(texture_filter))
	RenderingServer.canvas_item_set_default_texture_repeat(cell_data.canvas_rid, int(texture_repeat))
	RenderingServer.canvas_item_set_light_mask(cell_data.canvas_rid, get_light_mask())


func _get_cell_draw_state(cell_data: MapperCellData) -> CellDrawState:
	if cell_data.canvas_rid is RID and cell_data.canvas_rid != EMPTY_RID:
		return CellDrawState.CANVAS_ITEM

	if cell_data.current_quadrant is Quadrant:
		return CellDrawState.QUADRANT

	return CellDrawState.NONE


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


func add_cell(coords: Vector2, source_id: int, atlas_coords: Vector2 = Vector2.ZERO, alternative_tile: int = 0, keep_reference: bool = true, use_quadrants: bool = true) -> MapperCellData:
	var cell_data: MapperCellData = MapperCellData.new()
	var source: TileSetSource = tile_set.get_source(source_id) if tile_set is TileSet else null

	_current_cell_index += 1
	if _current_cell_index == 1:
		var new_quadrant: Quadrant = Quadrant.new()
		new_quadrant.canvas_item = RenderingServer.canvas_item_create()
		RenderingServer.canvas_item_set_parent(new_quadrant.canvas_item, get_canvas_item())
		_quadrants.append(new_quadrant)

	if _current_cell_index == quadrant_size:
		_current_cell_index = 0

	cell_data.texture = _get_texture_from_source_id(source_id)
	cell_data.atlas_coords = atlas_coords
	cell_data.transform = Transform2D(0, coords)
	cell_data.tile_data = source.get_tile_data(atlas_coords, alternative_tile)
	cell_data.physics_bodies_rid = _create_physics_bodies_for_cell(cell_data)
	cell_data.source_id = source_id

	if use_quadrants:
		var quadrant: Quadrant = _quadrants[-1]
		if keep_reference:
			quadrant.cells.append(cell_data)
			_tiles.append(cell_data)
		cell_data.current_quadrant = quadrant
		_draw_quadrant_cell(cell_data, quadrant)
	else:
		cell_data.canvas_rid = RenderingServer.canvas_item_create()
		_draw_tile(cell_data)
		_update_canvas_item_cell(cell_data)

	return cell_data


func use_canvas_item_for_cell(cell_data: MapperCellData, overwrite_quadrant: bool = false) -> void:
	var can_overwrite_quadrant: bool = (cell_data.current_quadrant and overwrite_quadrant) or not cell_data.current_quadrant

	if _get_cell_draw_state(cell_data) != CellDrawState.QUADRANT and can_overwrite_quadrant:
		_set_cell_to_use_canvas_item(cell_data)


func use_quadrant_for_cell(cell_data: MapperCellData, overwrite_canvas_item: bool = false) -> void:
	var can_overwrite_canvas_item: bool = (cell_data.canvas_rid and overwrite_canvas_item) or not cell_data.canvas_rid

	if _get_cell_draw_state(cell_data) != CellDrawState.CANVAS_ITEM and can_overwrite_canvas_item:
		var quadrant: Quadrant = _quadrants[-1] if _quadrants.size() > 0 else null

		if not quadrant is Quadrant:
			push_warning("Tried to use quadrant but quadrants size is 0?")
			return

		_set_cell_to_use_quadrant(cell_data, quadrant)


func set_quadrant_for_cell(cell_data: MapperCellData, quadrant: Quadrant, clear_previous_quadrant: bool = true, overwrite_canvas_item: bool = false) -> void:
	var draw_state: CellDrawState = _get_cell_draw_state(cell_data)

	if clear_previous_quadrant and cell_data.current_quadrant:
		cell_data.current_quadrant.cells.erase(cell_data)

	if not overwrite_canvas_item and draw_state == CellDrawState.CANVAS_ITEM:
		return

	cell_data.current_quadrant = quadrant
	_draw_quadrant_cell(cell_data, quadrant)


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


func get_collision_type() -> int:
	return collision_type


func set_quadrant_size(value: int) -> void:
	assert(value > 0, "Quadrant size can not be below 1.")
	quadrant_size = value


func get_quadrant_size() -> int:
	return quadrant_size


class MapperCellData:
	var canvas_rid: RID = EMPTY_RID
	var current_quadrant: Quadrant
	var physics_bodies_rid: Array[RID] = []
	var atlas_coords: Vector2i = Vector2i.ZERO
	var transform: Transform2D = Transform2D()
	var texture: Texture
	var tile_data: TileData
	var source_id: int = 0


class Quadrant:
	var cells: Array[MapperCellData]
	var canvas_item: RID = EMPTY_RID
