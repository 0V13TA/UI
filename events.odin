package UI

import "core:strings"
import sdl "./vendor/sdl2"

Event_Type :: enum {
	Click,
	Double_Click,
	Pointer_Down,
	Pointer_Up,
	Pointer_Move,
	Scroll,
	Key_Down,
	Text_Input,
	Touch_Start,
	Touch_Move,
	Touch_End,
	Drag_Start,
	Drag,
	Drag_Enter,
	Drag_Leave,
	Drag_Over,
	Drag_End,
	Drop,
	Custom,
}

Event_Callbacks :: struct {
	focusable:         bool,
	disabled:          bool,
	skip_tab:          bool,
	activate_on_key:   bool,
	draggable:         bool,
	drop_target:       bool,
	cursor:            sdl.SystemCursor,

	// Pointer
	on_click:       proc(e: ^UI_Event, data: rawptr),
	on_double_click: proc(e: ^UI_Event, data: rawptr),
	on_pointer_down: proc(e: ^UI_Event, data: rawptr),
	on_pointer_up:   proc(e: ^UI_Event, data: rawptr),
	on_pointer_move: proc(e: ^UI_Event, data: rawptr),
	on_hover_enter: proc(id: Box_ID, data: rawptr),
	on_hover_exit:  proc(id: Box_ID, data: rawptr),
	on_scroll:      proc(e: ^UI_Event, data: rawptr),
	on_touch_start: proc(e: ^UI_Event, data: rawptr),
	on_touch_move:  proc(e: ^UI_Event, data: rawptr),
	on_touch_end:   proc(e: ^UI_Event, data: rawptr),
	on_drag_start:  proc(e: ^UI_Event, data: rawptr),
	on_drag:        proc(e: ^UI_Event, data: rawptr),
	on_drag_enter:  proc(e: ^UI_Event, data: rawptr),
	on_drag_leave:  proc(e: ^UI_Event, data: rawptr),
	on_drag_over:   proc(e: ^UI_Event, data: rawptr),
	on_drag_end:    proc(e: ^UI_Event, data: rawptr),
	on_drop:        proc(e: ^UI_Event, data: rawptr),

	// Keyboard & Focus
	on_focus_enter: proc(id: Box_ID, data: rawptr),
	on_focus_exit:  proc(id: Box_ID, data: rawptr),
	on_key_down:    proc(e: ^UI_Event, data: rawptr),
	on_text_input:  proc(e: ^UI_Event, data: rawptr),

	// Custom Events
	on_custom:      proc(e: ^UI_Event, data: rawptr),
	user_data:      rawptr,
}

Event_Context :: struct {
	layout:               ^Layout_Context,
	listeners:            map[Box_ID]Event_Callbacks,
	previous_listeners:   map[Box_ID]Event_Callbacks,
	hovered_id:           Box_ID,
	pressed_id:           Box_ID,
	focused_id:           Box_ID,
	focus_visible:        bool,
	prev_focused_id:      Box_ID,
	prev_pressed_id:      Box_ID,
	click_x, click_y:     f32,
	pointer_x, pointer_y: f32,
	pointer_prev_x, pointer_prev_y: f32,
	viewport_w, viewport_h: f32,
	pointer_is_touch:     bool,
	active_touch_id:      sdl.FingerID,
	touch_active:         bool,
	drag_source_id:       Box_ID,
	drag_over_id:         Box_ID,
	drag_start_x, drag_start_y: f32,
	drag_active:          bool,
	context_menu_target:  Box_ID,
	clicked_this_frame:   map[Box_ID]bool,
	scroll_offsets_x:     map[Box_ID]f32,
	scroll_offsets_y:     map[Box_ID]f32,
	text_cursors:         map[Box_ID]int,
	text_selection:       map[Box_ID]int,
	cursor_blink_start:   map[Box_ID]u64,
	cursor_last_position: map[Box_ID]int,
	focused_buffer:       ^[dynamic]u8,
	focus_order:          [dynamic]Box_ID,
	focused_gap_buffer:   ^Gap_Buffer,
}

