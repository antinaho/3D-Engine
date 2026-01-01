package main

import "core:math"
import "core:math/linalg"

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

//TODO init in main or somewhere else with custom values
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

update_camera_vectors :: proc(camera: ^Camera) {
    camera.forward = linalg.normalize([3]f32{
        math.cos(camera.rotation.y) * math.cos(camera.rotation.x),
        math.sin(camera.rotation.x),
        math.sin(camera.rotation.y) * math.cos(camera.rotation.x),
    })
    camera.right = linalg.normalize(linalg.cross(camera.forward, VECTOR_UP))
    camera.up = linalg.normalize(linalg.cross(camera.right, camera.forward))
}

get_camera_forward :: proc(camera: Camera) -> Vector3 {

    rad_rotation := camera.rotation * DEG_TO_RAD
    forward := [3]f32{
        math.cos(rad_rotation.y) * math.cos(rad_rotation.x),
        math.sin(rad_rotation.x),                                 
        math.sin(rad_rotation.y) * math.cos(rad_rotation.x),
    }
    
    return camera.position + forward
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
