# SPDX-FileCopyrightText: 2025-2026, Elliot Fontaine <yard-godot@elliotfontaine.anonaddy.com>
# SPDX-FileCopyrightText: 2026-present, YARD contributors (see AUTHORS.md)
#
# SPDX-License-Identifier: MIT

@tool
extends HBoxContainer

signal add_entry_requested(res: Resource, string_id: String, target_dir: String)
signal registry_panel_toggled(toggled_on: bool)

const Namespace := preload("res://addons/yard/editor_only/namespace.gd")
const Compat := Namespace.Compat
const ClassUtils := Namespace.ClassUtils
const RegistryIO := Namespace.RegistryIO
const AnyIcon := Namespace.AnyIcon
const ShortcutUtils := Namespace.ShortcutUtils

const _AUTO_DIR_ID := -1
const _BROWSE_DIR_ID := -2

var _current_registry_uid: String
var _current_registry_settings: RegistryIO.RegistrySettings
var _add_entry_cache: Dictionary[String, Dictionary] = { }
var _add_entry_target_dir: String = ""
var _add_entry_custom_dir: String = ""
var _toggle_button_forward: bool = false
var _texture_rect_parent: Button
var _dir_dialog: EditorFileDialog
var _res_picker: EditorResourcePicker

@onready var toggle_registry_panel_button: Button = %ToggleRegistryPanelButton
@onready var add_entry_container: HBoxContainer = %AddEntryContainer
@onready var resource_picker_container: PanelContainer = %ResourcePickerContainer
@onready var add_entry_directory_container: PanelContainer = %AddEntryDirectoryContainer
@onready var add_entry_directory_button: OptionButton = %AddEntryDirectoryButton
@onready var entry_name_line_edit: LineEdit = %EntryNameLineEdit
@onready var add_entry_button: Button = %AddEntryButton


func _ready() -> void:
	if not Engine.is_editor_hint() or EditorInterface.get_edited_scene_root() == self:
		return

	entry_name_line_edit.text_submitted.connect(_on_new_entry_text_submitted)
	entry_name_line_edit.text_changed.connect(_on_entry_name_line_edit_text_changed)
	add_entry_directory_button.item_selected.connect(_on_add_entry_directory_button_item_selected)
	add_entry_button.pressed.connect(_on_add_entry_button_pressed)
	toggle_registry_panel_button.pressed.connect(_on_toggle_registry_panel_button_pressed)

	_dir_dialog = EditorFileDialog.new()
	_dir_dialog.access = EditorFileDialog.ACCESS_RESOURCES
	_dir_dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_DIR
	_dir_dialog.dir_selected.connect(_on_add_entry_dir_selected)
	add_child(_dir_dialog)

	var editor_line_edit_stylebox := get_theme_stylebox(&"normal", &"LineEdit").duplicate()
	for container: PanelContainer in [add_entry_directory_container, resource_picker_container]:
		container.add_theme_stylebox_override(&"panel", editor_line_edit_stylebox)
		container.get_theme_stylebox(&"panel").content_margin_bottom = 0
		container.get_theme_stylebox(&"panel").content_margin_top = 0
		container.get_theme_stylebox(&"panel").content_margin_left = 0
		container.get_theme_stylebox(&"panel").content_margin_right = 0

	var files_shortcut := ShortcutUtils.get_action_shortcut("toggle_registries_panel")
	if files_shortcut:
		toggle_registry_panel_button.shortcut = files_shortcut


func _process(_delta: float) -> void:
	if _texture_rect_parent and _texture_rect_parent.custom_minimum_size != Vector2(1, 1):
		# It's set by C++ code to enlarge the resource preview in the inspector.
		# Since we want the bottom bar height to remain constant, we have to reset it.
		_texture_rect_parent.custom_minimum_size = Vector2(1, 1)


func set_current_registry(registry: Registry) -> void:
	if not registry:
		_current_registry_uid = ""
		_current_registry_settings = null
		return
	var new_uid := Compat.path_to_uid(registry.resource_path)
	var is_another := new_uid != _current_registry_uid
	if is_another and _current_registry_uid:
		_cache_add_entry_value()
	_current_registry_uid = new_uid
	_current_registry_settings = RegistryIO.get_registry_settings(registry)
	_setup_add_entry()


## Discards the cached Add Entry value for a closed registry.
func clear_add_entry_cache(uid: String) -> void:
	_add_entry_cache.erase(uid)


func clear_resource_picker() -> void:
	_res_picker.edited_resource = null


func clear_string_id_line_edit() -> void:
	entry_name_line_edit.text = ""


func toggle_add_entry_fields(toggled_on: bool) -> void:
	add_entry_container.visible = toggled_on


func _toggle_add_entry_button() -> void:
	add_entry_button.disabled = !(
		_res_picker and _res_picker.edited_resource and entry_name_line_edit.text
	)


