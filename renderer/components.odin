package renderer

import lc "../layout_calc"
// This is where all the widgets are
// Like buttons, inputs, etc

ui_text :: proc(
	ctx: ^UI_Context,
	text: string,
	classes: []string = nil,
	style: Style = {},
	loc := #caller_location,
) {
	element_open(
		ctx,
		Element {
			box = {width = lc.Fit(true), height = lc.Fit(true), text = text},
			classes = classes,
			style = style,
		},
		loc,
	)

	element_close(ctx) // Immediately closed!
}
