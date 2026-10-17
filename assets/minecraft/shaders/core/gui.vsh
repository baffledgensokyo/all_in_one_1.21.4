#version 330
#extension GL_ARB_separate_shader_objects : require

// Can't moj_import in things used during startup, when resource packs don't exist.
// This is a copy of dynamicimports.glsl and projection.glsl
layout(std140) uniform DynamicTransforms {
    mat4 ModelViewMat;
    mat4 TextureMat;
    vec4 ColorModulator;
    vec3 ModelOffset;
};
layout(std140) uniform Projection {
    mat4 ProjMat;
};

layout(location = 0) in vec3 Position;
layout(location = 1) in vec4 Color;

layout(location = 0) out vec4 vertexColor;
layout(location = 1) noperspective out vec4 sidebarRect;
layout(location = 2) flat out vec2 sidebarGuiSize;

void main() {
    gl_Position = ProjMat * ModelViewMat * vec4(Position, 1.0);

    vertexColor = Color;
    // ColoredRectangleRenderState emits (x0,y0), (x0,y1), (x1,y1), (x1,y0).
    // Local quad coordinates let the fragment shader recover the ENTIRE rect,
    // independently of which triangle/provoking vertex is being rasterized.
    int corner = gl_VertexIndex & 3;
    vec2 quadUV = vec2(corner >= 2 ? 1.0 : 0.0,
                       corner == 1 || corner == 2 ? 1.0 : 0.0);
    sidebarRect = vec4(quadUV, Position.xy);
    // The projection uses fractional sizes, but HUD layout uses rounded-up
    // GUI sizes, including windows whose dimensions are not multiples of scale.
    sidebarGuiSize = ceil(2.0 / abs(vec2(ProjMat[0][0], ProjMat[1][1])) - 0.001);
}
