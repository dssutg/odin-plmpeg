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
import "core:fmt"
import plmpeg "..."

video_cb :: proc "c"(self: ^plmpeg.Plm, frame: ^plmpeg.Frame, user: rawptr) {
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

### Naming

The package name (`plmpeg`) already provides a namespace, so the C `plm_`
prefix and `_t` suffix are dropped from every identifier:

| C name                 | Odin name     |
| ---------------------- | ------------- |
| `plm_create_with_filename` | `create_with_filename` |
| `plm_frame_t`          | `Frame`       |
| `plm_buffer_t`         | `Buffer`      |
| `plm_samples_t`        | `Samples`     |
| `plm_video_decode_callback` | `Video_Decode_Callback` |
| `PLM_DEMUX_PACKET_AUDIO_1` | `Packet_Audio_1` |

### Layout

```
pl_mpeg.odin    Odin binding (package plmpeg)
pl_mpeg_odin.c  C implementation translation unit for the binding
build.sh        builds libplmpeg.a
src/            vendored pl_mpeg sources (do not modify)
```

## License

MIT. The vendored `src/` preserves the upstream pl_mpeg license.
