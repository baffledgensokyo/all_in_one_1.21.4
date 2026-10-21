#include <minecraft:globals.glsl>
#include <lbc:nuclear_inputs.glsl>
#include <lbc:nuclear_volume.glsl>
uniform sampler2D SceneDepthSampler;
#include <lbc:nuclear_trace.glsl>
layout(location = 0) out vec4 fragColor;

void main() {
    // Only radiance/transmittance, NEVER an early copy of world RGB.
    fragColor = vec4(0.0,0.0,0.0,1.0);
    if (nuclearCount == 0) return;
    if (any(greaterThanEqual(gl_FragCoord.xy,ceil(ScreenSize*0.5)))) return;
    vec2 uv = min((gl_FragCoord.xy*2.0)/ScreenSize,1.0-0.5/ScreenSize);
    vec2 ndc=uv*2.0-1.0;
    vec3 a=nuclearUnproject(ndc,0.25),b=nuclearUnproject(ndc,0.75);
    bool first=dot(a,a)<dot(b,b);
    vec3 origin=first?a:b, direction=normalize(first?b-a:a-b);
    float sceneRange=nuclearDepthDistance(SceneDepthSampler,uv);
    float sceneDistance=max(sceneRange-length(origin),0.0);
    fragColor=nuclearTrace(origin,direction,sceneDistance,gl_FragCoord.xy);
}
