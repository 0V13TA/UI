package renderer

import "../events"
import lc "../layout_calc"
import "core:fmt"
import "core:hash"

button :: proc(
	ui_ctx: ^UI_Context,
	ev_ctx: ^events.Event_Context,
	text: string,
	user_style := Style{},
	salt := "",
	loc := #caller_location,
) -> bool {
	hash_input := fmt.tprintf("%s:%d:%s", loc.file_path, loc.line, salt)
	id := lc.Box_ID(hash.murmur64a(transmute([]byte)hash_input))

	is_hovered := ev_ctx.hovered_id == id
	is_pressed := ev_ctx.pressed_id == id
	is_clicked := ev_ctx.clicked_this_frame[id] or_else false

	events.register(ev_ctx, id, events.Event_Callbacks{focusable = true})

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

	element_open(ui_ctx, Element{_box = {id = id}, text = text, style = final_style}, loc)
	element_close(ui_ctx)

	return is_clicked
}

scroll_begin :: proc(
	ui_ctx: ^UI_Context,
	ev_ctx: ^events.Event_Context,
	id: lc.Box_ID = 0,
	user_style := Style{},
	salt := "",
	loc := #caller_location,
) {
	// Generate a stable ID if an explicit one wasn't provided
	final_id := id
	if final_id == 0 {
		hash_input := fmt.tprintf("%s:%d:%s", loc.file_path, loc.line, salt)
		final_id = lc.Box_ID(hash.murmur64a(transmute([]byte)hash_input))
	}

	// Force vertical scrolling on the style
	final_style := user_style
	final_style.overflow_y = .SCROLL

	element_open(
		ui_ctx,
		Element {
			_box = {id = final_id, offset_y = ev_ctx.scroll_offsets[final_id]},
			style = final_style,
		},
		loc,
	)
}

scroll_end :: proc(ctx: ^UI_Context) {
	element_close(ctx)
}
