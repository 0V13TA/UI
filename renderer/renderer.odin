package renderer

import lc "../layout_calc"
import "core:fmt"
import "core:hash"
import "core:math"
import "core:strings"
import "core:unicode/utf8"
import sdl "vendor:sdl2"
import "vendor:sdl2/ttf"

Text_Align :: enum {
	LEFT,
	RIGHT,
	CENTER,
}
Text_Wrap :: enum {
	NONE,
	WORD,
	LETTER,
}
Cached_Texture :: struct {
	texture: ^sdl.Texture,
	width:   i32,
	height:  i32,
}

Object_Fit :: enum {
	STRETCH, // Fills exactly, ignoring aspect ratio (Default)
	CONTAIN, // Fits inside, preserving aspect ratio (Letterboxes)
	COVER, // Fills entirely, preserving aspect ratio (Crops excess)
	NONE, // Native size, centered (Crops if too large)
}

Color :: distinct [4]f32
Class :: distinct u32


Style :: struct {
	bg_color:        Maybe(Color),
	opacity:         Maybe(f32),

	//
	text_color:      Maybe(Color),
	text_wrap:       Maybe(Text_Wrap),
	text_align:      Maybe(Text_Align),
	selection_start: Maybe(int),
	selection_end:   Maybe(int),
	selection_color: Maybe(Color),

	// Typography
	font_size:       Maybe(f32),
	font_spacing:    Maybe(f32),
	font_name:       Maybe(string),
	font_style:      Maybe(ttf.StyleFlag),

	// Spacing
	gap:             Maybe(f32),
	margin:          Maybe([4]f32),
	padding:         Maybe([4]f32),

	//
	border:          Maybe([4]f32),
	border_color:    Maybe(Color),
	border_radius:   Maybe([4]f32),

	// Flex Alignment
	wrap:            Maybe(bool),
	basis:           Maybe(f32),
	direction:       Maybe(lc.Direction),
	align_items:     Maybe(lc.Align),
	justify_content: Maybe(lc.Align),

	// Position
	top:             Maybe(f32), // Only useful if position != STATIC
	left:            Maybe(f32),
	right:           Maybe(f32),
	bottom:          Maybe(f32),
	position:        Maybe(lc.Position),

	// Scrolling
	overflow_x:      Maybe(lc.Overflow),
	overflow_y:      Maybe(lc.Overflow),

	//
	z_index:         Maybe(i32),

	//
	object_fit:      Maybe(Object_Fit),
	bg_image:        Maybe(^sdl.Texture),

	//
	width:           Maybe(lc.Sizing),
	height:          Maybe(lc.Sizing),
	min_width:       Maybe(lc.Bound_Sizing),
	max_width:       Maybe(lc.Bound_Sizing),
	min_height:      Maybe(lc.Bound_Sizing),
	max_height:      Maybe(lc.Bound_Sizing),
}


Element :: struct {
	classes:                []Class,
	style:                  Style,
	using _box:             lc.Box,

	// Anything not in Box
	// Font
	resolved_font_spacing:  f32,
	resolved_font_size:     f32,
	resolved_font:          ^ttf.Font,
	resolved_font_style:    ttf.StyleFlag,

	// Text
	resolved_text_wrap:     Text_Wrap,
	resolved_text_color:    Color,
	resolved_text_align:    Text_Align,

	// Border
	resolved_opacity:       f32,
	resolved_border_color:  Color,
	resolved_border_radius: [4]f32,

	// Backgroud
	resolved_bg_color:      Color,
	resolved_object_fit:    Object_Fit,
	resolved_bg_image:      ^sdl.Texture,
}

Glyph_Key :: struct {
	font: ^ttf.Font,
	ch:   rune,
}

Glyph :: struct {
	texture:               ^sdl.Texture,
	width, height:         i32,
	min_x, max_y, advance: i32,
}

UI_Context :: struct {
	layout:      ^lc.Layout_Context,
	fonts:       map[u32]^ttf.Font, // Hash Font name + Cache name
	stylesheet:  map[Class]Style,
	glyph_cache: map[Glyph_Key]Glyph,
	slice_cache: map[i32]^sdl.Texture,
	image_cache: map[u32]^sdl.Texture,
}


// Utility Functions
Class_Name :: proc(id: string) -> Class {
	return Class(hash.fnv32(transmute([]byte)id))
}

space_1 :: proc(all: f32) -> [4]f32 {
	return {all, all, all, all}
}
space_2 :: proc(vertical, horizontal: f32) -> [4]f32 {
	return {vertical, horizontal, vertical, horizontal}
}
space_3 :: proc(top, horizontal, bottom: f32) -> [4]f32 {
	return {top, horizontal, bottom, horizontal}
}
space_4 :: proc(top, right, bottom, left: f32) -> [4]f32 {
	return {top, right, bottom, left}
}

space :: proc {
	space_1,
	space_2,
	space_3,
	space_4,
}


