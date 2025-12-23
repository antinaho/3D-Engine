package main

Renderer :: struct {
    using api: RendererAPI,
    platform: Platform,
    clear_color: Color,
}

RendererAPI :: struct {
    draw: proc(window: ^Window, renderer: ^Renderer),
    clear_background: proc(renderer: ^Renderer, color: Color),
}

Color :: [4]u8

PINK :: Color {255, 203, 196, 255}
PEACH :: Color {255, 203, 165, 255}
APINK :: Color {255, 152, 153, 255}
DARKPURP :: Color {30, 25, 35, 255}


Camera :: struct {
    position: [3]f32,
    near_clip: f32,
    far_clip: f32,
    FOV: f32,
}

camera := Camera {
    position = {0, 0, 1},
    near_clip = 0.1,
    far_clip = 100,
    FOV = 90,
}