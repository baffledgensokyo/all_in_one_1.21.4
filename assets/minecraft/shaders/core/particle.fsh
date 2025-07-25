#version 150

#moj_import <minecraft:fog.glsl>
#moj_import <minecraft:dynamictransforms.glsl>

uniform sampler2D Sampler0;

//in float vertexDistance;
in float sphericalVertexDistance;
in float cylindricalVertexDistance;

in vec2 texCoord0;
flat in vec4 vertexColor;

out vec4 fragColor;
ivec3 checkColor;
vec4 color;
vec2 oneTexel = vec2(1) / textureSize(Sampler0, 0);

void main() {
    vec4 precolor = texture(Sampler0, vec2(texCoord0.x,texCoord0.y)) * vertexColor * ColorModulator;

    checkColor = ivec3(vertexColor.rgb * 255);

    if(checkColor == ivec3(20,209,255) || checkColor == ivec3(255,170,0)) {
        color = texture(Sampler0, vec2(texCoord0.x, texCoord0.y + oneTexel.y*8)) * vertexColor * ColorModulator;
    } else if (checkColor == ivec3(68,64,11)) {
        color = vec4(0.282,0.323,0.098,1);
    } else {
        color = apply_fog(precolor, sphericalVertexDistance, cylindricalVertexDistance, FogEnvironmentalStart, FogEnvironmentalEnd, FogRenderDistanceStart, FogRenderDistanceEnd, FogColor);
    }

    if (color.a < 0.1) {
        discard;
    }
    
    //fragColor = linear_fog(color, vertexDistance, FogRenderDistanceStart, FogRenderDistanceEnd, FogColor);
    fragColor = color;
}