// --- Color Helpers ---
to_sdl_color :: proc(c: Color) -> (u8, u8, u8, u8) {
	return u8(c[0] * 255), u8(c[1] * 255), u8(c[2] * 255), u8(c[3] * 255)
}

set_render_color :: proc(renderer: ^sdl.Renderer, c: Color) {
	r, g, b, a := to_sdl_color(c)
	sdl.SetRenderDrawColor(renderer, r, g, b, a)
}

clear_texture_cache :: proc(ctx: ^UI_Context) {
	// ADD 9-SLICE CLEANUP
	for _, tex in ctx.slice_cache {
		sdl.DestroyTexture(tex)
	}
	clear(&ctx.slice_cache)
}

create_9slice_base_texture :: proc(renderer: ^sdl.Renderer, radius: i32) -> ^sdl.Texture {
	size := radius * 2 + 2 // +2 gives a 2px stretchable center

	// Create an RGBA32 surface
	rmask: u32 = 0x000000ff
	gmask: u32 = 0x0000ff00
	bmask: u32 = 0x00ff0000
	amask: u32 = 0xff000000

	surface := sdl.CreateRGBSurface(0, size, size, 32, rmask, gmask, bmask, amask)
	defer sdl.FreeSurface(surface)

	pixels := cast([^]u32)surface.pixels
	pitch := surface.pitch / 4 // pitch in u32s

	for y in 0 ..< size {
		for x in 0 ..< size {
			// Map x, y to distance from the nearest corner
			cx := x < radius ? radius - x : (x > radius + 1 ? x - (radius + 1) : 0)
			cy := y < radius ? radius - y : (y > radius + 1 ? y - (radius + 1) : 0)

			dist := math.sqrt(f32(cx * cx + cy * cy))

			alpha: u32 = 255
			if dist > f32(radius) {
				// Smooth anti-aliasing on the outer edge
				diff := dist - f32(radius)
				if diff > 1.0 {
					alpha = 0
				} else {
					alpha = u32(255.0 * (1.0 - diff))
				}
			}

			// Write white pixel with calculated alpha
			pixels[y * pitch + x] = (alpha << 24) | 0x00FFFFFF
		}
	}

	// Convert to a hardware texture
	tex := sdl.CreateTextureFromSurface(renderer, surface)
	sdl.SetTextureBlendMode(tex, .BLEND)
	return tex
}

draw_rounded_rect_9slice :: proc(
	renderer: ^sdl.Renderer,
	tex: ^sdl.Texture,
	dest_rect: sdl.Rect,
	corner_radius: i32,
	color: sdl.Color,
) {
	if tex == nil do return

	// Tint the white texture to the target UI color
	sdl.SetTextureColorMod(tex, color.r, color.g, color.b)
	sdl.SetTextureAlphaMod(tex, color.a)

	tex_w, tex_h: i32
	sdl.QueryTexture(tex, nil, nil, &tex_w, &tex_h)

	// The slice margin is the corner radius used when generating the texture
	slice := tex_w / 2 - 1

	// Clamp layout radius to avoid overlapping slices on very small boxes
	r := corner_radius
	if r > dest_rect.w / 2 do r = dest_rect.w / 2
	if r > dest_rect.h / 2 do r = dest_rect.h / 2

	// Define the 9 Source Rectangles (from the base texture)
	src := [9]sdl.Rect {
		{0, 0, slice, slice}, // Top Left
		{slice, 0, tex_w - 2 * slice, slice}, // Top Center
		{tex_w - slice, 0, slice, slice}, // Top Right
		{0, slice, slice, tex_h - 2 * slice}, // Mid Left
		{slice, slice, tex_w - 2 * slice, tex_h - 2 * slice}, // Mid Center
		{tex_w - slice, slice, slice, tex_h - 2 * slice}, // Mid Right
		{0, tex_h - slice, slice, slice}, // Bottom Left
		{slice, tex_h - slice, tex_w - 2 * slice, slice}, // Bottom Center
		{tex_w - slice, tex_h - slice, slice, slice}, // Bottom Right
	}

	// Define the 9 Destination Rectangles (on the screen)
	x, y, w, h := dest_rect.x, dest_rect.y, dest_rect.w, dest_rect.h
	dst := [9]sdl.Rect {
		{x, y, r, r}, // Top Left
		{x + r, y, w - 2 * r, r}, // Top Center
		{x + w - r, y, r, r}, // Top Right
		{x, y + r, r, h - 2 * r}, // Mid Left
		{x + r, y + r, w - 2 * r, h - 2 * r}, // Mid Center
		{x + w - r, y + r, r, h - 2 * r}, // Mid Right
		{x, y + h - r, r, r}, // Bottom Left
		{x + r, y + h - r, w - 2 * r, r}, // Bottom Center
		{x + w - r, y + h - r, r, r}, // Bottom Right
	}

	// Dispatch the 9 draw calls
	for i in 0 ..< 9 {
		// Skip drawing segments that have been squished to 0 width or height
		if dst[i].w > 0 && dst[i].h > 0 {
			sdl.RenderCopy(renderer, tex, &src[i], &dst[i])
		}
	}
}

