#ifndef LBC_RETICLE_NATIVE
#define LBC_RETICLE_NATIVE
// Shared physical-pixel geometry with the recognized native GUI sprite.
float lbc_reticle_pixel_scale(vec2 size) {return max(1.0,floor(min(size.x/640.0,size.y/360.0)));}
bool lbc_native_crosshair(vec2 pixel,ivec2 size) {
    float scale=lbc_reticle_pixel_scale(vec2(size));
    vec2 origin=floor(vec2(size)*.5-vec2(7.5*scale));
    ivec2 local=ivec2(floor((pixel-origin)/scale));
    if(any(lessThan(local,ivec2(0)))||any(greaterThanEqual(local,ivec2(15))))return false;
    const int rows[15]=int[15](0,0,0,128,128,128,128,4088,128,128,128,128,0,0,0);
    return (rows[local.y]&(1<<local.x))!=0;
}
#endif
