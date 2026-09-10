package renderer

import lc "../layout_calc"
import "core:fmt"
import "core:hash"
import "core:strings"
import rl "vendor:raylib"

Text_Align :: enum {
	LEFT,
	CENTER,
	RIGHT,
}

Pointer_Events :: enum {
	AUTO,
	NONE,
}
Style :: struct {
	bg_color:       Maybe(rl.Color),
	border_color:   Maybe(rl.Color),
	text_color:     Maybe(rl.Color),
	text_align:     Maybe(Text_Align),

	// Typography
	font_name:      Maybe(string),
	font_size:      Maybe(f32),
	font_spacing:   Maybe(f32),
	padding:        Maybe([4]f32),
	margin:         Maybe([4]f32),
	gap:            Maybe(f32),
	width:          Maybe(lc.Sizing),
	height:         Maybe(lc.Sizing),
	pointer_events: Maybe(Pointer_Events),
}

Class :: struct {
	name:  string,
	style: Style,
}

Element :: struct {
	using box:             lc.Box,
	classes:               []string,
	style:                 Style,

	// Resolved Visuals
	resolved_bg:           rl.Color,
	resolved_text:         rl.Color,
	resolved_border:       rl.Color,
	resolved_text_align:   Text_Align,
	resolved_font:         rl.Font,
	resolved_font_size:    f32,
	resolved_font_spacing: f32,
}

Scroll_State :: struct {
	pos: rl.Vector2,
	vel: rl.Vector2,
}

UI_Context :: struct {
	layout:           ^lc.Layout_Context,
	stylesheet:       map[string]Class,
	fonts:            map[string]rl.Font,
	default_font:     rl.Font,
	sdf_shader:       rl.Shader,
	hovered_id:       lc.Box_ID,
	active_id:        lc.Box_ID,
	focused_id:       lc.Box_ID,
	_next_hovered_id: lc.Box_ID, // Used internally during the end_frame hit-test
	pointer:          Pointer_State,
	scroll_state:     map[lc.Box_ID]Scroll_State,
	boxes:            map[lc.Box_ID]rl.Rectangle,
}

SDF_FRAG_SHADER :: `
#version 330
in vec2 fragTexCoord;
in vec4 fragColor;
out vec4 finalColor;
uniform sampler2D texture0;

void main() {
    // Fetch the distance field value from the alpha channel
    float dist = texture(texture0, fragTexCoord).a;
    
    // Calculate the anti-aliasing blur width based on the current scale
    float smoothing = fwidth(dist);
    
    // Crisp the edge
    float alpha = smoothstep(0.5 - smoothing, 0.5 + smoothing, dist);
    finalColor = vec4(fragColor.rgb, fragColor.a * alpha);
}
`

// --- Internal Text Measurement ---

@(private)
ui_text_width :: proc(box: ^lc.Box, text: string) -> f32 {
	el := (^Element)(box.user_data)
	if el == nil do return 0
	c_str := strings.clone_to_cstring(text, context.temp_allocator)
	return(
		rl.MeasureTextEx(el.resolved_font, c_str, el.resolved_font_size, el.resolved_font_spacing).x \
	)
}

@(private)
ui_text_height :: proc(box: ^lc.Box, text: string, max_width: f32) -> f32 {
	el := (^Element)(box.user_data)
	if el == nil do return 0

	space_width :=
		rl.MeasureTextEx(el.resolved_font, " ", el.resolved_font_size, el.resolved_font_spacing).x
	line_height :=
		rl.MeasureTextEx(el.resolved_font, "Wy", el.resolved_font_size, el.resolved_font_spacing).y

	total_lines: f32 = 0.0
	explicit_lines := strings.split(text, "\n", context.temp_allocator)

	for explicit_line in explicit_lines {
		total_lines += 1.0
		cursor_x: f32 = 0.0
		words := strings.split(explicit_line, " ", context.temp_allocator)

		for word in words {
			c_word := strings.clone_to_cstring(word, context.temp_allocator)
			word_width :=
				rl.MeasureTextEx(el.resolved_font, c_word, el.resolved_font_size, el.resolved_font_spacing).x

			// Added `box.wrap` condition here
			if box.wrap && cursor_x + word_width > max_width && cursor_x > 0 {
				cursor_x = 0
				total_lines += 1.0
			}
			cursor_x += word_width + space_width
		}
	}
	return max(total_lines, 1.0) * line_height
}