get_9slice_texture :: proc(
	ctx: ^UI_Context,
	renderer: ^sdl.Renderer,
	radius: i32,
) -> ^sdl.Texture {
	if tex, exists := ctx.slice_cache[radius]; exists {
		return tex
	}
	// Cache miss: Create and store the 9-slice base texture
	tex := create_9slice_base_texture(renderer, radius)
	ctx.slice_cache[radius] = tex
	return tex
}

// --- Master Box Drawing Proc ---
draw_ui_box :: proc(
	ctx: ^UI_Context,
	renderer: ^sdl.Renderer,
	bounds: sdl.Rect,
	bg_color, border_color: Color,
	border: [4]f32, // border: [Top, Right, Bottom, Left]
	radii: [4]f32, // radii:  [TopLeft, TopRight, BottomRight, BottomLeft]
) {
	has_border := border[0] > 0 || border[1] > 0 || border[2] > 0 || border[3] > 0

	// 9-slice requires a uniform radius. We'll use the top-left radius.
	corner_radius := i32(radii[0])

	// Fast path for hard corners (No texture overhead needed)
	if corner_radius <= 0 {
		if has_border && border_color[3] > 0 {
			set_render_color(renderer, border_color)
			rect_copy := bounds
			sdl.RenderFillRect(renderer, &rect_copy)
		}
		if bg_color[3] > 0 {
			inner_bounds := sdl.Rect {
				x = bounds.x + i32(border[3]),
				y = bounds.y + i32(border[0]),
				w = bounds.w - i32(border[3] + border[1]),
				h = bounds.h - i32(border[0] + border[2]),
			}
			set_render_color(renderer, bg_color)
			sdl.RenderFillRect(renderer, &inner_bounds)
		}
		return
	}

	// Draw Outer Border using 9-Slice
	if has_border && border_color[3] > 0 {
		tex := get_9slice_texture(ctx, renderer, corner_radius)
		r, g, b, a := to_sdl_color(border_color)
		draw_rounded_rect_9slice(renderer, tex, bounds, corner_radius, sdl.Color{r, g, b, a})
	}

	// Draw Inner Background using 9-Slice
	if bg_color[3] > 0 {
		inner_bounds := sdl.Rect {
			x = bounds.x + i32(border[3]),
			y = bounds.y + i32(border[0]),
			w = bounds.w - i32(border[3] + border[1]),
			h = bounds.h - i32(border[0] + border[2]),
		}

		// Calculate inner radius by subtracting the maximum border thickness
		max_border := max(border[0], border[3])
		inner_radius := i32(max(f32(corner_radius) - max_border, 0))

		if inner_radius > 0 {
			inner_tex := get_9slice_texture(ctx, renderer, inner_radius)
			r, g, b, a := to_sdl_color(bg_color)
			draw_rounded_rect_9slice(
				renderer,
				inner_tex,
				inner_bounds,
				inner_radius,
				sdl.Color{r, g, b, a},
			)
		} else {
			// If pushing the border in eliminates the radius, draw a standard hard rect
			set_render_color(renderer, bg_color)
			sdl.RenderFillRect(renderer, &inner_bounds)
		}
	}
}

draw_ui_text :: proc(
	ctx: ^UI_Context,
	renderer: ^sdl.Renderer,
	font: ^ttf.Font,
	text: string,
	x, y: i32,
	color: Color,
) {
	r, g, b, a := to_sdl_color(color)
	current_x := x
	prev_ch: rune = 0 // Track the preceding character for pair matching

	for ch in text {
		// Query and apply the kerning offset between the pair
		if prev_ch != 0 {
			kerning := ttf.GetFontKerningSizeGlyphs32(font, prev_ch, ch)
			current_x += kerning
		}

		glyph := get_glyph(ctx, renderer, font, ch)
		if glyph.texture != nil {
			sdl.SetTextureColorMod(glyph.texture, r, g, b)
			sdl.SetTextureAlphaMod(glyph.texture, a)

			dest := sdl.Rect {
				x = current_x + glyph.min_x,
				y = y,
				w = glyph.width,
				h = glyph.height,
			}

			sdl.RenderCopy(renderer, glyph.texture, nil, &dest)
			current_x += glyph.advance
		}

		// Save the current rune for the next iteration
		prev_ch = ch
	}
}


