#ifndef LBC_EFFECT_CAMERA_TRANSFER
#define LBC_EFFECT_CAMERA_TRANSFER
// The already existing zone display can keep the camera matrix fresh while
// all holes/mushrooms are retiring. Use the previously unused alpha row 1.
float lbc_effect_camera_alpha(sampler2D data,ivec2 pixel,ivec2 size,float original) {
    if(pixel.x>=171||min(pixel.y,size.y-1-pixel.y)!=1)return original;
    ivec2 sourceSize=textureSize(data,0);
    if(sourceSize.x<57)return original;
    for(int copy=0;copy<2;copy++) {
        int row=copy==0?0:sourceSize.y-1;
        ivec3 head=ivec3(round(texelFetch(data,ivec2(56,row),0).rgb*255.0));
        if(all(equal(head,ivec3(90,66,83)))) {
            if(pixel.x/3==56)return vec3(67,65,77)[pixel.x%3]/255.0;
            return texelFetch(data,ivec2(pixel.x/3,row),0)[pixel.x%3];
        }
    }
    return original;
}
#endif
