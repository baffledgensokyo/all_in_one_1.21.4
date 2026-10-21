#version 330
#extension GL_ARB_separate_shader_objects : require

#define LBC_BH_FULL_RESOLUTION
#define LBC_BH_FAR_MAP
#define LBC_BH_CACHED_GEOMETRY
#define LBC_BH_TRACE_COUNT 2
#include <lbc:black_hole_trace.glsl>
