#ifndef LBC_BH_TRACE_COUNT
#define LBC_BH_TRACE_COUNT 16
#endif

#include <minecraft:globals.glsl>
#include <lbc:black_hole_disk.glsl>
#include <lbc:black_hole_transfer.glsl>

// Lens the composited image. Original-pixel depth only clips foreground
// occluders; it never selects colour layers or reconstructs block geometry.
uniform sampler2D SceneSampler;
uniform sampler2D SceneDepthSampler;
layout(location = 0) in vec2 texCoord;
layout(location = 1) flat in mat4 holeInverseVP;
layout(location = 5) flat in mat4 holeVP;
layout(location = 9) flat in vec4 holeObjects[LBC_BH_TRACE_COUNT];
layout(location = 25) flat in uvec4 holeStyles[(LBC_BH_TRACE_COUNT + 3) / 4];
layout(location = 29) flat in uint holeMask;
layout(location = 0) out vec4 fragColor;

const float BH_REACH = 14.0;
const int BH_STEPS = 192;
#include <lbc:black_hole_gravity.glsl>

vec3 bhImageDirection(vec2 uv) {
    vec4 a = holeInverseVP * vec4(uv * 2.0 - 1.0, 0.25, 1.0);
    vec4 b = holeInverseVP * vec4(uv * 2.0 - 1.0, 0.75, 1.0);
    vec3 first = a.xyz / a.w, last = b.xyz / b.w;
    return normalize(dot(first,first) < dot(last,last) ? last - first : first - last);
}

vec2 bhImageMirror(vec2 uv) {
    vec2 halfTexel = 0.5 / vec2(textureSize(SceneSampler,0));
    return clamp(1.0 - abs(mod(uv,2.0) - 1.0),halfTexel,vec2(1.0)-halfTexel);
}

vec3 bhImageSample(vec2 uv) {
    vec2 source = bhImageMirror(uv);
    // Do not magnify the other effect's reserved control colour into scenery.
    if (all(lessThan(source * vec2(textureSize(SceneSampler,0)),vec2(4.5))) &&
        all(lessThanEqual(abs(ivec3(round(texelFetch(SceneSampler,ivec2(0),0).rgb*255.0))-
                             ivec3(72,82,25)),ivec3(1))))
        source = max(source,vec2(4.5)/vec2(textureSize(SceneSampler,0)));
    return textureLod(SceneSampler,source,0.0).rgb;
}

struct BHImageRay {
    vec2 uv;
    vec3 emission;
    float transmission;
};

float bhImageViewDepth(vec3 position) {
    return (holeVP * vec4(position,1.0)).w;
}

float bhImageSceneDepth(vec2 uv) {
    ivec2 size = textureSize(SceneDepthSampler,0);
    float depth = texelFetch(SceneDepthSampler,clamp(ivec2(uv*vec2(size)),ivec2(0),size-1),0).r;
    if (depth <= 1e-7 || depth >= 0.9999999) return 1e30;
#ifndef RENDERPEARL_DEPTH_IS_ZERO_TO_ONE
    depth = depth * 2.0 - 1.0;
#endif
    return 1.0 / (holeInverseVP[2][3]*depth + holeInverseVP[3][3]);
}

float bhImageLensDepth(vec3 direction) {
    float nearest = 1e30;
    for (int i=0;i<LBC_BH_TRACE_COUNT && (holeMask >> uint(i)) != 0u;i++) {
        vec4 hole = holeObjects[i];
        float along = dot(hole.xyz,direction);
        float depth = bhImageViewDepth(hole.xyz);
        vec3 offset = hole.xyz - direction * along;
        float reach = hole.w * BH_REACH;
        if (along <= 0.0 || depth <= 0.0 || dot(offset,offset) > reach*reach) continue;
        nearest = min(nearest,max(0.0,depth-hole.w));
    }
    // A nearby hole behind the camera can still lens the outward view.
    return nearest > 1e25 ? 0.0 : nearest;
}