@(private)
ui_text_width :: proc(box: ^lc.Box, text: string) -> f32 {
	el := (^Element)(box.user_data)
	if el == nil || el.resolved_font == nil do return 0

	max_w: f32 = 0.0
	explicit_lines := strings.split(text, "\n", context.temp_allocator)

	for line in explicit_lines {
		if len(line) == 0 do continue
		c_str := fmt.ctprintf("%s", line)
		w, h: i32
		ttf.SizeUTF8(el.resolved_font, c_str, &w, &h)

		if f32(w) > max_w do max_w = f32(w)
	}

	return max_w
}

@(private)
ui_text_height :: proc(box: ^lc.Box, text: string, max_width: f32) -> f32 {
	el := (^Element)(box.user_data)
	if el == nil || el.resolved_font == nil do return 0

	// SDL_ttf provides accurate line height directly from the font metrics
	line_height := f32(ttf.FontHeight(el.resolved_font))

	space_w, space_h: i32
	ttf.SizeUTF8(el.resolved_font, " ", &space_w, &space_h)
	space_width := f32(space_w)

	total_lines: f32 = 0.0
	explicit_lines := strings.split(text, "\n", context.temp_allocator)

	for explicit_line in explicit_lines {
		total_lines += 1.0
		cursor_x: f32 = 0.0

		if el.resolved_text_wrap == .LETTER {
			runes := utf8.string_to_runes(explicit_line, context.temp_allocator)
			for r in runes {
				buf: [5]u8
				bytes, n := utf8.encode_rune(r)
				for j in 0 ..< n do buf[j] = bytes[j]
				buf[n] = 0

				w, h: i32
				ttf.SizeUTF8(el.resolved_font, cstring(&buf[0]), &w, &h)
				rune_width := f32(w)

				if cursor_x + rune_width > max_width && cursor_x > 0 {
					cursor_x = 0
					total_lines += 1.0
				}
				cursor_x += rune_width
			}
		} else {
			words := strings.split(explicit_line, " ", context.temp_allocator)
			for word in words {
				word_width: f32 = 0.0
				if len(word) > 0 {
					c_word := fmt.ctprintf("%s", word)
					w, h: i32
					ttf.SizeUTF8(el.resolved_font, c_word, &w, &h)
					word_width = f32(w)

					if el.resolved_text_wrap == .WORD &&
					   cursor_x + word_width > max_width &&
					   cursor_x > 0 {
						cursor_x = 0
						total_lines += 1.0
					}
				}
				cursor_x += word_width + space_width
			}
		}
	}

	return max(total_lines, 1.0) * line_height
}


@(private)
default_styles :: proc(el: ^Element, ctx: ^UI_Context) {
	// ------------------------------------------------------------
	// Non-inherited visual defaults
	// ------------------------------------------------------------

	el.resolved_bg_image = nil
	el.resolved_object_fit = .STRETCH


	el.resolved_bg_color = {0, 0, 0, 0}
	el.resolved_border_color = {0, 0, 0, 0}
	el.resolved_border_radius = {0, 0, 0, 0}

	// ------------------------------------------------------------
	// Typography
	// ------------------------------------------------------------

	// Typography is inherited from the parent.
	if el._box.parent != nil && el._box.parent.user_data != nil {
		parent := (^Element)(el._box.parent.user_data)

		el.resolved_text_color = parent.resolved_text_color
		el.resolved_text_align = parent.resolved_text_align

		el.resolved_text_wrap = parent.resolved_text_wrap
		el.resolved_opacity = parent.resolved_opacity

		el.resolved_font_size = parent.resolved_font_size
		el.resolved_font_spacing = parent.resolved_font_spacing
		el.resolved_font = parent.resolved_font
		el.resolved_font_style = parent.resolved_font_style
	} else {
		// Root defaults.
		el.resolved_text_color = {0, 0, 0, 1}
		el.resolved_text_align = .LEFT

		el.resolved_font_size = 16.0
		el.resolved_font_spacing = 1.0
		el.resolved_font_style = {}

		el.resolved_text_wrap = .WORD
		el.resolved_opacity = 1.0

		DEFAULT_FONT_HASH := hash.fnv32(transmute([]byte)string("default_font"))
		el.resolved_font = ctx.fonts[DEFAULT_FONT_HASH]
	}
}

