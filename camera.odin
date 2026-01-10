package main

import "core:math"
import "core:math/linalg"

Camera :: struct {
    position: Vector3,
    rotation: Vector3,
    aspect: f32,
    near: f32,
    far: f32,

    fov: f32,
    zoom: f32,
}
