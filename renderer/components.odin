package renderer

import anim "../animations"
import "../events"
import lc "../layout_calc"
import "core:fmt"
import "core:hash"
import sdl "vendor:sdl2"
import img "vendor:sdl2/image"

text :: proc(
	ui_ctx: ^UI_Context,
	ev_ctx: ^events.Event_Context,
	text: string,
	user_style := Style{},
	salt := "",
	loc := #caller_location,
) {
	hash_input := fmt.tprintf("%s:%d:%s", loc.file_path, loc.line, salt)
	id := lc.ID(hash_input)

	events.register(ev_ctx, id, events.Event_Callbacks{focusable = true})

	is_pressed := ev_ctx.pressed_id == id
	just_pressed := is_pressed && ev_ctx.prev_pressed_id != id
	is_focused := ev_ctx.focused_id == id

	if id not_in ev_ctx.text_cursors do ev_ctx.text_cursors[id] = 0
	if id not_in ev_ctx.text_selection do ev_ctx.text_selection[id] = 0

	if !is_focused {
		ev_ctx.text_selection[id] = 0
		ev_ctx.text_cursors[id] = 0
	}

	if is_pressed {
		if prev_box, ok := ui_ctx.layout.prev_all_boxes[id]; ok {
			mx, my: i32
			sdl.GetMouseState(&mx, &my)
			local_x := f32(mx) - prev_box.x

			dummy_el := Element {
				resolved_font = ui_ctx.fonts[hash.fnv32(transmute([]byte)string("default_font"))],
			}
			dummy_box := lc.Box {
				user_data = &dummy_el,
			}

			best_cursor := 0
			for i in 0 ..= len(text) {
				x := ui_text_width(&dummy_box, text[:i])
				if i == len(text) {
					best_cursor = i
					break
				}
				next_x := ui_text_width(&dummy_box, text[:i + 1])
				if local_x < (x + next_x) * 0.5 {
					best_cursor = i
					break
				}
			}

			ev_ctx.text_cursors[id] = best_cursor
			if just_pressed {
				ev_ctx.text_selection[id] = best_cursor
			}
		}
	}

	final_style := user_style
	if user_style.text_wrap == nil do final_style.text_wrap = .WORD
	if ev_ctx.text_cursors[id] != ev_ctx.text_selection[id] {
		final_style.selection_start = ev_ctx.text_selection[id]
		final_style.selection_end = ev_ctx.text_cursors[id]
	}

	element_open(ui_ctx, Element{_box = {id = id}, text = text, style = final_style}, loc)
	element_close(ui_ctx)
}

button :: proc(
	ui_ctx: ^UI_Context,
	ev_ctx: ^events.Event_Context,
	text: string,
	user_style := Style{},
	salt := "",
	id: lc.Box_ID = 0,
	loc := #caller_location,
) -> bool {
	final_id := id
	if final_id == 0 {
		hash_input := fmt.tprintf("%s:%d:%s", loc.file_path, loc.line, salt)
		final_id = lc.ID(hash_input)
	}

	is_hovered := ev_ctx.hovered_id == final_id
	is_pressed := ev_ctx.pressed_id == final_id
	is_clicked := ev_ctx.clicked_this_frame[final_id] or_else false

	events.register(ev_ctx, final_id, events.Event_Callbacks{focusable = true, cursor = .HAND})

	// Fall back to default theme colors if not provided
	bg := user_style.bg_color.? or_else Color{0.15, 0.4, 0.8, 1.0}
	if is_pressed {
		bg = Color{bg[0] * 0.7, bg[1] * 0.7, bg[2] * 0.7, bg[3]}
	} else if is_hovered {
		bg = Color{min(bg[0] * 1.2, 1.0), min(bg[1] * 1.2, 1.0), min(bg[2] * 1.2, 1.0), bg[3]}
	}

	final_style := user_style
	final_style.bg_color = bg
	if final_style.padding == nil do final_style.padding = space_2(12, 24)
	if final_style.border_radius == nil do final_style.border_radius = space(6)
	if final_style.text_color == nil do final_style.text_color = Color{1, 1, 1, 1}
	if final_style.text_align == nil do final_style.text_align = .CENTER
	if final_style.width == nil do final_style.width = lc.Fit(true)
	if final_style.height == nil do final_style.height = lc.Fit(true)

	element_open(ui_ctx, Element{_box = {id = final_id}, text = text, style = final_style}, loc)
	element_close(ui_ctx)

	return is_clicked
}

