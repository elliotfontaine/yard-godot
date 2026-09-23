# SPDX-FileCopyrightText: 2025-2026, Elliot Fontaine <yard-godot@elliotfontaine.anonaddy.com>
# SPDX-FileCopyrightText: 2026-present, YARD contributors (see AUTHORS.md)
#
# SPDX-License-Identifier: MIT

@tool
extends EditorPlugin

const Namespace := preload("res://addons/yard/editor_only/namespace.gd")
const Compat := Namespace.Compat
const YardLogger := Namespace.YardLogger
const ShortcutUtils := Namespace.ShortcutUtils
const YardSettings := Namespace.YardSettings
const RegistryEditor := Namespace.RegistryEditor
const TRANSLATIONS := Namespace.TRANSLATIONS
const REGISTRY_EDITOR_SCENE := Namespace.REGISTRY_EDITOR_SCENE
const FILESYSTEM_CREATE_CONTEXT_MENU_PLUGIN := Namespace.FILESYSTEM_CREATE_CONTEXT_MENU_PLUGIN
const EDITOR_INSPECTOR_PLUGIN := Namespace.EDITOR_INSPECTOR_PLUGIN
const EDITOR_EXPORT_PLUGIN := Namespace.EDITOR_EXPORT_PLUGIN

var _registry_editor: RegistryEditor
var _filesystem_create_context_menu_plugin: EditorContextMenuPlugin
var _editor_inspector_plugin: EditorInspectorPlugin
var _editor_export_plugin: EditorExportPlugin
var _cached_plugin_name: String
var _dock: Control #EditorDock


func _init() -> void:
	if not Engine.is_editor_hint():
		return

	YardLogger.info("Yet Another Resource Database. Plugin loaded.")

	var editor_domain := TranslationServer.get_or_add_domain(&"godot.editor")
	for locale: String in TRANSLATIONS.keys():
		editor_domain.add_translation(load(TRANSLATIONS[locale]))

	ShortcutUtils.register_shortcuts()

	YardSettings.register_settings()


func _enter_tree() -> void:
	if not Engine.is_editor_hint():
		return

	_filesystem_create_context_menu_plugin = FILESYSTEM_CREATE_CONTEXT_MENU_PLUGIN.new(
		_filesystem_create_context_menu_plugin_callback
	)
	add_context_menu_plugin(
		EditorContextMenuPlugin.CONTEXT_SLOT_FILESYSTEM_CREATE,
		_filesystem_create_context_menu_plugin,
	)

	_editor_inspector_plugin = EDITOR_INSPECTOR_PLUGIN.new()
	add_inspector_plugin(_editor_inspector_plugin)

	_editor_export_plugin = EDITOR_EXPORT_PLUGIN.new()
	add_export_plugin(_editor_export_plugin)

	_registry_editor = REGISTRY_EDITOR_SCENE.instantiate()

	if Compat.is_engine_version_equal_or_newer(4, 8):
		_dock = ClassDB.instantiate(&"EditorDock") as Node
		_dock.set(&"title", _get_plugin_name())
		_dock.set(&"dock_icon", preload("res://addons/yard/editor_only/assets/yard.svg"))
		_dock.set(
			&"default_slot",
			ClassDB.class_get_integer_constant(&"EditorDock", &"DOCK_SLOT_MAIN_SCREEN"),
		)
		_dock.add_child(_registry_editor)
		call(&"add_dock", _dock)
	else:
		EditorInterface.get_editor_main_screen().add_child(_registry_editor)
		_make_visible(false)

	_reimport_icons()


func _exit_tree() -> void:
	if is_instance_valid(_dock):
		_dock.queue_free()
		call(&"remove_dock", _dock)
	elif is_instance_valid(_registry_editor):
		_registry_editor.queue_free()

	if is_instance_valid(_filesystem_create_context_menu_plugin):
		remove_context_menu_plugin(_filesystem_create_context_menu_plugin)

	if is_instance_valid(_editor_inspector_plugin):
		remove_inspector_plugin(_editor_inspector_plugin)

	if is_instance_valid(_editor_export_plugin):
		remove_export_plugin(_editor_export_plugin)


func _has_main_screen() -> bool:
	if Compat.is_engine_version_equal_or_newer(4, 8):
		return false
	else:
		return true


func _make_visible(visible: bool) -> void:
	if is_instance_valid(_registry_editor):
		_registry_editor.visible = visible
		_registry_editor._update_registries_itemlist()
		_registry_editor.registry_table_view.update_view()


func _handles(object: Object) -> bool:
	return object is Registry


func _edit(object: Object) -> void:
	if not object:
		return
	var edited_registry := object as Registry
	_registry_editor.open_registry(edited_registry)


func _build() -> bool:
	_registry_editor.rescan_known_registries()
	_registry_editor.reindex_known_registries()
	return true


func _get_plugin_name() -> String:
	if not _cached_plugin_name:
		_cached_plugin_name = tr("Registry")
	return _cached_plugin_name


func _get_plugin_icon() -> Texture2D:
	return preload("res://addons/yard/editor_only/assets/yard.svg")


# Force reimport of icons if it doesn't match the editor scale
func _reimport_icons() -> void:
	var icon: CompressedTexture2D = load("res://addons/yard/editor_only/assets/github_icon.svg")
	var scale := EditorInterface.get_editor_scale()
	if float(icon.get_width()) != scale * 16:
		YardLogger.warn(
			"YARD - Editor scale changed, reimporting icons. This might throw an error. Disregard."
		)
		EditorInterface.get_resource_filesystem().reimport_files(
			PackedStringArray(
				[
					"res://addons/yard/editor_only/assets/github_icon.svg",
					"res://addons/yard/editor_only/assets/yard.svg",
				],
			),
		)


func _filesystem_create_context_menu_plugin_callback(context: Array) -> void:
	var dir: String = context[0]
	var nrd := _registry_editor.new_registry_dialog

	nrd.popup_with_state(nrd.RegistryDialogState.NEW_REGISTRY, dir)
