package main

TextureSamplerFilter :: enum {
    Nearest,
    Linear,
}

TextureSamplerAddressMode :: enum {
    Repeat,
    MirrorRepeat,
    ClampToEdge,
    ClampToBorder,
}

TextureSamplerDesc :: struct {
    min_filter: TextureSamplerFilter,
    mag_filter: TextureSamplerFilter,
    mip_filter: TextureSamplerFilter,
    address_mode_u: TextureSamplerAddressMode,
    address_mode_v: TextureSamplerAddressMode,
    address_mode_w: TextureSamplerAddressMode,
    max_anisotropy: int,
}

TextureSampler :: struct {
    handle: rawptr,
}

create_sampler :: proc(desc: TextureSamplerDesc) -> TextureSampler {
    when RENDERER_KIND == .Metal {
        return metal_create_sampler(desc)
    }
}

destroy_sampler :: proc(sampler: ^TextureSampler) {
    when RENDERER_KIND == .Metal {
        metal_destroy_sampler(sampler)
    }
}
