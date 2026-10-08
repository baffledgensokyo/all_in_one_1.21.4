#version 330
#extension GL_ARB_separate_shader_objects : require

#if !defined(IS_GUI) && !defined(IS_SEE_THROUGH)
#include <minecraft:fog.glsl>
#include <minecraft:sample_lightmap.glsl>
#endif

#include <minecraft:dynamictransforms.glsl>
#include <minecraft:projection.glsl>

layout(location = 0) in vec3 Position;
layout(location = 1) in vec4 Color;
layout(location = 2) in vec2 UV0;
#if !defined(IS_GUI) && !defined(IS_SEE_THROUGH)
layout(location = 3) in ivec2 UV2;
#endif

#if !defined(IS_GUI) && !defined(IS_SEE_THROUGH)
uniform sampler2D Sampler2;
layout(location = 0) out float sphericalVertexDistance;
layout(location = 1) out float cylindricalVertexDistance;
#endif

layout(location = 2) out vec4 vertexColor;
layout(location = 3) out vec2 texCoord0;

bool isColorNear(ivec3 color, ivec3 target, int tolerance) {
    ivec3 delta = abs(color - target);
    return all(lessThanEqual(delta, ivec3(tolerance)));
}

void main() {
    gl_Position = ProjMat * ModelViewMat * vec4(Position, 1.0);

#if !defined(IS_GUI) && !defined(IS_SEE_THROUGH)
    sphericalVertexDistance = fog_spherical_distance(Position);
    cylindricalVertexDistance = fog_cylindrical_distance(Position);
    vertexColor = Color * sample_lightmap(Sampler2, UV2);
#else
    vertexColor = Color;
#endif
    texCoord0 = UV0;

    ivec3 checkColor = ivec3(round(Color.rgb * 255.0));
    if (isColorNear(checkColor, ivec3(78, 92, 36), 1) || isColorNear(checkColor, ivec3(170, 2, 2), 1)) {
#if !defined(IS_GUI) && !defined(IS_SEE_THROUGH)
        vertexColor = sample_lightmap(Sampler2, UV2);
#else
        vertexColor = vec4(1.0);
#endif
    } else if (isColorNear(checkColor, ivec3(19, 23, 9), 1) || isColorNear(checkColor, ivec3(21, 25, 10), 1) || isColorNear(checkColor, ivec3(74, 3, 15), 1) || isColorNear(checkColor, ivec3(25, 0, 0), 1)) {
        vertexColor = vec4(0.0);
    }
}
