#include <lbc:nuclear_data.glsl>
layout(location = 0) in vec2 texCoord;
layout(location = 1) flat in mat4 nuclearInverseVP;
#ifdef LBC_NUCLEAR_MANY
#define LBC_NUCLEAR_TRACE_COUNT 16
uniform sampler2D NuclearDataSampler;
layout(location = 5) flat in uvec4 nuclearRows[4];
#else
#define LBC_NUCLEAR_TRACE_COUNT 4
layout(location = 5) flat in vec4 nuclearObjects[4];
layout(location = 9) flat in mat3 nuclearRotations[4];
layout(location = 21) flat in vec4 nuclearAges;
layout(location = 23) flat in vec4 nuclearSeeds;
layout(location = 24) flat in mat4 nuclearVP;
layout(location = 28) flat in vec4 nuclearFades;
#endif
layout(location = 22) flat in int nuclearCount;

struct NuclearObject {
    vec4 sphere;
    mat3 rotation;
    float age;
    float fade;
    float seed;
};
#ifdef LBC_NUCLEAR_MANY
float nuclearObjectFloat(int field,int row) {
    uvec4 b=uvec4(round(texelFetch(NuclearDataSampler,ivec2(field,row),0)*255.0));
    return uintBitsToFloat(b.x|(b.y<<8u)|(b.z<<16u)|(b.w<<24u));
}
#endif
NuclearObject nuclearGetObject(int i) {
#ifdef LBC_NUCLEAR_MANY
    int row=int(nuclearRows[i/4][i%4]);
    NuclearObject object;
    object.sphere=vec4(nuclearObjectFloat(60,row),nuclearObjectFloat(61,row),
                       nuclearObjectFloat(62,row),nuclearObjectFloat(63,row));
    for(int j=0;j<9;j++)object.rotation[j/3][j%3]=nuclearObjectFloat(64+j,row);
    object.age=nuclearObjectFloat(73,row);
    object.fade=nuclearObjectFloat(74,row);
    object.seed=nuclearObjectFloat(75,row);
    return object;
#else
    return NuclearObject(nuclearObjects[i],nuclearRotations[i],nuclearAges[i],nuclearFades[i],nuclearSeeds[i]);
#endif
}

vec3 nuclearUnproject(vec2 ndc, float depth) {
    vec4 p = nuclearInverseVP * vec4(ndc, depth, 1.0);
    return p.xyz / p.w;
}
float nuclearDepthDistance(sampler2D depthSampler, vec2 uv) {
    float d = texture(depthSampler, uv).r;
#ifndef RENDERPEARL_DEPTH_IS_ZERO_TO_ONE
    d = d * 2.0 - 1.0;
#endif
    vec4 p = nuclearInverseVP * vec4(uv * 2.0 - 1.0, d, 1.0);
    return abs(p.w) > 1e-7 ? length(p.xyz / p.w) : 1e20;
}