event_callbacks :: proc(ctx: ^Event_Context, id: Box_ID) -> (Event_Callbacks, bool) {
	if callbacks, ok := ctx.listeners[id]; ok do return callbacks, true
	if callbacks, ok := ctx.previous_listeners[id]; ok do return callbacks, true
	return {}, false
}

UI_Event :: struct {
	target:           Box_ID, // where the event originated
	current_target:   Box_ID, // who is handling it right now

	// Mouse specific
	mouse_x, mouse_y: f32,
	scroll_dx:        f32,
	scroll_dy:        f32,

	// Keyboard specific
	keycode:          sdl.Keycode,
	key_mod:          sdl.Keymod,
	text:             string,

	// Custom Event Data
	custom_name:      string,
	custom_payload:   rawptr,
	is_touch:         bool,
	touch_id:         sdl.FingerID,
	pointer_dx, pointer_dy: f32,
	drag_source:      Box_ID,
	stop_propagation: bool,
}

begin_frame :: proc(ctx: ^Event_Context) {
	clear(&ctx.clicked_this_frame)
	ctx.prev_focused_id = ctx.focused_id
	ctx.prev_pressed_id = ctx.pressed_id
}

cycle_focus :: proc(ctx: ^Event_Context, reverse: bool) {
	if len(ctx.focus_order) == 0 do return

	idx := -1
	for id, i in ctx.focus_order {
		if id == ctx.focused_id {
			idx = i
			break
		}
	}

	if reverse {
		idx -= 1
		if idx < 0 do idx = len(ctx.focus_order) - 1
	} else {
		idx += 1
		if idx >= len(ctx.focus_order) do idx = 0
	}

	ctx.focus_visible = true
	set_focus(ctx, ctx.focus_order[idx])
}

refresh_hover :: proc(ctx: ^Event_Context) {
	if ctx.touch_active {
		hovered := get_hovered_box_at(ctx, ctx.pointer_x, ctx.pointer_y)
		update_hover(ctx, hovered != nil ? hovered.id : 0)
		return
	}

	mx, my: i32
	sdl.GetMouseState(&mx, &my)

	hovered_box := get_hovered_box_at(ctx, f32(mx), f32(my))
	update_hover(ctx, hovered_box != nil ? hovered_box.id : 0)
}

activate_focused :: proc(ctx: ^Event_Context, keycode: sdl.Keycode) -> bool {
	if keycode != .RETURN && keycode != .KP_ENTER && keycode != .SPACE do return false
	if target_box, ok := ctx.layout.all_boxes[ctx.focused_id]; ok {
		for target_box != nil {
			if cb, exists := event_callbacks(ctx, target_box.id);
			   exists && cb.activate_on_key && !cb.disabled {
				ui_ev := UI_Event{target = target_box.id, keycode = keycode}
				bubble_event(ctx, target_box, .Click, &ui_ev)
				return true
			}
			target_box = target_box.parent
		}
	}
	return false
}

register :: proc(ctx: ^Event_Context, id: Box_ID, callbacks: Event_Callbacks) {
	ctx.listeners[id] = callbacks
	found := false
	for existing, i in ctx.focus_order {
		if existing == id {
			if callbacks.focusable && !callbacks.disabled && !callbacks.skip_tab {
				found = true
			} else {
				ordered_remove(&ctx.focus_order, i)
			}
			break
		}
	}
	if callbacks.focusable && !callbacks.disabled && !callbacks.skip_tab {
		if !found do append(&ctx.focus_order, id)
	}
}

// Safely removes a listener, ensuring lifecycle hooks fire if it was active
unregister :: proc(ctx: ^Event_Context, id: Box_ID) {
	// 1. Gracefully remove focus
	if ctx.focused_id == id {
		set_focus(ctx, 0)
	}
	// 2. Gracefully remove hover
	if ctx.hovered_id == id {
		update_hover(ctx, 0)
	}
	// 3. Clear press state
	if ctx.pressed_id == id {
		ctx.pressed_id = 0
	}
	for focus_id, i in ctx.focus_order {
		if focus_id == id {
			ordered_remove(&ctx.focus_order, i)
			break
		}
	}

	delete_key(&ctx.listeners, id)
}

