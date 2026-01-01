package main

import "core:math"
import "core:math/rand"
import "core:math/linalg"

RAD_TO_DEG :: math.RAD_PER_DEG
DEG_TO_RAD :: math.DEG_PER_RAD

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

matrix_translate :: proc(v: [3]f32) -> matrix[4,4]f32 {
	return matrix[4,4]f32{
        1,   0,   0,   v.x,
        0,   1,   0,   v.y,
        0,   0,   1,   v.z,
        0,   0,   0,   1,
    }
}

matrix_scale :: proc(v: [3]f32) -> matrix[4,4]f32 {
    return matrix[4,4]f32{
        v.x, 0, 0, 0,
        0, v.y, 0, 0,
        0, 0, v.z, 0,
        0, 0, 0, 1,
    }
}

matrix_rotate_x :: proc(angle_radians: f32) -> matrix[4,4]f32 {
    c := math.cos(angle_radians)
    s := math.sin(angle_radians)
    return matrix[4,4]f32{
        1,  0,  0, 0,
        0,  c,  -s, 0,
        0, s,  c, 0,
        0,  0,  0, 1,

    }
}

matrix_rotate_y :: proc(angle_radians: f32) -> matrix[4,4]f32 {
    c := math.cos(angle_radians)
    s := math.sin(angle_radians)
    return matrix[4,4]f32{
        c, 0, s, 0,
        0, 1,  0, 0,
        -s, 0,  c, 0,
		0, 0,  0, 1,
    }
}

matrix_rotate_z :: proc(angle_radians: f32) -> matrix[4,4]f32 {
    c := math.cos(angle_radians)
    s := math.sin(angle_radians)
    return matrix[4,4]f32{
         c, -s, 0, 0,
         s,  c, 0, 0,
         0,  0, 1, 0,
         0,  0, 0, 1,
    }
}

matrix_model :: proc(position: [3]f32, rotation: [3]f32, scale: [3]f32) -> matrix[4,4]f32 {
    T := matrix_translate(position)
    Rx := matrix_rotate_x(rotation.x)
    Ry := matrix_rotate_y(rotation.y)
    Rz := matrix_rotate_z(rotation.z)
    S := matrix_scale(scale)
    
    return T * Ry * Rx * Rz * S 
}

// View matrix
matrix_look_at :: proc(eye: [3]f32, target: [3]f32, up: [3]f32) -> matrix[4,4]f32 {
    f := linalg.normalize(target - eye)  // Forward
    r := linalg.normalize(linalg.cross(f, up))  // Right
    u := linalg.cross(r, f)  // Up
    
    return matrix[4, 4]f32{
        r.x,    r.y,   r.z,   -linalg.dot(r, eye),
        u.x,    u.y,   u.z,   -linalg.dot(u, eye),
        -f.x,   -f.y,  -f.z,  linalg.dot(f, eye),
        0,      0,     0,     1,

    }
}

get_perspective_projection :: proc(camera: Camera) -> matrix[4,4]f32 {
	fov_rad := camera.fov * DEG_TO_RAD

	return _matrix_perspective(fov_rad, camera.aspect, camera.near, camera.far)
}

_matrix_perspective :: proc(fov_y_radians: f32, aspect: f32, near: f32, far: f32) -> matrix[4,4]f32 {
    tan_half_fov := math.tan(fov_y_radians / 2.0)
    
	ys := 1 / math.tan_f32(fov_y_radians * 0.5);
    xs := ys / aspect;
    zs := far / (near - far);

	return matrix[4,4]f32{
		xs,  0,   0,  0,
        0,   ys,  0,  0,
        0,   0,   zs, near * zs,
        0,   0,  -1,  0}
}

_matrix_orthographic :: proc(left: f32, right: f32, bottom: f32, top: f32, near: f32, far: f32) -> matrix[4,4]f32 {
    return matrix[4,4]f32{
        2.0 / (right - left), 0, 0, 0,
        0, 2.0 / (top - bottom), 0, 0,
        0, 0, 1.0 / (near - far), 0,
        -(right + left) / (right - left), -(top + bottom) / (top - bottom), near / (near - far), 1,
    }
}

get_orthographic_projection :: proc(camera: Camera) -> matrix[4,4]f32 {
    height := camera.zoom
    width := height * camera.aspect
    
    return _matrix_orthographic(
        -width * 0.5, width * 0.5,   // left, right
        -height * 0.5, height * 0.5,  // bottom, top
        camera.near,
        camera.far,
    )
}

random_unit_vector_spherical :: proc() -> [3]f32 {
    // Random angles
    theta := rand.float32_range(0, math.TAU)          // Azimuth [0, 2π]
    phi := math.acos(rand.float32_range(-1, 1))       // Polar angle via cosine distribution
    
    sin_phi := math.sin(phi)
    
    return [3]f32{
        sin_phi * math.cos(theta),  // X
        sin_phi * math.sin(theta),  // Y
        math.cos(phi),               // Z
    }
}