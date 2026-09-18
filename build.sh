#!/usr/bin/env sh
set -eu

# Builds the PL_MPEG library (vendored, untouched, in src/) into a static
# archive that the Odin binding in pl_mpeg.odin links against.
#
# Usage:
#   ./build.sh                 # produces libplmpeg.a
#   ./build.sh path/libfoo.a   # custom output path
#
# pl_mpeg.odin imports the library as "system:plmpeg", so the linker searches
# for libplmpeg.a (or libplmpeg.so) unless you pass the archive path directly.

cd "$(dirname "$0")"

CC="${CC:-cc}"
AR="${AR:-ar}"
CFLAGS="${CFLAGS:--O2}"
TARGET="${1:-libplmpeg.a}"

"$CC" $CFLAGS -Isrc -c pl_mpeg_odin.c -o pl_mpeg_odin.o
"$AR" rcs "$TARGET" pl_mpeg_odin.o
rm -f pl_mpeg_odin.o

printf 'built %s\n' "$TARGET"