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
	hash_input := fmt.tprintf("%s:%d:%s", loc.file_path, loc.line, salt)
	final_id := lc.ID(hash_input)

	events.register(ev_ctx, final_id, events.Event_Callbacks{focusable = true})

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
	width         = lc.Fit(true),
	height        = lc.Fit(true),
}

tooltip_begin :: proc(
	ui_ctx: ^UI_Context,
	ev_ctx: ^events.Event_Context,
	target_id: lc.Box_ID,
	user_style := Style{},
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
) -> lc.Box_ID {
	final_id := id
	if final_id == 0 {
		hash_input := fmt.tprintf("%s:%d:%s", loc.file_path, loc.line, salt)
		final_id = lc.ID(hash_input)
	}

	final_style := user_style
	if scroll_y do final_style.overflow_y = .SCROLL
	if scroll_x do final_style.overflow_x = .SCROLL

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
	return final_id
}

scroll_end :: proc(
	ui_ctx: ^UI_Context,
	ev_ctx: ^events.Event_Context,
	id: lc.Box_ID,
	anim_ctx: ^anim.Context = nil,
) {
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

			sb_id := lc.ID(id, "scrollbar")
			is_hovered := is_tree_hovered(ui_ctx, ev_ctx, id)

			opacity: f32 = is_hovered ? 1.0 : 0.0

			// Safely handle animations only if anim_ctx is provided
			if anim_ctx != nil {
				@(static) prev_hover: map[lc.Box_ID]bool
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
				sb_state := anim.get_state(anim_ctx, sb_id)
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
							width = lc.Fixed{6},
							height = lc.Fixed{thumb_h - 8.0},
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

DEFAULT_SLIDER_WRAPPER_STYLE :: Style {
	width           = lc.Percent{100},
	height          = lc.Fixed{30},
	justify_content = .START,
	align_items     = .CENTER,
}
DEFAULT_SLIDER_TRACK_STYLE :: Style {
	width         = lc.Percent{100},
	height        = lc.Fixed{4},
	bg_color      = Color{0.8, 0.8, 0.8, 0.25},
	border_radius = [4]f32{2, 2, 2, 2},
}

DEFAULT_SLIDER_FILL_STYLE :: Style {
	height        = lc.Percent{100},
	bg_color      = Color{0.9, 0.2, 0.2, 1.0},
	border_radius = [4]f32{2, 2, 2, 2},
}

DEFAULT_SLIDER_THUMB_STYLE :: Style {
	position      = .ABSOLUTE,
	top           = 8.0,
	width         = lc.Fixed{14},
	height        = lc.Fixed{14},
	bg_color      = Color{1, 0, 0, 1},
	border_radius = [4]f32{7, 7, 7, 7},
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
				target_val = new_val
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

	return changed, target_val
}

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
	font_size  = 28,
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
	dummy_box := lc.Box {
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
		ui_ctx,
		ev_ctx,
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
					width = lc.Fixed{end_px - start_px},
					height = lc.Percent{100},
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
					width = lc.Fixed{2},
					height = lc.Fixed{27},
					bg_color = Color{0.1, 0.1, 0.1, 1},
				},
			},
			loc,
		)
		element_close(ui_ctx)
	}

	scroll_end(ui_ctx, ev_ctx, root_id)
	return is_focused
}

image :: proc {
	image_texture,
	image_path,
}

image_texture :: proc(
	ui_ctx: ^UI_Context,
	texture: ^sdl.Texture,
	user_style := Style{},
	salt := "",
	id: lc.Box_ID = 0,
	loc := #caller_location,
) {
	final_id := id
	if final_id == 0 {
		hash_input := fmt.tprintf("%s:%d:%s", loc.file_path, loc.line, salt)
		final_id = lc.ID(hash_input)
	}

	final_style := user_style
	final_style.bg_image = texture

	tex_w, tex_h: i32 = 0, 0
	if texture != nil do sdl.QueryTexture(texture, nil, nil, &tex_w, &tex_h)

	if final_style.width == nil do final_style.width = lc.Fixed{f32(tex_w)}
	if final_style.height == nil do final_style.height = lc.Fixed{f32(tex_h)}

	element_open(ui_ctx, Element{_box = {id = final_id}, style = final_style}, loc)
	element_close(ui_ctx)
}

