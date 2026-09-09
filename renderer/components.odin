package renderer

import lc "../layout_calc"
// This is where all the widgets are
// Like buttons, inputs, etc

ui_text :: proc(
	ctx: ^UI_Context,
	text: string,
	wrap := true,
	classes: []string = nil,
	style: Style = {},
	box: lc.Box = {width = lc.Percent{100}, height = lc.Fit(true)},
	loc := #caller_location,
) {
	el_box := box
	el_box.text = text
	el_box.wrap = wrap

	element_open(ctx, Element{box = el_box, classes = classes, style = style}, loc)

	element_close(ctx) // Immediately closed!
}
