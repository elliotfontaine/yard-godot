@tool
extends Container

@onready var database_menu_button: MenuButton = %DatabaseMenuButton

@onready var registries_list: ItemList = %RegistriesList


func _ready() -> void:
	var recent := PopupMenu.new()
	recent.add_item("previously_used.reg")
	database_menu_button.get_popup().set_item_submenu_node(2, recent)
