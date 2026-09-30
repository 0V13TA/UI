package UI

import "core:testing"

@(test)
test_default_font_and_component_icons_are_embedded :: proc(t: ^testing.T) {
	font, has_font := builtin_resource("ui://font/default")
	down, has_down := builtin_resource("ui://icons/down")
	left, has_left := builtin_resource("ui://icons/left")
	pause, has_pause := builtin_resource("ui://icons/pause")
	play_button, has_play_button := builtin_resource("ui://icons/play-button")
	play, has_play := builtin_resource("ui://icons/play")
	right, has_right := builtin_resource("ui://icons/right")

	testing.expect(t, has_font && len(font) > 0)
	testing.expect(t, has_down && len(down) > 8)
	testing.expect(t, has_left && len(left) > 8)
	testing.expect(t, has_pause && len(pause) > 8)
	testing.expect(t, has_play_button && len(play_button) > 8)
	testing.expect(t, has_play && len(play) > 8)
	testing.expect(t, has_right && len(right) > 8)
}

@(test)
test_application_resource_paths_keep_the_configured_root :: proc(t: ^testing.T) {
	testing.expect_value(
		t,
		resource_path_join("assets", "fonts/body.ttf"),
		"assets/fonts/body.ttf",
	)
	testing.expect_value(
		t,
		resource_path_join("resources", "images/logo.png"),
		"resources/images/logo.png",
	)
	testing.expect_value(t, resource_path_join("", "images/logo.png"), "images/logo.png")
}
