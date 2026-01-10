package main

TextureUsage :: enum {
    RenderTarget,
    Depth,
    ShaderRead,
    ShaderWrite,
}

TextureType :: enum {
    Texture2D,
    TextureCube,
    Texture3D,
    Texture2DMultisample,
}

TextureStorage :: enum {
    Private,
}

TextureDesc :: struct {
    width: int,
    height: int,
    storage: TextureStorage,
    format: PixelFormat,
    usage: TextureUsage,
    type: TextureType,
    sample_count: int,
    mip_levels: int,
}

Texture :: struct {
    handle: rawptr,
    desc: TextureDesc,
}

TextureLoadDesc :: struct {
    filepath: string,
    format: PixelFormat,
}

// Load texture from file
load_texture :: proc(desc: TextureLoadDesc) -> Texture {
    when RENDERER_KIND == .Metal {
        return metal_load_texture(desc)
    }
}

// Create texture with TextureDesc
create_texture :: proc(desc: TextureDesc) -> Texture {
    when RENDERER_KIND == .Metal {
        return metal_create_texture(desc)
    }
}

// Free texture memory
destroy_texture :: proc(texture: ^Texture) {
    when RENDERER_KIND == .Metal {
        metal_destroy_texture(texture)
    }
}