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
    t: TextureSampler
    return t
}

destroy_sampler :: proc(sampler: ^TextureSampler) {
}
