#version 330
#extension GL_ARB_separate_shader_objects : require

#include <minecraft:fog.glsl>
#include <minecraft:dynamictransforms.glsl>
#include <minecraft:projection.glsl>

#include <minecraft:sample_lightmap.glsl>
#include <minecraft:globals.glsl>
layout(location = 0) in vec3 Position;
layout(location = 1) in vec2 UV0;
layout(location = 2) in vec4 Color;
layout(location = 3) in ivec2 UV2;

uniform sampler2D Sampler2;

//uniform int FogShape;

layout(location = 0) out float sphericalVertexDistance;
layout(location = 1) out float cylindricalVertexDistance;
layout(location = 2) out vec2 texCoord0;
layout(location = 3) flat out vec4 vertexColor;
float pos_z;
vec4 outColor;
ivec3 checkColor;

vec4 PositionSwitch(){

    // Four pixels survive resizing and OIT compositing; end_of_frame reads their centre.
    vec2 pixel = vec2(-1.0) + 8.0 / max(ScreenSize, vec2(1.0));
#ifdef RENDERPEARL_DEPTH_IS_ZERO_TO_ONE
    const float markerDepth = 0.0;
#else
    const float markerDepth = -1.0;
#endif
    vec4 returnPosition = vec4(0);
    switch(gl_VertexIndex % 4){
                case 0:
                returnPosition = vec4(pixel.x,-1.0,markerDepth,1.0);
                break;

                case 1:
                returnPosition = vec4(pixel,markerDepth,1.0);
                break;

                case 2:
                returnPosition = vec4(-1.0,pixel.y,markerDepth,1.0);
                break;

                case 3:
                returnPosition = vec4(-1.0,-1.0,markerDepth,1.0);
                break;
             }
        return returnPosition;
}

void main() {

    vec4 pre_Position = ProjMat * ModelViewMat * vec4(Position, 1.0);
    
    vertexColor = Color * sample_lightmap(Sampler2, UV2);

    pos_z = pre_Position.z;

    int particleType = 0;

    checkColor = ivec3(round(Color.rgb * 255.0));
    
    if (checkColor.r == 0 && checkColor.b == 0) {

    switch(checkColor.g) {

        case 1:
        outColor = vec4(vec3(20,209,255)/255,1.0);
        vertexColor = outColor;
        particleType = 1;
        pos_z = 0;
        break;

        case 2:
        outColor = vec4(vec3(255,170,0)/255,1.0);
        vertexColor = outColor;
        particleType = 1;
        pos_z = 0;
        break;    
        
        case 3:
        outColor = vec4(vec3(68,64,11)/255,1.0);
        vertexColor = outColor;
        particleType = 2;
        pos_z = 0;
        break;    
        }
    }
    
    switch(particleType){

        case 1:
        gl_Position = vec4(pre_Position.xy, pos_z, pre_Position.w);
        break;

        case 2:
        gl_Position = PositionSwitch();
        break;

        default:
        gl_Position = pre_Position;
        break;
        
    }

    //vertexDistance = fog_distance(Position, FogShape);
    sphericalVertexDistance = fog_spherical_distance(Position);
    cylindricalVertexDistance = fog_cylindrical_distance(Position);
    texCoord0 = UV0;
    
}
