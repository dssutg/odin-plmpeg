/* Implementation translation unit for the Odin binding (pl_mpeg.odin).
   Compile this into a static library with build.sh. pl_mpeg.h is resolved
   from the vendored sources in src/ via -Isrc. */

#include <stddef.h>
#include <stdio.h>

#define PL_MPEG_IMPLEMENTATION
#include "pl_mpeg.h"