set_focus :: proc(ctx: ^Event_Context, new_focus: Box_ID) {
	if cb, ok := event_callbacks(ctx, new_focus); ok && cb.disabled do return
	if ctx.focused_id == new_focus do return

	if old_cb, ok := event_callbacks(ctx, ctx.focused_id); ok && old_cb.on_focus_exit != nil {
		old_cb.on_focus_exit(ctx.focused_id, old_cb.user_data)
	}

	ctx.focused_id = new_focus
	if new_focus == 0 do ctx.focus_visible = false

	if new_cb, ok := event_callbacks(ctx, new_focus); ok && new_cb.on_focus_enter != nil {
		new_cb.on_focus_enter(new_focus, new_cb.user_data)
	}
}

update_hover :: proc(ctx: ^Event_Context, new_hovered_id: Box_ID) {
	if ctx.hovered_id != new_hovered_id {
		if old_cb, ok := event_callbacks(ctx, ctx.hovered_id);
		   ok && !old_cb.disabled && old_cb.on_hover_exit != nil {
			old_cb.on_hover_exit(ctx.hovered_id, old_cb.user_data)
		}
		if new_cb, ok := event_callbacks(ctx, new_hovered_id);
		   ok && !new_cb.disabled && new_cb.on_hover_enter != nil {
			new_cb.on_hover_enter(new_hovered_id, new_cb.user_data)
		}
		ctx.hovered_id = new_hovered_id
	}
}

get_hovered_box :: proc(ctx: ^Event_Context, box: ^Box, mx, my: f32) -> ^Box {
	if !box.pointer_events do return nil

	if clip, ok := box.clip_rect.?; ok {
		if mx < clip.x || mx > clip.x + clip.width || my < clip.y || my > clip.y + clip.height {
			return nil
		}
	}

	#reverse for child in box.children {
		if hit := get_hovered_box(ctx, child, mx, my); hit != nil {
			return hit
		}
	}

	in_x := mx >= box.x && mx <= box.x + box.computed_width
	in_y := my >= box.y && my <= box.y + box.computed_height

	if in_x && in_y do return box
	return nil
}

get_hovered_box_at :: proc(ctx: ^Event_Context, mx, my: f32) -> ^Box {
	#reverse for root in ctx.layout.root_boxes {
		if hit := get_hovered_box(ctx, root, mx, my); hit != nil do return hit
	}
	return nil
}

nearest_focusable :: proc(ctx: ^Event_Context, box: ^Box) -> Box_ID {
	for current := box; current != nil; current = current.parent {
		if cb, ok := event_callbacks(ctx, current.id); ok && cb.focusable && !cb.disabled {
			return current.id
		}
	}
	return 0
}

nearest_draggable :: proc(ctx: ^Event_Context, box: ^Box) -> Box_ID {
	for current := box; current != nil; current = current.parent {
		if cb, ok := event_callbacks(ctx, current.id); ok && cb.draggable && !cb.disabled {
			return current.id
		}
	}
	return 0
}

nearest_drop_target :: proc(ctx: ^Event_Context, box: ^Box) -> Box_ID {
	for current := box; current != nil; current = current.parent {
		if cb, ok := event_callbacks(ctx, current.id); ok && cb.drop_target && !cb.disabled {
			return current.id
		}
	}
	return 0
}

update_drag_target :: proc(
	ctx: ^Event_Context,
	hovered: ^Box,
	x, y, dx, dy: f32,
	is_touch: bool,
	touch_id: sdl.FingerID,
) {
	new_target_id := nearest_drop_target(ctx, hovered)
	if new_target_id != ctx.drag_over_id {
		if old_target, ok := ctx.layout.all_boxes[ctx.drag_over_id]; ok {
			pointer_event(ctx, .Drag_Leave, old_target, x, y, dx, dy, is_touch, touch_id)
		}
		ctx.drag_over_id = new_target_id
		if new_target, ok := ctx.layout.all_boxes[new_target_id]; ok {
			pointer_event(ctx, .Drag_Enter, new_target, x, y, dx, dy, is_touch, touch_id)
		}
	}
	if target, ok := ctx.layout.all_boxes[ctx.drag_over_id]; ok {
		pointer_event(ctx, .Drag_Over, target, x, y, dx, dy, is_touch, touch_id)
	}
}

