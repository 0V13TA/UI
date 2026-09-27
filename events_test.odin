package UI

import "core:testing"

Test_Focus_Counters :: struct {
	enters, exits: int,
}

Test_Interaction_Counters :: struct {
	touch_start, touch_move, touch_end: int,
	drag_start, drag_move, drag_enter, drag_leave, drag_over, drag_end, drops: int,
	last_drag_source: Box_ID,
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

test_touch_start :: proc(e: ^UI_Event, data: rawptr) {
	(^Test_Interaction_Counters)(data).touch_start += 1
}

test_touch_move :: proc(e: ^UI_Event, data: rawptr) {
	(^Test_Interaction_Counters)(data).touch_move += 1
}

test_touch_end :: proc(e: ^UI_Event, data: rawptr) {
	(^Test_Interaction_Counters)(data).touch_end += 1
}

test_drag_start :: proc(e: ^UI_Event, data: rawptr) {
	(^Test_Interaction_Counters)(data).drag_start += 1
}

test_drag_move :: proc(e: ^UI_Event, data: rawptr) {
	(^Test_Interaction_Counters)(data).drag_move += 1
}

test_drag_enter :: proc(e: ^UI_Event, data: rawptr) {
	(^Test_Interaction_Counters)(data).drag_enter += 1
}

test_drag_leave :: proc(e: ^UI_Event, data: rawptr) {
	(^Test_Interaction_Counters)(data).drag_leave += 1
}

test_drag_over :: proc(e: ^UI_Event, data: rawptr) {
	(^Test_Interaction_Counters)(data).drag_over += 1
}

test_drag_end :: proc(e: ^UI_Event, data: rawptr) {
	(^Test_Interaction_Counters)(data).drag_end += 1
}

test_drop :: proc(e: ^UI_Event, data: rawptr) {
	counters := (^Test_Interaction_Counters)(data)
	counters.drops += 1
	counters.last_drag_source = e.drag_source
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

@(test)
test_disabled_listener_is_not_focusable_or_activated :: proc(t: ^testing.T) {
	id := Box_ID(40)
	clicks := 0
	ctx := Event_Context {
		listeners = make(map[Box_ID]Event_Callbacks, context.temp_allocator),
		clicked_this_frame = make(map[Box_ID]bool, context.temp_allocator),
		focus_order = make([dynamic]Box_ID, context.temp_allocator),
	}
	defer delete(ctx.listeners)
	defer delete(ctx.clicked_this_frame)
	defer delete(ctx.focus_order)
	register(
		&ctx,
		id,
		Event_Callbacks {
			focusable = true,
			disabled = true,
			on_click = test_click_counter,
			user_data = &clicks,
		},
	)

	box := Box{id = id}
	event := UI_Event{target = id}
	bubble_event(&ctx, &box, .Click, &event)
	set_focus(&ctx, id)

	testing.expect_value(t, len(ctx.focus_order), 0)
	testing.expect_value(t, clicks, 0)
	testing.expect_value(t, ctx.focused_id, Box_ID(0))
	testing.expect(t, !(ctx.clicked_this_frame[id] or_else false))
}

@(test)
test_touch_and_drag_drop_dispatch :: proc(t: ^testing.T) {
	counters: Test_Interaction_Counters
	source := Box {
		id = Box_ID(41),
		pointer_events = true,
		computed_width = 50,
		computed_height = 50,
	}
	target := Box {
		id = Box_ID(42),
		pointer_events = true,
		x = 100,
		computed_width = 50,
		computed_height = 50,
	}
	touch := Box {
		id = Box_ID(43),
		pointer_events = true,
		y = 100,
		computed_width = 100,
		computed_height = 50,
	}
	layout := new(Layout_Context, context.temp_allocator)
	layout.root_boxes = make([dynamic]^Box, context.temp_allocator)
	layout.all_boxes = make(map[Box_ID]^Box, context.temp_allocator)
	append(&layout.root_boxes, &source)
	append(&layout.root_boxes, &target)
	append(&layout.root_boxes, &touch)
	layout.all_boxes[source.id] = &source
	layout.all_boxes[target.id] = &target
	layout.all_boxes[touch.id] = &touch

	ctx := Event_Context {
		layout = layout,
		listeners = make(map[Box_ID]Event_Callbacks, context.temp_allocator),
		clicked_this_frame = make(map[Box_ID]bool, context.temp_allocator),
	}
	defer delete(layout.root_boxes)
	defer delete(layout.all_boxes)
	defer delete(ctx.listeners)
	defer delete(ctx.clicked_this_frame)
	ctx.listeners[source.id] = Event_Callbacks {
		draggable = true,
		on_drag_start = test_drag_start,
		on_drag = test_drag_move,
		on_drag_end = test_drag_end,
		user_data = &counters,
	}
	ctx.listeners[target.id] = Event_Callbacks {
		drop_target   = true,
		on_drop       = test_drop,
		on_drag_enter = test_drag_enter,
		on_drag_leave = test_drag_leave,
		on_drag_over  = test_drag_over,
		user_data     = &counters,
	}
	ctx.listeners[touch.id] = Event_Callbacks {
		on_touch_start = test_touch_start,
		on_touch_move = test_touch_move,
		on_touch_end = test_touch_end,
		user_data = &counters,
	}

	pointer_down(&ctx, 10, 10, false, 0)
	pointer_move(&ctx, 110, 10, 100, 0, false, 0)
	pointer_up(&ctx, 110, 10, false, 0)
	testing.expect_value(t, counters.drag_start, 1)
	testing.expect_value(t, counters.drag_move, 1)
	testing.expect_value(t, counters.drag_enter, 1)
	testing.expect_value(t, counters.drag_leave, 1)
	testing.expect_value(t, counters.drag_over, 2)
	testing.expect_value(t, counters.drag_end, 1)
	testing.expect_value(t, counters.drops, 1)
	testing.expect_value(t, counters.last_drag_source, Box_ID(41))

	pointer_down(&ctx, 10, 110, true, 99)
	pointer_move(&ctx, 12, 111, 2, 1, true, 99)
	pointer_up(&ctx, 12, 111, true, 99)
	testing.expect_value(t, counters.touch_start, 1)
	testing.expect_value(t, counters.touch_move, 1)
	testing.expect_value(t, counters.touch_end, 1)
}
