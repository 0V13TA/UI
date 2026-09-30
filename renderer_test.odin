package UI

import "core:testing"

@(test)
test_nested_render_clip_intersects_canvas_and_component_clips :: proc(t: ^testing.T) {
	canvas_clip := Rect{0, 0, 100, 100}
	component_clip := Rect{20, 30, 100, 80}
	clip := intersect_clip(canvas_clip, component_clip).?

	testing.expect_value(t, clip.x, 20.0)
	testing.expect_value(t, clip.y, 30.0)
	testing.expect_value(t, clip.width, 80.0)
	testing.expect_value(t, clip.height, 70.0)
}

@(test)
test_nested_render_clip_keeps_canvas_clip_for_unclipped_component :: proc(t: ^testing.T) {
	canvas_clip := Rect{0, 0, 80, 60}
	clip := intersect_clip(canvas_clip, nil).?

	testing.expect_value(t, clip.x, 0.0)
	testing.expect_value(t, clip.y, 0.0)
	testing.expect_value(t, clip.width, 80.0)
	testing.expect_value(t, clip.height, 60.0)
}
