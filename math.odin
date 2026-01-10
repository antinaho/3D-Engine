package main

// NOTE Odin matrixes are syntax wise structured row by row, but stored in memory column-wise

import "core:math"
import "core:math/rand"
import "core:math/linalg"

DEG_TO_RAD :: math.RAD_PER_DEG

Vector2 :: [2]f32
Vector3 :: [3]f32

VECTOR_RIGHT   :: Vector3 {1, 0,  0}
VECTOR_UP      :: Vector3 {0, 1,  0}
VECTOR_FORWARD :: Vector3 {0, 0, -1}

vector_length :: proc(v: Vector2) -> f32 {
    return linalg.vector_length2(v)
}

vector_normalize :: proc(v: Vector2) -> Vector2 {
    return linalg.vector_normalize(v)
}

vec3_transform_direction :: proc "contextless" (m: matrix[4,4]f32, v: Vector3) -> Vector3 {
    x := m[0,0]*v.x + m[0,1]*v.y + m[0,2]*v.z
    y := m[1,0]*v.x + m[1,1]*v.y + m[1,2]*v.z
    z := m[2,0]*v.x + m[2,1]*v.y + m[2,2]*v.z
    return {x, y, z}
}

forward_from_euler :: proc "contextless" (euler_radians: Vector3) -> Vector3 {
    R := mat4_rotate_euler(euler_radians)
    f := vec3_transform_direction(R, VECTOR_FORWARD)
    return linalg.normalize(f)
}

right_from_euler :: proc(euler_radians: Vector3) -> Vector3 {
    R := mat4_rotate_euler(euler_radians)
    r := vec3_transform_direction(R, VECTOR_RIGHT)
    return linalg.normalize(r)
}

up_from_euler :: proc(euler_radians: Vector3) -> Vector3 {
    R := mat4_rotate_euler(euler_radians)
    u := vec3_transform_direction(R, VECTOR_UP)
    return linalg.normalize(u)
}

camera_basis_from_euler :: proc(euler_radians: Vector3) -> (forward, right, up: Vector3) {
    R := mat4_rotate_euler(euler_radians)
    forward = linalg.normalize(vec3_transform_direction(R, {0, 0, -1}))
    right   = linalg.normalize(vec3_transform_direction(R, {1, 0, 0}))
    up      = linalg.normalize(vec3_transform_direction(R, {0, 1, 0}))
    return
}

// SCALE
mat4_scale_vector3 :: proc(v: Vector3) -> matrix[4, 4]f32 {
    return {
        v.x, 0,   0,   0,
        0,   v.y, 0,   0,
        0,   0,   v.z, 0,
        0,   0,   0,   1
    }
}

mat4_scale_uniform :: proc(s: f32) -> matrix[4, 4]f32 {
    return mat4_scale_vector3({s, s, s})
}

// TRANSLATE
mat4_translate_vector3 :: proc(v: Vector3) -> matrix[4, 4]f32 {
    return {
        1, 0, 0, v.x,
        0, 1, 0, v.y,
        0, 0, 1, v.z,
        0, 0, 0, 1
    }
}

// ROTATE
mat4_rotate_x :: proc "contextless" (angle_radians: f32) -> matrix[4, 4]f32 {
    c := math.cos(angle_radians)
    s := math.sin(angle_radians)
    return {
        1,  0, 0, 0,
        0,  c, -s, 0,
        0,  s, c, 0,
        0, 0, 0, 1
    }
}

mat4_rotate_y :: proc "contextless" (angle_radians: f32) -> matrix[4, 4]f32 {
    c := math.cos(angle_radians)
    s := math.sin(angle_radians)
    return {
        c, 0, s, 0,
        0, 1,  0, 0, 
        -s, 0,  c, 0,
        0, 0, 0, 1
    }   
}

mat4_rotate_z :: proc "contextless" (angle_radians: f32) -> matrix[4, 4]f32 {
    c := math.cos(angle_radians)
    s := math.sin(angle_radians)
    return {
        c,  -s, 0, 0,
        s,  c, 0, 0,
        0,  0, 1, 0,
        0, 0, 0, 1
    }
}

mat4_rotate_euler :: proc "contextless" (radians_rotation: Vector3) -> matrix[4, 4]f32 {
    Rx := mat4_rotate_x(radians_rotation.x)
    Ry := mat4_rotate_y(radians_rotation.y)
    Rz := mat4_rotate_z(radians_rotation.z)

    return Rz * Ry * Rx
}

// MODEL
mat4_model :: proc(position, radian_rotation, scale: Vector3) -> matrix[4, 4]f32 {
    T := mat4_translate_vector3(position)
    R := mat4_rotate_euler(radian_rotation)
    S := mat4_scale_vector3(scale)

    return T * R * S
}

// VIEW
mat4_view :: proc(eye, target, up: Vector3) -> matrix[4,4]f32 {
    forward := linalg.normalize(target - eye)  
    right := linalg.normalize(linalg.cross(forward, up))  
    up := linalg.cross(right, forward) 
    
    return {
        right.x,     right.y,     right.z,   -linalg.dot(right, eye),
        up.x,        up.y,        up.z,      -linalg.dot(up, eye),
        -forward.x, -forward.y,  -forward.z,  linalg.dot(forward, eye),
        0,           0,           0,          1,
    }
}

// PROJECTION
mat4_perspective_projection :: proc(fov_y_radians, aspect, near, far: f32) -> matrix[4, 4]f32 {
    ys := 1 / math.tan_f32(fov_y_radians * 0.5);
    xs := ys / aspect;
    zs := far / (near - far);
    return { xs, 0,   0,  0,
             0,  ys,  0,  0,
             0,  0,   zs, near * zs,
             0,  0,   -1, 0 }
}

mat4_ortho :: proc(left, right, bottom, top, near, far: f32) -> matrix[4, 4]f32 {
    rl := right - left
    tb := top - bottom
    nf := near - far 

    return {
        2/rl,   0,      0,      -(right+left)/rl,
        0,      2/tb,   0,      -(top+bottom)/tb,
        0,      0,      1/nf,    near/nf,
        0,      0,      0,      1,
    }
}

mat4_ortho_fixed_height :: proc(height: f32, aspect: f32, near: f32 = 0, far: f32 = 1) -> matrix[4,4]f32 {
    width := height * aspect
    left   := -width * 0.5
    right  :=  width * 0.5
    bottom := -height * 0.5
    top    :=  height * 0.5
    return mat4_ortho(left, right, bottom, top, near, far)
}

// proj_ui := mat4_ui_ortho_fixed_height(1080, screen_width/screen_height)
// view_ui := mat4_identity()
// model_ui := mat4_identity()
// MVP_ui := proj_ui * view_ui * model_ui

mat4_identity :: proc() -> matrix[4, 4]f32 {
    return {
        1, 0, 0, 0,
        0, 1, 0, 0,
        0, 0, 1, 0,
        0, 0, 0, 1
    }
}


// RANDOM
random_unit_vector_spherical :: proc() -> Vector3 {
    // Random angles
    theta := rand.float32_range(0, math.TAU)      
    phi := math.acos(rand.float32_range(-1, 1))
    sin_phi := math.sin(phi)
    
    return {
        sin_phi * math.cos(theta),
        sin_phi * math.sin(theta),
        math.cos(phi),
    }
}
