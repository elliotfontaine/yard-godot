extends PanelContainer

const ITEM_REGISTRY = preload("uid://fr1nfvgyu25k")

@onready var string_id_line_edit: LineEdit = %StringIDLineEdit
@onready var display_button: Button = %DisplayButton
@onready var item_texture_rect: TextureRect = %ItemTextureRect
@onready var item_name_label: Label = %ItemNameLabel


func _on_display_button_pressed() -> void:
	var string_id := string_id_line_edit.text
	if ITEM_REGISTRY.has_string_id(string_id):
		var item := ITEM_REGISTRY.load_entry(string_id)
		display_item(item)


func display_item(item: Item) -> void:
	item_texture_rect.texture = item.texture
	item_name_label.text = item.name
