@tool
extends ConfirmationDialog

# Used both for the 'New Registry' menu item
# and for the 'Registry Settings' button

enum RegistryDialogState { NEW_REGISTRY, REGISTRY_SETTINGS }
enum FileDialogState { CLASS_RESTRICTION, SCAN_DIRECTORY, REGISTRY_PATH }

const Namespace := preload("res://addons/yard/editor_only/namespace.gd")
const RegistryIO := Namespace.RegistryIO
const ClassUtils := Namespace.ClassUtils
const AnyIcon := Namespace.AnyIcon
const DEFAULT_COLOR = Color(0.71, 0.722, 0.745, 1.0)
const SUCCESS_COLOR = Color(0.45, 0.95, 0.5)
const WARNING_COLOR = Color(0.83, 0.78, 0.62)
const ERROR_COLOR = Color(1, 0.47, 0.42)

# would be a constant if not for the `tr()`
var INFO_MESSAGES: Dictionary[StringName, Array] = {
	# --- Class restriction ---
	&"class_valid": [tr("Class/script is a Resource subclass."), SUCCESS_COLOR],
	&"class_invalid": [tr("Invalid class/script. Expected a Resource subclass (built-in, class_name, or [u]quoted[/u] script path)."), ERROR_COLOR],
	&"class_empty": [tr("No class filter, all Resource files will be accepted to the registry."), WARNING_COLOR],

	# --- Scan directory ---
	&"scan_valid": [tr("Scan directory valid. Will watch for new Resources…"), SUCCESS_COLOR],
	&"scan_invalid": [tr("Scan directory invalid. Pick an existing directory."), ERROR_COLOR],
	&"scan_empty": [tr("No scan directory, resources auto-discovery is disabled."), DEFAULT_COLOR],

	# --- Indexed properties ---
	&"properties_none": [tr("Indexed properties are optional. Separate multiple properties with commas."), DEFAULT_COLOR],
	&"properties_valid": [tr("All properties found on the specified resource class."), SUCCESS_COLOR],
	&"properties_empty_prop": [tr("Empty property name detected. Remove extra commas."), ERROR_COLOR],
	&"properties_cant_verify": [tr("Property '{prop}' may not exist on the resource class."), WARNING_COLOR],

	# --- Registry path ---
	&"path_available": [tr("Will create a new registry file."), SUCCESS_COLOR],
	&"path_invalid": [tr("Filename is invalid."), ERROR_COLOR],
	&"extension_invalid": [tr("Invalid extension."), ERROR_COLOR],
	&"filename_empty": [tr("Filename is empty."), ERROR_COLOR],
	&"path_already_used": [tr("Registry file already exists."), ERROR_COLOR],

	# --- Scan regex ---
	&"regex_include_valid": [tr("Include filter active. Only matching paths will be scanned."), SUCCESS_COLOR],
	&"regex_include_invalid": [tr("Invalid include regex pattern."), ERROR_COLOR],
	&"regex_exclude_valid": [tr("Exclude filter active. Matching paths will be skipped."), SUCCESS_COLOR],
	&"regex_exclude_invalid": [tr("Invalid exclude regex pattern."), ERROR_COLOR],
}

var edited_registry: Registry

var _state: RegistryDialogState
var _file_dialog: EditorFileDialog
var _file_dialog_state: FileDialogState