// --- TOOLTIP COMPONENT ---
tooltip_begin :: proc(
	ui_ctx: ^UI_Context,
	ev_ctx: ^events.Event_Context,
	target_id: lc.Box_ID,
	user_style := Style{},
	loc := #caller_location,
) -> bool {
	// Immediate Mode Magic: If the target isn't hovered, we return false and skip rendering the children!
	if ev_ctx.hovered_id != target_id do return false

	// Fetch the target's position from the previous frame to anchor the tooltip
	target_x, target_y, target_w, target_h: f32 = 0, 0, 0, 0
	if prev, ok := ui_ctx.layout.prev_all_boxes[target_id]; ok {
		target_x = prev.x
		target_y = prev.y
		target_w = prev.computed_width
		target_h = prev.computed_height
	}

	final_style := user_style
	final_style.position = .FIXED
	final_style.z_index = 1000

	// Default positioning (Anchored below the target)
	if final_style.left == nil do final_style.left = target_x
	if final_style.top == nil do final_style.top = target_y + target_h + 10.0
	if final_style.z_index == nil do final_style.z_index = 1000

	// Default Layout & Visuals
	if final_style.direction == nil do final_style.direction = .COLUMN
	if final_style.bg_color == nil do final_style.bg_color = Color{0.1, 0.1, 0.15, 0.95}
	if final_style.border_color == nil do final_style.border_color = Color{1, 1, 1, 0.1}
	if final_style.border == nil do final_style.border = space(1)
	if final_style.border_radius == nil do final_style.border_radius = space(6)
	if final_style.padding == nil do final_style.padding = space_2(8, 12)
	if final_style.width == nil do final_style.width = lc.Fit(true)
	if final_style.height == nil do final_style.height = lc.Fit(true)

	tooltip_id := lc.Box_ID(hash.fnv32(transmute([]byte)fmt.tprintf("tooltip_%d", target_id)))
	element_open(ui_ctx, Element{_box = {id = tooltip_id}, style = final_style}, loc)
	return true
}

tooltip_end :: proc(ui_ctx: ^UI_Context, is_open: bool) {
	if is_open do element_close(ui_ctx)
}

scroll_begin :: proc(
	ui_ctx: ^UI_Context,
	ev_ctx: ^events.Event_Context,
	id: lc.Box_ID = 0,
	scroll_y: bool = true,
	scroll_x: bool = false,
	user_style := Style{},
	salt := "",
	loc := #caller_location,
) {
	// Generate a stable ID if an explicit one wasn't provided
	final_id := id
	if final_id == 0 {
		hash_input := fmt.tprintf("%s:%d:%s", loc.file_path, loc.line, salt)
		final_id = lc.ID(hash_input)
	}

	// Apply scroll overflow styles conditionally
	final_style := user_style
	if scroll_y do final_style.overflow_y = .SCROLL
	if scroll_x do final_style.overflow_x = .SCROLL

	// Auto-assign the most logical flex direction if the user didn't specify one
	if final_style.direction == nil {
		final_style.direction = scroll_y ? lc.Direction.COLUMN : lc.Direction.ROW
	}

	element_open(
		ui_ctx,
		Element {
			_box = {
				id = final_id,
				offset_y = scroll_y ? ev_ctx.scroll_offsets_y[final_id] : 0,
				offset_x = scroll_x ? ev_ctx.scroll_offsets_x[final_id] : 0,
			},
			style = final_style,
		},
		loc,
	)
}

scroll_end :: proc(ctx: ^UI_Context) {
	element_close(ctx)
}

// --- CHECKBOX ---
DEFAULT_CHECKBOX_WRAPPER_STYLE :: Style{ width = lc.Fit(true), height = lc.Fit(true), direction = .ROW, align_items = .CENTER, gap = 12, padding = [4]f32{8, 12, 8, 12}, border_radius = [4]f32{6, 6, 6, 6}, bg_color = Color{0, 0, 0, 0} }
DEFAULT_CHECKBOX_BOX_STYLE     :: Style{ width = lc.Fixed{24}, height = lc.Fixed{24}, border_radius = [4]f32{6, 6, 6, 6}, border = [4]f32{2, 2, 2, 2}, border_color = Color{0.8, 0.8, 0.8, 1}, bg_color = Color{1, 1, 1, 1} }
DEFAULT_CHECKBOX_TEXT_STYLE    :: Style{ font_size = 18, text_color = Color{0.2, 0.2, 0.2, 1} }

