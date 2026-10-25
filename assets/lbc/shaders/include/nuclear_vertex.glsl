#include <lbc:nuclear_data.glsl>

#if defined(LBC_NUCLEAR_HEAT_MANY) || defined(LBC_NUCLEAR_MANY)
#define LBC_NUCLEAR_TRACE_COUNT 16
#else
#define LBC_NUCLEAR_TRACE_COUNT 4
#endif
uniform sampler2D NuclearDataSampler;
layout(location = 0) out vec2 texCoord;
#if !defined(LBC_NUCLEAR_HEAT) && !defined(LBC_NUCLEAR_MANY)
layout(location = 1) flat out mat4 nuclearInverseVP;
layout(location = 5) flat out vec4 nuclearObjects[LBC_NUCLEAR_TRACE_COUNT];
layout(location = 9) flat out mat3 nuclearRotations[LBC_NUCLEAR_TRACE_COUNT];
layout(location = 21) flat out vec4 nuclearAges;
layout(location = 23) flat out vec4 nuclearSeeds;
layout(location = 24) flat out mat4 nuclearVP;
layout(location = 28) flat out vec4 nuclearFades;

#else
#ifdef LBC_NUCLEAR_MANY
layout(location = 1) flat out mat4 nuclearInverseVP;
#else
mat4 nuclearInverseVP;
#endif
vec4 nuclearObjects[LBC_NUCLEAR_TRACE_COUNT];
mat3 nuclearRotations[LBC_NUCLEAR_TRACE_COUNT];
float nuclearAges[LBC_NUCLEAR_TRACE_COUNT];
float nuclearSeeds[LBC_NUCLEAR_TRACE_COUNT];
mat4 nuclearVP;
float nuclearFades[LBC_NUCLEAR_TRACE_COUNT];

#endif
#ifdef LBC_NUCLEAR_MANY
layout(location = 5) flat out uvec4 nuclearRows[4];
#endif
layout(location = 22) flat out int nuclearCount;

#ifdef LBC_NUCLEAR_HEAT
#include <minecraft:globals.glsl>
#include <lbc:nuclear_volume.glsl>
uniform sampler2D SceneDepthSampler;
layout(location = 1) flat out vec4 nuclearHeatCenters[LBC_NUCLEAR_TRACE_COUNT];
layout(location = 17) flat out vec4 nuclearHeatVisibilities[LBC_NUCLEAR_TRACE_COUNT/4];
float heatVisibility(vec3 p,float radius) {
    vec4 clip=nuclearVP*vec4(p,1.0);
    if(clip.w<=0.0)return 0.0;
    vec2 uv=clip.xy/clip.w*0.5+0.5;
    if(any(lessThan(uv,vec2(0.0)))||any(greaterThan(uv,vec2(1.0))))return 0.0;
    float d=textureLod(SceneDepthSampler,uv,0.0).r;
#ifndef RENDERPEARL_DEPTH_IS_ZERO_TO_ONE
    d=d*2.0-1.0;
#endif
    vec4 surface=nuclearInverseVP*vec4(uv*2.0-1.0,d,1.0);
    if(abs(surface.w)<1e-7)return 1.0;
    return smoothstep(-radius*0.2,radius*0.1,length(surface.xyz/surface.w)-length(p));
}
#endif

ivec3 nuclearBytes(ivec2 pixel) {
#if defined(LBC_NUCLEAR_PACKED_ALPHA) && !defined(LBC_EFFECT_HISTORY)
    int x = pixel.x * 3;
    return ivec3(round(vec3(texelFetch(NuclearDataSampler, ivec2(x, pixel.y), 0).a,
                           texelFetch(NuclearDataSampler, ivec2(x+1, pixel.y), 0).a,
                           texelFetch(NuclearDataSampler, ivec2(x+2, pixel.y), 0).a) * 255.0));
#else
    return ivec3(round(texelFetch(NuclearDataSampler, pixel, 0).rgb * 255.0));
#endif
}

bool nuclearHeader(int row) {
    return all(equal(nuclearBytes(ivec2(56, row)),
                     ivec3(78, 85, 75)));
}

float nuclearFloat(int field, int row, inout bool valid) {
    ivec3 lo = nuclearBytes(ivec2(field * 2, row));
    ivec3 hi = nuclearBytes(ivec2(field * 2 + 1, row));
    valid = valid && lo.b == 201 && hi.b == 202;
    uint bits = uint(lo.r) | (uint(lo.g) << 8u) | (uint(hi.r) << 16u) | (uint(hi.g) << 24u);
    float value = uintBitsToFloat(bits);
    valid = valid && !isnan(value) && !isinf(value);
    return value;
}