@onready var new_restriction_confirmation_dialog: ConfirmationDialog = %NewRestrictionConfirmationDialog
@onready var class_restriction_line_edit: LineEdit = %ClassRestrictionLineEdit
@onready var class_list_dialog_button: Button = %ClassListDialogButton
@onready var class_filesystem_button: Button = %ClassFilesystemButton
@onready var scan_directory_line_edit: LineEdit = %ScanDirectoryLineEdit
@onready var scan_directory_filesystem_button: Button = %ScanDirectoryFilesystemButton
@onready var registry_path_line_edit: LineEdit = %RegistryPathLineEdit
@onready var registry_path_filesystem_button: Button = %RegistryPathFilesystemButton
@onready var indexed_properties_line_edit: LineEdit = %IndexedPropertiesLineEdit
@onready var info_label: RichTextLabel = %InfoLabel
@onready var advanced_scan_options_container: FoldableContainer = $VBoxContainer/AdvancedScanOptionsContainer
@onready var scan_recursive_check_box: CheckBox = %RecursiveScanCheckBox
@onready var auto_rescan_check_box: CheckBox = %AutoRescanCheckBox
@onready var scan_remove_unlisted_check_box: CheckBox = %ScanRemoveUnlistedCheckBox
@onready var scan_regex_include_line_edit: LineEdit = %ScanRegexIncludeLineEdit
@onready var scan_regex_exclude_line_edit: LineEdit = %ScanRegexExcludeLineEdit


func _ready() -> void:
	if not Engine.is_editor_hint():
		return

	var base_font_color := get_theme_color(&"font_color", &"Editor")
	advanced_scan_options_container.add_theme_color_override(&"font_color", base_font_color)
	advanced_scan_options_container.add_theme_color_override(&"collapsed_font_color", base_font_color)
	for check_box: CheckBox in [scan_recursive_check_box, auto_rescan_check_box, scan_remove_unlisted_check_box]:
		check_box.add_theme_stylebox_override(&"focus", get_theme_stylebox(&"focus", &"LineEdit"))
		for override: StringName in [&"normal", &"hover", &"pressed", &"hover_pressed"]:
			check_box.add_theme_stylebox_override(override, get_theme_stylebox(&"normal", &"LineEdit"))

	about_to_popup.connect(_on_about_to_popup)
	_file_dialog = EditorFileDialog.new()
	_file_dialog.file_selected.connect(_on_file_dialog_file_selected)
	_file_dialog.dir_selected.connect(_on_file_dialog_dir_selected)
	add_child(_file_dialog)
	hide()


func popup_with_state(state: RegistryDialogState, dir: String = "") -> void:
	_state = state
	if state == RegistryDialogState.NEW_REGISTRY:
		var default_settings := RegistryIO.RegistrySettings.new() # to use default values
		class_restriction_line_edit.text = default_settings.class_restriction
		scan_directory_line_edit.text = default_settings.scan_directory
		scan_recursive_check_box.button_pressed = default_settings.recursive_scan
		auto_rescan_check_box.button_pressed = default_settings.auto_rescan
		scan_remove_unlisted_check_box.button_pressed = default_settings.remove_unmatched
		scan_regex_include_line_edit.text = default_settings.scan_regex_include
		scan_regex_exclude_line_edit.text = default_settings.scan_regex_exclude
		indexed_properties_line_edit.text = default_settings.indexed_props
		title = "Create Registry"
		ok_button_text = "Create"
		registry_path_line_edit.editable = true
		registry_path_line_edit.focus_mode = Control.FOCUS_ALL
		registry_path_line_edit.text = dir.path_join("new_registry.tres")
		registry_path_filesystem_button.icon = AnyIcon.get_icon(&"Folder")
		registry_path_filesystem_button.tooltip_text = ""
	elif edited_registry and state == RegistryDialogState.REGISTRY_SETTINGS:
		var settings := RegistryIO.get_registry_settings(edited_registry)
		class_restriction_line_edit.text = settings.class_restriction
		scan_directory_line_edit.text = settings.scan_directory
		scan_recursive_check_box.button_pressed = settings.recursive_scan
		auto_rescan_check_box.button_pressed = settings.auto_rescan
		scan_remove_unlisted_check_box.button_pressed = settings.remove_unmatched
		scan_regex_include_line_edit.text = settings.scan_regex_include
		scan_regex_exclude_line_edit.text = settings.scan_regex_exclude
		indexed_properties_line_edit.text = settings.indexed_props
		registry_path_line_edit.text = edited_registry.resource_path
		title = "Registry Settings"
		ok_button_text = "Save"
		registry_path_line_edit.editable = false
		registry_path_line_edit.focus_mode = Control.FOCUS_NONE
		registry_path_filesystem_button.icon = AnyIcon.get_icon(&"ShowInFileSystem")
		registry_path_filesystem_button.tooltip_text = "Show in FileSystem"
	else:
		return

	popup()


