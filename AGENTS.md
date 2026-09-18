# AGENTS.md

Guidance for AI agents working in this repository.

## What this is

An Odin binding for [PL_MPEG](https://github.com/phoboslab/pl_mpeg) (MIT), an
MPEG-PS demuxer plus MPEG1 video / MP2 audio decoder. The upstream C library
is vendored **untouched** in `src/`, which has its own git history.

> Do not modify anything under `src/`.

## Build

Build the static library that the binding links against, then verify with a
small Odin app:

```sh
./build.sh        # Linux/macOS -> libplmpeg.a
build.bat         # Windows    -> libplmpeg.a
```

- Output path may be given as the first argument.
- `CC`, `AR`, `CFLAGS` env vars are honored (`build.sh`).
- `build.bat` auto-detects MSVC (`cl` -> produces a `.lib`) vs MinGW
  (`gcc`/`ar` -> `.a`).

## Verify

There is no test suite. Manually verify that the binding compiles, links and
decodes. A working pattern:

```sh
./build.sh
mkdir -p test_app
# test_app/main.odin imports the package and calls plmpeg.create_with_filename
# + plmpeg.decode_video on an .mpg clip.
odin vet .   # type-check/lint a test app that imports the binding
```

`test_app/main.odin` uses a collection pointing at the parent of this repo and
a linker flag pointing at the archive:

```sh
odin run . \
  -collection:plm=/path/to/repo-parent \
  -extra-linker-flags:"-L/path/to/this/repo -lplmpeg" \
  -- clip.mpg
```

Generate a compatible clip when needed:

```sh
ffmpeg -f lavfi -i testsrc=duration=2:size=160x128 -f lavfi -i \
  sine=frequency=440:duration=2 -c:v mpeg1video -q:v 0 -c:a mp2 -b:a 128k \
  -f mpeg clip.mpg
```

Renamed procs only fail at link time, so always rebuild + rerun after touching
`pl_mpeg.odin`.

## Layout

- `pl_mpeg.odin` — the binding, package `plmpeg`
- `pl_mpeg_odin.c` — C translation unit: `PL_MPEG_IMPLEMENTATION` + the std
  headers that `pl_mpeg.h` needs before it
- `build.sh`, `build.bat` — build the library
- `src/` — vendored upstream pl_mpeg sources (do not modify)
- `README.md` — binding usage; keep pl_mpeg internals out of it

## Conventions

- Names are drop-in, namespace-free: the C `plm_` prefix and `_t` suffix are
  removed since package `plmpeg` already scopes them.
- Types are PascalCase (`Plm`, `Buffer`, `Frame`, `Samples`, `Packet`); procs
  are snake_case (`decode`, `create_with_filename`, `buffer_write`); constants
  are PascalCase (`Packet_Video_1`, `Audio_Samples_Per_Frame`).
- Foreign procs live in `foreign lib` blocks and are declared with
  `@(link_prefix = "plm_")` so the renamed Odin procs still bind the C
  symbols (every C symbol starts with `plm_`).
- The library is imported as `foreign import lib "system:plmpeg"`, so the
  archive must stay named `libplmpeg.a` (or `libplmpeg.lib`).
- Keep the binding a thin declaration layer: no state, globals or helper procs
  in `pl_mpeg.odin` unless they're needed by the binding itself.

## Gotchas

- `pl_mpeg.h` includes only `<stdint.h>`; `<stddef.h>` and `<stdio.h>` must be
  included before it (already done in `pl_mpeg_odin.c`).
- Struct field names follow the C header exactly (ABI positional); only types,
  procs and constants were renamed.
- Do not edit or reformat `src/`; treat it as an external dependency.