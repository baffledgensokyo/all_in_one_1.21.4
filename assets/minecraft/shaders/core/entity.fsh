#version 330

#moj_import <minecraft:fog.glsl>
#moj_import <minecraft:dynamictransforms.glsl>

uniform sampler2D Sampler0;

//uniform vec4 ColorModulator;
//uniform float FogRenderDistanceStart;
//uniform float FogRenderDistanceEnd;
//uniform vec4 FogColor;

in float sphericalVertexDistance;
in float cylindricalVertexDistance;
#ifdef PER_FACE_LIGHTING
in vec4 vertexPerFaceColorBack;
in vec4 vertexPerFaceColorFront;
#else
in vec4 vertexColor;
#endif
in vec4 lightMapColor;
in vec4 overlayColor;
in vec2 texCoord0;

out vec4 fragColor;

void main() {
    bool bypassFog = false;
    vec4 color;
    vec4 rawColor = texture(Sampler0, texCoord0);
    
    
    int checkAlpha = int(rawColor.a * 255);
    
    if (checkAlpha == 254) {

        color = rawColor;
        bypassFog = true;

    } else if (checkAlpha == 130) {
#ifdef PER_FACE_LIGHTING
        vec4 lightingColor = gl_FrontFacing ? vertexPerFaceColorFront : vertexPerFaceColorBack;
        color = mix(rawColor, rawColor * lightingColor * ColorModulator, 0.5);
#else
        color = mix(rawColor, rawColor * vertexColor * ColorModulator, 0.5);
#endif
    
    } else {
#ifdef PER_FACE_LIGHTING
        vec4 lightingColor = gl_FrontFacing ? vertexPerFaceColorFront : vertexPerFaceColorBack;
        color = rawColor * lightingColor * ColorModulator;
#else
        color = rawColor * vertexColor * ColorModulator;
#endif

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
    fragColor = bypassFog ? color : apply_fog(color, sphericalVertexDistance, cylindricalVertexDistance, FogEnvironmentalStart, FogEnvironmentalEnd, FogRenderDistanceStart, FogRenderDistanceEnd, FogColor);
    //fragColor = apply_fog(color, sphericalVertexDistance, cylindricalVertexDistance, FogEnvironmentalStart, FogEnvironmentalEnd, FogRenderDistanceStart, FogRenderDistanceEnd, FogColor);
}
