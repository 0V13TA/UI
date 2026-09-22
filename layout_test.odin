package UI

import "core:testing"

// --- Dummy Text Procs for Testing ---
dummy_text_width :: proc(box: ^Box, text: string) -> f32 {return f32(len(text) * 10)}
dummy_text_height :: proc(box: ^Box, text: string, max_width: f32) -> f32 {
	if max_width > 0 && max_width < 50 do return 40.0 // Simulate text wrap expanding height
	return 20.0
}

@(test)
test_flex_grow_with_constraints :: proc(t: ^testing.T) {
	ctx := layout_context_create(dummy_text_width, dummy_text_height, 1000, 1000)
	defer layout_context_destroy(ctx)
	begin_layout(ctx)

	// Container is 1000px wide.
	root := box_open(ctx, Box{direction = .ROW, width = Fixed{1000}, height = Fixed{100}})

	// Child 1: Fixed 200px. Remaining space = 800px.
	box_open(ctx, Box{width = Fixed{200}, height = Fixed{100}})
	box_close(ctx)

	// Child 2: Grow 1, but max width is 300px. (Normally would take 400px, but freezes at 300px).
	c2 := box_open(ctx, Box{width = Grow{1}, max_width = Fixed{300}, height = Fixed{100}})
	box_close(ctx)

	// Child 3: Grow 1. Receives the remaining 500px after Child 2 freezes.
	c3 := box_open(ctx, Box{width = Grow{1}, height = Fixed{100}})
	box_close(ctx)

	box_close(ctx)
	end_layout(ctx)

	testing.expect_value(t, root.children[0].computed_width, 200.0)
	testing.expect_value(t, c2.computed_width, 300.0)
	testing.expect_value(t, c3.computed_width, 500.0)
}

@(test)
test_flex_wrap_and_cross_stretch :: proc(t: ^testing.T) {
	ctx := layout_context_create(dummy_text_width, dummy_text_height, 1000, 1000)
	defer layout_context_destroy(ctx)
	begin_layout(ctx)

	// 100px wide. Fit height. Wrap enabled. Stretch align.
	root := box_open(
		ctx,
		Box {
			direction = .ROW,
			width = Fixed{100},
			height = Fit(true),
			wrap = true,
			gap = 10,
			align_items = .STRETCH,
		},
	)

	// Line 1: 40px + 10px (gap) + 40px = 90px. (Max height = 30)
	c1 := box_open(ctx, Box{width = Fixed{40}, height = Fit(true)})
	box_close(ctx)
	c2 := box_open(ctx, Box{width = Fixed{40}, height = Fixed{30}})
	box_close(ctx)

	// Line 2: Wraps because 90 + 10 + 40 > 100. (Max height = 15)
	c3 := box_open(ctx, Box{width = Fixed{40}, height = Fixed{15}})
	box_close(ctx)

	box_close(ctx)
	end_layout(ctx)

	// Children cross-stretch to their specific line's max height
	testing.expect_value(t, c1.computed_height, 30.0)
	testing.expect_value(t, c2.computed_height, 30.0)
	testing.expect_value(t, c3.computed_height, 15.0)

	// Total container height: Line 1 (30) + Gap (10) + Line 2 (15) = 55
	testing.expect_value(t, root.computed_height, 55.0)
}

@(test)
test_absolute_positioning_and_scroll_bounds :: proc(t: ^testing.T) {
	ctx := layout_context_create(dummy_text_width, dummy_text_height, 1000, 1000)
	defer layout_context_destroy(ctx)
	begin_layout(ctx)

	// Parent starts at X=10, Y=10 due to margin
	root := box_open(ctx, Box{width = Fixed{100}, height = Fixed{100}, margin = {10, 0, 0, 10}})

	// Normal child (expands scroll area)
	box_open(ctx, Box{width = Fixed{150}, height = Fixed{50}})
	box_close(ctx)

	// Absolute child (should NOT expand scroll area)
	abs_child := box_open(
		ctx,
		Box{position = .ABSOLUTE, left = 20, top = 30, width = Fixed{500}, height = Fixed{500}},
	)
	box_close(ctx)

	box_close(ctx)
	end_layout(ctx)

	// Absolute child coordinates relative to parent's inner content bounds
	testing.expect_value(t, abs_child.x, 30.0) // 10 (root X) + 20 (left)
	testing.expect_value(t, abs_child.y, 40.0) // 10 (root Y) + 30 (top)

	// Scroll bounds should only consider the normal child (150 width), ignoring absolute 500
	testing.expect_value(t, root.scroll_width, 150.0)
	testing.expect_value(t, root.scroll_height, 100.0) // Container is 100, child is 50
}

