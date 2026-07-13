<!--
SPDX-FileCopyrightText: 2025-2026, Elliot Fontaine <yard-godot@elliotfontaine.anonaddy.com>
SPDX-FileCopyrightText: 2026-present, YARD contributors (see AUTHORS.md)

SPDX-License-Identifier: MIT
-->

# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this project is

YARD (Yet Another Resource Database) is a **Godot 4 editor plugin** for managing collections of resources through a table-based editor UI and a lightweight runtime API. It targets Godot 4.5+ and supports both GDScript and C#.

Plugin entry point: `addons/yard/plugin.gd`
Runtime API class: `addons/yard/registry.gd` (`class_name Registry`)
C# wrapper: `addons/yard/Registry.cs`

## Development

This is a Godot 4 project. Development, testing, and all iteration happen inside the Godot editor. There is no CLI build or test command — open `project.godot` in Godot 4.5+ to work on it.

Tests use the **GUT** (Godot Unit Testing) framework. Test files live in `test/unit/` and are run from within the Godot editor via the GUT plugin.

The project also uses the **GDQuest GDScript Formatter** plugin (`addons/GDQuest_GDScript_formatter`) and the **Plugin Reloader** plugin (`addons/kenyoni/plugin_reloader`).

## Architecture

### Editor vs. Runtime split

All editor-only code lives under `addons/yard/editor_only/` and is **never shipped to players**. The runtime surface is just `addons/yard/registry.gd` (plus `Registry.cs` for C# users) — a single `Resource` subclass with no editor dependencies.

- `addons/yard/editor_only/namespace.gd` — central import hub; all editor scripts `preload` from here rather than using direct paths.
- `addons/yard/editor_only/registry_io.gd` — all mutations to a `Registry` resource (add/erase/rename entries, sync from directories, rebuild property index, save). The `Registry` class itself is read-only at runtime; `RegistryIO` is the only writer.
- `addons/yard/editor_only/ui_scenes/` — the editor tab UI (scenes + scripts). `registry_editor.gd` is the root container; `registry_table_view.gd` is the spreadsheet.
- `addons/yard/editor_only/classes/` — utility classes: `class_utils.gd` (reflection helpers for native classes and GDScript), `yard_editor_cache.gd` (per-registry editor state persisted to `.godot/plugins/yard/`), `fuzzy_search.gd`, theme helpers, etc.

### Registry data model

A `Registry` `.tres` file stores:

- `_uids_to_string_ids` / `_string_ids_to_uids` — bidirectional UID ↔ string ID map
- `_property_index` — nested dictionary baked in the editor: `property → value → set of string IDs`
- Scan settings (class restrictions, scan directories, rulesets) as `_scan_rulesets: Array[Dictionary]`

The `_version` field tracks the registry format version (current: `2`). `RegistryIO.get_registry_settings()` handles reading both v1 and v2 formats.

### Scan rulesets

A registry has one default `RegistryScanRuleset` and zero or more additional rulesets (stored in `RegistryIO.RegistryScanRuleset`). Additional rulesets declare `override_properties` — only those properties override the default; the rest inherit. `RegistrySettings.get_compiled_rulesets()` returns fully-resolved rulesets ready for iteration.

### Class restriction system

Class restrictions accept three forms:

- Native class name: `"Resource"`, `"Node2D"`
- Script global class name: `"Enemy"`, `"Item"`
- Quoted script path: `'"res://scripts/my_type.gd"'`

`ClassUtils.is_class_of()` handles all three forms, walking both the GDScript inheritance chain and the native `ClassDB` chain.

### Property index

Properties support dot-notation paths for nested resources (e.g. `"weapon.rarity"`). `RegistryIO._resolve_property_path()` resolves these at index-rebuild time. The index is a nested dictionary and is queried at runtime without loading resources.

### C# wrapper

`Registry.cs` wraps the GDScript `Registry` resource via `Godot.Resource` reflection (`Call`/`Get`). It provides a generic `Registry<TResource>` that mirrors the GDScript API with C# naming conventions.

## Git commits

Commits must be authored by the human contributor only. Do not add `Co-Authored-By` trailers.

## Code conventions

- All editor-side scripts are decorated `@tool`.
- GDScript uses strict typing throughout (`untyped_declaration` and `inference_on_variant` warnings are enabled in `project.godot`).
- Editor scripts import via `Namespace` rather than direct `preload` paths.
- `RegistryIO` methods are all `static`; they take a `Registry` argument and call `ResourceSaver.save(registry)` before returning.
- The `filter_by_*` methods on `Registry` are deprecated in favour of `filter()` / `where()`.
