package main

import "core:math"
import "core:math/linalg"

Camera :: struct {
    position: Vector3,
    aspect: f32,
    near: f32,
    far: f32,
    type: CameraType,
}

CameraType :: union {
    Perspective,
    Orthographic,
}

Perspective :: struct {
    rotation: Vector3,
    fov: f32,
}

Orthographic :: struct {
    zoom: f32,
}

//TODO init in main or somewhere else with custom values
main_camera := Camera {
    position = {0, 0, 5},
    aspect = 16.0 / 9.0,
    near = 0.1,
    far = 100.0,

    type = Perspective {
        rotation = {0, 0, 0},
        fov = 90,
    },
}
