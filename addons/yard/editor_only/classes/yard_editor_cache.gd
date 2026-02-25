@tool
extends Object

const _BASE_DIR := "res://.godot/plugins/yard/registries/"
const _SECTION_GENERAL := "general"
const _SECTION_TABLE := "table"
const _CACHE_VERSION := 1
const DISABLED_BY_DEFAULT_PROPERTIES: Array[StringName] = [
	&"script",
	&"resource_local_to_scene",
	&"resource_path",
	&"resource_name",
]


class RegistryCacheData:
	const Namespace := preload("res://addons/yard/editor_only/namespace.gd")
	const YardEditorCache := Namespace.YardEditorCache
	var version: int = _CACHE_VERSION
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
		DirAccess.make_dir_recursive_absolute(_BASE_DIR)
		return cfg.save(YardEditorCache._get_path(_registry))


static func load_or_default(registry: Registry) -> RegistryCacheData:
	var data := RegistryCacheData.new(registry)
	var cfg := ConfigFile.new()
	if cfg.load(_get_path(registry)) != OK:
		data.save()
		return data

	data.version = cfg.get_value(_SECTION_GENERAL, "version", data.version)
	if data.version != _CACHE_VERSION:
		_update_cache_format(data, cfg)
		data.version = _CACHE_VERSION
		data.save()
		return data

	data.disabled_columns = cfg.get_value(_SECTION_TABLE, "disabled_columns", data.disabled_columns)
	data.uid_column_width = cfg.get_value(_SECTION_TABLE, "uid_column_width", data.uid_column_width)
	data.string_id_column_width = cfg.get_value(_SECTION_TABLE, "string_id_column_width", data.string_id_column_width)
	data.property_columns_widths = cfg.get_value(_SECTION_TABLE, "property_columns_widths", data.property_columns_widths)
	return data


static func erase(registry: Registry) -> void:
	var path := _get_path(registry)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


static func _update_cache_format(_data: RegistryCacheData, _old_cfg: ConfigFile) -> void:
	# This function can be used to migrate old cache formats to new ones when _CACHE_VERSION is incremented.
	# For now, since this is the first version, we don't need to do anything here.
	# var old_version: int = cfg.get_value(_SECTION_GENERAL, "version", 0)
	#  if old_version < 2:
	#     _migrate_v1_to_v2(data, cfg)
	# if old_version < 3:
	#     _migrate_v2_to_v3(data, cfg)
	# etc.
	pass


static func _get_path(registry: Registry) -> String:
	var uid := ResourceUID.path_to_uid(registry.resource_path)
	var uid_str := uid.trim_prefix("uid://")
	return _BASE_DIR + uid_str + ".cfg"
