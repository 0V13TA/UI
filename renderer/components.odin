package renderer

import lc "../layout_calc"
// This is where all the widgets are
// Like buttons, inputs, etc

ui_text :: proc(
	ctx: ^UI_Context,
	text: string,
	classes: []string = nil,
	style: Style = {},
	box: lc.Box = {width = lc.Fit(true), height = lc.Fit(true)},
	loc := #caller_location,
) {
	el_box := box
	el_box.text = text
	element_open(ctx, Element{box = el_box, classes = classes, style = style}, loc)

	element_close(ctx) // Immediately closed!
}
