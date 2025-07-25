#version 150

#moj_import <minecraft:fog.glsl>
#moj_import <minecraft:dynamictransforms.glsl>

uniform sampler2D Sampler0;

//uniform vec4 ColorModulator;
//uniform float FogRenderDistanceStart;
//uniform float FogRenderDistanceEnd;
//uniform vec4 FogColor;

in float sphericalVertexDistance;
in float cylindricalVertexDistance;
in vec4 vertexColor;
in vec4 lightMapColor;
in vec4 overlayColor;
in vec2 texCoord0;

out vec4 fragColor;

void main() {
    vec4 color;
    vec4 rawColor = texture(Sampler0, texCoord0);
    
    
    int checkAlpha = int(rawColor.a * 255);
    
    if (checkAlpha == 254) {

        color = rawColor;

    } else if (checkAlpha == 130) {

        color = mix(rawColor, rawColor * vertexColor * ColorModulator, 0.5);
    
    } else {
        
        color = rawColor * vertexColor * ColorModulator;

        #ifndef NO_OVERLAY
        color.rgb = mix(overlayColor.rgb, color.rgb, overlayColor.a);
        #endif

        #ifndef EMISSIVE
        color *= lightMapColor;
        #endif
    }
    
#ifdef ALPHA_CUTOUT
    if (color.a < ALPHA_CUTOUT) {
        discard;
    }
#endif

    //fragColor = linear_fog(color, vertexDistance, FogRenderDistanceStart, FogRenderDistanceEnd, FogColor);
    fragColor = apply_fog(color, sphericalVertexDistance, cylindricalVertexDistance, FogEnvironmentalStart, FogEnvironmentalEnd, FogRenderDistanceStart, FogRenderDistanceEnd, FogColor);
}