@(private)
apply_style_block :: proc(el: ^Element, s: Style, ctx: ^UI_Context) {
	// ------------------------------------------------------------
	// Visuals
	// ------------------------------------------------------------

	if v, ok := s.bg_image.?; ok {
		el.resolved_bg_image = v
	}

	if v, ok := s.object_fit.?; ok {
		el.resolved_object_fit = v
	}

	if v, ok := s.bg_color.?; ok {
		el.resolved_bg_color = v
	}

	if v, ok := s.border_color.?; ok {
		el.resolved_border_color = v
	}

	if v, ok := s.border_radius.?; ok {
		el.resolved_border_radius = v
	}

	if v, ok := s.opacity.?; ok {
		el.resolved_opacity = v
	}

	// ------------------------------------------------------------
	// Typography
	// ------------------------------------------------------------

	if v, ok := s.text_wrap.?; ok {
		el.resolved_text_wrap = v
	}

	if v, ok := s.text_color.?; ok {
		el.resolved_text_color = v
	}

	if v, ok := s.text_align.?; ok {
		el.resolved_text_align = v
	}

	if v, ok := s.font_size.?; ok {
		el.resolved_font_size = v
	}

	if v, ok := s.font_spacing.?; ok {
		el.resolved_font_spacing = v
	}

	if v, ok := s.font_style.?; ok {
		el.resolved_font_style = v
	}

	if v, ok := s.font_name.?; ok {
		font_hash := hash.fnv32(transmute([]byte)v)

		if font, exists := ctx.fonts[font_hash]; exists {
			el.resolved_font = font
		}
	}

	// ------------------------------------------------------------
	// Spacing / layout
	// ------------------------------------------------------------

	if v, ok := s.gap.?; ok {
		el._box.gap = v
	}

	if v, ok := s.margin.?; ok {
		el._box.margin = v
	}

	if v, ok := s.padding.?; ok {
		el._box.padding = v
	}

	if v, ok := s.border.?; ok {
		el._box.border = v
	}

	// ------------------------------------------------------------
	// Flex
	// ------------------------------------------------------------

	if v, ok := s.wrap.?; ok {
		el._box.wrap = v
	}

	if v, ok := s.basis.?; ok {
		el._box.basis = v
	}

	if v, ok := s.direction.?; ok {
		el._box.direction = v
	}

	if v, ok := s.align_items.?; ok {
		el._box.align_items = v
	}

	if v, ok := s.justify_content.?; ok {
		el._box.justify_content = v
	}

	// ------------------------------------------------------------
	// Position
	// ------------------------------------------------------------

	if v, ok := s.position.?; ok {
		el._box.position = v
	}

	if v, ok := s.top.?; ok {
		el._box.top = v
	}

	if v, ok := s.left.?; ok {
		el._box.left = v
	}

	if v, ok := s.right.?; ok {
		el._box.right = v
	}

	if v, ok := s.bottom.?; ok {
		el._box.bottom = v
	}

	// ------------------------------------------------------------
	// Scrolling
	// ------------------------------------------------------------

	if v, ok := s.overflow_x.?; ok {
		el._box.overflow_x = v
	}

	if v, ok := s.overflow_y.?; ok {
		el._box.overflow_y = v
	}

	// ------------------------------------------------------------
	// Size
	// ------------------------------------------------------------

	if v, ok := s.width.?; ok {
		el._box.width = v
	}

	if v, ok := s.height.?; ok {
		el._box.height = v
	}

	if v, ok := s.min_width.?; ok {
		el._box.min_width = v
	}

	if v, ok := s.max_width.?; ok {
		el._box.max_width = v
	}

	if v, ok := s.min_height.?; ok {
		el._box.min_height = v
	}

	if v, ok := s.max_height.?; ok {
		el._box.max_height = v
	}

	// ------------------------------------------------------------
	// Stacking
	// ------------------------------------------------------------

	if v, ok := s.z_index.?; ok {
		el._box.z_index = v
	}
}

@(private)
apply_styles :: proc(el: ^Element, ctx: ^UI_Context) {
	default_styles(el, ctx)

	for cls in el.classes {
		if class_style, exists := ctx.stylesheet[cls]; exists {
			apply_style_block(el, class_style, ctx)
		}
	}

	apply_style_block(el, el.style, ctx)
}

@(private)
set_clip :: proc(renderer: ^sdl.Renderer, current: ^Maybe(lc.Rect), target: Maybe(lc.Rect)) {
	if current^ == target do return

	if t, ok := target.?; ok {
		clip_rect := sdl.Rect{i32(t.x), i32(t.y), i32(t.width), i32(t.height)}
		sdl.RenderSetClipRect(renderer, &clip_rect)
	} else {
		sdl.RenderSetClipRect(renderer, nil) // Removes the clip
	}
	current^ = target
}

