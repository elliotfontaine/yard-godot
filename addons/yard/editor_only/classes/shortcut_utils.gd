extends Object

const Namespace := preload("res://addons/yard/editor_only/namespace.gd")
const Compat := Namespace.Compat

## In which section of the Shortcuts tab should our custom ones be saved. Using the plugin's name
## is appropriate.
const _SECTION := "yard"

## Default primary value for our shortcuts. Make sure these are platform-agnostic to account for
## MacOS users (`InputEventKey.command_or_control_autoremap` should be true)
const _SHORTCUT_DEFAULTS: Dictionary = {
	"toggle_registries_panel": "res://addons/yard/editor_only/shortcuts/toggle_registries_panel.tres",
	"new_registry": "res://addons/yard/editor_only/shortcuts/new_registry.tres",
	"reopen_closed_registry": "res://addons/yard/editor_only/shortcuts/reopen_closed_registry.tres",
	"close_registry": "res://addons/yard/editor_only/shortcuts/close_registry.tres",
	"move_registry_up": "res://addons/yard/editor_only/shortcuts/move_registry_up.tres",
	"move_registry_down": "res://addons/yard/editor_only/shortcuts/move_registry_down.tres",
	"delete_entries": "res://addons/yard/editor_only/shortcuts/delete_entries.tres",
	"duplicate_entries": "res://addons/yard/editor_only/shortcuts/duplicate_entries.tres",
	"copy_cell_clipboard": "res://addons/yard/editor_only/shortcuts/copy_cell_clipboard.tres",
	"cut_cell_clipboard": "res://addons/yard/editor_only/shortcuts/cut_cell_clipboard.tres",
	"paste_cell_clipboard": "res://addons/yard/editor_only/shortcuts/paste_cell_clipboard.tres",
	"select_all_entries": "res://addons/yard/editor_only/shortcuts/select_all_entries.tres",
}


static func get_action_shortcut(action: String) -> Shortcut:
	if Compat.is_engine_version_equal_or_newer(4, 6):
		return EditorInterface.get_editor_settings().get_shortcut("%s/%s" % [_SECTION, action])
	else:
		return load(_SHORTCUT_DEFAULTS[action])


## Should be called each time the plugin loads
## (see footnote in `EditorSettings.add_shortcut` docstring for more details)
static func register_shortcuts() -> void:
	if Compat.is_engine_version_equal_or_newer(4, 6):
		for action: String in _SHORTCUT_DEFAULTS:
			var path := "%s/%s" % [_SECTION, action]
			if not EditorInterface.get_editor_settings().has_shortcut(path):
				var shortcut: Shortcut = load(_SHORTCUT_DEFAULTS[action])
				EditorInterface.get_editor_settings().add_shortcut(path, shortcut)
