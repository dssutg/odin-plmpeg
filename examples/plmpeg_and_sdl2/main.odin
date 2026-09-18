// plmpeg + SDL2 example - a minimal MPEG-PS (`.mpg`) player built on this
// package and SDL2's accelerated 2D renderer.
//
// It demonstrates:
//   - loading a file with plmpeg.create_with_filename
//   - probing the streams and reading dimensions/framerate/samplerate/duration
//   - the video and audio decode callbacks used with plmpeg.decode()
//   - uploading decoded YCrCb planes straight into an IYUV SDL texture
//   - handing decoded MP2 samples to the SDL audio device via QueueAudio
//   - seeking (arrow keys = +/-3s, drag with the mouse = scrub, loop enabled)
//
// Usage:
//
//	odin run . \
//	  -extra-linker-flags:"$(pkg-config --libs sdl2) -L../.. -lplmpeg" -- clip.mpg
//
// or just run ./build.sh clip.mpg. Generate a compatible clip with:
//
//	ffmpeg -f lavfi -i testsrc=duration=2:size=160x128 -f lavfi -i \
//	  sine=frequency=440:duration=2 -c:v mpeg1video -q:v 0 -c:a mp2 -b:a 128k \
//	  -f mpeg clip.mpg
//
// `vendor:sdl2` links against `system:SDL2` and `plmpeg` resolves relative to
// this file (two levels up, where pl_mpeg.odin lives).

package main

import plmpeg "../.."
import "core:c"
import "core:fmt"
import "core:os"
import "core:strings"
import sdl2 "vendor:sdl2"

// Reached by the decode callbacks, which are plain C callbacks with no other
// way to access the SDL objects.
texture: ^sdl2.Texture
audio_dev: sdl2.AudioDeviceID

// Upload the decoded Y/Cr/Cb planes of a video frame to the SDL texture.
video_cb :: proc "c" (self: ^plmpeg.Plm, frame: ^plmpeg.Frame, user: rawptr) {
	sdl2.UpdateYUVTexture(
		texture,
		nil,
		frame.y.data,
		c.int(frame.y.width),
		frame.cb.data,
		c.int(frame.cb.width),
		frame.cr.data,
		c.int(frame.cr.width),
	)
}

// Hand the decoded MP2 samples (interleaved stereo f32) over to the SDL
// audio device, which plays them asynchronously.
audio_cb :: proc "c" (self: ^plmpeg.Plm, samples: ^plmpeg.Samples, user: rawptr) {
	sdl2.QueueAudio(
		audio_dev,
		&samples.interleaved[0],
		u32(len(samples.interleaved) * size_of(f32)),
	)
}

exit_if_failed :: proc(cond: bool, message: string) {
	if cond {
		fmt.eprintln(message)
		os.exit(1)
	}
}