render_box :: proc(
	ui_ctx: ^UI_Context,
	renderer: ^sdl.Renderer,
	box: ^lc.Box,
	current_clip: ^Maybe(lc.Rect),
) {
	previous_clip := current_clip^

	set_clip(renderer, current_clip, box.clip_rect)

	if box.user_data == nil do return
	el := (^Element)(box.user_data)

	bg_color := el.resolved_bg_color
	bg_color[3] *= el.resolved_opacity

	border_color := el.resolved_border_color
	border_color[3] *= el.resolved_opacity

	bounds := sdl.Rect{i32(box.x), i32(box.y), i32(box.computed_width), i32(box.computed_height)}

	sdl.SetRenderDrawBlendMode(renderer, .BLEND)

	draw_ui_box(
		ui_ctx,
		renderer,
		bounds,
		bg_color,
		border_color,
		box.border,
		el.resolved_border_radius,
	)

	// --- Draw Image/Video Texture ---
	if el.resolved_bg_image != nil {
		sdl.SetTextureAlphaMod(el.resolved_bg_image, u8(el.resolved_opacity * 255.0))

		// Inset the image so it doesn't draw over your borders
		inner_bounds := sdl.Rect {
			x = bounds.x + i32(box.border[3]),
			y = bounds.y + i32(box.border[0]),
			w = bounds.w - i32(box.border[3] + box.border[1]),
			h = bounds.h - i32(box.border[0] + box.border[2]),
		}

		tex_w, tex_h: i32
		sdl.QueryTexture(el.resolved_bg_image, nil, nil, &tex_w, &tex_h)

		src_rect := sdl.Rect{0, 0, tex_w, tex_h}
		dst_rect := inner_bounds

		if tex_w > 0 && tex_h > 0 && inner_bounds.w > 0 && inner_bounds.h > 0 {
			tex_ratio := f32(tex_w) / f32(tex_h)
			box_ratio := f32(inner_bounds.w) / f32(inner_bounds.h)

			#partial switch el.resolved_object_fit {
			case .CONTAIN:
				if tex_ratio > box_ratio {
					dst_rect.w = inner_bounds.w
					dst_rect.h = i32(f32(inner_bounds.w) / tex_ratio)
					dst_rect.y = inner_bounds.y + (inner_bounds.h - dst_rect.h) / 2
				} else {
					dst_rect.h = inner_bounds.h
					dst_rect.w = i32(f32(inner_bounds.h) * tex_ratio)
					dst_rect.x = inner_bounds.x + (inner_bounds.w - dst_rect.w) / 2
				}
			case .COVER:
				if tex_ratio > box_ratio {
					crop_w := i32(f32(tex_h) * box_ratio)
					src_rect.x = (tex_w - crop_w) / 2
					src_rect.w = crop_w
				} else {
					crop_h := i32(f32(tex_w) / box_ratio)
					src_rect.y = (tex_h - crop_h) / 2
					src_rect.h = crop_h
				}
			case .NONE:
				dst_rect.w = min(tex_w, inner_bounds.w)
				dst_rect.h = min(tex_h, inner_bounds.h)
				dst_rect.x = inner_bounds.x + (inner_bounds.w - dst_rect.w) / 2
				dst_rect.y = inner_bounds.y + (inner_bounds.h - dst_rect.h) / 2
				src_rect.w = dst_rect.w
				src_rect.h = dst_rect.h
				src_rect.x = (tex_w - src_rect.w) / 2
				src_rect.y = (tex_h - src_rect.h) / 2
			}
		}

		sdl.RenderCopy(renderer, el.resolved_bg_image, &src_rect, &dst_rect)
	}

	// Draw Cached Text
	if text, ok := box.text.?; ok {
		if el.resolved_font != nil { 	// Prevent Segfault if font is missing!

			text_x := box.x + box.padding[lc.Side.LEFT] + box.border[lc.Side.LEFT]
			text_y := box.y + box.padding[lc.Side.TOP] + box.border[lc.Side.TOP]

			inner_width := max(
				box.computed_width -
				lc.get_horizontal(box.padding) -
				lc.get_horizontal(box.border),
				0.0,
			)

			space_w, space_h: i32
			ttf.SizeUTF8(el.resolved_font, " ", &space_w, &space_h)
			space_width := f32(space_w)
			line_height := f32(ttf.FontHeight(el.resolved_font))

			cursor_y := text_y
			global_char_idx := 0 // Track exact string index across wrapped lines
			explicit_lines := strings.split(text, "\n", context.temp_allocator)

			for explicit_line in explicit_lines {
				if el.resolved_text_wrap == .LETTER {
					runes := utf8.string_to_runes(explicit_line, context.temp_allocator)
					start_idx := 0
					for start_idx < len(runes) {
						end_idx := start_idx
						line_width: f32 = 0.0

						// Measure how many runes fit on this line
						for end_idx < len(runes) {
							buf: [5]u8
							bytes, n := utf8.encode_rune(runes[end_idx])
							for j in 0 ..< n do buf[j] = bytes[j]
							buf[n] = 0

							w, h: i32
							ttf.SizeUTF8(el.resolved_font, cstring(&buf[0]), &w, &h)
							rune_width := f32(w)

							if line_width + rune_width > inner_width && end_idx > start_idx {
								break
							}
							line_width += rune_width
							end_idx += 1
						}

						// Align the line horizontally
						start_x := text_x
						if el.resolved_text_align == .CENTER {
							start_x += max((inner_width - line_width) / 2.0, 0.0)
						} else if el.resolved_text_align == .RIGHT {
							start_x += max(inner_width - line_width, 0.0)
						}
						cursor_x := start_x

						// Draw the cached runes
						for i in start_idx ..< end_idx {
							buf: [5]u8
							bytes, n := utf8.encode_rune(runes[i])
							for j in 0 ..< n do buf[j] = bytes[j]
							buf[n] = 0
							rune_str := string(buf[:n])

							w, h: i32
							ttf.SizeUTF8(el.resolved_font, cstring(&buf[0]), &w, &h)

							// --- DRAW SELECTION HIGHLIGHT ---
							if s, ok1 := el.style.selection_start.?; ok1 {
								if e, ok2 := el.style.selection_end.?; ok2 {
									if global_char_idx >= min(s, e) &&
									   global_char_idx < max(s, e) {
										sel_col :=
											el.style.selection_color.? or_else Color {
												0.2,
												0.5,
												0.9,
												0.4,
											}
										set_render_color(renderer, sel_col)
										bg_rect := sdl.Rect {
											i32(cursor_x),
											i32(cursor_y),
											w,
											i32(line_height),
										}
										sdl.RenderFillRect(renderer, &bg_rect)
									}
								}
							}

							text_color := el.resolved_text_color
							text_color[3] *= el.resolved_opacity
							draw_ui_text(
								ui_ctx,
								renderer,
								el.resolved_font,
								rune_str,
								i32(cursor_x),
								i32(cursor_y),
								text_color,
							)

							cursor_x += f32(w)
							global_char_idx += 1
						}
						cursor_y += line_height
						start_idx = end_idx
					}
				} else {
					words := strings.split(explicit_line, " ", context.temp_allocator)
					start_idx := 0
					for start_idx < len(words) {
						end_idx := start_idx
						line_width: f32 = 0.0

						// Measure how many words fit on this line
						for end_idx < len(words) {
							word_width: f32 = 0.0
							if len(words[end_idx]) > 0 {
								c_word := fmt.ctprintf("%s", words[end_idx])
								w, h: i32
								ttf.SizeUTF8(el.resolved_font, c_word, &w, &h)
								word_width = f32(w)
							}
							if el.resolved_text_wrap == .WORD &&
							   end_idx > start_idx &&
							   line_width + word_width > inner_width {
								break
							}
							line_width += word_width + space_width
							end_idx += 1
						}

						if end_idx > start_idx do line_width -= space_width

						// Align the line horizontally
						start_x := text_x
						if el.resolved_text_align == .CENTER {
							start_x += max((inner_width - line_width) / 2.0, 0.0)
						} else if el.resolved_text_align == .RIGHT {
							start_x += max(inner_width - line_width, 0.0)
						}
						cursor_x := start_x

						// Draw the cached words
						for i in start_idx ..< end_idx {
							if len(words[i]) > 0 {
								word_runes := utf8.string_to_runes(
									words[i],
									context.temp_allocator,
								)
								word_len := len(word_runes)

								c_word := fmt.ctprintf("%s", words[i])
								w, h: i32
								ttf.SizeUTF8(el.resolved_font, c_word, &w, &h)

								// --- DRAW SELECTION HIGHLIGHT ---
								if s, ok1 := el.style.selection_start.?; ok1 {
									if e, ok2 := el.style.selection_end.?; ok2 {
										s_idx, e_idx := min(s, e), max(s, e)
										if s_idx < global_char_idx + word_len &&
										   e_idx > global_char_idx {
											overlap_s :=
												max(s_idx, global_char_idx) - global_char_idx
											overlap_e :=
												min(e_idx, global_char_idx + word_len) -
												global_char_idx

											pre_str := utf8.runes_to_string(
												word_runes[:overlap_s],
												context.temp_allocator,
											)
											hl_str := utf8.runes_to_string(
												word_runes[overlap_s:overlap_e],
												context.temp_allocator,
											)

											pre_w: i32 = 0
											if len(pre_str) > 0 do ttf.SizeUTF8(el.resolved_font, fmt.ctprintf("%s", pre_str), &pre_w, nil)
											hl_w: i32
											ttf.SizeUTF8(
												el.resolved_font,
												fmt.ctprintf("%s", hl_str),
												&hl_w,
												nil,
											)

											sel_col :=
												el.style.selection_color.? or_else Color {
													0.2,
													0.5,
													0.9,
													0.4,
												}
											set_render_color(renderer, sel_col)
											bg_rect := sdl.Rect {
												i32(cursor_x) + pre_w,
												i32(cursor_y),
												hl_w,
												i32(line_height),
											}
											sdl.RenderFillRect(renderer, &bg_rect)
										}
									}
								}

								text_color := el.resolved_text_color
								text_color[3] *= el.resolved_opacity
								draw_ui_text(
									ui_ctx,
									renderer,
									el.resolved_font,
									words[i],
									i32(cursor_x),
									i32(cursor_y),
									text_color,
								)

								cursor_x += f32(w) + space_width
								global_char_idx += word_len + 1 // Advance by word length + trailing space
							} else {
								cursor_x += space_width
								global_char_idx += 1 // Empty string in split means consecutive spaces
							}
						}

						cursor_y += line_height
						start_idx = end_idx
					}
					global_char_idx += 1 // Advance +1 for the newline character skipped by strings.split
				}
			}
		}
	}

	for child in box.children {
		render_box(ui_ctx, renderer, child, current_clip)
	}

	// RESTORE the caller's clip state before returning
	set_clip(renderer, current_clip, previous_clip)
}

