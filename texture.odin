package main

Texture_Usage :: enum {
    RenderTarget,
    Depth,
    ShaderRead,
    ShaderWrite,
}

Texture_Type :: enum {
    Texture2D,
    TextureCube,
    Texture3D,
    Texture2DMultisample,
}

Texture_Desc :: struct {
    width: int,
    height: int,
    //depth: int,
    format: Pixel_Format,
    usage: Texture_Usage,
    type: Texture_Type,
    sample_count: int,  // For MSAA
    mip_levels: int,
}

Texture :: struct {
    handle: rawptr,
    desc: Texture_Desc,
}

create_texture :: proc(desc: Texture_Desc) -> Texture {
    when RENDERER == .Metal {
        return metal_create_texture(desc)
    } else when RENDERER == .Vulkan {
        return vulkan_create_texture(desc)
    }
}

destroy_texture :: proc(texture: ^Texture) {
    when RENDERER == .Metal {
        metal_destroy_texture(texture)
    } else when RENDERER == .Vulkan {
        vulkan_destroy_texture(texture)
    }
}