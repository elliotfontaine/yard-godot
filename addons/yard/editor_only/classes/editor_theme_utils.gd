#class_name EditorThemeUtils

static func get_base_color(p_dimness_ofs: float = 0.0, p_saturation_mult: float = 1.0) -> Color:
	var settings := EditorInterface.get_editor_settings()

	var c: Color = settings.get_setting("interface/theme/base_color")
	var contrast: float = float(settings.get_setting("interface/theme/contrast"))

	c.v = clamp(lerp(c.v, 0.0, contrast * p_dimness_ofs), 0.0, 1.0)
	c.s = c.s * p_saturation_mult
	return c