@(private)
set_clip :: proc(current: ^Maybe(lc.Rect), target: Maybe(lc.Rect)) {
	if current^ == target do return // Skip redundant batch flushes!

	if t, ok := target.?; ok {
		rl.BeginScissorMode(i32(t.x), i32(t.y), i32(t.width), i32(t.height))
	} else {
		rl.EndScissorMode()
	}
	current^ = target
}

@(private)
ui_set_pointer_state :: proc(ctx: ^UI_Context, pos: rl.Vector2, is_down: bool) {
	ctx.pointer.pos = pos

	// 1. Advance state machine
	if is_down {
		if ctx.pointer.current_state == .PRESSED_THIS_FRAME {
			ctx.pointer.current_state = .HELD
		} else if ctx.pointer.current_state != .HELD {
			ctx.pointer.current_state = .PRESSED_THIS_FRAME
		}
	} else {
		if ctx.pointer.current_state == .RELEASED_THIS_FRAME {
			ctx.pointer.current_state = .IDLE
		} else if ctx.pointer.current_state != .IDLE {
			ctx.pointer.current_state = .RELEASED_THIS_FRAME
		}
	}

	// 2. Hit-test against last frame's computed rectangles
	ctx.hovered_id = 0
	for id, rect in ctx.boxes {
		if rl.CheckCollisionPointRec(pos, rect) {
			ctx.hovered_id = id
			// If handling hierarchy/z-index, pick the deepest/highest layer
		}
	}

	// 3. Track active item (drag / click-down capture)
	if ctx.pointer.current_state == .PRESSED_THIS_FRAME {
		ctx.active_id = ctx.hovered_id
	}
}

@(private)
hit_test_tree :: proc(ctx: ^UI_Context, box: ^lc.Box, mouse_pos: rl.Vector2) -> bool {
	// 1. CULLING: Reject if mouse is outside the visible clipped area
	if clip, ok := box.clip_rect.?; ok {
		if mouse_pos.x < clip.x ||
		   mouse_pos.x > clip.x + clip.width ||
		   mouse_pos.y < clip.y ||
		   mouse_pos.y > clip.y + clip.height {
			return false
		}
	}

	// 2. OVERLAPS: Check children first in reverse-draw order (front-to-back)
	for i := len(box.children) - 1; i >= 0; i -= 1 {
		if hit_test_tree(ctx, box.children[i], mouse_pos) do return true
	}

	// 3. ACTUAL HIT: Bounding box check
	if mouse_pos.x >= box.x &&
	   mouse_pos.x <= box.x + box.computed_width &&
	   mouse_pos.y >= box.y &&
	   mouse_pos.y <= box.y + box.computed_height {
		if box.user_data != nil {
			el := (^Element)(box.user_data)
			pe := el.style.pointer_events.? or_else .AUTO

			// Ignore this element if pointer events are disabled
			if pe != .NONE {
				ctx._next_hovered_id = box.id
				return true
			}
		}
	}
	return false
}
// --- Public API ---

ui_context_create :: proc(screen_width, screen_height: f32) -> ^UI_Context {
	ctx := new(UI_Context)
	ctx.layout = lc.layout_context_create(
		ui_text_width,
		ui_text_height,
		screen_width,
		screen_height,
	)
	ctx.stylesheet = make(map[string]Class)
	ctx.fonts = make(map[string]rl.Font)
	ctx.default_font = rl.GetFontDefault()
	ctx.sdf_shader = rl.LoadShaderFromMemory(nil, SDF_FRAG_SHADER)

	ctx.scroll_state = make(map[lc.Box_ID]Scroll_State)
	return ctx
}