func _setup_add_entry() -> void:
	if _res_picker:
		_res_picker.queue_free()
	_res_picker = EditorResourcePicker.new()
	_res_picker.custom_minimum_size = Vector2(240, 0)
	_res_picker.base_type = "Resource"

	if _current_registry_settings.has_any_class_restriction():
		var all_class_restrictions_usable_strings: PackedStringArray
		for restriction in _current_registry_settings.get_all_class_restrictions():
			if not RegistryIO.is_quoted_string(restriction):
				all_class_restrictions_usable_strings.append(restriction)
			else:
				var script: Script = load(RegistryIO.unquote(restriction))
				all_class_restrictions_usable_strings.append(ClassUtils.get_type_name(script))
		if not all_class_restrictions_usable_strings.is_empty():
			_res_picker.base_type = ",".join(all_class_restrictions_usable_strings)

	resource_picker_container.add_child(_res_picker)
	_texture_rect_parent = _res_picker.get_child(0)
	_res_picker.resource_changed.connect(_on_res_picker_resource_changed)
	_res_picker.resource_selected.connect(_on_res_picker_resource_selected)

	var cached: Dictionary = _add_entry_cache.get(_current_registry_uid, { })
	entry_name_line_edit.text = cached.get(&"string_id", "")
	_res_picker.edited_resource = cached.get(&"resource", null)

	var cached_dir: String = cached.get(&"directory", "")
	_add_entry_target_dir = cached_dir
	_add_entry_custom_dir = (
		cached_dir
		if (cached_dir and cached_dir not in _current_registry_settings.get_all_scan_directories())
		else ""
	)

	_rebuild_add_entry_directory_options()
	_toggle_add_entry_button()


func _rebuild_add_entry_directory_options() -> void:
	add_entry_directory_button.clear()
	add_entry_directory_button.add_item(tr("Auto (registry file location)"))
	add_entry_directory_button.set_item_id(0, _AUTO_DIR_ID)

	var scan_dirs := _current_registry_settings.get_all_scan_directories()
	for dir in scan_dirs:
		add_entry_directory_button.add_item(dir)
	if _add_entry_custom_dir and _add_entry_custom_dir not in scan_dirs:
		add_entry_directory_button.add_item(_add_entry_custom_dir)

	add_entry_directory_button.add_separator()

	var popup := add_entry_directory_button.get_popup()
	var browse_idx := add_entry_directory_button.item_count
	add_entry_directory_button.add_icon_item(AnyIcon.get_icon(&"FolderBrowse"), tr("Browse"))
	add_entry_directory_button.set_item_id(browse_idx, _BROWSE_DIR_ID)
	popup.set_item_as_radio_checkable(browse_idx, false)

	var target_idx := 0
	for i in add_entry_directory_button.item_count:
		var id := add_entry_directory_button.get_item_id(i)
		if (
			id not in [_AUTO_DIR_ID, _BROWSE_DIR_ID]
			and add_entry_directory_button.get_item_text(i) == _add_entry_target_dir
		):
			target_idx = i
			break
	add_entry_directory_button.select(target_idx)


func _cache_add_entry_value() -> void:
	_add_entry_cache[_current_registry_uid] = {
		&"string_id": entry_name_line_edit.text,
		&"resource": _res_picker.edited_resource if _res_picker else null,
		&"directory": _add_entry_target_dir,
	}


func _on_entry_name_line_edit_text_changed(_new_text: String) -> void:
	_toggle_add_entry_button()


func _on_res_picker_resource_changed(_new_resource: Resource) -> void:
	_toggle_add_entry_button()


func _on_res_picker_resource_selected(resource: Resource, inspect: bool) -> void:
	if inspect:
		EditorInterface.edit_resource(resource)


func _on_add_entry_directory_button_item_selected(index: int) -> void:
	match add_entry_directory_button.get_item_id(index):
		_AUTO_DIR_ID:
			_add_entry_target_dir = ""
		_BROWSE_DIR_ID:
			_dir_dialog.current_dir = _add_entry_target_dir if _add_entry_target_dir else "res://"
			_dir_dialog.popup_file_dialog()
			_rebuild_add_entry_directory_options() # revert selection until a dir is actually picked
		_:
			_add_entry_target_dir = add_entry_directory_button.get_item_text(index)


func _on_add_entry_dir_selected(dir: String) -> void:
	_add_entry_custom_dir = dir
	_add_entry_target_dir = dir
	_rebuild_add_entry_directory_options()


func _on_new_entry_text_submitted(_new_text: String) -> void:
	_on_add_entry_button_pressed()


func _on_add_entry_button_pressed() -> void:
	_toggle_add_entry_button()
	if add_entry_button.disabled:
		return

	add_entry_requested.emit(
		_res_picker.edited_resource,
		entry_name_line_edit.text,
		_add_entry_target_dir,
	)


func _on_toggle_registry_panel_button_pressed() -> void:
	registry_panel_toggled.emit(_toggle_button_forward)
	_toggle_button_forward = !_toggle_button_forward
	var icon_name := &"Forward" if _toggle_button_forward else &"Back"
	toggle_registry_panel_button.icon = get_theme_icon(icon_name, &"EditorIcons")
