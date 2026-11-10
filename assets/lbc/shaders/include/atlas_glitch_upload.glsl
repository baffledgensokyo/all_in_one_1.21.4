#ifndef LBC_ATLAS_GLITCH_UPLOAD_GLSL
#define LBC_ATLAS_GLITCH_UPLOAD_GLSL

#include <lbc:atlas_glitch_directory.glsl>
layout(location = 2) flat in int lbcDirectoryTriangle;

// Returns true for a directory fragment; all ordinary fragments keep their
// original sampling/interpolation, RGBA and mip generation.
bool lbc_glitch_upload(out vec4 record) {
    ivec2 atlasSize = ivec2(round(abs(2.0 / vec2(ProjectionMatrix[0][0], ProjectionMatrix[1][1]))));
    if (MipMapLevel != 0 || !lbc_glitch_directory_atlas(atlasSize)) return false;
    ivec2 pixel = ivec2(gl_FragCoord.xy);
    vec2 padding = vec2(UPadding, VPadding);
    ivec2 frame = ivec2(round(vec2(SpriteMatrix[0][0], SpriteMatrix[1][1]) / (1.0 + 2.0 * padding)));
    ivec2 origin = ivec2(round(SpriteMatrix[3].xy + padding * vec2(frame)));
    if (lbcDirectoryTriangle != 0) {
        if (pixel.y != atlasSize.y - 1) discard;
        ivec4 sprite = ivec4(origin, frame);
        uint slot = uint(pixel.x / 2);
        uint key = lbc_glitch_directory_key(sprite);
        bool selected = false;
        for (uint copy = 0u; copy < 4u; ++copy) {
            selected = selected || slot == lbc_glitch_directory_slot(key, copy, uint(atlasSize.x / 2));
        }
        if (!selected) discard;
        record = lbc_glitch_directory_record(sprite, pixel.x & 1);
        return true;
    }
    // Also clips the oversized sprite triangle to the original padded quad.
    ivec2 paddedOrigin = ivec2(round(SpriteMatrix[3].xy));
    ivec2 paddedEnd = ivec2(round(SpriteMatrix[3].xy + vec2(SpriteMatrix[0][0], SpriteMatrix[1][1])));
    if (any(lessThan(pixel, paddedOrigin)) || any(greaterThanEqual(pixel, paddedEnd))) discard;
    // Every stitched sprite has at least one outer padding texel. Protect the
    // directory from later uploads, including oversized animated photographs.
    if (pixel.y == atlasSize.y - 1) discard;
    return false;
}

#endif
