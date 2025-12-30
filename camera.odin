package main

Camera :: struct {
    position: [3]f32,
    target: [3]f32,
    fov: f32,
    zoom: f32,
    aspect: f32,
    near: f32,
    far: f32,
}

//TODO init in main or somewhere else
main_camera := Camera {
    position = {0, 0, 1},
    target = {0, 0, 0},
    aspect = 1280.0 / 720.0,
    zoom = 5,
    near = 0.1,
    far = 100,
    fov = 90,
}