pointer_event :: proc(
	ctx: ^Event_Context,
	event_type: Event_Type,
	target_box: ^Box,
	x, y, dx, dy: f32,
	is_touch: bool,
	touch_id: sdl.FingerID,
) {
	if target_box == nil do return
	ui_ev := UI_Event {
		target      = target_box.id,
		mouse_x     = x,
		mouse_y     = y,
		pointer_dx  = dx,
		pointer_dy  = dy,
		is_touch    = is_touch,
		touch_id    = touch_id,
		drag_source = ctx.drag_source_id,
	}
	bubble_event(ctx, target_box, event_type, &ui_ev)
}

pointer_down :: proc(ctx: ^Event_Context, x, y: f32, is_touch: bool, touch_id: sdl.FingerID) {
	ctx.focus_visible = false
	ctx.pointer_prev_x, ctx.pointer_prev_y = ctx.pointer_x, ctx.pointer_y
	ctx.pointer_x, ctx.pointer_y = x, y
	ctx.pointer_is_touch = is_touch
	hovered := get_hovered_box_at(ctx, x, y)
	update_hover(ctx, hovered != nil ? hovered.id : 0)
	target_id := nearest_focusable(ctx, hovered)
	if target_id == 0 && hovered != nil do target_id = hovered.id
	ctx.pressed_id = target_id
	ctx.drag_source_id = nearest_draggable(ctx, hovered)
	ctx.drag_start_x, ctx.drag_start_y = x, y
	ctx.drag_active = false

	focus_id := nearest_focusable(ctx, hovered)
	if focus_id != 0 {
		set_focus(ctx, focus_id)
	} else {
		set_focus(ctx, 0)
	}

	if hovered != nil {
		pointer_event(ctx, .Pointer_Down, hovered, x, y, 0, 0, is_touch, touch_id)
		if is_touch do pointer_event(ctx, .Touch_Start, hovered, x, y, 0, 0, true, touch_id)
	}
}

pointer_move :: proc(ctx: ^Event_Context, x, y, dx, dy: f32, is_touch: bool, touch_id: sdl.FingerID) {
	ctx.pointer_prev_x, ctx.pointer_prev_y = ctx.pointer_x, ctx.pointer_y
	ctx.pointer_x, ctx.pointer_y = x, y
	ctx.pointer_is_touch = is_touch
	hovered := get_hovered_box_at(ctx, x, y)
	update_hover(ctx, hovered != nil ? hovered.id : 0)

	if hovered != nil {
		pointer_event(ctx, .Pointer_Move, hovered, x, y, dx, dy, is_touch, touch_id)
	}
	if is_touch {
		if pressed, ok := ctx.layout.all_boxes[ctx.pressed_id]; ok {
			pointer_event(ctx, .Touch_Move, pressed, x, y, dx, dy, true, touch_id)
		}
	}

	if ctx.drag_source_id != 0 {
		distance_x := x - ctx.drag_start_x
		distance_y := y - ctx.drag_start_y
		if !ctx.drag_active && distance_x * distance_x + distance_y * distance_y >= 36.0 {
			ctx.drag_active = true
			if source, ok := ctx.layout.all_boxes[ctx.drag_source_id]; ok {
				pointer_event(ctx, .Drag_Start, source, x, y, dx, dy, is_touch, touch_id)
			}
		}
		if ctx.drag_active {
			if source, ok := ctx.layout.all_boxes[ctx.drag_source_id]; ok {
				pointer_event(ctx, .Drag, source, x, y, dx, dy, is_touch, touch_id)
			}
			update_drag_target(ctx, hovered, x, y, dx, dy, is_touch, touch_id)
		}
	}
}

