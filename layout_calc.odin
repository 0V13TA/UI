package layout_calc

import "core:fmt"
import "core:mem"
import "core:strings"

Layout_Context :: struct {
	allocator:     mem.Allocator,
	screen_width:  f32,
	screen_height: f32,
	text_width:    proc(text: string) -> f32,
	text_height:   proc(text: string, max_width: f32) -> f32,
	all_boxes:     [dynamic]^Box,
	parent_stack:  [dynamic]^Box,
	draw_buffer:   [dynamic]^Box, // Sorted buffer by depth
}

Direction :: enum {
	ROW,
	COLUMN,
	ROW_REVERSE,
	COLUMN_REVERSE,
}

Align :: enum {
	START,
	CENTER,
	END,
	STRETCH,
	SPACE_BETWEEN,
}

Side :: enum {
	TOP,
	RIGHT,
	BOTTOM,
	LEFT,
}

Overflow :: enum {
	HIDDEN, // No scrollbar hides content that overflows
	VISIBLE, // Overflows, does not resize anything and draws over parent
	SCROLL, // Scrollbar and whatnot
}

Fixed :: struct {
	value: f32,
}
Percent :: struct {
	value: f32,
}
ViewPercent :: struct {
	value: f32,
}
Grow :: struct {
	factor: f32,
}
Shrink :: struct {
	factor: f32,
}
Fit :: distinct bool

Sizing :: union {
	Fixed,
	Percent,
	ViewPercent,
	Grow,
	Shrink,
	Fit,
}

// Restricted union for min/max bounds (Only Fixed or ViewPercent)
Bound_Sizing :: union {
	Fixed,
	ViewPercent,
}

Position :: enum {
	STATIC,
	STICKY,
	ABSOLUTE,
	RELATIVE,
	FIXED,
}

Box_ID :: distinct string
Box :: struct {
	id:                    Box_ID,

	// Sizing Intent
	width:                 Sizing,
	height:                Sizing,
	min_width, min_height: Bound_Sizing,
	max_width, max_height: Bound_Sizing,

	// Spacing
	padding:               [4]f32, // [TOP, RIGHT, BOTTOM, LEFT]
	margin:                [4]f32,
	border:                [4]f32,
	gap:                   f32,

	// Flex Alignment
	direction:             Direction,
	justify_content:       Align,
	align_items:           Align,
	basis:                 f32,
	wrap:                  bool,

	// Position
	top:                   Maybe(f32), // Only useful if position != STATIC
	left:                  Maybe(f32),
	right:                 Maybe(f32),
	bottom:                Maybe(f32),
	position:              Position,

	// Depth
	z_index:               i32,

	// Content (Optional)
	text:                  string,

	// Scrolling
	offset_x:              f32,
	offset_y:              f32,
	overflow_x:            Overflow,
	overflow_y:            Overflow,

	// Hierarchy
	parent:                ^Box,
	children:              [dynamic]^Box,

	// Output Coordinates
	x, y:                  f32,
	computed_width:        f32,
	computed_height:       f32,
}

// --- Helper Functions ---

get_main_axis :: proc(dir: Direction, width, height: f32) -> (main, cross: f32) {
	switch dir {
	case .ROW, .ROW_REVERSE:
		return width, height
	case .COLUMN, .COLUMN_REVERSE:
		return height, width
	}
	return
}

set_main_axis :: proc(dir: Direction, main, cross: f32) -> (width, height: f32) {
	switch dir {
	case .ROW, .ROW_REVERSE:
		return main, cross
	case .COLUMN, .COLUMN_REVERSE:
		return cross, main
	}
	return
}

get_axis_margins :: proc(margins: [4]f32, dir: Direction) -> f32 {
	switch dir {
	case .ROW, .ROW_REVERSE:
		return margins[Side.LEFT] + margins[Side.RIGHT]
	case .COLUMN, .COLUMN_REVERSE:
		return margins[Side.TOP] + margins[Side.BOTTOM]
	}
	return 0.0
}

get_axis_padding :: proc(padding: [4]f32, dir: Direction) -> f32 {
	switch dir {
	case .ROW, .ROW_REVERSE:
		return padding[Side.LEFT] + padding[Side.RIGHT]
	case .COLUMN, .COLUMN_REVERSE:
		return padding[Side.TOP] + padding[Side.BOTTOM]
	}
	return 0.0
}

get_axis_border :: proc(border: [4]f32, dir: Direction) -> f32 {
	switch dir {
	case .ROW, .ROW_REVERSE:
		return border[Side.LEFT] + border[Side.RIGHT]
	case .COLUMN, .COLUMN_REVERSE:
		return border[Side.TOP] + border[Side.BOTTOM]
	}
	return 0.0
}

