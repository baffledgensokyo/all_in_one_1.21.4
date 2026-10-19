#version 330
#extension GL_ARB_separate_shader_objects : require

#define LBC_BH_GEOMETRY_BUILD
#define LBC_BH_FULL_RESOLUTION
#include <lbc:black_hole_trace.glsl>

void main() {
    fragColor = vec4(0.0);
    if (holeMask == 0u) return;
    vec2 uv = gl_FragCoord.xy / vec2(textureSize(SceneDepthSampler,0));
    vec3 surface = bhObservedPosition(uv);
    if (any(greaterThan(abs(surface),vec3(1e19)))) return;
    vec3 world = surface - CameraOffset;
    for (int axis=0;axis<3;axis++) {
        vec3 interior = world;
        interior[axis] += surface[axis] < 0.0 ? -0.01 : 0.01;
        fragColor[axis] = bhBlockFaceValid(uv,axis,floor(interior)+CameraOffset) ? 1.0 : 0.0;
    }
}
