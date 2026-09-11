# SPDX-FileCopyrightText: 2025-2026, Elliot Fontaine <yard-godot@elliotfontaine.anonaddy.com>
# SPDX-FileCopyrightText: 2026-present, YARD contributors (see AUTHORS.md)
#
# SPDX-License-Identifier: MIT

extends Object
## Engine version helpers for backward/forward compatibility


## Return true if the current engine version is equal or newer compared to the values provided.
static func is_engine_version_equal_or_newer(major: int, minor: int = 0, patch: int = 0) -> bool:
	var engine_ver: Dictionary = Engine.get_version_info()
	return engine_ver.major >= major and engine_ver.minor >= minor and engine_ver.patch >= patch


## Return true if the current engine version is older compared to the values provided.
static func is_engine_version_older(major: int, minor: int = 0, patch: int = 0) -> bool:
	return not is_engine_version_equal_or_newer(major, minor, patch)
