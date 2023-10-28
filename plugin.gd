@tool
extends EditorPlugin


func _enter_tree() -> void:
	add_custom_type("TileMapper", "Node2D", preload("./tile_mapper.gd"), preload("./TileMap.svg"))


func _exit_tree() -> void:
	remove_custom_type("TileMapper")
