#version 330
#extension GL_ARB_separate_shader_objects : require

#define LBC_BH_PACKED_ALPHA
#define LBC_BH_COARSE_PASS
#define LBC_BH_MANY_OBJECTS
#include <lbc:black_hole_vertex.glsl>
