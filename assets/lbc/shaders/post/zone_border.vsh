#version 330
#extension GL_ARB_separate_shader_objects : require

uniform sampler2D ZoneDataSampler;

layout(location = 0) out vec2 texCoord;
layout(location = 1) flat out mat4 zoneInverseViewProjection;
layout(location = 5) flat out mat3 zoneInverseBasis;
layout(location = 8) flat out vec3 zoneCenter;
layout(location = 9) flat out int zoneEnabled;
layout(location = 10) flat out float zoneOutsideDistance;

bool zoneHeader(int row) {
    return all(equal(ivec3(round(texelFetch(ZoneDataSampler, ivec2(56, row), 0).rgb * 255.0)),
                     ivec3(90, 66, 83)));
}

float zoneFloat(int field, int row, inout bool valid) {
    ivec3 low = ivec3(round(texelFetch(ZoneDataSampler, ivec2(field * 2, row), 0).rgb * 255.0));
    ivec3 high = ivec3(round(texelFetch(ZoneDataSampler, ivec2(field * 2 + 1, row), 0).rgb * 255.0));
    valid = valid && low.b == 201 && high.b == 202;
    uint bits = uint(low.r) | (uint(low.g) << 8u) | (uint(high.r) << 16u) | (uint(high.g) << 24u);
    float value = uintBitsToFloat(bits);
    valid = valid && !isnan(value) && !isinf(value);
    return value;
}

void main() {
    vec2 uv = vec2((gl_VertexIndex << 1) & 2, gl_VertexIndex & 2);
    gl_Position = vec4(uv * 2.0 - 1.0, 0.0, 1.0);
    texCoord = uv;
    zoneEnabled = 0;
    zoneOutsideDistance = -100000.0;
    zoneCenter = vec3(0.0);
    zoneInverseBasis = mat3(1.0);
    zoneInverseViewProjection = mat4(1.0);
    ivec2 size = textureSize(ZoneDataSampler, 0);
    if (size.x < 57) return;
    int row = zoneHeader(0) ? 0 : size.y - 1;
    if (!zoneHeader(row)) return;
    bool valid = true;
    vec3 references[4];
    for (int point = 0; point < 4; point++) {
        for (int axis = 0; axis < 3; axis++) {
            references[point][axis] = zoneFloat(point * 3 + axis, row, valid);
        }
    }
    mat4 invVP;
    for (int component = 0; component < 16; component++) {
        invVP[component / 4][component % 4] = zoneFloat(12 + component, row, valid);
    }
    mat3 basis = mat3(references[1] - references[0],
                      references[2] - references[0],
                      references[3] - references[0]);
    if (!valid || abs(determinant(basis)) < 1e-12 || abs(determinant(invVP)) < 1e-16) return;
    zoneCenter = references[0];
    zoneInverseBasis = inverse(basis);
    zoneInverseViewProjection = invVP;
    vec3 cameraLocal = zoneInverseBasis * -zoneCenter;
    float cameraRadius = length(cameraLocal.xz);
    if (cameraRadius > 1e-6) {
        vec3 radialGradient = transpose(zoneInverseBasis) *
            vec3(cameraLocal.x / cameraRadius, 0.0, cameraLocal.z / cameraRadius);
        zoneOutsideDistance = (cameraRadius - 1.0) / max(length(radialGradient), 1e-8);
    }
    zoneEnabled = 1;
}
