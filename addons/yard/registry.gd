@tool
@icon("res://addons/yard/editor_only/assets/FileList.svg")
class_name Registry
extends Resource
## A lightweight registry mapping resource UIDs to human-readable string IDs.
##
## Maps each resource UID (for example, [code]"uid://dqtv77mng5dyh"[/code]) to a readable string ID
## (for example, [code]"enemy_skeleton"[/code]) and vice versa.
## Provides helper methods to check, resolve, and load registered resources, either
## synchronously or asynchronously using threaded loading.
##
## [codeblock]
## const ENEMY_REGISTRY: Registry = preload("res://data/enemy_registry.tres")
##
## @onready var enemy_sprite: Sprite2D = %EnemySprite
##
##
## func _on_show_skeleton_button_pressed():
##     var skeleton: Enemy = ENEMY_REGISTRY.load_entry(&"skeleton")
##     enemy_sprite.texture = skeleton.creature_sprite
## [/codeblock][br]
##
## Instances are immutable at runtime. Entries cannot be added/removed
## via script and the [Registry] must be edited using the dedicated tab of the
## editor.[br][br]
##
## [img width=1200]res://addons/yard/editor_only/assets/ui_example.png[/img]

@warning_ignore_start("unused_private_class_variable")
@export_storage var _class_restriction: StringName = &""
@export_storage var _scan_directory: String = ""
@export_storage var _recursive_scan: bool = false
@warning_ignore_restore("unused_private_class_variable")

@export_storage var _uids_to_string_ids: Dictionary[StringName, StringName]
@export_storage var _string_ids_to_uids: Dictionary[StringName, StringName]


func _init() -> void:
	if not Engine.is_editor_hint():
		_uids_to_string_ids.make_read_only()
		_string_ids_to_uids.make_read_only()


## Returns the number of entries in the registry. Empty registries always return [code]0[/code].
## See also [method Registry.is_empty].
func size() -> int:
	return _uids_to_string_ids.size()


## Returns [code]true[/code] if the registry contains no entries.
## See also [method Registry.size].
func is_empty() -> bool:
	return _uids_to_string_ids.is_empty()


## Returns [code]true[/code] if the given [param id] exists in the registry.[br][br]
##
## The [param id] may be either a string ID (for example, [code]&"enemy_skeleton"[/code])
## or a UID (for example, [code]&"uid://dqtv77mng5dyh"[/code]).
func has(id: StringName) -> bool:
	return get_uid(id) != &""


## Returns [code]true[/code] if the given UID is present in the registry.
##
## The [param uid] must start with [code]uid://[/code].
func has_uid(uid: StringName) -> bool:
	return _uids_to_string_ids.has(uid)


## Returns [code]true[/code] if the given string ID is present in the registry.
func has_string_id(string_id: StringName) -> bool:
	return _string_ids_to_uids.has(string_id)


## Returns an [Array] of all registered UIDs.
##
## Each entry is a [StringName] in the form [code]&"uid://..."[/code].
func get_all_uids() -> Array[StringName]:
	return _uids_to_string_ids.keys()


## Returns an [Array] of all registered string IDs.
func get_all_string_ids() -> Array[StringName]:
	return _string_ids_to_uids.keys()


## Resolves any identifier (string ID or UID) to its canonical UID form.[br][br]
##
## If [param id] is already a registered UID, it is returned unchanged.
## If [param id] is a registered string ID, returns the corresponding UID.
## Returns an empty [StringName] when [param id] cannot be resolved.
func get_uid(id: StringName) -> StringName:
	if id.is_empty():
		return &""

	if id.begins_with("uid://"):
		return id if _uids_to_string_ids.has(id) else &""

	var string_id := StringName(id)
	return _string_ids_to_uids.get(string_id, &"")


## Returns the string ID associated with the given UID.
##
## Returns an empty [StringName] if [param uid] is not found in the registry.
func get_string_id(uid: StringName) -> StringName:
	if _uids_to_string_ids.has(uid):
		return _uids_to_string_ids[uid]
	else:
		return &""


## Loads the resource associated with [param id] (string ID or UID) and returns it.
## Returns [code]null[/code] if the entry does not exist or cannot be loaded.[br][br]
##
## [param type_hint] and [param cache_down] are passed down to
## [method ResourceLoader.load].
func load_entry(
		id: StringName,
		type_hint: String = "",
		cache_mode: ResourceLoader.CacheMode = ResourceLoader.CACHE_MODE_REUSE,
) -> Resource:
	var uid := get_uid(id)
	if uid == &"" or not ResourceLoader.exists(uid):
		return null
	else:
		return ResourceLoader.load(uid, type_hint, cache_mode)


