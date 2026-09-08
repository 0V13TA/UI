package renderer

import lc "../layout_calc"
import rl "vendor:raylib"

TITLE :: "This is a hero card showcasing dynamic word wrapping."
CONTENT :: "The layout core automatically calculates the height of this text block based on the parent's width constraints. Because this card uses `lc.ViewPercent{100}`, resizing the window will seamlessly reflow this text and expand or contract the card's height."

metrics := []string{"Total Views\n\n14,092", "Active Users\n\n1,042", "Conversion\n\n4.2%"}


main :: proc() {
	rl.SetConfigFlags({.VSYNC_HINT})
	rl.InitWindow(1024, 768, "WYSIWYG Layout Engine - Complex UI")
	defer rl.CloseWindow()

	// The UI Context now completely encapsulates the layout math, text measuring, and rendering
	ui_ctx := ui_context_create(1024, 768)
	defer ui_context_destroy(ui_ctx)

	// --- Editor Loop ---
	for !rl.WindowShouldClose() {
		ui_begin_frame(ui_ctx, f32(rl.GetScreenWidth()), f32(rl.GetScreenHeight()))
		defer ui_end_frame(ui_ctx)

		{
			element_open(
				ui_ctx,
				{
					box = {
						width = lc.ViewPercent{100},
						height = lc.ViewPercent{100},
						direction = .COLUMN,
						justify_content = .CENTER,
						align_items = .CENTER,
					},
					style = {bg_color = rl.RAYWHITE},
				},
			)
			defer element_close(ui_ctx)

			{
				element_open(
					ui_ctx,
					{
						box = {
							wrap = true,
							width = lc.ViewPercent{50},
							height = lc.Fit(true),
							direction = .COLUMN,
							justify_content = .CENTER,
							align_items = .CENTER,
						},
					},
				)
				defer element_close(ui_ctx)

				ui_text(ui_ctx, TITLE, nil, {text_color = rl.MAGENTA, text_align = .CENTER})
				ui_text(ui_ctx, CONTENT, nil, {text_color = rl.GREEN})
			}

			{
				element_open(
					ui_ctx,
					{
						width = lc.ViewPercent{60},
						height = lc.Fit(true),
						wrap = true,
						gap = 15,
						border = {3, 3, 3, 3},
						padding = {10, 10, 10, 10},
						style = {border_color = rl.DARKBROWN, bg_color = rl.PINK},
					},
				)
				defer element_close(ui_ctx)

				for metric in metrics {
					element_open(
						ui_ctx,
						Element {
							box = {
								width = lc.Grow{1},
								min_width = lc.Fixed{200},
								height = lc.Fit(true),
								border = {1, 1, 1, 1},
								text = metric,
							},
							classes = {"card"},
							style = Style {
								text_align = .CENTER,
								border_color = rl.BLACK,
								bg_color = rl.RAYWHITE,
							},
						},
					)
					element_close(ui_ctx)
				}
			}
		}
	}
}