pointer_up :: proc(ctx: ^Event_Context, x, y: f32, is_touch: bool, touch_id: sdl.FingerID) {
	ctx.pointer_prev_x, ctx.pointer_prev_y = ctx.pointer_x, ctx.pointer_y
	ctx.pointer_x, ctx.pointer_y = x, y
	ctx.pointer_is_touch = is_touch
	hovered := get_hovered_box_at(ctx, x, y)
	update_hover(ctx, hovered != nil ? hovered.id : 0)
	if hovered != nil {
		pointer_event(ctx, .Pointer_Up, hovered, x, y, 0, 0, is_touch, touch_id)
	}
	if is_touch {
		if pressed, ok := ctx.layout.all_boxes[ctx.pressed_id]; ok {
			pointer_event(ctx, .Touch_End, pressed, x, y, 0, 0, true, touch_id)
		}
	}

	release_id := nearest_focusable(ctx, hovered)
	if release_id == 0 && hovered != nil do release_id = hovered.id
	if ctx.pressed_id != 0 && ctx.pressed_id == release_id && !ctx.drag_active {
		if target, ok := ctx.layout.all_boxes[ctx.pressed_id]; ok {
			click := UI_Event {
				target   = ctx.pressed_id,
				mouse_x  = x,
				mouse_y  = y,
				is_touch = is_touch,
				touch_id = touch_id,
			}
			ctx.click_x, ctx.click_y = x, y
			bubble_event(ctx, target, .Click, &click)
		}
	}

	if ctx.drag_active {
		update_drag_target(ctx, hovered, x, y, 0, 0, is_touch, touch_id)
		drop_id := ctx.drag_over_id
		if drop_id != 0 {
			if target, ok := ctx.layout.all_boxes[drop_id]; ok {
				drop := UI_Event {
					target      = drop_id,
					mouse_x     = x,
					mouse_y     = y,
					is_touch    = is_touch,
					touch_id    = touch_id,
					drag_source = ctx.drag_source_id,
				}
				bubble_event(ctx, target, .Drop, &drop)
			}
		}
		if source, ok := ctx.layout.all_boxes[ctx.drag_source_id]; ok {
			pointer_event(ctx, .Drag_End, source, x, y, 0, 0, is_touch, touch_id)
		}
		if target, ok := ctx.layout.all_boxes[ctx.drag_over_id]; ok {
			pointer_event(ctx, .Drag_Leave, target, x, y, 0, 0, is_touch, touch_id)
		}
	}

	ctx.pressed_id = 0
	ctx.drag_source_id = 0
	ctx.drag_over_id = 0
	ctx.drag_active = false
}

