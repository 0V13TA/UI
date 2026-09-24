package UI

import "core:strings"
import sdl "vendor:sdl2"

Event_Type :: enum {
	Click,
	Scroll,
	Key_Down,
	Text_Input,
	Custom,
}

Event_Callbacks :: struct {
	focusable:      bool,
	cursor:         sdl.SystemCursor,

	// Mouse
	on_click:       proc(e: ^UI_Event, data: rawptr),
	on_hover_enter: proc(id: Box_ID, data: rawptr),
	on_hover_exit:  proc(id: Box_ID, data: rawptr),
	on_scroll:      proc(e: ^UI_Event, data: rawptr),

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
	hovered_id:           Box_ID,
	pressed_id:           Box_ID,
	focused_id:           Box_ID,
	prev_focused_id:      Box_ID,
	prev_pressed_id:      Box_ID,
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
	stop_propagation: bool,
}

begin_frame :: proc(ctx: ^Event_Context) {
	clear(&ctx.clicked_this_frame)
	ctx.prev_focused_id = ctx.focused_id
	ctx.prev_pressed_id = ctx.pressed_id
	clear(&ctx.focus_order) // (From your earlier changes)
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

	ctx.focused_id = ctx.focus_order[idx]
}

register :: proc(ctx: ^Event_Context, id: Box_ID, callbacks: Event_Callbacks) {
	ctx.listeners[id] = callbacks
	if callbacks.focusable {
		append(&ctx.focus_order, id) // Collect the natural DOM order
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

	delete_key(&ctx.listeners, id)
}

set_focus :: proc(ctx: ^Event_Context, new_focus: Box_ID) {
	if ctx.focused_id == new_focus do return

	if old_cb, ok := ctx.listeners[ctx.focused_id]; ok && old_cb.on_focus_exit != nil {
		old_cb.on_focus_exit(ctx.focused_id, old_cb.user_data)
	}

	ctx.focused_id = new_focus

	if new_cb, ok := ctx.listeners[new_focus]; ok && new_cb.on_focus_enter != nil {
		new_cb.on_focus_enter(new_focus, new_cb.user_data)
	}
}

update_hover :: proc(ctx: ^Event_Context, new_hovered_id: Box_ID) {
	if ctx.hovered_id != new_hovered_id {
		if old_cb, ok := ctx.listeners[ctx.hovered_id]; ok && old_cb.on_hover_exit != nil {
			old_cb.on_hover_exit(ctx.hovered_id, old_cb.user_data)
		}
		if new_cb, ok := ctx.listeners[new_hovered_id]; ok && new_cb.on_hover_enter != nil {
			new_cb.on_hover_enter(new_hovered_id, new_cb.user_data)
		}
		ctx.hovered_id = new_hovered_id
	}
}

get_hovered_box :: proc(ctx: ^Event_Context, box: ^Box, mx, my: f32) -> ^Box {
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

pump_events :: proc(ctx: ^Event_Context, e: ^sdl.Event) {
	mx, my: i32
	sdl.GetMouseState(&mx, &my)

	hovered_box: ^Box = nil
	#reverse for root in ctx.layout.root_boxes {
		if hit := get_hovered_box(ctx, root, f32(mx), f32(my)); hit != nil {
			hovered_box = hit
			break
		}
	}

	current_hovered_id := hovered_box != nil ? hovered_box.id : 0

	// Constantly verify hover state to catch layout shifts occurring without mouse motion
	update_hover(ctx, current_hovered_id)

	#partial switch e.type {
	case .MOUSEBUTTONDOWN:
		if e.button.button == sdl.BUTTON_LEFT {
			focus_target: Box_ID = 0
			curr := hovered_box
			for curr != nil {
				if cb, ok := ctx.listeners[curr.id]; ok && cb.focusable {
					focus_target = curr.id
					break
				}
				curr = curr.parent
			}

			// Snap the press to the interactive parent
			if focus_target != 0 {
				ctx.pressed_id = focus_target
				set_focus(ctx, focus_target)
			} else {
				ctx.pressed_id = current_hovered_id
				set_focus(ctx, 0)
			}
		}
		if e.button.button == sdl.BUTTON_RIGHT {
			// Snap the right click to the nearest interactive parent
			target: Box_ID = 0
			curr := hovered_box
			for curr != nil {
				if cb, ok := ctx.listeners[curr.id]; ok && cb.focusable {
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
			if ctx.pressed_id != 0 {
				release_target: Box_ID = 0
				curr := hovered_box
				for curr != nil {
					if cb, ok := ctx.listeners[curr.id]; ok && cb.focusable {
						release_target = curr.id
						break
					}
					curr = curr.parent
				}
				if release_target == 0 do release_target = current_hovered_id

				// The release must match the interactive parent that was pressed
				if ctx.pressed_id == release_target {
					if target_box, ok := ctx.layout.all_boxes[ctx.pressed_id]; ok {
						ui_ev := UI_Event {
							target  = ctx.pressed_id,
							mouse_x = f32(mx),
							mouse_y = f32(my),
						}
						bubble_event(ctx, target_box, .Click, &ui_ev)
					}
				}
				ctx.pressed_id = 0
			}
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
		if event_type == .Scroll {
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

		if event_type == .Click {
			ctx.clicked_this_frame[current.id] = true
		}
		// 2. Trigger User Callbacks
		if cb, ok := ctx.listeners[current.id]; ok {
			if event_type == .Click && cb.on_click != nil do cb.on_click(e, cb.user_data)
			if event_type == .Scroll && cb.on_scroll != nil do cb.on_scroll(e, cb.user_data)
			if event_type == .Key_Down && cb.on_key_down != nil do cb.on_key_down(e, cb.user_data)
			if event_type == .Text_Input && cb.on_text_input != nil do cb.on_text_input(e, cb.user_data)
			if event_type == .Custom && cb.on_custom != nil do cb.on_custom(e, cb.user_data)
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