func _build_settings() -> RegistryIO.RegistrySettings:
	var settings := RegistryIO.RegistrySettings.new()
	settings.class_restriction = class_restriction_line_edit.text.strip_edges()
	settings.scan_directory = scan_directory_line_edit.text.strip_edges()
	settings.recursive_scan = scan_recursive_check_box.button_pressed
	settings.auto_rescan = auto_rescan_check_box.button_pressed
	settings.remove_unmatched = scan_remove_unlisted_check_box.button_pressed
	settings.scan_regex_include = scan_regex_include_line_edit.text.strip_edges()
	settings.scan_regex_exclude = scan_regex_exclude_line_edit.text.strip_edges()
	settings.indexed_props = indexed_properties_line_edit.text.strip_edges()
	return settings


func _validate_fields() -> void:
	get_ok_button().disabled = false
	var info_messages: Array[Array] = [] # elements from INFO_MESSAGES

	# Resource class
	var class_string := class_restriction_line_edit.text.strip_edges()
	var is_class_valid := RegistryIO.is_resource_class_string(class_string)
	if class_string.is_empty():
		class_string = "Resource"
		is_class_valid = true
		class_restriction_line_edit.right_icon = AnyIcon.get_class_icon(&"Resource")
		info_messages.append(INFO_MESSAGES.class_empty)
	elif is_class_valid:
		# TODO: Fix icon size in Godot 4.6 — https://github.com/godotengine/godot/pull/95817
		class_restriction_line_edit.right_icon = (
			AnyIcon.get_script_icon(load(RegistryIO.unquote(class_string)))
			if RegistryIO.is_quoted_string(class_string)
			else AnyIcon.get_class_icon(class_string)
		)
		info_messages.append(INFO_MESSAGES.class_valid)
	else:
		class_restriction_line_edit.right_icon = AnyIcon.get_icon(&"MissingResource")
		_invalidate(info_messages, &"class_invalid")

	# Scan directory
	var scan_path := scan_directory_line_edit.text.strip_edges()
	if scan_path.is_empty():
		info_messages.append(INFO_MESSAGES.scan_empty)
	elif DirAccess.dir_exists_absolute(scan_path):
		info_messages.append(INFO_MESSAGES.scan_valid)
	else:
		_invalidate(info_messages, &"scan_invalid")

	# Indexed properties
	var properties: Array[String] = []
	var indexed_properties_string := indexed_properties_line_edit.text.strip_edges()
	if indexed_properties_string.is_empty():
		info_messages.append(INFO_MESSAGES.properties_none)
	else:
		properties.assign(indexed_properties_string.split(",", true))
		if properties.any(func(s: String) -> bool: return s.strip_edges().is_empty()):
			_invalidate(info_messages, &"properties_empty_prop")
		else:
			var class_props := _get_class_property_names(class_string) if is_class_valid else []
			var msgs_before := info_messages.size()
			for p: String in properties:
				if not class_props.has(p.strip_edges()):
					var msg := INFO_MESSAGES.properties_cant_verify.duplicate()
					msg[0] = tr(msg[0]).format({ "prop": p })
					info_messages.append(msg)
			if info_messages.size() == msgs_before:
				info_messages.append(INFO_MESSAGES.properties_valid)

	# Scan regex filters
	var regex_include := scan_regex_include_line_edit.text.strip_edges()
	if not regex_include.is_empty():
		if RegistryIO.is_valid_regex_pattern(regex_include):
			info_messages.append(INFO_MESSAGES.regex_include_valid)
		else:
			_invalidate(info_messages, &"regex_include_invalid")

	var regex_exclude := scan_regex_exclude_line_edit.text.strip_edges()
	if not regex_exclude.is_empty():
		if RegistryIO.is_valid_regex_pattern(regex_exclude):
			info_messages.append(INFO_MESSAGES.regex_exclude_valid)
		else:
			_invalidate(info_messages, &"regex_exclude_invalid")

	if _state == RegistryDialogState.REGISTRY_SETTINGS:
		_fill_info_label(info_messages)
		return

	# Registry file path
	var file_path := registry_path_line_edit.text.strip_edges()
	if file_path.is_empty():
		_invalidate(info_messages, &"filename_empty")
	elif file_path.get_extension().to_lower() not in RegistryIO.REGISTRY_FILE_EXTENSIONS:
		_invalidate(info_messages, &"extension_invalid")
	elif not RegistryIO.is_valid_registry_output_path(file_path):
		_invalidate(info_messages, &"path_invalid")
	elif ResourceLoader.exists(file_path):
		_invalidate(info_messages, &"path_already_used")
	else:
		info_messages.append(INFO_MESSAGES.path_available)

	_fill_info_label(info_messages)