## Loads all registered resources in a blocking manner. Returns a dictionary
## mapping string IDs to their loaded [Resource] instances.
## Missing or invalid entries are skipped.[br][br]
##
## [param type_hint] and [param cache_down] are passed down to
## [method ResourceLoader.load].
func load_all_blocking(
		type_hint: String = "",
		cache_mode: ResourceLoader.CacheMode = ResourceLoader.CACHE_MODE_REUSE,
) -> Dictionary[StringName, Resource]:
	var dict: Dictionary[StringName, Resource] = { }

	for uid in get_all_uids():
		if not uid == &"" and ResourceLoader.exists(uid):
			dict[_uids_to_string_ids[uid]] = ResourceLoader.load(
				uid,
				type_hint,
				cache_mode,
			)

	return dict


## Requests threaded loading for all entries and returns a [Registry.RegistryLoadTracker].
## The returned tracker can be used to monitor progress, inspect statuses,
## and retrieve loaded resources as they become available.[br][br]
## See also [method ResourceLoader.load_threaded_request].
func load_all_threaded_request(
		type_hint: String = "",
		use_sub_threads: bool = false,
		cache_mode := ResourceLoader.CACHE_MODE_REUSE,
) -> RegistryLoadTracker:
	var tracker := RegistryLoadTracker.new()

	for string_id: StringName in get_all_string_ids():
		var uid := get_uid(string_id)
		tracker.__uids[string_id] = uid
		tracker.__resources[string_id] = null
		var err := ResourceLoader.load_threaded_request(uid, type_hint, use_sub_threads, cache_mode)
		if err == OK:
			tracker.__requested[string_id] = true
			tracker.__status[string_id] = ResourceLoader.THREAD_LOAD_IN_PROGRESS
		else:
			tracker.__requested[string_id] = false
			tracker.__status[string_id] = ResourceLoader.THREAD_LOAD_INVALID_RESOURCE

	return tracker


## Loading tracker used with [method Registry.load_all_threaded_request]
##
## Returned by [method Registry.load_all_threaded_request].
## Provides information about asynchronous resource loading.[br][br]
## All its [Dictionary] properties use resources String IDs as keys :[br][br]
##  - [member progress] is the overall load progress ([code]0.0[/code]–[code]1.0[/code]).[br]
##  - [member status] matches an entry string ID to its current [enum ResourceLoader.ThreadLoadStatus].[br]
##  - [member resources] holds loaded [Resource] objects as they become ready.[br]
##  - [member uids] matches an entry string ID to its UID.[br]
##  - [member requested] tells if the entry was successfully requested through [method ResourceLoader.load_threaded_request].[br][br]
##
## [b]Note:[/b] Accessors automatically poll and update internal loading states before returning.
class RegistryLoadTracker extends RefCounted:
	var progress: float:
		get:
			_poll()
			return __progress

	var uids: Dictionary[StringName, StringName]:
		get:
			return __uids.duplicate()

	var requested: Dictionary[StringName, bool]:
		get:
			return __requested.duplicate()

	var status: Dictionary[StringName, ResourceLoader.ThreadLoadStatus]:
		get:
			_poll()
			return __status.duplicate()

	var resources: Dictionary[StringName, Resource]:
		get:
			_poll()
			return __resources.duplicate()

	var __progress: float = 0.0
	var __uids: Dictionary[StringName, StringName]
	var __requested: Dictionary[StringName, bool]
	var __status: Dictionary[StringName, ResourceLoader.ThreadLoadStatus]
	var __resources: Dictionary[StringName, Resource]


	func _poll() -> void:
		var n_res_requested := 0
		var n_res_loaded := 0.0 # allow fractional loading progress
		for uid: String in __uids.values():
			var res_progress := []
			if not __requested[uid]:
				continue
			n_res_requested += 1
			__status[uid] = ResourceLoader.load_threaded_get_status(uid, res_progress)
			n_res_loaded += res_progress[0]
			if (
				__status[uid] == ResourceLoader.THREAD_LOAD_LOADED
				and __resources[uid] == null
			):
				__resources[uid] = ResourceLoader.load_threaded_get(uid)
		__progress = n_res_loaded / n_res_requested
