package UI

import "core:fmt"
import "core:hash"
import "core:math"
import "core:strings"
import sdl "vendor:sdl2"
import img "vendor:sdl2/image"
import "vendor:sdl2/ttf"

is_tree_hovered :: proc(app: ^App, target_id: Box_ID) -> bool {
	ui_ctx := app.ui
	ev_ctx := app.ev

	curr := ev_ctx.hovered_id
	for curr != 0 {
		if curr == target_id do return true

		if prev, ok := ui_ctx.layout.prev_all_boxes[curr]; ok && prev.parent != nil {
			curr = prev.parent.id
		} else {
			break
		}
	}
	return false
}

text :: proc(
	app: ^App,
	text: string,
	user_style := Style{},
	salt := "",
	id: string = "",
	loc := #caller_location,
) {
	ui_ctx := app.ui
	ev_ctx := app.ev

	hash_input := fmt.tprintf("%s:%d:%s", loc.file_path, loc.line, salt)
	final_id := ID(hash_input)

	register(ev_ctx, final_id, Event_Callbacks{focusable = true})

	is_pressed := ev_ctx.pressed_id == final_id
	just_pressed := is_pressed && ev_ctx.prev_pressed_id != final_id
	is_focused := ev_ctx.focused_id == final_id

	if final_id not_in ev_ctx.text_cursors do ev_ctx.text_cursors[final_id] = 0
	if final_id not_in ev_ctx.text_selection do ev_ctx.text_selection[final_id] = 0

	if !is_focused {
		ev_ctx.text_selection[final_id] = 0
		ev_ctx.text_cursors[final_id] = 0
	}

	final_style := user_style
	if user_style.text_wrap == nil do final_style.text_wrap = .WORD
	if ev_ctx.text_cursors[final_id] != ev_ctx.text_selection[final_id] {
		final_style.selection_start = ev_ctx.text_selection[final_id]
		final_style.selection_end = ev_ctx.text_cursors[final_id]
	}

	parent_font_name := ""
	parent_font_size: f32 = 16.0
	if len(ui_ctx.layout.parent_stack) > 0 {
		parent_box := ui_ctx.layout.parent_stack[len(ui_ctx.layout.parent_stack) - 1]
		if parent_box.user_data != nil {
			parent_el := (^Element)(parent_box.user_data)
			parent_font_name = parent_el.resolved_font_name
			parent_font_size = parent_el.resolved_font_size
		}
	}

	font_path := final_style.font_name.? or_else parent_font_name
	font_size := final_style.font_size.? or_else parent_font_size
	active_font := get_font(ui_ctx, font_path, font_size)

	if is_pressed {
		if prev_box, ok := ui_ctx.layout.prev_all_boxes[final_id]; ok {
			mx, my: i32
			sdl.GetMouseState(&mx, &my)
			local_x := f32(mx) - prev_box.x

			dummy_el := Element {
				resolved_font = active_font,
			}
			dummy_box := Box {
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

			ev_ctx.text_cursors[final_id] = best_cursor
			if just_pressed {
				ev_ctx.text_selection[final_id] = best_cursor
			}
		}
	}

	element_open(ui_ctx, Element{_box = {id = final_id}, text = text, style = final_style}, loc)
	element_close(ui_ctx)
}

DEFAULT_BUTTON_STYLE :: Style {
	padding       = [4]f32{12, 24, 12, 24},
	border_radius = [4]f32{6, 6, 6, 6},
	text_color    = Color{1, 1, 1, 1},
	text_align    = .CENTER,
	width         = Fit(true),
	height        = Fit(true),
	bg_color      = Color{0.15, 0.4, 0.8, 1.0},
}

button :: proc(
	app: ^App,
	text: string,
	user_style := Style{},
	salt := "",
	id: Box_ID = 0,
	loc := #caller_location,
) -> bool {
	ui_ctx := app.ui
	ev_ctx := app.ev
	final_id := id
	if final_id == 0 {
		hash_input := fmt.tprintf("%s:%d:%s", loc.file_path, loc.line, salt)
		final_id = ID(hash_input)
	}

	is_hovered := is_tree_hovered(app, final_id)
	is_pressed := ev_ctx.pressed_id == final_id
	is_clicked := ev_ctx.clicked_this_frame[final_id] or_else false

	register(ev_ctx, final_id, Event_Callbacks{focusable = true, cursor = .HAND})

	final_style := merge_styles(DEFAULT_BUTTON_STYLE, user_style)
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

DEFAULT_TOOLTIP_STYLE :: Style {
	position      = .FIXED,
	z_index       = 1000,
	direction     = .COLUMN,
	bg_color      = Color{0.1, 0.1, 0.15, 0.95},
	border_color  = Color{1, 1, 1, 0.1},
	border        = [4]f32{1, 1, 1, 1},
	border_radius = [4]f32{6, 6, 6, 6},
	padding       = [4]f32{8, 12, 8, 12},
	width         = Fit(true),
	height        = Fit(true),
}

tooltip_begin :: proc(
	app: ^App,
	target_id: Box_ID,
	user_style := Style{},
	loc := #caller_location,
) -> bool {
	ui_ctx := app.ui
	ev_ctx := app.ev
	if ev_ctx.hovered_id != target_id do return false

	target_x, target_y, target_w, target_h: f32 = 0, 0, 0, 0
	if prev, ok := ui_ctx.layout.prev_all_boxes[target_id]; ok {
		target_x = prev.x
		target_y = prev.y
		target_w = prev.computed_width
		target_h = prev.computed_height
	}

	final_style := merge_styles(DEFAULT_TOOLTIP_STYLE, user_style)

	if final_style.left == nil do final_style.left = target_x
	if final_style.top == nil do final_style.top = target_y + target_h + 10.0

	tooltip_id := Box_ID(hash.fnv32(transmute([]byte)fmt.tprintf("tooltip_%d", target_id)))
	element_open(ui_ctx, Element{_box = {id = tooltip_id}, style = final_style}, loc)
	return true
}

tooltip_end :: proc(app: ^App, is_open: bool) {
	if is_open do element_close(app.ui)
}

scroll_begin :: proc(
	app: ^App,
	id: Box_ID = 0,
	scroll_y: bool = true,
	scroll_x: bool = false,
	user_style := Style{},
	salt := "",
	loc := #caller_location,
) -> Box_ID {
	ui_ctx := app.ui
	ev_ctx := app.ev
	final_id := id
	if final_id == 0 {
		hash_input := fmt.tprintf("%s:%d:%s", loc.file_path, loc.line, salt)
		final_id = ID(hash_input)
	}

	final_style := user_style
	if scroll_y do final_style.overflow_y = .SCROLL
	if scroll_x do final_style.overflow_x = .SCROLL

	if final_style.direction == nil {
		final_style.direction = scroll_y ? Direction.COLUMN : Direction.ROW
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
	return final_id
}

scroll_end :: proc(app: ^App, id: Box_ID) {
	ui_ctx := app.ui
	ev_ctx := app.ev
	anim_ctx := app.anim

	if prev, ok := ui_ctx.layout.prev_all_boxes[id]; ok {
		content_h: f32 = 0
		for child in prev.children {
			content_h = max(content_h, child.y + child.computed_height - prev.y)
		}

		if content_h > prev.computed_height {
			ratio := prev.computed_height / content_h
			thumb_h := max(prev.computed_height * ratio, 24.0)

			max_scroll := content_h - prev.computed_height
			scroll_y := ev_ctx.scroll_offsets_y[id]
			scroll_progress := max_scroll > 0 ? clamp(scroll_y / max_scroll, 0.0, 1.0) : 0.0
			thumb_y := (scroll_progress * (prev.computed_height - thumb_h)) + scroll_y

			sb_id := ID(id, "scrollbar")
			is_hovered := is_tree_hovered(app, id)

			opacity: f32 = is_hovered ? 1.0 : 0.0

			// Safely handle animations only if anim_ctx is provided
			if anim_ctx != nil {
				@(static) prev_hover: map[Box_ID]bool
				if sb_id not_in prev_hover do prev_hover[sb_id] = false

				if prev_hover[sb_id] != is_hovered {
					prev_hover[sb_id] = is_hovered
					to(
						ui_ctx,
						anim_ctx,
						sb_id,
						{opacity = is_hovered ? 1.0 : 0.0, duration = 0.25},
					)
				}
				sb_state := get_state(anim_ctx, sb_id)
				opacity = sb_state.opacity
			}

			if is_hovered || opacity > 0.01 {
				element_open(
					ui_ctx,
					Element {
						_box = {id = sb_id},
						style = {
							position = .ABSOLUTE,
							right = 4.0,
							top = thumb_y + 4.0,
							width = Fixed{6},
							height = Fixed{thumb_h - 8.0},
							bg_color = Color{0.4, 0.4, 0.4, opacity * 0.8},
							border_radius = space(3),
							z_index = 100,
						},
					},
				)
				element_close(ui_ctx)
			}
		}
	}
	element_close(ui_ctx)
}

DEFAULT_CHECKBOX_WRAPPER_STYLE :: Style {
	width         = Fit(true),
	height        = Fit(true),
	direction     = .ROW,
	align_items   = .CENTER,
	gap           = 12,
	padding       = [4]f32{8, 12, 8, 12},
	border_radius = [4]f32{6, 6, 6, 6},
	bg_color      = Color{0, 0, 0, 0},
}
DEFAULT_CHECKBOX_BOX_STYLE :: Style {
	width         = Fixed{24},
	height        = Fixed{24},
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
	app: ^App,
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
	ui_ctx := app.ui
	ev_ctx := app.ev
	root_id := id != "" ? ID(id) : ID(loc, salt)
	box_id := ID(root_id, "box")
	text_id := ID(root_id, "text")

	register(ev_ctx, root_id, Event_Callbacks{focusable = true, cursor = .HAND})
	if ev_ctx.clicked_this_frame[root_id] or_else false do state^ = !state^

	is_hovered := is_tree_hovered(app, root_id)

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

DEFAULT_RADIO_WRAPPER_STYLE :: Style {
	width         = Fit(true),
	height        = Fit(true),
	direction     = .ROW,
	align_items   = .CENTER,
	gap           = 12,
	padding       = [4]f32{8, 12, 8, 12},
	border_radius = [4]f32{6, 6, 6, 6},
	bg_color      = Color{0, 0, 0, 0},
}
DEFAULT_RADIO_BUTTON_STYLE :: Style {
	width         = Fixed{24},
	height        = Fixed{24},
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
	app: ^App,
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
	ui_ctx := app.ui
	ev_ctx := app.ev
	hash_input := id
	if id == "" do hash_input = fmt.tprintf("%s:%d:%s", loc.file_path, loc.line, salt)

	root_id := ID(hash_input)
	button_id := ID(fmt.tprintf("%d_btn", root_id))
	text_id := ID(fmt.tprintf("%d_text", root_id))

	register(ev_ctx, root_id, Event_Callbacks{focusable = true, cursor = .HAND})
	if ev_ctx.clicked_this_frame[root_id] or_else false do state^ = value
	is_active := state^ == value

	is_hovered := is_tree_hovered(app, root_id)
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

DEFAULT_SLIDER_WRAPPER_STYLE :: Style {
	width           = Percent{100},
	height          = Fixed{30},
	justify_content = .START,
	align_items     = .CENTER,
}
DEFAULT_SLIDER_TRACK_STYLE :: Style {
	width         = Percent{100},
	height        = Fixed{4},
	bg_color      = Color{0.8, 0.8, 0.8, 0.25},
	border_radius = [4]f32{2, 2, 2, 2},
}

DEFAULT_SLIDER_FILL_STYLE :: Style {
	height        = Percent{100},
	bg_color      = Color{0.9, 0.2, 0.2, 1.0},
	border_radius = [4]f32{2, 2, 2, 2},
}

DEFAULT_SLIDER_THUMB_STYLE :: Style {
	position      = .ABSOLUTE,
	top           = 8.0,
	width         = Fixed{14},
	height        = Fixed{14},
	bg_color      = Color{1, 0, 0, 1},
	border_radius = [4]f32{7, 7, 7, 7},
}

slider :: proc(
	app: ^App,
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
	ui_ctx := app.ui
	ev_ctx := app.ev
	anim_ctx := app.anim
	root_id := ID(loc, salt)
	fill_id := ID(root_id, "fill")
	track_id := ID(root_id, "track")
	thumb_id := ID(root_id, "thumb")

	register(ev_ctx, root_id, Event_Callbacks{focusable = true})

	changed = false
	target_val := value^

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
					tween_to(
						&anim_ctx.engine,
						Tween_Vars {
							duration = 0.25,
							ease_func = ease_out_exp,
							properties = {{target = value, to = new_val}},
						},
					)
				} else if is_dragging {
					tween_to(
						&anim_ctx.engine,
						Tween_Vars {
							duration = 0.05,
							ease_func = ease_linear,
							properties = {{target = value, to = new_val}},
						},
					)
				}
				changed = true
				target_val = new_val
			}
		}
	}

	fill_percent := clamp((value^ - min_val) / (max_val - min_val), 0.0, 1.0)

	element_open(ui_ctx, Element{_box = {id = root_id}, style = wrapper_style}, loc)
	element_open(ui_ctx, Element{_box = {id = track_id}, style = track_style})

	dynamic_fill := fill_style
	dynamic_fill.width = Percent{fill_percent * 100.0}
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

	return changed, target_val
}

DEFAULT_TEXT_INPUT_WRAPPER_STYLE :: Style {
	width         = Percent{100},
	height        = Fixed{50},
	padding       = [4]f32{5, 5, 5, 5},
	border_radius = [4]f32{6, 6, 6, 6},
	border        = [4]f32{2, 2, 2, 2},
	border_color  = Color{0.8, 0.8, 0.8, 1},
	bg_color      = Color{1, 1, 1, 1},
}
DEFAULT_TEXT_INPUT_TEXT_STYLE :: Style {
	width      = Fit(true),
	height     = Fit(true),
	font_size  = 28,
	text_wrap  = .NONE,
	text_color = Color{0.1, 0.1, 0.1, 1},
}

@(private = "file")
_delete_selection :: proc(buf: ^[dynamic]u8, ev_ctx: ^Event_Context, id: Box_ID) -> bool {
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

@(private = "file")
_text_input_cb :: proc(e: ^UI_Event, data: rawptr) {
	ev_ctx := (^Event_Context)(data)
	if ev_ctx.focused_buffer == nil do return

	_delete_selection(ev_ctx.focused_buffer, ev_ctx, e.current_target)

	buf := ev_ctx.focused_buffer
	cursor := clamp(ev_ctx.text_cursors[e.current_target], 0, len(buf^))

	for i in 0 ..< len(e.text) {
		inject_at(buf, cursor + i, e.text[i])
	}
	ev_ctx.text_cursors[e.current_target] = cursor + len(e.text)
	ev_ctx.text_selection[e.current_target] = ev_ctx.text_cursors[e.current_target]
}

@(private = "file")
_key_down_cb :: proc(e: ^UI_Event, data: rawptr) {
	ev_ctx := (^Event_Context)(data)
	if ev_ctx.focused_buffer == nil do return

	buf := ev_ctx.focused_buffer
	cursor := clamp(ev_ctx.text_cursors[e.current_target], 0, len(buf^))

	anchor := clamp(ev_ctx.text_selection[e.current_target], 0, len(buf^))
	ev_ctx.text_selection[e.current_target] = anchor
	has_selection := cursor != anchor

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
				defer sdl.free(rawptr(clipboard_cstr))

				_delete_selection(buf, ev_ctx, e.current_target)

				active_cursor := clamp(ev_ctx.text_cursors[e.current_target], 0, len(buf^))
				pasted_str := string(clipboard_cstr)

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
	app: ^App,
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
	ui_ctx := app.ui
	ev_ctx := app.ev
	root_id := ID(id) if id != "" else ID(loc, salt)
	string_id := ID(root_id, "text")

	register(
		ev_ctx,
		root_id,
		Event_Callbacks {
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

		if root_id not_in ev_ctx.cursor_blink_start {
			ev_ctx.cursor_blink_start[root_id] = u64(sdl.GetTicks())
		}
	} else if ev_ctx.focused_buffer == buffer {
		sdl.StopTextInput()
		ev_ctx.focused_buffer = nil
	}

	cursor := clamp(ev_ctx.text_cursors[root_id], 0, len(buffer))

	final_text := merge_styles(DEFAULT_TEXT_INPUT_TEXT_STYLE, text_style)
	parent_font_name := ""
	parent_font_size: f32 = 16.0
	if len(ui_ctx.layout.parent_stack) > 0 {
		parent_box := ui_ctx.layout.parent_stack[len(ui_ctx.layout.parent_stack) - 1]
		if parent_box.user_data != nil {
			parent_el := (^Element)(parent_box.user_data)
			parent_font_name = parent_el.resolved_font_name
			parent_font_size = parent_el.resolved_font_size
		}
	}

	font_path := final_text.font_name.? or_else parent_font_name
	font_size := final_text.font_size.? or_else parent_font_size
	active_font := get_font(ui_ctx, font_path, font_size)

	dummy_el := Element {
		resolved_font = active_font,
	}
	dummy_box := Box {
		user_data = &dummy_el,
	}

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

			if just_pressed {
				ev_ctx.text_selection[root_id] = best_cursor
				ev_ctx.cursor_blink_start[root_id] = u64(sdl.GetTicks())
			}

			anchor := clamp(ev_ctx.text_selection[root_id], 0, len(buffer))
			ev_ctx.text_selection[root_id] = anchor
		}
	}

	if is_focused {
		if root_id not_in ev_ctx.cursor_last_position {
			ev_ctx.cursor_last_position[root_id] = cursor
		}

		if ev_ctx.cursor_last_position[root_id] != cursor {
			ev_ctx.cursor_last_position[root_id] = cursor
			ev_ctx.cursor_blink_start[root_id] = u64(sdl.GetTicks())
		}
	}

	current_len := len(buffer^)
	cursor = clamp(ev_ctx.text_cursors[root_id], 0, current_len)
	anchor := clamp(ev_ctx.text_selection[root_id], 0, current_len)
	cursor_px := ui_text_width(&dummy_box, string(buffer^[:cursor]))

	if is_focused {
		if prev_outer, ok := ui_ctx.layout.prev_all_boxes[root_id]; ok {
			scroll_x := ev_ctx.scroll_offsets_x[root_id]

			padding_left := prev_outer.padding[3]
			border_left := prev_outer.border[3]

			viewport_left := padding_left + border_left
			viewport_right :=
				prev_outer.computed_width - prev_outer.padding[1] - prev_outer.border[1]
			viewport_width := max(viewport_right - viewport_left, 1.0)

			cursor_px := ui_text_width(&dummy_box, string(buffer^[:cursor]))
			margin: f32 = 5.0
			cursor_left := cursor_px
			cursor_right := cursor_px + 2.0

			if cursor_left < scroll_x + margin {
				ev_ctx.scroll_offsets_x[root_id] = max(cursor_left - margin, 0)
			} else if cursor_right > scroll_x + viewport_width - margin {
				ev_ctx.scroll_offsets_x[root_id] = cursor_right - viewport_width + margin
			}

			total_text_width := ui_text_width(&dummy_box, string(buffer^[:]))
			max_scroll := max(total_text_width + 15.0 - viewport_width, 0.0)

			ev_ctx.scroll_offsets_x[root_id] = clamp(
				ev_ctx.scroll_offsets_x[root_id],
				0.0,
				max_scroll,
			)
			prev_outer.offset_x = ev_ctx.scroll_offsets_x[root_id]
		}
	}

	display_text := ""
	if len(buffer) > 0 do display_text = string(buffer^[:])
	else do display_text = placeholder

	cursor_visible := false
	if is_focused {
		elapsed := u64(sdl.GetTicks()) - ev_ctx.cursor_blink_start[root_id]
		cursor_visible = (elapsed % 1000) < 500
	}

	final_wrapper := wrapper_style
	if is_focused do final_wrapper.border_color = focused_border_color

	scroll_begin(
		app,
		id = root_id,
		scroll_y = false,
		scroll_x = true,
		user_style = final_wrapper,
		loc = loc,
	)

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
					left = start_px,
					top = 2.0,
					width = Fixed{end_px - start_px},
					height = Percent{100},
					bg_color = Color{0.2, 0.5, 0.9, 0.4},
				},
			},
			loc,
		)
		element_close(ui_ctx)
	}

	if len(buffer) == 0 do final_text.text_color = placeholder_color
	else do final_text.text_color = text_style.text_color

	element_open(
		ui_ctx,
		Element {
			_box = {id = string_id},
			text = display_text,
			style = final_text,
			resolved_font = active_font,
		},
		loc,
	)
	element_close(ui_ctx)

	if cursor_visible {
		element_open(
			ui_ctx,
			Element {
				style = {
					position = .ABSOLUTE,
					left = cursor_px,
					top = 4.0,
					width = Fixed{2},
					height = Fixed{27},
					bg_color = Color{0.1, 0.1, 0.1, 1},
				},
			},
			loc,
		)
		element_close(ui_ctx)
	}

	scroll_end(app, root_id)
	return is_focused
}