BHImageRay bhImageTrace(vec2 uv, vec3 direction, float pixelAngle, float sceneDepth) {
    BHImageRay result = BHImageRay(uv,vec3(0.0),1.0);
    float entry = bhEntry(vec3(0.0),direction);
    if (entry > 1e25) return result;
    vec3 position = direction * entry;
    vec3 velocity = direction;
    bool escaped = false;
    bool occluded = bhImageViewDepth(position) >= sceneDepth;
    for (int step=0;step<BH_STEPS;step++) {
        float dt;
        bool captured,nearHorizon;
        vec3 acceleration = bhField(position,velocity,dt,captured,nearHorizon);
        if (captured) {
            if (!occluded) result.transmission = 0.0;
            return result;
        }
        if (dt > 1e25) {
            float nextEntry = bhEntry(position,normalize(velocity));
            if (nextEntry > 1e25) {
                escaped = true;
                break;
            }
            position += normalize(velocity) * nextEntry;
            occluded = occluded || bhImageViewDepth(position) >= sceneDepth;
            continue;
        }
        vec3 halfVelocity = velocity + acceleration * (0.5 * dt);
        vec3 nextPosition = position + halfVelocity * dt;
        float horizon = nearHorizon ? bhHorizonSegment(position,nextPosition) : 2.0;
        if (horizon <= 1.0) nextPosition = mix(position,nextPosition,horizon);
        float startDepth = bhImageViewDepth(position);
        float endDepth = bhImageViewDepth(nextPosition);
        vec3 diskEnd = nextPosition;
        // Clip emission against one foreground plane from the original pixel.
        // There are no further depth reads along the curved ray.
        if (endDepth > sceneDepth && startDepth < sceneDepth)
            diskEnd = mix(position,nextPosition,(sceneDepth-startDepth)/(endDepth-startDepth));
        for (int i=0;i<LBC_BH_TRACE_COUNT && (holeMask >> uint(i)) != 0u;i++) {
            if (!occluded && startDepth < sceneDepth && bhDisk(i))
                bhAccretion(i,position,diskEnd,normalize(halfVelocity),pixelAngle,
                            result.emission,result.transmission);
        }
        occluded = occluded || max(startDepth,endDepth) >= sceneDepth;
        if (horizon <= 1.0) {
            if (!occluded) result.transmission = 0.0;
            return result;
        }
        if (result.transmission < 0.002) {
            result.transmission = 0.0;
            return result;
        }
        float ignoredStep;
        bool ignoredCapture,ignoredHorizon;
        vec3 nextAcceleration = bhField(nextPosition,halfVelocity,ignoredStep,ignoredCapture,ignoredHorizon);
        velocity = halfVelocity + nextAcceleration * (0.5 * dt);
        position = nextPosition;
    }
    if (!escaped) {
        float nearest = 1e30;
        for (int i=0;i<LBC_BH_TRACE_COUNT && (holeMask >> uint(i)) != 0u;i++)
            nearest = min(nearest,length(position-holeObjects[i].xyz)/holeObjects[i].w);
        if (nearest < 2.0) {
            if (!occluded) result.transmission = 0.0;
            return result;
        }
    }
    // Keep foreground walls/hand intact. Depth affects visibility only;
    // background colour still comes from the complete composited image.
    if (sceneDepth < bhImageLensDepth(direction)) return result;
    // The final direction addresses the complete image, including its
    // translucent layers. Never choose a different layer from depth texels.
    vec4 projected = holeVP * vec4(normalize(velocity),0.0);
    float safeW = (projected.w < 0.0 ? -1.0 : 1.0) * max(abs(projected.w),0.002);
    result.uv = projected.xy / safeW * 0.5 + 0.5;
    return result;
}

void main() {
    ivec2 size = textureSize(SceneSampler,0);
    ivec2 pixel = clamp(ivec2(gl_FragCoord.xy),ivec2(0),size-1);
    vec4 original = texelFetch(SceneSampler,pixel,0);
    fragColor = original;
    if (lbc_bh_carrier_pixel(pixel,size)) fragColor.a = 1.0;
    if (holeMask == 0u) return;
    vec2 uv = gl_FragCoord.xy / vec2(size);
    vec3 direction = bhImageDirection(uv);
    float pixelAngle = max(length(bhImageDirection(uv+vec2(1.0/float(size.x),0.0))-direction),
                           length(bhImageDirection(uv+vec2(0.0,1.0/float(size.y)))-direction));
    BHImageRay ray = bhImageTrace(uv,direction,pixelAngle,bhImageSceneDepth(uv));
    // Derivatives are evaluated by every lane, including captured/untouched
    // rays. Filter compressed repeats without changing output resolution.
    vec2 dx = dFdx(ray.uv), dy = dFdy(ray.uv);
    vec2 footprint = max(abs(dx),abs(dy)) * vec2(size);
    vec3 background;
    if (max(footprint.x,footprint.y) > 1.5) {
        background = (bhImageSample(ray.uv + 0.25*(dx+dy)) +
                      bhImageSample(ray.uv + 0.25*(dx-dy)) +
                      bhImageSample(ray.uv + 0.25*(-dx+dy)) +
                      bhImageSample(ray.uv - 0.25*(dx+dy))) * 0.25;
    } else background = bhImageSample(ray.uv);
    float peak = max(ray.emission.r,max(ray.emission.g,ray.emission.b));
    fragColor.rgb = ray.emission / (1.0 + peak) + ray.transmission * background;
    if (all(equal(ray.uv,uv)) && peak == 0.0 && ray.transmission == 1.0)
        fragColor.rgb = original.rgb;
    if (all(lessThan(pixel,ivec2(4))) &&
        all(lessThanEqual(abs(ivec3(round(original.rgb*255.0))-ivec3(72,82,25)),ivec3(1))))
        fragColor.rgb = original.rgb;
}