image_path :: proc(
	ui_ctx: ^UI_Context,
	sdl_rend: ^sdl.Renderer,
	path: string,
	user_style: Style = {},
	salt := "",
	id: lc.Box_ID = 0,
	loc := #caller_location,
) {
	path_hash := hash.fnv32(transmute([]byte)path)
	tex, exists := ui_ctx.image_cache[path_hash]
	if !exists {
		c_path := fmt.ctprintf("%s", path)
		tex = img.LoadTexture(sdl_rend, c_path)
		if tex == nil do fmt.printfln("ERROR: Failed to load image '%s': %s", path, sdl.GetError())
		ui_ctx.image_cache[path_hash] = tex
	}
	image_texture(ui_ctx, tex, user_style, salt, id, loc)
}

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

	if final_style.width == nil do final_style.width = lc.Fixed{28}
	if final_style.height == nil do final_style.height = lc.Fixed{28}
	if final_style.object_fit == nil do final_style.object_fit = .CONTAIN

	element_open(ui_ctx, Element{_box = {id = id}, style = final_style}, loc)
	element_close(ui_ctx)

	return is_clicked
}

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
	hash_input := id
	if id == "" do hash_input = fmt.tprintf("%s:%d:%s", loc.file_path, loc.line, salt)
	root_id := lc.ID(hash_input)

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
			overlay_id := lc.ID(fmt.tprintf("%d_overlay", root_id))
			should_show := is_tree_hovered(ui_ctx, ev_ctx, root_id) || is_scrubbing^

			if should_show != overlay_active^ {
				overlay_active^ = should_show
				anim.to(
					&anim_ctx.engine,
					anim.Tween_Vars {
						duration = 0.35,
						ease_func = anim.ease_out_exp,
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

// NEW: Requires anim_ctx for slide/fade animations
popover_begin :: proc(
	ui_ctx: ^UI_Context,
	ev_ctx: ^events.Event_Context,
	anim_ctx: ^anim.Context,
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

	final_style := merge_styles(DEFAULT_POPOVER_STYLE, user_style)
	final_style.position = .FIXED
	final_style.z_index = 1000

	if final_style.left == nil do final_style.left = target_x
	if final_style.top == nil do final_style.top = target_y + target_h + 8.0

	events.register(ev_ctx, content_id, events.Event_Callbacks{focusable = true})
	element_open(ui_ctx, Element{_box = {id = content_id}, style = final_style}, loc)

	// --- NEW: ANIMATE IN ON FIRST RENDER ---
	@(static) prev_open: map[lc.Box_ID]bool
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
				ease = anim.ease_out_exp,
			},
		)
	}

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

dropdown :: proc(
	ui_ctx: ^UI_Context,
	ev_ctx: ^events.Event_Context,
	anim_ctx: ^anim.Context, // NEW
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

	display_text := label
	if selected_idx^ >= 0 && selected_idx^ < len(options) {
		display_text = options[selected_idx^]
	}

	final_wrapper := merge_styles(DEFAULT_DROPDOWN_STYLE, wrapper_style)

	if button(ui_ctx, ev_ctx, display_text, user_style = final_wrapper, id = root_id) do is_open^ = !is_open^

	final_popover := merge_styles(DEFAULT_DROPDOWN_POPOVER_STYLE, popover_style)

	if popover_begin(
		ui_ctx,
		ev_ctx,
		anim_ctx, // Added Context
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
	width         = lc.Fixed{400},
	height        = lc.Fit(true),
	gap           = 16,
	position      = .RELATIVE, // NEW: Ensures dynamic Y translation offsets work correctly
}

modal_begin :: proc(
	ui_ctx: ^UI_Context,
	ev_ctx: ^events.Event_Context,
	anim_ctx: ^anim.Context, // NEW
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

	events.register(ev_ctx, backdrop_id, events.Event_Callbacks{focusable = true})

	if dismiss_on_click_outside &&
	   ev_ctx.hovered_id == backdrop_id &&
	   (ev_ctx.clicked_this_frame[backdrop_id] or_else false) {
		is_open^ = false
		return false
	}

	final_backdrop := merge_styles(DEFAULT_MODAL_BACKDROP_STYLE, backdrop_style)
	element_open(ui_ctx, Element{_box = {id = backdrop_id}, style = final_backdrop}, loc)

	events.register(ev_ctx, content_id, events.Event_Callbacks{focusable = true})

	final_modal := merge_styles(DEFAULT_MODAL_STYLE, modal_style)
	element_open(ui_ctx, Element{_box = {id = content_id}, style = final_modal}, loc)

	// --- NEW: ANIMATE IN ON FIRST RENDER ---
	@(static) prev_open: map[lc.Box_ID]bool
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
				ease     = anim.ease_out_exp,
			},
		)
	}

	return true
}

modal_end :: proc(ui_ctx: ^UI_Context, is_open: bool) {
	if is_open {
		element_close(ui_ctx)
		element_close(ui_ctx)
	}
}

DEFAULT_CONTEXT_MENU_BACKDROP_STYLE :: Style {
	position = .FIXED,
	top      = 0,
	left     = 0,
	width    = lc.ViewPercent{100},
	height   = lc.ViewPercent{100},
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
	width         = lc.Fit(true),
	height        = lc.Fit(true),
}

context_menu_begin :: proc(
	ui_ctx: ^UI_Context,
	ev_ctx: ^events.Event_Context,
	anim_ctx: ^anim.Context, // NEW
	x, y: f32,
	is_open: ^bool,
	backdrop_style: Style = {},
	user_style: Style = {},
	salt := "",
	loc := #caller_location,
) -> (
	is_active: bool,
	target_id: lc.Box_ID,
) {
	if !is_open^ do return false, 0

	hash_input := fmt.tprintf("%s:%d:%s", loc.file_path, loc.line, salt)
	root_id := lc.ID(hash_input)
	backdrop_id := lc.ID(fmt.tprintf("%d_backdrop", root_id))
	content_id := lc.ID(fmt.tprintf("%d_content", root_id))

	events.register(ev_ctx, backdrop_id, events.Event_Callbacks{focusable = true})
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

	events.register(ev_ctx, content_id, events.Event_Callbacks{focusable = true})
	element_open(ui_ctx, Element{_box = {id = content_id}, style = final_style}, loc)

	// --- NEW: ANIMATE IN ON FIRST RENDER ---
	@(static) prev_open: map[lc.Box_ID]bool
	if root_id not_in prev_open do prev_open[root_id] = false
	just_opened := is_open^ && !prev_open[root_id]
	prev_open[root_id] = is_open^

	if just_opened {
		from(
			ui_ctx,
			anim_ctx,
			content_id,
			{opacity = 0.0, y = y - 10.0, duration = 0.2, ease = anim.ease_out_exp},
		)
	}

	return true, ev_ctx.context_menu_target
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
	border_radius = [4]f32{12, 12, 12, 12},
	border        = [4]f32{2, 2, 2, 2},
	border_color  = Color{0.8, 0.8, 0.8, 1},
}

DEFAULT_SWITCH_THUMB_STYLE :: Style {
	position      = .ABSOLUTE,
	top           = 2,
	width         = lc.Fixed{16},
	height        = lc.Fixed{16},
	border_radius = [4]f32{8, 8, 8, 8},
	bg_color      = Color{1, 1, 1, 1},
}

