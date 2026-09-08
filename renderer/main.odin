package renderer

import lc "../layout_calc"
import rl "vendor:raylib"

main :: proc() {
	rl.SetConfigFlags({.VSYNC_HINT})
	rl.InitWindow(1024, 768, "WYSIWYG Layout Engine - Complex UI")
	defer rl.CloseWindow()

	// The UI Context now completely encapsulates the layout math, text measuring, and rendering
	ui_ctx := ui_context_create(1024, 768)
	defer ui_context_destroy(ui_ctx)

	// --- Define Stylesheet ---
	ui_ctx.stylesheet["sidebar"] = Class {
		name = "sidebar",
		style = Style {
			bg_color = rl.Color{30, 40, 50, 255},
			border_color = rl.Color{20, 25, 30, 255},
			text_color = rl.RAYWHITE,
		},
	}

	ui_ctx.stylesheet["nav_item"] = Class {
		name = "nav_item",
		style = Style {
			bg_color = rl.Color{45, 55, 65, 255},
			text_color = rl.LIGHTGRAY,
			padding = [4]f32{10, 15, 10, 15},
		},
	}

	ui_ctx.stylesheet["topbar"] = Class {
		name = "topbar",
		style = Style{bg_color = rl.WHITE, border_color = rl.LIGHTGRAY},
	}

	ui_ctx.stylesheet["card"] = Class {
		name = "card",
		style = Style {
			bg_color = rl.WHITE,
			border_color = rl.LIGHTGRAY,
			padding = [4]f32{20, 20, 20, 20},
		},
	}

	// --- Editor Loop ---
	for !rl.WindowShouldClose() {
		free_all(context.temp_allocator)

		// Begin UI frame (handles layout_reset and screen size sync internally)
		ui_begin_frame(ui_ctx, f32(rl.GetScreenWidth()), f32(rl.GetScreenHeight()))

		// =========================================================
		// ROOT CONTAINER (Row)
		// =========================================================
		element_open(
			ui_ctx,
			Element {
				box = {
					width = lc.ViewPercent{100},
					height = lc.ViewPercent{100},
					direction = .ROW,
				},
				style = Style{bg_color = rl.Color{240, 242, 245, 255}},
			},
		)

		// ---------------------------------------------------------
		// 1. SIDEBAR
		// ---------------------------------------------------------
		{
			element_open(
				ui_ctx,
				Element {
					box = {
						width     = lc.Fixed{240},
						height    = lc.ViewPercent{100},
						direction = .COLUMN,
						border    = {0, 4, 0, 0}, // 4px Right Border only
						padding   = {20, 20, 20, 20},
						gap       = 15,
					},
					classes = {"sidebar"},
				},
			)

			// Sidebar Title
			element_open(
				ui_ctx,
				Element {
					box = {
						width = lc.ViewPercent{100},
						height = lc.Fit(true),
						text = "WYSIWYG\nDashboard",
						padding = {0, 0, 20, 0},
					},
					style = Style{text_align = .CENTER},
				},
			)
			element_close(ui_ctx)

			// Nav Items
			nav_labels := []string{"Home", "Analytics", "Settings", "Profile"}
			for label in nav_labels {
				element_open(
					ui_ctx,
					Element {
						box = {width = lc.ViewPercent{100}, height = lc.Fit(true), text = label},
						classes = {"nav_item"},
					},
				)
				element_close(ui_ctx)
			}

			element_close(ui_ctx) // Close Sidebar
		}

		// ---------------------------------------------------------
		// 2. MAIN CONTENT AREA
		// ---------------------------------------------------------
		{
			element_open(
				ui_ctx,
				Element {
					box = {width = lc.Grow{1}, height = lc.ViewPercent{100}, direction = .COLUMN},
				},
			)

			// TOP BAR
			{
				element_open(
					ui_ctx,
					Element {
						box = {
							width           = lc.ViewPercent{100},
							height          = lc.Fixed{60},
							direction       = .ROW,
							align_items     = .CENTER,
							justify_content = .SPACE_BETWEEN,
							border          = {0, 0, 2, 0}, // 2px Bottom Border only
							padding         = {0, 30, 0, 30},
						},
						classes = {"topbar"},
					},
				)

				element_open(
					ui_ctx,
					Element {
						box = {width = lc.Fit(true), height = lc.Fit(true), text = "Overview"},
						style = Style{text_color = rl.DARKGRAY},
					},
				)
				element_close(ui_ctx)

				element_open(
					ui_ctx,
					Element {
						box = {
							width = lc.Fit(true),
							height = lc.Fit(true),
							text = "Welcome, Admin",
						},
						style = Style{text_color = rl.GRAY, text_align = .RIGHT},
					},
				)
				element_close(ui_ctx)

				element_close(ui_ctx) // Close Top Bar
			}

			// DASHBOARD GRID

			{
				// DASHBOARD CONTENT AREA (Column)
				element_open(
					ui_ctx,
					Element {
						box = {
							width     = lc.ViewPercent{100},
							height    = lc.Grow{1},
							direction = .COLUMN, // <--- Change to Column
							padding   = {30, 30, 30, 30},
							gap       = 20,
						},
					},
				)

				// Hero Card
				element_open(
					ui_ctx,
					Element {
						box = {
							width      = lc.ViewPercent{100},
							height     = lc.Grow{1}, // <--- Dynamically shrinks/grows to fit the screen
							border     = {2, 2, 2, 2},
							overflow_y = .HIDDEN, // <--- Safely clips text if the screen is too small
							text       = "This is a hero card showcasing dynamic word wrapping.\n\nThe layout core automatically calculates the height of this text block based on the parent's width constraints. Because this card uses `lc.ViewPercent{100}`, resizing the window will seamlessly reflow this text and expand or contract the card's height.",
						},
						classes = {"card"},
						style = Style{text_color = rl.DARKGRAY, text_align = .CENTER},
					},
				)
				element_close(ui_ctx)

				// Metrics Grid (Wraps)
				element_open(
					ui_ctx,
					Element {
						box = {
							width     = lc.ViewPercent{100},
							height    = lc.Fit(true), // <--- Fits tightly around the wrapping cards
							direction = .ROW,
							wrap      = true,
							gap       = 20,
						},
					},
				)

				// Flexible Metric Cards
				metrics := []string {
					"Total Views\n\n14,092",
					"Active Users\n\n1,042",
					"Conversion\n\n4.2%",
				}

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
								border_color = rl.Color{200, 200, 200, 255},
							},
						},
					)
					element_close(ui_ctx)
				}

				element_close(ui_ctx) // Close Metrics Grid
				element_close(ui_ctx) // Close Dashboard Content Area
			}

			element_close(ui_ctx) // Close Main Content Area
		}

		element_close(ui_ctx) // Close Root Container

		// Resolves the math and draws the frame
		ui_end_frame(ui_ctx)
	}
}
