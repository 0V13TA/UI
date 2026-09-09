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

	// 1. Load high-res, smoothed fonts
	font_bold := load_sdf_font("font/CaacupeOne-Regular.ttf")
	font_italic := load_sdf_font("font/SankofaDisplay-Regular.ttf")

	// Pick fonts that actually contain English letters!
	font_mono := load_sdf_font("font/CaacupeOne-Regular.ttf")
	font_serif := load_sdf_font("font/Kablammo-Regular-VariableFont_MORF.ttf")

	// Clean up Raylib resources on exit
	defer {
		rl.UnloadFont(font_bold)
		rl.UnloadFont(font_italic)
		rl.UnloadFont(font_mono)
		rl.UnloadFont(font_serif)
	}

	// 2. Register them into your UI Engine
	ui_ctx.fonts["bold"] = font_bold
	ui_ctx.fonts["italic"] = font_italic
	ui_ctx.fonts["mono"] = font_mono
	ui_ctx.fonts["serif"] = font_serif

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

				ui_text(
					ui_ctx,
					TITLE,
					true,
					nil,
					{
						text_color = rl.MAGENTA,
						text_align = .CENTER,
						font_name = "italic",
						font_size = 28.0,
					},
				)
				ui_text(
					ui_ctx,
					CONTENT,
					true,
					nil,
					{
						text_color = rl.GREEN,
						text_align = .CENTER,
						font_name = "bold",
						font_size = 28.0,
					},
				)
				// In main.odin

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
					ui_text(
						ui_ctx,
						metric,
						true,
						nil,
						{
							font_name = "serif",
							font_size = 20.0,
							text_align = .CENTER,
							bg_color = rl.RAYWHITE,
							text_color = rl.BLACK,
						},
						{width = lc.Grow{1}},
					)
				}
			}
		}
	}
}
