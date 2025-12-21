@tool
extends Container

## uid: filepath
var _opened_registries: Dictionary[int, String]

@onready var database_menu_button: MenuButton = %DatabaseMenuButton
@onready var registry_view: Panel = %RegistryView
@onready var registries_filter: LineEdit = %RegistriesFilter
@onready var registries_list: ItemList = %RegistriesList


func _ready() -> void:
	var recent := PopupMenu.new()
	recent.add_item("previously_used.reg")
	database_menu_button.get_popup().set_item_submenu_node(2, recent)
	registries_filter.right_icon = get_theme_icon(&"Search", &"EditorIcons")


func open_registry(registry: Registry) -> void:
	var filepath := registry.resource_path
	var uid := int(ResourceUID.path_to_uid(filepath))
	if uid not in _opened_registries:
		_opened_registries[uid] = filepath
	_update_registry_names()
	select_registry(uid)


## Select a registry on the list and open its content view on the right
func select_registry(uid: int) -> void:
	pass
	print("registry selected")
	registry_view.show_placeholder()


## Updates the script list on the left
func _update_registry_names() -> void:
	registries_list.clear()
	
	if registries_filter.text != "":
		print("filter not empty :", registries_filter.text)
	
	for uid in _opened_registries:
		add_registry_to_list(_opened_registries[uid])


func add_registry_to_list(filename: String, icon: Texture2D = null) -> int:
	if not icon:
		icon = get_theme_icon("FileList", "EditorIcons")
	var idx := registries_list.add_item(filename.get_file(), icon, true)
	registries_list.set_item_tooltip(idx, filename)
	return idx


func _on_registries_filter_text_changed(_new_text: String) -> void:
	_update_registry_names()
