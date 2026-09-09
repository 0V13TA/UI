package renderer

import lc "../layout_calc"
import "core:fmt"
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

// Returns `true` the exact frame the user releases a click/touch over this box
ui_button :: proc(
	ctx: ^UI_Context,
	text: string,
	id: string = "",
	style: Style = {},
	loc := #caller_location,
) -> bool {
	// 1. Resolve a predictable ID for interaction tracking
	target_id: lc.Box_ID
	if id != "" {
		target_id = lc.Box_ID(id)
	} else {
		loc_str := fmt.tprintf("%s:%d", loc.file_path, loc.line)
		target_id = lc.Box_ID(loc_str) // Temporary string, layout engine clones it
	}

	// 2. Query the interaction state to drive visual feedback
	interaction := get_interaction(ctx, target_id)

	dynamic_style := style

	// Provide default fallback colors if none are set
	base_bg := style.bg_color.? or_else rl.Color{60, 130, 246, 255} // Blue
	hover_bg := rl.Color{96, 165, 250, 255} // Lighter Blue
	active_bg := rl.Color{37, 99, 235, 255} // Darker Blue

	// Apply state-driven styles
	if interaction.is_active {
		dynamic_style.bg_color = active_bg
	} else if interaction.is_hovered {
		dynamic_style.bg_color = hover_bg
		rl.SetMouseCursor(.POINTING_HAND) // Web/Desktop UX
	} else {
		dynamic_style.bg_color = base_bg
	}

	// 3. Define the structural box
	el_box := lc.Box {
		id              = target_id,
		width           = style.width.? or_else lc.Fit(true),
		height          = style.height.? or_else lc.Fit(true),
		padding         = style.padding.? or_else [4]f32{12, 24, 12, 24},
		border          = {2, 2, 2, 2},
		justify_content = .CENTER,
		align_items     = .CENTER,
	}

	// 4. Render the container and text
	element_open(ctx, Element{box = el_box, style = dynamic_style}, loc)

	text_col := style.text_color.? or_else rl.WHITE
	ui_text(ctx, text, false, nil, Style{text_color = text_col, text_align = .CENTER})

	element_close(ctx)

	// 5. Fire the onClick handler
	return interaction.clicked
}