ui_context_destroy :: proc(ctx: ^UI_Context) {
	lc.layout_context_destroy(ctx.layout)
	rl.UnloadShader(ctx.sdf_shader)


	delete(ctx.stylesheet)
	delete(ctx.fonts)
	delete(ctx.scroll_state)
	free(ctx)
}

ui_begin_frame :: proc(ctx: ^UI_Context, screen_width, screen_height: f32) {
	ui_set_pointer_state(ctx, rl.GetMousePosition(), rl.IsMouseButtonDown(.LEFT))
	// Swap hovered state from the previous frame's hit test
	if ctx._next_hovered_id > 0 {
		ctx.hovered_id = ctx._next_hovered_id
	}
	ctx._next_hovered_id = 0

	// Poll Unified Input (Mouse & Primary Touch)
	ctx.pointer.pos = rl.GetMousePosition()
	ctx.pointer.delta = rl.GetMouseDelta()
	ctx.pointer.scroll = rl.GetMouseWheelMoveV()
	ctx.pointer.pressed = rl.IsMouseButtonPressed(.LEFT)
	ctx.pointer.released = rl.IsMouseButtonReleased(.LEFT)
	ctx.pointer.is_down = rl.IsMouseButtonDown(.LEFT)

	// Poll Multi-Touch Input (For advanced mobile gestures)
	ctx.pointer.touch_count = rl.GetTouchPointCount()
	for i in 0 ..< min(ctx.pointer.touch_count, MAX_TOUCHES) {
		ctx.pointer.touches[i] = rl.GetTouchPosition(i32(i))
	}

	rl.SetMouseCursor(.DEFAULT)
	if ctx.pointer.pressed {
		// Free old persistent IDs to prevent memory leaks

		// Clone new IDs using the default allocator so they survive across frames
		if ctx.hovered_id > 0 {
			ctx.active_id = ctx.hovered_id
			ctx.focused_id = ctx.hovered_id
		} else {
			ctx.active_id = 0
			ctx.focused_id = 0
		}
	}

	dt := rl.GetFrameTime()
	if dt == 0 do dt = 0.016

	// --- SCROLL BUBBLING (Mouse Wheel) ---
	if (ctx.pointer.scroll.y != 0 || ctx.pointer.scroll.x != 0) && ctx.hovered_id != 0 {
		target := ctx.layout.all_boxes[ctx.hovered_id]
		for target != nil && target.overflow_y != .SCROLL && target.overflow_x != .SCROLL {
			target = target.parent
		}
		if target != nil {
			state := ctx.scroll_state[target.id]
			if target.overflow_y == .SCROLL {
				state.vel.y -= ctx.pointer.scroll.y * 2000.0 // Add velocity impulse
			}
			if target.overflow_x == .SCROLL {
				state.vel.x -= ctx.pointer.scroll.x * 2000.0
			}
			ctx.scroll_state[target.id] = state
		}
	}

	// --- DRAG BUBBLING (Mobile Swipe / Click-and-Drag) ---
	if (ctx.pointer.delta.y != 0 || ctx.pointer.delta.x != 0) && ctx.active_id != 0 {
		target := ctx.layout.all_boxes[ctx.active_id]
		for target != nil && target.overflow_y != .SCROLL && target.overflow_x != .SCROLL {
			target = target.parent
		}
		if target != nil {
			state := ctx.scroll_state[target.id]
			if target.overflow_y == .SCROLL {
				delta_y := ctx.pointer.delta.y
				max_y := max(target.scroll_height - target.computed_height, 0.0)
				if state.pos.y < 0.0 || state.pos.y > max_y do delta_y *= 0.3 // Resist dragging out of bounds
				state.pos.y -= delta_y
				state.vel.y = -ctx.pointer.delta.y / dt // Track exact release velocity
			}
			if target.overflow_x == .SCROLL {
				delta_x := ctx.pointer.delta.x
				max_x := max(target.scroll_width - target.computed_width, 0.0)
				if state.pos.x < 0.0 || state.pos.x > max_x do delta_x *= 0.3
				state.pos.x -= delta_x
				state.vel.x = -ctx.pointer.delta.x / dt
			}
			ctx.scroll_state[target.id] = state
		}
	}

	// Reset layout arena for the new frame
	lc.layout_reset(ctx.layout)
	ctx.layout.screen_width = screen_width
	ctx.layout.screen_height = screen_height
	lc.begin_layout(ctx.layout)
}