render_tree :: proc(ctx: ^UI_Context, renderer: ^sdl.Renderer, root_boxes: []^lc.Box) {
	current_clip: Maybe(lc.Rect) = nil
	for root_box in root_boxes {
		render_box(ctx, renderer, root_box, &current_clip)
	}

	if current_clip != nil {
		sdl.RenderSetClipRect(renderer, nil)
	}
}

get_glyph :: proc(ctx: ^UI_Context, renderer: ^sdl.Renderer, font: ^ttf.Font, ch: rune) -> Glyph {
	key := Glyph_Key {
		font = font,
		ch   = ch,
	}

	if glyph, exists := ctx.glyph_cache[key]; exists {
		return glyph
	}

	// Cache miss: query metrics and generate a white glyph
	minx, maxx, miny, maxy, advance: i32
	ttf.GlyphMetrics32(font, ch, &minx, &maxx, &miny, &maxy, &advance)

	white := sdl.Color{255, 255, 255, 255}
	surface := ttf.RenderGlyph32_Blended(font, ch, white)

	glyph := Glyph {
		min_x   = minx,
		max_y   = maxy,
		advance = advance,
	}

	if surface != nil {
		glyph.texture = sdl.CreateTextureFromSurface(renderer, surface)
		glyph.width = surface.w
		glyph.height = surface.h
		sdl.SetTextureBlendMode(glyph.texture, .BLEND)
		sdl.FreeSurface(surface)
	}

	ctx.glyph_cache[key] = glyph
	return glyph
}

