package main

RendererInterface :: struct {
    config_size : proc() -> int,
    init        : proc(wsi: WSI, render_state: rawptr) -> rawptr,
    draw        : proc(),
    cleanup: proc(),
}

RENDERER_KIND :: #config(RENDER_KIND, "Vulkan")

WSI :: union {
    VulkanWSI
}