resolve_bound :: proc(bound: Bound_Sizing, viewport_dim: f32) -> f32 {
	switch v in bound {
	case Fixed:
		return v.value
	case ViewPercent:
		return (v.value / 100.0) * viewport_dim
	case:
		return -1
	}
	return -1
}

// --- Tree Building ---

new_box_from_config :: proc(
	ctx: ^Layout_Context,
	box_config: Box,
	loc := #caller_location,
) -> ^Box {
	box, err := new(Box, ctx.allocator)
	if err != nil do panic("Failed to allocate memory")
	box^ = box_config
	if box_config.id == "" {
		loc_str := fmt.tprintf("%s:%d", loc.file_path, loc.line)
		box.id = Box_ID(strings.clone(loc_str, ctx.allocator))
	}
	box.children = make([dynamic]^Box, 0, 4, ctx.allocator)
	box.computed_width = -1
	box.computed_height = -1
	return box
}

resolve_fixed_width :: proc(box: ^Box, viewport_dim: f32, parent_is_fit: bool) {
	is_row := box.direction == .ROW || box.direction == .ROW_REVERSE

	switch v in box.width {
	case Fixed:
		box.computed_width = v.value
	case ViewPercent:
		box.computed_width = (v.value / 100.0) * viewport_dim
	case Percent:
		if parent_is_fit || box.parent == nil {
			box.computed_width = 0.0
			// TODO: warn once here
		} else do box.computed_width = (v.value / 100) * box.parent.computed_width
	case Grow, Shrink:
		box.computed_width = 0.0
	case Fit:
		sum: f32 = 0.0
		for child in box.children {
			resolve_fixed_width(child, viewport_dim, true)
			if is_row {sum += child.computed_width} else {sum = max(sum, child.computed_width)}
		}
		gap_count := max(len(box.children) - 1, 0)
		if is_row do sum += f32(gap_count) * box.gap
		box.computed_width =
			sum +
			get_axis_padding(box.padding, box.direction) +
			get_axis_border(box.border, box.direction)
	case:
		box.computed_width = 0
	}

	if min_w := resolve_bound(box.min_width, viewport_dim); min_w >= 0 do box.computed_width = max(box.computed_width, min_w)
	if max_w := resolve_bound(box.max_width, viewport_dim); max_w >= 0 do box.computed_width = min(box.computed_width, max_w)

	#partial switch _ in box.width {
	case Fit:
	// Already Handled
	case:
		for child in box.children {
			resolve_fixed_width(child, viewport_dim, false)
		}
	}
}

box_open :: proc(ctx: ^Layout_Context, box_config: Box, loc := #caller_location) -> ^Box {
	box := new_box_from_config(ctx, box_config, loc)

	if len(ctx.parent_stack) > 0 {
		parent := ctx.parent_stack[len(ctx.parent_stack) - 1]
		append(&parent.children, box)
		box.parent = parent
	}

	append(&ctx.all_boxes, box)
	append(&ctx.parent_stack, box)

	return box
}

box_close :: proc(ctx: ^Layout_Context) {
	if len(ctx.parent_stack) > 0 {
		pop(&ctx.parent_stack)
	}
}

layout_context_create :: proc(
	text_width: proc(text: string) -> f32,
	text_height: proc(text: string, max_width: f32) -> f32,
	allocator := context.allocator,
) -> ^Layout_Context {
	ctx := new(Layout_Context, allocator)
	ctx.allocator = allocator
	ctx.text_width = text_width
	ctx.text_height = text_height
	ctx.all_boxes = make([dynamic]^Box, allocator)
	ctx.parent_stack = make([dynamic]^Box, allocator)
	ctx.draw_buffer = make([dynamic]^Box, allocator)
	return ctx
}

layout_reset :: proc(arena: ^mem.Arena, ctx: ^Layout_Context) {
	mem.arena_free_all(arena)
	ctx.all_boxes = make([dynamic]^Box, 0, 64, ctx.allocator)
	ctx.parent_stack = make([dynamic]^Box, 0, 16, ctx.allocator)
	ctx.draw_buffer = make([dynamic]^Box, 0, 64, ctx.allocator)
}

main :: proc() {
	layout_ctx := layout_context_create(nil, nil)

	{
		box_open(layout_ctx, Box{width = Fixed{value = 800}, height = Fixed{value = 600}})
		defer box_close(layout_ctx)

		{
			box_open(layout_ctx, Box{width = Percent{value = 50}, height = Fixed{value = 100}})
			defer box_close(layout_ctx)

			// Child content...
		}

		// Sibling box
		{
			box_open(layout_ctx, Box{width = Percent{value = 50}, height = Fixed{value = 100}})
			defer box_close(layout_ctx)

			// More child content...
		}
	}
}