@(test)
test_z_index_sorting :: proc(t: ^testing.T) {
	ctx := layout_context_create(dummy_text_width, dummy_text_height, 1000, 1000)
	defer layout_context_destroy(ctx)
	begin_layout(ctx)

	root := box_open(ctx, Box{width = Fixed{100}, height = Fixed{100}})

	box_open(ctx, Box{id = ID("mid"), z_index = 5})
	box_close(ctx)
	box_open(ctx, Box{id = ID("back"), z_index = 0})
	box_close(ctx)
	box_open(ctx, Box{id = ID("front"), z_index = 10})
	box_close(ctx)

	box_close(ctx)
	end_layout(ctx)

	testing.expect_value(t, root.children[0].id, ID("back"))
	testing.expect_value(t, root.children[1].id, ID("mid"))
	testing.expect_value(t, root.children[2].id, ID("front"))
}

@(test)
test_overflow_clipping_rects :: proc(t: ^testing.T) {
	ctx := layout_context_create(dummy_text_width, dummy_text_height, 1000, 1000)
	defer layout_context_destroy(ctx)
	begin_layout(ctx)

	// Overflow hidden: Should constrain children's clip rects
	root := box_open(
		ctx,
		Box{width = Fixed{100}, height = Fixed{100}, overflow_x = .HIDDEN, overflow_y = .HIDDEN},
	)

	child := box_open(ctx, Box{width = Fixed{200}, height = Fixed{200}})
	box_close(ctx)

	box_close(ctx)
	end_layout(ctx)

	// Root has no parent, shouldn't have a clip rect itself
	testing.expect(t, root.clip_rect == nil)

	// Child inherits intersected clip from root
	clip := child.clip_rect.?
	testing.expect_value(t, clip.x, 0.0)
	testing.expect_value(t, clip.y, 0.0)
	testing.expect_value(t, clip.width, 100.0)
	testing.expect_value(t, clip.height, 100.0)
}

@(test)
test_text_height_measurement :: proc(t: ^testing.T) {
	ctx := layout_context_create(dummy_text_width, dummy_text_height, 1000, 1000)
	defer layout_context_destroy(ctx)
	begin_layout(ctx)

	// Width restricts text below 50px, forcing dummy proc to return 40.0 height
	root := box_open(ctx, Box{width = Fixed{40}, height = Fit(true), text = "Hello"})
	box_close(ctx)

	end_layout(ctx)

	// Height should dynamically scale to fit the text wrap measurement
	testing.expect_value(t, root.computed_height, 40.0)
}

@(test)
test_flex_alignment_justify :: proc(t: ^testing.T) {
	ctx := layout_context_create(dummy_text_width, dummy_text_height, 1000, 1000)
	defer layout_context_destroy(ctx)
	begin_layout(ctx)

	root := box_open(
		ctx,
		Box {
			direction = .ROW,
			width = Fixed{100},
			height = Fixed{100},
			justify_content = .CENTER,
			align_items = .CENTER,
		},
	)

	child := box_open(ctx, Box{width = Fixed{50}, height = Fixed{40}})
	box_close(ctx)

	box_close(ctx)
	end_layout(ctx)

	// Center justify in 100px width with 50px child = offset by 25
	testing.expect_value(t, child.x, 25.0)
	// Center align in 100px height with 40px child = offset by 30
	testing.expect_value(t, child.y, 30.0)
}
