package main

import "core:os"
import "core:strings"
import "core:io"
import "core:strconv"
import "core:bufio"

SmoothShading :: struct {
    mode: bool,
    start: int,
    end: int,
}

Model :: struct {
    object_name: string,
    material_name: string,
    smooth_shading: [dynamic]SmoothShading,
    vertex_positions: [dynamic][4]f32,
    texture_positions: [dynamic][3]f32,
    vertex_normals: [dynamic][3]f32,
    face_elements: [dynamic][3][3]int,
}


read_model_from_file :: proc(filepath: string) -> (model: Model, err: bool) {
    f, ferr := os.open(filepath)
    if ferr != 0 {
		// handle error appropriately
		return model, false
	}
    defer os.close(f)

    r: bufio.Reader
	buffer: [1024]byte
	bufio.reader_init_with_buf(&r, os.stream_from_handle(f), buffer[:])
    defer bufio.reader_destroy(&r)

    line_n := 0
    shading_count := 0
    outer: for {
		line, err := bufio.reader_read_string(&r, '\n', context.allocator)
		if err != nil {
			break
		}
		defer delete(line, context.allocator)
		
        line = strings.trim_right(line, "\r")
        line = strings.trim_right(line, "\n")

        parts := strings.split(line, " ", context.allocator)
        start := parts[0]

        if start == "o" {
            model.object_name = parts[1]
        } else if start == "v" {
            vertex_position: [4]f32
            i := 0
            for vcoord in parts[1:] {
                if val, ok := strconv.parse_f32(vcoord); ok {
                    vertex_position[i] = val
                }
                i += 1
            }
            if i == 2 { vertex_position[3] = 1.0 }
            append(&model.vertex_positions, vertex_position)

        } else if start == "vt" {
            texture_position: [3]f32
            i := 0
            for texcoord in parts[1:] {
                if val, ok := strconv.parse_f32(texcoord); ok {
                    texture_position[i] = val
                }
                i += 1
            }
            if i == 1 { texture_position[2] = 0.0 }
            append(&model.texture_positions, texture_position)

        } else if start == "vn" {
            vertex_normals: [3]f32
            for vertn, i in parts[1:] {
                if val, ok := strconv.parse_f32(vertn); ok {
                    vertex_normals[i] = val
                }
            }
            append(&model.vertex_normals, vertex_normals)
        } else if start == "usemtl" {
            model.material_name = parts[1]
        } else if start == "s" {
            
            c := len(model.smooth_shading)
            mode := parts[1]
            mode_bool: bool
            mode_bool = mode == "1"

            if c == 0 {
                append(&model.smooth_shading, SmoothShading{mode=mode_bool, start=line_n})
            } else {
                model.smooth_shading[shading_count - 1].end = line_n
                append(&model.smooth_shading, SmoothShading{mode=mode_bool, start=line_n})
            }

            shading_count += 1

        } else if start == "f" {
            face_elements_line: [3][3]int
            i := 0
            for part in parts[1:] {
                face_elements: [3]int
                s := strings.split(part, "/", allocator=context.allocator)
                v, e := strconv.parse_int(s[0])
                vt, e1 := strconv.parse_int(s[1])
                vn, e2 := strconv.parse_int(s[2])
                face_elements[0] = v
                face_elements[1] = vt
                face_elements[2] = vn

                face_elements_line[i] = face_elements
                i += 1
            }

            append(&model.face_elements, face_elements_line)
        }
        line_n += 1
	}

    model.smooth_shading[shading_count - 1].end = line_n

    return model, true
}
