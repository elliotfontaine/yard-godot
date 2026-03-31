extends PanelContainer

const ITEM_REGISTRY = preload("uid://fr1nfvgyu25k")

@onready var item_list: ItemList = %ItemList
@onready var property_option_button: OptionButton = %PropertyOptionButton
@onready var operator_option_button: OptionButton = %OperatorOptionButton
@onready var value_spin_box: SpinBox = %ValueSpinBox
@onready var clear_filter_button: Button = %ClearFilterButton
@onready var texture_center_container: CenterContainer = $MarginContainer/HBoxContainer/Display/TextureCenterContainer
@onready var item_texture_rect: TextureRect = %ItemTextureRect
@onready var item_name_label: Label = %ItemNameLabel
@onready var max_stack_count_label: Label = %MaxStackCountLabel
@onready var width_label: Label = %WidthLabel
@onready var height_label: Label = %HeightLabel
@onready var info_label: Label = %InfoLabel


func _ready() -> void:
	_list_all_items()
	texture_center_container.hide()
	info_label.hide()

	property_option_button.clear()
	for prop in ITEM_REGISTRY.get_indexed_properties():
		property_option_button.add_item(prop)


func display_item(item: Item) -> void:
	texture_center_container.show()
	info_label.show()
	item_texture_rect.texture = item.texture
	item_name_label.text = item.name.capitalize()
	max_stack_count_label.text = "Max stack count: " + str(item.max_stack_count)
	width_label.text = "Inventory width: " + str(item.in_inventory_width)
	height_label.text = "Inventory height: " + str(item.in_inventory_height)


func _list_all_items() -> void:
	clear_filter_button.hide()
	item_list.clear()
	for item_name in ITEM_REGISTRY.get_all_string_ids():
		item_list.add_item(item_name)


func _on_item_list_item_selected(index: int) -> void:
	var string_id := item_list.get_item_text(index)
	if ITEM_REGISTRY.has_string_id(string_id):
		var item := ITEM_REGISTRY.load_entry(string_id)
		display_item(item)


func _on_filter_button_pressed() -> void:
	var prop := property_option_button.text
	var operator := operator_option_button.text
	var value := int(value_spin_box.value)

	var criterion: Variant # Callable or exact value
	match operator:
		"==":
			criterion = value
		"!=":
			criterion = func(v: int) -> bool: return v != value
		"<":
			criterion = func(v: int) -> bool: return v < value
		"<=":
			criterion = func(v: int) -> bool: return v <= value
		">":
			criterion = func(v: int) -> bool: return v > value
		">=":
			criterion = func(v: int) -> bool: return v >= value

	var matches := ITEM_REGISTRY.filter(prop, criterion)
	item_list.clear()
	for item_name in matches:
		item_list.add_item(item_name)
	clear_filter_button.show()


func _on_clear_filter_button_pressed() -> void:
	_list_all_items()
