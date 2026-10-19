#version 330
#extension GL_ARB_separate_shader_objects : require

#define LBC_BH_MIRRORED_VOLUMES
#ifndef LBC_BH_INLINE_GEOMETRY
#define LBC_BH_CACHED_GEOMETRY
#endif
#define LBC_BH_TRACE_COUNT 2
#include <lbc:black_hole_trace.glsl>
