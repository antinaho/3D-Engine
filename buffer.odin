package main

Buffer :: struct {
    handle: rawptr,
    size: int,
    usage: BufferKind,
    access: BufferAccess,
}

BufferKind :: enum {
    Vertex,
    Index,
    Uniform,
}

BufferAccess :: enum {
    Static,
    Dynamic,
}

// Initialize a buffer with given size and usage
init_buffer_with_size :: proc(
    size: int,
    usage: BufferKind,
    access: BufferAccess,
) -> Buffer {
    assert(size > 0, "Trying to create zero / negative size buffer")
    when RENDERER_KIND == .Metal {
        return metal_init_buffer(size, usage, access)
    }
}

// Fill buffer with data
fill_buffer :: proc(buffer: ^Buffer, data: rawptr, size: int, offset: int) {
    assert(offset + size <= buffer.size, "Buffer overflow")
    
    when RENDERER_KIND == .Metal {
        metal_fill_buffer(buffer, data, size, offset)
    }
}

// Fill buffer with typed slice
fill_buffer_slice :: proc(buffer: ^Buffer, data: $T/[]$E, offset: int) {
    fill_buffer(buffer, raw_data(data), len(data) * size_of(E), offset)
}

// Release buffer and free resources
release_buffer :: proc(buffer: ^Buffer) {
    when RENDERER_KIND == .Metal {
        metal_release_buffer(buffer)
    }
    
    buffer.handle = nil
    buffer.size = 0
}
