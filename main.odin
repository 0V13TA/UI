package main

import "core:fmt"
import sdl "vendor:sdl2"
import ttf "vendor:sdl2/ttf"

main :: proc() {
	// 1. Initialize SDL and SDL_ttf
	sdl.Init({.VIDEO})
	defer sdl.Quit()

	if ttf.Init() != 0 {
		fmt.printfln("TTF Init failed: %s", sdl.GetError())
		return
	}
	defer ttf.Quit()

	window := sdl.CreateWindow(
		"SDL2 Text Caching Test",
		sdl.WINDOWPOS_CENTERED,
		sdl.WINDOWPOS_CENTERED,
		600,
		400,
		{.SHOWN},
	)
	defer sdl.DestroyWindow(window)

	renderer := sdl.CreateRenderer(window, -1, {.ACCELERATED, .PRESENTVSYNC})
	defer sdl.DestroyRenderer(renderer)

	// 2. Load the font (using the path from your UI_8.zip)
	font := ttf.OpenFont("font/CaacupeOne-Regular.ttf", 32)
	if font == nil {
		fmt.printfln("Failed to load font: %s", ttf.GetError())
		return
	}
	defer ttf.CloseFont(font)

	// 3. CACHING: Render the string to a Surface (CPU), then to a Texture (GPU)
	text_str := cstring("Hardware Cached Text Rendering!")
	text_color := sdl.Color {
		r = 255,
		g = 255,
		b = 255,
		a = 255,
	} 	// White

	// Blended gives the highest quality anti-aliasing in SDL_ttf
	text_surface := ttf.RenderText_Blended(font, text_str, text_color)
	defer sdl.FreeSurface(text_surface)

	text_texture := sdl.CreateTextureFromSurface(renderer, text_surface)
	defer sdl.DestroyTexture(text_texture)

	// Save the dimensions so we know how big to draw the rect
	dest_rect := sdl.Rect {
		x = 50,
		y = 150,
		w = text_surface.w,
		h = text_surface.h,
	}

	running := true
	for running {
		event: sdl.Event
		for sdl.PollEvent(&event) {
			#partial switch event.type {
			case .QUIT:
				running = false
			}
		}

		// --- RENDER PASS ---
		sdl.SetRenderDrawColor(renderer, 30, 30, 30, 255) // Dark background
		sdl.RenderClear(renderer)

		// 4. Draw the cached texture. This is virtually free for the GPU!
		sdl.RenderCopy(renderer, text_texture, nil, &dest_rect)

		sdl.RenderPresent(renderer)
	}
}
