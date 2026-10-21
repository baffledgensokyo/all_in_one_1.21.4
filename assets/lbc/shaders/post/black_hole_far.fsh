#version 330
#extension GL_ARB_separate_shader_objects : require

#define LBC_BH_FULL_RESOLUTION
#define LBC_BH_FAR_MAP
#define LBC_BH_CACHED_GEOMETRY
#include <lbc:black_hole_trace.glsl>
