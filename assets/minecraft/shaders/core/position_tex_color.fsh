#version 150
#define SPEED 1000
// Can't moj_import in things used during startup, when resource packs don't exist.
// This is a copy of dynamicimports.glsl
layout(std140) uniform DynamicTransforms {
    mat4 ModelViewMat;
    vec4 ColorModulator;
    vec3 ModelOffset;
    mat4 TextureMat;
    float LineWidth;
};

layout(std140) uniform Globals {
    vec2 ScreenSize;
    float GlintAlpha;
    float GameTime;
    int MenuBlurRadius;
};


uniform sampler2D Sampler0;

in vec2 texCoord0;
in vec4 vertexColor;

out vec4 fragColor;

vec3 hsv_to_rgb(vec3 hsv) {
    vec3 rgb = clamp(abs(fract(hsv.xxx + vec3(0.0, 2.0/3.0, 1.0/3.0)) * 6.0 - 3.0) - 1.0, 0.0, 1.0);
    rgb = mix(vec3(1.0), rgb, hsv.y);
    rgb *= hsv.z;
    return rgb;
}

vec3 currentRGB = hsv_to_rgb(vec3(fract(texCoord0.x) + fract(GameTime * SPEED),0.6,1.0));

void main() {
    vec4 color = texture(Sampler0, texCoord0) * vertexColor;
    if (color.a == 0.0) {
        discard;
    }

    if (color == vec4(78/255., 92/255., 36/255., color.a)) {
        color = vec4(currentRGB, color.a);
    }
    
    fragColor = color * ColorModulator;
}
