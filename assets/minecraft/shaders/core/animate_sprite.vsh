#version 330
#extension GL_ARB_separate_shader_objects : require

#include <minecraft:animation_sprite.glsl>
#include <lbc:atlas_glitch_directory.glsl>

layout(location = 0) out float fAnimationProgress;
layout(location = 1) out vec2 texCoord0;
layout(location = 2) flat out int lbcDirectoryTriangle;

const vec2[] positions = vec2[](
    vec2(0, 0), vec2(1, 0), vec2(0, 1),
    vec2(0, 1), vec2(1, 0), vec2(1, 1)
);
const vec2[] triangle = vec2[](vec2(0, 0), vec2(2, 0), vec2(0, 2));

void main() {
    int index = gl_VertexIndex & 7;
    vec2 atlasSize = abs(2.0 / vec2(ProjectionMatrix[0][0], ProjectionMatrix[1][1]));
    vec2 padding = vec2(UPadding, VPadding);
    vec2 frameSize = vec2(SpriteMatrix[0][0], SpriteMatrix[1][1]) / (1.0 + 2.0 * padding);
    bool directory = MipMapLevel == 0 && lbc_glitch_directory_atlas(ivec2(round(atlasSize)));
    bool entry = directory && lbc_glitch_directory_eligible(ivec4(0, 0, ivec2(round(frameSize))));
    lbcDirectoryTriangle = entry && index >= 3 ? 1 : 0;
    vec2 uv = positions[index];
    if (entry) uv = triangle[index % 3];
    if (lbcDirectoryTriangle != 0) {
        // The second triangle writes a sparse directory into the bottom
        // padding row. The first still covers the full original sprite quad.
        vec2 pixel = vec2(uv.x * atlasSize.x, atlasSize.y - 1.0 + uv.y);
        gl_Position = ProjectionMatrix * vec4(pixel, 0.0, 1.0);
    } else {
        gl_Position = ProjectionMatrix * SpriteMatrix * vec4(uv, 0.0, 1.0);
    }
    texCoord0 = uv + padding * (uv * 2.0 - 1.0);
    fAnimationProgress = (gl_VertexIndex >> 3) / 1000.0;
}
