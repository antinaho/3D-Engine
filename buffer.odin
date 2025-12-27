package main

Buffer_Usage :: enum {
    Vertex,
    Index,
    Uniform,
    Storage,
}

Buffer_Access :: enum {
    Static,   // Write once, read many (GPU only)
    Dynamic,  // Update frequently (CPU → GPU)
    Staging,  // CPU readable (GPU → CPU)
}

Buffer :: struct {
    handle: rawptr,
    size: int,
    usage: Buffer_Usage,
    access: Buffer_Access,
}

init_buffer :: proc {
    init_buffer_with_size,
    init_buffer_with_count,
}

// Initialize a buffer with given size and usage
init_buffer_with_count :: proc(
    count: int,
    type: typeid,
    usage: Buffer_Usage,
    access: Buffer_Access = .Static,
) -> Buffer {
    return init_buffer_with_size(size_of(type) * count, usage, access)
}

// Initialize a buffer with given size and usage
init_buffer_with_size :: proc(
    size: int,
    usage: Buffer_Usage,
    access: Buffer_Access = .Static,
) -> Buffer {
    when RENDERER == .Metal {
        return metal_init_buffer(size, usage, access)
    } else when RENDERER == .Vulkan {
        return vulkan_init_buffer(size, usage, access)
    } else when RENDERER == .D3D12 {
        return d3d12_init_buffer(size, usage, access)
    } else {
        //TODO some logging
        os.exit(1)
    }
}

// Fill buffer with data (upload to GPU)
fill_buffer :: proc(buffer: ^Buffer, data: rawptr, size: int, offset: int = 0) {
    assert(offset + size <= buffer.size, "Buffer overflow")
    
    when RENDERER == .Metal {
        metal_fill_buffer(buffer, data, size, offset)
    } else when RENDERER == .Vulkan {
        vulkan_fill_buffer(buffer, data, size, offset)
    } else when RENDERER == .D3D12 {
        d3d12_fill_buffer(buffer, data, size, offset)
    }
}

// Fill buffer with typed slice
fill_buffer_slice :: proc(buffer: ^Buffer, data: $T/[]$E, offset: int = 0) {
    fill_buffer(buffer, raw_data(data), len(data) * size_of(E), offset)
}

// Release buffer and free resources
release_buffer :: proc(buffer: ^Buffer) {
    when RENDERER == .Metal {
        metal_release_buffer(buffer)
    } else when RENDERER == .Vulkan {
        vulkan_release_buffer(buffer)
    } else when RENDERER == .D3D12 {
        d3d12_release_buffer(buffer)
    }
    
    buffer.handle = nil
    buffer.size = 0
}