image :: proc {
	image_texture,
	image_path,
}

image_texture :: proc(
	app: ^App,
	texture: ^sdl.Texture,
	user_style := Style{},
	salt := "",
	id: Box_ID = 0,
	loc := #caller_location,
) {
	ui_ctx := app.ui
	final_id := id
	if final_id == 0 {
		hash_input := fmt.tprintf("%s:%d:%s", loc.file_path, loc.line, salt)
		final_id = ID(hash_input)
	}

	final_style := user_style
	final_style.bg_image = texture

	tex_w, tex_h: i32 = 0, 0
	if texture != nil do sdl.QueryTexture(texture, nil, nil, &tex_w, &tex_h)

	if final_style.width == nil do final_style.width = Fixed{f32(tex_w)}
	if final_style.height == nil do final_style.height = Fixed{f32(tex_h)}

	element_open(ui_ctx, Element{_box = {id = final_id}, style = final_style}, loc)
	element_close(ui_ctx)
}

image_path :: proc(
	app: ^App,
	path: string,
	user_style: Style = {},
	salt := "",
	id: Box_ID = 0,
	loc := #caller_location,
) {
	ui_ctx := app.ui
	sdl_rend := app.renderer
	path_hash := hash.fnv32(transmute([]byte)path)
	tex, exists := ui_ctx.image_cache[path_hash]
	if !exists {
		c_path := fmt.ctprintf("%s", path)
		tex = img.LoadTexture(sdl_rend, c_path)
		if tex == nil do fmt.printfln("ERROR: Failed to load image '%s': %s", path, sdl.GetError())
		ui_ctx.image_cache[path_hash] = tex
	}
	image_texture(app, tex, user_style, salt, id, loc)
}

image_button :: proc(
	app: ^App,
	path: string,
	user_style: Style = {},
	salt := "",
	loc := #caller_location,
) -> bool {
	ui_ctx := app.ui
	ev_ctx := app.ev
	sdl_rend := app.renderer
	hash_input := fmt.tprintf("%s:%d:%s", loc.file_path, loc.line, salt)
	id := ID(hash_input)

	is_clicked := ev_ctx.clicked_this_frame[id] or_else false
	register(ev_ctx, id, Event_Callbacks{focusable = true, cursor = .HAND})

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

	if final_style.width == nil do final_style.width = Fixed{28}
	if final_style.height == nil do final_style.height = Fixed{28}
	if final_style.object_fit == nil do final_style.object_fit = .CONTAIN

	element_open(ui_ctx, Element{_box = {id = id}, style = final_style}, loc)
	element_close(ui_ctx)

	return is_clicked
}

