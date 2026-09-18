# odin-plmpeg - Odin bindings for pl_mpeg

Odin bindings for [pl_mpeg](https://github.com/phoboslab/pl_mpeg), an
MIT-licensed single-file C library that demuxes MPEG Program Streams (`.mpg`)
and decodes MPEG1 video and MP2 audio.

The original pl_mpeg sources are vendored **untouched** in `src/`. This
repository only adds the Odin binding (`pl_mpeg.odin`) and the tooling to build
and link it.

## Requirements

- [Odin](https://odin-lang.org)
- a C compiler (`cc`) and archiver (`ar`)

## Building

`build.sh` compiles the vendored C implementation into a static library that
the binding links against:

```shell
./build.sh            # Linux/macOS: produces libplmpeg.a
build.bat             # Windows: produces libplmpeg.a
./build.sh <path>     # custom output path
```

On Windows, `build.bat` auto-detects MSVC (`cl` -> `.lib`) vs MinGW
(`gcc`/`ar` -> `.a`). Set `CC`, `AR` or `CFLAGS` to override the compiler,
archiver or flags:

```shell
CC=clang ./build.sh
```

## Using from Odin

The `plmpeg` package imports the library as `system:plmpeg`, so the linker
looks for `libplmpeg.a` in the standard search paths. Either install it there
or point the linker at its location:

```shell
odin build my_app.odin -extra-linker-flags:"-L<path> -lplmpeg"
```

```odin
package main

import plmpeg "..."
import "core:fmt"

video_cb :: proc "c" (self: ^plmpeg.Plm, frame: ^plmpeg.Frame, user: rawptr) {
	fmt.println("frame:", frame.width, "x", frame.height, "at", frame.time)
}

main :: proc() {
	plm := plmpeg.create_with_filename("video.mpg")
	defer plmpeg.destroy(plm)

	plmpeg.set_video_decode_callback(plm, video_cb, nil)

	for plmpeg.has_ended(plm) == 0 {
		plmpeg.decode(plm, 1.0 / 60.0)
	}
}
```

Audio works the same way through `plmpeg.set_audio_decode_callback` and
`plmpeg.Audio_Decode_Callback`. A full usage walkthrough with build, link and
decode examples lives in the header comment of `pl_mpeg.odin`.

## Converting video with ffmpeg

pl_mpeg only plays MPEG-1 video and MPEG-2 audio inside an MPEG Program
Stream (`.mpg`), so most source files need converting first.

The codec pair to target is MPEG-1 video (`-c:v mpeg1video`) and MPEG-1/2
Layer II audio (`-c:a mp2`), wrapped in an MPEG-PS container (`-f mpeg`):

```shell
ffmpeg -i input.mp4 -c:v mpeg1video -q:v 4 -c:a mp2 -b:a 192k -f mpeg output.mpg
```

Notes:

- `-q:v` sets MPEG-1 quality (2-31, lower is better; 4 is a good
  trade-off). `-q:v 0` lets ffmpeg pick the best quality.
- MPEG-1 does not support modern resolutions well; rescale to a small,
  normal-PAR size whose width and height are multiples of 16 (e.g.
  `-vf scale=256:192`). SBG/PAR flags and interlacing are not supported.
- Keep the audio bitrate at one of the standard MP2 rates (e.g. `32k`,
  `48k`, `56k`, `64k`, `128k`, `192k`, `256k`, `384k`).
- Any media (MKV, AVI, WebM, streams, etc.) can be used as input; ffmpeg
  converts and muxes it into the `.mpg` program stream.

Synthesize a quick test clip when you have no source footage:

```shell
ffmpeg -f lavfi -i testsrc=duration=2:size=160x128 -f lavfi -i \
  sine=frequency=440:duration=2 -c:v mpeg1video -q:v 0 -c:a mp2 -b:a 128k \
  -f mpeg clip.mpg
```

### Naming

The package name (`plmpeg`) already provides a namespace, so the C `plm_`
prefix and `_t` suffix are dropped from every identifier:

| C name | Odin name |
|---|---|
| `plm_create_with_filename` | `create_with_filename` |
| `plm_frame_t` | `Frame` |
| `plm_buffer_t` | `Buffer` |
| `plm_samples_t` | `Samples` |
| `plm_video_decode_callback` | `Video_Decode_Callback` |
| `PLM_DEMUX_PACKET_AUDIO_1` | `Packet_Audio_1` |

### Layout

```
pl_mpeg.odin    Odin binding (package plmpeg)
pl_mpeg_odin.c  C implementation translation unit for the binding
build.sh        builds libplmpeg.a (Linux/macOS)
build.bat       builds libplmpeg.a (Windows)
README.md       this file
AGENTS.md       guidance for AI agents
src/            vendored pl_mpeg sources (do not modify)
examples/
  plmpeg_and_sdl2/   minimal MPEG player using this binding and SDL2
```

## License

MIT. The vendored `src/` preserves the upstream pl_mpeg license.
