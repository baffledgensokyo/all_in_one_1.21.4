#version 330
#extension GL_ARB_separate_shader_objects : require

// Can't moj_import in things used during startup, when resource packs don't exist.
// This is a copy of dynamicimports.glsl
layout(std140) uniform DynamicTransforms {
    mat4 ModelViewMat;
    mat4 TextureMat;
    vec4 ColorModulator;
    vec3 ModelOffset;
};

layout(location = 0) in vec4 vertexColor;
layout(location = 1) noperspective in vec4 sidebarRect;
layout(location = 2) flat in vec2 sidebarGuiSize;

layout(location = 0) out vec4 fragColor;

void main() {
    // Compute derivatives before any discard. Invert the quad-UV Jacobian to
    // recover GUI bounds on both triangles, without relying on vertex order
    // chosen by OpenGL/Vulkan for flat interpolation.
    vec4 dx = dFdx(sidebarRect);
    vec4 dy = dFdy(sidebarRect);
    float determinant = dx.x * dy.y - dy.x * dx.y;
    if (abs(determinant) > 1e-12) {
        vec2 edgeU = (dx.zw * dy.y - dy.zw * dx.y) / determinant;
        vec2 edgeV = (dy.zw * dx.x - dx.zw * dy.x) / determinant;
        vec2 origin = sidebarRect.zw - edgeU * sidebarRect.x - edgeV * sidebarRect.y;
        vec2 lower = origin + min(edgeU, vec2(0.0)) + min(edgeV, vec2(0.0));
        vec2 upper = origin + max(edgeU, vec2(0.0)) + max(edgeV, vec2(0.0));
        float height = upper.y - lower.y;
        float centre = floor(sidebarGuiSize.y * 0.5);
        float bodyRows = round((height - 1.0) / 9.0);
        float titleRows = round((centre - 1.0 - upper.y) / 6.0);
        bool bodyShape = bodyRows >= 0.0 && bodyRows <= 15.0 &&
                         abs(height - (9.0 * bodyRows + 1.0)) < 0.05;
        bool titleShape = abs(height - 9.0) < 0.05;
        bool body = bodyShape &&
                    abs(upper.y - (centre + 3.0 * bodyRows)) < 0.05;
        bool title = titleRows >= 0.0 && titleRows <= 15.0 &&
                     titleShape &&
                     abs(upper.y - (centre - 6.0 * titleRows - 1.0)) < 0.05;
        bool rightEdge = abs(upper.x - (sidebarGuiSize.x - 1.0)) < 0.05;
        bool sidebarWidth = lower.x >= sidebarGuiSize.x * 0.5 && upper.x - lower.x >= 3.0;
        bool aligned = abs(edgeU.y) < 0.05 && abs(edgeV.x) < 0.05;
        bool black = all(lessThan(abs(vertexColor.rgb), vec3(0.001)));
        // Keep arbitrary accessibility opacity at the vanilla HUD position.
        bool vanillaSidebar = rightEdge && sidebarWidth && (body || title);
        // A moved sidebar no longer matches the screen anchors. Recognize its
        // shape and standard alpha instead (vertex alpha is quantized to 8 bits).
        // Match body/title alpha separately to avoid removing unrelated panels.
        float alphaByte = round(vertexColor.a * 255.0);
        bool bodyAlpha = alphaByte == 76.0 || alphaByte == 77.0;
        bool titleAlpha = alphaByte == 102.0;
        bool movedSidebar = upper.x - lower.x >= 3.0 &&
                            ((bodyShape && bodyAlpha) || (titleShape && titleAlpha));
        if (black && aligned && (vanillaSidebar || movedSidebar)) discard;
    }
    vec4 color = vertexColor;
    if (color.a == 0.0) {
        discard;
    }
    fragColor = color * ColorModulator;
}