func _invalidate(info_messages: Array[Array], key: StringName) -> void:
	get_ok_button().disabled = true
	info_messages.append(INFO_MESSAGES[key])


func _get_class_property_names(class_string: String) -> Array:
	if RegistryIO.is_quoted_string(class_string):
		return ClassUtils.get_class_property_names(load(RegistryIO.unquote(class_string)))
	return ClassUtils.get_class_property_names(class_string)


func _fill_info_label(info_messages: Array[Array]) -> void:
	info_label.text = ""
	for i in info_messages.size():
		if i != 0:
			info_label.newline()
			info_label.newline()
		var message: Array = info_messages[i]
		var text: String = message[0]
		var color: Color = message[1]
		info_label.push_color(color)
		info_label.append_text("• " + tr(text))
		info_label.pop()


func _open_file_dialog_as_class_restriction() -> void:
	_file_dialog.title = tr("Choose Custom Resource Script")
	_file_dialog.clear_filters()
	_file_dialog.add_filter("*.gd", "Scripts")
	_file_dialog_state = FileDialogState.CLASS_RESTRICTION
	_file_dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
	var restriction := class_restriction_line_edit.text
	if not restriction.is_empty() and RegistryIO.is_quoted_string(restriction):
		var path := RegistryIO.unquote(restriction)
		_file_dialog.current_dir = path.get_base_dir()
		_file_dialog.current_path = path.get_file()
	else:
		_file_dialog.current_dir = ""
		_file_dialog.current_path = ""
	_file_dialog.popup_file_dialog()


func _open_file_dialog_as_scan_directory() -> void:
	_file_dialog.title = tr("Choose Directory to Scan")
	_file_dialog_state = FileDialogState.SCAN_DIRECTORY
	_file_dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_DIR
	var scan_dir := scan_directory_line_edit.text
	var dir_exist := DirAccess.dir_exists_absolute(scan_dir)
	_file_dialog.current_dir = scan_dir if dir_exist else scan_dir.get_base_dir()
	_file_dialog.clear_filters()
	_file_dialog.popup_file_dialog()


func _open_file_dialog_as_registry_path() -> void:
	_file_dialog.title = tr("Choose Registry Location")
	_file_dialog.clear_filters()
	_file_dialog.add_filter("*.tres, *.res")
	_file_dialog_state = FileDialogState.REGISTRY_PATH
	_file_dialog.file_mode = EditorFileDialog.FILE_MODE_SAVE_FILE
	_file_dialog.current_dir = registry_path_line_edit.text.get_base_dir()
	_file_dialog.current_path = registry_path_line_edit.text.get_file()
	_file_dialog.popup_file_dialog()


