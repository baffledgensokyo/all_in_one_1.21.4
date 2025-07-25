#version 150
#moj_import <globals.glsl>

#define WIDTH 1
#define COMPARE vec4(0.02,0.02,0.02,0)
vec4 color_min = vec4(0,0.082,0.308,1);
vec4 color_max = vec4(0.169,0.847,0.576,1);

layout(std140) uniform BlitConfig {
    vec4 ColorModulate;
};

uniform sampler2D DiffuseSampler;
uniform sampler2D NexusOutlineSampler;
uniform sampler2D ParticlesDepthSampler;
uniform sampler2D TranslucentDepthSampler;
uniform sampler2D ItemEntityDepthSampler;


float GameTimeR = fract(GameTime * 12);

vec2 oneTexel = 1.0 / ScreenSize;

in vec2 texCoord;

out vec4 fragColor;
vec4 outlineColor;


vec4 center = texture(NexusOutlineSampler, texCoord);

vec4 subtractVector(vec4 in_vec){
    return abs(center - in_vec);
}

vec4 recolor(sampler2D Sampler, vec2 Coord, vec4 ColorMin, vec4 ColorMax, bool interlace){
    vec4 getTexture = texture(Sampler, Coord);
    float lum = float((getTexture.r + getTexture.g + getTexture.b)/3);
    if (interlace) lum -= 0.3;
    return vec4(mix(ColorMin, ColorMax, lum));
}

float checkParticle = (1 - texture(ParticlesDepthSampler,texCoord).r);
float checkTranslucent = (1 - texture(TranslucentDepthSampler,texCoord).r);
float checkItemEntity = (1 - texture(ItemEntityDepthSampler,texCoord).r);
float checkMixed = (checkTranslucent + checkItemEntity + checkParticle)/3;


void main(){
    vec4 right, down, diag1, diag2;
    bool edge = false;
    
    for (int i = -WIDTH; i <= WIDTH; i++){
        
        right = texture(NexusOutlineSampler, texCoord + vec2(oneTexel.x * i, 0.0));
        
        down = texture(NexusOutlineSampler, texCoord + vec2(0.0, oneTexel.y * i));

        diag1 = texture(NexusOutlineSampler, texCoord + vec2(oneTexel.x * i, oneTexel.y * i));

        diag2 = texture(NexusOutlineSampler, texCoord + vec2(oneTexel.x * -i, oneTexel.y * i));

        // и почему-то я крайне уверен, что такое количество проверок нахуй не нужно...
    
        if (lessThan (subtractVector(right), COMPARE) == bvec4(0,0,0,0) ||
            lessThan (subtractVector(down), COMPARE) == bvec4(0,0,0,0) ||
            lessThan (subtractVector(diag1), COMPARE) == bvec4(0,0,0,0) ||
            lessThan (subtractVector(diag2), COMPARE) == bvec4(0,0,0,0)
        ){
            edge = true;
        }
    }
    
    vec4 outColor = vec4(vec3(center.rgb),0);
    
    if (center == vec4(0,0,0,1)){
        outColor.rgb = vec3(0.01,0.01,0.01);
    }

    if (outColor.rgb != vec3(0)){
        outlineColor = vec4(outColor);

        if (edge == true){
            outlineColor = vec4(center.rgb, 1);
        }
    }
    else 
    {
        outlineColor = vec4(0);
    }

    if (checkMixed != 0){
        
        ivec2 grumm = ivec2(texCoord * ScreenSize + int(GameTimeR * ScreenSize.y));
        bool doInterlace = grumm.y / 4 % 2 == 0;
        
        fragColor = recolor(DiffuseSampler, texCoord, color_min, color_max, doInterlace);
        
    } else {
        fragColor = texture(DiffuseSampler,texCoord);
        
    }
    
    fragColor.rgb = mix(fragColor.rgb,outlineColor.rgb,outlineColor.a);
    
}