checkbox :: proc(
	ui_ctx: ^UI_Context,
	ev_ctx: ^events.Event_Context,
	label: string,
	state: ^bool,
	wrapper_style: Style = DEFAULT_CHECKBOX_WRAPPER_STYLE,
	box_style: Style     = DEFAULT_CHECKBOX_BOX_STYLE,
	text_style: Style    = DEFAULT_CHECKBOX_TEXT_STYLE,
	checked_color: Color  = {0.15, 0.4, 0.8, 1.0},
	hover_bg_color: Color = {0.9, 0.9, 0.92, 1.0},
	salt := "",
	loc := #caller_location,
) -> bool {
	hash_input := fmt.tprintf("%s:%d:%s", loc.file_path, loc.line, salt)
	root_id := lc.ID(hash_input)
	box_id := lc.ID(fmt.tprintf("%d_box", root_id))
	text_id := lc.ID(fmt.tprintf("%d_text", root_id))

	events.register(ev_ctx, root_id, events.Event_Callbacks{focusable = true, cursor = .HAND})
	if ev_ctx.clicked_this_frame[root_id] or_else false do state^ = !state^

	// Robust spatial hover check that ignores children blocking the raycast
	is_hovered := false
	if prev, ok := ui_ctx.layout.prev_all_boxes[root_id]; ok {
		mx, my: i32
		sdl.GetMouseState(&mx, &my)
		f_mx, f_my := f32(mx), f32(my)
		is_hovered =
			f_mx >= prev.x &&
			f_mx <= prev.x + prev.computed_width &&
			f_my >= prev.y &&
			f_my <= prev.y + prev.computed_height
	}

	final_wrapper := wrapper_style
	if is_hovered do final_wrapper.bg_color = hover_bg_color

	element_open(ui_ctx, Element{_box = {id = root_id}, style = final_wrapper}, loc)

	final_box := box_style
	if state^ do final_box.bg_color = checked_color
	
	element_open(ui_ctx, Element{_box = {id = box_id}, style = final_box})
	element_close(ui_ctx)

	element_open(ui_ctx, Element{_box = {id = text_id}, text = label, style = text_style})
	element_close(ui_ctx)
	
	element_close(ui_ctx)
	return ev_ctx.clicked_this_frame[root_id] or_else false
}

// --- RADIO BUTTON ---
DEFAULT_RADIO_WRAPPER_STYLE :: Style{ width = lc.Fit(true), height = lc.Fit(true), direction = .ROW, align_items = .CENTER, gap = 12, padding = [4]f32{8, 12, 8, 12}, border_radius = [4]f32{6, 6, 6, 6}, bg_color = Color{0, 0, 0, 0} }
DEFAULT_RADIO_BUTTON_STYLE  :: Style{ width = lc.Fixed{24}, height = lc.Fixed{24}, border_radius = [4]f32{12, 12, 12, 12}, border = [4]f32{2, 2, 2, 2}, border_color = Color{0.8, 0.8, 0.8, 1.0}, bg_color = Color{1, 1, 1, 1} }
DEFAULT_RADIO_TEXT_STYLE    :: Style{ font_size = 18, text_color = Color{0.2, 0.2, 0.2, 1} }

radio :: proc(
	ui_ctx: ^UI_Context,
	ev_ctx: ^events.Event_Context,
	label: string,
	state: ^$T,
	value: T,
	wrapper_style: Style = DEFAULT_RADIO_WRAPPER_STYLE,
	button_style: Style  = DEFAULT_RADIO_BUTTON_STYLE,
	text_style: Style    = DEFAULT_RADIO_TEXT_STYLE,
	active_color: Color   = {0.15, 0.4, 0.8, 1.0},
	hover_bg_color: Color = {0.9, 0.9, 0.92, 1.0},
	salt := "",
	loc := #caller_location,
) -> bool {
	hash_input := fmt.tprintf("%s:%d:%s:%v", loc.file_path, loc.line, salt, value)
	root_id := lc.ID(hash_input)
	button_id := lc.ID(fmt.tprintf("%d_btn", root_id))
	text_id := lc.ID(fmt.tprintf("%d_text", root_id))

	events.register(ev_ctx, root_id, events.Event_Callbacks{focusable = true, cursor = .HAND})
	if ev_ctx.clicked_this_frame[root_id] or_else false do state^ = value
	is_active := state^ == value

	is_hovered := false
	if prev, ok := ui_ctx.layout.prev_all_boxes[root_id]; ok {
		mx, my: i32
		sdl.GetMouseState(&mx, &my)
		f_mx, f_my := f32(mx), f32(my)
		is_hovered =
			f_mx >= prev.x &&
			f_mx <= prev.x + prev.computed_width &&
			f_my >= prev.y &&
			f_my <= prev.y + prev.computed_height
	}

	final_wrapper := wrapper_style
	if is_hovered do final_wrapper.bg_color = hover_bg_color

	element_open(ui_ctx, Element{_box = {id = root_id}, style = final_wrapper}, loc)

	final_button := button_style
	if is_active {
		final_button.border_color = active_color
		final_button.border = [4]f32{7, 7, 7, 7}
	}

	element_open(ui_ctx, Element{_box = {id = button_id}, style = final_button})
	element_close(ui_ctx)

	element_open(ui_ctx, Element{_box = {id = text_id}, text = label, style = text_style})
	element_close(ui_ctx)
	
	element_close(ui_ctx)
	return ev_ctx.clicked_this_frame[root_id] or_else false
}

