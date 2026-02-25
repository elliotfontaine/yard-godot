@tool
extends Object

const _BASE_DIR := "res://.godot/plugins/yard/"
const _REGISTRIES_DIR := _BASE_DIR + "registries/"
const _STATE_FILE := _BASE_DIR + "editor_state.cfg"
const _SECTION_GENERAL := "general"
const _SECTION_TABLE := "table"
const _SECTION_RECENT := "recent"
const _REGISTRY_CACHE_VERSION := 1
const _EDITOR_STATE_VERSION := 1
const _MAX_RECENT := 10
const DISABLED_BY_DEFAULT_PROPERTIES: Array[StringName] = [
	&"script",
	&"resource_local_to_scene",
	&"resource_path",
	&"resource_name",
]


class RegistryCacheData:
	const Namespace := preload("res://addons/yard/editor_only/namespace.gd")
	const YardEditorCache := Namespace.YardEditorCache
	var version: int = _REGISTRY_CACHE_VERSION
	var disabled_columns: Array[StringName] = DISABLED_BY_DEFAULT_PROPERTIES.duplicate()
	var uid_column_width: float = 200.0
	var string_id_column_width: float = 200.0
	var property_columns_widths: Dictionary[StringName, float] = { }

	var _registry: Registry


	func _init(registry: Registry) -> void:
		_registry = registry


	func save() -> Error:
		var cfg := ConfigFile.new()
		cfg.set_value(_SECTION_GENERAL, "version", version)
		cfg.set_value(_SECTION_TABLE, "disabled_columns", disabled_columns)
		cfg.set_value(_SECTION_TABLE, "uid_column_width", uid_column_width)
		cfg.set_value(_SECTION_TABLE, "string_id_column_width", string_id_column_width)
		cfg.set_value(_SECTION_TABLE, "property_columns_widths", property_columns_widths)
		DirAccess.make_dir_recursive_absolute(_REGISTRIES_DIR)
		return cfg.save(YardEditorCache._get_registry_cache_path(_registry))


static func load_or_default(registry: Registry) -> RegistryCacheData:
	var data := RegistryCacheData.new(registry)
	var cfg := ConfigFile.new()
	if cfg.load(_get_registry_cache_path(registry)) != OK:
		data.save()
		return data

	data.version = cfg.get_value(_SECTION_GENERAL, "version", data.version)
	if data.version != _REGISTRY_CACHE_VERSION:
		_update_cache_format(data, cfg)
		data.version = _REGISTRY_CACHE_VERSION
		data.save()
		return data

	data.disabled_columns = cfg.get_value(_SECTION_TABLE, "disabled_columns", data.disabled_columns)
	data.uid_column_width = cfg.get_value(_SECTION_TABLE, "uid_column_width", data.uid_column_width)
	data.string_id_column_width = cfg.get_value(_SECTION_TABLE, "string_id_column_width", data.string_id_column_width)
	data.property_columns_widths = cfg.get_value(_SECTION_TABLE, "property_columns_widths", data.property_columns_widths)
	return data


static func erase(registry: Registry) -> void:
	var path := _get_registry_cache_path(registry)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


static func _update_cache_format(_data: RegistryCacheData, _old_cfg: ConfigFile) -> void:
	# Migrate old cache formats here when _REGISTRY_CACHE_VERSION is incremented.
	# var old_version: int = cfg.get_value(_SECTION_GENERAL, "version", 0)
	# if old_version < 2:
	#     _migrate_v1_to_v2(data, cfg)
	pass


static func _get_registry_cache_path(registry: Registry) -> String:
	var uid := ResourceUID.path_to_uid(registry.resource_path)
	var uid_str := uid.trim_prefix("uid://")
	return _REGISTRIES_DIR + uid_str + ".cfg"


static func add_recent_registry(registry: Registry) -> void:
	var uid := ResourceUID.path_to_uid(registry.resource_path)
	var list := get_recent_registry_uids()
	list.erase(uid)
	list.push_front(uid)
	if list.size() > _MAX_RECENT:
		list.resize(_MAX_RECENT)
	_save_recent(list)


static func clear_recent_registries() -> void:
	_save_recent([])


static func get_recent_registry_uids() -> Array[String]:
	var cfg := ConfigFile.new()
	if cfg.load(_STATE_FILE) != OK:
		return []
	var raw: Array = cfg.get_value(_SECTION_RECENT, "uids", [])
	var result: Array[String] = []
	result.assign(raw)
	return result


static func _save_recent(uids: Array[String]) -> void:
	var cfg := ConfigFile.new()
	cfg.set_value(_SECTION_RECENT, "version", _EDITOR_STATE_VERSION)
	cfg.set_value(_SECTION_RECENT, "uids", uids)
	DirAccess.make_dir_recursive_absolute(_BASE_DIR)
	cfg.save(_STATE_FILE)
