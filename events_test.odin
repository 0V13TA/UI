package UI

import "core:testing"

@(test)
test_tab_focus_cycles_through_previous_frame_order :: proc(t: ^testing.T) {
	ctx := Event_Context {
		focus_order = make([dynamic]Box_ID, context.temp_allocator),
	}
	append(&ctx.focus_order, Box_ID(1))
	append(&ctx.focus_order, Box_ID(2))
	append(&ctx.focus_order, Box_ID(3))

	begin_frame(&ctx)
	cycle_focus(&ctx, reverse = false)
	testing.expect_value(t, ctx.focused_id, Box_ID(1))

	cycle_focus(&ctx, reverse = false)
	testing.expect_value(t, ctx.focused_id, Box_ID(2))

	cycle_focus(&ctx, reverse = true)
	testing.expect_value(t, ctx.focused_id, Box_ID(1))

	cycle_focus(&ctx, reverse = true)
	testing.expect_value(t, ctx.focused_id, Box_ID(3))
}

@(test)
test_enter_and_space_activate_focused_control_from_child :: proc(t: ^testing.T) {
	control_id := Box_ID(10)
	text_id := Box_ID(11)
	control := Box{id = control_id}
	child := Box{id = text_id, parent = &control}
	layout := new(Layout_Context, context.temp_allocator)
	layout.all_boxes = make(map[Box_ID]^Box, context.temp_allocator)
	layout.all_boxes[text_id] = &child

	ctx := Event_Context {
		layout = layout,
		listeners = make(map[Box_ID]Event_Callbacks, context.temp_allocator),
		clicked_this_frame = make(map[Box_ID]bool, context.temp_allocator),
		focused_id = text_id,
	}
	ctx.listeners[control_id] = Event_Callbacks{focusable = true, activate_on_key = true}

	testing.expect(t, activate_focused(&ctx, .RETURN))
	testing.expect(t, ctx.clicked_this_frame[control_id])

	clear(&ctx.clicked_this_frame)
	testing.expect(t, activate_focused(&ctx, .SPACE))
	testing.expect(t, ctx.clicked_this_frame[control_id])
}
