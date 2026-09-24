package UI

import "core:fmt"
import "core:math"
import "core:math/rand"
import sdl "vendor:sdl2"

// --- APPLICATION STATE ---

User_Record :: struct {
	id:          int,
	name_buf:    [dynamic]u8,
	role_idx:    int,
	is_active:   bool,
	theme_color: [4]f32,
	join_date:   [3]int,
}

Showcase_State :: struct {
	// Navigation
	router:            Router_State,
	nav_items:         []string,
	nav_idx:           int,

	// CRUD State (User Directory)
	users:             [dynamic]User_Record,
	selected_user_idx: int,
	role_options:      []string,
	search_buf:        [dynamic]u8,
	combo_open:        bool,
	color_picker_open: bool,
	date_picker_open:  bool,
	modal_open:        bool,

	// Widget Lab State
	lab_tab_idx:       int,
	volume_val:        f32,
	brightness_val:    f32,
	wifi_enabled:      bool,
	bt_enabled:        bool,
	notes_buffer:      Gap_Buffer,
	toast_open:        bool,

	// Overlays
	context_x:         f32,
	context_y:         f32,
	context_open:      bool,
	show_debug:        bool,
}

main :: proc() {
	app := app_init("UI Toolkit Showcase", 1280, 800, {.SHOWN, .ALLOW_HIGHDPI})
	if app == nil do return
	defer app_destroy(app)

	state := Showcase_State {
		nav_items         = {"Dashboard", "User Directory", "Widget Lab"},
		role_options      = {"Administrator", "Editor", "Viewer", "Guest"},
		selected_user_idx = -1,
		volume_val        = 0.65,
		brightness_val    = .8,
		wifi_enabled      = true,
	}
	seed_initial_users(&state)

	gap_buffer_init(&state.notes_buffer)
	defer gap_buffer_destroy(&state.notes_buffer)

	for !app.quit {
		app_begin_frame(app)
		defer app_end_frame(app)

		{
			element_open(
				app,
				{
					style = {
						direction = .ROW,
						bg_color = COLOR_WHITE,
						width = ViewPercent{100},
						height = ViewPercent{100},
					},
				},
			)
			defer element_close(app)
		}
	}
}

seed_initial_users :: proc(state: ^Showcase_State) {
	names := []string{"Ada Lovelace", "Alan Turing", "Grace Hopper", "John von Neumann"}
	colors := [][4]f32 {
		{0.9, 0.3, 0.4, 1.0},
		{0.2, 0.6, 0.9, 1.0},
		{0.8, 0.4, 0.8, 1.0},
		{0.2, 0.8, 0.5, 1.0},
	}

	for i in 0 ..< 4 {
		u := User_Record {
			id          = 1000 + i,
			role_idx    = i % 2,
			is_active   = i != 3,
			theme_color = colors[i],
			join_date   = {2024, i + 1, 15},
		}
		u.name_buf = make([dynamic]u8)
		for c in names[i] do append(&u.name_buf, u8(c))
		append(&state.users, u)
	}
}