pump_events :: proc(ctx: ^Event_Context, e: ^sdl.Event) {
	mx, my: i32
	sdl.GetMouseState(&mx, &my)

	hovered_box := get_hovered_box_at(ctx, f32(mx), f32(my))

	current_hovered_id := hovered_box != nil ? hovered_box.id : 0

	// Constantly verify hover state to catch layout shifts occurring without mouse motion
	update_hover(ctx, current_hovered_id)

	#partial switch e.type {
	case .MOUSEBUTTONDOWN:
		if e.button.button == sdl.BUTTON_LEFT {
			ctx.focus_visible = false
			pointer_down(ctx, f32(e.button.x), f32(e.button.y), false, 0)
		}
		if e.button.button == sdl.BUTTON_RIGHT {
			// Snap the right click to the nearest interactive parent
			target: Box_ID = 0
			curr := hovered_box
			for curr != nil {
				if cb, ok := event_callbacks(ctx, curr.id); ok && cb.focusable && !cb.disabled {
					target = curr.id
					break
				}
				curr = curr.parent
			}
			if target == 0 do target = current_hovered_id

			ctx.context_menu_target = target
		}

	case .MOUSEBUTTONUP:
		if e.button.button == sdl.BUTTON_LEFT {
			pointer_up(ctx, f32(e.button.x), f32(e.button.y), false, 0)
			if e.button.clicks >= 2 {
				double_click_target := get_hovered_box_at(ctx, f32(e.button.x), f32(e.button.y))
				if double_click_target != nil {
					click := UI_Event {
						target  = double_click_target.id,
						mouse_x = f32(e.button.x),
						mouse_y = f32(e.button.y),
					}
					bubble_event(ctx, double_click_target, .Double_Click, &click)
				}
			}
		}

	case .MOUSEMOTION:
		pointer_move(ctx, f32(e.motion.x), f32(e.motion.y), f32(e.motion.xrel), f32(e.motion.yrel), false, 0)

	case .FINGERDOWN:
		if ctx.viewport_w > 0 && ctx.viewport_h > 0 {
			ctx.touch_active = true
			ctx.active_touch_id = sdl.FingerID(e.tfinger.fingerId)
			pointer_down(ctx, e.tfinger.x * ctx.viewport_w, e.tfinger.y * ctx.viewport_h, true, ctx.active_touch_id)
		}

	case .FINGERMOTION:
		if ctx.touch_active && sdl.FingerID(e.tfinger.fingerId) == ctx.active_touch_id {
			pointer_move(
				ctx,
				e.tfinger.x * ctx.viewport_w,
				e.tfinger.y * ctx.viewport_h,
				e.tfinger.dx * ctx.viewport_w,
				e.tfinger.dy * ctx.viewport_h,
				true,
				ctx.active_touch_id,
			)
		}

	case .FINGERUP:
		if ctx.touch_active && sdl.FingerID(e.tfinger.fingerId) == ctx.active_touch_id {
			pointer_up(ctx, e.tfinger.x * ctx.viewport_w, e.tfinger.y * ctx.viewport_h, true, ctx.active_touch_id)
			ctx.touch_active = false
		}

	case .MOUSEWHEEL:
		if hovered_box != nil {
			dx := f32(e.wheel.x)
			dy := f32(e.wheel.y)

			// Handle OS-level inverted scrolling (e.g. macOS "Natural" scrolling)
			if e.wheel.direction == u32(sdl.MouseWheelDirection.FLIPPED) {
				dx *= -1.0
				dy *= -1.0
			}

			ui_ev := UI_Event {
				target    = current_hovered_id,
				mouse_x   = f32(mx),
				mouse_y   = f32(my),
				scroll_dx = dx,
				scroll_dy = dy,
			}
			bubble_event(ctx, hovered_box, .Scroll, &ui_ev)
		}

	case .KEYDOWN:
		if e.key.keysym.sym == .TAB {
			if e.key.repeat == 0 {
				has_shift := (transmute(u16)e.key.keysym.mod & 0x0003) != 0
				cycle_focus(ctx, reverse = has_shift)
			}
			break
		}

		if e.key.keysym.sym == .RETURN || e.key.keysym.sym == .KP_ENTER ||
		   e.key.keysym.sym == .SPACE {
			if e.key.repeat == 0 && activate_focused(ctx, e.key.keysym.sym) do break
		}

		if ctx.focused_id != 0 {
			if target_box, ok := ctx.layout.all_boxes[ctx.focused_id]; ok {
				ui_ev := UI_Event {
					target  = ctx.focused_id,
					keycode = e.key.keysym.sym,
					key_mod = e.key.keysym.mod,
				}
				bubble_event(ctx, target_box, .Key_Down, &ui_ev)
			}
		}

	case .TEXTINPUT:
		if ctx.focused_id != 0 {
			if target_box, ok := ctx.layout.all_boxes[ctx.focused_id]; ok {
				text_bytes := e.text.text[:]
				null_idx := strings.index_byte(string(text_bytes), 0)
				odin_str := null_idx >= 0 ? string(text_bytes[:null_idx]) : string(text_bytes)

				ui_ev := UI_Event {
					target = ctx.focused_id,
					text   = odin_str,
				}
				bubble_event(ctx, target_box, .Text_Input, &ui_ev)
			}
		}
	}
}

