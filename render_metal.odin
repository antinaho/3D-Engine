#+private file

package main

import MTL "vendor:darwin/Metal"
import MTLK "vendor:darwin/MetalKit"
import CA "vendor:darwin/QuartzCore"
import NS "core:sys/darwin/Foundation"

import "core:fmt"

@(private="package")
RENDERER_METAL :: RendererInterface{
    config_size = metal_state_size,
    init        = metal_init,
	draw		= metal_draw,
	cleanup 	= metal_cleanup,
}

MetalRenderState :: struct {
    device: ^MTL.Device,
    swapchain: ^CA.MetalLayer,
    command_queue: ^MTL.CommandQueue,
    pipelinestate: ^MTL.RenderPipelineState,
    position_buffer: ^MTL.Buffer,
    color_buffer: ^MTL.Buffer,

    compile_options: ^MTL.CompileOptions,
}

metal_cleanup :: proc() {
    state.compile_options->release()
    free(state)
}

metal_state_size :: proc() -> int {
    return size_of(MetalRenderState)
}

state: ^MetalRenderState

metal_init :: proc(wsi: WSI, renderer_state: rawptr) -> rawptr {

    // state = (^MetalRenderState)(renderer_state)

    // state.device = MTL.CreateSystemDefaultDevice()

    // fmt.println(state.device->name()->odinString())
    
    // w := cast(^NS.Window)window.window_handle()

    // state.swapchain = CA.MetalLayer.layer()
    // state.swapchain->setDevice(state.device)
    // state.swapchain->setPixelFormat(.BGRA8Unorm_sRGB)
    // state.swapchain->setFramebufferOnly(true)
    // state.swapchain->setFrame(w->frame())

    // w->contentView()->setLayer(state.swapchain)
    // w->setOpaque(true)
    // w->setBackgroundColor(nil)

    // state.command_queue = state.device->newCommandQueue()
    
    // state.compile_options = NS.new(MTL.CompileOptions)

    // program_source :: `
	// using namespace metal;
	// struct ColoredVertex {
	// 	float4 position [[position]];
	// 	float4 color;
	// };
	// vertex ColoredVertex vertex_main(constant float4 *position [[buffer(0)]],
	//                                  constant float4 *color    [[buffer(1)]],
	//                                  uint vid                  [[vertex_id]]) {
	// 	ColoredVertex vert;
	// 	vert.position = position[vid];
	// 	vert.color    = color[vid];
	// 	return vert;
	// }
	// fragment float4 fragment_main(ColoredVertex vert [[stage_in]]) {
	// 	return vert.color;
	// }
	// `

    // program_library := state.device->newLibraryWithSource(NS.AT(program_source), state.compile_options) or_return

    // vertex_program := program_library->newFunctionWithName(NS.AT("vertex_main"))
    // fragment_program := program_library->newFunctionWithName(NS.AT("fragment_main"))

    // assert(vertex_program != nil)
    // assert(fragment_program != nil)

    // pipeline_state_descriptor := NS.new(MTL.RenderPipelineDescriptor)
    // pipeline_state_descriptor->colorAttachments()->object(0)->setPixelFormat(.BGRA8Unorm_sRGB)
    // pipeline_state_descriptor->setVertexFunction(vertex_program)
    // pipeline_state_descriptor->setFragmentFunction(fragment_program)


    // state.pipelinestate = state.device->newRenderPipelineState(pipeline_state_descriptor)  or_return

    // positions := [?][4]f32{
	// 	{ 0.0,  0.5, 0, 1},
	// 	{-0.5, -0.5, 0, 1},
	// 	{ 0.5, -0.5, 0, 1},
	// }
	// colors := [?][4]f32{
	// 	{1, 0, 0, 1},
	// 	{0, 1, 0, 1},
	// 	{0, 0, 1, 1},
	// }

    // state.position_buffer = state.device->newBufferWithSlice(positions[:], {})
	// state.color_buffer    = state.device->newBufferWithSlice(colors[:],    {})

    return nil
}

metal_draw :: proc() {
    NS.scoped_autoreleasepool()

    drawable := state.swapchain->nextDrawable()
    assert(drawable != nil)

    pass := MTL.RenderPassDescriptor.renderPassDescriptor()
    color_attachment := pass->colorAttachments()->object(0)
    assert(color_attachment != nil)
    color_attachment->setClearColor(MTL.ClearColor{0.25, 0.5, 1.0, 1.0})
    color_attachment->setLoadAction(.Clear)
    color_attachment->setStoreAction(.Store)
    color_attachment->setTexture(drawable->texture())

    command_buffer := state.command_queue->commandBuffer()
    render_encoder := command_buffer->renderCommandEncoderWithDescriptor(pass)

    render_encoder->setRenderPipelineState(state.pipelinestate)
    render_encoder->setVertexBuffer(state.position_buffer, 0, 0)
    render_encoder->setVertexBuffer(state.color_buffer,    0, 1)
    render_encoder->drawPrimitivesWithInstanceCount(.Triangle, 0, 3, 1)

    render_encoder->endEncoding()

    command_buffer->presentDrawable(drawable)
    command_buffer->commit()
}