package renderer

import "core:c"
import avcodec "../ffmpeg-bindings/avcodec"
import avformat "../ffmpeg-bindings/avformat"
import avutil "../ffmpeg-bindings/avutil"
import swscale "../ffmpeg-bindings/swscale"
import types "../ffmpeg-bindings/types"
import "core:fmt"
import "core:slice"
import "core:strings"
import "core:sync"
import "core:thread"
import "core:time"
import sdl "vendor:sdl2"

Video_Frame :: struct {
	y_plane, u_plane, v_plane: []u8,
	y_pitch, u_pitch, v_pitch: i32,
	pts:                       f64,
}

Video_Player :: struct {
	texture:          ^sdl.Texture,
	width:            i32,
	height:           i32,
	is_playing:       bool,
	playback_time:    f64,

	// --- FFmpeg State ---
	file_path:        string,
	fmt_ctx:          ^types.Format_Context,
	codec_ctx:        ^types.Codec_Context,
	video_stream_idx: i32,
	sws_ctx:          ^types.Sws_Context,

	// --- Threading ---
	decoder_thread:   ^thread.Thread,
	frame_queue:      [dynamic]Video_Frame,
	queue_mutex:      sync.Mutex,
	quit_flag:        bool,
}

video_player_init :: proc(renderer: ^sdl.Renderer, path: string) -> ^Video_Player {
	player := new(Video_Player)
	player.file_path = path
	player.is_playing = true
	player.frame_queue = make([dynamic]Video_Frame)

	c_path := strings.clone_to_cstring(path)
	defer delete(c_path)

	// 1. Open the file container
	if avformat.open_input(&player.fmt_ctx, c_path, nil, nil) < 0 {
		fmt.printfln("FFMPEG ERROR: Could not open file: %s", path)
		return nil
	}

	// 2. Read packets to get stream information
	if avformat.find_stream_info(player.fmt_ctx, nil) < 0 {
		fmt.println("FFMPEG ERROR: Could not find stream info")
		return nil
	}

	// 3. Find the first video stream
	player.video_stream_idx = -1
	codec: ^types.Codec = nil

	// Convert C-array to Odin slice for safe iteration
	streams := slice.from_ptr(player.fmt_ctx.streams, int(player.fmt_ctx.nb_streams))

	for stream, i in streams {
		if stream.codecpar.codec_type == .Video {
			player.video_stream_idx = i32(i)
			codec = avcodec.find_decoder(stream.codecpar.codec_id)
			break
		}
	}

	if player.video_stream_idx == -1 || codec == nil {
		fmt.println("FFMPEG ERROR: No video stream or unsupported codec found")
		return nil
	}

	// 4. Allocate and open the codec context
	player.codec_ctx = avcodec.alloc_context3(codec)
	avcodec.parameters_to_context(
		player.codec_ctx,
		streams[player.video_stream_idx].codecpar,
	)

	if avcodec.open2(player.codec_ctx, codec, nil) < 0 {
		fmt.println("FFMPEG ERROR: Could not open codec")
		return nil
	}
    
	player.sws_ctx = swscale.getContext(
		player.codec_ctx.width,
		player.codec_ctx.height,
		player.codec_ctx.pix_fmt,
		player.codec_ctx.width,
		player.codec_ctx.height,
		types.Pixel_Format.YUV420P,
		2, // SWS_BILINEAR flag
		nil,
		nil,
		nil,
	)

	// 5. Create the GPU Texture using the detected dimensions
	player.width = player.codec_ctx.width
	player.height = player.codec_ctx.height

	player.texture = sdl.CreateTexture(
		renderer,
		sdl.PixelFormatEnum.IYUV,
		sdl.TextureAccess.STREAMING,
		player.width,
		player.height,
	)

	// 6. Spawn the worker thread
	player.decoder_thread = thread.create_and_start_with_data(player, ffmpeg_worker_thread)
	return player
}