switch_toggle :: proc(
	ui_ctx: ^UI_Context,
	ev_ctx: ^events.Event_Context,
	anim_ctx: ^anim.Context, // NEW
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
	final_thumb.left = state^ ? 22.0 : 2.0

	element_open(ui_ctx, Element{_box = {id = thumb_id}, style = final_thumb})
	element_close(ui_ctx)
	element_close(ui_ctx)

	final_text := merge_styles(DEFAULT_CHECKBOX_TEXT_STYLE, text_style)
	element_open(ui_ctx, Element{_box = {id = text_id}, text = label, style = final_text})
	element_close(ui_ctx)

	element_close(ui_ctx)

	// --- NEW: FIRE ANIMATION TWEENS ON TOGGLE ---
	@(static) prev_state: map[lc.Box_ID]bool
	if root_id not_in prev_state do prev_state[root_id] = state^
	just_toggled := prev_state[root_id] != state^
	prev_state[root_id] = state^

	if just_toggled {
		to(
			ui_ctx,
			anim_ctx,
			thumb_id,
			{x = state^ ? 22.0 : 2.0, duration = 0.25, ease = anim.ease_out_exp},
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
	anim_ctx: ^anim.Context, // NEW
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
		anim_ctx, // Added
		root_id,
		is_open,
		salt = salt,
		loc = loc,
		user_style = final_popover,
	) {
		defer popover_end(ui_ctx, is_open^)

		for opt, i in options {
			cb_salt := fmt.tprintf("%s_opt_%d", salt, i)
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
	anim_ctx: ^anim.Context, // NEW
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

	search_str := strings.to_lower(string(buffer^[:]), context.temp_allocator)
	final_popover := merge_styles(DEFAULT_COMBOBOX_POPOVER_STYLE, popover_style)

	if popover_begin(
		ui_ctx,
		ev_ctx,
		anim_ctx, // Added Context
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

	final_wrapper.border_color = wrapper_style.border_color.? or_else indicator_color

	if b, ok := final_wrapper.border.?; ok {
		final_wrapper.border = [4]f32{b[0], b[1], b[2], b[3] + 4.0}
	} else {
		final_wrapper.border = [4]f32{1, 1, 1, 5}
	}

	element_open(ui_ctx, Element{_box = {id = root_id}, style = final_wrapper}, loc)

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
	element_close(ui_ctx)

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

	element_close(ui_ctx)
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
	border        = [4]f32{0, 0, 3, 0},
	border_radius = [4]f32{0, 0, 0, 0},
	padding       = [4]f32{12, 16, 12, 16},
	bg_color      = Color{0, 0, 0, 0},
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

	final_wrapper := merge_styles(DEFAULT_TABS_WRAPPER_STYLE, wrapper_style)
	element_open(ui_ctx, Element{_box = {id = root_id}, style = final_wrapper}, loc)

	for label, i in labels {
		tab_id := lc.ID(root_id, fmt.tprintf("tab_%d", i))
		is_active := active_idx^ == i

		final_tab := merge_styles(DEFAULT_TABS_TAB_STYLE, tab_style)

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
	justify_content = .START,
	align_items     = .CENTER,
	gap             = 12,
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
	anim_ctx: ^anim.Context, // NEW
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
	root_id := lc.ID(id) if id != "" else lc.ID(loc, salt)
	header_id := lc.ID(root_id, "header")
	content_id := lc.ID(root_id, "content")

	final_wrapper := merge_styles(DEFAULT_ACCORDION_WRAPPER_STYLE, wrapper_style)
	element_open(ui_ctx, Element{_box = {id = root_id}, style = final_wrapper}, loc)

	events.register(ev_ctx, header_id, events.Event_Callbacks{focusable = true, cursor = .HAND})
	if ev_ctx.clicked_this_frame[header_id] or_else false {
		is_expanded^ = !is_expanded^
	}

	final_header := merge_styles(DEFAULT_ACCORDION_HEADER_STYLE, header_style)

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

	icon_path := is_expanded^ ? expanded_icon : collapsed_icon
	final_icon := merge_styles(DEFAULT_ACCORDION_ICON_STYLE, icon_style)
	image_path(ui_ctx, sdl_rend, icon_path, user_style = final_icon)

	text_col := final_header.text_color.? or_else Color{0.1, 0.1, 0.1, 1}
	font_sz := final_header.font_size.? or_else 16
	text(ui_ctx, ev_ctx, title, user_style = {text_color = text_col, font_size = font_sz})

	element_close(ui_ctx)

	// --- NEW: FIRE ANIMATION TWEENS ON EXPAND ---
	@(static) prev_exp: map[lc.Box_ID]bool
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
				{opacity = 0.0, y = -10.0, duration = 0.25, ease = anim.ease_out_exp},
			)
		}
		return true
	}

	element_close(ui_ctx)
	return false
}

accordion_end :: proc(ui_ctx: ^UI_Context, is_expanded: bool) {
	if is_expanded {
		element_close(ui_ctx)
		element_close(ui_ctx)
	}
}

// --- DATA TABLE ---
DEFAULT_TABLE_WRAPPER_STYLE :: Style {
	direction     = .COLUMN,
	width         = lc.Percent{100},
	height        = lc.Grow{1},
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

	final_header_row := merge_styles(DEFAULT_TABLE_HEADER_ROW_STYLE, header_row_style)
	element_open(ui_ctx, Element{_box = {id = header_id}, style = final_header_row})

	final_header_text := merge_styles(DEFAULT_TABLE_HEADER_TEXT_STYLE, header_text_style)
	for h, i in headers {
		element_open(ui_ctx, Element{style = {width = col_widths[i], justify_content = .START}})
		text(ui_ctx, ev_ctx, h, user_style = final_header_text)
		element_close(ui_ctx)
	}
	element_close(ui_ctx)

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

	scroll_end(ui_ctx, ev_ctx, body_id)
	element_close(ui_ctx)
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

		opt_bg := Color{0.15, 0.4, 0.8, 0.1} if is_selected else Color{0, 0, 0, 0}
		opt_text := Color{0.15, 0.4, 0.8, 1.0} if is_selected else Color{0.3, 0.3, 0.3, 1.0}

		if item_style.bg_color == nil do final_item.bg_color = opt_bg
		if item_style.text_color == nil do final_item.text_color = opt_text

		if button(ui_ctx, ev_ctx, item, id = item_id, user_style = final_item) {
			selected_idx^ = i
			changed = true
		}
	}

	scroll_end(ui_ctx, ev_ctx, scroll_id)
	element_close(ui_ctx)

	return changed
}

// Define the signature that all page procedures must match
Page_Proc :: proc(
	ui_ctx: ^UI_Context,
	ev_ctx: ^events.Event_Context,
	anim_ctx: ^anim.Context,
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
	ui_ctx: ^UI_Context,
	ev_ctx: ^events.Event_Context,
	anim_ctx: ^anim.Context,
	router_state: ^Router_State,
	requested_idx: int,
	pages: []Page_Proc,
	app_state: rawptr = nil,
	wrapper_style: Style = {},
	salt := "",
	loc := #caller_location,
) {
	root_id := lc.ID(loc, salt)

	final_wrapper := merge_styles(
		Style {
			direction  = .COLUMN,
			width      = lc.Grow{1},
			height     = lc.Percent{100},
			position   = .RELATIVE,
			overflow_x = .HIDDEN, // Clips the pages as they slide in/out
		},
		wrapper_style,
	)

	// 1. MUST OPEN ELEMENT FIRST! (So the animation engine can find its ID)
	element_open(ui_ctx, Element{_box = {id = root_id}, style = final_wrapper}, loc)

	// 2. Trigger the "Out" animation
	if requested_idx != router_state.target_idx && !router_state.is_transitioning {
		router_state.is_transitioning = true
		router_state.target_idx = requested_idx
		to(
			ui_ctx,
			anim_ctx,
			root_id,
			{opacity = 0.0, x = -20.0, duration = 0.15, ease = anim.ease_linear},
		)
	}

	// 3. Trigger the "In" animation when the fade-out completes
	page_anim := anim.get_state(anim_ctx, root_id)
	if router_state.is_transitioning &&
	   page_anim.opacity <= 0.01 &&
	   router_state.current_idx != router_state.target_idx {
		router_state.current_idx = router_state.target_idx
		router_state.is_transitioning = false

		from(
			ui_ctx,
			anim_ctx,
			root_id,
			{opacity = 0.0, x = 20.0, duration = 0.3, ease = anim.ease_out_exp},
		)
	}

	// 4. Execute the isolated page procedure
	if router_state.current_idx >= 0 && router_state.current_idx < len(pages) {
		pages[router_state.current_idx](ui_ctx, ev_ctx, anim_ctx, app_state)
	}

	element_close(ui_ctx)
}

// --- CAROUSEL ---
DEFAULT_CAROUSEL_WRAPPER :: Style {
	direction   = .COLUMN,
	align_items = .CENTER,
	width       = lc.Fit(true),
	height      = lc.Fit(true),
	position    = .RELATIVE,
}
DEFAULT_CAROUSEL_VIEWPORT :: Style {
	width         = lc.Fixed{600},
	height        = lc.Fixed{400},
	overflow_x    = .HIDDEN,
	overflow_y    = .HIDDEN,
	border_radius = [4]f32{12, 12, 12, 12},
}

carousel_textures :: proc(
	ui_ctx: ^UI_Context,
	ev_ctx: ^events.Event_Context,
	anim_ctx: ^anim.Context,
	sdl_rend: ^sdl.Renderer,
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
	if len(images) == 0 do return

	current_idx^ = current_idx^ % len(images)
	if current_idx^ < 0 do current_idx^ += len(images)

	root_id := lc.ID(loc, salt)
	@(static) last_tick: map[lc.Box_ID]u32
	if auto_play {
		if root_id not_in last_tick do last_tick[root_id] = sdl.GetTicks()

		if !is_tree_hovered(ui_ctx, ev_ctx, root_id) {
			current_tick := sdl.GetTicks()
			if current_tick - last_tick[root_id] > auto_play_interval {
				current_idx^ += 1
				last_tick[root_id] = current_tick
			}
		} else {
			last_tick[root_id] = sdl.GetTicks()
		}
	}
	track_id := lc.ID(root_id, "track")
	arrows_id := lc.ID(root_id, "arrows")
	dots_id := lc.ID(root_id, "dots")

	final_wrapper := merge_styles(DEFAULT_CAROUSEL_WRAPPER, wrapper_style)
	final_wrapper.position = .RELATIVE
	element_open(ui_ctx, Element{_box = {id = root_id}, style = final_wrapper}, loc)

	final_viewport := merge_styles(DEFAULT_CAROUSEL_VIEWPORT, viewport_style)
	element_open(ui_ctx, Element{style = final_viewport})

	// Safely extract fixed dimensions to enforce constraint boundaries
	vp_width: f32 = 600.0
	vp_height: f32 = 400.0
	if w_union, ok := final_viewport.width.?; ok {
		if w_fixed, is_fixed := w_union.(lc.Fixed); is_fixed do vp_width = w_fixed.value
	}
	if h_union, ok := final_viewport.height.?; ok {
		if h_fixed, is_fixed := h_union.(lc.Fixed); is_fixed do vp_height = h_fixed.value
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
				width     = lc.Fit(true),
				// height = lc.Percent{100},
			},
		},
	)

	@(static) map_init: bool
	@(static) prev_idx: map[lc.Box_ID]int
	if !map_init {
		prev_idx = make(map[lc.Box_ID]int)
		map_init = true
	}

	if track_id not_in prev_idx do prev_idx[track_id] = current_idx^

	if prev_idx[track_id] != current_idx^ {
		old_x := -f32(prev_idx[track_id]) * vp_width
		prev_idx[track_id] = current_idx^
		from(ui_ctx, anim_ctx, track_id, {x = old_x, duration = 0.4, ease = anim.ease_out_exp})
	}

	for tex, i in images {
		slide_style := Style {
			width      = lc.Fixed{vp_width},
			height     = lc.Fixed{vp_height},
			object_fit = .COVER,
		}
		image_texture(ui_ctx, tex, slide_style, salt = fmt.tprintf("slide_%d", i))
	}
	element_close(ui_ctx) // Track
	element_close(ui_ctx) // Viewport

	is_hovered := is_tree_hovered(ui_ctx, ev_ctx, root_id)
	arrows_state := anim.get_state(anim_ctx, arrows_id)

	@(static) prev_hover: map[lc.Box_ID]bool
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
					width           = lc.Percent{100},
					height          = lc.Fixed{vp_height}, // Restore this line
					direction       = .ROW,
					justify_content = .SPACE_BETWEEN,
					align_items     = .CENTER,
					padding         = space(0, 16),
				},
			},
		)

		final_arrow_style := merge_styles(
			Style {
				width = lc.Fixed{48},
				height = lc.Fixed{48},
				bg_color = Color{0, 0, 0, 0.4},
				border_radius = space(24),
				padding = space(12),
			},
			arrow_style,
		)

		if image_button(
			ui_ctx,
			ev_ctx,
			sdl_rend,
			left_arrow,
			user_style = final_arrow_style,
			salt = "prev",
		) {
			current_idx^ -= 1
			if auto_play do last_tick[root_id] = sdl.GetTicks()
		}

		if image_button(
			ui_ctx,
			ev_ctx,
			sdl_rend,
			right_arrow,
			user_style = final_arrow_style,
			salt = "next",
		) {
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
				width = lc.Percent{100},
				height = lc.Fit(true),
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

		dot_id := lc.ID(dots_id, fmt.tprintf("dot_%d", i))

		if button(
			ui_ctx,
			ev_ctx,
			"",
			id = dot_id,
			user_style = {
				width = lc.Fixed{dot_size},
				height = lc.Fixed{dot_size},
				bg_color = dot_color,
				border_radius = space(5),
				padding = space(0),
			},
		) {
			current_idx^ = i
		}

		@(static) prev_dot_active: map[lc.Box_ID]bool
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
					ease = anim.ease_out_exp,
				},
			)
		}
	}
	element_close(ui_ctx) // Dots Overlay
	element_close(ui_ctx) // Wrapper
}

