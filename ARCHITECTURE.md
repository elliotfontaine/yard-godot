<!--
SPDX-FileCopyrightText: 2025-2026, Elliot Fontaine <yard-godot@elliotfontaine.anonaddy.com>
SPDX-FileCopyrightText: 2026-present, YARD contributors (see AUTHORS.md)

SPDX-License-Identifier: MIT
-->

# YARD architecture

This document describes how the codebase is organized and the rules specific to each part of it. The contribution process and the conventions that apply to all code are in [CONTRIBUTING.md](CONTRIBUTING.md).

## Project structure

```r
addons/yard/
  plugin.gd                  # Plugin entry point
  registry.gd                # Runtime API (class_name Registry)
  Registry.cs                # C# wrapper
  editor_only/               # Editor-only code, not loaded at runtime
    namespace.gd             # Central import hub for all editor scripts
    registry_io.gd           # All Registry mutations (add, erase, sync, index)
    editor_inspector_plugin.gd
    editor_context_menu_plugin.gd
    editor_export_plugin.gd
    ui_scenes/               # Editor tab UI (scenes + scripts)
    classes/                 # Utility classes (DataTable, ClassUtils, Compat, FuzzySearch, cache...)
    assets/                  # Editor icons and images
    locale/                  # Translations (.po / .pot)
    shortcuts/               # Shortcut resources
test/
  project/test_project.godot # Strict project settings used by CI
example/                     # Example project for manual testing, including the Godomon dataset
```

The runtime surface is intentionally minimal: `registry.gd` and `Registry.cs` only. Everything else is editor-only and can be excluded from exported projects.

`Registry.cs` mirrors the public API of `registry.gd`. Any change to that API must be made in both files.

## Editor/runtime boundary

Nothing under `editor_only/` may be referenced from `registry.gd` or `Registry.cs`.

## `Registry` does not write itself

`RegistryIO` is the only writer. `Registry` exposes a read-only API at runtime. All mutations (add/erase/rename entries, rebuild property index, directory sync) go through `RegistryIO`, whose methods are all `static`, receive a `Registry` as their first argument, and call `ResourceSaver.save(registry)` before returning.

## Python-like imports via `Namespace`

Editor scripts preload `namespace.gd` rather than using direct paths. When adding a new editor utility (script or scene), register it there first.

```gdscript
# registry_table_view.gd
@tool
extends PanelContainer

const Namespace := preload("res://addons/yard/editor_only/namespace.gd")
const RegistryIO := Namespace.RegistryIO
const ClassUtils := Namespace.ClassUtils
const EditorThemeUtils := Namespace.EditorThemeUtils
const DataTable := Namespace.DataTable
const RegistryCacheData := Namespace.YardEditorCache.RegistryCacheData
```

Do not declare `class_name` on editor-only scripts. This avoids polluting Godot's user-facing class database.

## UI layer architecture

The core display loosely follows the [Model-View-Adapter](https://en.wikipedia.org/wiki/Model%E2%80%93view%E2%80%93adapter) pattern:

- **Model**: `Registry` — the resource holding entries and the property index.
- **Adapter**: `RegistryTableView` — translates registry entries into rows and column
  configs, and calls `RegistryIO` when a cell is edited. This is where most
  registry-specific UI logic lives.
- **View**: `DataTable` — a generic spreadsheet over a flat `Array[Array]` of
  `Variant` values. It has no knowledge of `Registry` or any YARD-specific logic.
  Keep it that way.

`RegistryEditor` sits above this as an application shell: it manages which
registries are open, handles file operations (open, close, recent), and owns the top
bar menus. It drives the MVA trio by setting `registry_table_view.current_registry`.

![Plugin UI architecture overview, highlighting the RegistryEditor, RegistryTableView and DataTable scenes](/etc/plugin_ui_architecture.png)

When working on a new feature, this layering tells you where to make the change:
registry display / editing logic belongs in `RegistryTableView`; spreadsheet rendering / cell editing
in `DataTable`; plugin-level operations (top-level menus, file I/O) in `RegistryEditor`.

## Column and cell types

`DataTable` never branches on value types. Type-specific behavior (drawing,
editing, sorting, filtering, tooltips) lives in the `CellType` scripts under
`classes/data_table/cell_types/`.

Each column is described by a `ColumnConfig`, built from the property's type and
export hint. To pick a cell type, `ColumnConfig` tries each script in
`CELL_TYPES_PRIORITY_LIST` and keeps the first one that matches. More specific
types come first in the list.

Cell type scripts are never instantiated: every method is `static`, and each
script overrides only the hooks it needs (`draw_cell()`, `create_editor()`,
`handle_input()`, `get_sort_key()`...). They stay stateless. Derived data
(parsed hint strings, enum maps) is memoized with `ColumnConfig.get_cached()`.
A cell type only produces a value: `DataTable` emits `cell_edited`, and
`RegistryTableView` writes it.

`DataTable` itself knows nothing about YARD, but cell types may.
`RegistryEntryCellType` reads the target registry through the runtime
`Registry` API. It must never call `RegistryIO`.

### Adding a cell type

1. Create `cell_types/<name>_cell_type.gd`, extending `cell_type.gd` by path.
2. Implement `matches()` and override only the methods you need.
3. Register the script in `namespace.gd`.
4. Add it to `CELL_TYPES_PRIORITY_LIST` in `column_config.gd`, before any more
   generic cell type that would also match its columns.
