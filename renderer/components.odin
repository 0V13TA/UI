package renderer

import anim "../animations"
import "../events"
import lc "../layout_calc"
import "core:fmt"
import "core:hash"
import "core:math"
import "core:strings"
import sdl "vendor:sdl2"
import img "vendor:sdl2/image"

is_tree_hovered :: proc(
	ui_ctx: ^UI_Context,
	ev_ctx: ^events.Event_Context,
	target_id: lc.Box_ID,
) -> bool {
	curr := ev_ctx.hovered_id
	for curr != 0 {
		if curr == target_id do return true

		// Walk up the previous frame's layout tree
		if prev, ok := ui_ctx.layout.prev_all_boxes[curr]; ok && prev.parent != nil {
			curr = prev.parent.id
		} else {
			break
		}
	}
	return false
}

text :: proc(
	ui_ctx: ^UI_Context,
	ev_ctx: ^events.Event_Context,
	text: string,
	user_style := Style{},
	salt := "",
	id: string = "",
	loc := #caller_location,
) {
	id := lc.ID(loc, id)

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


	final_style := user_style
	if user_style.text_wrap == nil do final_style.text_wrap = .WORD
	if ev_ctx.text_cursors[id] != ev_ctx.text_selection[id] {
		final_style.selection_start = ev_ctx.text_selection[id]
		final_style.selection_end = ev_ctx.text_cursors[id]
	}

	font_path := final_style.font_name.? or_else ""
	font_size := final_style.font_size.? or_else 16.0
	active_font := get_font(ui_ctx, font_path, font_size)

	if is_pressed {
		if prev_box, ok := ui_ctx.layout.prev_all_boxes[id]; ok {
			mx, my: i32
			sdl.GetMouseState(&mx, &my)
			local_x := f32(mx) - prev_box.x

			dummy_el := Element {
				resolved_font = active_font,
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

	element_open(ui_ctx, Element{_box = {id = id}, text = text, style = final_style}, loc)
	element_close(ui_ctx)
}

DEFAULT_BUTTON_STYLE :: Style {
	padding       = [4]f32{12, 24, 12, 24},
	border_radius = [4]f32{6, 6, 6, 6},
	text_color    = Color{1, 1, 1, 1},
	text_align    = .CENTER,
	width         = lc.Fit(true),
	height        = lc.Fit(true),
	bg_color      = Color{0.15, 0.4, 0.8, 1.0},
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

	is_hovered := is_tree_hovered(ui_ctx, ev_ctx, final_id)
	is_pressed := ev_ctx.pressed_id == final_id
	is_clicked := ev_ctx.clicked_this_frame[final_id] or_else false

	events.register(ev_ctx, final_id, events.Event_Callbacks{focusable = true, cursor = .HAND})

	// 1. Establish base visuals mixed with user overrides
	final_style := merge_styles(DEFAULT_BUTTON_STYLE, user_style)

	// 2. Resolve dynamic interaction states
	// We safely unwrap bg_color since merge_styles guarantees it falls back to the default
	bg := final_style.bg_color.? or_else Color{0.15, 0.4, 0.8, 1.0}

	if is_pressed {
		final_style.bg_color = Color{bg[0] * 0.7, bg[1] * 0.7, bg[2] * 0.7, bg[3]}
	} else if is_hovered {
		final_style.bg_color = Color {
			min(bg[0] * 1.2, 1.0),
			min(bg[1] * 1.2, 1.0),
			min(bg[2] * 1.2, 1.0),
			bg[3],
		}
	}

	element_open(ui_ctx, Element{_box = {id = final_id}, text = text, style = final_style}, loc)
	element_close(ui_ctx)

	return is_clicked
}

// --- TOOLTIP COMPONENT ---
DEFAULT_TOOLTIP_STYLE :: Style {
	position      = .FIXED,
	z_index       = 1000,
	direction     = .COLUMN,
	bg_color      = Color{0.1, 0.1, 0.15, 0.95},
	border_color  = Color{1, 1, 1, 0.1},
	border        = [4]f32{1, 1, 1, 1},
	border_radius = [4]f32{6, 6, 6, 6},
	padding       = [4]f32{8, 12, 8, 12},
	width         = lc.Fit(true),
	height        = lc.Fit(true),
}

tooltip_begin :: proc(
	ui_ctx: ^UI_Context,
	ev_ctx: ^events.Event_Context,
	target_id: lc.Box_ID,
	user_style := Style{}, // Default is now empty
	loc := #caller_location,
) -> bool {
	if ev_ctx.hovered_id != target_id do return false

	target_x, target_y, target_w, target_h: f32 = 0, 0, 0, 0
	if prev, ok := ui_ctx.layout.prev_all_boxes[target_id]; ok {
		target_x = prev.x
		target_y = prev.y
		target_w = prev.computed_width
		target_h = prev.computed_height
	}

	final_style := merge_styles(DEFAULT_TOOLTIP_STYLE, user_style)

	// Dynamic anchors only apply if the user didn't explicitly override them
	if final_style.left == nil do final_style.left = target_x
	if final_style.top == nil do final_style.top = target_y + target_h + 10.0

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
DEFAULT_CHECKBOX_WRAPPER_STYLE :: Style {
	width         = lc.Fit(true),
	height        = lc.Fit(true),
	direction     = .ROW,
	align_items   = .CENTER,
	gap           = 12,
	padding       = [4]f32{8, 12, 8, 12},
	border_radius = [4]f32{6, 6, 6, 6},
	bg_color      = Color{0, 0, 0, 0},
}
DEFAULT_CHECKBOX_BOX_STYLE :: Style {
	width         = lc.Fixed{24},
	height        = lc.Fixed{24},
	border_radius = [4]f32{6, 6, 6, 6},
	border        = [4]f32{2, 2, 2, 2},
	border_color  = Color{0.8, 0.8, 0.8, 1},
	bg_color      = Color{1, 1, 1, 1},
}
DEFAULT_CHECKBOX_TEXT_STYLE :: Style {
	font_size  = 18,
	text_color = Color{0.2, 0.2, 0.2, 1},
}

checkbox :: proc(
	ui_ctx: ^UI_Context,
	ev_ctx: ^events.Event_Context,
	label: string,
	state: ^bool,
	wrapper_style: Style = {},
	box_style: Style = {},
	text_style: Style = {},
	checked_color: Color = {0.15, 0.4, 0.8, 1.0},
	hover_bg_color: Color = {0.9, 0.9, 0.92, 1.0},
	salt := "",
	id: string = "",
	loc := #caller_location,
) -> bool {
	root_id := id != "" ? lc.ID(id) : lc.ID(loc, salt)
	box_id := lc.ID(root_id, "box")
	text_id := lc.ID(root_id, "text")

	events.register(ev_ctx, root_id, events.Event_Callbacks{focusable = true, cursor = .HAND})
	if ev_ctx.clicked_this_frame[root_id] or_else false do state^ = !state^

	is_hovered := is_tree_hovered(ui_ctx, ev_ctx, root_id)

	final_wrapper := merge_styles(DEFAULT_CHECKBOX_WRAPPER_STYLE, wrapper_style)
	if is_hovered do final_wrapper.bg_color = hover_bg_color

	element_open(ui_ctx, Element{_box = {id = root_id}, style = final_wrapper}, loc)

	final_box := merge_styles(DEFAULT_CHECKBOX_BOX_STYLE, box_style)
	if state^ do final_box.bg_color = checked_color

	element_open(ui_ctx, Element{_box = {id = box_id}, style = final_box})
	element_close(ui_ctx)

	final_text := merge_styles(DEFAULT_CHECKBOX_TEXT_STYLE, text_style)
	element_open(ui_ctx, Element{_box = {id = text_id}, text = label, style = final_text})
	element_close(ui_ctx)

	element_close(ui_ctx)
	return ev_ctx.clicked_this_frame[root_id] or_else false
}

// --- RADIO BUTTON ---
DEFAULT_RADIO_WRAPPER_STYLE :: Style {
	width         = lc.Fit(true),
	height        = lc.Fit(true),
	direction     = .ROW,
	align_items   = .CENTER,
	gap           = 12,
	padding       = [4]f32{8, 12, 8, 12},
	border_radius = [4]f32{6, 6, 6, 6},
	bg_color      = Color{0, 0, 0, 0},
}
DEFAULT_RADIO_BUTTON_STYLE :: Style {
	width         = lc.Fixed{24},
	height        = lc.Fixed{24},
	border_radius = [4]f32{12, 12, 12, 12},
	border        = [4]f32{2, 2, 2, 2},
	border_color  = Color{0.8, 0.8, 0.8, 1.0},
	bg_color      = Color{1, 1, 1, 1},
}
DEFAULT_RADIO_TEXT_STYLE :: Style {
	font_size  = 18,
	text_color = Color{0.2, 0.2, 0.2, 1},
}

radio :: proc(
	ui_ctx: ^UI_Context,
	ev_ctx: ^events.Event_Context,
	label: string,
	state: ^$T,
	value: T,
	wrapper_style: Style = DEFAULT_RADIO_WRAPPER_STYLE,
	button_style: Style = DEFAULT_RADIO_BUTTON_STYLE,
	text_style: Style = DEFAULT_RADIO_TEXT_STYLE,
	active_color: Color = {0.15, 0.4, 0.8, 1.0},
	hover_bg_color: Color = {0.9, 0.9, 0.92, 1.0},
	salt := "",
	id: string = "",
	loc := #caller_location,
) -> bool {
	hash_input := id
	if id == "" do hash_input = fmt.tprintf("%s:%d:%s", loc.file_path, loc.line, salt)

	root_id := lc.ID(hash_input)
	button_id := lc.ID(fmt.tprintf("%d_btn", root_id))
	text_id := lc.ID(fmt.tprintf("%d_text", root_id))

	events.register(ev_ctx, root_id, events.Event_Callbacks{focusable = true, cursor = .HAND})
	if ev_ctx.clicked_this_frame[root_id] or_else false do state^ = value
	is_active := state^ == value

	is_hovered := is_tree_hovered(ui_ctx, ev_ctx, root_id)
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
DEFAULT_SLIDER_WRAPPER_STYLE :: Style {
	width           = lc.Percent{100},
	height          = lc.Fixed{30},
	justify_content = .START,
	align_items     = .CENTER,
}
DEFAULT_SLIDER_TRACK_STYLE :: Style {
	width         = lc.Percent{100},
	height        = lc.Fixed{4}, // Slim down to 4px
	bg_color      = Color{1, 1, 1, 0.25}, // Clean, translucent backdrop
	border_radius = [4]f32{2, 2, 2, 2},
}

DEFAULT_SLIDER_FILL_STYLE :: Style {
	height        = lc.Percent{100},
	bg_color      = Color{0.9, 0.2, 0.2, 1.0}, // A sharp red (or swap to your accent color)
	border_radius = [4]f32{2, 2, 2, 2},
}

DEFAULT_SLIDER_THUMB_STYLE :: Style {
	position      = .ABSOLUTE,
	top           = 8.0, // Vertically centered: (30px wrapper - 14px thumb) / 2 = 8
	width         = lc.Fixed{14},
	height        = lc.Fixed{14},
	bg_color      = Color{1, 1, 1, 1},
	border_radius = [4]f32{7, 7, 7, 7}, // Perfect borderless circle
}

slider :: proc(
	ui_ctx: ^UI_Context,
	ev_ctx: ^events.Event_Context,
	anim_ctx: ^anim.Context,
	value: ^f32,
	min_val, max_val: f32,
	wrapper_style: Style = DEFAULT_SLIDER_WRAPPER_STYLE,
	track_style: Style = DEFAULT_SLIDER_TRACK_STYLE,
	fill_style: Style = DEFAULT_SLIDER_FILL_STYLE,
	thumb_style: Style = DEFAULT_SLIDER_THUMB_STYLE,
	salt := "",
	loc := #caller_location,
) -> (
	changed: bool,
	new_target: f32,
) {
	root_id := lc.ID(loc, salt)
	fill_id := lc.ID(root_id, "fill")
	track_id := lc.ID(root_id, "track")
	thumb_id := lc.ID(root_id, "thumb")

	events.register(ev_ctx, root_id, events.Event_Callbacks{focusable = true})

	changed = false
	target_val := value^ // <-- FALLBACK TO CURRENT VALUE

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
					anim.to(
						&anim_ctx.engine,
						anim.Tween_Vars {
							duration = 0.25,
							ease_func = anim.ease_out_exp,
							properties = {{target = value, to = new_val}},
						},
					)
				} else if is_dragging {
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
				target_val = new_val // <-- CAPTURE RAW INTENT
			}
		}
	}

	fill_percent := clamp((value^ - min_val) / (max_val - min_val), 0.0, 1.0)

	element_open(ui_ctx, Element{_box = {id = root_id}, style = wrapper_style}, loc)
	element_open(ui_ctx, Element{_box = {id = track_id}, style = track_style})

	dynamic_fill := fill_style
	dynamic_fill.width = lc.Percent{fill_percent * 100.0}
	element_open(ui_ctx, Element{_box = {id = fill_id}, style = dynamic_fill})
	element_close(ui_ctx)

	element_close(ui_ctx)

	thumb_x: f32 = 0.0
	if prev, ok := ui_ctx.layout.prev_all_boxes[root_id]; ok {
		thumb_x = (fill_percent * prev.computed_width) - 10.0
	}

	dynamic_thumb := thumb_style
	dynamic_thumb.position = .ABSOLUTE
	dynamic_thumb.left = thumb_x
	element_open(ui_ctx, Element{_box = {id = thumb_id}, style = dynamic_thumb})
	element_close(ui_ctx)

	element_close(ui_ctx)

	return changed, target_val // <-- RETURN BOTH
}

// --- TEXT INPUT ---
DEFAULT_TEXT_INPUT_WRAPPER_STYLE :: Style {
	width         = lc.Percent{100},
	height        = lc.Fixed{50},
	padding       = [4]f32{5, 5, 5, 5},
	border_radius = [4]f32{6, 6, 6, 6},
	border        = [4]f32{2, 2, 2, 2},
	border_color  = Color{0.8, 0.8, 0.8, 1},
	bg_color      = Color{1, 1, 1, 1},
}
DEFAULT_TEXT_INPUT_TEXT_STYLE :: Style {
	width      = lc.Fit(true),
	height     = lc.Fit(true),
	font_size  = 18,
	text_wrap  = .NONE,
	text_color = Color{0.1, 0.1, 0.1, 1},
}

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
	text_style: Style = DEFAULT_TEXT_INPUT_TEXT_STYLE,
	focused_border_color: Color = {0.15, 0.4, 0.8, 1},
	placeholder_color: Color = {0.6, 0.6, 0.6, 1},
	salt := "",
	id: string = "",
	loc := #caller_location,
) -> bool {
	root_id := lc.ID(id) if id != "" else lc.ID(loc, salt)
	string_id := lc.ID(root_id, "text")

	events.register(
		ev_ctx,
		root_id,
		events.Event_Callbacks {
			cursor = .IBEAM,
			focusable = true,
			user_data = ev_ctx,
			on_text_input = _text_input_cb,
			on_key_down = _key_down_cb,
		},
	)

	is_focused := ev_ctx.focused_id == root_id

	if is_focused {
		sdl.StartTextInput()
		ev_ctx.focused_buffer = buffer

		if root_id not_in ev_ctx.text_cursors {
			ev_ctx.text_cursors[root_id] = len(buffer)
		}

		// Start/restart the blink timer when focus is gained.
		if root_id not_in ev_ctx.cursor_blink_start {
			ev_ctx.cursor_blink_start[root_id] = u64(sdl.GetTicks())
		}
	} else if ev_ctx.focused_buffer == buffer {
		sdl.StopTextInput()
		ev_ctx.focused_buffer = nil
	}

	cursor := clamp(ev_ctx.text_cursors[root_id], 0, len(buffer))

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
	is_pressed := ev_ctx.pressed_id == root_id
	was_pressed := ev_ctx.prev_pressed_id == root_id
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

			ev_ctx.text_cursors[root_id] = best_cursor
			cursor = best_cursor

			// Anchor the text highlight the exact frame the mouse goes down
			if just_pressed {
				ev_ctx.text_selection[root_id] = best_cursor
				ev_ctx.cursor_blink_start[root_id] = u64(sdl.GetTicks())
			}

			// ADD CLAMP HERE
			anchor := clamp(ev_ctx.text_selection[root_id], 0, len(buffer))
			ev_ctx.text_selection[root_id] = anchor // Keep state in sync
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
		if root_id not_in ev_ctx.cursor_last_position {
			ev_ctx.cursor_last_position[root_id] = cursor
		}

		if ev_ctx.cursor_last_position[root_id] != cursor {
			ev_ctx.cursor_last_position[root_id] = cursor
			ev_ctx.cursor_blink_start[root_id] = u64(sdl.GetTicks())
		}
	}

	current_len := len(buffer^)

	// Clamp BOTH the cursor and the selection anchor
	cursor = clamp(ev_ctx.text_cursors[root_id], 0, current_len)
	anchor := clamp(ev_ctx.text_selection[root_id], 0, current_len)

	// ------------------------------------------------------------
	// Calculate cursor position
	// ------------------------------------------------------------

	cursor_px := ui_text_width(&dummy_box, string(buffer^[:cursor]))


	// ------------------------------------------------------------
	// Auto-scroll so cursor stays visible
	// ------------------------------------------------------------
	if is_focused {
		if prev_outer, ok := ui_ctx.layout.prev_all_boxes[root_id]; ok {
			scroll_x := ev_ctx.scroll_offsets_x[root_id]

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
				ev_ctx.scroll_offsets_x[root_id] = max(cursor_left - margin, 0)
			} else if cursor_right > scroll_x + viewport_width - margin {
				ev_ctx.scroll_offsets_x[root_id] = cursor_right - viewport_width + margin
			}

			// CLAMP SCROLL: Prevent the text from floating away from the right edge
			// when characters are deleted and the total text width shrinks.
			total_text_width := ui_text_width(&dummy_box, string(buffer^[:]))
			max_scroll := max(total_text_width + 15.0 - viewport_width, 0.0)

			ev_ctx.scroll_offsets_x[root_id] = clamp(
				ev_ctx.scroll_offsets_x[root_id],
				0.0,
				max_scroll,
			)

			// Mutate the previous frame's box so the layout engine
			// copies THIS new value instead of restoring the old one.
			prev_outer.offset_x = ev_ctx.scroll_offsets_x[root_id]
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
		elapsed := u64(sdl.GetTicks()) - ev_ctx.cursor_blink_start[root_id]

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
		id = root_id,
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
		Element{_box = {id = string_id}, text = display_text, style = final_text},
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

// --- IMAGE BUTTON ---
image_button :: proc(
	ui_ctx: ^UI_Context,
	ev_ctx: ^events.Event_Context,
	sdl_rend: ^sdl.Renderer,
	path: string,
	user_style: Style = {},
	salt := "",
	loc := #caller_location,
) -> bool {
	hash_input := fmt.tprintf("%s:%d:%s", loc.file_path, loc.line, salt)
	id := lc.ID(hash_input)

	is_clicked := ev_ctx.clicked_this_frame[id] or_else false
	events.register(ev_ctx, id, events.Event_Callbacks{focusable = true, cursor = .HAND})

	// Cache & Load Texture (mirroring image_path)
	path_hash := hash.fnv32(transmute([]byte)path)
	tex, exists := ui_ctx.image_cache[path_hash]
	if !exists {
		c_path := fmt.ctprintf("%s", path)
		tex = img.LoadTexture(sdl_rend, c_path)
		if tex == nil do fmt.printfln("ERROR: Failed to load image '%s': %s", path, sdl.GetError())
		ui_ctx.image_cache[path_hash] = tex
	}

	final_style := user_style
	final_style.bg_image = tex

	// Sensible default size for icons so they don't blow up the layout
	if final_style.width == nil do final_style.width = lc.Fixed{28}
	if final_style.height == nil do final_style.height = lc.Fixed{28}
	if final_style.object_fit == nil do final_style.object_fit = .CONTAIN

	element_open(ui_ctx, Element{_box = {id = id}, style = final_style}, loc)
	element_close(ui_ctx)

	return is_clicked
}

// --- VIDEO PLAYER ---
DEFAULT_VIDEO_WRAPPER_STYLE :: Style {
	width  = lc.Percent{100},
	height = lc.Percent{100},
}
DEFAULT_VIDEO_FRAME_STYLE :: Style {
	width      = lc.Percent{100},
	height     = lc.Percent{100},
	object_fit = .CONTAIN,
}
DEFAULT_VIDEO_OVERLAY_STYLE :: Style {
	position    = .ABSOLUTE,
	bottom      = 0,
	left        = 0,
	width       = lc.Percent{100},
	direction   = .ROW,
	align_items = .CENTER,
	gap         = 15,
	padding     = [4]f32{10, 10, 10, 10},
	bg_color    = Color{0, 0, 0, 0.7},
}
DEFAULT_VIDEO_TIME_STYLE :: Style {
	font_name  = "time_font",
	text_color = Color{1, 1, 1, 1},
	text_wrap  = .NONE,
	text_align = .RIGHT,
}

video :: proc(
	ui_ctx: ^UI_Context,
	ev_ctx: ^events.Event_Context,
	anim_ctx: ^anim.Context,
	sdl_rend: ^sdl.Renderer,
	path: string,
	dt: f64,
	is_scrubbing: ^bool,
	scrub_time: ^f32,
	slider_val: ^f32,
	overlay_active: ^bool,
	overlay_anim: ^f32,
	play_icon: string = "assets/pictures/play-button.png",
	pause_icon: string = "assets/pictures/pause.png",
	wrapper_style: Style = {},
	frame_style: Style = {},
	overlay_style: Style = {},
	play_btn_style: Style = {},
	time_style: Style = {},
	slider_wrapper_style: Style = {},
	slider_track_style: Style = {},
	slider_fill_style: Style = {},
	slider_thumb_style: Style = {},
	salt := "",
	id: string = "",
	loc := #caller_location,
) {
	hash_input := id
	if id == "" do hash_input = fmt.tprintf("%s:%d:%s", loc.file_path, loc.line, salt)
	root_id := lc.ID(hash_input)

	// Cache Layer: Init if it doesn't exist
	if path not_in ui_ctx.videos {
		ui_ctx.videos[path] = video_player_init(sdl_rend, path)
	}
	player := ui_ctx.videos[path]

	// Playback Layer: Advance the media clocks
	if player != nil && player.is_playing {
		video_player_update(player, dt)
	}

	// --- RELATIVE WRAPPER ---
	final_wrapper := merge_styles(DEFAULT_VIDEO_WRAPPER_STYLE, wrapper_style)
	final_wrapper.position = .RELATIVE
	final_wrapper.overflow_y = .HIDDEN

	{
		element_open(ui_ctx, {id = root_id, style = final_wrapper}, loc)
		defer element_close(ui_ctx)

		{
			final_frame := merge_styles(DEFAULT_VIDEO_FRAME_STYLE, frame_style)
			// Inherit rounded corners from the wrapper so the video perfectly clips
			if final_frame.border_radius == nil do final_frame.border_radius = final_wrapper.border_radius

			el := element_open(ui_ctx, Element{style = final_frame})
			defer element_close(ui_ctx) // close video frame
			if player != nil && player.texture != nil {
				if player.playback_time > 0.1 do el.resolved_bg_image = player.texture
			}
		}

		// --- CONTROLS OVERLAY ---
		if player != nil {
			overlay_id := lc.ID(fmt.tprintf("%d_overlay", root_id))

			// Determine if it SHOULD be open (using the tree hover fix!)
			should_show := is_tree_hovered(ui_ctx, ev_ctx, root_id) || is_scrubbing^

			// Fire the animation ONLY when the state changes
			if should_show != overlay_active^ {
				overlay_active^ = should_show

				anim.to(
					&anim_ctx.engine,
					anim.Tween_Vars {
						duration   = 0.35, // 350ms feels smooth for a UI slide
						ease_func  = anim.ease_out_exp,
						properties = {{target = overlay_anim, to = should_show ? 1.0 : 0.0}},
					},
				)
			}

			// Only render the overlay if the animation is actually visible
			if overlay_anim^ > 0.001 {
				final_overlay := merge_styles(DEFAULT_VIDEO_OVERLAY_STYLE, overlay_style)

				if final_overlay.border_radius == nil {
					if br, ok := final_wrapper.border_radius.?; ok {
						final_overlay.border_radius = [4]f32{0, 0, br[2], br[3]}
					}
				}

				// --- ANIMATION MAGIC ---
				// Slide down by 55 pixels when hiding (adjust based on your actual height)
				offset_y := 55.0 * (1.0 - overlay_anim^)
				final_overlay.bottom = -offset_y

				// Fade out the dark background overlay
				if bg, ok := final_overlay.bg_color.?; ok {
					final_overlay.bg_color = Color{bg[0], bg[1], bg[2], bg[3] * overlay_anim^}
				}

				{
					element_open(ui_ctx, Element{_box = {id = overlay_id}, style = final_overlay})
					defer element_close(ui_ctx)


					// Play/Pause Button
					icon := player.is_playing ? pause_icon : play_icon
					if image_button(
						ui_ctx,
						ev_ctx,
						sdl_rend,
						icon,
						user_style = play_btn_style,
						salt = fmt.tprintf("%s_play", salt),
					) {
						player.is_playing = !player.is_playing
						sdl.PauseAudioDevice(player.audio_dev, !player.is_playing)
					}

					// Time Formatting
					display_time := is_scrubbing^ ? f64(scrub_time^) : player.playback_time
					curr_m := int(display_time) / 60
					curr_s := int(display_time) % 60
					tot_m := int(player.duration) / 60
					tot_s := int(player.duration) % 60
					time_str := fmt.tprintf("%02d:%02d / %02d:%02d", curr_m, curr_s, tot_m, tot_s)

					final_time_style := merge_styles(DEFAULT_VIDEO_TIME_STYLE, time_style)

					text(
						ui_ctx,
						ev_ctx,
						time_str,
						user_style = final_time_style,
						salt = fmt.tprintf("%s_time", salt),
					)

					// Scrubbing Logic
					mouse_state := sdl.GetMouseState(nil, nil)
					is_mouse_down := (mouse_state & sdl.BUTTON_LMASK) != 0

					slider_val^ = is_scrubbing^ ? scrub_time^ : f32(player.playback_time)

					final_slider_wrapper := merge_styles(
						DEFAULT_SLIDER_WRAPPER_STYLE,
						slider_wrapper_style,
					)
					final_slider_wrapper.width = lc.Grow{1}

					final_slider_track := merge_styles(
						DEFAULT_SLIDER_TRACK_STYLE,
						slider_track_style,
					)
					final_slider_fill := merge_styles(DEFAULT_SLIDER_FILL_STYLE, slider_fill_style)
					final_slider_thumb := merge_styles(
						DEFAULT_SLIDER_THUMB_STYLE,
						slider_thumb_style,
					)

					slider_changed, scrub_target := slider(
						ui_ctx,
						ev_ctx,
						anim_ctx,
						slider_val,
						0.0,
						f32(player.duration),
						wrapper_style = final_slider_wrapper,
						track_style = final_slider_track,
						fill_style = final_slider_fill,
						thumb_style = final_slider_thumb,
						salt = fmt.tprintf("%s_slider", salt),
					)

					// Handle state transitions based on instant feedback
					if slider_changed {
						scrub_time^ = scrub_target
						if is_mouse_down {
							is_scrubbing^ = true
						} else {
							video_player_seek(player, f64(scrub_time^))
							is_scrubbing^ = false
						}
					} else if is_scrubbing^ {
						if !is_mouse_down {
							video_player_seek(player, f64(scrub_time^))
							is_scrubbing^ = false
						}
					}
				}
			}
		}
	}
}

DEFAULT_POPOVER_STYLE :: Style {
	direction     = .COLUMN,
	bg_color      = Color{1, 1, 1, 1},
	border        = [4]f32{1, 1, 1, 1},
	border_color  = Color{0.8, 0.8, 0.8, 1},
	border_radius = [4]f32{6, 6, 6, 6},
	padding       = [4]f32{8, 12, 8, 12},
	width         = lc.Fit(true),
	height        = lc.Fit(true),
}

// Returns true if the popover is active and its children should be rendered
popover_begin :: proc(
	ui_ctx: ^UI_Context,
	ev_ctx: ^events.Event_Context,
	target_id: lc.Box_ID,
	is_open: ^bool,
	user_style: Style = {},
	salt := "",
	loc := #caller_location,
) -> bool {
	if !is_open^ do return false

	hash_input := fmt.tprintf("%s:%d:%s", loc.file_path, loc.line, salt)
	root_id := lc.ID(hash_input)

	backdrop_id := lc.ID(fmt.tprintf("%d_backdrop", root_id))
	content_id := lc.ID(fmt.tprintf("%d_content", root_id))

	events.register(ev_ctx, backdrop_id, events.Event_Callbacks{focusable = true})

	if ev_ctx.hovered_id == backdrop_id && (ev_ctx.clicked_this_frame[backdrop_id] or_else false) {
		is_open^ = false
		return false
	}

	element_open(
		ui_ctx,
		Element {
			_box = {id = backdrop_id},
			style = {
				position = .FIXED,
				top = 0,
				left = 0,
				width = lc.ViewPercent{100},
				height = lc.ViewPercent{100},
				z_index = 999,
				bg_color = Color{0, 0, 0, 0},
			},
		},
		loc,
	)
	element_close(ui_ctx)

	target_x, target_y, target_w, target_h: f32 = 0, 0, 0, 0
	if prev, ok := ui_ctx.layout.prev_all_boxes[target_id]; ok {
		target_x = prev.x
		target_y = prev.y
		target_w = prev.computed_width
		target_h = prev.computed_height
	}

	// Merge styles here
	final_style := merge_styles(DEFAULT_POPOVER_STYLE, user_style)
	final_style.position = .FIXED
	final_style.z_index = 1000

	if final_style.left == nil do final_style.left = target_x
	if final_style.top == nil do final_style.top = target_y + target_h + 8.0

	events.register(ev_ctx, content_id, events.Event_Callbacks{focusable = true})

	element_open(ui_ctx, Element{_box = {id = content_id}, style = final_style}, loc)

	return true
}

popover_end :: proc(ui_ctx: ^UI_Context, is_open: bool) {
	if is_open do element_close(ui_ctx)
}

DEFAULT_DROPDOWN_STYLE :: Style {
	width         = lc.Fixed{200},
	height        = lc.Fit(true),
	padding       = [4]f32{8, 12, 8, 12},
	border_radius = [4]f32{6, 6, 6, 6},
	border        = [4]f32{1, 1, 1, 1},
	border_color  = Color{0.8, 0.8, 0.8, 1},
	bg_color      = Color{1, 1, 1, 1},
	text_color    = Color{0, 0, 0, 1},
}

DEFAULT_DROPDOWN_POPOVER_STYLE :: Style {
	align_items   = .STRETCH,
	width         = lc.Fit(true),
	direction     = .COLUMN,
	bg_color      = Color{1, 1, 1, 1},
	border_radius = [4]f32{6, 6, 6, 6},
	border        = [4]f32{1, 1, 1, 1},
	border_color  = Color{0.8, 0.8, 0.8, 1},
	padding       = [4]f32{4, 4, 4, 4},
}

// Returns true if the selection changed this frame
dropdown :: proc(
	ui_ctx: ^UI_Context,
	ev_ctx: ^events.Event_Context,
	label: string,
	options: []string,
	selected_idx: ^int,
	is_open: ^bool,
	wrapper_style: Style = {},
	popover_style: Style = {},
	salt := "",
	id: string = "",
	loc := #caller_location,
) -> bool {
	changed := false
	hash_input := id
	if id == "" do hash_input = fmt.tprintf("%s:%d:%s", loc.file_path, loc.line, salt)
	root_id := lc.ID(hash_input)

	// Determine Display Text
	display_text := label
	if selected_idx^ >= 0 && selected_idx^ < len(options) {
		display_text = options[selected_idx^]
	}

	final_wrapper := merge_styles(DEFAULT_DROPDOWN_STYLE, wrapper_style)

	// The Trigger Button
	if button(ui_ctx, ev_ctx, display_text, user_style = final_wrapper, id = root_id) do is_open^ = !is_open^

	final_popover := merge_styles(DEFAULT_DROPDOWN_POPOVER_STYLE, popover_style)

	// The Popover List
	if popover_begin(
		ui_ctx,
		ev_ctx,
		root_id,
		is_open,
		salt = salt,
		loc = loc,
		user_style = final_popover,
	) {
		defer popover_end(ui_ctx, true)

		for opt, i in options {
			opt_id := lc.ID(fmt.tprintf("%d_opt_%d", root_id, i))

			is_selected := selected_idx^ == i
			opt_bg := is_selected ? Color{0.15, 0.4, 0.8, 1.0} : Color{0, 0, 0, 0}
			opt_text := is_selected ? Color{1, 1, 1, 1} : Color{0.2, 0.2, 0.2, 1}

			if button(
				ui_ctx,
				ev_ctx,
				opt,
				id = opt_id,
				user_style = {
					bg_color = opt_bg,
					text_color = opt_text,
					text_align = .LEFT,
					border_radius = space(4),
				},
			) {
				selected_idx^ = i
				is_open^ = false
				changed = true
			}
		}
	}

	return changed
}

DEFAULT_MODAL_BACKDROP_STYLE :: Style {
	position        = .FIXED,
	top             = 0,
	left            = 0,
	width           = lc.ViewPercent{100},
	height          = lc.ViewPercent{100},
	bg_color        = Color{0, 0, 0, 0.6}, // Darkened overlay
	z_index         = 2000,
	direction       = .COLUMN,
	justify_content = .CENTER, // Centers children vertically
	align_items     = .CENTER, // Centers children horizontally
}

DEFAULT_MODAL_STYLE :: Style {
	direction     = .COLUMN,
	bg_color      = Color{1, 1, 1, 1},
	border_radius = [4]f32{8, 8, 8, 8},
	padding       = [4]f32{24, 24, 24, 24},
	width         = lc.Fixed{400},
	height        = lc.Fit(true),
	gap           = 16,
}

modal_begin :: proc(
	ui_ctx: ^UI_Context,
	ev_ctx: ^events.Event_Context,
	is_open: ^bool,
	dismiss_on_click_outside: bool = true,
	backdrop_style: Style = {},
	modal_style: Style = {},
	salt := "",
	loc := #caller_location,
) -> bool {
	if !is_open^ do return false

	hash_input := fmt.tprintf("%s:%d:%s", loc.file_path, loc.line, salt)
	root_id := lc.ID(hash_input)
	backdrop_id := lc.ID(fmt.tprintf("%d_backdrop", root_id))
	content_id := lc.ID(fmt.tprintf("%d_content", root_id))

	// The Full-Screen Backdrop
	events.register(ev_ctx, backdrop_id, events.Event_Callbacks{focusable = true})

	if dismiss_on_click_outside &&
	   ev_ctx.hovered_id == backdrop_id &&
	   (ev_ctx.clicked_this_frame[backdrop_id] or_else false) {
		is_open^ = false
		return false
	}

	final_backdrop := merge_styles(DEFAULT_MODAL_BACKDROP_STYLE, backdrop_style)
	element_open(ui_ctx, Element{_box = {id = backdrop_id}, style = final_backdrop}, loc)

	// The Modal Content Container (Catches clicks so they don't hit the backdrop)
	events.register(ev_ctx, content_id, events.Event_Callbacks{focusable = true})

	final_modal := merge_styles(DEFAULT_MODAL_STYLE, modal_style)
	element_open(ui_ctx, Element{_box = {id = content_id}, style = final_modal}, loc)

	return true
}

modal_end :: proc(ui_ctx: ^UI_Context, is_open: bool) {
	if is_open {
		element_close(ui_ctx) // Close Content
		element_close(ui_ctx) // Close Backdrop
	}
}

DEFAULT_CONTEXT_MENU_BACKDROP_STYLE :: Style {
	position = .FIXED,
	top      = 0,
	left     = 0,
	width    = lc.ViewPercent{100},
	height   = lc.ViewPercent{100},
	z_index  = 3000,
	bg_color = Color{0, 0, 0, 0}, // Fully transparent click shield
}

DEFAULT_CONTEXT_MENU_STYLE :: Style {
	direction     = .COLUMN,
	align_items   = .STRETCH,
	bg_color      = Color{1.0, 1.0, 1.0, 1.0}, // Clean white background
	border        = [4]f32{1, 1, 1, 1},
	border_color  = Color{0.9, 0.9, 0.9, 1.0}, // Softer, more subtle border
	border_radius = [4]f32{8, 8, 8, 8}, // Modern, rounder corners
	padding       = [4]f32{8, 8, 8, 8}, // More breathable internal padding
	gap           = 4, // Spacing between buttons so hover states don't collide
	width         = lc.Fit(true),
	height        = lc.Fit(true),
}

context_menu_begin :: proc(
	ui_ctx: ^UI_Context,
	ev_ctx: ^events.Event_Context,
	x, y: f32,
	is_open: ^bool,
	backdrop_style: Style = {},
	user_style: Style = {},
	salt := "",
	loc := #caller_location,
) -> bool {
	if !is_open^ do return false

	hash_input := fmt.tprintf("%s:%d:%s", loc.file_path, loc.line, salt)
	root_id := lc.ID(hash_input)
	backdrop_id := lc.ID(fmt.tprintf("%d_backdrop", root_id))
	content_id := lc.ID(fmt.tprintf("%d_content", root_id))

	// Invisible Click Shield
	events.register(ev_ctx, backdrop_id, events.Event_Callbacks{focusable = true})
	if ev_ctx.hovered_id == backdrop_id && (ev_ctx.clicked_this_frame[backdrop_id] or_else false) {
		is_open^ = false
		return false
	}

	final_backdrop := merge_styles(DEFAULT_CONTEXT_MENU_BACKDROP_STYLE, backdrop_style)
	element_open(ui_ctx, Element{_box = {id = backdrop_id}, style = final_backdrop}, loc)
	element_close(ui_ctx)

	// The Menu Container
	final_style := merge_styles(DEFAULT_CONTEXT_MENU_STYLE, user_style)

	// Force positioning constraints regardless of user overrides
	final_style.position = .FIXED
	final_style.left = x
	final_style.top = y
	final_style.z_index = 3001

	events.register(ev_ctx, content_id, events.Event_Callbacks{focusable = true})
	element_open(ui_ctx, Element{_box = {id = content_id}, style = final_style}, loc)

	return true
}

context_menu_end :: proc(ui_ctx: ^UI_Context, is_open: bool) {
	if is_open do element_close(ui_ctx)
}

DEFAULT_SWITCH_WRAPPER_STYLE :: Style {
	width         = lc.Fit(true),
	height        = lc.Fit(true),
	direction     = .ROW,
	align_items   = .CENTER,
	gap           = 12,
	padding       = [4]f32{8, 12, 8, 12},
	border_radius = [4]f32{6, 6, 6, 6},
	bg_color      = Color{0, 0, 0, 0},
}

DEFAULT_SWITCH_TRACK_STYLE :: Style {
	width         = lc.Fixed{44},
	height        = lc.Fixed{24},
	border_radius = [4]f32{12, 12, 12, 12}, // Fully rounded pill
	border        = [4]f32{2, 2, 2, 2},
	border_color  = Color{0.8, 0.8, 0.8, 1},
}

DEFAULT_SWITCH_THUMB_STYLE :: Style {
	position      = .ABSOLUTE,
	top           = 2, // 2px inset from the top border
	width         = lc.Fixed{16},
	height        = lc.Fixed{16},
	border_radius = [4]f32{8, 8, 8, 8},
	bg_color      = Color{1, 1, 1, 1},
}

switch_toggle :: proc(
	ui_ctx: ^UI_Context,
	ev_ctx: ^events.Event_Context,
	label: string,
	state: ^bool,
	wrapper_style: Style = {},
	track_style: Style = {},
	thumb_style: Style = {},
	text_style: Style = {},
	active_color: Color = {0.2, 0.8, 0.4, 1.0},
	inactive_color: Color = {0.8, 0.8, 0.8, 1.0},
	hover_bg_color: Color = {0.9, 0.9, 0.92, 1.0},
	salt := "",
	id: string = "",
	loc := #caller_location,
) -> bool {
	root_id := lc.ID(id) if id != "" else lc.ID(loc, salt)
	track_id := lc.ID(root_id, "track")
	thumb_id := lc.ID(root_id, "thumb")
	text_id := lc.ID(root_id, "text")

	events.register(ev_ctx, root_id, events.Event_Callbacks{focusable = true, cursor = .HAND})
	if ev_ctx.clicked_this_frame[root_id] or_else false do state^ = !state^

	is_hovered := is_tree_hovered(ui_ctx, ev_ctx, root_id)

	final_wrapper := merge_styles(DEFAULT_SWITCH_WRAPPER_STYLE, wrapper_style)
	if is_hovered do final_wrapper.bg_color = hover_bg_color

	element_open(ui_ctx, Element{_box = {id = root_id}, style = final_wrapper}, loc)

	final_track := merge_styles(DEFAULT_SWITCH_TRACK_STYLE, track_style)
	final_track.bg_color = state^ ? active_color : inactive_color
	final_track.border_color = state^ ? active_color : Color{0.7, 0.7, 0.7, 1.0}

	element_open(ui_ctx, Element{_box = {id = track_id}, style = final_track})

	final_thumb := merge_styles(DEFAULT_SWITCH_THUMB_STYLE, thumb_style)
	final_thumb.left = state^ ? 26.0 : 2.0

	element_open(ui_ctx, Element{_box = {id = thumb_id}, style = final_thumb})
	element_close(ui_ctx)
	element_close(ui_ctx)

	final_text := merge_styles(DEFAULT_CHECKBOX_TEXT_STYLE, text_style)
	element_open(ui_ctx, Element{_box = {id = text_id}, text = label, style = final_text})
	element_close(ui_ctx)

	element_close(ui_ctx)
	return ev_ctx.clicked_this_frame[root_id] or_else false
}

// --- MULTI-SELECT ---

DEFAULT_MULTI_SELECT_POPOVER_STYLE :: Style {
	align_items   = .STRETCH,
	width         = lc.Fit(true),
	direction     = .COLUMN,
	bg_color      = Color{1, 1, 1, 1},
	border_radius = [4]f32{6, 6, 6, 6},
	border        = [4]f32{1, 1, 1, 1},
	border_color  = Color{0.8, 0.8, 0.8, 1},
	padding       = [4]f32{4, 4, 4, 4},
}

multi_select :: proc(
	ui_ctx: ^UI_Context,
	ev_ctx: ^events.Event_Context,
	label: string,
	options: []string,
	selected_states: []bool,
	is_open: ^bool,
	wrapper_style: Style = {},
	popover_style: Style = {},
	salt := "",
	id: string = "",
	loc := #caller_location,
) -> bool {
	changed := false
	root_id := lc.ID(id) if id != "" else lc.ID(loc, salt)

	selected_count := 0
	for s in selected_states do if s do selected_count += 1

	display_text := label
	if selected_count > 0 do display_text = fmt.tprintf("%s (%d)", label, selected_count)

	final_wrapper := merge_styles(DEFAULT_DROPDOWN_STYLE, wrapper_style)

	if button(ui_ctx, ev_ctx, display_text, user_style = final_wrapper, id = root_id) do is_open^ = !is_open^

	final_popover := merge_styles(DEFAULT_MULTI_SELECT_POPOVER_STYLE, popover_style)

	if popover_begin(
		ui_ctx,
		ev_ctx,
		root_id,
		is_open,
		salt = salt,
		loc = loc,
		user_style = final_popover,
	) {
		defer popover_end(ui_ctx, is_open^)

		for opt, i in options {
			cb_salt := fmt.tprintf("%s_opt_%d", salt, i)
			// Pass loc so it combines nicely with the salt!
			if checkbox(ui_ctx, ev_ctx, opt, &selected_states[i], salt = cb_salt, loc = loc) do changed = true
		}
	}
	return changed
}

DEFAULT_COMBOBOX_POPOVER_STYLE :: Style {
	align_items   = .STRETCH,
	width         = lc.Fit(true),
	direction     = .COLUMN,
	bg_color      = Color{1, 1, 1, 1},
	border_radius = [4]f32{6, 6, 6, 6},
	border        = [4]f32{1, 1, 1, 1},
	border_color  = Color{0.8, 0.8, 0.8, 1},
	padding       = [4]f32{4, 4, 4, 4},
}

combobox :: proc(
	ui_ctx: ^UI_Context,
	ev_ctx: ^events.Event_Context,
	placeholder: string,
	options: []string,
	buffer: ^[dynamic]u8,
	selected_idx: ^int,
	is_open: ^bool,
	wrapper_style: Style = {},
	popover_style: Style = {},
	salt := "",
	id: string = "",
	loc := #caller_location,
) -> bool {
	changed := false
	root_id := lc.ID(id) if id != "" else lc.ID(loc, salt)

	// Create a stable salt for the inner text input
	input_salt := fmt.tprintf("%s_input", salt)
	input_id := lc.ID(loc, input_salt)

	final_wrapper := merge_styles(DEFAULT_TEXT_INPUT_WRAPPER_STYLE, wrapper_style)

	is_focused := text_input(
		ui_ctx,
		ev_ctx,
		buffer,
		placeholder = placeholder,
		wrapper_style = final_wrapper,
		salt = input_salt,
		loc = loc,
	)

	if ev_ctx.clicked_this_frame[input_id] or_else false do is_open^ = true

	// Safe dereference for the dynamic array
	search_str := strings.to_lower(string(buffer^[:]), context.temp_allocator)

	final_popover := merge_styles(DEFAULT_COMBOBOX_POPOVER_STYLE, popover_style)

	if popover_begin(
		ui_ctx,
		ev_ctx,
		input_id,
		is_open,
		salt = salt,
		loc = loc,
		user_style = final_popover,
	) {
		defer popover_end(ui_ctx, true)

		for opt, i in options {
			opt_lower := strings.to_lower(opt, context.temp_allocator)

			if strings.contains(opt_lower, search_str) || len(search_str) == 0 {
				opt_id := lc.ID(root_id, fmt.tprintf("opt_%d", i))
				is_selected := selected_idx^ == i

				opt_bg := Color{0.15, 0.4, 0.8, 1.0} if is_selected else Color{0, 0, 0, 0}
				opt_text := Color{1, 1, 1, 1} if is_selected else Color{0.2, 0.2, 0.2, 1}

				if button(
					ui_ctx,
					ev_ctx,
					opt,
					id = opt_id,
					user_style = {
						bg_color = opt_bg,
						text_color = opt_text,
						text_align = .LEFT,
						border_radius = space(4),
					},
				) {
					selected_idx^ = i
					is_open^ = false
					changed = true

					clear(buffer)
					for c in opt do append(buffer, u8(c))

					ev_ctx.text_cursors[input_id] = len(buffer^)
					ev_ctx.text_selection[input_id] = len(buffer^)
				}
			}
		}
	}
	return changed
}

// --- PROGRESS BAR ---
DEFAULT_PROGRESS_WRAPPER_STYLE :: Style {
	width         = lc.Percent{100},
	height        = lc.Fixed{8},
	bg_color      = Color{0.85, 0.85, 0.85, 1.0},
	border_radius = [4]f32{4, 4, 4, 4},
}

DEFAULT_PROGRESS_FILL_STYLE :: Style {
	height        = lc.Percent{100},
	bg_color      = Color{0.15, 0.4, 0.8, 1.0},
	border_radius = [4]f32{4, 4, 4, 4},
}

progress_bar :: proc(
	ui_ctx: ^UI_Context,
	value: f32,
	min_val: f32 = 0.0,
	max_val: f32 = 1.0,
	wrapper_style: Style = {},
	fill_style: Style = {},
	salt := "",
	id: string = "",
	loc := #caller_location,
) {
	root_id := lc.ID(id) if id != "" else lc.ID(loc, salt)
	fill_id := lc.ID(root_id, "fill")

	percent := clamp((value - min_val) / (max_val - min_val), 0.0, 1.0)

	final_wrapper := merge_styles(DEFAULT_PROGRESS_WRAPPER_STYLE, wrapper_style)
	element_open(ui_ctx, Element{_box = {id = root_id}, style = final_wrapper}, loc)

	dynamic_fill := merge_styles(DEFAULT_PROGRESS_FILL_STYLE, fill_style)
	dynamic_fill.width = lc.Percent{percent * 100.0}

	element_open(ui_ctx, Element{_box = {id = fill_id}, style = dynamic_fill})
	element_close(ui_ctx)

	element_close(ui_ctx)
}

// --- SPINNER ---
DEFAULT_SPINNER_WRAPPER_STYLE :: Style {
	width           = lc.Fit(true),
	height          = lc.Fit(true),
	direction       = .ROW,
	gap             = 8,
	align_items     = .CENTER,
	justify_content = .CENTER,
}

DEFAULT_SPINNER_DOT_STYLE :: Style {
	width         = lc.Fixed{12},
	height        = lc.Fixed{12},
	border_radius = [4]f32{6, 6, 6, 6},
	bg_color      = Color{0.15, 0.4, 0.8, 1.0},
}

spinner :: proc(
	ui_ctx: ^UI_Context,
	wrapper_style: Style = {},
	dot_style: Style = {},
	salt := "",
	id: string = "",
	loc := #caller_location,
) {
	root_id := lc.ID(id) if id != "" else lc.ID(loc, salt)

	final_wrapper := merge_styles(DEFAULT_SPINNER_WRAPPER_STYLE, wrapper_style)
	element_open(ui_ctx, Element{_box = {id = root_id}, style = final_wrapper}, loc)

	time_ms := f32(sdl.GetTicks())

	// Create a staggered sine wave for the 3 bouncing dots
	for i in 0 ..< 3 {
		dot_id := lc.ID(root_id, fmt.tprintf("dot_%d", i))

		phase := (time_ms * 0.005) + (f32(i) * 1.5)
		opacity := 0.2 + 0.8 * ((math.sin(phase) + 1.0) / 2.0)

		dynamic_dot := merge_styles(DEFAULT_SPINNER_DOT_STYLE, dot_style)
		if bg, ok := dynamic_dot.bg_color.?; ok {
			dynamic_dot.bg_color = Color{bg[0], bg[1], bg[2], bg[3] * opacity}
		}

		element_open(ui_ctx, Element{_box = {id = dot_id}, style = dynamic_dot})
		element_close(ui_ctx)
	}

	element_close(ui_ctx)
}

// --- TOAST NOTIFICATION ---
Toast_Type :: enum {
	INFO,
	SUCCESS,
	WARNING,
	ERROR,
}

DEFAULT_TOAST_STYLE :: Style {
	direction     = .ROW,
	align_items   = .CENTER,
	gap           = 16,
	padding       = [4]f32{12, 16, 12, 16},
	border_radius = [4]f32{6, 6, 6, 6},
	width         = lc.Fixed{320},
	height        = lc.Fit(true),
	bg_color      = Color{1, 1, 1, 1},
	border        = [4]f32{1, 1, 1, 1},
	border_color  = Color{0.8, 0.8, 0.8, 1},
}

toast :: proc(
	ui_ctx: ^UI_Context,
	ev_ctx: ^events.Event_Context,
	title: string,
	message: string,
	type: Toast_Type = .INFO,
	is_open: ^bool,
	wrapper_style: Style = {},
	salt := "",
	id: string = "",
	loc := #caller_location,
) -> bool {
	if !is_open^ do return false
	closed_this_frame := false
	root_id := lc.ID(id) if id != "" else lc.ID(loc, salt)

	indicator_color: Color
	switch type {
	case .INFO:
		indicator_color = Color{0.2, 0.5, 0.9, 1.0}
	case .SUCCESS:
		indicator_color = Color{0.2, 0.8, 0.4, 1.0}
	case .WARNING:
		indicator_color = Color{0.9, 0.7, 0.1, 1.0}
	case .ERROR:
		indicator_color = Color{0.9, 0.2, 0.2, 1.0}
	}

	final_wrapper := merge_styles(DEFAULT_TOAST_STYLE, wrapper_style)

	// Respect user-provided border_color, otherwise fallback to the calculated type color
	final_wrapper.border_color = wrapper_style.border_color.? or_else indicator_color

	// Thicken the left border to serve as a status indicator
	if b, ok := final_wrapper.border.?; ok {
		final_wrapper.border = [4]f32{b[0], b[1], b[2], b[3] + 4.0}
	} else {
		final_wrapper.border = [4]f32{1, 1, 1, 5}
	}

	element_open(ui_ctx, Element{_box = {id = root_id}, style = final_wrapper}, loc)

	// Content Column
	content_id := lc.ID(root_id, "content")
	element_open(
		ui_ctx,
		Element {
			_box = {id = content_id},
			style = {direction = .COLUMN, gap = 4, width = lc.Grow{1}},
		},
	)

	text(
		ui_ctx,
		ev_ctx,
		title,
		user_style = {font_size = 18, text_color = Color{0.1, 0.1, 0.1, 1}},
		salt = "title",
	)
	if message != "" {
		text(
			ui_ctx,
			ev_ctx,
			message,
			user_style = {font_size = 14, text_color = Color{0.4, 0.4, 0.4, 1}},
			salt = "msg",
		)
	}
	element_close(ui_ctx) // close content column

	// Close Button
	if button(
		ui_ctx,
		ev_ctx,
		"x",
		salt = "close",
		user_style = {
			bg_color = Color{0, 0, 0, 0},
			text_color = Color{0.5, 0.5, 0.5, 1},
			width = lc.Fixed{24},
			height = lc.Fixed{24},
			padding = space(0),
		},
	) {
		is_open^ = false
		closed_this_frame = true
	}

	element_close(ui_ctx) // close wrapper
	return closed_this_frame
}

// --- TABS ---
DEFAULT_TABS_WRAPPER_STYLE :: Style {
	direction    = .ROW,
	width        = lc.Percent{100},
	border       = [4]f32{0, 0, 1, 0},
	border_color = Color{0.8, 0.8, 0.8, 1},
}

DEFAULT_TABS_TAB_STYLE :: Style {
	bg_color      = Color{0, 0, 0, 0},
	border        = [4]f32{0, 0, 3, 0},
	border_radius = [4]f32{0, 0, 0, 0},
	padding       = [4]f32{12, 16, 12, 16},
}

tabs :: proc(
	ui_ctx: ^UI_Context,
	ev_ctx: ^events.Event_Context,
	labels: []string,
	active_idx: ^int,
	wrapper_style: Style = {},
	tab_style: Style = {},
	salt := "",
	id: string = "",
	loc := #caller_location,
) -> bool {
	changed := false
	root_id := lc.ID(id) if id != "" else lc.ID(loc, salt)

	// Tab header row
	final_wrapper := merge_styles(DEFAULT_TABS_WRAPPER_STYLE, wrapper_style)
	element_open(ui_ctx, Element{_box = {id = root_id}, style = final_wrapper}, loc)

	for label, i in labels {
		tab_id := lc.ID(root_id, fmt.tprintf("tab_%d", i))
		is_active := active_idx^ == i

		final_tab := merge_styles(DEFAULT_TABS_TAB_STYLE, tab_style)

		// Highlight the active tab with a thick colored bottom border (if not overridden)
		active_text := Color{0.15, 0.4, 0.8, 1.0} if is_active else Color{0.4, 0.4, 0.4, 1.0}
		active_border := Color{0.15, 0.4, 0.8, 1.0} if is_active else Color{0, 0, 0, 0}

		if tab_style.text_color == nil do final_tab.text_color = active_text
		if tab_style.border_color == nil do final_tab.border_color = active_border

		if button(ui_ctx, ev_ctx, label, id = tab_id, user_style = final_tab) {
			active_idx^ = i
			changed = true
		}
	}

	element_close(ui_ctx)
	return changed
}

// --- ACCORDION ---
DEFAULT_ACCORDION_WRAPPER_STYLE :: Style {
	direction     = .COLUMN,
	width         = lc.Percent{100},
	border        = [4]f32{1, 1, 1, 1},
	border_color  = Color{0.8, 0.8, 0.8, 1},
	border_radius = [4]f32{6, 6, 6, 6},
	bg_color      = Color{1, 1, 1, 1},
	overflow_y    = .HIDDEN,
}

DEFAULT_ACCORDION_HEADER_STYLE :: Style {
	direction       = .ROW,
	width           = lc.Percent{100},
	padding         = [4]f32{12, 16, 12, 16},
	justify_content = .START, // Changed to START to neatly align the icon and text
	align_items     = .CENTER,
	gap             = 12, // Space between icon and title
	bg_color        = Color{0.96, 0.96, 0.98, 1},
	text_color      = Color{0.1, 0.1, 0.1, 1},
	border_radius   = [4]f32{0, 0, 0, 0},
}

DEFAULT_ACCORDION_ICON_STYLE :: Style {
	width      = lc.Fixed{16},
	height     = lc.Fixed{16},
	object_fit = .CONTAIN,
}

DEFAULT_ACCORDION_CONTENT_STYLE :: Style {
	direction = .COLUMN,
	width     = lc.Percent{100},
	padding   = [4]f32{16, 16, 16, 16},
	gap       = 12,
}

accordion_begin :: proc(
	ui_ctx: ^UI_Context,
	ev_ctx: ^events.Event_Context,
	sdl_rend: ^sdl.Renderer,
	title: string,
	is_expanded: ^bool,
	expanded_icon: string = "assets/pictures/down.png",
	collapsed_icon: string = "assets/pictures/play.png",
	wrapper_style: Style = {},
	header_style: Style = {},
	content_style: Style = {},
	icon_style: Style = {},
	salt := "",
	id: string = "",
	loc := #caller_location,
) -> bool {
	root_id := lc.ID(id) if id != "" else lc.ID(loc, salt)
	header_id := lc.ID(root_id, "header")
	content_id := lc.ID(root_id, "content")

	final_wrapper := merge_styles(DEFAULT_ACCORDION_WRAPPER_STYLE, wrapper_style)
	element_open(ui_ctx, Element{_box = {id = root_id}, style = final_wrapper}, loc)

	// --- Interactive Header Container ---
	events.register(ev_ctx, header_id, events.Event_Callbacks{focusable = true, cursor = .HAND})
	if ev_ctx.clicked_this_frame[header_id] or_else false {
		is_expanded^ = !is_expanded^
	}

	final_header := merge_styles(DEFAULT_ACCORDION_HEADER_STYLE, header_style)

	// Apply a manual darkening effect when hovered to mimic the button hover state
	is_hovered := is_tree_hovered(ui_ctx, ev_ctx, header_id)
	if is_hovered {
		if bg, ok := final_header.bg_color.?; ok {
			final_header.bg_color = Color {
				max(bg[0] - 0.05, 0.0),
				max(bg[1] - 0.05, 0.0),
				max(bg[2] - 0.05, 0.0),
				bg[3],
			}
		}
	}

	element_open(ui_ctx, Element{_box = {id = header_id}, style = final_header}, loc)

	// Indicator Icon
	icon_path := is_expanded^ ? expanded_icon : collapsed_icon
	final_icon := merge_styles(DEFAULT_ACCORDION_ICON_STYLE, icon_style)
	image_path(ui_ctx, sdl_rend, icon_path, user_style = final_icon)

	// Title Text
	text_col := final_header.text_color.? or_else Color{0.1, 0.1, 0.1, 1}
	font_sz := final_header.font_size.? or_else 16
	text(ui_ctx, ev_ctx, title, user_style = {text_color = text_col, font_size = font_sz})

	element_close(ui_ctx) // close header container

	// --- Content Block ---
	if is_expanded^ {
		final_content := merge_styles(DEFAULT_ACCORDION_CONTENT_STYLE, content_style)
		element_open(ui_ctx, Element{_box = {id = content_id}, style = final_content})
		return true
	}

	element_close(ui_ctx) // close wrapper early if collapsed
	return false
}

accordion_end :: proc(ui_ctx: ^UI_Context, is_expanded: bool) {
	if is_expanded {
		element_close(ui_ctx) // close content block
		element_close(ui_ctx) // close wrapper block
	}
}

// --- DATA TABLE ---
DEFAULT_TABLE_WRAPPER_STYLE :: Style {
	direction     = .COLUMN,
	width         = lc.Percent{100},
	height        = lc.Fit(true),
	border        = [4]f32{1, 1, 1, 1},
	border_color  = Color{0.8, 0.8, 0.8, 1},
	border_radius = [4]f32{6, 6, 6, 6},
	bg_color      = Color{1, 1, 1, 1},
	overflow_y    = .HIDDEN,
}

DEFAULT_TABLE_HEADER_ROW_STYLE :: Style {
	direction    = .ROW,
	width        = lc.Percent{100},
	bg_color     = Color{0.95, 0.95, 0.97, 1},
	padding      = [4]f32{12, 16, 12, 16},
	border       = [4]f32{0, 0, 1, 0},
	border_color = Color{0.8, 0.8, 0.8, 1},
}

DEFAULT_TABLE_HEADER_TEXT_STYLE :: Style {
	font_size  = 14,
	text_color = Color{0.4, 0.4, 0.4, 1},
}

DEFAULT_TABLE_ROW_STYLE :: Style {
	direction    = .ROW,
	width        = lc.Percent{100},
	padding      = [4]f32{12, 16, 12, 16},
	border       = [4]f32{0, 0, 1, 0},
	border_color = Color{0.9, 0.9, 0.9, 1},
}

DEFAULT_TABLE_CELL_TEXT_STYLE :: Style {
	font_size  = 16,
	text_color = Color{0.1, 0.1, 0.1, 1},
}

DEFAULT_TABLE_SCROLL_STYLE :: Style {
	direction = .COLUMN,
	width     = lc.Percent{100},
	height    = lc.Grow{1},
}

table :: proc(
	ui_ctx: ^UI_Context,
	ev_ctx: ^events.Event_Context,
	headers: []string,
	rows: [][]string,
	col_widths: []lc.Sizing,
	wrapper_style: Style = {},
	header_row_style: Style = {},
	header_text_style: Style = {},
	row_style: Style = {},
	cell_text_style: Style = {},
	scroll_style: Style = {},
	salt := "",
	id: string = "",
	loc := #caller_location,
) {
	root_id := lc.ID(id) if id != "" else lc.ID(loc, salt)
	header_id := lc.ID(root_id, "header")
	body_id := lc.ID(root_id, "body")

	final_wrapper := merge_styles(DEFAULT_TABLE_WRAPPER_STYLE, wrapper_style)
	element_open(ui_ctx, Element{_box = {id = root_id}, style = final_wrapper}, loc)

	// 1. Header Row
	final_header_row := merge_styles(DEFAULT_TABLE_HEADER_ROW_STYLE, header_row_style)
	element_open(ui_ctx, Element{_box = {id = header_id}, style = final_header_row})

	final_header_text := merge_styles(DEFAULT_TABLE_HEADER_TEXT_STYLE, header_text_style)
	for h, i in headers {
		element_open(ui_ctx, Element{style = {width = col_widths[i], justify_content = .START}})
		text(ui_ctx, ev_ctx, h, user_style = final_header_text)
		element_close(ui_ctx)
	}
	element_close(ui_ctx)

	// 2. Scrollable Body
	final_scroll_style := merge_styles(DEFAULT_TABLE_SCROLL_STYLE, scroll_style)
	scroll_begin(
		ui_ctx,
		ev_ctx,
		id = body_id,
		scroll_y = true,
		scroll_x = false,
		user_style = final_scroll_style,
	)

	final_cell_text := merge_styles(DEFAULT_TABLE_CELL_TEXT_STYLE, cell_text_style)

	for row, r_idx in rows {
		row_id := lc.ID(body_id, fmt.tprintf("row_%d", r_idx))
		final_row := merge_styles(DEFAULT_TABLE_ROW_STYLE, row_style)

		// Zebra striping for rows (only if user didn't explicitly set a row background color)
		if row_style.bg_color == nil {
			final_row.bg_color =
				Color{0.98, 0.98, 0.98, 1} if r_idx % 2 == 1 else Color{1, 1, 1, 1}
		}

		element_open(ui_ctx, Element{_box = {id = row_id}, style = final_row})

		for cell, c_idx in row {
			element_open(
				ui_ctx,
				Element{style = {width = col_widths[c_idx], justify_content = .START}},
			)
			text(ui_ctx, ev_ctx, cell, user_style = final_cell_text)
			element_close(ui_ctx)
		}

		element_close(ui_ctx)
	}

	scroll_end(ui_ctx)
	element_close(ui_ctx) // close wrapper
}

// --- LIST VIEW ---
DEFAULT_LIST_WRAPPER_STYLE :: Style {
	direction     = .COLUMN,
	width         = lc.Percent{100},
	height        = lc.Grow{1},
	border        = [4]f32{1, 1, 1, 1},
	border_color  = Color{0.8, 0.8, 0.8, 1},
	border_radius = [4]f32{6, 6, 6, 6},
	bg_color      = Color{1, 1, 1, 1},
	overflow_y    = .HIDDEN,
}

DEFAULT_LIST_SCROLL_STYLE :: Style {
	direction = .COLUMN,
	width     = lc.Percent{100},
	height    = lc.Percent{100},
}

DEFAULT_LIST_ITEM_STYLE :: Style {
	width         = lc.Percent{100},
	padding       = [4]f32{12, 16, 12, 16},
	text_align    = .LEFT,
	border_radius = [4]f32{0, 0, 0, 0},
}

list_view :: proc(
	ui_ctx: ^UI_Context,
	ev_ctx: ^events.Event_Context,
	items: []string,
	selected_idx: ^int,
	wrapper_style: Style = {},
	scroll_style: Style = {},
	item_style: Style = {},
	salt := "",
	id: string = "",
	loc := #caller_location,
) -> bool {
	changed := false
	root_id := lc.ID(id) if id != "" else lc.ID(loc, salt)
	scroll_id := lc.ID(root_id, "scroll")

	final_wrapper := merge_styles(DEFAULT_LIST_WRAPPER_STYLE, wrapper_style)
	element_open(ui_ctx, Element{_box = {id = root_id}, style = final_wrapper}, loc)

	final_scroll := merge_styles(DEFAULT_LIST_SCROLL_STYLE, scroll_style)
	scroll_begin(
		ui_ctx,
		ev_ctx,
		id = scroll_id,
		scroll_y = true,
		scroll_x = false,
		user_style = final_scroll,
	)

	for item, i in items {
		item_id := lc.ID(scroll_id, fmt.tprintf("item_%d", i))
		is_selected := selected_idx^ == i

		final_item := merge_styles(DEFAULT_LIST_ITEM_STYLE, item_style)

		// Determine dynamic states, respecting explicit user overrides
		opt_bg := Color{0.15, 0.4, 0.8, 0.1} if is_selected else Color{0, 0, 0, 0}
		opt_text := Color{0.15, 0.4, 0.8, 1.0} if is_selected else Color{0.3, 0.3, 0.3, 1.0}

		if item_style.bg_color == nil do final_item.bg_color = opt_bg
		if item_style.text_color == nil do final_item.text_color = opt_text

		if button(ui_ctx, ev_ctx, item, id = item_id, user_style = final_item) {
			selected_idx^ = i
			changed = true
		}
	}

	scroll_end(ui_ctx)
	element_close(ui_ctx)

	return changed
}
