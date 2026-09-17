# SPDX-FileCopyrightText: 2025-2026, Elliot Fontaine <yard-godot@elliotfontaine.anonaddy.com>
# SPDX-FileCopyrightText: 2026-present, YARD contributors (see AUTHORS.md)
#
# SPDX-License-Identifier: MIT
extends EditorExportPlugin

const Namespace := preload("res://addons/yard/editor_only/namespace.gd")
const RegistryIO := Namespace.RegistryIO


func _get_name() -> String:
	return "YARD - Yet Another Resource Database"


func _begin_customize_resources(_platform: EditorExportPlatform, _features: PackedStringArray) -> bool:
	return true


func _get_customization_configuration_hash() -> int:
	return 0


func _customize_resource(resource: Resource, _path: String) -> Resource:
	if resource is not Registry:
		return null

	var registry := resource as Registry
	RegistryIO.sync_from_scan_directories(registry)
	RegistryIO.rebuild_property_index(registry)

	# Required to sync the in-memory registry in the editor from its file
	ResourceLoader.load(registry.resource_path, "", ResourceLoader.CACHE_MODE_REPLACE)

	return registry
