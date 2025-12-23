@tool
extends EditorPlugin

const Namespace := preload("res://addons/yard/editor_only/namespace.gd")
const MainView := Namespace.MainView
const MAIN_VIEW_SCENE = Namespace.MAIN_VIEW_SCENE
const TRANSLATION_DOMAIN = Namespace.TRANSLATION_DOMAIN

var _main_view: MainView


func _enter_tree() -> void:
	if not Engine.is_editor_hint():
		return
	
	print("YARD - Yet Another Resource Database")
	var domain := TranslationServer.get_or_add_domain(TRANSLATION_DOMAIN)
	domain.add_translation(preload(Namespace.TRANSLATIONS.fr_FR))
	
	_main_view = MAIN_VIEW_SCENE.instantiate()
	EditorInterface.get_editor_main_screen().add_child(_main_view)
	_main_view.set_translation_domain(TRANSLATION_DOMAIN)
	_make_visible(false)


func _exit_tree() -> void:
	if is_instance_valid(_main_view):
		_main_view.queue_free()
	
	TranslationServer.remove_domain(TRANSLATION_DOMAIN)


func _has_main_screen() -> bool:
	return true


func _make_visible(visible: bool) -> void:
	if is_instance_valid(_main_view):
		_main_view.visible = visible


func _handles(object: Object) -> bool:
	return object is Registry


func _edit(object: Object) -> void:
	if not object:
		return
	var edited_registry := object as Registry
	_main_view.open_registry(edited_registry)


func _get_plugin_name() -> String:
	return "YARD"


func _get_plugin_icon() -> Texture2D:
	# will do for now
	return EditorInterface.get_editor_theme().get_icon(
		"ResourcePreloader", "EditorIcons"
	)
