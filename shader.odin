package main

import "core:os"
import "core:strings"
import "core:fmt"

ShaderLanguage :: enum {
    SPIRV,      // Vulkan native, can convert to others
    MSL,        // Metal Shading Language
    HLSL,       // Direct3D
}

ShaderDesc :: struct {
    source: string,
    shader_language: ShaderLanguage,
    stage: ShaderStage,
    entry_point: string,  // "main", "vertex_main", etc.
}

Shader :: struct {
    handle: rawptr,
    stage: ShaderStage,
}

compile_shader :: proc(desc: ShaderDesc) -> (Shader, bool) {
    when RENDERER == .Metal {
        return metal_compile_shader(desc)
    } else when RENDERER == .Vulkan {
        return vulkan_compile_shader(desc)
    }
}

load_shader :: proc(path: string, stage: ShaderStage, entry_point: string) -> (Shader, bool) {
    source, ok := os.read_entire_file(path, context.temp_allocator)
    assert(ok, fmt.tprintf("Cant open shader file at: %v", path))
    if !ok do return {}, false
    
    // Detect type from extension
    source_type: ShaderLanguage
    if strings.has_suffix(path, ".metal") {
        source_type = .MSL
    } else if strings.has_suffix(path, ".hlsl") {
        source_type = .HLSL
    } else if strings.has_suffix(path, ".spv") {
        source_type = .SPIRV
    }
    
    return compile_shader(ShaderDesc{
        source = string(source),
        shader_language = source_type,
        stage = stage,
        entry_point = entry_point,
    })
}