// --- SLIDER ---
DEFAULT_SLIDER_WRAPPER_STYLE :: Style{ width = lc.Percent{100}, height = lc.Fixed{30}, justify_content = .START, align_items = .CENTER }
DEFAULT_SLIDER_TRACK_STYLE   :: Style{ width = lc.Percent{100}, height = lc.Fixed{8}, bg_color = Color{0.85, 0.85, 0.85, 1}, border_radius = [4]f32{4, 4, 4, 4} }
DEFAULT_SLIDER_FILL_STYLE    :: Style{ height = lc.Percent{100}, bg_color = Color{0.15, 0.4, 0.8, 1.0}, border_radius = [4]f32{4, 4, 4, 4} }
DEFAULT_SLIDER_THUMB_STYLE   :: Style{ position = .ABSOLUTE, top = 5.0, width = lc.Fixed{20}, height = lc.Fixed{20}, bg_color = Color{1, 1, 1, 1}, border_radius = [4]f32{10, 10, 10, 10}, border = [4]f32{2, 2, 2, 2}, border_color = Color{0.15, 0.4, 0.8, 1.0} }

slider :: proc(
	ui_ctx: ^UI_Context,
	ev_ctx: ^events.Event_Context,
	anim_ctx: ^anim.Context,
	value: ^f32,
	min_val, max_val: f32,
	wrapper_style: Style = DEFAULT_SLIDER_WRAPPER_STYLE,
	track_style: Style   = DEFAULT_SLIDER_TRACK_STYLE,
	fill_style: Style    = DEFAULT_SLIDER_FILL_STYLE,
	thumb_style: Style   = DEFAULT_SLIDER_THUMB_STYLE,
	salt := "",
	loc := #caller_location,
) -> bool {
	hash_input := fmt.tprintf("%s:%d:%s", loc.file_path, loc.line, salt)
	root_id := lc.ID(hash_input)
	track_id := lc.ID(fmt.tprintf("%d_track", root_id))
	fill_id  := lc.ID(fmt.tprintf("%d_fill", root_id))
	thumb_id := lc.ID(fmt.tprintf("%d_thumb", root_id))
	
	events.register(ev_ctx, root_id, events.Event_Callbacks{focusable = true})

	changed := false
	is_pressed := ev_ctx.pressed_id == root_id
	was_pressed := ev_ctx.prev_pressed_id == root_id
	just_pressed := is_pressed && !was_pressed
	is_dragging := is_pressed && was_pressed

	if is_pressed {
		if prev_box, ok := ui_ctx.layout.prev_all_boxes[root_id]; ok {
			mx, my: i32
			sdl.GetMouseState(&mx, &my)
			local_x := f32(mx) - prev_box.x
			percent := clamp(local_x / prev_box.computed_width, 0.0, 1.0)
			new_val := min_val + (max_val - min_val) * percent

			if new_val != value^ {
				if just_pressed {
					// Slower, expressive tween for the initial jump
					anim.to(
						&anim_ctx.engine,
						anim.Tween_Vars {
							duration = 0.25,
							ease_func = anim.ease_out_exp,
							properties = {{target = value, to = new_val}},
						},
					)
				} else if is_dragging {
					// Fast tween for dragging to override the click animation
					anim.to(
						&anim_ctx.engine,
						anim.Tween_Vars {
							duration = 0.05,
							ease_func = anim.ease_linear,
							properties = {{target = value, to = new_val}},
						},
					)
				}
				changed = true
			}
		}
	}

	fill_percent := clamp((value^ - min_val) / (max_val - min_val), 0.0, 1.0)

	// 1. Wrapper
	element_open(ui_ctx, Element{_box = {id = root_id}, style = wrapper_style}, loc)

	// 2. Track
	element_open(ui_ctx, Element{_box = {id = track_id}, style = track_style})
	
	// 3. Fill
	dynamic_fill := fill_style
	dynamic_fill.width = lc.Percent{fill_percent * 100.0}
	element_open(ui_ctx, Element{_box = {id = fill_id}, style = dynamic_fill})
	element_close(ui_ctx) // close fill
	
	element_close(ui_ctx) // close track

	thumb_x: f32 = 0.0
	if prev, ok := ui_ctx.layout.prev_all_boxes[root_id]; ok {
		thumb_x = (fill_percent * prev.computed_width) - 10.0
	}

	// 4. Thumb
	dynamic_thumb := thumb_style
	dynamic_thumb.position = .ABSOLUTE
	dynamic_thumb.left = thumb_x
	element_open(ui_ctx, Element{_box = {id = thumb_id}, style = dynamic_thumb})
	element_close(ui_ctx) // close thumb
	
	element_close(ui_ctx) // close wrapper
	
	return changed
}