bubble_event :: proc(ctx: ^Event_Context, start_node: ^Box, event_type: Event_Type, e: ^UI_Event) {
	current := start_node

	for current != nil && !e.stop_propagation {
		e.current_target = current.id

		// 1. Native Scroll Interception (Smart Nested Scrolling)
		current_callbacks, has_callbacks := event_callbacks(ctx, current.id)
		current_disabled := current.disabled || (has_callbacks && current_callbacks.disabled)
		if event_type == .Scroll && !current_disabled {
			if current.overflow_y == .SCROLL && e.scroll_dy != 0 {
				max_scroll := max(current.scroll_height - current.computed_height, 0.0)
				old_offset := current.offset_y

				// Apply the scroll delta
				new_offset := current.offset_y - (e.scroll_dy * 50.0)

				// HARD CLAMP: Prevent the offset from leaving the valid layout bounds
				if new_offset < 0.0 do new_offset = 0.0
				if new_offset > max_scroll do new_offset = max_scroll

				ctx.scroll_offsets_y[current.id] = new_offset
				current.offset_y = new_offset

				// Only stop propagation if we actually scrolled.
				// This allows nested scroll views to pass the scroll event to their parents
				// when they hit the top or bottom!
				if new_offset != old_offset do e.stop_propagation = true
			}

			if current.overflow_x == .SCROLL && e.scroll_dx != 0 {
				max_scroll := max(current.scroll_width - current.computed_width, 0.0)
				old_offset := current.offset_x

				new_offset := current.offset_x - (e.scroll_dx * 50.0)

				// HARD CLAMP: Prevent the offset from leaving the valid layout bounds
				if new_offset < 0.0 do new_offset = 0.0
				if new_offset > max_scroll do new_offset = max_scroll

				ctx.scroll_offsets_x[current.id] = new_offset
				current.offset_x = new_offset

				if new_offset != old_offset do e.stop_propagation = true
			}
		}

		// 2. Trigger User Callbacks
		if has_callbacks {
			if !current_disabled {
				cb := current_callbacks
				if event_type == .Click {
					ctx.clicked_this_frame[current.id] = true
					if cb.on_click != nil do cb.on_click(e, cb.user_data)
				}
				if event_type == .Double_Click && cb.on_double_click != nil do cb.on_double_click(e, cb.user_data)
				if event_type == .Pointer_Down && cb.on_pointer_down != nil do cb.on_pointer_down(e, cb.user_data)
				if event_type == .Pointer_Up && cb.on_pointer_up != nil do cb.on_pointer_up(e, cb.user_data)
				if event_type == .Pointer_Move && cb.on_pointer_move != nil do cb.on_pointer_move(e, cb.user_data)
				if event_type == .Scroll && cb.on_scroll != nil do cb.on_scroll(e, cb.user_data)
				if event_type == .Touch_Start && cb.on_touch_start != nil do cb.on_touch_start(e, cb.user_data)
				if event_type == .Touch_Move && cb.on_touch_move != nil do cb.on_touch_move(e, cb.user_data)
				if event_type == .Touch_End && cb.on_touch_end != nil do cb.on_touch_end(e, cb.user_data)
				if event_type == .Drag_Start && cb.on_drag_start != nil do cb.on_drag_start(e, cb.user_data)
				if event_type == .Drag && cb.on_drag != nil do cb.on_drag(e, cb.user_data)
				if event_type == .Drag_Enter && cb.on_drag_enter != nil do cb.on_drag_enter(e, cb.user_data)
				if event_type == .Drag_Leave && cb.on_drag_leave != nil do cb.on_drag_leave(e, cb.user_data)
				if event_type == .Drag_Over && cb.on_drag_over != nil do cb.on_drag_over(e, cb.user_data)
				if event_type == .Drag_End && cb.on_drag_end != nil do cb.on_drag_end(e, cb.user_data)
				if event_type == .Drop && cb.on_drop != nil do cb.on_drop(e, cb.user_data)
				if event_type == .Key_Down && cb.on_key_down != nil do cb.on_key_down(e, cb.user_data)
				if event_type == .Text_Input && cb.on_text_input != nil do cb.on_text_input(e, cb.user_data)
				if event_type == .Custom && cb.on_custom != nil do cb.on_custom(e, cb.user_data)
			}
		}

		current = current.parent
	}
}

dispatch_custom_event :: proc(
	ctx: ^Event_Context,
	target_id: Box_ID,
	event_name: string,
	payload: rawptr = nil,
) {
	target_box, ok := ctx.layout.all_boxes[target_id]
	if !ok do return

	ui_ev := UI_Event {
		target         = target_id,
		custom_name    = event_name,
		custom_payload = payload,
	}

	bubble_event(ctx, target_box, .Custom, &ui_ev)
}