func _edit_settings_and_rebuild_index() -> void:
	var err := RegistryIO.set_registry_settings(edited_registry, _build_settings())
	if err != OK:
		print_debug(error_string(err))

	err = RegistryIO.rebuild_property_index(edited_registry)
	if err != OK:
		print_debug(error_string(err))


func _on_about_to_popup() -> void:
	_validate_fields()


func _on_close_requested() -> void:
	hide()


func _on_canceled() -> void:
	hide()


func _on_confirmed() -> void:
	match _state:
		RegistryDialogState.NEW_REGISTRY:
			hide()
			var registry_path := registry_path_line_edit.text.strip_edges()
			var err := RegistryIO.create_registry_file(registry_path, _build_settings())
			if err != OK:
				print_debug(error_string(err))
				return
			var new_registry: Registry = load(registry_path)
			EditorInterface.edit_resource(new_registry)
			err = RegistryIO.rebuild_property_index(new_registry)
			if err != OK:
				print_debug(error_string(err))
		RegistryDialogState.REGISTRY_SETTINGS:
			var new_class_restriction := class_restriction_line_edit.text.strip_edges()
			if (
				new_class_restriction != edited_registry._class_restriction
				and RegistryIO.would_erase_entries(edited_registry, new_class_restriction)
			):
				new_restriction_confirmation_dialog.popup()
			else:
				hide()
				_edit_settings_and_rebuild_index()


func _on_class_restriction_line_edit_text_changed(_new_text: String) -> void:
	_validate_fields()


func _on_class_list_dialog_button_pressed() -> void:
	exclusive = false
	var class_restriction := class_restriction_line_edit.text
	EditorInterface.popup_create_dialog(
		_on_class_list_dialog_confirmed,
		&"Resource",
		class_restriction,
		tr("Choose Class Restriction"),
	)


func _on_class_list_dialog_confirmed(type_name: String) -> void:
	exclusive = true
	if not type_name:
		return

	if type_name.begins_with("res://") or type_name.begins_with("uid://"):
		type_name = '"%s"' % type_name

	class_restriction_line_edit.text = type_name
	_validate_fields()


func _on_class_filesystem_button_pressed() -> void:
	_open_file_dialog_as_class_restriction()


func _on_scan_directory_line_edit_text_changed(_new_text: String) -> void:
	_validate_fields()


func _on_scan_directory_filesystem_button_pressed() -> void:
	_open_file_dialog_as_scan_directory()


func _on_indexed_properties_line_edit_text_changed(_new_text: String) -> void:
	_validate_fields()


func _on_registry_path_line_edit_text_changed(_new_text: String) -> void:
	_validate_fields()


func _on_registry_path_filesystem_button_pressed() -> void:
	match _state:
		RegistryDialogState.NEW_REGISTRY:
			_open_file_dialog_as_registry_path()
		RegistryDialogState.REGISTRY_SETTINGS:
			var fs := EditorInterface.get_file_system_dock()
			fs.navigate_to_path(registry_path_line_edit.text)


func _on_file_dialog_file_selected(file: String) -> void:
	if _file_dialog_state == FileDialogState.CLASS_RESTRICTION:
		class_restriction_line_edit.text = '"%s"' % file
		_validate_fields()
	elif _file_dialog_state == FileDialogState.REGISTRY_PATH:
		registry_path_line_edit.text = file
		_validate_fields()


func _on_file_dialog_dir_selected(path: String) -> void:
	if _file_dialog_state == FileDialogState.SCAN_DIRECTORY:
		scan_directory_line_edit.text = path
		_validate_fields()


func _on_new_restriction_confirmation_dialog_confirmed() -> void:
	hide()
	_edit_settings_and_rebuild_index()


func _on_scan_regex_include_line_edit_text_changed(_new_text: String) -> void:
	_validate_fields()


func _on_scan_regex_exclude_line_edit_text_changed(_new_text: String) -> void:
	_validate_fields()


func _on_foldable_container_folding_changed(is_folded: bool) -> void:
	if is_folded:
		info_label.reset_size()
		reset_size()