carousel_paths :: proc(
	ui_ctx: ^UI_Context,
	ev_ctx: ^events.Event_Context,
	anim_ctx: ^anim.Context,
	sdl_rend: ^sdl.Renderer,
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
		ui_ctx,
		ev_ctx,
		anim_ctx,
		sdl_rend,
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
	width       = lc.Fit(true),
	height      = lc.Fit(true),
	direction   = .ROW,
	align_items = .CENTER,
	gap         = 12,
}
DEFAULT_COLOR_PICKER_SWATCH :: Style {
	width         = lc.Fixed{40},
	height        = lc.Fixed{30},
	border_radius = [4]f32{4, 4, 4, 4},
	border        = [4]f32{2, 2, 2, 2},
	border_color  = Color{0.8, 0.8, 0.8, 1},
}

@(private)
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

@(private)
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
	ui_ctx: ^UI_Context,
	ev_ctx: ^events.Event_Context,
	anim_ctx: ^anim.Context,
	label: string,
	color: ^[4]f32,
	is_open: ^bool,
	wrapper_style: Style = {},
	salt := "",
	loc := #caller_location,
) -> bool {
	changed := false
	root_id := lc.ID(loc, salt)
	swatch_id := lc.ID(root_id, "swatch")

	// 1. Stateful HSV Tracking (Prevents losing Hue when Value is 0 / Black)
	@(static) hsv_states: map[lc.Box_ID][3]f32
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

	text(ui_ctx, ev_ctx, label, user_style = {text_color = Color{0.2, 0.2, 0.2, 1}})

	final_swatch := DEFAULT_COLOR_PICKER_SWATCH
	final_swatch.bg_color = transmute(Color)color^

	events.register(ev_ctx, swatch_id, events.Event_Callbacks{focusable = true, cursor = .HAND})
	if ev_ctx.clicked_this_frame[swatch_id] or_else false do is_open^ = !is_open^
	element_open(ui_ctx, Element{_box = {id = swatch_id}, style = final_swatch})
	element_close(ui_ctx)
	element_close(ui_ctx)

	if popover_begin(
		ui_ctx,
		ev_ctx,
		anim_ctx,
		swatch_id,
		is_open,
		user_style = {width = lc.Fixed{240}, gap = 12},
		salt = salt,
	) {
		defer popover_end(ui_ctx, true)

		// 2. Allocate Render Data on the layout frame allocator so it survives until render_tree!
		Render_State :: struct {
			h, s, v, a: f32,
		}
		rs := new(Render_State, lc.frame_allocator(ui_ctx.layout))
		rs.h = hsv_states[root_id][0]
		rs.s = hsv_states[root_id][1]
		rs.v = hsv_states[root_id][2]
		rs.a = color[3]

		// --- SV 2D GRADIENT AREA ---
		sv_str := fmt.tprintf("%d_sv_canvas", root_id)
		sv_id := lc.ID(sv_str)
		events.register(ev_ctx, sv_id, events.Event_Callbacks{focusable = true, cursor = .HAND})

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
			ui_ctx,
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
			user_style = {
				width = lc.Percent{100},
				height = lc.Fixed{140},
				border_radius = space(4),
			},
			id = sv_str,
		)

		// --- HUE SLIDER ---
		hue_str := fmt.tprintf("%d_hue_canvas", root_id)
		hue_id := lc.ID(hue_str)
		events.register(ev_ctx, hue_id, events.Event_Callbacks{focusable = true, cursor = .HAND})

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

		canvas(ui_ctx, proc(renderer: ^sdl.Renderer, bounds: sdl.Rect, data: rawptr) {
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
			}, data = rs, user_style = {width = lc.Percent{100}, height = lc.Fixed{16}, border_radius = space(4)}, id = hue_str)

		// --- ALPHA SLIDER ---
		alpha_str := fmt.tprintf("%d_alpha_canvas", root_id)
		alpha_id := lc.ID(alpha_str)
		events.register(ev_ctx, alpha_id, events.Event_Callbacks{focusable = true, cursor = .HAND})

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
			ui_ctx,
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
			user_style = {
				width = lc.Percent{100},
				height = lc.Fixed{16},
				border_radius = space(4),
			},
			id = alpha_str,
		)
	}
	return changed
}

