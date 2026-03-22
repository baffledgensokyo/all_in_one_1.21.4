#version 330

#moj_import <minecraft:fog.glsl>
#moj_import <minecraft:dynamictransforms.glsl>
#moj_import <minecraft:projection.glsl>

in vec3 Position;
in vec4 Color;
in vec2 UV0;
in ivec2 UV2;

uniform sampler2D Sampler2;

out float sphericalVertexDistance;
out float cylindricalVertexDistance;
out vec4 vertexColor;
out vec2 texCoord0;

bool isColorNear(ivec3 color, ivec3 target, int tolerance) {
    ivec3 delta = abs(color - target);
    return all(lessThanEqual(delta, ivec3(tolerance)));
}

void main() {
    gl_Position = ProjMat * ModelViewMat * vec4(Position, 1.0);

    sphericalVertexDistance = fog_spherical_distance(Position);
    cylindricalVertexDistance = fog_cylindrical_distance(Position);
    vertexColor = Color * texelFetch(Sampler2, UV2 / 16, 0);
    texCoord0 = UV0;

    ivec3 checkColor = ivec3(round(Color.rgb * 255.0));

    if (isColorNear(checkColor, ivec3(78, 92, 36), 1) || isColorNear(checkColor, ivec3(170, 2, 2), 1)) {
        vertexColor = texelFetch(Sampler2, UV2 / 16, 0);
    } else if (isColorNear(checkColor, ivec3(19, 23, 9), 1) || isColorNear(checkColor, ivec3(21, 25, 10), 1) || isColorNear(checkColor, ivec3(74, 3, 15), 1) || isColorNear(checkColor, ivec3(25, 0, 0), 1)) {
        vertexColor = vec4(0.0);
    }
}
