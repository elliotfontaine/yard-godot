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
const INFO_MESSAGES: Dictionary[StringName, Array] = {
	# --- Class restriction ---
	&"class_valid": ["Class/script is a Resource subclass.", SUCCESS_COLOR],
	&"class_invalid": ["Invalid class/script. Expected a Resource subclass (built-in, class_name, or script path).", ERROR_COLOR],
	&"class_empty": ["No class filter, all Resource files will be accepted to the registry.", WARNING_COLOR],

	# --- Scan directory ---
	&"scan_valid": ["Scan directory valid. Will watch for new Resources…", SUCCESS_COLOR],
	&"scan_invalid": ["Scan directory invalid. Pick an existing directory.", ERROR_COLOR],
	&"scan_empty": ["No scan directory, resources auto-discovery is disabled.", DEFAULT_COLOR],

	# --- Indexed properties ---
	&"properties_none": ["Indexed properties are optional. Separate multiple properties with commas.", DEFAULT_COLOR],
	&"properties_valid": ["All properties found on the specified resource class.", SUCCESS_COLOR],
	&"properties_empty_prop": ["Empty property name detected. Remove extra commas.", ERROR_COLOR],
	&"properties_cant_verify": ["Property '{prop}' may not exist on the resource class.", WARNING_COLOR],

	# --- Registry path ---
	&"path_available": ["Will create a new registry file.", SUCCESS_COLOR],
	&"path_invalid": ["Filename is invalid", ERROR_COLOR],
	&"extension_invalid": ["Invalid extension.", ERROR_COLOR],
	&"filename_empty": ["Filename is empty.", ERROR_COLOR],
	&"path_already_used": ["Registry file already exists.", ERROR_COLOR],
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
@onready var recursive_scan_check_box: CheckBox = %RecursiveScanCheckBox
@onready var registry_path_line_edit: LineEdit = %RegistryPathLineEdit
@onready var registry_path_filesystem_button: Button = %RegistryPathFilesystemButton
@onready var indexed_properties_line_edit: LineEdit = %IndexedPropertiesLineEdit
@onready var info_label: RichTextLabel = %InfoLabel


func _ready() -> void:
	if not Engine.is_editor_hint():
		return

	about_to_popup.connect(_on_about_to_popup)
	_file_dialog = EditorFileDialog.new()
	_file_dialog.confirmed.connect(_on_file_dialog_file_selected)
	_file_dialog.dir_selected.connect(_on_file_dialog_dir_selected)
	add_child(_file_dialog)
	hide()


func popup_with_state(state: RegistryDialogState, dir: String = "") -> void:
	_state = state
	if state == RegistryDialogState.NEW_REGISTRY:
		title = "Create Registry"
		ok_button_text = "Create"
		class_restriction_line_edit.text = ""
		scan_directory_line_edit.text = ""
		recursive_scan_check_box.button_pressed = false
		indexed_properties_line_edit.text = ""
		registry_path_line_edit.editable = true
		registry_path_line_edit.focus_mode = Control.FOCUS_ALL
		registry_path_line_edit.text = dir + "new_registry.tres"
		registry_path_filesystem_button.icon = AnyIcon.get_icon(&"Folder")
		registry_path_filesystem_button.tooltip_text = ""
	elif edited_registry and state == RegistryDialogState.REGISTRY_SETTINGS:
		title = "Edit Registry Settings"
		ok_button_text = "Save"
		class_restriction_line_edit.text = edited_registry._class_restriction
		scan_directory_line_edit.text = edited_registry._scan_directory
		recursive_scan_check_box.button_pressed = edited_registry._recursive_scan
		indexed_properties_line_edit.text = ",".join(edited_registry._property_index.keys())
		registry_path_line_edit.text = edited_registry.resource_path
		registry_path_line_edit.editable = false
		registry_path_line_edit.focus_mode = Control.FOCUS_NONE
		registry_path_filesystem_button.icon = AnyIcon.get_icon(&"ShowInFileSystem")
		registry_path_filesystem_button.tooltip_text = "Show in filesystem."
	else:
		return

	popup()


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
					msg[0] = msg[0].format({ "prop": p })
					info_messages.append(msg)
			if info_messages.size() == msgs_before:
				info_messages.append(INFO_MESSAGES.properties_valid)

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
		info_label.append_text("• " + text)
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
	var err := RegistryIO.edit_registry_settings(
		edited_registry,
		class_restriction_line_edit.text.strip_edges(),
		scan_directory_line_edit.text.strip_edges(),
		recursive_scan_check_box.button_pressed,
		indexed_properties_line_edit.text.strip_edges(),
	)
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
			var err := RegistryIO.create_registry_file(
				registry_path,
				class_restriction_line_edit.text.strip_edges(),
				scan_directory_line_edit.text.strip_edges(),
				recursive_scan_check_box.button_pressed,
				indexed_properties_line_edit.text.strip_edges(),
			)
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
	print_rich("Please upvote the following proposal to see it implemented :")
	print_rich(
		"[color=SKY_BLUE][url]",
		"https://github.com/godotengine/godot-proposals/discussions/14041",
		"[/url][/color]",
	)


func _on_class_filesystem_button_pressed() -> void:
	_open_file_dialog_as_class_restriction()


func _on_scan_directory_line_edit_text_changed(_new_text: String) -> void:
	_validate_fields()


func _on_scan_directory_filesystem_button_pressed() -> void:
	_open_file_dialog_as_scan_directory()


func _on_recursive_scan_check_box_pressed() -> void:
	pass


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


func _on_file_dialog_file_selected() -> void:
	var path: String = _file_dialog.current_path
	if _file_dialog_state == FileDialogState.CLASS_RESTRICTION:
		class_restriction_line_edit.text = '"%s"' % path
		_validate_fields()
	elif _file_dialog_state == FileDialogState.REGISTRY_PATH:
		registry_path_line_edit.text = path
		_validate_fields()


func _on_file_dialog_dir_selected(path: String) -> void:
	if _file_dialog_state == FileDialogState.SCAN_DIRECTORY:
		scan_directory_line_edit.text = path
		_validate_fields()


func _on_new_restriction_confirmation_dialog_confirmed() -> void:
	hide()
	_edit_settings_and_rebuild_index()
