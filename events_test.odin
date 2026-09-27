package UI

import "core:testing"

Test_Focus_Counters :: struct {
	enters, exits: int,
}

test_focus_enter :: proc(id: Box_ID, data: rawptr) {
	(^Test_Focus_Counters)(data).enters += 1
}

test_focus_exit :: proc(id: Box_ID, data: rawptr) {
	(^Test_Focus_Counters)(data).exits += 1
}

test_click_counter :: proc(e: ^UI_Event, data: rawptr) {
	(^int)(data)^ += 1
}

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
	defer delete(layout.all_boxes)
	defer delete(ctx.listeners)
	defer delete(ctx.clicked_this_frame)
	ctx.listeners[control_id] = Event_Callbacks{focusable = true, activate_on_key = true}

	testing.expect(t, activate_focused(&ctx, .RETURN))
	testing.expect(t, ctx.clicked_this_frame[control_id])

	clear(&ctx.clicked_this_frame)
	testing.expect(t, activate_focused(&ctx, .SPACE))
	testing.expect(t, ctx.clicked_this_frame[control_id])
}

@(test)
test_focus_callbacks_fire_on_transitions :: proc(t: ^testing.T) {
	first_id := Box_ID(21)
	second_id := Box_ID(22)
	first, second: Test_Focus_Counters
	ctx := Event_Context {
		listeners = make(map[Box_ID]Event_Callbacks, context.temp_allocator),
		focus_order = make([dynamic]Box_ID, context.temp_allocator),
	}
	defer delete(ctx.listeners)
	defer delete(ctx.focus_order)
	register(
		&ctx,
		first_id,
		Event_Callbacks {
			focusable = true,
			on_focus_enter = test_focus_enter,
			on_focus_exit = test_focus_exit,
			user_data = &first,
		},
	)
	register(
		&ctx,
		second_id,
		Event_Callbacks{focusable = true, on_focus_enter = test_focus_enter, user_data = &second},
	)
	register(&ctx, Box_ID(23), Event_Callbacks{focusable = true, skip_tab = true})
	testing.expect_value(t, len(ctx.focus_order), 2)

	set_focus(&ctx, first_id)
	set_focus(&ctx, second_id)
	testing.expect_value(t, first.enters, 1)
	testing.expect_value(t, first.exits, 1)
	testing.expect_value(t, second.enters, 1)
}

@(test)
test_focus_exit_uses_previous_frame_listener :: proc(t: ^testing.T) {
	id := Box_ID(24)
	counters: Test_Focus_Counters
	ctx := Event_Context {
		listeners = make(map[Box_ID]Event_Callbacks, context.temp_allocator),
		previous_listeners = make(map[Box_ID]Event_Callbacks, context.temp_allocator),
	}
	defer delete(ctx.listeners)
	defer delete(ctx.previous_listeners)

	ctx.listeners[id] = Event_Callbacks {
		focusable = true,
		on_focus_enter = test_focus_enter,
		on_focus_exit = test_focus_exit,
		user_data = &counters,
	}
	set_focus(&ctx, id)
	ctx.previous_listeners[id] = ctx.listeners[id]
	clear(&ctx.listeners)
	set_focus(&ctx, 0)

	testing.expect_value(t, counters.enters, 1)
	testing.expect_value(t, counters.exits, 1)
}

@(test)
test_event_bubbles_and_respects_stop_propagation :: proc(t: ^testing.T) {
	parent_id := Box_ID(31)
	child_id := Box_ID(32)
	parent_clicks, child_clicks: int
	parent := Box{id = parent_id}
	child := Box{id = child_id, parent = &parent}
	ctx := Event_Context {
		listeners = make(map[Box_ID]Event_Callbacks, context.temp_allocator),
		clicked_this_frame = make(map[Box_ID]bool, context.temp_allocator),
	}
	defer delete(ctx.listeners)
	defer delete(ctx.clicked_this_frame)
	ctx.listeners[parent_id] = Event_Callbacks{on_click = test_click_counter, user_data = &parent_clicks}
	ctx.listeners[child_id] = Event_Callbacks{on_click = test_click_counter, user_data = &child_clicks}

	event := UI_Event{target = child_id}
	bubble_event(&ctx, &child, .Click, &event)
	testing.expect_value(t, child_clicks, 1)
	testing.expect_value(t, parent_clicks, 1)
	testing.expect(t, ctx.clicked_this_frame[child_id])
	testing.expect(t, ctx.clicked_this_frame[parent_id])

	event.stop_propagation = true
	bubble_event(&ctx, &child, .Click, &event)
	testing.expect_value(t, child_clicks, 1)
	testing.expect_value(t, parent_clicks, 1)
}