DEFAULT_VIDEO_WRAPPER_STYLE :: Style {
	width  = Percent{100},
	height = Percent{100},
}
DEFAULT_VIDEO_FRAME_STYLE :: Style {
	width      = Percent{100},
	height     = Percent{100},
	object_fit = .CONTAIN,
}
DEFAULT_VIDEO_OVERLAY_STYLE :: Style {
	position    = .ABSOLUTE,
	bottom      = 0,
	left        = 0,
	width       = Percent{100},
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
	app: ^App,
	path: string,
	dt: f64,
	is_scrubbing: ^bool,
	scrub_time: ^f32,
	slider_val: ^f32,
	overlay_active: ^bool,
	overlay_anim: ^f32,
	play_icon: string = "assets/pictures/icons/play-button.png",
	pause_icon: string = "assets/pictures/icons/pause.png",
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
	ui_ctx := app.ui
	ev_ctx := app.ev
	anim_ctx := app.anim
	sdl_rend := app.renderer

	hash_input := id
	if id == "" do hash_input = fmt.tprintf("%s:%d:%s", loc.file_path, loc.line, salt)
	root_id := ID(hash_input)

	if path not_in ui_ctx.videos {
		ui_ctx.videos[path] = video_player_init(sdl_rend, path)
	}
	player := ui_ctx.videos[path]

	if player != nil && player.is_playing {
		video_player_update(player, dt)
	}

	final_wrapper := merge_styles(DEFAULT_VIDEO_WRAPPER_STYLE, wrapper_style)
	final_wrapper.position = .RELATIVE
	final_wrapper.overflow_y = .HIDDEN

	{
		element_open(ui_ctx, {id = root_id, style = final_wrapper}, loc)
		defer element_close(ui_ctx)

		{
			final_frame := merge_styles(DEFAULT_VIDEO_FRAME_STYLE, frame_style)
			if final_frame.border_radius == nil do final_frame.border_radius = final_wrapper.border_radius

			el := element_open(ui_ctx, Element{style = final_frame})
			defer element_close(ui_ctx)
			if player != nil && player.texture != nil {
				if player.playback_time > 0.1 do el.resolved_bg_image = player.texture
			}
		}

		if player != nil {
			overlay_id := ID(fmt.tprintf("%d_overlay", root_id))
			should_show := is_tree_hovered(app, root_id) || is_scrubbing^

			if should_show != overlay_active^ {
				overlay_active^ = should_show
				tween_to(
					&anim_ctx.engine,
					Tween_Vars {
						duration = 0.35,
						ease_func = ease_out_exp,
						properties = {{target = overlay_anim, to = should_show ? 1.0 : 0.0}},
					},
				)
			}

			if overlay_anim^ > 0.001 {
				final_overlay := merge_styles(DEFAULT_VIDEO_OVERLAY_STYLE, overlay_style)

				if final_overlay.border_radius == nil {
					if br, ok := final_wrapper.border_radius.?; ok {
						final_overlay.border_radius = [4]f32{0, 0, br[2], br[3]}
					}
				}

				offset_y := 55.0 * (1.0 - overlay_anim^)
				final_overlay.bottom = -offset_y

				if bg, ok := final_overlay.bg_color.?; ok {
					final_overlay.bg_color = Color{bg[0], bg[1], bg[2], bg[3] * overlay_anim^}
				}

				{
					element_open(ui_ctx, Element{_box = {id = overlay_id}, style = final_overlay})
					defer element_close(ui_ctx)

					icon := player.is_playing ? pause_icon : play_icon
					if image_button(
						app,
						icon,
						user_style = play_btn_style,
						salt = fmt.tprintf("%s_play", salt),
					) {
						player.is_playing = !player.is_playing
						sdl.PauseAudioDevice(player.audio_dev, !player.is_playing)
					}

					display_time := is_scrubbing^ ? f64(scrub_time^) : player.playback_time
					curr_m := int(display_time) / 60
					curr_s := int(display_time) % 60
					tot_m := int(player.duration) / 60
					tot_s := int(player.duration) % 60
					time_str := fmt.tprintf("%02d:%02d / %02d:%02d", curr_m, curr_s, tot_m, tot_s)

					final_time_style := merge_styles(DEFAULT_VIDEO_TIME_STYLE, time_style)

					text(
						app,
						time_str,
						user_style = final_time_style,
						salt = fmt.tprintf("%s_time", salt),
					)

					mouse_state := sdl.GetMouseState(nil, nil)
					is_mouse_down := (mouse_state & sdl.BUTTON_LMASK) != 0

					slider_val^ = is_scrubbing^ ? scrub_time^ : f32(player.playback_time)

					final_slider_wrapper := merge_styles(
						DEFAULT_SLIDER_WRAPPER_STYLE,
						slider_wrapper_style,
					)
					final_slider_wrapper.width = Grow{1}

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
						app,
						slider_val,
						0.0,
						f32(player.duration),
						wrapper_style = final_slider_wrapper,
						track_style = final_slider_track,
						fill_style = final_slider_fill,
						thumb_style = final_slider_thumb,
						salt = fmt.tprintf("%s_slider", salt),
					)

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
	width         = Fit(true),
	height        = Fit(true),
}

popover_begin :: proc(
	app: ^App,
	target_id: Box_ID,
	is_open: ^bool,
	user_style: Style = {},
	salt := "",
	loc := #caller_location,
) -> bool {
	ui_ctx := app.ui
	ev_ctx := app.ev
	anim_ctx := app.anim
	if !is_open^ do return false

	hash_input := fmt.tprintf("%s:%d:%s", loc.file_path, loc.line, salt)
	root_id := ID(hash_input)

	backdrop_id := ID(fmt.tprintf("%d_backdrop", root_id))
	content_id := ID(fmt.tprintf("%d_content", root_id))

	register(ev_ctx, backdrop_id, Event_Callbacks{focusable = true})

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
				width = ViewPercent{100},
				height = ViewPercent{100},
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

	final_style := merge_styles(DEFAULT_POPOVER_STYLE, user_style)
	final_style.position = .FIXED
	final_style.z_index = 1000

	if final_style.left == nil do final_style.left = target_x
	if final_style.top == nil do final_style.top = target_y + target_h + 8.0

	register(ev_ctx, content_id, Event_Callbacks{focusable = true})
	element_open(ui_ctx, Element{_box = {id = content_id}, style = final_style}, loc)

	// --- NEW: ANIMATE IN ON FIRST RENDER ---
	@(static) prev_open: map[Box_ID]bool
	if root_id not_in prev_open do prev_open[root_id] = false
	just_opened := is_open^ && !prev_open[root_id]
	prev_open[root_id] = is_open^

	if just_opened {
		from(
			ui_ctx,
			anim_ctx,
			content_id,
			{
				opacity = 0.0,
				y = (final_style.top.? or_else 0.0) - 10.0,
				duration = 0.2,
				ease = ease_out_exp,
			},
		)
	}

	return true
}

popover_end :: proc(app: ^App, is_open: bool) {
	if is_open do element_close(app.ui)
}

DEFAULT_DROPDOWN_STYLE :: Style {
	width         = Fixed{200},
	height        = Fit(true),
	padding       = [4]f32{8, 12, 8, 12},
	border_radius = [4]f32{6, 6, 6, 6},
	border        = [4]f32{1, 1, 1, 1},
	border_color  = Color{0.8, 0.8, 0.8, 1},
	bg_color      = Color{1, 1, 1, 1},
	text_color    = Color{0, 0, 0, 1},
}

DEFAULT_DROPDOWN_POPOVER_STYLE :: Style {
	align_items   = .STRETCH,
	width         = Fit(true),
	direction     = .COLUMN,
	bg_color      = Color{1, 1, 1, 1},
	border_radius = [4]f32{6, 6, 6, 6},
	border        = [4]f32{1, 1, 1, 1},
	border_color  = Color{0.8, 0.8, 0.8, 1},
	padding       = [4]f32{4, 4, 4, 4},
}

dropdown :: proc(
	app: ^App,
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
	ui_ctx := app.ui
	ev_ctx := app.ev
	anim_ctx := app.anim
	changed := false
	hash_input := id
	if id == "" do hash_input = fmt.tprintf("%s:%d:%s", loc.file_path, loc.line, salt)
	root_id := ID(hash_input)

	display_text := label
	if selected_idx^ >= 0 && selected_idx^ < len(options) {
		display_text = options[selected_idx^]
	}

	final_wrapper := merge_styles(DEFAULT_DROPDOWN_STYLE, wrapper_style)

	if button(app, display_text, user_style = final_wrapper, id = root_id) do is_open^ = !is_open^

	final_popover := merge_styles(DEFAULT_DROPDOWN_POPOVER_STYLE, popover_style)

	if popover_begin(
		app, // Added Context
		root_id,
		is_open,
		salt = salt,
		loc = loc,
		user_style = final_popover,
	) {
		defer popover_end(app, true)

		for opt, i in options {
			opt_id := ID(fmt.tprintf("%d_opt_%d", root_id, i))

			is_selected := selected_idx^ == i
			opt_bg := is_selected ? Color{0.15, 0.4, 0.8, 1.0} : Color{0, 0, 0, 0}
			opt_text := is_selected ? Color{1, 1, 1, 1} : Color{0.2, 0.2, 0.2, 1}

			if button(
				app,
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
	width           = ViewPercent{100},
	height          = ViewPercent{100},
	bg_color        = Color{0, 0, 0, 0.6},
	z_index         = 2000,
	direction       = .COLUMN,
	justify_content = .CENTER,
	align_items     = .CENTER,
}

DEFAULT_MODAL_STYLE :: Style {
	direction     = .COLUMN,
	bg_color      = Color{1, 1, 1, 1},
	border_radius = [4]f32{8, 8, 8, 8},
	padding       = [4]f32{24, 24, 24, 24},
	width         = Fixed{400},
	height        = Fit(true),
	gap           = 16,
	position      = .RELATIVE, // NEW: Ensures dynamic Y translation offsets work correctly
}

modal_begin :: proc(
	app: ^App,
	is_open: ^bool,
	dismiss_on_click_outside: bool = true,
	backdrop_style: Style = {},
	modal_style: Style = {},
	salt := "",
	loc := #caller_location,
) -> bool {
	ui_ctx := app.ui
	ev_ctx := app.ev
	anim_ctx := app.anim
	if !is_open^ do return false

	hash_input := fmt.tprintf("%s:%d:%s", loc.file_path, loc.line, salt)
	root_id := ID(hash_input)
	backdrop_id := ID(fmt.tprintf("%d_backdrop", root_id))
	content_id := ID(fmt.tprintf("%d_content", root_id))

	register(ev_ctx, backdrop_id, Event_Callbacks{focusable = true})

	if dismiss_on_click_outside &&
	   ev_ctx.hovered_id == backdrop_id &&
	   (ev_ctx.clicked_this_frame[backdrop_id] or_else false) {
		is_open^ = false
		return false
	}

	final_backdrop := merge_styles(DEFAULT_MODAL_BACKDROP_STYLE, backdrop_style)
	element_open(ui_ctx, Element{_box = {id = backdrop_id}, style = final_backdrop}, loc)

	register(ev_ctx, content_id, Event_Callbacks{focusable = true})

	final_modal := merge_styles(DEFAULT_MODAL_STYLE, modal_style)
	element_open(ui_ctx, Element{_box = {id = content_id}, style = final_modal}, loc)

	// --- NEW: ANIMATE IN ON FIRST RENDER ---
	@(static) prev_open: map[Box_ID]bool
	if root_id not_in prev_open do prev_open[root_id] = false
	just_opened := is_open^ && !prev_open[root_id]
	prev_open[root_id] = is_open^

	if just_opened {
		from(ui_ctx, anim_ctx, backdrop_id, {opacity = 0.0, duration = 0.25})
		from(
			ui_ctx,
			anim_ctx,
			content_id,
			{
				opacity  = 0.0,
				y        = -20.0, // Slides up
				duration = 0.35,
				ease     = ease_out_exp,
			},
		)
	}

	return true
}

modal_end :: proc(app: ^App, is_open: bool) {
	if is_open {
		element_close(app.ui)
		element_close(app.ui)
	}
}

DEFAULT_CONTEXT_MENU_BACKDROP_STYLE :: Style {
	position = .FIXED,
	top      = 0,
	left     = 0,
	width    = ViewPercent{100},
	height   = ViewPercent{100},
	z_index  = 3000,
	bg_color = Color{0, 0, 0, 0},
}

DEFAULT_CONTEXT_MENU_STYLE :: Style {
	direction     = .COLUMN,
	align_items   = .STRETCH,
	bg_color      = Color{1.0, 1.0, 1.0, 1.0},
	border        = [4]f32{1, 1, 1, 1},
	border_color  = Color{0.9, 0.9, 0.9, 1.0},
	border_radius = [4]f32{8, 8, 8, 8},
	padding       = [4]f32{8, 8, 8, 8},
	gap           = 4,
	width         = Fit(true),
	height        = Fit(true),
}

context_menu_begin :: proc(
	app: ^App,
	x, y: f32,
	is_open: ^bool,
	backdrop_style: Style = {},
	user_style: Style = {},
	salt := "",
	loc := #caller_location,
) -> (
	is_active: bool,
	target_id: Box_ID,
) {
	ui_ctx := app.ui
	ev_ctx := app.ev
	anim_ctx := app.anim
	if !is_open^ do return false, 0

	hash_input := fmt.tprintf("%s:%d:%s", loc.file_path, loc.line, salt)
	root_id := ID(hash_input)
	backdrop_id := ID(fmt.tprintf("%d_backdrop", root_id))
	content_id := ID(fmt.tprintf("%d_content", root_id))

	register(ev_ctx, backdrop_id, Event_Callbacks{focusable = true})
	if ev_ctx.hovered_id == backdrop_id && (ev_ctx.clicked_this_frame[backdrop_id] or_else false) {
		is_open^ = false
		return false, 0
	}

	final_backdrop := merge_styles(DEFAULT_CONTEXT_MENU_BACKDROP_STYLE, backdrop_style)
	element_open(ui_ctx, Element{_box = {id = backdrop_id}, style = final_backdrop}, loc)
	element_close(ui_ctx)

	final_style := merge_styles(DEFAULT_CONTEXT_MENU_STYLE, user_style)

	final_style.position = .FIXED
	final_style.left = x
	final_style.top = y
	final_style.z_index = 3001

	register(ev_ctx, content_id, Event_Callbacks{focusable = true})
	element_open(ui_ctx, Element{_box = {id = content_id}, style = final_style}, loc)

	// --- NEW: ANIMATE IN ON FIRST RENDER ---
	@(static) prev_open: map[Box_ID]bool
	if root_id not_in prev_open do prev_open[root_id] = false
	just_opened := is_open^ && !prev_open[root_id]
	prev_open[root_id] = is_open^

	if just_opened {
		from(
			ui_ctx,
			anim_ctx,
			content_id,
			{opacity = 0.0, y = y - 10.0, duration = 0.2, ease = ease_out_exp},
		)
	}

	return true, ev_ctx.context_menu_target
}

context_menu_end :: proc(app: ^App, is_open: bool) {
	if is_open do element_close(app.ui)
}

DEFAULT_SWITCH_WRAPPER_STYLE :: Style {
	width         = Fit(true),
	height        = Fit(true),
	direction     = .ROW,
	align_items   = .CENTER,
	gap           = 12,
	padding       = [4]f32{8, 12, 8, 12},
	border_radius = [4]f32{6, 6, 6, 6},
	bg_color      = Color{0, 0, 0, 0},
}

DEFAULT_SWITCH_TRACK_STYLE :: Style {
	width         = Fixed{44},
	height        = Fixed{24},
	border_radius = [4]f32{12, 12, 12, 12},
	border        = [4]f32{2, 2, 2, 2},
	border_color  = Color{0.8, 0.8, 0.8, 1},
}

DEFAULT_SWITCH_THUMB_STYLE :: Style {
	position      = .ABSOLUTE,
	top           = 2,
	width         = Fixed{16},
	height        = Fixed{16},
	border_radius = [4]f32{8, 8, 8, 8},
	bg_color      = Color{1, 1, 1, 1},
}

switch_toggle :: proc(
	app: ^App,
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
	ui_ctx := app.ui
	ev_ctx := app.ev
	anim_ctx := app.anim
	root_id := ID(id) if id != "" else ID(loc, salt)
	track_id := ID(root_id, "track")
	thumb_id := ID(root_id, "thumb")
	text_id := ID(root_id, "text")

	register(ev_ctx, root_id, Event_Callbacks{focusable = true, cursor = .HAND})
	if ev_ctx.clicked_this_frame[root_id] or_else false do state^ = !state^

	is_hovered := is_tree_hovered(app, root_id)

	final_wrapper := merge_styles(DEFAULT_SWITCH_WRAPPER_STYLE, wrapper_style)
	if is_hovered do final_wrapper.bg_color = hover_bg_color

	element_open(ui_ctx, Element{_box = {id = root_id}, style = final_wrapper}, loc)

	final_track := merge_styles(DEFAULT_SWITCH_TRACK_STYLE, track_style)
	final_track.bg_color = state^ ? active_color : inactive_color
	final_track.border_color = state^ ? active_color : Color{0.7, 0.7, 0.7, 1.0}

	element_open(ui_ctx, Element{_box = {id = track_id}, style = final_track})

	final_thumb := merge_styles(DEFAULT_SWITCH_THUMB_STYLE, thumb_style)
	final_thumb.left = state^ ? 22.0 : 2.0

	element_open(ui_ctx, Element{_box = {id = thumb_id}, style = final_thumb})
	element_close(ui_ctx)
	element_close(ui_ctx)

	final_text := merge_styles(DEFAULT_CHECKBOX_TEXT_STYLE, text_style)
	element_open(ui_ctx, Element{_box = {id = text_id}, text = label, style = final_text})
	element_close(ui_ctx)

	element_close(ui_ctx)

	// --- NEW: FIRE ANIMATION TWEENS ON TOGGLE ---
	@(static) prev_state: map[Box_ID]bool
	if root_id not_in prev_state do prev_state[root_id] = state^
	just_toggled := prev_state[root_id] != state^
	prev_state[root_id] = state^

	if just_toggled {
		to(
			ui_ctx,
			anim_ctx,
			thumb_id,
			{x = state^ ? 22.0 : 2.0, duration = 0.25, ease = ease_out_exp},
		)
		to(
			ui_ctx,
			anim_ctx,
			track_id,
			{
				bg_color = transmute([4]f32)(state^ ? active_color : inactive_color),
				border_color = transmute([4]f32)(state^ ? active_color : Color{0.7, 0.7, 0.7, 1.0}),
				duration = 0.25,
			},
		)
	}

	return ev_ctx.clicked_this_frame[root_id] or_else false
}

// --- MULTI-SELECT ---

DEFAULT_MULTI_SELECT_POPOVER_STYLE :: Style {
	align_items   = .STRETCH,
	width         = Fit(true),
	direction     = .COLUMN,
	bg_color      = Color{1, 1, 1, 1},
	border_radius = [4]f32{6, 6, 6, 6},
	border        = [4]f32{1, 1, 1, 1},
	border_color  = Color{0.8, 0.8, 0.8, 1},
	padding       = [4]f32{4, 4, 4, 4},
}

multi_select :: proc(
	app: ^App,
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
	ui_ctx := app.ui
	ev_ctx := app.ev
	anim_ctx := app.anim
	changed := false
	root_id := ID(id) if id != "" else ID(loc, salt)

	selected_count := 0
	for s in selected_states do if s do selected_count += 1

	display_text := label
	if selected_count > 0 do display_text = fmt.tprintf("%s (%d)", label, selected_count)

	final_wrapper := merge_styles(DEFAULT_DROPDOWN_STYLE, wrapper_style)

	if button(app, display_text, user_style = final_wrapper, id = root_id) do is_open^ = !is_open^

	final_popover := merge_styles(DEFAULT_MULTI_SELECT_POPOVER_STYLE, popover_style)

	if popover_begin(
		app, // Added
		root_id,
		is_open,
		salt = salt,
		loc = loc,
		user_style = final_popover,
	) {
		defer popover_end(app, is_open^)

		for opt, i in options {
			cb_salt := fmt.tprintf("%s_opt_%d", salt, i)
			if checkbox(app, opt, &selected_states[i], salt = cb_salt, loc = loc) do changed = true
		}
	}
	return changed
}

DEFAULT_COMBOBOX_POPOVER_STYLE :: Style {
	align_items   = .STRETCH,
	width         = Fit(true),
	direction     = .COLUMN,
	bg_color      = Color{1, 1, 1, 1},
	border_radius = [4]f32{6, 6, 6, 6},
	border        = [4]f32{1, 1, 1, 1},
	border_color  = Color{0.8, 0.8, 0.8, 1},
	padding       = [4]f32{4, 4, 4, 4},
}

combobox :: proc(
	app: ^App,
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
	ui_ctx := app.ui
	ev_ctx := app.ev
	anim_ctx := app.anim
	changed := false
	root_id := ID(id) if id != "" else ID(loc, salt)

	input_salt := fmt.tprintf("%s_input", salt)
	input_id := ID(loc, input_salt)

	final_wrapper := merge_styles(DEFAULT_TEXT_INPUT_WRAPPER_STYLE, wrapper_style)

	is_focused := text_input(
		app,
		buffer,
		placeholder = placeholder,
		wrapper_style = final_wrapper,
		salt = input_salt,
		loc = loc,
	)

	if ev_ctx.clicked_this_frame[input_id] or_else false do is_open^ = true

	search_str := strings.to_lower(string(buffer^[:]), context.temp_allocator)
	final_popover := merge_styles(DEFAULT_COMBOBOX_POPOVER_STYLE, popover_style)

	if popover_begin(
		app, // Added Context
		input_id,
		is_open,
		salt = salt,
		loc = loc,
		user_style = final_popover,
	) {
		defer popover_end(app, true)

		for opt, i in options {
			opt_lower := strings.to_lower(opt, context.temp_allocator)

			if strings.contains(opt_lower, search_str) || len(search_str) == 0 {
				opt_id := ID(root_id, fmt.tprintf("opt_%d", i))
				is_selected := selected_idx^ == i

				opt_bg := Color{0.15, 0.4, 0.8, 1.0} if is_selected else Color{0, 0, 0, 0}
				opt_text := Color{1, 1, 1, 1} if is_selected else Color{0.2, 0.2, 0.2, 1}

				if button(
					app,
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
	width         = Percent{100},
	height        = Fixed{8},
	bg_color      = Color{0.85, 0.85, 0.85, 1.0},
	border_radius = [4]f32{4, 4, 4, 4},
}

DEFAULT_PROGRESS_FILL_STYLE :: Style {
	height        = Percent{100},
	bg_color      = Color{0.15, 0.4, 0.8, 1.0},
	border_radius = [4]f32{4, 4, 4, 4},
}

progress_bar :: proc(
	app: ^App,
	value: f32,
	min_val: f32 = 0.0,
	max_val: f32 = 1.0,
	wrapper_style: Style = {},
	fill_style: Style = {},
	salt := "",
	id: string = "",
	loc := #caller_location,
) {
	ui_ctx := app.ui

	root_id := ID(id) if id != "" else ID(loc, salt)
	fill_id := ID(root_id, "fill")

	percent := clamp((value - min_val) / (max_val - min_val), 0.0, 1.0)

	final_wrapper := merge_styles(DEFAULT_PROGRESS_WRAPPER_STYLE, wrapper_style)
	element_open(ui_ctx, Element{_box = {id = root_id}, style = final_wrapper}, loc)

	dynamic_fill := merge_styles(DEFAULT_PROGRESS_FILL_STYLE, fill_style)
	dynamic_fill.width = Percent{percent * 100.0}

	element_open(ui_ctx, Element{_box = {id = fill_id}, style = dynamic_fill})
	element_close(ui_ctx)

	element_close(ui_ctx)
}

// --- SPINNER ---
DEFAULT_SPINNER_WRAPPER_STYLE :: Style {
	width           = Fit(true),
	height          = Fit(true),
	direction       = .ROW,
	gap             = 8,
	align_items     = .CENTER,
	justify_content = .CENTER,
}

DEFAULT_SPINNER_DOT_STYLE :: Style {
	width         = Fixed{12},
	height        = Fixed{12},
	border_radius = [4]f32{6, 6, 6, 6},
	bg_color      = Color{0.15, 0.4, 0.8, 1.0},
}

spinner :: proc(
	app: ^App,
	wrapper_style: Style = {},
	dot_style: Style = {},
	salt := "",
	id: string = "",
	loc := #caller_location,
) {
	ui_ctx := app.ui
	root_id := ID(id) if id != "" else ID(loc, salt)

	final_wrapper := merge_styles(DEFAULT_SPINNER_WRAPPER_STYLE, wrapper_style)
	element_open(ui_ctx, Element{_box = {id = root_id}, style = final_wrapper}, loc)

	time_ms := f32(sdl.GetTicks())

	// Create a staggered sine wave for the 3 bouncing dots
	for i in 0 ..< 3 {
		dot_id := ID(root_id, fmt.tprintf("dot_%d", i))

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
	width         = Fixed{320},
	height        = Fit(true),
	bg_color      = Color{1, 1, 1, 1},
	border        = [4]f32{1, 1, 1, 1},
	border_color  = Color{0.8, 0.8, 0.8, 1},
}

toast :: proc(
	app: ^App,
	title: string,
	message: string,
	type: Toast_Type = .INFO,
	is_open: ^bool,
	wrapper_style: Style = {},
	salt := "",
	id: string = "",
	loc := #caller_location,
) -> bool {
	ui_ctx := app.ui
	ev_ctx := app.ev
	if !is_open^ do return false
	closed_this_frame := false
	root_id := ID(id) if id != "" else ID(loc, salt)

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

	final_wrapper.border_color = wrapper_style.border_color.? or_else indicator_color

	if b, ok := final_wrapper.border.?; ok {
		final_wrapper.border = [4]f32{b[0], b[1], b[2], b[3] + 4.0}
	} else {
		final_wrapper.border = [4]f32{1, 1, 1, 5}
	}

	element_open(ui_ctx, Element{_box = {id = root_id}, style = final_wrapper}, loc)

	content_id := ID(root_id, "content")
	element_open(
		ui_ctx,
		Element{_box = {id = content_id}, style = {direction = .COLUMN, gap = 4, width = Grow{1}}},
	)

	text(
		app,
		title,
		user_style = {font_size = 18, text_color = Color{0.1, 0.1, 0.1, 1}},
		salt = "title",
	)
	if message != "" {
		text(
			app,
			message,
			user_style = {font_size = 14, text_color = Color{0.4, 0.4, 0.4, 1}},
			salt = "msg",
		)
	}
	element_close(ui_ctx)

	if button(
		app,
		"x",
		salt = "close",
		user_style = {
			bg_color = Color{0, 0, 0, 0},
			text_color = Color{0.5, 0.5, 0.5, 1},
			width = Fixed{24},
			height = Fixed{24},
			padding = space(0),
		},
	) {
		is_open^ = false
		closed_this_frame = true
	}

	element_close(ui_ctx)
	return closed_this_frame
}

// --- TABS ---
DEFAULT_TABS_WRAPPER_STYLE :: Style {
	direction    = .ROW,
	width        = Percent{100},
	border       = [4]f32{0, 0, 1, 0},
	border_color = Color{0.8, 0.8, 0.8, 1},
}

DEFAULT_TABS_TAB_STYLE :: Style {
	border        = [4]f32{0, 0, 3, 0},
	border_radius = [4]f32{0, 0, 0, 0},
	padding       = [4]f32{12, 16, 12, 16},
	bg_color      = Color{0, 0, 0, 0},
}

tabs :: proc(
	app: ^App,
	labels: []string,
	active_idx: ^int,
	wrapper_style: Style = {},
	tab_style: Style = {},
	salt := "",
	id: string = "",
	loc := #caller_location,
) -> bool {
	ui_ctx := app.ui
	ev_ctx := app.ev
	changed := false
	root_id := ID(id) if id != "" else ID(loc, salt)

	final_wrapper := merge_styles(DEFAULT_TABS_WRAPPER_STYLE, wrapper_style)
	element_open(ui_ctx, Element{_box = {id = root_id}, style = final_wrapper}, loc)

	for label, i in labels {
		tab_id := ID(root_id, fmt.tprintf("tab_%d", i))
		is_active := active_idx^ == i

		final_tab := merge_styles(DEFAULT_TABS_TAB_STYLE, tab_style)

		active_text := Color{0.15, 0.4, 0.8, 1.0} if is_active else Color{0.4, 0.4, 0.4, 1.0}
		active_border := Color{0.15, 0.4, 0.8, 1.0} if is_active else Color{0, 0, 0, 0}

		if tab_style.text_color == nil do final_tab.text_color = active_text
		if tab_style.border_color == nil do final_tab.border_color = active_border

		if button(app, label, id = tab_id, user_style = final_tab) {
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
	width         = Percent{100},
	border        = [4]f32{1, 1, 1, 1},
	border_color  = Color{0.8, 0.8, 0.8, 1},
	border_radius = [4]f32{6, 6, 6, 6},
	bg_color      = Color{1, 1, 1, 1},
	overflow_y    = .HIDDEN,
}

DEFAULT_ACCORDION_HEADER_STYLE :: Style {
	direction       = .ROW,
	width           = Percent{100},
	padding         = [4]f32{12, 16, 12, 16},
	justify_content = .START,
	align_items     = .CENTER,
	gap             = 12,
	bg_color        = Color{0.96, 0.96, 0.98, 1},
	text_color      = Color{0.1, 0.1, 0.1, 1},
	border_radius   = [4]f32{0, 0, 0, 0},
}

DEFAULT_ACCORDION_ICON_STYLE :: Style {
	width      = Fixed{16},
	height     = Fixed{16},
	object_fit = .CONTAIN,
}

DEFAULT_ACCORDION_CONTENT_STYLE :: Style {
	direction = .COLUMN,
	width     = Percent{100},
	padding   = [4]f32{16, 16, 16, 16},
	gap       = 12,
}

accordion_begin :: proc(
	app: ^App,
	sdl_rend: ^sdl.Renderer,
	title: string,
	is_expanded: ^bool,
	expanded_icon: string = "assets/pictures/icons/down.png",
	collapsed_icon: string = "assets/pictures/icons/play.png",
	wrapper_style: Style = {},
	header_style: Style = {},
	content_style: Style = {},
	icon_style: Style = {},
	salt := "",
	id: string = "",
	loc := #caller_location,
) -> bool {
	ui_ctx := app.ui
	ev_ctx := app.ev
	anim_ctx := app.anim
	root_id := ID(id) if id != "" else ID(loc, salt)
	header_id := ID(root_id, "header")
	content_id := ID(root_id, "content")

	final_wrapper := merge_styles(DEFAULT_ACCORDION_WRAPPER_STYLE, wrapper_style)
	element_open(ui_ctx, Element{_box = {id = root_id}, style = final_wrapper}, loc)

	register(ev_ctx, header_id, Event_Callbacks{focusable = true, cursor = .HAND})
	if ev_ctx.clicked_this_frame[header_id] or_else false {
		is_expanded^ = !is_expanded^
	}

	final_header := merge_styles(DEFAULT_ACCORDION_HEADER_STYLE, header_style)

	is_hovered := is_tree_hovered(app, header_id)
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

	icon_path := is_expanded^ ? expanded_icon : collapsed_icon
	final_icon := merge_styles(DEFAULT_ACCORDION_ICON_STYLE, icon_style)
	image_path(app, icon_path, user_style = final_icon)

	text_col := final_header.text_color.? or_else Color{0.1, 0.1, 0.1, 1}
	font_sz := final_header.font_size.? or_else 16
	text(app, title, user_style = {text_color = text_col, font_size = font_sz})

	element_close(ui_ctx)

	// --- NEW: FIRE ANIMATION TWEENS ON EXPAND ---
	@(static) prev_exp: map[Box_ID]bool
	if root_id not_in prev_exp do prev_exp[root_id] = is_expanded^
	just_expanded := is_expanded^ && !prev_exp[root_id]
	prev_exp[root_id] = is_expanded^

	if is_expanded^ {
		final_content := merge_styles(DEFAULT_ACCORDION_CONTENT_STYLE, content_style)
		element_open(ui_ctx, Element{_box = {id = content_id}, style = final_content})

		if just_expanded {
			from(
				ui_ctx,
				anim_ctx,
				content_id,
				{opacity = 0.0, y = -10.0, duration = 0.25, ease = ease_out_exp},
			)
		}
		return true
	}

	element_close(ui_ctx)
	return false
}

accordion_end :: proc(app: ^App, is_expanded: bool) {
	if is_expanded {
		element_close(app.ui)
		element_close(app.ui)
	}
}

// --- DATA TABLE ---
DEFAULT_TABLE_WRAPPER_STYLE :: Style {
	direction     = .COLUMN,
	width         = Percent{100},
	height        = Grow{1},
	border        = [4]f32{1, 1, 1, 1},
	border_color  = Color{0.8, 0.8, 0.8, 1},
	border_radius = [4]f32{6, 6, 6, 6},
	bg_color      = Color{1, 1, 1, 1},
	overflow_y    = .HIDDEN,
}

DEFAULT_TABLE_HEADER_ROW_STYLE :: Style {
	direction    = .ROW,
	width        = Percent{100},
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
	width        = Percent{100},
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
	width     = Percent{100},
	height    = Grow{1},
}

table :: proc(
	app: ^App,
	headers: []string,
	rows: [][]string,
	col_widths: []Sizing,
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
	ui_ctx := app.ui
	ev_ctx := app.ev
	root_id := ID(id) if id != "" else ID(loc, salt)
	header_id := ID(root_id, "header")
	body_id := ID(root_id, "body")

	final_wrapper := merge_styles(DEFAULT_TABLE_WRAPPER_STYLE, wrapper_style)
	element_open(ui_ctx, Element{_box = {id = root_id}, style = final_wrapper}, loc)

	final_header_row := merge_styles(DEFAULT_TABLE_HEADER_ROW_STYLE, header_row_style)
	element_open(ui_ctx, Element{_box = {id = header_id}, style = final_header_row})

	final_header_text := merge_styles(DEFAULT_TABLE_HEADER_TEXT_STYLE, header_text_style)
	for h, i in headers {
		element_open(ui_ctx, Element{style = {width = col_widths[i], justify_content = .START}})
		text(app, h, user_style = final_header_text)
		element_close(ui_ctx)
	}
	element_close(ui_ctx)

	final_scroll_style := merge_styles(DEFAULT_TABLE_SCROLL_STYLE, scroll_style)
	scroll_begin(
		app,
		id = body_id,
		scroll_y = true,
		scroll_x = false,
		user_style = final_scroll_style,
	)

	final_cell_text := merge_styles(DEFAULT_TABLE_CELL_TEXT_STYLE, cell_text_style)

	for row, r_idx in rows {
		row_id := ID(body_id, fmt.tprintf("row_%d", r_idx))
		final_row := merge_styles(DEFAULT_TABLE_ROW_STYLE, row_style)

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
			text(app, cell, user_style = final_cell_text)
			element_close(ui_ctx)
		}

		element_close(ui_ctx)
	}

	scroll_end(app, body_id)
	element_close(ui_ctx)
}

// --- LIST VIEW ---
DEFAULT_LIST_WRAPPER_STYLE :: Style {
	direction     = .COLUMN,
	width         = Percent{100},
	height        = Grow{1},
	border        = [4]f32{1, 1, 1, 1},
	border_color  = Color{0.8, 0.8, 0.8, 1},
	border_radius = [4]f32{6, 6, 6, 6},
	bg_color      = Color{1, 1, 1, 1},
	overflow_y    = .HIDDEN,
}

DEFAULT_LIST_SCROLL_STYLE :: Style {
	direction = .COLUMN,
	width     = Percent{100},
	height    = Percent{100},
}

DEFAULT_LIST_ITEM_STYLE :: Style {
	width         = Percent{100},
	padding       = [4]f32{12, 16, 12, 16},
	text_align    = .LEFT,
	border_radius = [4]f32{0, 0, 0, 0},
}

list_view :: proc(
	app: ^App,
	items: []string,
	selected_idx: ^int,
	wrapper_style: Style = {},
	scroll_style: Style = {},
	item_style: Style = {},
	salt := "",
	id: string = "",
	loc := #caller_location,
) -> bool {
	ui_ctx := app.ui
	ev_ctx := app.ev
	changed := false
	root_id := ID(id) if id != "" else ID(loc, salt)
	scroll_id := ID(root_id, "scroll")

	final_wrapper := merge_styles(DEFAULT_LIST_WRAPPER_STYLE, wrapper_style)
	element_open(ui_ctx, Element{_box = {id = root_id}, style = final_wrapper}, loc)

	final_scroll := merge_styles(DEFAULT_LIST_SCROLL_STYLE, scroll_style)
	scroll_begin(app, id = scroll_id, scroll_y = true, scroll_x = false, user_style = final_scroll)

	for item, i in items {
		item_id := ID(scroll_id, fmt.tprintf("item_%d", i))
		is_selected := selected_idx^ == i

		final_item := merge_styles(DEFAULT_LIST_ITEM_STYLE, item_style)

		opt_bg := Color{0.15, 0.4, 0.8, 0.1} if is_selected else Color{0, 0, 0, 0}
		opt_text := Color{0.15, 0.4, 0.8, 1.0} if is_selected else Color{0.3, 0.3, 0.3, 1.0}

		if item_style.bg_color == nil do final_item.bg_color = opt_bg
		if item_style.text_color == nil do final_item.text_color = opt_text

		if button(app, item, id = item_id, user_style = final_item) {
			selected_idx^ = i
			changed = true
		}
	}

	scroll_end(app, scroll_id)
	element_close(ui_ctx)

	return changed
}

// Define the signature that all page procedures must match
Page_Proc :: proc(
	ui_ctx: ^UI_Context,
	ev_ctx: ^Event_Context,
	anim_ctx: ^Context,
	app_state: rawptr,
)

// The state needed to track transitions
Router_State :: struct {
	current_idx:      int,
	target_idx:       int,
	is_transitioning: bool,
}

// The Animated Router Component
router_view :: proc(
	app: ^App,
	router_state: ^Router_State,
	requested_idx: int,
	pages: []Page_Proc,
	app_state: rawptr = nil,
	wrapper_style: Style = {},
	salt := "",
	loc := #caller_location,
) {
	ui_ctx := app.ui
	ev_ctx := app.ev
	anim_ctx := app.anim
	root_id := ID(loc, salt)

	final_wrapper := merge_styles(
		Style {
			direction  = .COLUMN,
			width      = Grow{1},
			height     = Percent{100},
			position   = .RELATIVE,
			overflow_x = .HIDDEN, // Clips the pages as they slide in/out
		},
		wrapper_style,
	)

	// MUST OPEN ELEMENT FIRST! (So the animation engine can find its ID)
	element_open(ui_ctx, Element{_box = {id = root_id}, style = final_wrapper}, loc)

	// Trigger the "Out" animation
	if requested_idx != router_state.target_idx && !router_state.is_transitioning {
		router_state.is_transitioning = true
		router_state.target_idx = requested_idx
		to(
			ui_ctx,
			anim_ctx,
			root_id,
			{opacity = 0.0, x = -20.0, duration = 0.15, ease = ease_linear},
		)
	}

	// Trigger the "In" animation when the fade-out completes
	page_anim := get_state(anim_ctx, root_id)
	if router_state.is_transitioning &&
	   page_anim.opacity <= 0.01 &&
	   router_state.current_idx != router_state.target_idx {
		router_state.current_idx = router_state.target_idx
		router_state.is_transitioning = false

		from(
			ui_ctx,
			anim_ctx,
			root_id,
			{opacity = 0.0, x = 20.0, duration = 0.3, ease = ease_out_exp},
		)
	}

	// Execute the isolated page procedure
	if router_state.current_idx >= 0 && router_state.current_idx < len(pages) {
		pages[router_state.current_idx](ui_ctx, ev_ctx, anim_ctx, app_state)
	}

	element_close(ui_ctx)
}

// --- CAROUSEL ---
DEFAULT_CAROUSEL_WRAPPER :: Style {
	direction   = .COLUMN,
	align_items = .CENTER,
	width       = Fit(true),
	height      = Fit(true),
	position    = .RELATIVE,
}
DEFAULT_CAROUSEL_VIEWPORT :: Style {
	width         = Fixed{600},
	height        = Fixed{400},
	overflow_x    = .HIDDEN,
	overflow_y    = .HIDDEN,
	border_radius = [4]f32{12, 12, 12, 12},
}

carousel_textures :: proc(
	app: ^App,
	images: []^sdl.Texture,
	current_idx: ^int,
	wrapper_style: Style = {},
	viewport_style: Style = {},
	arrow_style: Style = {},
	left_arrow: string = "assets/pictures/icons/left_button.png",
	right_arrow: string = "assets/pictures/icons/right_button.png",
	auto_play: bool = false,
	auto_play_interval: u32 = 3000,
	salt := "",
	loc := #caller_location,
) {
	ui_ctx := app.ui
	ev_ctx := app.ev
	anim_ctx := app.anim
	sdl_rend := app.renderer

	if len(images) == 0 do return

	current_idx^ = current_idx^ % len(images)
	if current_idx^ < 0 do current_idx^ += len(images)

	root_id := ID(loc, salt)
	@(static) last_tick: map[Box_ID]u32
	if auto_play {
		if root_id not_in last_tick do last_tick[root_id] = sdl.GetTicks()

		if !is_tree_hovered(app, root_id) {
			current_tick := sdl.GetTicks()
			if current_tick - last_tick[root_id] > auto_play_interval {
				current_idx^ += 1
				last_tick[root_id] = current_tick
			}
		} else {
			last_tick[root_id] = sdl.GetTicks()
		}
	}
	track_id := ID(root_id, "track")
	arrows_id := ID(root_id, "arrows")
	dots_id := ID(root_id, "dots")

	final_wrapper := merge_styles(DEFAULT_CAROUSEL_WRAPPER, wrapper_style)
	final_wrapper.position = .RELATIVE
	element_open(ui_ctx, Element{_box = {id = root_id}, style = final_wrapper}, loc)

	final_viewport := merge_styles(DEFAULT_CAROUSEL_VIEWPORT, viewport_style)
	element_open(ui_ctx, Element{style = final_viewport})

	// Safely extract fixed dimensions to enforce constraint boundaries
	vp_width: f32 = 600.0
	vp_height: f32 = 400.0
	if w_union, ok := final_viewport.width.?; ok {
		if w_fixed, is_fixed := w_union.(Fixed); is_fixed do vp_width = w_fixed.value
	}
	if h_union, ok := final_viewport.height.?; ok {
		if h_fixed, is_fixed := h_union.(Fixed); is_fixed do vp_height = h_fixed.value
	}

	target_x := -f32(current_idx^) * vp_width

	element_open(
		ui_ctx,
		Element {
			_box = {id = track_id},
			style = {
				direction = .ROW,
				position  = .RELATIVE,
				left      = target_x,
				width     = Fit(true),
				// height = Percent{100},
			},
		},
	)

	@(static) map_init: bool
	@(static) prev_idx: map[Box_ID]int
	if !map_init {
		prev_idx = make(map[Box_ID]int)
		map_init = true
	}

	if track_id not_in prev_idx do prev_idx[track_id] = current_idx^

	if prev_idx[track_id] != current_idx^ {
		old_x := -f32(prev_idx[track_id]) * vp_width
		prev_idx[track_id] = current_idx^
		from(ui_ctx, anim_ctx, track_id, {x = old_x, duration = 0.4, ease = ease_out_exp})
	}

	for tex, i in images {
		slide_style := Style {
			width      = Fixed{vp_width},
			height     = Fixed{vp_height},
			object_fit = .COVER,
		}
		image_texture(app, tex, slide_style, salt = fmt.tprintf("slide_%d", i))
	}
	element_close(ui_ctx) // Track
	element_close(ui_ctx) // Viewport

	is_hovered := is_tree_hovered(app, root_id)
	arrows_state := get_state(anim_ctx, arrows_id)

	@(static) prev_hover: map[Box_ID]bool
	if arrows_id not_in prev_hover {
		prev_hover[arrows_id] = is_hovered
		arrows_state.opacity = is_hovered ? 1.0 : 0.0
	}

	if prev_hover[arrows_id] != is_hovered {
		prev_hover[arrows_id] = is_hovered
		to(ui_ctx, anim_ctx, arrows_id, {opacity = is_hovered ? 1.0 : 0.0, duration = 0.2})
	}

	if is_hovered || arrows_state.opacity > 0.01 {
		element_open(
			ui_ctx,
			Element {
				_box = {id = arrows_id},
				style = {
					position        = .ABSOLUTE,
					top             = 0,
					left            = 0,
					width           = Percent{100},
					height          = Fixed{vp_height}, // Restore this line
					direction       = .ROW,
					justify_content = .SPACE_BETWEEN,
					align_items     = .CENTER,
					padding         = space(0, 16),
				},
			},
		)

		final_arrow_style := merge_styles(
			Style {
				width = Fixed{48},
				height = Fixed{48},
				bg_color = Color{0, 0, 0, 0.4},
				border_radius = space(24),
				padding = space(12),
			},
			arrow_style,
		)

		if image_button(app, left_arrow, user_style = final_arrow_style, salt = "prev") {
			current_idx^ -= 1
			if auto_play do last_tick[root_id] = sdl.GetTicks()
		}

		if image_button(app, right_arrow, user_style = final_arrow_style, salt = "next") {
			current_idx^ += 1
			if auto_play do last_tick[root_id] = sdl.GetTicks()
		}

		element_close(ui_ctx) // Arrows
	}

	element_open(
		ui_ctx,
		Element {
			_box = {id = dots_id},
			style = {
				position = .ABSOLUTE,
				bottom = 16,
				left = 0,
				width = Percent{100},
				height = Fit(true),
				direction = .ROW,
				justify_content = .CENTER,
				align_items = .CENTER,
				gap = 8,
			},
		},
	)

	for _, i in images {
		is_active := current_idx^ == i
		dot_color := is_active ? Color{1, 1, 1, 1} : Color{1, 1, 1, 0.5}
		dot_size: f32 = is_active ? 10.0 : 8.0

		dot_id := ID(dots_id, fmt.tprintf("dot_%d", i))

		if button(
			app,
			"",
			id = dot_id,
			user_style = {
				width = Fixed{dot_size},
				height = Fixed{dot_size},
				bg_color = dot_color,
				border_radius = space(5),
				padding = space(0),
			},
		) {
			current_idx^ = i
		}

		@(static) prev_dot_active: map[Box_ID]bool
		if dot_id not_in prev_dot_active do prev_dot_active[dot_id] = is_active
		if prev_dot_active[dot_id] != is_active {
			prev_dot_active[dot_id] = is_active
			to(
				ui_ctx,
				anim_ctx,
				dot_id,
				{
					bg_color = transmute([4]f32)dot_color,
					width = dot_size,
					height = dot_size,
					duration = 0.2,
					ease = ease_out_exp,
				},
			)
		}
	}
	element_close(ui_ctx) // Dots Overlay
	element_close(ui_ctx) // Wrapper
}

carousel_paths :: proc(
	app: ^App,
	images: []string,
	current_idx: ^int,
	wrapper_style: Style = {},
	viewport_style: Style = {},
	arrow_style: Style = {},
	left_arrow: string = "assets/pictures/icons/left_button.png",
	right_arrow: string = "assets/pictures/icons/right_button.png",
	auto_play: bool = false,
	auto_play_interval: u32 = 3000,
	salt := "",
	loc := #caller_location,
) {
	ui_ctx := app.ui
	ev_ctx := app.ev
	anim_ctx := app.anim
	sdl_rend := app.renderer

	textures := make([dynamic]^sdl.Texture, context.temp_allocator)
	for path in images {
		path_hash := hash.fnv32(transmute([]byte)path)
		tex, exists := ui_ctx.image_cache[path_hash]
		if !exists {
			c_path := fmt.ctprintf("%s", path)
			tex = img.LoadTexture(sdl_rend, c_path)
			if tex == nil do fmt.printfln("ERROR: Failed to load image '%s': %s", path, sdl.GetError())
			ui_ctx.image_cache[path_hash] = tex
		}
		append(&textures, tex)
	}

	carousel_textures(
		app,
		textures[:],
		current_idx,
		wrapper_style,
		viewport_style,
		arrow_style,
		left_arrow,
		right_arrow,
		auto_play,
		auto_play_interval,
		salt,
		loc,
	)
}


// --- COLOR PICKER ---
DEFAULT_COLOR_PICKER_WRAPPER :: Style {
	width       = Fit(true),
	height      = Fit(true),
	direction   = .ROW,
	align_items = .CENTER,
	gap         = 12,
}
DEFAULT_COLOR_PICKER_SWATCH :: Style {
	width         = Fixed{40},
	height        = Fixed{30},
	border_radius = [4]f32{4, 4, 4, 4},
	border        = [4]f32{2, 2, 2, 2},
	border_color  = Color{0.8, 0.8, 0.8, 1},
}

@(private = "file")
hsv_to_rgb :: proc(h, s, v: f32) -> [3]f32 {
	c := v * s
	x := c * (1.0 - math.abs(math.mod_f32(h / 60.0, 2.0) - 1.0))
	m := v - c
	r, g, b: f32
	if h < 60 do r, g, b = c, x, 0
	else if h < 120 do r, g, b = x, c, 0
	else if h < 180 do r, g, b = 0, c, x
	else if h < 240 do r, g, b = 0, x, c
	else if h < 300 do r, g, b = x, 0, c
	else do r, g, b = c, 0, x
	return {r + m, g + m, b + m}
}

@(private = "file")
rgb_to_hsv :: proc(r, g, b: f32) -> [3]f32 {
	max_c := max(r, max(g, b))
	min_c := min(r, min(g, b))
	delta := max_c - min_c
	h, s, v: f32 = 0, 0, max_c

	if max_c > 0 do s = delta / max_c
	else do return {0, 0, 0}

	if delta == 0 do h = 0
	else if max_c == r do h = 60 * math.mod_f32((g - b) / delta, 6)
	else if max_c == g do h = 60 * (((b - r) / delta) + 2)
	else do h = 60 * (((r - g) / delta) + 4)

	if h < 0 do h += 360
	return {h, s, v}
}

color_picker :: proc(
	app: ^App,
	label: string,
	color: ^[4]f32,
	is_open: ^bool,
	wrapper_style: Style = {},
	salt := "",
	loc := #caller_location,
) -> bool {
	ui_ctx := app.ui
	ev_ctx := app.ev
	anim_ctx := app.anim

	changed := false
	root_id := ID(loc, salt)
	swatch_id := ID(root_id, "swatch")

	// Stateful HSV Tracking (Prevents losing Hue when Value is 0 / Black)
	@(static) hsv_states: map[Box_ID][3]f32
	if root_id not_in hsv_states do hsv_states[root_id] = rgb_to_hsv(color[0], color[1], color[2])

	// Detect if color changed externally and sync our internal HSV map
	curr_rgb := hsv_to_rgb(hsv_states[root_id][0], hsv_states[root_id][1], hsv_states[root_id][2])
	if math.abs(color[0] - curr_rgb[0]) > 0.01 ||
	   math.abs(color[1] - curr_rgb[1]) > 0.01 ||
	   math.abs(color[2] - curr_rgb[2]) > 0.01 {
		hsv_states[root_id] = rgb_to_hsv(color[0], color[1], color[2])
	}

	final_wrapper := merge_styles(DEFAULT_COLOR_PICKER_WRAPPER, wrapper_style)
	element_open(ui_ctx, Element{_box = {id = root_id}, style = final_wrapper}, loc)

	text(app, label, user_style = {text_color = Color{0.2, 0.2, 0.2, 1}})

	final_swatch := DEFAULT_COLOR_PICKER_SWATCH
	final_swatch.bg_color = transmute(Color)color^

	register(ev_ctx, swatch_id, Event_Callbacks{focusable = true, cursor = .HAND})
	if ev_ctx.clicked_this_frame[swatch_id] or_else false do is_open^ = !is_open^
	element_open(ui_ctx, Element{_box = {id = swatch_id}, style = final_swatch})
	element_close(ui_ctx)
	element_close(ui_ctx)

	if popover_begin(
		app,
		swatch_id,
		is_open,
		user_style = {width = Fixed{240}, gap = 12},
		salt = salt,
	) {
		defer popover_end(app, true)

		// Allocate Render Data on the layout frame allocator so it survives until render_tree!
		Render_State :: struct {
			h, s, v, a: f32,
		}
		rs := new(Render_State, frame_allocator(ui_ctx.layout))
		rs.h = hsv_states[root_id][0]
		rs.s = hsv_states[root_id][1]
		rs.v = hsv_states[root_id][2]
		rs.a = color[3]

		// --- SV 2D GRADIENT AREA ---
		sv_str := fmt.tprintf("%d_sv_canvas", root_id)
		sv_id := ID(sv_str)
		register(ev_ctx, sv_id, Event_Callbacks{focusable = true, cursor = .HAND})

		if ev_ctx.pressed_id == sv_id {
			if prev, ok := ui_ctx.layout.prev_all_boxes[sv_id]; ok {
				mx, my: i32
				sdl.GetMouseState(&mx, &my)
				lx := clamp(f32(mx) - prev.x, 0.0, prev.computed_width)
				ly := clamp(f32(my) - prev.y, 0.0, prev.computed_height)

				st := &hsv_states[root_id]
				st[1] = lx / prev.computed_width
				st[2] = 1.0 - (ly / prev.computed_height)

				rgb := hsv_to_rgb(st[0], st[1], st[2])
				color[0], color[1], color[2] = rgb[0], rgb[1], rgb[2]
				rs.s, rs.v = st[1], st[2]
				changed = true
			}
		}

		canvas(
			app,
			proc(renderer: ^sdl.Renderer, bounds: sdl.Rect, data: rawptr) {
				rs := (^Render_State)(data)
				step: i32 = 4 // Granularity for performance

				for y := bounds.y; y < bounds.y + bounds.h; y += step {
					v := 1.0 - (f32(y - bounds.y) / f32(bounds.h))
					for x := bounds.x; x < bounds.x + bounds.w; x += step {
						s := f32(x - bounds.x) / f32(bounds.w)
						rgb := hsv_to_rgb(rs.h, s, v)
						sdl.SetRenderDrawColor(
							renderer,
							u8(rgb[0] * 255),
							u8(rgb[1] * 255),
							u8(rgb[2] * 255),
							255,
						)
						rect := sdl.Rect{x, y, step, step}
						sdl.RenderFillRect(renderer, &rect)
					}
				}

				cx := bounds.x + i32(rs.s * f32(bounds.w))
				cy := bounds.y + i32((1.0 - rs.v) * f32(bounds.h))
				sdl.SetRenderDrawColor(renderer, 255, 255, 255, 255)
				ring := sdl.Rect{cx - 4, cy - 4, 8, 8}
				sdl.RenderDrawRect(renderer, &ring)
				sdl.SetRenderDrawColor(renderer, 0, 0, 0, 255)
				ring2 := sdl.Rect{cx - 3, cy - 3, 6, 6}
				sdl.RenderDrawRect(renderer, &ring2)
			},
			data = rs,
			user_style = {width = Percent{100}, height = Fixed{140}, border_radius = space(4)},
			id = sv_str,
		)

		// --- HUE SLIDER ---
		hue_str := fmt.tprintf("%d_hue_canvas", root_id)
		hue_id := ID(hue_str)
		register(ev_ctx, hue_id, Event_Callbacks{focusable = true, cursor = .HAND})

		if ev_ctx.pressed_id == hue_id {
			if prev, ok := ui_ctx.layout.prev_all_boxes[hue_id]; ok {
				mx, my: i32
				sdl.GetMouseState(&mx, &my)
				lx := clamp(f32(mx) - prev.x, 0.0, prev.computed_width)

				st := &hsv_states[root_id]
				st[0] = (lx / prev.computed_width) * 360.0

				rgb := hsv_to_rgb(st[0], st[1], st[2])
				color[0], color[1], color[2] = rgb[0], rgb[1], rgb[2]
				rs.h = st[0]
				changed = true
			}
		}

		canvas(app, proc(renderer: ^sdl.Renderer, bounds: sdl.Rect, data: rawptr) {
				rs := (^Render_State)(data)
				step: i32 = 2
				for x := bounds.x; x < bounds.x + bounds.w; x += step {
					h := (f32(x - bounds.x) / f32(bounds.w)) * 360.0
					rgb := hsv_to_rgb(h, 1.0, 1.0)
					sdl.SetRenderDrawColor(
						renderer,
						u8(rgb[0] * 255),
						u8(rgb[1] * 255),
						u8(rgb[2] * 255),
						255,
					)
					rect := sdl.Rect{x, bounds.y, step, bounds.h}
					sdl.RenderFillRect(renderer, &rect)
				}

				cx := bounds.x + i32((rs.h / 360.0) * f32(bounds.w))
				sdl.SetRenderDrawColor(renderer, 255, 255, 255, 255)
				ring := sdl.Rect{cx - 3, bounds.y - 2, 6, bounds.h + 4}
				sdl.RenderDrawRect(renderer, &ring)
				sdl.SetRenderDrawColor(renderer, 0, 0, 0, 255)
				ring2 := sdl.Rect{cx - 2, bounds.y - 1, 4, bounds.h + 2}
				sdl.RenderDrawRect(renderer, &ring2)
			}, data = rs, user_style = {width = Percent{100}, height = Fixed{16}, border_radius = space(4)}, id = hue_str)

		// --- ALPHA SLIDER ---
		alpha_str := fmt.tprintf("%d_alpha_canvas", root_id)
		alpha_id := ID(alpha_str)
		register(ev_ctx, alpha_id, Event_Callbacks{focusable = true, cursor = .HAND})

		if ev_ctx.pressed_id == alpha_id {
			if prev, ok := ui_ctx.layout.prev_all_boxes[alpha_id]; ok {
				mx, my: i32
				sdl.GetMouseState(&mx, &my)
				lx := clamp(f32(mx) - prev.x, 0.0, prev.computed_width)
				color[3] = lx / prev.computed_width
				rs.a = color[3]
				changed = true
			}
		}

		canvas(
			app,
			proc(renderer: ^sdl.Renderer, bounds: sdl.Rect, data: rawptr) {
				rs := (^Render_State)(data)
				rgb := hsv_to_rgb(rs.h, rs.s, rs.v)
				step: i32 = 2

				for x := bounds.x; x < bounds.x + bounds.w; x += step {
					a := f32(x - bounds.x) / f32(bounds.w)

					// Draw gray to color blend as faux alpha checker
					bg := f32(0.3)
					r := bg * (1.0 - a) + rgb[0] * a
					g := bg * (1.0 - a) + rgb[1] * a
					b := bg * (1.0 - a) + rgb[2] * a

					sdl.SetRenderDrawColor(renderer, u8(r * 255), u8(g * 255), u8(b * 255), 255)
					rect := sdl.Rect{x, bounds.y, step, bounds.h}
					sdl.RenderFillRect(renderer, &rect)
				}

				cx := bounds.x + i32(rs.a * f32(bounds.w))
				sdl.SetRenderDrawColor(renderer, 255, 255, 255, 255)
				ring := sdl.Rect{cx - 3, bounds.y - 2, 6, bounds.h + 4}
				sdl.RenderDrawRect(renderer, &ring)
				sdl.SetRenderDrawColor(renderer, 0, 0, 0, 255)
				ring2 := sdl.Rect{cx - 2, bounds.y - 1, 4, bounds.h + 2}
				sdl.RenderDrawRect(renderer, &ring2)
			},
			data = rs,
			user_style = {width = Percent{100}, height = Fixed{16}, border_radius = space(4)},
			id = alpha_str,
		)
	}
	return changed
}

// --- DATE PICKER ---

DEFAULT_DATE_PICKER_WRAPPER :: Style {
	width         = Fixed{200},
	height        = Fit(true),
	padding       = [4]f32{8, 12, 8, 12},
	border_radius = [4]f32{6, 6, 6, 6},
	border        = [4]f32{1, 1, 1, 1},
	border_color  = Color{0.8, 0.8, 0.8, 1},
	bg_color      = Color{1, 1, 1, 1},
	text_color    = Color{0, 0, 0, 1},
}

// Zeller's congruence adapted for 0 = Sunday
@(private = "file")
day_of_week :: proc(year, month, day: int) -> int {
	y, m := year, month
	if m < 3 {
		m += 12
		y -= 1
	}
	k := y % 100
	j := y / 100
	dow := (day + ((13 * (m + 1)) / 5) + k + (k / 4) + (j / 4) + (5 * j)) % 7
	return (dow + 6) % 7
}

@(private = "file")
days_in_month :: proc(year, month: int) -> int {
	if month == 2 {
		is_leap := (year % 4 == 0 && year % 100 != 0) || (year % 400 == 0)
		return is_leap ? 29 : 28
	}
	if month == 4 || month == 6 || month == 9 || month == 11 do return 30
	return 31
}

date_picker :: proc(
	app: ^App,
	label: string,
	date: ^[3]int, // [YYYY, MM, DD]
	is_open: ^bool,
	wrapper_style: Style = {},
	salt := "",
	loc := #caller_location,
) -> bool {
	ui_ctx := app.ui
	ev_ctx := app.ev
	anim_ctx := app.anim

	changed := false
	root_id := ID(loc, salt)

	// Local view state to navigate months without altering the selected date
	@(static) views: map[Box_ID][2]int
	if root_id not_in views {
		views[root_id] = {date^[0], date^[1]}
		if views[root_id][0] == 0 do views[root_id] = {2026, 1}
	}

	display_text := fmt.tprintf("%d-%02d-%02d", date^[0], date^[1], date^[2])
	if date^[0] == 0 do display_text = label

	final_wrapper := merge_styles(DEFAULT_DATE_PICKER_WRAPPER, wrapper_style)
	if button(app, display_text, user_style = final_wrapper, id = root_id) {
		is_open^ = !is_open^
		if is_open^ && date^[0] != 0 do views[root_id] = {date^[0], date^[1]}
	}

	if popover_begin(
		app,
		root_id,
		is_open,
		user_style = {width = Fixed{300}, padding = space(16), gap = 12},
		salt = salt,
	) {
		defer popover_end(app, true)

		// Take a pointer to the map value to allow direct mutation
		v := &views[root_id]

		// Header
		element_open(
			ui_ctx,
			{
				style = {
					direction = .ROW,
					justify_content = .SPACE_BETWEEN,
					align_items = .CENTER,
					width = Percent{100},
				},
			},
		)
		if button(app, "<", user_style = {padding = space(6, 12)}) {
			v[1] -= 1
			if v[1] < 1 {
				v[1] = 12
				v[0] -= 1
			}
		}
		text(app, fmt.tprintf("%d - %02d", v[0], v[1]), user_style = {font_size = 18})
		if button(app, ">", user_style = {padding = space(6, 12)}) {
			v[1] += 1
			if v[1] > 12 {
				v[1] = 1
				v[0] += 1
			}
		}
		element_close(ui_ctx)

		// Weekdays
		days_of_week := [7]string{"Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"}
		element_open(
			ui_ctx,
			{style = {direction = .ROW, width = Percent{100}, justify_content = .SPACE_BETWEEN}},
		)
		for d in days_of_week {
			text(
				app,
				d,
				user_style = {
					text_color = Color{0.5, 0.5, 0.5, 1},
					width = Fixed{32},
					text_align = .CENTER,
				},
			)
		}
		element_close(ui_ctx)

		// Grid
		v_year, v_month := v[0], v[1]
		days_count := days_in_month(v_year, v_month)
		start_day := day_of_week(v_year, v_month, 1)

		element_open(
			ui_ctx,
			{style = {direction = .ROW, wrap = true, width = Percent{100}, gap = 5}},
		)

		for _ in 0 ..< start_day {
			element_open(ui_ctx, {style = {width = Fixed{32}, height = Fixed{32}}})
			element_close(ui_ctx)
		}

		for d in 1 ..= days_count {
			is_sel := (date^[0] == v_year && date^[1] == v_month && date^[2] == d)
			bg := Color{0.15, 0.4, 0.8, 1} if is_sel else Color{0, 0, 0, 0}
			tc := Color{1, 1, 1, 1} if is_sel else Color{0.1, 0.1, 0.1, 1}

			if button(
				app,
				fmt.tprintf("%d", d),
				user_style = {
					width = Fixed{32},
					height = Fixed{32},
					padding = space(0),
					bg_color = bg,
					text_color = tc,
					border_radius = space(6),
				},
				salt = fmt.tprintf("%s_day_%d", salt, d),
			) {
				date^[0] = v_year
				date^[1] = v_month
				date^[2] = d
				is_open^ = false
				changed = true
			}
		}
		element_close(ui_ctx)
	}
	return changed
}

canvas :: proc(
	app: ^App,
	draw_proc: proc(renderer: ^sdl.Renderer, bounds: sdl.Rect, data: rawptr),
	data: rawptr = nil,
	user_style := Style{},
	salt := "",
	id: string = "",
	loc := #caller_location,
) {
	ui_ctx := app.ui
	// Generate a stable ID based on the caller location or a provided string
	final_id := id != "" ? ID(id) : ID(loc, salt)

	final_style := user_style
	// Default to filling the available layout space if not overridden
	if final_style.width == nil do final_style.width = Percent{100}
	if final_style.height == nil do final_style.height = Percent{100}

	element_open(
		ui_ctx,
		Element {
			_box = {id = final_id},
			style = final_style,
			custom_render = draw_proc,
			custom_render_data = data,
		},
		loc,
	)
	element_close(ui_ctx)
}

debug_panel :: proc(app: ^App) {
	ui_ctx := app.ui
	ev_ctx := app.ev
	anim_ctx := app.anim
	prev_roots := ui_ctx.layout.prev_root_boxes

	// State trackers
	@(static) active_target_id: Box_ID
	@(static) pinned_node_id: Box_ID
	@(static) tree_hover_target: Box_ID
	@(static) tree_click_target: Box_ID
	@(static) prev_mouse_down: bool

	tree_hover_target = 0
	tree_click_target = 0

	// Global mouse click detection for pinning from the main UI
	mouse_state := sdl.GetMouseState(nil, nil)
	is_mouse_down := (mouse_state & sdl.BUTTON_LMASK) != 0
	just_clicked := is_mouse_down && !prev_mouse_down
	prev_mouse_down = is_mouse_down

	debug_panel_id := ID("DEBUG_PANEL_ROOT")
	highlight_id := ID("DEBUG_HIGHLIGHT_OVERLAY")
	info_bar_id := ID("DEBUG_INFO_BAR")

	// Highlight Overlay
	if active_target_id != 0 {
		if target, ok := ui_ctx.layout.prev_all_boxes[active_target_id]; ok {
			element_open(
				ui_ctx,
				Element {
					_box = {id = highlight_id},
					style = {
						position = .FIXED,
						left = target.x,
						top = target.y,
						width = Fixed{target.computed_width},
						height = Fixed{target.computed_height},
						bg_color = Color{0.2, 0.6, 1.0, 0.3},
						border = space(2),
						border_color = Color{0.2, 0.6, 1.0, 1.0},
						z_index = 99998,
					},
				},
			)
			element_close(ui_ctx)
		}
	}

	// Fixed Tree Panel
	element_open(
		ui_ctx,
		Element {
			_box = {id = debug_panel_id},
			style = {
				position     = .FIXED,
				top          = 0,
				right        = 0,
				width        = Fixed{350},
				height       = ViewPercent{100},
				bg_color     = Color{0.1, 0.1, 0.12, 0.95}, // Dark Theme
				border       = space(0, 0, 0, 1),
				border_color = Color{0.25, 0.25, 0.25, 1},
				z_index      = 100000,
				direction    = .COLUMN,
			},
		},
	)
	defer element_close(ui_ctx)

	// Panel Header
	element_open(
		ui_ctx,
		{
			style = {
				padding = space(16),
				border = space(0, 0, 1, 0),
				border_color = Color{0.25, 0.25, 0.25, 1},
				bg_color = Color{0.15, 0.15, 0.18, 1},
			},
		},
	)
	text(app, "Debug Inspector", user_style = {text_color = Color{1, 1, 1, 1}, font_size = 18})
	element_close(ui_ctx)

	// Panel Body (Scrollable Tree)
	scroll_id := scroll_begin(
		app,
		scroll_y = true,
		scroll_x = true,
		user_style = {width = Percent{100}, height = Grow{1}}, // Pushes info bar to bottom
		salt = "debug_tree_scroll",
	)

	for root in prev_roots {
		if root.id == debug_panel_id || root.id == highlight_id || root.id == info_bar_id do continue
		_render_debug_node(app, root, 0, &tree_hover_target, &tree_click_target, pinned_node_id)
	}
	scroll_end(app, scroll_id)

	// --- RESOLVE HOVER AND PIN TARGETS ---
	hover_target := ev_ctx.hovered_id
	is_debug := false
	curr := hover_target
	for curr != 0 {
		if curr == debug_panel_id || curr == highlight_id || curr == info_bar_id {
			is_debug = true
			break
		}
		if prev, ok := ui_ctx.layout.prev_all_boxes[curr]; ok && prev.parent != nil {
			curr = prev.parent.id
		} else {
			break
		}
	}
	if is_debug do hover_target = 0

	if tree_click_target != 0 {
		pinned_node_id = tree_click_target
	} else if just_clicked && hover_target != 0 {
		pinned_node_id = hover_target
	}

	if pinned_node_id != 0 && pinned_node_id not_in ui_ctx.layout.prev_all_boxes {
		pinned_node_id = 0
	}

	if tree_hover_target != 0 {
		active_target_id = tree_hover_target
	} else if hover_target != 0 {
		active_target_id = hover_target
	} else {
		active_target_id = pinned_node_id
	}

	// Information Bar (Docked natively at the bottom of the column!)
	info_scroll_id := scroll_begin(
		app,
		scroll_y = true,
		user_style = {
			width        = Percent{100},
			height       = Fixed{350}, // Fixed vertical slice for the dump pane
			bg_color     = Color{0.1, 0.1, 0.12, 1},
			border       = space(1, 0, 0, 0),
			border_color = Color{0.25, 0.25, 0.25, 1},
			padding      = space(16),
			gap          = 4,
		},
		salt = "debug_info_scroll",
	)

	if active_target_id != 0 {
		if target, ok := ui_ctx.layout.prev_all_boxes[active_target_id]; ok {
			el := (^Element)(target.user_data)
			name := get_debug_name(target.id)
			if name == "UNKNOWN_ID" do name = fmt.tprintf("Box_%d", target.id)

			// -- IDENTITY & BOUNDS --
			text(
				app,
				"IDENTITY & BOUNDS",
				user_style = {
					text_color = Color{0.4, 0.8, 0.4, 1},
					font_size = 14,
					padding = space(0, 0, 4, 0),
				},
				salt = "h_id",
			)
			_debug_kv(app, "Name", name, "kv_name")
			_debug_kv(app, "ID", fmt.tprintf("%d", target.id), "kv_id")
			_debug_kv(
				app,
				"Absolute Pos (X, Y)",
				fmt.tprintf("[%.0f, %.0f]", target.x, target.y),
				"kv_pos",
			)
			_debug_kv(
				app,
				"Computed Size",
				fmt.tprintf("%.0f x %.0f", target.computed_width, target.computed_height),
				"kv_size",
			)

			_debug_divider(app)

			// -- FLEX & LAYOUT --
			text(
				app,
				"FLEX & LAYOUT",
				user_style = {
					text_color = Color{0.4, 0.8, 0.4, 1},
					font_size = 14,
					padding = space(0, 0, 4, 0),
				},
				salt = "h_flex",
			)
			_debug_kv(app, "Direction", fmt.tprintf("%v", target.direction), "kv_dir")
			_debug_kv(app, "Width", fmt.tprintf("%v", target.width), "kv_w")
			_debug_kv(app, "Height", fmt.tprintf("%v", target.height), "kv_h")
			_debug_kv(app, "Justify Content", fmt.tprintf("%v", target.justify_content), "kv_just")
			_debug_kv(app, "Align Items", fmt.tprintf("%v", target.align_items), "kv_align")
			_debug_kv(app, "Flex Wrap", fmt.tprintf("%v", target.wrap), "kv_wrap")
			_debug_kv(app, "Basis", fmt.tprintf("%.0f", target.basis), "kv_bas")

			_debug_divider(app)

			// -- BOX MODEL --
			text(
				app,
				"BOX MODEL",
				user_style = {
					text_color = Color{0.4, 0.8, 0.4, 1},
					font_size = 14,
					padding = space(0, 0, 4, 0),
				},
				salt = "h_box",
			)
			_debug_kv(app, "Padding", fmt.tprintf("%v", target.padding), "kv_pad")
			_debug_kv(app, "Margin", fmt.tprintf("%v", target.margin), "kv_mar")
			_debug_kv(app, "Border", fmt.tprintf("%v", target.border), "kv_bor")
			_debug_kv(app, "Gap", fmt.tprintf("%.0f", target.gap), "kv_gap")
			_debug_kv(
				app,
				"Overflow (X / Y)",
				fmt.tprintf("%v / %v", target.overflow_x, target.overflow_y),
				"kv_over",
			)

			_debug_divider(app)

			// -- POSITIONING --
			text(
				app,
				"POSITIONING",
				user_style = {
					text_color = Color{0.4, 0.8, 0.4, 1},
					font_size = 14,
					padding = space(0, 0, 4, 0),
				},
				salt = "h_pos",
			)
			_debug_kv(app, "Type", fmt.tprintf("%v", target.position), "kv_postype")
			_debug_kv(app, "Z-Index", fmt.tprintf("%d", target.z_index), "kv_z")
			_debug_kv(
				app,
				"Top / Bottom",
				fmt.tprintf("%v / %v", target.top, target.bottom),
				"kv_tb",
			)
			_debug_kv(
				app,
				"Left / Right",
				fmt.tprintf("%v / %v", target.left, target.right),
				"kv_lr",
			)

			if el != nil {
				_debug_divider(app)

				// -- VISUALS & TEXT --
				text(
					app,
					"VISUALS & TEXT",
					user_style = {
						text_color = Color{0.4, 0.8, 0.4, 1},
						font_size = 14,
						padding = space(0, 0, 4, 0),
					},
					salt = "h_vis",
				)

				c_bg := el.resolved_bg_color
				_debug_kv(
					app,
					"Bg Color",
					fmt.tprintf("[%.2f, %.2f, %.2f, %.2f]", c_bg[0], c_bg[1], c_bg[2], c_bg[3]),
					"kv_bg",
				)

				c_bd := el.resolved_border_color
				_debug_kv(
					app,
					"Border Color",
					fmt.tprintf("[%.2f, %.2f, %.2f, %.2f]", c_bd[0], c_bd[1], c_bd[2], c_bd[3]),
					"kv_bdc",
				)

				_debug_kv(
					app,
					"Border Radius",
					fmt.tprintf("%v", el.resolved_border_radius),
					"kv_rad",
				)
				_debug_kv(app, "Opacity", fmt.tprintf("%.2f", el.resolved_opacity), "kv_op")
				_debug_kv(app, "Object Fit", fmt.tprintf("%v", el.resolved_object_fit), "kv_objf")

				c_tx := el.resolved_text_color
				_debug_kv(
					app,
					"Text Color",
					fmt.tprintf("[%.2f, %.2f, %.2f, %.2f]", c_tx[0], c_tx[1], c_tx[2], c_tx[3]),
					"kv_txc",
				)
				_debug_kv(app, "Font Size", fmt.tprintf("%.1f", el.resolved_font_size), "kv_fs")
				_debug_kv(app, "Text Wrap", fmt.tprintf("%v", el.resolved_text_wrap), "kv_tw")
				_debug_kv(app, "Text Align", fmt.tprintf("%v", el.resolved_text_align), "kv_ta")
			}
		}
	} else {
		element_open(
			ui_ctx,
			{style = {height = Grow{1}, justify_content = .CENTER, align_items = .CENTER}},
		)
		text(
			app,
			"Hover or click an element\nto inspect.",
			user_style = {
				text_color = Color{0.4, 0.4, 0.4, 1},
				font_size = 14,
				text_align = .CENTER,
			},
			salt = "info_empty",
		)
		element_close(ui_ctx)
	}

	scroll_end(app, info_scroll_id)
}

@(private = "file")
_render_debug_node :: proc(
	app: ^App,
	box: ^Box,
	depth: f32,
	hovered_target: ^Box_ID,
	clicked_target: ^Box_ID,
	pinned_id: Box_ID,
) {
	ui_ctx := app.ui
	ev_ctx := app.ev
	anim_ctx := app.anim
	if box == nil do return

	name := get_debug_name(box.id)
	if name == "UNKNOWN_ID" do name = fmt.tprintf("Box_%d", box.id)

	row_id := ID(box.id, "debug_row")
	has_children := len(box.children) > 0

	@(static) expanded_nodes: map[Box_ID]bool
	if box.id not_in expanded_nodes do expanded_nodes[box.id] = false

	is_hovered := is_tree_hovered(app, row_id)
	if is_hovered do hovered_target^ = box.id

	register(ev_ctx, row_id, Event_Callbacks{focusable = true, cursor = .HAND})
	if ev_ctx.clicked_this_frame[row_id] or_else false {
		expanded_nodes[box.id] = !expanded_nodes[box.id]
		clicked_target^ = box.id
	}

	is_pinned := box.id == pinned_id
	row_bg := Color{0, 0, 0, 0}
	if is_hovered {
		row_bg = Color{0.2, 0.4, 0.8, 0.5}
	} else if is_pinned {
		row_bg = Color{0.2, 0.5, 0.9, 0.25}
	}

	element_open(
		ui_ctx,
		Element {
			_box = {id = row_id},
			style = {
				direction = .COLUMN,
				width = Percent{100},
				padding = space(6, 8, 6, 8 + (depth * 16.0)),
				bg_color = row_bg,
				border = space(0, 0, 1, 0),
				border_color = Color{1, 1, 1, 0.05},
				gap = 2,
			},
		},
	)

	prefix := has_children ? (expanded_nodes[box.id] ? "v " : "> ") : "- "
	t_color := has_children ? Color{0.9, 0.9, 0.9, 1} : Color{0.5, 0.7, 1.0, 1}

	text(
		app,
		fmt.tprintf("%s%s", prefix, name),
		user_style = {text_color = t_color, font_size = 14},
		salt = fmt.tprintf("debug_name_%d", box.id),
	)

	stats := fmt.tprintf(
		"%.0f x %.0f  @  [%.0f, %.0f]",
		box.computed_width,
		box.computed_height,
		box.x,
		box.y,
	)
	text(
		app,
		stats,
		user_style = {
			text_color = Color{0.5, 0.5, 0.5, 1},
			font_size = 12,
			padding = space(0, 0, 0, 14),
		},
		salt = fmt.tprintf("debug_stats_%d", box.id),
	)

	element_close(ui_ctx)

	if has_children && expanded_nodes[box.id] {
		for child in box.children {
			_render_debug_node(app, child, depth + 1, hovered_target, clicked_target, pinned_id)
		}
	}
}

@(private = "file")
_debug_kv :: proc(app: ^App, label: string, val: string, salt: string) {
	ui_ctx := app.ui
	ev_ctx := app.ev
	element_open(
		ui_ctx,
		Element {
			style = {
				direction = .ROW,
				justify_content = .SPACE_BETWEEN,
				width = Percent{100},
				gap = 16,
			},
		},
	)
	text(
		app,
		label,
		user_style = {text_color = Color{0.6, 0.6, 0.6, 1}, font_size = 12, width = Shrink{1}},
		salt = fmt.tprintf("%s_lbl", salt),
	)
	text(
		app,
		val,
		user_style = {
			text_color = Color{0.8, 0.8, 0.8, 1},
			font_size = 12,
			text_align = .RIGHT,
			width = Grow{1},
		},
		salt = fmt.tprintf("%s_val", salt),
	)
	element_close(ui_ctx)
}

@(private = "file")
_debug_divider :: proc(app: ^App) {
	element_open(
		app.ui,
		{
			style = {
				width = Percent{100},
				height = Fixed{1},
				bg_color = Color{0.25, 0.25, 0.25, 1},
				margin = space(8, 0),
			},
		},
	)
	element_close(app.ui)
}

DEFAULT_TEXTAREA_WRAPPER_STYLE :: Style {
	width         = Percent{100},
	height        = Fixed{150},
	padding       = [4]f32{8, 8, 8, 8},
	border_radius = [4]f32{6, 6, 6, 6},
	border        = [4]f32{2, 2, 2, 2},
	border_color  = Color{0.8, 0.8, 0.8, 1},
	bg_color      = Color{1, 1, 1, 1},
}

DEFAULT_TEXTAREA_TEXT_STYLE :: Style {
	width      = Percent{100},
	height     = Fit(true),
	font_size  = 18,
	text_wrap  = .WORD,
	text_align = .LEFT,
	text_color = Color{0.1, 0.1, 0.1, 1},
}

@(private = "file")
Textarea_State :: struct {
	ev_ctx: ^Event_Context,
	ui_ctx: ^UI_Context,
}

@(private = "file")
_textarea_text_input_cb :: proc(e: ^UI_Event, data: rawptr) {
	state := (^Textarea_State)(data)
	ev_ctx := state.ev_ctx
	if ev_ctx.focused_gap_buffer == nil do return

	gb := ev_ctx.focused_gap_buffer
	gap_buffer_delete_selection(gb)
	gap_buffer_insert_string(gb, e.text)
}


@(private = "file")
_textarea_key_down_cb :: proc(e: ^UI_Event, data: rawptr) {
	state := (^Textarea_State)(data)
	ev_ctx := state.ev_ctx
	ui_ctx := state.ui_ctx

	gb := ev_ctx.focused_gap_buffer

	has_shift := (transmute(u16)e.key_mod & 0x0003) != 0
	has_ctrl := (transmute(u16)e.key_mod & 0x00C0) != 0

	#partial switch e.keycode {
	case .a:
		if has_ctrl { 	// Select All
			gb.anchor = 0
			gap_buffer_move_cursor(gb, gap_buffer_length(gb), true)
		}
	case .c:
		if has_ctrl && gap_buffer_has_selection(gb) { 	// Copy
			start_idx := min(gb.gap_start, gb.anchor)
			end_idx := max(gb.gap_start, gb.anchor)

			// We allocate the C-String on the temp allocator to pass to the OS
			clipboard_str := gap_buffer_get_substring(gb, start_idx, end_idx)
			clipboard_cstr := fmt.ctprintf("%s", clipboard_str)
			sdl.SetClipboardText(clipboard_cstr)
		}
	case .x:
		if has_ctrl && gap_buffer_has_selection(gb) { 	// Cut
			start_idx := min(gb.gap_start, gb.anchor)
			end_idx := max(gb.gap_start, gb.anchor)

			clipboard_str := gap_buffer_get_substring(gb, start_idx, end_idx)
			clipboard_cstr := fmt.ctprintf("%s", clipboard_str)
			sdl.SetClipboardText(clipboard_cstr)

			gap_buffer_delete_selection(gb)
		}
	case .v:
		if has_ctrl && sdl.HasClipboardText() { 	// Paste
			clipboard_cstr := sdl.GetClipboardText()
			if clipboard_cstr != nil {
				defer sdl.free(rawptr(clipboard_cstr))
				pasted_str := string(clipboard_cstr)

				// Strip carriage returns if present from Windows clipboards
				clean_str, _ := strings.replace_all(pasted_str, "\r", "", context.temp_allocator)

				gap_buffer_delete_selection(gb)
				gap_buffer_insert_string(gb, clean_str)
			}
		}
	case .ESCAPE:
		if gap_buffer_has_selection(gb) {
			gb.anchor = gb.gap_start // Clear selection
		}
	case .LEFT:
		if has_shift {
			gap_buffer_move_left(gb, true)
		} else {
			if gap_buffer_has_selection(gb) {
				gap_buffer_move_cursor(gb, min(gb.gap_start, gb.anchor), false)
			} else {
				gap_buffer_move_left(gb, false)
			}
		}
	case .RIGHT:
		if has_shift {
			gap_buffer_move_right(gb, true)
		} else {
			if gap_buffer_has_selection(gb) {
				gap_buffer_move_cursor(gb, max(gb.gap_start, gb.anchor), false)
			} else {
				gap_buffer_move_right(gb, false)
			}
		}
	case .UP, .DOWN:
		box, has_box := ui_ctx.layout.prev_all_boxes[e.current_target]
		if has_box && box.user_data != nil {
			el := (^Element)(box.user_data)
			font := el.resolved_font
			text := gap_buffer_to_string(gb, context.temp_allocator)

			// Reconstruct the inner width bounds
			viewport_width :=
				box.computed_width -
				box.padding[1] -
				box.padding[3] -
				box.border[1] -
				box.border[3]
			if viewport_width <= 0 do viewport_width = 1000.0

			curr_x, curr_y := calc_textarea_cursor_pos(font, text, gb.gap_start, viewport_width)
			line_height := f32(ttf.FontHeight(font))

			target_y := e.keycode == .UP ? curr_y - line_height : curr_y + line_height
			target_idx := calc_textarea_cursor_idx(font, text, curr_x, target_y, viewport_width)

			gap_buffer_move_cursor(gb, target_idx, has_shift)
		} else {
			// Fallbacks in case the layout engine hasn't processed the box yet
			if e.keycode == .UP do gap_buffer_move_up(gb, has_shift)
			else do gap_buffer_move_down(gb, has_shift)
		}
	case .BACKSPACE:
		if !gap_buffer_delete_selection(gb) {
			gap_buffer_backspace(gb)
		}
	case .DELETE:
		if !gap_buffer_delete_selection(gb) {
			gap_buffer_delete(gb)
		}
	case .RETURN, .KP_ENTER:
		gap_buffer_delete_selection(gb)
		gap_buffer_insert_rune(gb, '\n')
	case .HOME:
		gap_buffer_move_cursor(gb, 0, has_shift)
	case .END:
		gap_buffer_move_cursor(gb, gap_buffer_length(gb), has_shift)
	}
}

@(private = "file")
calc_textarea_cursor_pos :: proc(
	font: ^ttf.Font,
	text: string,
	cursor_byte_idx: int,
	max_width: f32,
) -> (
	x, y: f32,
) {
	if font == nil do return 0, 0
	if cursor_byte_idx <= 0 do return 0.0, 0.0

	line_height := f32(ttf.FontHeight(font))
	space_w, space_h: i32
	ttf.SizeUTF8(font, " ", &space_w, &space_h)
	space_width := f32(space_w)

	current_x: f32 = 0.0
	current_y: f32 = 0.0
	byte_tracker := 0

	explicit_lines := strings.split(text, "\n", context.temp_allocator)

	for explicit_line, l_idx in explicit_lines {
		words := strings.split(explicit_line, " ", context.temp_allocator)
		start_idx := 0

		for start_idx < len(words) {
			end_idx := start_idx
			line_width: f32 = 0.0

			// Simulate word wrap to find how many words fit on this line
			for end_idx < len(words) {
				word_width: f32 = 0.0
				if len(words[end_idx]) > 0 {
					c_word := fmt.ctprintf("%s", words[end_idx])
					w, h: i32
					ttf.SizeUTF8(font, c_word, &w, &h)
					word_width = f32(w)
				}
				if end_idx > start_idx && line_width + word_width > max_width {
					break
				}
				line_width += word_width + space_width
				end_idx += 1
			}

			// Traverse the words on this specific wrapped line
			for i in start_idx ..< end_idx {
				word_bytes := len(words[i])

				// Does the cursor fall inside this word?
				if cursor_byte_idx >= byte_tracker &&
				   cursor_byte_idx <= byte_tracker + word_bytes {
					local_byte_offset := cursor_byte_idx - byte_tracker
					sub_str := words[i][:local_byte_offset]

					w: i32 = 0
					if len(sub_str) > 0 do ttf.SizeUTF8(font, fmt.ctprintf("%s", sub_str), &w, nil)
					return current_x + f32(w), current_y
				}

				w: i32 = 0
				if word_bytes > 0 do ttf.SizeUTF8(font, fmt.ctprintf("%s", words[i]), &w, nil)

				current_x += f32(w)
				byte_tracker += word_bytes

				// Apply space separator if it's not the last word of the explicit line
				if i < len(words) - 1 {
					if cursor_byte_idx == byte_tracker {
						return current_x, current_y
					}
					current_x += space_width
					byte_tracker += 1 // 1 byte for ' '
				}
			}

			current_y += line_height
			current_x = 0.0
			start_idx = end_idx
		}

		// Apply newline separator if it's not the last explicit line
		if l_idx < len(explicit_lines) - 1 {
			if cursor_byte_idx == byte_tracker {
				return current_x, current_y
			}
			byte_tracker += 1 // 1 byte for '\n'
		}
	}

	return current_x, current_y
}

@(private = "file")
calc_textarea_cursor_idx :: proc(
	font: ^ttf.Font,
	text: string,
	target_x, target_y: f32,
	max_width: f32,
) -> int {
	if font == nil || len(text) == 0 do return 0
	if target_y < 0 do return 0 // Above the first line

	line_height := f32(ttf.FontHeight(font))
	space_w, space_h: i32
	ttf.SizeUTF8(font, " ", &space_w, &space_h)
	space_width := f32(space_w)

	current_y: f32 = 0.0
	byte_tracker := 0

	explicit_lines := strings.split(text, "\n", context.temp_allocator)

	for explicit_line, l_idx in explicit_lines {
		words := strings.split(explicit_line, " ", context.temp_allocator)
		start_idx := 0

		for start_idx < len(words) {
			end_idx := start_idx
			line_width: f32 = 0.0

			// Determine visual line boundaries
			for end_idx < len(words) {
				word_width: f32 = 0.0
				if len(words[end_idx]) > 0 {
					c_word := fmt.ctprintf("%s", words[end_idx])
					w, h: i32
					ttf.SizeUTF8(font, c_word, &w, &h)
					word_width = f32(w)
				}
				if end_idx > start_idx && line_width + word_width > max_width {
					break
				}
				line_width += word_width + space_width
				end_idx += 1
			}

			// Map X position if target_y falls inside this visual line
			if target_y >= current_y && target_y < current_y + line_height {
				current_x: f32 = 0.0
				best_dist: f32 = 999999.0
				best_idx: int = byte_tracker

				for i in start_idx ..< end_idx {
					word_bytes := len(words[i])

					for char_idx in 0 ..= word_bytes {
						sub_str := words[i][:char_idx]
						w: i32 = 0
						if len(sub_str) > 0 do ttf.SizeUTF8(font, fmt.ctprintf("%s", sub_str), &w, nil)

						char_x := current_x + f32(w)
						dist := math.abs(char_x - target_x)
						if dist < best_dist {
							best_dist = dist
							best_idx = byte_tracker + char_idx
						}
					}

					w: i32 = 0
					if word_bytes > 0 do ttf.SizeUTF8(font, fmt.ctprintf("%s", words[i]), &w, nil)
					current_x += f32(w)
					byte_tracker += word_bytes

					if i < len(words) - 1 {
						dist := math.abs(current_x - target_x)
						if dist < best_dist {
							best_dist = dist
							best_idx = byte_tracker
						}
						current_x += space_width
						byte_tracker += 1
					}
				}

				// Check trailing line space
				if math.abs(current_x - target_x) < best_dist {
					best_idx = byte_tracker
				}
				return best_idx
			}

			// Advance trackers if we haven't found the line yet
			for i in start_idx ..< end_idx {
				byte_tracker += len(words[i])
				if i < len(words) - 1 do byte_tracker += 1
			}

			current_y += line_height
			start_idx = end_idx
		}

		if l_idx < len(explicit_lines) - 1 {
			byte_tracker += 1 // Account for explicit '\n'
		}
	}

	return len(text) // Below the last line
}


textarea :: proc(
	app: ^App,
	buffer: ^Gap_Buffer,
	placeholder := "",
	wrapper_style: Style = DEFAULT_TEXTAREA_WRAPPER_STYLE,
	text_style: Style = DEFAULT_TEXTAREA_TEXT_STYLE,
	focused_border_color: Color = {0.15, 0.4, 0.8, 1},
	salt := "",
	id: string = "",
	loc := #caller_location,
) -> bool {
	ui_ctx := app.ui
	ev_ctx := app.ev
	root_id := ID(id) if id != "" else ID(loc, salt)
	string_id := ID(root_id, "text")

	state := new(Textarea_State, frame_allocator(ui_ctx.layout))
	state.ev_ctx = ev_ctx
	state.ui_ctx = ui_ctx

	register(
		ev_ctx,
		root_id,
		Event_Callbacks {
			cursor = .IBEAM,
			focusable = true,
			user_data = state,
			on_text_input = _textarea_text_input_cb,
			on_key_down = _textarea_key_down_cb,
		},
	)

	is_focused := ev_ctx.focused_id == root_id

	if is_focused {
		sdl.StartTextInput()
		ev_ctx.focused_gap_buffer = buffer

		if root_id not_in ev_ctx.cursor_blink_start {
			ev_ctx.cursor_blink_start[root_id] = u64(sdl.GetTicks())
		}
	} else if ev_ctx.focused_gap_buffer == buffer {
		sdl.StopTextInput()
		ev_ctx.focused_gap_buffer = nil
	}

	// Generate text for rendering
	display_text := gap_buffer_to_string(buffer, context.temp_allocator)
	if len(display_text) == 0 do display_text = placeholder

	// Resolve Fonts
	final_text := merge_styles(DEFAULT_TEXTAREA_TEXT_STYLE, text_style)

	parent_font_name := ""
	parent_font_size: f32 = 16.0
	if len(ui_ctx.layout.parent_stack) > 0 {
		parent_box := ui_ctx.layout.parent_stack[len(ui_ctx.layout.parent_stack) - 1]
		if parent_box.user_data != nil {
			parent_el := (^Element)(parent_box.user_data)
			parent_font_name = parent_el.resolved_font_name
			parent_font_size = parent_el.resolved_font_size
		}
	}

	font_path := final_text.font_name.? or_else parent_font_name
	font_size := final_text.font_size.? or_else parent_font_size
	active_font := get_font(ui_ctx, font_path, font_size)

  is_pressed := ev_ctx.pressed_id == root_id
	was_pressed := ev_ctx.prev_pressed_id == root_id
	just_pressed := is_pressed && !was_pressed
	is_dragging := is_pressed && was_pressed

	if is_pressed {
		if prev_outer, ok := ui_ctx.layout.prev_all_boxes[root_id]; ok {
			mx, my: i32
			sdl.GetMouseState(&mx, &my)

			// Convert global mouse coordinates to local scrolled space
			scroll_x := ev_ctx.scroll_offsets_x[root_id]
			scroll_y := ev_ctx.scroll_offsets_y[root_id]
			
			local_x := f32(mx) - prev_outer.x - prev_outer.border[3] - prev_outer.padding[3] + scroll_x
			local_y := f32(my) - prev_outer.y - prev_outer.border[0] - prev_outer.padding[0] + scroll_y

			// Determine inner viewport width for text wrapping bounds
			viewport_width := prev_outer.computed_width - get_horizontal(prev_outer.padding) - get_horizontal(prev_outer.border)
			if viewport_width <= 0 do viewport_width = 1000.0

			// Find the visual index
			best_cursor := calc_textarea_cursor_idx(active_font, display_text, local_x, local_y, viewport_width)

			// Update the gap buffer (keep_anchor = true if dragging to create a selection)
			gap_buffer_move_cursor(buffer, best_cursor, is_dragging)

			// Reset blink timer so the caret stays solid while clicking/dragging
			if just_pressed || ev_ctx.cursor_last_position[root_id] != best_cursor {
				ev_ctx.cursor_blink_start[root_id] = u64(sdl.GetTicks())
				ev_ctx.cursor_last_position[root_id] = best_cursor
			}
		}
	}

	// Resolve Wrap and Styles
	final_wrapper := merge_styles(DEFAULT_TEXTAREA_WRAPPER_STYLE, wrapper_style)
	if is_focused do final_wrapper.border_color = focused_border_color

	if is_focused && buffer.anchor != buffer.gap_start {
		final_text.selection_start = buffer.anchor
		final_text.selection_end = buffer.gap_start
		final_text.selection_color = Color{0.2, 0.5, 0.9, 0.4}
	}

	scroll_begin(
		app,
		id = root_id,
		scroll_y = true,
		scroll_x = false,
		user_style = final_wrapper,
		loc = loc,
	)

	// Cursor Pos & Scroll Handling
	cursor_x, cursor_y: f32 = 0.0, 0.0
	cursor_visible := false

	if is_focused {
		elapsed := u64(sdl.GetTicks()) - ev_ctx.cursor_blink_start[root_id]
		cursor_visible = (elapsed % 1000) < 500

		viewport_width: f32 = 1000.0 // Default wide fallback
		if prev_outer, ok := ui_ctx.layout.prev_all_boxes[root_id]; ok {
			viewport_width =
				prev_outer.computed_width -
				get_horizontal(prev_outer.padding) -
				get_horizontal(prev_outer.border)
		}

		cursor_x, cursor_y = calc_textarea_cursor_pos(
			active_font,
			display_text,
			buffer.gap_start,
			viewport_width,
		)

		// Auto-scroll
		if prev_outer, ok := ui_ctx.layout.prev_all_boxes[root_id]; ok {
			scroll_y := ev_ctx.scroll_offsets_y[root_id]
			viewport_height :=
				prev_outer.computed_height -
				get_vertical(prev_outer.padding) -
				get_vertical(prev_outer.border)

			margin: f32 = 10.0
			line_height := f32(ttf.FontHeight(active_font))

			if cursor_y < scroll_y + margin {
				ev_ctx.scroll_offsets_y[root_id] = max(cursor_y - margin, 0)
			} else if cursor_y + line_height > scroll_y + viewport_height - margin {
				ev_ctx.scroll_offsets_y[root_id] =
					cursor_y + line_height - viewport_height + margin
			}
		}
	}

	// Draw the text
	element_open(
		ui_ctx,
		Element {
			_box = {id = string_id},
			text = display_text,
			style = final_text,
			resolved_font = active_font, // Feed the resolved font natively
		},
		loc,
	)
	element_close(ui_ctx)

	// Draw the Caret
	if cursor_visible {
		line_h := f32(ttf.FontHeight(active_font))
		element_open(
			ui_ctx,
			Element {
				style = {
					position = .ABSOLUTE,
					left = cursor_x,
					top = cursor_y,
					width = Fixed{2},
					height = Fixed{line_h},
					bg_color = Color{0.1, 0.1, 0.1, 1},
				},
			},
			loc,
		)
		element_close(ui_ctx)
	}

	scroll_end(app, root_id)
	return is_focused
}
