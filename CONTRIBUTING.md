<!--
SPDX-FileCopyrightText: 2025-2026, Elliot Fontaine <yard-godot@elliotfontaine.anonaddy.com>
SPDX-FileCopyrightText: 2026-present, YARD contributors (see AUTHORS.md)

SPDX-License-Identifier: MIT
-->

# Contributing to YARD

Thanks for your interest in contributing! This guide covers how to work on YARD: setup, the contribution process, and the conventions that apply to all code. How the code is organized, and the rules specific to each part of it, are in [ARCHITECTURE.md](ARCHITECTURE.md).

## Good first issues

Issues tagged [`good first issue`](https://github.com/elliotfontaine/yard-godot/issues?q=is%3Aissue+is%3Aopen+label%3A%22good+first+issue%22) are a good starting point if you are new to the codebase.

## Getting started

1. Clone the repository.
2. Open the project in the **latest stable release of Godot**.
3. Enable the YARD plugin in **Project > Project Settings > Plugins** if it isn't already active.

The following plugins are recommended for a comfortable development experience (install them separately via the Asset Library or their repository):

- **[GDQuest GDScript Formatter](https://github.com/GDQuest/GDScript-formatter)**: formats GDScript on save.
- **[Plugin Reloader](https://github.com/kenyoni-software/godot-addons)**: reloads plugins without going to Project Settings.
- **[Editor Theme Explorer](https://github.com/YuriSizov/godot-editor-theme-explorer)**: browse editor theme constants, colors, and icons.
- **[Editor Debugger](https://github.com/Zylann/godot_editor_debugger_plugin)**: inspect the editor's own scene tree at runtime.

## Godot version support

Development targets the latest stable Godot release. You don't need to install older versions to contribute.

Backward compatibility is checked in two places:

- **While iterating**: CI loads the plugin on every Godot version in its matrix (see [Testing and CI](#testing-and-ci)).
- **Before a release**: older versions are tested manually.

When an API differs between Godot versions, branch on the engine version with the helpers in `Compat` (`editor_only/classes/compat.gd`).

```gdscript
func _ready() -> void:
  var is_4_7_or_newer := Compat.is_engine_version_equal_or_newer(4, 7)
  var download_icon := &"AssetStore" if is_4_7_or_newer else &"AssetLib"
  install_button.icon = get_theme_icon(download_icon, &"EditorIcons")
```

## Code conventions

- GDScript uses **strict typing** throughout.
- The `untyped_declaration` warning is enabled in `project.godot` as a warning only, so it won't block you in the editor. CI treats it and most other warnings as errors (see [Testing and CI](#testing-and-ci)), so fix them before pushing.
- Connect signals in `_ready`, not from the Scene view.
- Log through `YardLogger` (`info()`, `warn()`, `error()`), not `push_error()` or `push_warning()`. Called from editor scripts, those report a location in Godot's source instead of yours (`ERROR: core/variant/variant_utility.cpp:1023 - this is my error text`). `YardLogger` prints the caller's `file:line`.
- Follow the architectural rules in [ARCHITECTURE.md](ARCHITECTURE.md): the editor/runtime boundary, `RegistryIO` as the only writer, imports through `Namespace`, `Registry.cs` kept in sync with `registry.gd`, and a generic `DataTable`.

## Translations

The editor UI is translated into several languages (`addons/yard/editor_only/locale/`). If your change adds or modifies user-facing text:

1. Wrap strings set from code in `tr()`. Text set in scenes is translated automatically.
2. Add each new string by hand to `plugin.pot`, with a `#:` comment pointing to the file that uses it and an empty `msgstr`:

   ```po
   #: addons/yard/editor_only/ui_scenes/registry_table_view.gd
   msgid "Auto (registry file location)"
   msgstr ""
   ```

3. Add the same entry to every `.po` file, with its translation in `msgstr`. In `en_US.po`, `msgstr` repeats the `msgid`.

You don't need to speak every language. An LLM can do a good job here: give it the whole `.po` file for the language, not only the new strings, and ask it to stay consistent with the existing translations and their conventions (terminology, tone, capitalization).

## Testing and CI

There is no automated test suite as of now. Test your changes by hand in the editor. The [`example/`](example/) folder has registries to try things on (`example/godomon/data/`) and a runtime scene (`example/scenes/`).

CI runs two workflows on each push and pull request. Check their results on your PR:

- [`load_plugin.yml`](.github/workflows/load_plugin.yml) loads the plugin on every Godot version in its matrix. It uses [`test/project/test_project.godot`](test/project/test_project.godot), which raises most GDScript warnings to errors, and fails on any error or warning Godot prints.
- [`reuse_compliance.yml`](.github/workflows/reuse_compliance.yml) checks that every file declares its copyright and license (see [Licensing](#licensing-reuse)).

## Licensing (REUSE)

YARD follows the [REUSE](https://reuse.software/) specification: every file must declare its copyright and license. CI checks this on each push and pull request.

When you add a file, either:

- **Give it an SPDX header**, for files that support comments (GDScript, C#, Markdown, YAML...). Copy it from an existing file:

  ```gdscript
  # SPDX-FileCopyrightText: 2025-2026, Elliot Fontaine <yard-godot@elliotfontaine.anonaddy.com>
  # SPDX-FileCopyrightText: 2026-present, YARD contributors (see AUTHORS.md)
  #
  # SPDX-License-Identifier: MIT
  ```

- **Or declare it in [`REUSE.toml`](REUSE.toml)**, for files that can't carry a header (images, Godot-managed files...). Scenes and resources under `addons/yard/` and `example/`, as well as `.import` and `.uid` files, are already covered by glob patterns. Images must be listed explicitly.

Third-party assets keep their original copyright and license. If that license isn't in [`LICENSES/`](LICENSES/) yet, add it (`reuse download <SPDX-ID>`).

You can run the check locally with `reuse lint`. You'll have to install the [reuse tool](https://codeberg.org/fsfe/reuse-tool).

## Opening issues or PRs

- Please use the templates provided on GitHub, as they help ensure you provide all the necessary information.
- Please write them yourself, even if English isn't your first language. Nobody wants to talk to a LLM while thinking they're talking to a person.

## Submitting changes

- Keep commits focused on a single concern.
- Do not commit theme-related changes. These can sneak in when saving UI scenes such as `registry_table_view.tscn` or `registry_editor.tscn`, which run inside the editor.
- Write commit messages following [Conventional Commits](https://www.conventionalcommits.org/).
- The same goes for the **PR title**, which matters most: pull requests are squash-merged, so the title becomes the commit on `main` and, through [git-cliff](https://git-cliff.org/), the changelog entry. Example: `fix: use lexicographic comparison for Godot version check`.
- Do not edit [CHANGELOG.md](CHANGELOG.md). It is generated from the commit history then manually curated by maintainers.
- Do not add **Co-Authored-By** trailers for coding agents (Claude Code, Copilot, etc.). Commits must be authored by the human contributor only.
- Add your name to [AUTHORS.md](AUTHORS.md) (alphabetical list).
- Open a pull request against `main`. Describe what changed and why, and link any related issue.
