# Contributing to YARD

Thanks for your interest in contributing! This guide covers setup, project structure, and the conventions to follow.

## Getting started

YARD is a Godot 4.5+ project. Development should target Godot 4.5, since forward-compatibility is easier to maintain than backward-compatibility. Test your changes on later versions before submitting.

1. Clone the repository.
2. Open the project in **Godot 4.5**.
3. Enable the YARD plugin in **Project > Project Settings > Plugins** if it isn't already active.

The following plugins are recommended for a comfortable development experience (install them separately via the Asset Library or their repository):

- **[GDQuest GDScript Formatter](https://github.com/GDQuest/GDScript-formatter)**: formats GDScript on save.
- **[Plugin Reloader](https://github.com/kenyoni-software/godot-addons)**: reloads plugins without going to Project Settings.
- **[Editor Theme Explorer](https://github.com/YuriSizov/godot-editor-theme-explorer)**: browse editor theme constants, colors, and icons.
- **[Editor Debugger](https://github.com/Zylann/godot_editor_debugger_plugin)**: inspect the editor's own scene tree at runtime.

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
    ui_scenes/               # Editor tab UI (scenes + scripts)
    classes/                 # Utility classes (ClassUtils, FuzzySearch, cache...)
test/
  unit/                      # GUT test files
  fixtures/                  # Test resources and registry files
example/                     # Example scene for manual testing
```

The runtime surface is intentionally minimal: `registry.gd` and `Registry.cs` only. Everything else is editor-only and can be excluded from exported projects.

## Architecture notes

### Editor/runtime boundary

Nothing under `editor_only/` may be referenced from `registry.gd` or `Registry.cs`.

### `Registry` does not write itself

`RegistryIO` is the only writer. `Registry` exposes a read-only API at runtime. All mutations (add/erase/rename entries, rebuild property index, directory sync) go through `RegistryIO`, whose methods are all `static` and call `ResourceSaver.save(registry)` before returning.

### Python-like imports via `Namespace`

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

### UI layer architecture

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

## Code conventions

- All editor-side scripts carry the `@tool` annotation.
- GDScript uses **strict typing** throughout. The project enables `untyped_declaration` and `inference_on_variant` warnings.
- Keep `RegistryIO` methods `static`; they receive a `Registry` as their first argument.
- Connect signals in `_ready`, not from the Scene view.

## Submitting changes

- Keep commits focused on a single concern.
- Do not commit theme-related changes. These can sneak in when saving UI scenes such as `registry_table_view.tscn` or `registry_editor.tscn`, which run inside the editor.
- Write commit messages following [Conventional Commits](https://www.conventionalcommits.org/).
- Do not add **Co-Authored-By** trailers for coding agents (Claude Code, Copilot, etc.). Commits must be authored by the human contributor only.
- Open a pull request against `main`. Describe what changed and why, and link any related issue.

## Good first issues

Issues tagged [`good first issue`](https://github.com/elliotfontaine/yard-godot/issues?q=is%3Aissue+is%3Aopen+label%3A%22good+first+issue%22) are a good starting point if you are new to the codebase.
