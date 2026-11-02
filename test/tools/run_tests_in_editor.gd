# SPDX-FileCopyrightText: 2025-2026, Elliot Fontaine <yard-godot@elliotfontaine.anonaddy.com>
# SPDX-FileCopyrightText: 2026-present, YARD contributors (see AUTHORS.md)
#
# SPDX-License-Identifier: MIT

extends SceneTree
## Runs the GdUnit4 command line tool inside the editor, so that tests can use editor-only APIs.
## Takes the same options as GdUnitCmdTool.gd:
## [codeblock]
## godot --headless --editor --path . -s -d --remote-debug tcp://127.0.0.1:0 \
##     res://test/tools/run_tests_in_editor.gd -a res://test -c --ignoreHeadlessMode
## [/codeblock]
## GdUnit4 rejects the [code]--editor[/code] argument that Godot adds to the command line. Its
## runner reads [code]_debug_cmd_args[/code] instead when set, which is not part of its public API
## and may break when updating GdUnit4.

var _cli_runner: GdUnitTestCIRunner


func _initialize() -> void:
	var args := PackedStringArray()
	for arg: String in OS.get_cmdline_args():
		if arg != "--editor":
			args.append(arg.replace("run_tests_in_editor.gd", "GdUnitCmdTool.gd"))

	_cli_runner = GdUnitTestCIRunner.new()
	_cli_runner._debug_cmd_args = args
	root.add_child(_cli_runner)


func _finalize() -> void:
	queue_delete(_cli_runner)
