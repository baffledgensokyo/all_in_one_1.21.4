#version 150
#define SPEED 400
#define WAVES 2
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
vec2 uv = gl_FragCoord.xy / ScreenSize;
vec2 oneTexel = vec2(1.0) / ScreenSize;
float rand(vec2 co) {
    return fract(sin(dot(co.xy, vec2(12.9898, 78.233))) * 43758.5453);
}

vec3 hsv_to_rgb(vec3 hsv) {
    vec3 rgb = clamp(abs(fract(hsv.xxx + vec3(0.0, 2.0/3.0, 1.0/3.0)) * 6.0 - 3.0) - 1.0, 0.0, 1.0);
    rgb = mix(vec3(1.0), rgb, hsv.y);
    rgb *= hsv.z;
    return rgb;
}

vec3 currentRGB = hsv_to_rgb(vec3(fract(uv.x * WAVES) + fract(GameTime * SPEED),0.6,1.0));

vec3 getPulseColor() {
    // Pulse factor: smooth transition from 0 to 1 to 0
    float pulseTime = fract(GameTime * SPEED); // Loops every second
    float pulse = 0.5 * (1.0 + sin(pulseTime * 2.0 * 3.14159)); // Full sine wave per second
    // Colors to interpolate between
    vec3 darkRed = vec3(0.5, 0.0, 0.0);
    vec3 black = vec3(0.1, 0.0, 0.0);

    // Return interpolated color
    return mix(black, darkRed, pulse);
}

void main() {
    vec4 color = texture(Sampler0, texCoord0) * vertexColor;
    if (color.a == 0.0) {
        discard;
    }

    if (color == vec4(78/255., 92/255., 36/255., color.a)) {
        color = vec4(currentRGB, color.a);
    } else if (color == vec4(21/255., 25/255., 10/255., color.a)) {
        color = vec4(currentRGB * 0.1, color.a);

    } else if (color == vec4(170/255.,2/255.,2/255., color.a)) {


        color = vec4(getPulseColor(), color.a); 
        if (rand(vec2(float(floor(texCoord0.x * 1000) / 1000) + GameTime, float(floor(texCoord0.y * 1000) / 1000) + GameTime)) <= 0.4) {
            color = vec4(0, 0, 0, color.a);
        }



    } else if (color == vec4(74/255.,3/255.,15/255., color.a)) {
        color = vec4(getPulseColor(), color.a) * vec4(0.5,0.5,0.5,1.0);
       if (rand(vec2(float(floor(texCoord0.x * 1000) / 1000) + GameTime, float(floor(texCoord0.y * 1000) / 1000) + GameTime)) <= 0.4) {
            color = vec4(0, 0, 0, color.a);
       }
    }   
    
    
    
    fragColor = color * ColorModulator;
}
