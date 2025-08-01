#version 150

#moj_import <minecraft:fog.glsl>
#moj_import <minecraft:dynamictransforms.glsl>

uniform sampler2D Sampler0;

in float cylindricalVertexDistance;
in float sphericalVertexDistance;
in vec4 vertexColor;
in vec2 texCoord0;
in vec2 texCoord1;

out vec4 fragColor;

void main() {
    vec4 precolor = texture(Sampler0, texCoord0);
    vec4 color = precolor * vertexColor * ColorModulator;
    int alpha = int(precolor.a * 255);
    

    if (color.a < 0.1) {
        discard;
    }
    
    if (alpha == 254) {
        
        fragColor = vec4(precolor.rgb,1);
      
    } else if (alpha == 130) {
        
        fragColor = vec4(precolor.rgb,0.5);
        
    } else { 
        
        //fragColor = linear_fog(color, vertexDistance, FogRenderDistanceStart, FogRenderDistanceEnd, FogColor);
        fragColor = apply_fog(color, sphericalVertexDistance, cylindricalVertexDistance, FogEnvironmentalStart, FogRenderDistanceEnd, FogRenderDistanceStart, FogRenderDistanceEnd, FogColor);
        
    }
}