ui_end_frame :: proc(ctx: ^UI_Context) {
	lc.end_layout(ctx.layout)

	clear(&ctx.boxes)
	for id, box in ctx.layout.all_boxes {
		ctx.boxes[id] = rl.Rectangle{box.x, box.y, box.computed_width, box.computed_height}
	}


	mouse_pos := rl.GetMousePosition()
	for i := len(ctx.layout.root_boxes) - 1; i >= 0; i -= 1 {
		if hit_test_tree(ctx, ctx.layout.root_boxes[i], mouse_pos) do break
	}

	dt := rl.GetFrameTime()
	if dt == 0 do dt = 0.016

	// --- INERTIA & RUBBER-BAND PHYSICS ---
	for id, state in ctx.scroll_state {
		box := ctx.layout.all_boxes[id]
		if box == nil do continue

		spring_stiffness: f32 = 300.0
		damping: f32 = 30.0 // Friction when springing back
		drag_damping: f32 = 5.0 // Friction when free-scrolling

		new_state := state

		if box.overflow_y == .SCROLL {
			max_y := max(box.scroll_height - box.computed_height, 0.0)

			// Only apply physics if the user isn't actively dragging this box
			if ctx.active_id != id {
				if new_state.pos.y < 0.0 {
					new_state.vel.y += (0.0 - new_state.pos.y) * spring_stiffness * dt
					new_state.vel.y -= new_state.vel.y * damping * dt
				} else if new_state.pos.y > max_y {
					new_state.vel.y += (max_y - new_state.pos.y) * spring_stiffness * dt
					new_state.vel.y -= new_state.vel.y * damping * dt
				} else do new_state.vel.y -= new_state.vel.y * drag_damping * dt


				// 1. Unconditionally apply velocity to position
				new_state.pos.y += new_state.vel.y * dt

				// 2. Clamp velocity to 0 when resting within bounds
				if abs(new_state.vel.y) < 1.0 &&
				   new_state.pos.y >= 0.0 &&
				   new_state.pos.y <= max_y {
					new_state.vel.y = 0
				}
			}
		}

		if box.overflow_x == .SCROLL {
			max_x := max(box.scroll_width - box.computed_width, 0.0)

			if ctx.active_id != id {
				if new_state.pos.x < 0.0 {
					new_state.vel.x += (0.0 - new_state.pos.x) * spring_stiffness * dt
					new_state.vel.x -= new_state.vel.x * damping * dt
				} else if new_state.pos.x > max_x {
					new_state.vel.x += (max_x - new_state.pos.x) * spring_stiffness * dt
					new_state.vel.x -= new_state.vel.x * damping * dt
				} else {
					new_state.vel.x -= new_state.vel.x * drag_damping * dt
				}

				new_state.pos.x += new_state.vel.x * dt
				if abs(new_state.vel.x) < 1.0 && new_state.pos.x >= 0.0 && new_state.pos.x <= max_x do new_state.vel.x = 0
			}
		}

		ctx.scroll_state[id] = new_state
	}


	rl.BeginDrawing()
	rl.ClearBackground(rl.RAYWHITE)

	current_clip: Maybe(lc.Rect) = nil
	for root_box in ctx.layout.root_boxes do render_box(ctx, root_box, &current_clip)

	if current_clip != nil do rl.EndScissorMode()
	rl.EndDrawing()
}