void main() {
    vec2 uv = vec2((gl_VertexIndex << 1) & 2, gl_VertexIndex & 2);
    gl_Position = vec4(uv * 2.0 - 1.0, 0.0, 1.0);
    texCoord = uv;
#ifdef LBC_NUCLEAR_COARSE
    vec2 fullSize = vec2(textureSize(NuclearDataSampler, 0));
    gl_Position.xy = (gl_Position.xy + 1.0) * ceil(fullSize / 2.0) / fullSize - 1.0;
#endif
    nuclearCount = 0;
#ifdef LBC_NUCLEAR_HEAT
    for(int i=0;i<LBC_NUCLEAR_TRACE_COUNT;i++)nuclearHeatCenters[i]=vec4(0.0);
    for(int i=0;i<LBC_NUCLEAR_TRACE_COUNT/4;i++)nuclearHeatVisibilities[i]=vec4(0.0);
#endif
    nuclearInverseVP = mat4(1.0);
    nuclearVP = mat4(1.0);
    for (int i = 0; i < LBC_NUCLEAR_TRACE_COUNT; i++) {
        nuclearAges[i]=0.0;nuclearSeeds[i]=0.0;nuclearFades[i]=1.0;
        nuclearObjects[i] = vec4(0.0);
        nuclearRotations[i] = mat3(1.0);
    }
    ivec2 size = textureSize(NuclearDataSampler, 0);
    if (size.x < 57 || size.y < 2 * (LBC_NUCLEAR_FIRST_ROW + LBC_NUCLEAR_COUNT)) return;
    for (int slot = 0; slot < LBC_NUCLEAR_COUNT; slot++) {
      for (int replica = 0; replica < 2; replica++) {
        int row = replica == 0 ? LBC_NUCLEAR_FIRST_ROW + slot : size.y - 1 - LBC_NUCLEAR_FIRST_ROW - slot;
        if (!nuclearHeader(row)) continue;
        bool valid = true;
        vec3 p[4];
        for (int i = 0; i < 4; i++) {
            for (int axis = 0; axis < 3; axis++) p[i][axis] = nuclearFloat(i * 3 + axis, row, valid);
        }
        mat4 invVP;
        for (int i = 0; i < 16; i++) invVP[i / 4][i % 4] = nuclearFloat(12 + i, row, valid);
        vec3 x = p[1] - p[0], y = p[2] - p[0], z = p[3] - p[0];
        float radius = length(x), clock = length(y);
        if (!valid || radius < 0.01 || radius > 4096.0 || clock < 0.001 || length(z) < 0.01 ||
            abs(determinant(invVP)) < 1e-16) continue;
        mat3 rotation = mat3(normalize(x), normalize(y), normalize(z));
        if (abs(determinant(rotation)) < 0.9) continue;
        float age=clamp(clock-1.0,0.0,120.0),fade=1.0;
#ifdef LBC_EFFECT_HISTORY
        fade=texelFetch(NuclearDataSampler,ivec2(56,row),0).a;
#endif
        // Hidden/expired records remain in history for their lifecycle but
        // do not select the costly many-object route or trace any volume.
        if(age>=70.0||fade<=0.0)break;
        // Y scale is a clock in seconds + 1; X/Z set the physical size.
        if(nuclearCount<LBC_NUCLEAR_TRACE_COUNT) {
        nuclearObjects[nuclearCount] = vec4(p[0], radius);
        nuclearRotations[nuclearCount] = transpose(rotation);
        nuclearAges[nuclearCount] = age;
        nuclearSeeds[nuclearCount] = float(slot) * 13.71;
#ifdef LBC_EFFECT_HISTORY
        nuclearFades[nuclearCount] = fade;
#endif
        }
#ifdef LBC_NUCLEAR_MANY
        nuclearRows[nuclearCount/4][nuclearCount%4]=uint(row);
#endif
        nuclearInverseVP = invVP;
        nuclearCount++;
        break;
      }
    }
    if (nuclearCount > 0) nuclearVP = inverse(nuclearInverseVP);
#if defined(LBC_NUCLEAR_MANY) || defined(LBC_NUCLEAR_HEAT_MANY)
    if(nuclearCount<=4)gl_Position=vec4(4.0,4.0,0.0,1.0);
#else
    if(nuclearCount>4)gl_Position=vec4(4.0,4.0,0.0,1.0);
#endif
#ifdef LBC_NUCLEAR_HEAT
    for(int i=0;i<min(nuclearCount,LBC_NUCLEAR_TRACE_COUNT);i++) {
        float radius=nuclearObjects[i].w*NUCLEAR_WORLD_SCALE;
        float age=nuclearAges[i];
        vec3 dim=nuclearDimensions(age);
        vec3 up=transpose(nuclearRotations[i])*vec3(0.0,1.0,0.0);
        vec3 center=nuclearObjects[i].xyz+up*dim.y*radius*0.48;
        vec3 top=nuclearObjects[i].xyz+up*dim.y*radius;
        vec3 local=nuclearRotations[i]*-nuclearObjects[i].xyz/radius;
        float insideAir=(1.0-smoothstep(dim.x*0.8,dim.x+0.5,length(local.xz)))*
                        smoothstep(-0.3,0.1,local.y)*(1.0-smoothstep(dim.y+dim.z,dim.y+dim.z+0.8,local.y));
        float visible=max(max(heatVisibility(center,radius),heatVisibility(top,radius)),insideAir);
        float proximity=1.0/(1.0+length(nuclearObjects[i].xyz)/(radius*10.0));
        float envelope=1.0-smoothstep(66.0,70.0,age);
        // Atmospheric color/flash affects every viewing direction. Screen
        // visibility/depth gates only the local refractive haze below.
        float heat=proximity*envelope*exp(-age*0.028)*nuclearFades[i];
        float shock=exp(-pow((age-length(local)/4.8)/0.55,2.0));
        vec4 projected=nuclearVP*vec4(center,1.0);
        vec2 uv=projected.w>0.001?projected.xy/projected.w*0.5+0.5:vec2(0.5);
        nuclearHeatCenters[i]=vec4(uv,heat,shock);
        nuclearHeatVisibilities[i/4][i%4]=visible;
    }
#endif
}