// --- TEXT INPUT ---
DEFAULT_TEXT_INPUT_WRAPPER_STYLE :: Style{ width = lc.Percent{100}, height = lc.Fixed{50}, padding = [4]f32{5, 5, 5, 5}, border_radius = [4]f32{6, 6, 6, 6}, border = [4]f32{2, 2, 2, 2}, border_color = Color{0.8, 0.8, 0.8, 1}, bg_color = Color{1, 1, 1, 1} }
DEFAULT_TEXT_INPUT_TEXT_STYLE    :: Style{ width = lc.Fit(true), height = lc.Fit(true), font_size = 18, text_wrap = .NONE, text_color = Color{0.1, 0.1, 0.1, 1} }

@(private)
_delete_selection :: proc(
	buf: ^[dynamic]u8,
	ev_ctx: ^events.Event_Context,
	id: lc.Box_ID,
) -> bool {
	cursor := clamp(ev_ctx.text_cursors[id], 0, len(buf^))
	anchor := clamp(ev_ctx.text_selection[id], 0, len(buf^))
	if cursor == anchor do return false

	start_idx := min(cursor, anchor)
	end_idx := max(cursor, anchor)

	for _ in 0 ..< (end_idx - start_idx) {
		ordered_remove(buf, start_idx)
	}

	ev_ctx.text_cursors[id] = start_idx
	ev_ctx.text_selection[id] = start_idx
	return true
}

@(private)
_text_input_cb :: proc(e: ^events.UI_Event, data: rawptr) {
	ev_ctx := (^events.Event_Context)(data)
	if ev_ctx.focused_buffer == nil do return

	// Clear highlighted text before inserting new characters
	_delete_selection(ev_ctx.focused_buffer, ev_ctx, e.current_target)

	buf := ev_ctx.focused_buffer
	cursor := clamp(ev_ctx.text_cursors[e.current_target], 0, len(buf^))

	for i in 0 ..< len(e.text) {
		inject_at(buf, cursor + i, e.text[i])
	}
	ev_ctx.text_cursors[e.current_target] = cursor + len(e.text)
	ev_ctx.text_selection[e.current_target] = ev_ctx.text_cursors[e.current_target]
}

@(private)
_key_down_cb :: proc(e: ^events.UI_Event, data: rawptr) {
	ev_ctx := (^events.Event_Context)(data)
	if ev_ctx.focused_buffer == nil do return

	buf := ev_ctx.focused_buffer
	cursor := clamp(ev_ctx.text_cursors[e.current_target], 0, len(buf^))

	anchor := clamp(ev_ctx.text_selection[e.current_target], 0, len(buf^))
	ev_ctx.text_selection[e.current_target] = anchor
	has_selection := cursor != anchor

	// Safely check for LSHIFT/RSHIFT (0x0003) and LCTRL/RCTRL (0x00C0)
	has_shift := (transmute(u16)e.key_mod & 0x0003) != 0
	has_ctrl := (transmute(u16)e.key_mod & 0x00C0) != 0

	#partial switch e.keycode {
	case .a:
		if has_ctrl {
			ev_ctx.text_selection[e.current_target] = 0
			ev_ctx.text_cursors[e.current_target] = len(buf^)
		}
	case .c:
		if has_ctrl && has_selection {
			start_idx := min(cursor, anchor)
			end_idx := max(cursor, anchor)

			// Temp allocate a cstring to pass to SDL
			clipboard_cstr := fmt.ctprintf("%s", string(buf[start_idx:end_idx]))
			sdl.SetClipboardText(clipboard_cstr)
		}

	case .HOME:
		ev_ctx.text_cursors[e.current_target] = 0
		if !has_shift {
			ev_ctx.text_selection[e.current_target] = 0
		}

	case .END:
		ev_ctx.text_cursors[e.current_target] = len(buf^)
		if !has_shift {
			ev_ctx.text_selection[e.current_target] = len(buf^)
		}

	case .x:
		if has_ctrl && has_selection {
			start_idx := min(cursor, anchor)
			end_idx := max(cursor, anchor)

			clipboard_cstr := fmt.ctprintf("%s", string(buf[start_idx:end_idx]))
			sdl.SetClipboardText(clipboard_cstr)

			_delete_selection(buf, ev_ctx, e.current_target)
		}

	case .v:
		if has_ctrl && sdl.HasClipboardText() {
			clipboard_cstr := sdl.GetClipboardText()
			if clipboard_cstr != nil {
				// SDL allocates this string; we own it now and must free it.
				defer sdl.free(rawptr(clipboard_cstr))

				// Clear anything currently highlighted
				_delete_selection(buf, ev_ctx, e.current_target)

				// Grab the fresh cursor position after the potential deletion
				active_cursor := clamp(ev_ctx.text_cursors[e.current_target], 0, len(buf^))
				pasted_str := string(clipboard_cstr)

				// Iterate raw bytes to safely preserve UTF-8 encoding
				for i in 0 ..< len(pasted_str) {
					b := pasted_str[i]
					if b != '\n' && b != '\r' {
						inject_at(buf, active_cursor, b)
						active_cursor += 1
					}
				}

				ev_ctx.text_cursors[e.current_target] = active_cursor
				ev_ctx.text_selection[e.current_target] = active_cursor
			}
		}
	case .ESCAPE:
		if has_selection {
			ev_ctx.text_selection[e.current_target] = cursor
		}
	case .BACKSPACE:
		if !_delete_selection(buf, ev_ctx, e.current_target) {
			if cursor > 0 {
				ordered_remove(buf, cursor - 1)
				ev_ctx.text_cursors[e.current_target] -= 1
				ev_ctx.text_selection[e.current_target] -= 1
			}
		}
	case .DELETE:
		if !_delete_selection(buf, ev_ctx, e.current_target) {
			if cursor < len(buf^) {
				ordered_remove(buf, cursor)
			}
		}
	case .LEFT:
		if has_shift {
			if cursor > 0 do ev_ctx.text_cursors[e.current_target] -= 1
		} else {
			if has_selection {
				ev_ctx.text_cursors[e.current_target] = min(cursor, anchor)
			} else if cursor > 0 {
				ev_ctx.text_cursors[e.current_target] -= 1
			}
			ev_ctx.text_selection[e.current_target] = ev_ctx.text_cursors[e.current_target]
		}
	case .RIGHT:
		if has_shift {
			if cursor < len(buf^) do ev_ctx.text_cursors[e.current_target] += 1
		} else {
			if has_selection {
				ev_ctx.text_cursors[e.current_target] = max(cursor, anchor)
			} else if cursor < len(buf^) {
				ev_ctx.text_cursors[e.current_target] += 1
			}
			ev_ctx.text_selection[e.current_target] = ev_ctx.text_cursors[e.current_target]
		}
	}
}

