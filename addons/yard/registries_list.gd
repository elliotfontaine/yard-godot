@tool
extends VBoxContainer

@onready var filter_registries_line_edit: LineEdit = %FilterRegistriesLineEdit
@onready var item_list: ItemList = %ItemList

func _ready() -> void:
	filter_registries_line_edit.right_icon = get_theme_icon("Search", "EditorIcons")
	item_list.add_item("NewRegistry", get_theme_icon("FileList", "EditorIcons"))