apply_styles :: proc(el: ^Element, ctx: ^UI_Context) {
	// 1. Set base defaults
	el.resolved_bg = rl.BLANK
	el.resolved_text = rl.BLACK
	el.resolved_border = rl.BLANK
	el.resolved_text_align = .LEFT
	el.resolved_font = ctx.default_font
	el.resolved_font_size = 20.0
	el.resolved_font_spacing = 1.0

	merge_style :: proc(el: ^Element, s: Style, ctx: ^UI_Context) {
		if c, ok := s.bg_color.?; ok do el.resolved_bg = c
		if c, ok := s.text_color.?; ok do el.resolved_text = c
		if c, ok := s.border_color.?; ok do el.resolved_border = c
		if ta, ok := s.text_align.?; ok do el.resolved_text_align = ta

		if fn, ok := s.font_name.?; ok {
			if f, exists := ctx.fonts[fn]; exists do el.resolved_font = f
		}
		if fs, ok := s.font_size.?; ok do el.resolved_font_size = fs
		if fsp, ok := s.font_spacing.?; ok do el.resolved_font_spacing = fsp

		if p, ok := s.padding.?; ok do el.padding = p
		if m, ok := s.margin.?; ok do el.margin = m
		if g, ok := s.gap.?; ok do el.gap = g
		if w, ok := s.width.?; ok do el.width = w
		if h, ok := s.height.?; ok do el.height = h
	}

	for class_name in el.classes {
		if c, ok := ctx.stylesheet[class_name]; ok do merge_style(el, c.style, ctx)
	}
	merge_style(el, el.style, ctx)
}

element_open :: proc(
	ctx: ^UI_Context,
	el_val: Element,
	loc := #caller_location,
) -> Interaction_State {
	el := new(Element, context.temp_allocator)
	el^ = el_val

	if el.box.id == 0 {
		loc_str := fmt.tprintf("%s:%d", loc.file_path, loc.line)
		el.box.id = lc.Box_ID(hash.fnv32(transmute([]byte)loc_str))
	}

	apply_styles(el, ctx)

	// --- AUTO-INJECT SCROLL STATE ---
	if scroll, ok := ctx.scroll_state[el.box.id]; ok {
		el.box.offset_x = scroll.pos.x
		el.box.offset_y = scroll.pos.y
	}

	el.box.user_data = el
	lc.box_open(ctx.layout, el.box, loc)
	return get_interaction(ctx, el.box.id)
}

element_close :: proc(ctx: ^UI_Context) {
	lc.box_close(ctx.layout)
}

load_smooth_font :: proc(path: cstring, base_size: i32 = 64) -> rl.Font {
	// 1. Load the font at a high resolution (64px)
	font := rl.LoadFontEx(path, base_size, nil, 0)

	// 2. Generate Mipmaps so the GPU has clean, downscaled reference textures
	// rl.GenTextureMipmaps(&font.texture)

	// 3. Force the GPU to smooth the pixels when scaling down to 20px or 28px
	rl.SetTextureFilter(font.texture, .TRILINEAR)

	return font
}

load_sdf_font :: proc(path: cstring, base_size: i32 = 64) -> rl.Font {
	file_size: i32
	file_data := rl.LoadFileData(path, &file_size)
	defer rl.UnloadFileData(file_data)

	font: rl.Font
	font.baseSize = base_size
	font.glyphCount = 95 // Standard ASCII range

	// Load explicitly as .SDF to generate distance fields instead of raw pixels
	glyph_count: i32 = 95
	font.glyphs = rl.LoadFontData(
		file_data,
		file_size,
		base_size,
		nil,
		font.glyphCount,
		.SDF,
		&glyph_count,
	)

	// Pack the atlas (SDF handles its own padding internally)
	atlas_image := rl.GenImageFontAtlas(font.glyphs, &font.recs, font.glyphCount, base_size, 0, 0)
	font.texture = rl.LoadTextureFromImage(atlas_image)
	rl.UnloadImage(atlas_image)

	// Bilinear filtering is required so the shader can smoothly interpolate the distance values
	rl.SetTextureFilter(font.texture, .BILINEAR)

	return font
}

// --- Recursive Render Pass ---

