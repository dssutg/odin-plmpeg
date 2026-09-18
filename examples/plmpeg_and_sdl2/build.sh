#!/bin/sh
# Build libplmpeg.a when missing, then run the SDL2 example with Odin.
# Usage: ./build.sh <video.mpg>
set -e

cd "$(dirname "$0")"

if [ ! -f ../../libplmpeg.a ]; then
	../../build.sh
fi

sdl_flags="$(pkg-config --libs sdl2 2>/dev/null) -lSDL2"

odin run . \
	-extra-linker-flags:"$sdl_flags -L../.. -lplmpeg" \
	-- "${1:?usage: $0 <video.mpg>}"