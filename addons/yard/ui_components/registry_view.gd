@tool
extends Panel

const COLUMNS := ["String ID", "UID", "Property 1", "Property 2", "Property 3"]

@onready var grid_tree: Tree = %GridTree


func _ready() -> void:
	_set_tree_placeholder()


func _set_tree_placeholder() -> void:
	var root := grid_tree.create_item()
	for i in 5:
		grid_tree.set_column_title(i, COLUMNS[i])
		grid_tree.set_column_expand(i, false)
		grid_tree.set_column_clip_content(i, false)
	
	var child1 := grid_tree.create_item(root)
	var child2 := grid_tree.create_item(root)
	_set_treeitem_default_properties(child1)
	_set_treeitem_default_properties(child2)
	
	child1.set_text(0, "iron_sword")
	child1.set_icon(0, get_theme_icon("Object", "EditorIcons"))
	child1.set_text(1, "uid://dwi4ioxeauoc4")
	child1.set_icon(2, preload("uid://vi43b1o26w60").texture)
	child1.set_custom_color(0, Color.RED)
	
	child2.set_text(0, "diamond_swordddddddddd")
	child2.set_icon(0, get_theme_icon("Object", "EditorIcons"))
	child2.set_text(1, "uid://uebd5i8hzn9ak")
	child2.set_icon(2, preload("uid://c65l1w3756rlu").texture)
	#child2.set_icon_region(2, Rect2i(12, 24, 24, 12))
	
	
func _set_treeitem_default_properties(item: TreeItem) -> void:
	item.set_editable(0, true)
	for col in grid_tree.columns:
		item.set_text_overrun_behavior(col, TextServer.OVERRUN_NO_TRIMMING)
