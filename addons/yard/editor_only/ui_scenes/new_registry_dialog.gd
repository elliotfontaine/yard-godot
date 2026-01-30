@tool
extends ConfirmationDialog

const SUCCESS_COLOR = Color(0.45, 0.95, 0.5)
const WARNING_COLOR = Color(0.83, 0.78, 0.62)
const ERROR_COLOR = Color(1, 0.47, 0.42)

@onready var class_restriction_line_edit: LineEdit = %ClassRestrictionLineEdit
@onready var class_list_dialog_button: Button = %ClassListDialogButton
@onready var class_filesystem_button: Button = %ClassFilesystemButton
@onready var path_line_edit: LineEdit = %PathLineEdit
@onready var path_filesystem_button: Button = %PathFilesystemButton
@onready var scan_directory_line_edit: LineEdit = %ScanDirectoryLineEdit
@onready var scan_directory_filesystem_button: Button = %ScanDirectoryFilesystemButton
@onready var info_label: RichTextLabel = %InfoLabel


func _ready() -> void:
	if not Engine.is_editor_hint():
		return
	hide()
	class_list_dialog_button.icon = get_theme_icon(&"ClassList", &"EditorIcons")
	class_filesystem_button.icon = get_theme_icon(&"Folder", &"EditorIcons")
	path_filesystem_button.icon = get_theme_icon(&"Folder", &"EditorIcons")
	scan_directory_filesystem_button.icon = get_theme_icon(&"Folder", &"EditorIcons")

	info_label.text = ""
	info_label.push_color(SUCCESS_COLOR)
	info_label.append_text("• Bullet point 1 (success)")
	info_label.pop()
	info_label.newline()
	info_label.newline()
	info_label.push_color(ERROR_COLOR)
	info_label.append_text("• Bullet point 2 (error)")
	info_label.pop()


func _on_close_requested() -> void:
	hide()


func _on_canceled() -> void:
	hide()


func _on_confirmed() -> void:
	print_debug("Unimplemented")