render_box :: proc(ui_ctx: ^UI_Context, box: ^lc.Box, current_clip: ^Maybe(lc.Rect)) {
	// 1. Snapshot the state we inherited from the caller
	previous_clip := current_clip^

	// 2. Apply this box's required clip (only hits OpenGL if it differs)
	set_clip(current_clip, box.clip_rect)

	if box.user_data == nil do return
	el := (^Element)(box.user_data)

	box_rect := rl.Rectangle{box.x, box.y, box.computed_width, box.computed_height}
	if el.resolved_bg != rl.BLANK {
		rl.DrawRectangleRec(box_rect, el.resolved_bg)
	}

	if el.resolved_border != rl.BLANK {
		if box.border[lc.Side.TOP] > 0.0 do rl.DrawRectangleRec({box.x, box.y, box.computed_width, box.border[lc.Side.TOP]}, el.resolved_border)
		if box.border[lc.Side.BOTTOM] > 0.0 do rl.DrawRectangleRec({box.x, box.y + box.computed_height - box.border[lc.Side.BOTTOM], box.computed_width, box.border[lc.Side.BOTTOM]}, el.resolved_border)
		if box.border[lc.Side.LEFT] > 0.0 do rl.DrawRectangleRec({box.x, box.y, box.border[lc.Side.LEFT], box.computed_height}, el.resolved_border)
		if box.border[lc.Side.RIGHT] > 0.0 do rl.DrawRectangleRec({box.x + box.computed_width - box.border[lc.Side.RIGHT], box.y, box.border[lc.Side.RIGHT], box.computed_height}, el.resolved_border)
	}

	if text, ok := box.text.?; ok {
		text_x := box.x + box.padding[lc.Side.LEFT] + box.border[lc.Side.LEFT]
		text_y := box.y + box.padding[lc.Side.TOP] + box.border[lc.Side.TOP]
		inner_width := max(
			box.computed_width - lc.get_horizontal(box.padding) - lc.get_horizontal(box.border),
			0.0,
		)

		space_width :=
			rl.MeasureTextEx(el.resolved_font, " ", el.resolved_font_size, el.resolved_font_spacing).x
		line_height :=
			rl.MeasureTextEx(el.resolved_font, "Wy", el.resolved_font_size, el.resolved_font_spacing).y
		cursor_y := text_y

		explicit_lines := strings.split(text, "\n", context.temp_allocator)
		for explicit_line in explicit_lines {
			words := strings.split(explicit_line, " ", context.temp_allocator)
			start_idx := 0

			for start_idx < len(words) {
				end_idx := start_idx
				line_width: f32 = 0.0

				for end_idx < len(words) {
					c_word := strings.clone_to_cstring(words[end_idx], context.temp_allocator)
					word_width :=
						rl.MeasureTextEx(el.resolved_font, c_word, el.resolved_font_size, el.resolved_font_spacing).x
					if box.wrap && end_idx > start_idx && line_width + word_width > inner_width do break
					line_width += word_width + space_width
					end_idx += 1
				}
				if end_idx > start_idx do line_width -= space_width

				start_x := text_x
				if el.resolved_text_align == .CENTER {
					start_x += max((inner_width - line_width) / 2.0, 0.0)
				} else if el.resolved_text_align == .RIGHT {
					start_x += max(inner_width - line_width, 0.0)
				}

				cursor_x := start_x
				rl.BeginShaderMode(ui_ctx.sdf_shader)
				for i in start_idx ..< end_idx {
					c_word := strings.clone_to_cstring(words[i], context.temp_allocator)
					rl.DrawTextEx(
						el.resolved_font,
						c_word,
						{cursor_x, cursor_y},
						el.resolved_font_size,
						el.resolved_font_spacing,
						el.resolved_text,
					)
					cursor_x +=
						rl.MeasureTextEx(el.resolved_font, c_word, el.resolved_font_size, el.resolved_font_spacing).x +
						space_width
				}

				rl.EndShaderMode()

				cursor_y += line_height
				start_idx = end_idx
			}
		}
	}

	for child in box.children {
		render_box(ui_ctx, child, current_clip)
	}

	// 3. RESTORE the caller's clip state before returning!
	set_clip(current_clip, previous_clip)
}
