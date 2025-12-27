package main

Sampler_Filter :: enum {
    Nearest,
    Linear,
}

Sampler_Address_Mode :: enum {
    Repeat,
    MirrorRepeat,
    ClampToEdge,
    ClampToBorder,
}

Sampler_Desc :: struct {
    min_filter: Sampler_Filter,
    mag_filter: Sampler_Filter,
    mip_filter: Sampler_Filter,
    address_mode_u: Sampler_Address_Mode,
    address_mode_v: Sampler_Address_Mode,
    address_mode_w: Sampler_Address_Mode,
    max_anisotropy: int,
}

Sampler :: struct {
    handle: rawptr,
}

create_sampler :: proc(desc: Sampler_Desc) -> Sampler {
    when RENDERER == .Metal {
        return metal_create_sampler(desc)
    }
}

destroy_sampler :: proc(sampler: ^Sampler) {
    when RENDERER == .Metal {
        metal_destroy_sampler(sampler)
    }
}
