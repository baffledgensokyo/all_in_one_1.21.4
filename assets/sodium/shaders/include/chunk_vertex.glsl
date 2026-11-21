// Adapted from CaffeineMC Sodium 0.9.2+mc26.3 (https://github.com/CaffeineMC/sodium).
// PolyForm Shield 1.0.0: assets/sodium/licenses/LICENSE.md.
// Changes: wrap the native terrain entry point to transport the atlas signal.
// Keep Sodium's own camera transforms, including its 0.9.3 camera offset.

// The position of the vertex around the model origin
vec3 _vert_position;

// The block texture coordinate of the vertex
vec2 _vert_tex_diffuse_coord;
vec2 _vert_tex_diffuse_coord_bias;

// The light texture coordinate of the vertex
vec2 _vert_tex_light_coord;

// The color of the vertex
vec4 _vert_color;

// The index of the draw command which this vertex belongs to
uint _draw_id;

// The material bits for the primitive
uint _material_params;

#ifdef USE_VERTEX_COMPRESSION
const uint POSITION_BITS        = 20u;
const uint POSITION_MAX_COORD   = 1u << POSITION_BITS;
const uint POSITION_MAX_VALUE   = POSITION_MAX_COORD - 1u;

const uint TEXTURE_BITS         = 15u;
const uint TEXTURE_MAX_COORD    = 1u << TEXTURE_BITS;
const uint TEXTURE_MAX_VALUE    = TEXTURE_MAX_COORD - 1u;

const float VERTEX_SCALE = 32.0 / float(POSITION_MAX_COORD);
const float VERTEX_OFFSET = -8.0;

layout(location = 0) in uvec2 a_Position;
layout(location = 1) in vec4 a_Color;
layout(location = 2) in uvec2 a_TexCoord;
layout(location = 3) in uvec4 a_LightAndData;

uvec3 _deinterleave_u20x3(uvec2 data) {
    uvec3 hi = (uvec3(data.x) >> uvec3(0u, 10u, 20u)) & 0x3FFu;
    uvec3 lo = (uvec3(data.y) >> uvec3(0u, 10u, 20u)) & 0x3FFu;

    return (hi << 10u) | lo;
}

vec2 _get_texcoord() {
    return vec2(a_TexCoord & TEXTURE_MAX_VALUE) / float(TEXTURE_MAX_COORD);
}

vec2 _get_texcoord_bias() {
    return mix(vec2(-1.0), vec2(1.0), bvec2(a_TexCoord >> TEXTURE_BITS));
}

void _vert_init() {
    _vert_position = (_deinterleave_u20x3(a_Position) * VERTEX_SCALE) + VERTEX_OFFSET;
    _vert_color = a_Color;
    _vert_tex_diffuse_coord = _get_texcoord();
    _vert_tex_diffuse_coord_bias = _get_texcoord_bias();

    _vert_tex_light_coord = vec2(a_LightAndData.xy) / vec2(256.0);

    _material_params = a_LightAndData[2];
    _draw_id = a_LightAndData[3];
}

#else
#error "Vertex compression must be enabled"
#endif
#include <lbc:atlas_glitch.glsl>

// Sodium Extra uses locations 4 and 5 for fog.
layout(location = 10) flat out float atlasGlitchCode;

// This include is shared by Sodium versions with different camera uniforms.
// Wrap the installed vertex shader instead of copying its position calculation.
// The macro expands at the native main(), after v_Color/u_LightTex are declared.
#ifdef OIT_ALPHA_ONLY
#define LBC_SODIUM_FINISH_VERTEX atlasGlitchCode = 0.0;
#else
// Restore coverage after native lighting, whose alpha carries our private signal.
#define LBC_SODIUM_FINISH_VERTEX v_Color.a = _vert_color.a; atlasGlitchCode = lbc_atlas_glitch_code(u_LightTex);
#endif
// GLSL 330 needs each macro on one line (no backslash continuations).
#define main() lbc_sodium_main(); void main() { lbc_sodium_main(); LBC_SODIUM_FINISH_VERTEX } void lbc_sodium_main()
