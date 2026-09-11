package renderer

import "../events"
import lc "../layout_calc"
import "core:fmt"
import "core:hash"

button :: proc(
	ui_ctx: ^UI_Context,
	ev_ctx: ^events.Event_Context,
	text: string,
	salt := "",
	loc := #caller_location,
) -> bool {
	// 1. Generate stable ID
	hash_input := fmt.tprintf("%s:%d:%s", loc.file_path, loc.line, salt)
	id := lc.Box_ID(hash.murmur64a(transmute([]byte)hash_input))

	// 2. Evaluate State
	is_hovered := ev_ctx.hovered_id == id
	is_pressed := ev_ctx.pressed_id == id
	is_clicked := ev_ctx.clicked_this_frame[id] or_else false

	// We still register so the event system knows this box is interactive (hit testing/focus)
	events.register(ev_ctx, id, events.Event_Callbacks{focusable = true})

	// 3. Style based on state
	bg := Color{0.15, 0.4, 0.8, 1.0}
	if is_pressed {
		bg = Color{0.1, 0.25, 0.6, 1.0}
	} else if is_hovered {
		bg = Color{0.25, 0.5, 0.9, 1.0}
	}

	// 4. Render
	element_open(
		ui_ctx,
		Element {
			_box = {id = id},
			text = text,
			style = {
				padding = space_2(12, 24),
				bg_color = bg,
				border_radius = space(6),
				text_color = Color{1, 1, 1, 1},
				text_align = .CENTER,
				width = lc.Fit(true),
				height = lc.Fit(true),
			},
		},
		loc,
	)
	element_close(ui_ctx)

	return is_clicked
}