text_input :: proc(
	ui_ctx: ^UI_Context,
	ev_ctx: ^events.Event_Context,
	buffer: ^[dynamic]u8,
	placeholder := "",
	wrapper_style: Style = DEFAULT_TEXT_INPUT_WRAPPER_STYLE,
	text_style: Style    = DEFAULT_TEXT_INPUT_TEXT_STYLE,
	focused_border_color: Color = {0.15, 0.4, 0.8, 1},
	placeholder_color: Color    = {0.6, 0.6, 0.6, 1},
	salt := "",
	loc := #caller_location,
) -> bool {
	hash_input := fmt.tprintf("%s:%d:%s", loc.file_path, loc.line, salt)
	id := lc.ID(hash_input)
	string_id := lc.ID(fmt.tprintf("%d_text", id))

	events.register(
		ev_ctx,
		id,
		events.Event_Callbacks {
			cursor = .IBEAM,
			focusable = true,
			user_data = ev_ctx,
			on_text_input = _text_input_cb,
			on_key_down = _key_down_cb,
		},
	)

	is_focused := ev_ctx.focused_id == id

	if is_focused {
		sdl.StartTextInput()
		ev_ctx.focused_buffer = buffer

		if id not_in ev_ctx.text_cursors {
			ev_ctx.text_cursors[id] = len(buffer)
		}

		// Start/restart the blink timer when focus is gained.
		if id not_in ev_ctx.cursor_blink_start {
			ev_ctx.cursor_blink_start[id] = u64(sdl.GetTicks())
		}
	} else if ev_ctx.focused_buffer == buffer {
		sdl.StopTextInput()
		ev_ctx.focused_buffer = nil
	}

	cursor := clamp(ev_ctx.text_cursors[id], 0, len(buffer))

	// Dummy element used to measure text.
	dummy_el := Element {
		resolved_font = ui_ctx.fonts[hash.fnv32(transmute([]byte)string("default_font"))],
	}

	dummy_box := lc.Box {
		user_data = &dummy_el,
	}

	// ------------------------------------------------------------
	// Mouse click & Drag -> cursor position
	// ------------------------------------------------------------
	is_pressed := ev_ctx.pressed_id == id
	was_pressed := ev_ctx.prev_pressed_id == id
	just_pressed := is_pressed && !was_pressed

	if is_pressed {
		if prev_inner, ok := ui_ctx.layout.prev_all_boxes[string_id]; ok {
			mx, my: i32
			sdl.GetMouseState(&mx, &my)
			local_x := f32(mx) - prev_inner.x

			best_cursor := 0
			for i in 0 ..= len(buffer) {
				x := ui_text_width(&dummy_box, string(buffer^[:i]))
				if i == len(buffer) {best_cursor = i; break}

				next_x := ui_text_width(&dummy_box, string(buffer^[:i + 1]))
				if local_x < (x + next_x) * 0.5 {best_cursor = i; break}
			}

			ev_ctx.text_cursors[id] = best_cursor
			cursor = best_cursor

			// Anchor the text highlight the exact frame the mouse goes down
			if just_pressed {
				ev_ctx.text_selection[id] = best_cursor
				ev_ctx.cursor_blink_start[id] = u64(sdl.GetTicks())
			}

			// ADD CLAMP HERE
			anchor := clamp(ev_ctx.text_selection[id], 0, len(buffer))
			ev_ctx.text_selection[id] = anchor // Keep state in sync
		}
	}


	// ------------------------------------------------------------
	// Detect keyboard/text changes and restart blinking
	// ------------------------------------------------------------

	if is_focused {
		// The callbacks have already modified the cursor by the
		// time this function is called again. If the cursor changed
		// this frame, restart blinking.
		//
		// Store the last known cursor position in the same map.
		if id not_in ev_ctx.cursor_last_position {
			ev_ctx.cursor_last_position[id] = cursor
		}

		if ev_ctx.cursor_last_position[id] != cursor {
			ev_ctx.cursor_last_position[id] = cursor
			ev_ctx.cursor_blink_start[id] = u64(sdl.GetTicks())
		}
	}

	current_len := len(buffer^)

	// Clamp BOTH the cursor and the selection anchor
	cursor = clamp(ev_ctx.text_cursors[id], 0, current_len)
	anchor := clamp(ev_ctx.text_selection[id], 0, current_len)

	// ------------------------------------------------------------
	// Calculate cursor position
	// ------------------------------------------------------------

	cursor_px := ui_text_width(&dummy_box, string(buffer^[:cursor]))


	// ------------------------------------------------------------
	// Auto-scroll so cursor stays visible
	// ------------------------------------------------------------
	if is_focused {
		if prev_outer, ok := ui_ctx.layout.prev_all_boxes[id]; ok {
			scroll_x := ev_ctx.scroll_offsets_x[id]

			padding_left := prev_outer.padding[3]
			border_left := prev_outer.border[3]

			// The usable horizontal viewport.
			viewport_left := padding_left + border_left
			viewport_right :=
				prev_outer.computed_width - prev_outer.padding[1] - prev_outer.border[1]
			viewport_width := max(viewport_right - viewport_left, 1.0)

			// Cursor position in the text's unscrolled coordinate space.
			cursor_px := ui_text_width(&dummy_box, string(buffer^[:cursor]))

			// Small amount of space around the cursor.
			margin: f32 = 5.0
			cursor_left := cursor_px
			cursor_right := cursor_px + 2.0

			// Cursor has gone past the left side.
			if cursor_left < scroll_x + margin {
				ev_ctx.scroll_offsets_x[id] = max(cursor_left - margin, 0)
			} else if cursor_right > scroll_x + viewport_width - margin {
				ev_ctx.scroll_offsets_x[id] = cursor_right - viewport_width + margin
			}

			// CLAMP SCROLL: Prevent the text from floating away from the right edge
			// when characters are deleted and the total text width shrinks.
			total_text_width := ui_text_width(&dummy_box, string(buffer^[:]))
			max_scroll := max(total_text_width + 15.0 - viewport_width, 0.0)

			ev_ctx.scroll_offsets_x[id] = clamp(ev_ctx.scroll_offsets_x[id], 0.0, max_scroll)

			// Mutate the previous frame's box so the layout engine
			// copies THIS new value instead of restoring the old one.
			prev_outer.offset_x = ev_ctx.scroll_offsets_x[id]
		}
	}

	// ------------------------------------------------------------
	// Text
	// ------------------------------------------------------------

	display_text := ""
	if len(buffer) > 0 do display_text = string(buffer^[:])
	else do display_text = placeholder

	// ------------------------------------------------------------
	// Cursor blink
	// ------------------------------------------------------------

	cursor_visible := false

	if is_focused {
		elapsed := u64(sdl.GetTicks()) - ev_ctx.cursor_blink_start[id]

		// Visible for 500ms, invisible for 500ms.
		cursor_visible = (elapsed % 1000) < 500
	}

	// ------------------------------------------------------------
	// Scroll container
	// ------------------------------------------------------------

	final_wrapper := wrapper_style
	if is_focused do final_wrapper.border_color = focused_border_color

	scroll_begin(
		ui_ctx,
		ev_ctx,
		id = id,
		scroll_y = false,
		scroll_x = true,
		user_style = final_wrapper,
		loc = loc,
	)

	// ------------------------------------------------------------
	// Selection Highlight
	// ------------------------------------------------------------
	start_idx := min(cursor, anchor)
	end_idx := max(cursor, anchor)

	if start_idx != end_idx {
		start_px := ui_text_width(&dummy_box, string(buffer^[:start_idx]))
		end_px := ui_text_width(&dummy_box, string(buffer^[:end_idx]))

		element_open(
			ui_ctx,
			Element {
				style = {
					position = .ABSOLUTE,
					left     = start_px,
					top      = 2.0,
					width    = lc.Fixed{end_px - start_px},
					height   = lc.Percent{100},
					bg_color = Color{0.2, 0.5, 0.9, 0.4}, // Translucent blue
				},
			},
			loc,
		)
		element_close(ui_ctx)
	}

	// ------------------------------------------------------------
	// Text element
	// ------------------------------------------------------------

	final_text := text_style
	if len(buffer) == 0 do final_text.text_color = placeholder_color
	else do final_text.text_color = text_style.text_color

	element_open(
		ui_ctx,
		Element {
			_box = {id = string_id},
			text = display_text,
			style = final_text,
		},
		loc,
	)

	element_close(ui_ctx)

	// ------------------------------------------------------------
	// Cursor
	//
	// This is deliberately NOT part of the text string.
	// Its X position is the measured width of the text before
	// the cursor, and because it is inside the scroll container,
	// it moves with the text.
	// ------------------------------------------------------------

	if cursor_visible {
		element_open(
			ui_ctx,
			Element {
				style = {
					position = .ABSOLUTE,
					left = cursor_px,
					top = 4.0,
					width = lc.Fixed{2},
					height = lc.Fixed{27},
					bg_color = Color{0.1, 0.1, 0.1, 1},
				},
			},
			loc,
		)

		element_close(ui_ctx)
	}

	scroll_end(ui_ctx)

	return is_focused
}