// --- DATE PICKER ---

DEFAULT_DATE_PICKER_WRAPPER :: Style {
	width         = lc.Fixed{200},
	height        = lc.Fit(true),
	padding       = [4]f32{8, 12, 8, 12},
	border_radius = [4]f32{6, 6, 6, 6},
	border        = [4]f32{1, 1, 1, 1},
	border_color  = Color{0.8, 0.8, 0.8, 1},
	bg_color      = Color{1, 1, 1, 1},
	text_color    = Color{0, 0, 0, 1},
}

// Zeller's congruence adapted for 0 = Sunday
@(private)
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

@(private)
days_in_month :: proc(year, month: int) -> int {
	if month == 2 {
		is_leap := (year % 4 == 0 && year % 100 != 0) || (year % 400 == 0)
		return is_leap ? 29 : 28
	}
	if month == 4 || month == 6 || month == 9 || month == 11 do return 30
	return 31
}

date_picker :: proc(
	ui_ctx: ^UI_Context,
	ev_ctx: ^events.Event_Context,
	anim_ctx: ^anim.Context,
	label: string,
	date: ^[3]int, // [YYYY, MM, DD]
	is_open: ^bool,
	wrapper_style: Style = {},
	salt := "",
	loc := #caller_location,
) -> bool {
	changed := false
	root_id := lc.ID(loc, salt)

	// Local view state to navigate months without altering the selected date
	@(static) views: map[lc.Box_ID][2]int
	if root_id not_in views {
		views[root_id] = {date^[0], date^[1]}
		if views[root_id][0] == 0 do views[root_id] = {2026, 1}
	}

	display_text := fmt.tprintf("%d-%02d-%02d", date^[0], date^[1], date^[2])
	if date^[0] == 0 do display_text = label

	final_wrapper := merge_styles(DEFAULT_DATE_PICKER_WRAPPER, wrapper_style)
	if button(ui_ctx, ev_ctx, display_text, user_style = final_wrapper, id = root_id) {
		is_open^ = !is_open^
		if is_open^ && date^[0] != 0 do views[root_id] = {date^[0], date^[1]}
	}

	if popover_begin(
		ui_ctx,
		ev_ctx,
		anim_ctx,
		root_id,
		is_open,
		user_style = {width = lc.Fixed{300}, padding = space(16), gap = 12},
		salt = salt,
	) {
		defer popover_end(ui_ctx, true)

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
					width = lc.Percent{100},
				},
			},
		)
		if button(ui_ctx, ev_ctx, "<", user_style = {padding = space(6, 12)}) {
			v[1] -= 1
			if v[1] < 1 {
				v[1] = 12
				v[0] -= 1
			}
		}
		text(ui_ctx, ev_ctx, fmt.tprintf("%d - %02d", v[0], v[1]), user_style = {font_size = 18})
		if button(ui_ctx, ev_ctx, ">", user_style = {padding = space(6, 12)}) {
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
			{
				style = {
					direction = .ROW,
					width = lc.Percent{100},
					justify_content = .SPACE_BETWEEN,
				},
			},
		)
		for d in days_of_week {
			text(
				ui_ctx,
				ev_ctx,
				d,
				user_style = {
					text_color = Color{0.5, 0.5, 0.5, 1},
					width = lc.Fixed{32},
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
			{style = {direction = .ROW, wrap = true, width = lc.Percent{100}, gap = 5}},
		)

		for _ in 0 ..< start_day {
			element_open(ui_ctx, {style = {width = lc.Fixed{32}, height = lc.Fixed{32}}})
			element_close(ui_ctx)
		}

		for d in 1 ..= days_count {
			is_sel := (date^[0] == v_year && date^[1] == v_month && date^[2] == d)
			bg := Color{0.15, 0.4, 0.8, 1} if is_sel else Color{0, 0, 0, 0}
			tc := Color{1, 1, 1, 1} if is_sel else Color{0.1, 0.1, 0.1, 1}

			if button(
				ui_ctx,
				ev_ctx,
				fmt.tprintf("%d", d),
				user_style = {
					width = lc.Fixed{32},
					height = lc.Fixed{32},
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
	ui_ctx: ^UI_Context,
	draw_proc: proc(renderer: ^sdl.Renderer, bounds: sdl.Rect, data: rawptr),
	data: rawptr = nil,
	user_style := Style{},
	salt := "",
	id: string = "",
	loc := #caller_location,
) {
	// Generate a stable ID based on the caller location or a provided string
	final_id := id != "" ? lc.ID(id) : lc.ID(loc, salt)

	final_style := user_style
	// Default to filling the available layout space if not overridden
	if final_style.width == nil do final_style.width = lc.Percent{100}
	if final_style.height == nil do final_style.height = lc.Percent{100}

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

debug_panel :: proc(ui_ctx: ^UI_Context, ev_ctx: ^events.Event_Context, anim_ctx: ^anim.Context) {
	prev_roots := ui_ctx.layout.prev_root_boxes

	// State trackers
	@(static) active_target_id: lc.Box_ID
	@(static) pinned_node_id: lc.Box_ID
	@(static) tree_hover_target: lc.Box_ID
	@(static) tree_click_target: lc.Box_ID
	@(static) prev_mouse_down: bool

	tree_hover_target = 0
	tree_click_target = 0

	// Global mouse click detection for pinning from the main UI
	mouse_state := sdl.GetMouseState(nil, nil)
	is_mouse_down := (mouse_state & sdl.BUTTON_LMASK) != 0
	just_clicked := is_mouse_down && !prev_mouse_down
	prev_mouse_down = is_mouse_down

	debug_panel_id := lc.ID("DEBUG_PANEL_ROOT")
	highlight_id := lc.ID("DEBUG_HIGHLIGHT_OVERLAY")
	info_bar_id := lc.ID("DEBUG_INFO_BAR")

	// 1. Highlight Overlay
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
						width = lc.Fixed{target.computed_width},
						height = lc.Fixed{target.computed_height},
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

	// 2. Fixed Tree Panel
	element_open(
		ui_ctx,
		Element {
			_box = {id = debug_panel_id},
			style = {
				position     = .FIXED,
				top          = 0,
				right        = 0,
				width        = lc.Fixed{350},
				height       = lc.ViewPercent{100},
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
	text(
		ui_ctx,
		ev_ctx,
		"Debug Inspector",
		user_style = {text_color = Color{1, 1, 1, 1}, font_size = 18},
	)
	element_close(ui_ctx)

	// Panel Body (Scrollable Tree)
	scroll_id := scroll_begin(
		ui_ctx,
		ev_ctx,
		scroll_y = true,
		scroll_x = true,
		user_style = {width = lc.Percent{100}, height = lc.Grow{1}}, // Pushes info bar to bottom
		salt = "debug_tree_scroll",
	)

	for root in prev_roots {
		if root.id == debug_panel_id || root.id == highlight_id || root.id == info_bar_id do continue
		_render_debug_node(
			ui_ctx,
			ev_ctx,
			anim_ctx,
			root,
			0,
			&tree_hover_target,
			&tree_click_target,
			pinned_node_id,
		)
	}
	scroll_end(ui_ctx, ev_ctx, scroll_id, anim_ctx)

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

	// 3. Information Bar (Docked natively at the bottom of the column!)
	info_scroll_id := scroll_begin(
		ui_ctx,
		ev_ctx,
		scroll_y = true,
		user_style = {
			width        = lc.Percent{100},
			height       = lc.Fixed{350}, // Fixed vertical slice for the dump pane
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
			name := lc.get_debug_name(target.id)
			if name == "UNKNOWN_ID" do name = fmt.tprintf("Box_%d", target.id)

			// -- IDENTITY & BOUNDS --
			text(
				ui_ctx,
				ev_ctx,
				"IDENTITY & BOUNDS",
				user_style = {
					text_color = Color{0.4, 0.8, 0.4, 1},
					font_size = 14,
					padding = space(0, 0, 4, 0),
				},
				salt = "h_id",
			)
			_debug_kv(ui_ctx, ev_ctx, "Name", name, "kv_name")
			_debug_kv(ui_ctx, ev_ctx, "ID", fmt.tprintf("%d", target.id), "kv_id")
			_debug_kv(
				ui_ctx,
				ev_ctx,
				"Absolute Pos (X, Y)",
				fmt.tprintf("[%.0f, %.0f]", target.x, target.y),
				"kv_pos",
			)
			_debug_kv(
				ui_ctx,
				ev_ctx,
				"Computed Size",
				fmt.tprintf("%.0f x %.0f", target.computed_width, target.computed_height),
				"kv_size",
			)

			_debug_divider(ui_ctx)

			// -- FLEX & LAYOUT --
			text(
				ui_ctx,
				ev_ctx,
				"FLEX & LAYOUT",
				user_style = {
					text_color = Color{0.4, 0.8, 0.4, 1},
					font_size = 14,
					padding = space(0, 0, 4, 0),
				},
				salt = "h_flex",
			)
			_debug_kv(ui_ctx, ev_ctx, "Direction", fmt.tprintf("%v", target.direction), "kv_dir")
			_debug_kv(ui_ctx, ev_ctx, "Width", fmt.tprintf("%v", target.width), "kv_w")
			_debug_kv(ui_ctx, ev_ctx, "Height", fmt.tprintf("%v", target.height), "kv_h")
			_debug_kv(
				ui_ctx,
				ev_ctx,
				"Justify Content",
				fmt.tprintf("%v", target.justify_content),
				"kv_just",
			)
			_debug_kv(
				ui_ctx,
				ev_ctx,
				"Align Items",
				fmt.tprintf("%v", target.align_items),
				"kv_align",
			)
			_debug_kv(ui_ctx, ev_ctx, "Flex Wrap", fmt.tprintf("%v", target.wrap), "kv_wrap")
			_debug_kv(ui_ctx, ev_ctx, "Basis", fmt.tprintf("%.0f", target.basis), "kv_bas")

			_debug_divider(ui_ctx)

			// -- BOX MODEL --
			text(
				ui_ctx,
				ev_ctx,
				"BOX MODEL",
				user_style = {
					text_color = Color{0.4, 0.8, 0.4, 1},
					font_size = 14,
					padding = space(0, 0, 4, 0),
				},
				salt = "h_box",
			)
			_debug_kv(ui_ctx, ev_ctx, "Padding", fmt.tprintf("%v", target.padding), "kv_pad")
			_debug_kv(ui_ctx, ev_ctx, "Margin", fmt.tprintf("%v", target.margin), "kv_mar")
			_debug_kv(ui_ctx, ev_ctx, "Border", fmt.tprintf("%v", target.border), "kv_bor")
			_debug_kv(ui_ctx, ev_ctx, "Gap", fmt.tprintf("%.0f", target.gap), "kv_gap")
			_debug_kv(
				ui_ctx,
				ev_ctx,
				"Overflow (X / Y)",
				fmt.tprintf("%v / %v", target.overflow_x, target.overflow_y),
				"kv_over",
			)

			_debug_divider(ui_ctx)

			// -- POSITIONING --
			text(
				ui_ctx,
				ev_ctx,
				"POSITIONING",
				user_style = {
					text_color = Color{0.4, 0.8, 0.4, 1},
					font_size = 14,
					padding = space(0, 0, 4, 0),
				},
				salt = "h_pos",
			)
			_debug_kv(ui_ctx, ev_ctx, "Type", fmt.tprintf("%v", target.position), "kv_postype")
			_debug_kv(ui_ctx, ev_ctx, "Z-Index", fmt.tprintf("%d", target.z_index), "kv_z")
			_debug_kv(
				ui_ctx,
				ev_ctx,
				"Top / Bottom",
				fmt.tprintf("%v / %v", target.top, target.bottom),
				"kv_tb",
			)
			_debug_kv(
				ui_ctx,
				ev_ctx,
				"Left / Right",
				fmt.tprintf("%v / %v", target.left, target.right),
				"kv_lr",
			)

			if el != nil {
				_debug_divider(ui_ctx)

				// -- VISUALS & TEXT --
				text(
					ui_ctx,
					ev_ctx,
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
					ui_ctx,
					ev_ctx,
					"Bg Color",
					fmt.tprintf("[%.2f, %.2f, %.2f, %.2f]", c_bg[0], c_bg[1], c_bg[2], c_bg[3]),
					"kv_bg",
				)

				c_bd := el.resolved_border_color
				_debug_kv(
					ui_ctx,
					ev_ctx,
					"Border Color",
					fmt.tprintf("[%.2f, %.2f, %.2f, %.2f]", c_bd[0], c_bd[1], c_bd[2], c_bd[3]),
					"kv_bdc",
				)

				_debug_kv(
					ui_ctx,
					ev_ctx,
					"Border Radius",
					fmt.tprintf("%v", el.resolved_border_radius),
					"kv_rad",
				)
				_debug_kv(
					ui_ctx,
					ev_ctx,
					"Opacity",
					fmt.tprintf("%.2f", el.resolved_opacity),
					"kv_op",
				)
				_debug_kv(
					ui_ctx,
					ev_ctx,
					"Object Fit",
					fmt.tprintf("%v", el.resolved_object_fit),
					"kv_objf",
				)

				c_tx := el.resolved_text_color
				_debug_kv(
					ui_ctx,
					ev_ctx,
					"Text Color",
					fmt.tprintf("[%.2f, %.2f, %.2f, %.2f]", c_tx[0], c_tx[1], c_tx[2], c_tx[3]),
					"kv_txc",
				)
				_debug_kv(
					ui_ctx,
					ev_ctx,
					"Font Size",
					fmt.tprintf("%.1f", el.resolved_font_size),
					"kv_fs",
				)
				_debug_kv(
					ui_ctx,
					ev_ctx,
					"Text Wrap",
					fmt.tprintf("%v", el.resolved_text_wrap),
					"kv_tw",
				)
				_debug_kv(
					ui_ctx,
					ev_ctx,
					"Text Align",
					fmt.tprintf("%v", el.resolved_text_align),
					"kv_ta",
				)
			}
		}
	} else {
		element_open(
			ui_ctx,
			{style = {height = lc.Grow{1}, justify_content = .CENTER, align_items = .CENTER}},
		)
		text(
			ui_ctx,
			ev_ctx,
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

	scroll_end(ui_ctx, ev_ctx, info_scroll_id, anim_ctx)
}

@(private)
_render_debug_node :: proc(
	ui_ctx: ^UI_Context,
	ev_ctx: ^events.Event_Context,
	anim_ctx: ^anim.Context,
	box: ^lc.Box,
	depth: f32,
	hovered_target: ^lc.Box_ID,
	clicked_target: ^lc.Box_ID,
	pinned_id: lc.Box_ID,
) {
	if box == nil do return

	name := lc.get_debug_name(box.id)
	if name == "UNKNOWN_ID" do name = fmt.tprintf("Box_%d", box.id)

	row_id := lc.ID(box.id, "debug_row")
	has_children := len(box.children) > 0

	@(static) expanded_nodes: map[lc.Box_ID]bool
	if box.id not_in expanded_nodes do expanded_nodes[box.id] = false

	is_hovered := is_tree_hovered(ui_ctx, ev_ctx, row_id)
	if is_hovered do hovered_target^ = box.id

	events.register(ev_ctx, row_id, events.Event_Callbacks{focusable = true, cursor = .HAND})
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
				width = lc.Percent{100},
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
		ui_ctx,
		ev_ctx,
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
		ui_ctx,
		ev_ctx,
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
			_render_debug_node(
				ui_ctx,
				ev_ctx,
				anim_ctx,
				child,
				depth + 1,
				hovered_target,
				clicked_target,
				pinned_id,
			)
		}
	}
}

@(private)
_debug_kv :: proc(
	ui_ctx: ^UI_Context,
	ev_ctx: ^events.Event_Context,
	label: string,
	val: string,
	salt: string,
) {
	element_open(
		ui_ctx,
		Element {
			style = {
				direction = .ROW,
				justify_content = .SPACE_BETWEEN,
				width = lc.Percent{100},
				gap = 16,
			},
		},
	)
	text(
		ui_ctx,
		ev_ctx,
		label,
		user_style = {text_color = Color{0.6, 0.6, 0.6, 1}, font_size = 12, width = lc.Shrink{1}},
		salt = fmt.tprintf("%s_lbl", salt),
	)
	text(
		ui_ctx,
		ev_ctx,
		val,
		user_style = {
			text_color = Color{0.8, 0.8, 0.8, 1},
			font_size = 12,
			text_align = .RIGHT,
			width = lc.Grow{1},
		},
		salt = fmt.tprintf("%s_val", salt),
	)
	element_close(ui_ctx)
}

@(private)
_debug_divider :: proc(ui_ctx: ^UI_Context) {
	element_open(
		ui_ctx,
		{
			style = {
				width = lc.Percent{100},
				height = lc.Fixed{1},
				bg_color = Color{0.25, 0.25, 0.25, 1},
				margin = space(8, 0),
			},
		},
	)
	element_close(ui_ctx)
}
