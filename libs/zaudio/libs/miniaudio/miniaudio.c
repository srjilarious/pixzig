/* pixzig addition: stb_vorbis gives miniaudio Ogg Vorbis decoding. Its header
   has to come before the miniaudio implementation, and its implementation
   after, per miniaudio's docs. */
#define STB_VORBIS_HEADER_ONLY
#include "stb_vorbis.c"

#define MINIAUDIO_IMPLEMENTATION
#include "miniaudio.h"

#undef STB_VORBIS_HEADER_ONLY
#include "stb_vorbis.c"