// --- OVERLOAD BLOCK ---
image :: proc {
	image_texture,
	image_path,
}

// The original base component (renamed)
image_texture :: proc(
	ui_ctx: ^UI_Context,
	texture: ^sdl.Texture,
	user_style := Style{},
	loc := #caller_location,
) {
	final_style := user_style
	final_style.bg_image = texture

	tex_w, tex_h: i32 = 0, 0
	if texture != nil do sdl.QueryTexture(texture, nil, nil, &tex_w, &tex_h)

	if final_style.width == nil do final_style.width = lc.Fixed{f32(tex_w)}
	if final_style.height == nil do final_style.height = lc.Fixed{f32(tex_h)}

	element_open(ui_ctx, Element{style = final_style}, loc)
	element_close(ui_ctx)
}

// The new path-based component
image_path :: proc(
	ui_ctx: ^UI_Context,
	sdl_rend: ^sdl.Renderer,
	path: string,
	user_style: Style = {},
	loc := #caller_location,
) {
	// Hash the file path to use as a fast map key
	path_hash := hash.fnv32(transmute([]byte)path)

	// Fetch from cache, or load from disk if missing
	tex, exists := ui_ctx.image_cache[path_hash]
	if !exists {
		c_path := fmt.ctprintf("%s", path)
		tex = img.LoadTexture(sdl_rend, c_path)
		if tex == nil {
			fmt.printfln("ERROR: Failed to load image '%s': %s", path, sdl.GetError())
		}
		ui_ctx.image_cache[path_hash] = tex
	}

	// Pass the cached texture down to the base component
	image_texture(ui_ctx, tex, user_style, loc)
}

video :: proc(
	ctx: ^UI_Context,
	rend: ^sdl.Renderer,
	path: string,
	dt: f64,
	user_style: Style = {},
	id: lc.Box_ID = 0,
) {
	// Cache Layer: Init if it doesn't exist
	if path not_in ctx.videos {
		// Note: Use strings.clone_to_cstring(path, context.temp_allocator)
		// if your init function strictly requires a cstring.
		ctx.videos[path] = video_player_init(rend, path)
	}

	player := ctx.videos[path]

	// Playback Layer: Advance the media clocks
	if player != nil && player.is_playing {
		video_player_update(player, dt)
	}

	// Presentation Layer: Emit the layout node
	// (Mirror exactly how your existing `image` component works)
	el := element_open(ctx, {id = id, style = user_style})

	if player != nil && player.texture != nil {
		// Prevent the green FFmpeg startup flash
		if player.playback_time > 0.1 {
			el.resolved_bg_image = player.texture // Attach the decoded frame
		}
	}

	element_close(ctx)
}