main :: proc() {
	if len(os.args) < 2 {
		fmt.eprintln("usage: plmpeg_and_sdl2 <video.mpg>")
		os.exit(1)
	}
	filename := os.args[1]

	plm := plmpeg.create_with_filename(strings.clone_to_cstring(filename, context.temp_allocator))
	defer plmpeg.destroy(plm)
	exit_if_failed(plm == nil, fmt.tprintf("couldn't open %q", filename))

	exit_if_failed(
		plmpeg.probe(plm, c.size_t(5 * 1024 * 1024)) == 0,
		fmt.tprintf("no MPEG video or audio streams found in %q", filename),
	)

	fmt.printfln(
		"opened %q - framerate: %v, samplerate: %v, duration: %v",
		filename,
		plmpeg.get_framerate(plm),
		plmpeg.get_samplerate(plm),
		plmpeg.get_duration(plm),
	)

	plmpeg.set_video_decode_callback(plm, video_cb, nil)
	plmpeg.set_audio_decode_callback(plm, audio_cb, nil)
	plmpeg.set_loop(plm, 1)
	plmpeg.set_audio_enabled(plm, 1)
	plmpeg.set_audio_stream(plm, 0)

	exit_if_failed(sdl2.Init(sdl2.INIT_VIDEO | sdl2.INIT_AUDIO) != 0, "SDL_Init failed")
	defer sdl2.Quit()

	if plmpeg.get_num_audio_streams(plm) > 0 {
		// SDL pulls from the queue we fill in the audio callback.
		spec: sdl2.AudioSpec
		spec.freq = c.int(plmpeg.get_samplerate(plm))
		spec.format = sdl2.AudioFormat(sdl2.AUDIO_F32SYS)
		spec.channels = 2
		spec.samples = 4096

		audio_dev = sdl2.OpenAudioDevice(nil, false, &spec, nil, {})
		exit_if_failed(audio_dev == 0, "failed to open audio device")

		sdl2.PauseAudioDevice(audio_dev, false)
		// Let enough audio accumulate to cover the device buffer.
		plmpeg.set_audio_lead_time(plm, f64(spec.samples) / f64(spec.freq))
	}
	// defer is block-scoped, so this must live in main's scope, not the
	// if-block above, or the device would be closed before playback starts.
	defer if audio_dev != 0 {
		sdl2.CloseAudioDevice(audio_dev)
	}

	width := plmpeg.get_width(plm)
	height := plmpeg.get_height(plm)

	window := sdl2.CreateWindow(
		"plmpeg + SDL2",
		sdl2.WINDOWPOS_CENTERED,
		sdl2.WINDOWPOS_CENTERED,
		width,
		height,
		sdl2.WINDOW_SHOWN | sdl2.WINDOW_RESIZABLE,
	)
	defer sdl2.DestroyWindow(window)
	exit_if_failed(window == nil, "failed to create window")

	// STREAMING texture in IYUV format; updated from the raw Y/Cr/Cb planes.
	renderer := sdl2.CreateRenderer(window, -1, sdl2.RENDERER_PRESENTVSYNC)
	defer sdl2.DestroyRenderer(renderer)
	exit_if_failed(renderer == nil, "failed to create renderer")

	// The renderer keeps the aspect ratio and centers the video when resized.
	texture = sdl2.CreateTexture(
		renderer,
		sdl2.PixelFormatEnum.IYUV,
		sdl2.TextureAccess.STREAMING,
		width,
		height,
	)
	defer sdl2.DestroyTexture(texture)
	exit_if_failed(texture == nil, "failed to create texture")

	sdl2.RenderSetLogicalSize(renderer, width, height)
	sdl2.SetHint(sdl2.HINT_RENDER_SCALE_QUALITY, "2")

	last_time := f64(sdl2.GetTicks()) / 1000.0
	wants_quit := false
	for !wants_quit {
		seek_to: f64 = -1

		ev: sdl2.Event
		for sdl2.PollEvent(&ev) {
			#partial switch ev.type {
			case .QUIT:
				wants_quit = true
			case .KEYUP:
				if ev.key.keysym.sym == .ESCAPE {
					wants_quit = true
				}
			case .KEYDOWN:
				// Seek 3 seconds forward/backward with the arrow keys.
				#partial switch ev.key.keysym.sym {
				case .RIGHT:
					seek_to = plmpeg.get_time(plm) + 3
				case .LEFT:
					seek_to = plmpeg.get_time(plm) - 3
				}
			}
		}

		sdl2.RenderClear(renderer)
		sdl2.RenderCopy(renderer, texture, nil, nil)
		sdl2.RenderPresent(renderer)

		// Elapsed time since the last frame, capped at 1/30s so window drags
		// don't cause a giant decode jump.
		now := f64(sdl2.GetTicks()) / 1000.0
		elapsed := min(now - last_time, 1.0 / 30.0)
		last_time = now

		// While the left mouse button is held, scrub through the whole file.
		mouse_x, mouse_y: c.int
		if sdl2.GetMouseState(&mouse_x, &mouse_y) & u32(sdl2.BUTTON(sdl2.BUTTON_LEFT)) != 0 {
			window_w, window_h: c.int
			sdl2.GetWindowSize(window, &window_w, &window_h)
			seek_to = plmpeg.get_duration(plm) * f64(mouse_x) / f64(window_w)
		}

		if seek_to >= 0 {
			if audio_dev != 0 {
				sdl2.ClearQueuedAudio(audio_dev)
			}
			plmpeg.seek(plm, seek_to, 0)
		} else {
			plmpeg.decode(plm, elapsed)
		}

		if plmpeg.has_ended(plm) != 0 {
			wants_quit = true
		}
	}
}
