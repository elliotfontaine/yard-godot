<!--
SPDX-FileCopyrightText: 2025-2026, Elliot Fontaine <yard-godot@elliotfontaine.anonaddy.com>
SPDX-FileCopyrightText: 2026-present, YARD contributors (see AUTHORS.md)

SPDX-License-Identifier: CC0-1.0
-->

# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/2.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Allow browsing sub-resource properties as a table by @elliotfontaine in [#151](https://github.com/elliotfontaine/yard-godot/pull/151)
- Backport to Godot 4.4.1 by @elliotfontaine in [#143](https://github.com/elliotfontaine/yard-godot/pull/143)
- Support Godot 4.8dev4 by @francoisdlt in [#123](https://github.com/elliotfontaine/yard-godot/pull/123)
- Make editor shortcuts configurable by @elliotfontaine in [#127](https://github.com/elliotfontaine/yard-godot/pull/127)
- Add a multiline text editor to the table for `@export_multiline` properties by @elliotfontaine in [#121](https://github.com/elliotfontaine/yard-godot/pull/121)
- Support `Registry.PROPERTY_HINT_CUSTOM` columns with a dropdown editor by @elliotfontaine in [#120](https://github.com/elliotfontaine/yard-godot/pull/120)
- Add a bitflags editor to the table by @elliotfontaine in [#119](https://github.com/elliotfontaine/yard-godot/pull/119)
- Add a StringName editor to the table by @elliotfontaine in [#116](https://github.com/elliotfontaine/yard-godot/pull/116)
- Add rich tooltips for color, resource, dict and array cells by @elliotfontaine in [#109](https://github.com/elliotfontaine/yard-godot/pull/109)
- Allow hiding the UID and String ID columns by @elliotfontaine in [#102](https://github.com/elliotfontaine/yard-godot/pull/102)
- Freeze arbitrary columns and add per-column hide/freeze menu by @elliotfontaine in [#101](https://github.com/elliotfontaine/yard-godot/pull/101)
- Support undo/redo for property value edits by @elliotfontaine in [#94](https://github.com/elliotfontaine/yard-godot/pull/94)
- Allow duplicating registry entries from the table view by @elliotfontaine in [#84](https://github.com/elliotfontaine/yard-godot/pull/84)

### Changed

- Reduce progress bar contrast when using the modern editor theme by @elliotfontaine
- Add directory picker to Add Entry footer by @elliotfontaine in [#145](https://github.com/elliotfontaine/yard-godot/pull/145)
- Remember Add Entry field per registry by @elliotfontaine in [#144](https://github.com/elliotfontaine/yard-godot/pull/144)
- Scan and index registries before run/export instead of on every filesystem change by @elliotfontaine in [#141](https://github.com/elliotfontaine/yard-godot/pull/141)
- Strip leading/trailing whitespace from new entry string IDs by @elliotfontaine in [#118](https://github.com/elliotfontaine/yard-godot/pull/118)

### Fixed

- Allow export groups with a name prefix in registry resources by @elliotfontaine in [#153](https://github.com/elliotfontaine/yard-godot/pull/153)
- Keep class restriction working after script file moves by @elliotfontaine in [#138](https://github.com/elliotfontaine/yard-godot/pull/138)
- Repair RegistryLoadTracker and add example scene to test it by @elliotfontaine in [#137](https://github.com/elliotfontaine/yard-godot/pull/137)
- Stop row filtering from throwing an error by @elliotfontaine in [#117](https://github.com/elliotfontaine/yard-godot/pull/117)
- Prevent error when selecting a color in the color editor by @elliotfontaine in [#115](https://github.com/elliotfontaine/yard-godot/pull/115)
- Improve cell text ellipsis performance by @elliotfontaine in [#114](https://github.com/elliotfontaine/yard-godot/pull/114)
- Keep table filter state after editing a property by @elliotfontaine in [#98](https://github.com/elliotfontaine/yard-godot/pull/98)

### New Contributors

- @francoisdlt made their first contribution in [#123](https://github.com/elliotfontaine/yard-godot/pull/123)
- @Guihurt made their first contribution in [#134](https://github.com/elliotfontaine/yard-godot/pull/134)

## [1.2.0] - 2026-05-19

### Added

- Open subresource in inspector on cell selection by @elliotfontaine in [#80](https://github.com/elliotfontaine/yard-godot/pull/80)
- Add `Registry.get_string_id_of()` for reverse resource lookup by @elliotfontaine in [#75](https://github.com/elliotfontaine/yard-godot/pull/75)
- Allow adding multiple entries quickly via keyboard by @Mar0Lard in [#69](https://github.com/elliotfontaine/yard-godot/pull/69)
- Support horizontal scrolling via mouse wheel in table view by @elliotfontaine in [#55](https://github.com/elliotfontaine/yard-godot/pull/55)
- Add `filter()` and `where()` to Registry API, deprecate old filtering methods by @elliotfontaine in [#50](https://github.com/elliotfontaine/yard-godot/pull/50)
- Add registry 'rulesets' with advanced scan features by @skison in [#48](https://github.com/elliotfontaine/yard-godot/pull/48)
- Add specific error messages for add-entry failures by @elliotfontaine
- Add resource thumbnail (when available) for path cells by @elliotfontaine in [#40](https://github.com/elliotfontaine/yard-godot/pull/40)
- Add advanced scan options (auto, remove unlisted, regex filters) by @elliotfontaine in [#38](https://github.com/elliotfontaine/yard-godot/pull/38)
- Add C# wrapper class by @Verfeon in [#36](https://github.com/elliotfontaine/yard-godot/pull/36)
- Allow indexing by inner object property by @elliotfontaine in [#29](https://github.com/elliotfontaine/yard-godot/pull/29)
- Add a progress bar editor to the table for range properties by @elliotfontaine in [#26](https://github.com/elliotfontaine/yard-godot/pull/26)
- Add dropdown popup editor for enum cells by @elliotfontaine in [#23](https://github.com/elliotfontaine/yard-godot/pull/23)

### Changed

- Warn when scan directory is set to project root (`res://`) by @elliotfontaine in [#82](https://github.com/elliotfontaine/yard-godot/pull/82)
- Make `Registry.get_string_id()` idempotent by @elliotfontaine
- Create resource files inline from Add Entry by @elliotfontaine in [#66](https://github.com/elliotfontaine/yard-godot/pull/66)
- Improve property column ordering and add parent-first display option by @elliotfontaine in [#53](https://github.com/elliotfontaine/yard-godot/pull/53)
- Show enum labels in collection cells by @elliotfontaine in [#45](https://github.com/elliotfontaine/yard-godot/pull/45)
- **tweak:** Move Rescan button before the Reindex button in topbar by @elliotfontaine
- Right-align numeric cells (int, float) by @elliotfontaine
- Display resource filename in resource and collection cells by @elliotfontaine in [#41](https://github.com/elliotfontaine/yard-godot/pull/41)
- Clarify unsaved resource error log with remediation steps by @elliotfontaine in [#35](https://github.com/elliotfontaine/yard-godot/pull/35)
- Enhance logging format for entry property edits by @elliotfontaine

### Fixed

- Allow selecting the first entry in @export_custom dropdown by @elliotfontaine in [#74](https://github.com/elliotfontaine/yard-godot/pull/74)
- Refresh resource picker when class restriction changes by @elliotfontaine in [#73](https://github.com/elliotfontaine/yard-godot/pull/73)
- Skip 'Remove Unlisted' when no scan directory is configured by @elliotfontaine in [#71](https://github.com/elliotfontaine/yard-godot/pull/71)
- Allow deleting/reassigning entries with invalid UID by @elliotfontaine in [#70](https://github.com/elliotfontaine/yard-godot/pull/70)
- Use nearest filter for pixel art textures in registry table by @elliotfontaine in [#64](https://github.com/elliotfontaine/yard-godot/pull/64)
- Improve plugin UI consistency with the Godot editor by @elliotfontaine
- Unlocalized cell editor strings (color picker, file dialog) due to overridden defaults by @elliotfontaine
- Resource cell click failed to open quick load dialog in non-English locales due to node name translation by @elliotfontaine
- Add missing i18n and l10n for registry settings input tabs by @elliotfontaine
- Show more descriptive "Registry Settings" label in dialog title for non-English locales by @elliotfontaine
- Contrast was too high when using "Classic" editor theme by @elliotfontaine
- Progress bar rendered in wrong column with `or_less` hint by @elliotfontaine in [#49](https://github.com/elliotfontaine/yard-godot/pull/49)
- Prevent res:// scan directory from being stripped to res:/ by @elliotfontaine
- Use editor accent color for StringID column by @elliotfontaine
- Add missing uid file for `Registry.cs` wrapper by @elliotfontaine
- Missing format version in registry `.tres` files by @elliotfontaine
- Don't try to use non-2D Texture resources as their own thumbnail by @elliotfontaine
- Get thumbnails for filepath cells without loading the underlying resource by @elliotfontaine
- Do not match partial resource paths against include filter by @elliotfontaine
- Always left-align header text by @elliotfontaine
- Quote string values in entry property edit logs by @elliotfontaine
- Add en_US locale to prevent fallback to project's `internationalization/locale/fallback` by @elliotfontaine in [#39](https://github.com/elliotfontaine/yard-godot/pull/39)
- Do not scan directory on registry selection, only on first opening by @elliotfontaine
- Prevent copypasting from/to invalid cells by @elliotfontaine
- Keep menu shortcuts in sync with registry state by @elliotfontaine
- Pressing Enter on checkbox cell now toggles it by @elliotfontaine
- Support string enums and implicit int values in enum cell rendering by @elliotfontaine

### New Contributors

- @Mar0Lard made their first contribution in [#69](https://github.com/elliotfontaine/yard-godot/pull/69)
- @skison made their first contribution in [#48](https://github.com/elliotfontaine/yard-godot/pull/48)
- @Verfeon made their first contribution in [#36](https://github.com/elliotfontaine/yard-godot/pull/36)

## [1.1.0] - 2026-03-07

### Added

- **l10n:** Add Polish and Turkish translations by @elliotfontaine
- **l10n:** Add French, Spanish, Brazilian Portuguese, German, Italian, Simplified Chinese and Russian translations by @elliotfontaine
- Add shortcuts for `Registry Settings`, `Reindex`, and `Toggle Files Panel` by @elliotfontaine
- Add custom inspector editor with enum-like dropdown for registry ids by @elliotfontaine in [#15](https://github.com/elliotfontaine/yard-godot/pull/15)
- Add support for C#-defined resource scripts by @Cer0reZ in [#4](https://github.com/elliotfontaine/yard-godot/pull/4)

### Changed

- Trigger cell edit on Enter key by @elliotfontaine
- **i18n:** Make the editor plugin UI fully translatable by @elliotfontaine
- Inform users that script paths in class restriction must be quoted by @elliotfontaine in [#12](https://github.com/elliotfontaine/yard-godot/pull/12)
- Implement class restriction selection dialog by @elliotfontaine in [#9](https://github.com/elliotfontaine/yard-godot/pull/9)

### Fixed

- Resolve UIDs to file paths in table path editor by @elliotfontaine
- Disable 'inspect resource' item in context menu for empty resource cells by @elliotfontaine
- Prevent add entry resource picker from clearing on file save by @elliotfontaine
- Adapt quick load button detection for Godot 4.6 by @elliotfontaine
- Preserve row or cell selection after table refresh by @elliotfontaine
- Render table color editor at top level to prevent clipping by @elliotfontaine
- Add 'metadata/\_custom_type_script' to disabled by default columns by @elliotfontaine
- Properly load registry on creation and avoid uid cache race condition by @elliotfontaine
- Keyboard shortcuts not adapting to platform (macOS vs Windows/Linux) by @elliotfontaine in [#20](https://github.com/elliotfontaine/yard-godot/pull/20)
- Update resource picker base type handling for script-based class restrictions by @elliotfontaine in [#18](https://github.com/elliotfontaine/yard-godot/pull/18)
- Handle script path return from popup_create_dialog in Godot 4.6 by @elliotfontaine in [#16](https://github.com/elliotfontaine/yard-godot/pull/16)
- Populate line edits on file double-click, not only on "Confirm" by @elliotfontaine in [#14](https://github.com/elliotfontaine/yard-godot/pull/14)

### New Contributors

- @Cer0reZ made their first contribution in [#4](https://github.com/elliotfontaine/yard-godot/pull/4)

## [1.0.1] - 2026-03-02

### Fixed

- Prevent duplicate error messages for invalid UIDs by @elliotfontaine
- Properly handle path at setup for the "new registry" dialog by @elliotfontaine
- Make the EditorContextMenuPlugin use our custom icon instead of the ResourcePreloader icon by @elliotfontaine
- Make scrollbars offset be based on editor scale by @elliotfontaine
- Drop deleted registry UIDs from history cache by @elliotfontaine
- When creating a new registry, values in the "indexed properties" field were ignored by @elliotfontaine
- Parent and siblings classes could be added to a registry with script path class restriction by @elliotfontaine
- Handle class identity for unnamed scripts by recursively checking base scripts by @elliotfontaine
- Table was hidden when searching on column yielded no result by @elliotfontaine

## [1.0.0] - 2026-02-26

### Added

- Add custom project icon by @elliotfontaine
- Add license file (MIT) by @elliotfontaine
- Add README.md window using Markdown label support by @elliotfontaine
- Add support for tracking opened registries between Godot editor sessions by @elliotfontaine
- Add reindex button to topbar by @elliotfontaine
- Add public method to Registry to get all indexed properties by @elliotfontaine
- Allow reducing column width past text size and add text truncation for better readability by @elliotfontaine
- Allow users to set indexed properties from the new/edit registry dialog by @elliotfontaine
- Add a property index and add filtering methods to Registry API by @elliotfontaine
- Allow (un)freezing id columns from menu by @elliotfontaine
- Add floating window behavior (part 1) by @elliotfontaine
- Allow copy-pasting between int and float cells, and from int/float to string cells by @elliotfontaine
- Add shortcuts for Edit menu items (topbar and contextual) by @elliotfontaine
- Add button to open the reference documentation for the Registry class by @elliotfontaine
- Add a 'has()' to Registry API, taking either uid or string_id as parameter by @elliotfontaine
- Add cut/copy/paste for cells, with dedicated cliboard by @elliotfontaine
- Add support for enum cells (only view, no custom cell editor) by @elliotfontaine
- Add context menu item to open selected cell resource in inspector by @elliotfontaine
- Add logic to the Edit menu items by @elliotfontaine
- Add entries context menu (partial implementation) by @elliotfontaine
- Allow drag-and-drop of folders to the registry by @elliotfontaine
- Add a bottom bar with an "Add Entry" resource picker and a button to hide the list of registries by @elliotfontaine
- Allow changing an entry's UID by @elliotfontaine
- Add path editor with file dialog by @elliotfontaine
- Add resource editor with "Quick Load" dialog by @elliotfontaine
- Allow changing Registry entries' string ids by @elliotfontaine
- Allow user to toggle columns visibility by @elliotfontaine
- Add Edit and Columns menu buttons, and Registry Setting button (unimplemented) by @elliotfontaine
- Add custom class icon for Registry resources by @elliotfontaine
- Add floating window button (unimplemented) by @elliotfontaine
- Add button to report issues on github by @elliotfontaine
- Add button to refresh table view by @elliotfontaine
- Add custom editor for color cells by @elliotfontaine
- Allow dropping mix-typed resources and only keep valid ones by @elliotfontaine
- Allow dropping resources to a registry from the editor filesystem by @elliotfontaine
- Add new registry dialog (skeleton) by @elliotfontaine
- Add context menu item in filesystem dock, used to create a registry by @elliotfontaine
- Add shortcuts matching the Script Editor ones by @elliotfontaine
- **editor:** Add i18n support and French translation by @elliotfontaine
- **ui:** Add dynamic table view scaffold (not yet bound to registry) by @elliotfontaine
- Add barebore Registry custom resource by @elliotfontaine
- Add ui skeleton by @elliotfontaine

### Changed

- Improve ui preview in Registry docs by @elliotfontaine
- Improve display of collections (array and dict) by @elliotfontaine
- Implement "open recent" logic in file menu by @elliotfontaine
- Increase grid contrast by @elliotfontaine
- Implement RegistryCacheData for managing editor settings and column widths by @elliotfontaine
- Improve icon design by @elliotfontaine
- Better resolve registry icon in itemlist by @elliotfontaine
- Use custom icon for plugin, use DPITexture for all icons by @elliotfontaine
- **tweak:** Make horizontal scroll stop before frozen columns by @elliotfontaine
- Freeze first 2 columns (String ID and UID) by @elliotfontaine
- Show confirmation dialog when the new class restriction would exclude entries from the registry by @elliotfontaine
- Improve context-based toggle of Edit menu items by @elliotfontaine
- Show tip about drag and dropping resources by @elliotfontaine
- **tweak:** Vertical slider does not overlap with table header by @elliotfontaine
- Show class restriction icon in registries list by @elliotfontaine
- Implement directory scan by @elliotfontaine
- Update Add Entry resource picker when class restriction is changed by @elliotfontaine
- Improve context-based disabling of File menu items by @elliotfontaine
- Create new registry using filesystem context menu, at current directory by @elliotfontaine
- Handle pan gesture by @elliotfontaine
- Show previews and show rows based on scroll after refresh by @elliotfontaine
- Ensure selected cell can be seen by @elliotfontaine
- **ui:** Properly show selected cell by @elliotfontaine
- **tweak:** Make the row selection overlay less bright by @elliotfontaine
- Display invalid uids in red when viewing registry by @elliotfontaine
- Make the first 2 columns more distinct visually by @elliotfontaine
- Describe runtime API for Registry by @elliotfontaine
- Implement 'Registry Settings' dialog (recycle 'New Registry' dialog) by @elliotfontaine
- Display class icon in New Registry dialog by @elliotfontaine
- Implement new registry dialog logic by @elliotfontaine
- Sync table entries to their real resource counterparts by @elliotfontaine
- Show preview (rather than a stringified value) for resource and color properties by @elliotfontaine
- Display registry entries content (as string) by @elliotfontaine
- Implement most menu options for the registry list by @elliotfontaine
- Unify registries list UX with Godot open scripts list by @elliotfontaine
- Make DynamicTable follow the Godot editor theme by @elliotfontaine
- Make YARD a main screen plugin by @elliotfontaine

### Fixed

- Last column could not be resized by @elliotfontaine
- Ignore unused variable warning for Registry version tag by @elliotfontaine
- Update editor_icon_button external resource uid in dependant scene files by @elliotfontaine
- Reimport icons on editor scale change by @elliotfontaine
- Scrolling to last columns not working after toggling visibility or disabling id column freeze by @elliotfontaine
- Refactor sort logic to suppress errors when ordering resources by @elliotfontaine
- Use correct key mask (ctrl/cmd) on Windows for cut, copy, etc by @elliotfontaine
- Do not draw table if data is empty, even if there are columns by @elliotfontaine
- Hide "make floating" button since it's unimplemented by @elliotfontaine
- Make path editor for DynamicTable more reliable by @elliotfontaine
- Improve path logic for "new registry" file dialogs by @elliotfontaine
- Increase icon size in header by @elliotfontaine
- Fix HTML header in readme by @elliotfontaine
- Specify dictionary inner types for criteria parameter in `filter_by_values` function by @elliotfontaine
- Don't draw cell content behind scrollbar by @elliotfontaine
- Convert icon colors with editor theme by @elliotfontaine
- Actually, use Texture2D for icons, with `scale_with_editor_scale` set to true by @elliotfontaine
- Allow multiple types for resource editor (ResourcePicker), for exemple BaseMaterial3D & ShaderMaterial for PrimitiveMesh.material by @elliotfontaine
- Stop v-separator between frozen columns and remaining ones at last row by @elliotfontaine
- Do not run `_restore_selected_rows()` inside custom sort functions by @elliotfontaine
- Make non-string cells editable again by @elliotfontaine
- Make topbar buttons unfocusable by @elliotfontaine
- Keep drag-and-drop info panel visible for empty registries when drag begin by @elliotfontaine
- Disable broken "Progress" cells for now by @elliotfontaine
- **ui:** Properly render mixed-class registries in table by @elliotfontaine
- Do not reset scrollbars on refresh by @elliotfontaine
- Pan gesture now reset accumulation when switching direction by @elliotfontaine
- Handle minimal column width better by @elliotfontaine
- Ensure last row is fully visible when vertical slider is at the bottom by @elliotfontaine
- Move back scroller to minimum value when it disappear by @elliotfontaine
- **ui:** Clarify visual difference between empty resource cells and invalid rows by @elliotfontaine
- Update displayed registry size when adding/removing entries by @elliotfontaine
- Make scan follow the "Recursive" registry setting by @elliotfontaine
- Correctly save registry on edition by @elliotfontaine
- Fix drag and drog by @elliotfontaine
- Fix uid cache error when creating a new registry by @elliotfontaine
- Center text better within cells by @elliotfontaine
- **ui:** Fix behavior of the Registries List — Registry View horizontal split by @elliotfontaine
- Properly read file extension in new registry dialog by @elliotfontaine
- Add missing logic for the Save button in the Edit Registry dialog by @elliotfontaine
- Do not draw header background if there are no columns by @elliotfontaine
- Stop trying to save changes on virtual cell [-1, -1] by @elliotfontaine
- Error when clicking outside row range by @elliotfontaine
- Fix error when trying to drop resources without any registry in view by @elliotfontaine
- Reset column widths when switching edited registry by @elliotfontaine
- Order StringNames alphanumerically rather than by pointer's location by @elliotfontaine
- Class restriction now works with built-in Resources by @elliotfontaine
- Avoid out-of-bounds errors when reopening closed resources by @elliotfontaine

### Removed

- Remove useless menu items about "saving" registries by @elliotfontaine

### New Contributors

- @elliotfontaine made their first contribution

[unreleased]: https://github.com/elliotfontaine/yard-godot/compare/v1.2.0...HEAD
[1.2.0]: https://github.com/elliotfontaine/yard-godot/compare/v1.1.0...v1.2.0
[1.1.0]: https://github.com/elliotfontaine/yard-godot/compare/v1.0.1...v1.1.0
[1.0.1]: https://github.com/elliotfontaine/yard-godot/compare/v1.0.0...v1.0.1

<!-- generated by git-cliff -->
