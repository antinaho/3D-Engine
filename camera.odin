package main

Camera :: struct {
    using transform: Transform,
    projection: Projection,

    forward: [3]f32,
    right: [3]f32,
    up: [3]f32,

    zoom: f32,
    
    near: f32,
    far: f32,
    fov: f32,
    aspect: f32,
}

//TODO init in main or somewhere else
main_camera := Camera {
    position = {0, 0, 5},
    rotation = {0, -90, 0},


    projection = .Orthographic,
    
    near = 0.1,
    far = 100.0,
    aspect = 1280.0 / 720.0,
    fov = 70,
    
    zoom = 1,
}

Projection :: enum {
    Orthographic,
    Perspective,
}

// Idk this just overkill but maybe later if there's more settings
ProjectionSettings :: union {
    OrthographicProjectionSettings,
    PerspectiveProjectionSettings,
}

OrthographicProjectionSettings :: struct {
    zoom: f32,
}

PerspectiveProjectionSettings :: struct {
    fov: f32,
    aspect: f32,
    near: f32,
    far: f32,
}
