#include <minecraft:globals.glsl>
#include <lbc:nuclear_data.glsl>
uniform sampler2D SceneSampler;
// Keep visual intensity independent of geometric displacement.
const float NUCLEAR_HEAT_WAVE_SCALE=0.25;
const float NUCLEAR_HEAT_INTENSITY=1.15;
layout(location = 0) in vec2 texCoord;
layout(location = 22) flat in int nuclearCount;
layout(location = 1) flat in vec4 nuclearHeatCenters[LBC_NUCLEAR_TRACE_COUNT];
layout(location = 17) flat in vec4 nuclearHeatVisibilities[LBC_NUCLEAR_TRACE_COUNT/4];
layout(location = 0) out vec4 fragColor;
void main() {
    if(nuclearCount==0){fragColor=texture(SceneSampler,texCoord);return;}
    vec2 displacement=vec2(0.0);
    float warmth=0.0,flash=0.0;
    float time=GameTime*1200.0;
    for(int i=0;i<nuclearCount;i++) {
        vec4 heat=nuclearHeatCenters[i];
        if(heat.z<=0.0)continue;
        warmth=min(warmth+heat.z*(0.72+heat.w*0.45)*NUCLEAR_HEAT_INTENSITY,1.0);
        flash+=heat.z*heat.w*0.28*NUCLEAR_HEAT_INTENSITY;
        if(nuclearHeatVisibilities[i/4][i%4]<=0.0)continue;
        vec2 away=texCoord-heat.xy;
        vec2 radial=away/max(length(away),0.08);
        float wave=sin(length(away*vec2(ScreenSize.x/ScreenSize.y,1.0))*42.0-time*17.0);
        // Several noncommensurate frequencies avoid a regular rippling grid.
        vec2 turbulent=vec2(sin(texCoord.y*31.0+time*13.1)+sin(texCoord.x*17.0+texCoord.y*23.0-time*9.7)*0.45,
                            sin(texCoord.x*29.0-time*11.3)+sin(texCoord.y*19.0-texCoord.x*11.0+time*15.7)*0.4);
        displacement+=(turbulent*0.0045+radial*wave*(0.006+heat.w*0.015))*
                      heat.z*nuclearHeatVisibilities[i/4][i%4]*NUCLEAR_HEAT_WAVE_SCALE;
    }
    vec2 uv=clamp(texCoord+displacement,0.5/ScreenSize,1.0-0.5/ScreenSize);
    // ONE source lookup from the final, already composited world. There is
    // no blend with an unwarped world and no early scene saved in the smoke.
    vec4 scene=texture(SceneSampler,uv);
    vec3 hot=pow(max(scene.rgb,vec3(0.0)),vec3(0.89))*vec3(1.28,0.96,0.65);
    fragColor=vec4(mix(scene.rgb,hot,warmth*0.72)+vec3(1.0,0.68,0.29)*flash,scene.a);
}
