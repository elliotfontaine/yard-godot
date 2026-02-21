@tool
extends EditorPlugin

const Namespace := preload("res://addons/yard/editor_only/namespace.gd")
const WindowWrapper := Namespace.WindowWrapper
const WINDOW_WRAPPER_SCENE = Namespace.WINDOW_WRAPPER_SCENE
const TRANSLATION_DOMAIN = Namespace.TRANSLATION_DOMAIN
const FILESYSTEM_CREATE_CONTEXT_MENU_PLUGIN = Namespace.FILESYSTEM_CREATE_CONTEXT_MENU_PLUGIN

var _window_wrapper: WindowWrapper
var _filesystem_create_context_menu_plugin: EditorContextMenuPlugin


func _enter_tree() -> void:
	if not Engine.is_editor_hint():
		return

	print("YARD - Yet Another Resource Database")
	var domain := TranslationServer.get_or_add_domain(TRANSLATION_DOMAIN)
	domain.add_translation(preload(Namespace.TRANSLATIONS.fr_FR))

	_filesystem_create_context_menu_plugin = FILESYSTEM_CREATE_CONTEXT_MENU_PLUGIN.new(_filesystem_create_context_menu_plugin_callback)
	add_context_menu_plugin(EditorContextMenuPlugin.CONTEXT_SLOT_FILESYSTEM_CREATE, _filesystem_create_context_menu_plugin)

	_window_wrapper = WINDOW_WRAPPER_SCENE.instantiate()
	EditorInterface.get_editor_main_screen().add_child(_window_wrapper)
	_window_wrapper.set_translation_domain(TRANSLATION_DOMAIN)
	_make_visible(false)


func _exit_tree() -> void:
	if is_instance_valid(_window_wrapper):
		_window_wrapper.queue_free()

	if is_instance_valid(_filesystem_create_context_menu_plugin):
		remove_context_menu_plugin(_filesystem_create_context_menu_plugin)

	TranslationServer.remove_domain(TRANSLATION_DOMAIN)


func _has_main_screen() -> bool:
	return true


func _make_visible(visible: bool) -> void:
	if is_instance_valid(_window_wrapper):
		_window_wrapper.visible = visible


func _handles(object: Object) -> bool:
	return object is Registry


func _edit(object: Object) -> void:
	if not object:
		return
	var edited_registry := object as Registry
	_window_wrapper.registry_editor.open_registry(edited_registry)


func _get_plugin_name() -> String:
	return "Registry"


func _get_plugin_icon() -> Texture2D:
	# will do for now
	return EditorInterface.get_editor_theme().get_icon(
		"ResourcePreloader",
		"EditorIcons",
	)


func _filesystem_create_context_menu_plugin_callback(context: Array) -> void:
	var dir: String = context[0]
	var nrd: ConfirmationDialog = _window_wrapper.registry_editor.new_registry_dialog

	nrd.popup_with_state(nrd.RegistryDialogState.NEW_REGISTRY, dir)