video_player_update :: proc(player: ^Video_Player, dt: f64) {
	if !player.is_playing do return

	// Advance our UI playback clock
	player.playback_time += dt

	sync.lock(&player.queue_mutex)
	defer sync.unlock(&player.queue_mutex)

	if len(player.frame_queue) > 0 {
		// Check if the next frame in the queue is due to be shown
		next_frame := player.frame_queue[0]

		// If our UI clock has passed the frame's presentation timestamp (PTS)
		if player.playback_time >= next_frame.pts {

			// Push the decoded YUV planes directly to the GPU
			sdl.UpdateYUVTexture(
				player.texture,
				nil,
				raw_data(next_frame.y_plane),
				next_frame.y_pitch,
				raw_data(next_frame.u_plane),
				next_frame.u_pitch,
				raw_data(next_frame.v_plane),
				next_frame.v_pitch,
			)

			// Free the memory and remove it from the queue
			delete(next_frame.y_plane); delete(next_frame.u_plane); delete(next_frame.v_plane)
			ordered_remove(&player.frame_queue, 0)
		}
	}
}

video_player_destroy :: proc(player: ^Video_Player) {
	// Signal the thread to die, wait for it, then clean up memory
	player.quit_flag = true
	thread.join(player.decoder_thread)
	thread.destroy(player.decoder_thread)
	swscale.freeContext(player.sws_ctx)

	sdl.DestroyTexture(player.texture)
	delete(player.frame_queue)
}

@(private)
ffmpeg_worker_thread :: proc(data: rawptr) {
	player := cast(^Video_Player)data

	pkt: ^types.Packet = avcodec.packet_alloc()
	frame: ^types.Frame = avutil.frame_alloc()
	defer {
		avcodec.packet_free(&pkt)
		avutil.frame_free(&frame)
	}

	MAX_BUFFERED_FRAMES :: 30

	stream := player.fmt_ctx.streams[player.video_stream_idx]
	time_base := f64(stream.time_base.numerator) / f64(stream.time_base.denominator)

	for !player.quit_flag {
		// 1. Throttle decoding if UI thread falls behind
		sync.lock(&player.queue_mutex)
		queue_len := len(player.frame_queue)
		sync.unlock(&player.queue_mutex)

		if queue_len >= MAX_BUFFERED_FRAMES {
			time.sleep(time.Millisecond * 5)
			continue
		}

		// 2. Read the next packet
		if avformat.read_frame(player.fmt_ctx, pkt) < 0 do break
		defer avcodec.packet_unref(pkt)

		if pkt.stream_index != player.video_stream_idx do continue

		// 3. Send to Decoder
		if avcodec.send_packet(player.codec_ctx, pkt) == 0 {

			// 4. Receive all available uncompressed frames
			for avcodec.receive_frame(player.codec_ctx, frame) == 0 {
				pts_seconds := f64(frame.best_effort_timestamp) * time_base

				// YUV420P Math: U and V planes are exactly half the width and height of Y
				y_pitch := player.width
				u_pitch := player.width / 2
				v_pitch := player.width / 2

				new_frame := Video_Frame {
					y_plane = make([]u8, y_pitch * player.height),
					u_plane = make([]u8, u_pitch * (player.height / 2)),
					v_plane = make([]u8, v_pitch * (player.height / 2)),
					y_pitch = y_pitch,
					u_pitch = u_pitch,
					v_pitch = v_pitch,
					pts     = pts_seconds,
				}

				// 5. Setup destination arrays for SwsScale
				dst_data := [4][^]u8 {
					raw_data(new_frame.y_plane),
					raw_data(new_frame.u_plane),
					raw_data(new_frame.v_plane),
					nil,
				}
				dst_linesize := [4]c.int{y_pitch, u_pitch, v_pitch, 0}

				// 6. Scale and convert colors directly into our Odin slices!
        swscale.scale(
					player.sws_ctx,
					cast([^]^u8)&frame.data[0],
					&frame.linesize[0],
					0,
					player.height,
					cast([^]^u8)&dst_data[0],
					&dst_linesize[0],
				)

				sync.lock(&player.queue_mutex)
				append(&player.frame_queue, new_frame)
				sync.unlock(&player.queue_mutex)

				avutil.frame_unref(frame)
			}
		}
	}
}
