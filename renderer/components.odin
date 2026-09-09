package renderer

import lc "../layout_calc"
import "core:fmt"
import "core:hash"
import rl "vendor:raylib"

ui_text :: proc(
	ctx: ^UI_Context,
	text: string,
	wrap := true,
	classes: []string = nil,
	style: Style = {},
	box: lc.Box = {width = lc.Fit(true), height = lc.Fit(true)},
	loc := #caller_location,
) {
	mut_style := style
	if mut_style.pointer_events == nil {
		mut_style.pointer_events = .NONE
	}
	el_box := box
	el_box.text = text
	el_box.wrap = wrap

	element_open(ctx, Element{box = el_box, classes = classes, style = mut_style}, loc)

	element_close(ctx) // Immediately closed!
}

ui_button :: proc(
	ctx: ^UI_Context,
	text: string,
	id: lc.Box_ID = 0,
	style: Style = {},
	loc := #caller_location,
) -> bool {
	target_id := id
	if target_id == 0 {
		loc_str := fmt.tprintf("%s:%d", loc.file_path, loc.line)
		target_id = lc.Box_ID(hash.fnv32a(transmute([]byte)loc_str))
	}

	is_hovered := (ctx.hovered_id == target_id) && (target_id != 0)
	is_active := (ctx.active_id == target_id) && (target_id != 0)
	clicked := is_hovered && is_active && (ctx.pointer.current_state == .RELEASED_THIS_FRAME)

	dynamic_style := style
	base_bg := style.bg_color.? or_else rl.Color{60, 130, 246, 255}

	if is_active {
		dynamic_style.bg_color = rl.Color{37, 99, 235, 255}
	} else if is_hovered {
		dynamic_style.bg_color = rl.Color{96, 165, 250, 255}
		rl.SetMouseCursor(.POINTING_HAND)
	} else {
		dynamic_style.bg_color = base_bg
	}

	el_box := lc.Box {
		id              = lc.Box_ID(target_id),
		width           = style.width.? or_else lc.Fit(true),
		height          = style.height.? or_else lc.Fit(true),
		padding         = style.padding.? or_else [4]f32{12, 24, 12, 24},
		border          = {2, 2, 2, 2},
		justify_content = .CENTER,
		align_items     = .CENTER,
	}

	element_open(ctx, Element{box = el_box, style = dynamic_style}, loc)
	text_col := style.text_color.? or_else rl.WHITE
	ui_text(ctx, text, false, nil, Style{text_color = text_col, text_align = .CENTER})
	element_close(ctx)

	return clicked
}