clear_glyph_cache :: proc(ctx: ^UI_Context) {
	for _, glyph in ctx.glyph_cache {
		if glyph.texture != nil {
			sdl.DestroyTexture(glyph.texture)
		}
	}
	clear(&ctx.glyph_cache)
}

ui_context_create :: proc(screen_width, screen_height: f32) -> ^UI_Context {
	ctx := new(UI_Context)

	// Pass the SDL text measurement functions to the layout core
	ctx.layout = lc.layout_context_create(
		ui_text_width,
		ui_text_height,
		screen_width,
		screen_height,
	)

	ctx.stylesheet = make(map[Class]Style)
	ctx.fonts = make(map[u32]^ttf.Font)
	ctx.glyph_cache = make(map[Glyph_Key]Glyph)
	ctx.slice_cache = make(map[i32]^sdl.Texture)
	ctx.image_cache = make(map[u32]^sdl.Texture)

	return ctx
}

ui_context_destroy :: proc(ctx: ^UI_Context) {
	lc.layout_context_destroy(ctx.layout)
	clear_glyph_cache(ctx)
	delete(ctx.glyph_cache)

	// Purge GPU textures before destroying the map
	clear_texture_cache(ctx)
	for _, tex in ctx.slice_cache {
		sdl.DestroyTexture(tex)
	}
	delete(ctx.slice_cache)
	for _, tex in ctx.image_cache {
		if tex != nil do sdl.DestroyTexture(tex)
	}
	delete(ctx.image_cache)

	delete(ctx.stylesheet)
	delete(ctx.fonts)
	free(ctx)
}

ui_begin_frame :: proc(ctx: ^UI_Context, renderer: ^sdl.Renderer, screen_w, screen_h: i32) {
	// Note: Event processing and pointer state updates will go here next

	ctx.layout.screen_width = f32(screen_w)
	ctx.layout.screen_height = f32(screen_h)
	lc.begin_layout(ctx.layout)
}

ui_layout_tree :: proc(ctx: ^UI_Context) -> []^lc.Box {
	return ctx.layout.root_boxes[:]
}

ui_compute :: proc(ctx: ^UI_Context) {
	lc.end_layout(ctx.layout)
}


element_open :: proc(ctx: ^UI_Context, el_val: Element, loc := #caller_location) {
	// Allocate the element for this frame
	el := new(Element, lc.frame_allocator(ctx.layout))
	el^ = el_val

	// Auto-generate an ID based on the call site if one wasn't provided
	if el._box.id == 0 {
		loc_str := fmt.tprintf("%s:%d", loc.file_path, loc.line)
		el._box.id = lc.Box_ID(hash.fnv32(transmute([]byte)loc_str))
	}

	// Resolve cascading styles
	apply_styles(el, ctx)

	// Bind the styled element to the layout box
	el._box.user_data = el

	lc.box_open(ctx.layout, el._box, loc)
}

element_close :: proc(ctx: ^UI_Context) {
	lc.box_close(ctx.layout)
}
