package main

import "core:os"
import "core:strings"
import "core:io"
import "core:strconv"
import "core:bufio"

//TODO Fix everything... check out "tinyobjloader"

Model :: struct {
    vertices: [dynamic][3]f32,
    vertex_index: u32,

    texcoords: [dynamic][2]f32,
    texture_index: u32,

    faces: [dynamic]FacePoint,
}

import "core:fmt"

FacePoint :: struct {
    vertex_index: u32,
    texture_index: u32,
}

VertexPosition :: [3]f32
TextureCoordinate :: [2]f32

append_vertex_position :: proc(model: ^Model, vertex: VertexPosition) {
    append(&model.vertices, vertex)
    model.vertex_index += 1
}

append_texture_coordinate :: proc(model: ^Model, coordinate: TextureCoordinate) {
    append(&model.texcoords, coordinate)
    model.texture_index += 1
}

append_face_point :: proc(model: ^Model, vindex, tindex: int) {
    append(&model.faces, FacePoint{u32(vindex), u32(tindex)})
}

read_model_from_file :: proc(filepath: string) -> (model: Model, err: bool) {
    f, ferr := os.open(filepath)
    if ferr != 0 {
		// handle error appropriately
		return model, true
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

        if start == "v" {
            position: VertexPosition
            for vcoord, i in parts[1:] {
                if val, ok := strconv.parse_f32(vcoord); ok {
                    position[i] = val
                }
            }
            append_vertex_position(&model, position)
        } else if start == "vt" {
            coord: TextureCoordinate
            for texcoord, i in parts[1:] {
                if val, ok := strconv.parse_f32(texcoord); ok {
                    coord[i] = val
                }
            }
            append_texture_coordinate(&model, coord)
        } else if start == "f" {
            
            for face_point in parts[1:] {
                points := strings.split(face_point, "/", allocator=context.allocator)

                vertex_index, e := strconv.parse_int(points[0])
                texture_coord_index, e1 := strconv.parse_int(points[1])
                normal_index, e2 := strconv.parse_int(points[2]) // not being used for now

                if !e || !e1 || !e2 {
                    fmt.println("sore err")
                    continue
                } 

                append_face_point(&model, vertex_index - 1, texture_coord_index - 1)
            }
        }
        line_n += 1
	}

    return model, false
}
