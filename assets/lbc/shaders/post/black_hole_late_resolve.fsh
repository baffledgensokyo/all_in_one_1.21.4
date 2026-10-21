#version 330
#extension GL_ARB_separate_shader_objects : require

#define LBC_BH_PACKED_ALPHA
#define LBC_BH_FAR_MAP_RESOLVE
#include <lbc:black_hole_transfer.glsl>
#include <lbc:black_hole_resolve.glsl>
