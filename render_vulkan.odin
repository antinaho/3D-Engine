#+private file


//TODO Redone everything
// Just don't bother even looking here...

package main

import vk "vendor:vulkan"
import "core:log"
import "core:slice"
import stbi "vendor:stb/image"
import "core:math"
import "core:mem"
import "core:time"
import "core:math/linalg/glsl"
import "core:fmt"

_ :: fmt

import "core:strings"

Vertex :: struct {
	position: glsl.vec3,
	color: glsl.vec3,
	tex_coord: glsl.vec2
}

UniformBufferObject :: struct #align(16) {
	model: glsl.mat4,
	view: glsl.mat4,
	proj: glsl.mat4,
}


when ODIN_OS == .Darwin {
REQUIRED_EXTENSIONS := []cstring {
	vk.KHR_SWAPCHAIN_EXTENSION_NAME,
	vk.KHR_PORTABILITY_SUBSET_EXTENSION_NAME
}
} else {
REQUIRED_EXTENSIONS := []cstring {
	vk.KHR_SWAPCHAIN_EXTENSION_NAME,
}
}

vk_cleanup :: proc() {
	vk.DeviceWaitIdle(state.device)

	cleanup_swapchain()

	vk.DestroySampler(state.device, state.texture_sampler, nil)

	// All image views + images + memory
	vk.DestroyImageView(state.device, state.texture_image_view, nil)
	vk.DestroyImage(state.device, state.texture_image, nil)
	vk.FreeMemory(state.device, state.texture_image_memory, nil)

	for i in 0..<MAX_FRAMES_IN_FLIGHT {
		vk.DestroyBuffer(state.device, state.uniform_buffers[i], nil)
		vk.FreeMemory(state.device, state.uniform_buffers_memory[i], nil)
	}

	vk.DestroyDescriptorPool(state.device, state.descriptor_pool, nil)
	vk.DestroyDescriptorSetLayout(state.device, state.descriptor_set_layout, nil)

	vk.DestroyBuffer(state.device, state.index_buffer, nil)
	vk.FreeMemory(state.device, state.index_buffer_memory, nil)

	vk.DestroyBuffer(state.device, state.vertex_buffer, nil)
	vk.FreeMemory(state.device, state.vertex_buffer_memory, nil)

	vk.DestroyPipeline(state.device, state.graphics_pipeline, nil)
	vk.DestroyPipelineLayout(state.device, state.pipeline_layout, nil)

	vk.DestroyRenderPass(state.device, state.renderpass, nil)

	for i in 0..<MAX_FRAMES_IN_FLIGHT {
		vk.DestroySemaphore(state.device, state.image_available_semaphores[i], nil)
		vk.DestroySemaphore(state.device, state.render_finished_semaphores[i], nil)
		vk.DestroyFence(state.device, state.in_flight_fences[i], nil)
	}

	vk.DestroyCommandPool(state.device, state.command_pool, nil)

	vk.DestroyDevice(state.device, nil)		

when ODIN_DEBUG {
	generic := vk.GetInstanceProcAddr(state.instance, "vkDestroyDebugUtilsMessengerEXT") 
	func := cast(vk.ProcDestroyDebugUtilsMessengerEXT)generic
	if func != nil {
		func(state.instance, state.debug_messenger, nil);
	}	
}

	vk.DestroySurfaceKHR(state.instance, state.surface, nil)			
	vk.DestroyInstance(state.instance, nil)		
	
	free(state)
}

state: ^VulkanRendererState

MAX_FRAMES_IN_FLIGHT :: 2

VulkanRendererState :: struct {
	start_time: time.Time,

    instance: vk.Instance,
	surface: vk.SurfaceKHR,

	physical_device: vk.PhysicalDevice,

	device: vk.Device,
	graphics_queue: vk.Queue,
	present_queue: vk.Queue,

	debug_messenger: vk.DebugUtilsMessengerEXT,

	graphics_family_index : u32,
	present_family_index : u32,

	swapchain: vk.SwapchainKHR,
	swapchain_images: []vk.Image,
	swapchain_format: vk.SurfaceFormatKHR,
	swapchain_extent: vk.Extent2D,
	swapchain_views: []vk.ImageView,
	swapchain_framebuffers: [dynamic]vk.Framebuffer,

	renderpass: vk.RenderPass,

	descriptor_set_layout: vk.DescriptorSetLayout,

	pipeline_layout: vk.PipelineLayout,
	graphics_pipeline: vk.Pipeline,

	command_pool: vk.CommandPool,

	depth_image: vk.Image,
	depth_image_memory: vk.DeviceMemory,
	depth_image_view: vk.ImageView,



	// These to function + array
	texture_image: vk.Image,
	texture_image_view: vk.ImageView,
	texture_image_memory: vk.DeviceMemory,
	mip_levels: u32,


	texture_sampler: vk.Sampler,


	// These function + array
	model_verts: [dynamic]Vertex,
	model_indices: [dynamic]u32,



	vertex_buffer: vk.Buffer,
	vertex_buffer_memory: vk.DeviceMemory,

	index_buffer: vk.Buffer,
	index_buffer_memory: vk.DeviceMemory,

	uniform_buffers: [MAX_FRAMES_IN_FLIGHT]vk.Buffer,
	uniform_buffers_memory: [MAX_FRAMES_IN_FLIGHT]vk.DeviceMemory,
	uniform_buffers_mapped: [MAX_FRAMES_IN_FLIGHT]rawptr,

	descriptor_pool: vk.DescriptorPool,
	descriptor_sets: [MAX_FRAMES_IN_FLIGHT]vk.DescriptorSet,

	command_buffers: [MAX_FRAMES_IN_FLIGHT]vk.CommandBuffer,

	image_available_semaphores: [MAX_FRAMES_IN_FLIGHT]vk.Semaphore,
	render_finished_semaphores: [MAX_FRAMES_IN_FLIGHT]vk.Semaphore,
	in_flight_fences: [MAX_FRAMES_IN_FLIGHT]vk.Fence,

	current_frame: u32,
}

@(private="package")
VulkanWSI :: struct {
	get_global_proc_addresses: proc() -> rawptr,
	get_required_instance_extensions: proc() -> []cstring,
	create_surface: proc(window: rawptr, instance: vk.Instance, surface: ^vk.SurfaceKHR) -> vk.Result,
}

vk_config_size :: proc() -> int {
    return size_of(VulkanRendererState)
}

vk_init :: proc(renderer_state: rawptr) -> rawptr {
	state = cast(^VulkanRendererState)renderer_state
    vk_wsi: VulkanWSI

	state.start_time = time.now()

	{	// Instance

		vk.load_proc_addresses_global(vk_wsi.get_global_proc_addresses())
		if vk.CreateInstance == nil do log.panic("Vulkan function pointers not loaded")

		app_info := vk.ApplicationInfo {
			sType = .APPLICATION_INFO,

			pApplicationName = "MyCoolRenderer",
			applicationVersion = 0,
			
			pEngineName = "MyCoolEngine",
			engineVersion = 0,
			
			apiVersion = vk.API_VERSION_1_2,
		}

		create_info := vk.InstanceCreateInfo {
			sType = .INSTANCE_CREATE_INFO,
			pApplicationInfo = &app_info,
		}

		// Validation layers
	when ODIN_DEBUG {

		required_layers := []cstring { "VK_LAYER_KHRONOS_validation" }
		
		layer_count: u32
		vk.EnumerateInstanceLayerProperties(&layer_count, nil)
		available_layers := make([]vk.LayerProperties, layer_count, context.temp_allocator)
		vk.EnumerateInstanceLayerProperties(&layer_count, raw_data(available_layers))

		for required_layer in required_layers {
			layer_found := false
			for &available_layer in available_layers {
				
				if cstring(&available_layer.layerName[0]) == required_layer {
					layer_found = true
					break
				}
			}

			if !layer_found {
				log.panicf("Validation layer: %v not found", required_layer)
			}
		}

		create_info.enabledLayerCount = u32(len(required_layers))
		create_info.ppEnabledLayerNames = raw_data(required_layers)

		
	} // ODIN_DEBUG 
	else {
		create_info.enabledLayerCount = 0
		create_info.ppEnabledLayerNames = nil
	}

		exs := vk_wsi.get_required_instance_extensions()
		required_extensions := slice.clone_to_dynamic(exs, context.temp_allocator)

	when ODIN_DEBUG {
		append(&required_extensions, vk.EXT_DEBUG_UTILS_EXTENSION_NAME)
	}

	when ODIN_OS == .Darwin {
		create_info.flags |= {.ENUMERATE_PORTABILITY_KHR}
		append(&required_extensions, vk.KHR_PORTABILITY_ENUMERATION_EXTENSION_NAME)
	}

		extension_count: u32
		vk.EnumerateInstanceExtensionProperties(nil, &extension_count, nil)
		available_extensions := make([]vk.ExtensionProperties, extension_count, context.temp_allocator)
		vk.EnumerateInstanceExtensionProperties(nil, &extension_count, raw_data(available_extensions))

		for required_extension in required_extensions {
			extension_found := false
			for &available_extension in available_extensions {
				
				if cstring(&available_extension.extensionName[0]) == required_extension {
					extension_found = true
					break
				}
			}
			
			if !extension_found {
				log.panicf("Extension: %v not found", required_extension)
			}
		}

		create_info.enabledExtensionCount = u32(len(required_extensions))
		create_info.ppEnabledExtensionNames = raw_data(required_extensions)

		assert_success(vk.CreateInstance(&create_info, nil, &state.instance))
		
		vk.load_proc_addresses_instance(state.instance)
	}	log.debug("Vk: Instance created")

when ODIN_DEBUG {
	create_debug_messenger() 
} 

	
	{ // Surface
		//assert_success(vk_wsi.create_surface(window.window_handle(), state.instance, &state.surface))
	} log.debug("Vk: Surface created")

	{ // Physical device
		count: u32
		assert_success(vk.EnumeratePhysicalDevices(state.instance, &count, nil))

		if count == 0 do log.panic("vulkan: No GPUs found")

		devices := make([]vk.PhysicalDevice, count, context.temp_allocator)
		assert_success(vk.EnumeratePhysicalDevices(state.instance, &count, raw_data(devices)))

		best_device_score := -1
		for device in devices {
			if score := score_physical_device(device); score > best_device_score {
				state.physical_device = device
				best_device_score = score
			}
		}

		if best_device_score <= 0 {
			log.panic("vulkan: no suitable GPU found")
		}

		byte_arr_str :: proc(arr: ^[$N]byte) -> string {
			return strings.truncate_to_byte(string(arr[:]), 0)
		}

		score_physical_device :: proc(device: vk.PhysicalDevice) -> (score: int) {
		
			properties: vk.PhysicalDeviceProperties
			vk.GetPhysicalDeviceProperties(device, &properties)

			name := byte_arr_str(&properties.deviceName)
			log.infof("vulkan: evaluating device %q", name)
			defer log.infof("vulkan: device %q scored %v", name, score)

			features: vk.PhysicalDeviceFeatures
			vk.GetPhysicalDeviceFeatures(device, &features)

			{ // Extensions
				extensions, result := physical_device_extensions(device, context.temp_allocator)
				if result != .SUCCESS {
					log.infof("vulkan: enumerate device extension properties failed: %v", result)
					return 0
				}

				req_loop: for required in REQUIRED_EXTENSIONS {
					for &extension in extensions {
						extension_name := byte_arr_str(&extension.extensionName)
						if extension_name == string(required) {
							continue req_loop
						}
					}

					log.infof("vulkan: device doesn't support required extension %q", required)
					return 0
				}	
			}

			{ // Swapchain
				details, result := query_swapchain_support(device, context.temp_allocator)
				if result != .SUCCESS {
					log.infof("vulkan: query swapchain support failed: %v", result)
					return 0
				}

				if len(details.surface_formats) == 0 || len(details.present_modes) == 0 {
					log.info("vulkan: device does not support swapchain")
					return 0
				}
			}

			indices := find_queue_families(device)
			
			if _, has_graphiscs := indices.graphics_family.?; !has_graphiscs {
				log.info("vulkan: device does not have a graphics queue")
				return 0
			}

			if _, has_present := indices.present_family.?; !has_present {
				log.info("vulkan: device does not have a presentation queue")
				return 0
			}

			switch properties.deviceType {
			case .DISCRETE_GPU:
				score += 300_000
			case .INTEGRATED_GPU:
				score += 200_000
			case .VIRTUAL_GPU:
				score += 100_000
			case .CPU, .OTHER:
			}
			log.infof("vulkan: scored %i based on device type %v", score, properties.deviceType)

			score += int(properties.limits.maxImageDimension2D)
			log.infof(
				"vulkan: added the max 2D image dimensions (texture size) of %v to the score",
				properties.limits.maxImageDimension2D,
			)

			return
		}
	} log.debug("Vk: physical device chosen")


	{ // Logical device

		indices := find_queue_families(state.physical_device)

		indices_set: map[u32]struct {}
		indices_set[indices.graphics_family.?] = {}
		indices_set[indices.present_family.?] = {}

		queue_priority: f32 = 1.0
		queue_create_infos := make([dynamic]vk.DeviceQueueCreateInfo, 0, len(indices_set), context.temp_allocator)
		for queue_index, _ in indices_set {
			append(&queue_create_infos,
				vk.DeviceQueueCreateInfo {
					sType = .DEVICE_QUEUE_CREATE_INFO,
					queueFamilyIndex = queue_index,
					queueCount = 1,
					pQueuePriorities = &queue_priority
			})
		}

		device_features: vk.PhysicalDeviceFeatures
		device_features.samplerAnisotropy = true

		create_info: vk.DeviceCreateInfo = {
			sType = .DEVICE_CREATE_INFO,
			pQueueCreateInfos = raw_data(queue_create_infos),
			queueCreateInfoCount = cast(u32)len(queue_create_infos),
			pEnabledFeatures = &device_features,
			enabledExtensionCount = cast(u32)len(REQUIRED_EXTENSIONS),
			ppEnabledExtensionNames = raw_data(REQUIRED_EXTENSIONS),

			// Validation layers are ignored, only considered when creating instance
			enabledLayerCount = 0, 
			ppEnabledLayerNames = nil,
		}

		assert_success(vk.CreateDevice(state.physical_device, &create_info, nil, &state.device))
	
		vk.GetDeviceQueue(state.device, indices.graphics_family.?, 0, &state.graphics_queue)
		vk.GetDeviceQueue(state.device, indices.present_family.?, 0, &state.present_queue)

		state.graphics_family_index = indices.graphics_family.?
		state.present_family_index = indices.present_family.?
	} log.debug("Vk: logical device chosen")


	{ // Swapchain
		create_swapchain()
	} log.debug("Vk: created swapchain")

	{ // Image views
		create_image_views()
	} log.debug("Vk: created image views")

	{ // Render pass
		depth_attachment := vk.AttachmentDescription {
			format = find_depth_format(),
			samples = {._1},
			loadOp = .CLEAR,
			storeOp = .DONT_CARE,
			stencilLoadOp = .DONT_CARE,
			stencilStoreOp = .DONT_CARE,
			initialLayout = .UNDEFINED,
			finalLayout = .DEPTH_STENCIL_ATTACHMENT_OPTIMAL,
		}

		depth_attachment_ref := vk.AttachmentReference {
			attachment = 1,
			layout = .STENCIL_ATTACHMENT_OPTIMAL,
		}

		color_attachment := vk.AttachmentDescription {
			format = state.swapchain_format.format,
			samples = {._1},
			loadOp = .CLEAR,
			storeOp = .STORE,
			stencilLoadOp = .DONT_CARE,
			stencilStoreOp = .DONT_CARE,
			initialLayout = .UNDEFINED,
			finalLayout = .PRESENT_SRC_KHR,
		}

		color_attachment_ref := vk.AttachmentReference {
			attachment = 0,
			layout = .COLOR_ATTACHMENT_OPTIMAL,
		}

		subpass := vk.SubpassDescription {
			pipelineBindPoint = .GRAPHICS,
			colorAttachmentCount = 1,
			pColorAttachments = &color_attachment_ref,
			pDepthStencilAttachment = &depth_attachment_ref,
		}

		dependency := vk.SubpassDependency {
			srcSubpass = vk.SUBPASS_EXTERNAL,
			dstSubpass = 0,
			srcStageMask = {.COLOR_ATTACHMENT_OUTPUT, .LATE_FRAGMENT_TESTS},
			srcAccessMask = {.DEPTH_STENCIL_ATTACHMENT_WRITE},
			dstStageMask = {.COLOR_ATTACHMENT_OUTPUT, .EARLY_FRAGMENT_TESTS},
			dstAccessMask = {.COLOR_ATTACHMENT_WRITE, .DEPTH_STENCIL_ATTACHMENT_WRITE},
		}

		attachments := [2]vk.AttachmentDescription {
			color_attachment,
			depth_attachment
		}

		render_pass_info := vk.RenderPassCreateInfo {
			sType = .RENDER_PASS_CREATE_INFO,
			attachmentCount = len(attachments),
			pAttachments = &attachments[0],
			subpassCount = 1,
			pSubpasses = &subpass,
			dependencyCount = 1,
			pDependencies = &dependency,
		}

		assert_success(vk.CreateRenderPass(state.device, &render_pass_info, nil, &state.renderpass))
	} log.debug("Vk: renderpass created")

	{	// Descriptor set layout
		ubo_layout_binding := vk.DescriptorSetLayoutBinding {
			binding = 0,
			descriptorCount = 1,
			descriptorType = .UNIFORM_BUFFER,
			stageFlags = {.VERTEX},
			pImmutableSamplers = nil,
		}

		sampler_layout_binding := vk.DescriptorSetLayoutBinding {
			binding = 1,
			descriptorCount = 1,
			descriptorType = .COMBINED_IMAGE_SAMPLER,
			stageFlags = {.FRAGMENT},
			pImmutableSamplers = nil,
		}

		bindings := [2]vk.DescriptorSetLayoutBinding {
			ubo_layout_binding,
			sampler_layout_binding,
		}

		create_info := vk.DescriptorSetLayoutCreateInfo {
			sType = .DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
			bindingCount = len(bindings),
			pBindings = raw_data(bindings[:]),
		}

		assert_success(vk.CreateDescriptorSetLayout(state.device, &create_info, nil, &state.descriptor_set_layout))
	} log.debug("Vk: descriptor set layout created")


	{ // Graphics pipeline
		create_shader_module :: proc(code: []byte) -> (shader_module: vk.ShaderModule) {
			as_u32 := slice.reinterpret([]u32, code)

			create_info: vk.ShaderModuleCreateInfo = {
				sType = .SHADER_MODULE_CREATE_INFO,
				codeSize = len(code),
				pCode = raw_data(as_u32)
			}

			assert_success(vk.CreateShaderModule(state.device, &create_info, nil, &shader_module))

			return
		}
		vert_shader_code := []byte {}
		frag_shader_code := []byte {}

		vert_shader_module := create_shader_module(vert_shader_code)
		frag_shader_module := create_shader_module(frag_shader_code)

		vertex_shader_stage_info :vk.PipelineShaderStageCreateInfo = {
			sType = .PIPELINE_SHADER_STAGE_CREATE_INFO,
			stage = {.VERTEX},
			module = vert_shader_module,
			pName = "main",
		}

		fragment_shader_stage_info: vk.PipelineShaderStageCreateInfo = {
			sType = .PIPELINE_SHADER_STAGE_CREATE_INFO,
			stage = {.FRAGMENT},
			module = frag_shader_module,
			pName = "main",
		}

		shader_stages := [2]vk.PipelineShaderStageCreateInfo {
			vertex_shader_stage_info, fragment_shader_stage_info
		}

		dynamic_states := []vk.DynamicState {
			vk.DynamicState.VIEWPORT,
			vk.DynamicState.SCISSOR
		}

		dynamic_state := vk.PipelineDynamicStateCreateInfo {
			sType = .PIPELINE_DYNAMIC_STATE_CREATE_INFO,
			dynamicStateCount = cast(u32)len(dynamic_states),
			pDynamicStates = raw_data(dynamic_states)
		}

		binding_description := get_vertex_binding_description()
		attribute_description := get_vertex_attribute_description()

		vertex_input_info := vk.PipelineVertexInputStateCreateInfo {
			sType = .PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,	
			vertexBindingDescriptionCount = 1,
			vertexAttributeDescriptionCount = cast(u32)len(attribute_description),

			pVertexBindingDescriptions = &binding_description,
			pVertexAttributeDescriptions = &attribute_description[0],
		}

		input_assembly := vk.PipelineInputAssemblyStateCreateInfo {
			sType = .PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
			topology = .TRIANGLE_LIST,
			primitiveRestartEnable = false,
		}

		viewport_state := vk.PipelineViewportStateCreateInfo {
			sType = .PIPELINE_VIEWPORT_STATE_CREATE_INFO,
			viewportCount = 1,
			scissorCount = 1,
		}

		rasterizer := vk.PipelineRasterizationStateCreateInfo {
			sType = .PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
			depthClampEnable = false,
			rasterizerDiscardEnable = false,
			polygonMode = .FILL,
			lineWidth = 1,
			cullMode = {.BACK},
			frontFace = .COUNTER_CLOCKWISE,
			depthBiasEnable = false,
			depthBiasConstantFactor = 0,
			depthBiasClamp = 0,
			depthBiasSlopeFactor = 0,
		}

		multisampling := vk.PipelineMultisampleStateCreateInfo {
			sType = .PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
			sampleShadingEnable = false,
			rasterizationSamples = {._1},
			minSampleShading = 1,
			pSampleMask = nil,
			alphaToCoverageEnable = false,
			alphaToOneEnable = false,
		}

		color_blend_attachment := vk.PipelineColorBlendAttachmentState {
			colorWriteMask = {.R, .G, .B, .A},
			blendEnable = false,
			srcColorBlendFactor = .ONE,
			dstColorBlendFactor = .ZERO,
			colorBlendOp = .ADD,
			srcAlphaBlendFactor = .ONE,
			dstAlphaBlendFactor = .ZERO,
			alphaBlendOp = .ADD,
		}

		color_blending := vk.PipelineColorBlendStateCreateInfo {
			sType = .PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
			logicOpEnable = false,
			logicOp = .COPY,
			attachmentCount = 1,
			pAttachments = &color_blend_attachment,
			blendConstants = {0, 0, 0, 0},
		}

		pipeline_layout_info := vk.PipelineLayoutCreateInfo {
			sType = .PIPELINE_LAYOUT_CREATE_INFO,
			setLayoutCount = 1,
			pSetLayouts = &state.descriptor_set_layout,
			pushConstantRangeCount = 0,
			pPushConstantRanges = nil,
		}

		assert_success(vk.CreatePipelineLayout(state.device, &pipeline_layout_info, nil, &state.pipeline_layout))

		depth_stencil := vk.PipelineDepthStencilStateCreateInfo {
			sType = .PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO,
			depthTestEnable = true,
			depthWriteEnable = true,
			depthCompareOp = .LESS,
			depthBoundsTestEnable = false,
			minDepthBounds = 0,
			maxDepthBounds = 1,

			stencilTestEnable = false,
			front = {},
			back = {},
		}

		pipeline_info := vk.GraphicsPipelineCreateInfo {
			sType = .GRAPHICS_PIPELINE_CREATE_INFO,
			stageCount = 2,
			pStages = raw_data(shader_stages[:]),
			pVertexInputState = &vertex_input_info,
			pInputAssemblyState = &input_assembly,
			pViewportState = &viewport_state,
			pRasterizationState = &rasterizer,
			pMultisampleState = &multisampling,
			pDepthStencilState = &depth_stencil,
			pColorBlendState = &color_blending,
			pDynamicState = &dynamic_state,
			layout = state.pipeline_layout,
			renderPass = state.renderpass,
			subpass = 0,
			basePipelineHandle = 0,
			basePipelineIndex = -1,
		}

		assert_success(vk.CreateGraphicsPipelines(state.device, 0, 1, &pipeline_info, nil, &state.graphics_pipeline))

		vk.DestroyShaderModule(state.device, vert_shader_module, nil)
		vk.DestroyShaderModule(state.device, frag_shader_module, nil)
	} log.debug("Vk: pipeline created")


	{	// Command pool
		graphics_pool := vk.CommandPoolCreateInfo {
			sType = .COMMAND_POOL_CREATE_INFO,
			flags = {.RESET_COMMAND_BUFFER},
			queueFamilyIndex = state.graphics_family_index,
		}

		assert_success(vk.CreateCommandPool(state.device, &graphics_pool, nil, &state.command_pool))	
	} log.debug("Vk: command pool created")


	{	// Depth resources
		create_depth_resources()
	} log.debug("Vk: depth resources created")


	{	// Frame buffers
		create_frame_buffers()
	} log.debug("Vk: framebuffer created")


	// TODO these 2 to load texture func

	{	// Texture image
		width, height, channels: i32
		model_tex :cstring= ""
		pixels := stbi.load(model_tex, &width, &height, &channels, 4)

		if pixels == nil do log.panic("Couldnt load image")

		state.mip_levels = u32(math.floor(math.log2(f32(u32(math.max(width, height)))))) + 1

		image_size := vk.DeviceSize(width * height * 4)

		staging_buffer: vk.Buffer
		staging_buffer_memory: vk.DeviceMemory

		create_buffer(image_size, {.TRANSFER_SRC}, {.HOST_VISIBLE, .HOST_COHERENT}, &staging_buffer, &staging_buffer_memory)

		data: rawptr
		vk.MapMemory(state.device, staging_buffer_memory, 0, image_size, {}, &data)
		mem.copy(data, &pixels[0], int(image_size))
		vk.UnmapMemory(state.device, staging_buffer_memory)

		create_image(u32(width), u32(height), state.mip_levels, .R8G8B8A8_SRGB, .OPTIMAL, {.TRANSFER_DST, .TRANSFER_SRC, .SAMPLED}, {.DEVICE_LOCAL}, &state.texture_image, &state.texture_image_memory)

		transition_image_layout(state.texture_image, .R8G8B8A8_SRGB, .UNDEFINED, .TRANSFER_DST_OPTIMAL, state.mip_levels)
		copy_buffer_to_image(staging_buffer, state.texture_image, u32(width), u32(height))
		generate_mipmaps(state.texture_image, .R8G8B8A8_SRGB, u32(width), u32(height), state.mip_levels)	


		vk.DestroyBuffer(state.device, staging_buffer, nil)
		vk.FreeMemory(state.device, staging_buffer_memory, nil)
	} log.debug("Vk: texture loaded loaded")


	{	// Texture image view
		state.texture_image_view = create_image_view(state.texture_image, .R8G8B8A8_SRGB, {.COLOR}, state.mip_levels)
	} log.debug("Vk: texture image views created")


	{	// Sampler

		sampler_info := vk.SamplerCreateInfo {
			sType = .SAMPLER_CREATE_INFO,
			magFilter = .LINEAR,
			minFilter = .LINEAR,

			addressModeU = .REPEAT,
			addressModeV = .REPEAT,
			addressModeW = .REPEAT,

			borderColor = .INT_OPAQUE_BLACK,
			unnormalizedCoordinates = false,
			
			compareEnable = false,
			compareOp = .ALWAYS,

			mipmapMode = .LINEAR,
			mipLodBias = 0,
			minLod = 0,
			maxLod = vk.LOD_CLAMP_NONE,
		}

		props: vk.PhysicalDeviceProperties
		vk.GetPhysicalDeviceProperties(state.physical_device, &props)

		features: vk.PhysicalDeviceFeatures
		vk.GetPhysicalDeviceFeatures(state.physical_device, &features)
		
		if features.samplerAnisotropy {
			sampler_info.anisotropyEnable = true
			sampler_info.maxAnisotropy = props.limits.maxSamplerAnisotropy
		} else {
			sampler_info.anisotropyEnable = false
			sampler_info.maxAnisotropy = 1.0
		}

		assert_success(vk.CreateSampler(state.device, &sampler_info, nil, &state.texture_sampler))
	} log.debug("Vk: texture sampler created")



	// This to function

	{	// Load model
		model, err := read_model_from_file("viking_room.obj")
		if err do log.panicf("Error loading the model file: %v", err)

		vertex_set: map[Vertex]u32
		for face in model.faces {
			vertex := Vertex {
				position = model.vertices[face.vertex_index],
				tex_coord = {model.texcoords[face.texture_index].x, 1 - model.texcoords[face.texture_index].y},
				color = {1, 1, 1}
			}
			
			if vertex not_in vertex_set {
				vertex_set[vertex] = u32(len(state.model_verts))
				append(&state.model_verts, vertex)
			}

			append(&state.model_indices, vertex_set[vertex])
		}
	} log.debug("Vk: model loaded")



	{	// Vertex buffer
		buffer_size := vk.DeviceSize(size_of(Vertex) * len(state.model_verts))

		staging_buffer: vk.Buffer
		staging_buffer_memory: vk.DeviceMemory

		create_buffer(buffer_size, {.TRANSFER_SRC}, {.HOST_VISIBLE, .HOST_COHERENT}, &staging_buffer, &staging_buffer_memory)

		data: rawptr
		assert_success(vk.MapMemory(state.device, staging_buffer_memory, 0, buffer_size, {}, &data))
		//mem.copy(data, raw_data(VERTICES), cast(int)buffer_size)
		mem.copy(data, &state.model_verts[0], cast(int)buffer_size)
		vk.UnmapMemory(state.device, staging_buffer_memory)

		create_buffer(buffer_size, {.TRANSFER_DST, .VERTEX_BUFFER}, {.DEVICE_LOCAL}, &state.vertex_buffer, &state.vertex_buffer_memory)

		copy_buffer(staging_buffer, state.vertex_buffer, buffer_size)

		vk.DestroyBuffer(state.device, staging_buffer, nil)
		vk.FreeMemory(state.device, staging_buffer_memory, nil)
	} log.debug("Vk: vertex buffer created")


	{	// Index buffer
		buffer_size := vk.DeviceSize(size_of(u32) * len(state.model_indices))

		staging_buffer: vk.Buffer
		staging_buffer_memory: vk.DeviceMemory

		create_buffer(buffer_size, {.TRANSFER_SRC}, {.HOST_VISIBLE, .HOST_COHERENT}, &staging_buffer, &staging_buffer_memory)

		data: rawptr
		assert_success(vk.MapMemory(state.device, staging_buffer_memory, 0, buffer_size, {}, &data))
		mem.copy(data, &state.model_indices[0], cast(int)buffer_size)
		vk.UnmapMemory(state.device, staging_buffer_memory)

		create_buffer(buffer_size, {.TRANSFER_DST, .INDEX_BUFFER}, {.DEVICE_LOCAL}, &state.index_buffer, &state.index_buffer_memory)

		copy_buffer(staging_buffer, state.index_buffer, buffer_size)

		vk.DestroyBuffer(state.device, staging_buffer, nil)
		vk.FreeMemory(state.device, staging_buffer_memory, nil)
	} log.debug("Vk: index buffer created")


	{	// Uniform buffers
		buffer_size := vk.DeviceSize(size_of(UniformBufferObject))

		for i in 0..<MAX_FRAMES_IN_FLIGHT {
			create_buffer(buffer_size, {.UNIFORM_BUFFER}, {.HOST_VISIBLE, .HOST_COHERENT}, &state.uniform_buffers[i], &state.uniform_buffers_memory[i])
			assert_success(vk.MapMemory(state.device, state.uniform_buffers_memory[i], 0, buffer_size, {}, &state.uniform_buffers_mapped[i]))
		}
	} log.debug("Vk: uniform buffer created")


	{	// Create descriptor pool
		pool_sizes := [2]vk.DescriptorPoolSize {
			{
				type = .UNIFORM_BUFFER, 
				descriptorCount = MAX_FRAMES_IN_FLIGHT
			},
			{
				type = .COMBINED_IMAGE_SAMPLER, 
				descriptorCount = MAX_FRAMES_IN_FLIGHT
			}
		}

		pool_info := vk.DescriptorPoolCreateInfo {
			sType = .DESCRIPTOR_POOL_CREATE_INFO,
			poolSizeCount = len(pool_sizes),
			pPoolSizes = raw_data(pool_sizes[:]),
			maxSets = MAX_FRAMES_IN_FLIGHT,
		}

		assert_success(vk.CreateDescriptorPool(state.device, &pool_info, nil, &state.descriptor_pool))
	} log.debug("Vk: descriptor pool created")


	{	// Create descriptor sets
		layouts := [2]vk.DescriptorSetLayout { 0..<2 = state.descriptor_set_layout }

		alloc_info := vk.DescriptorSetAllocateInfo {
			sType = .DESCRIPTOR_SET_ALLOCATE_INFO,
			descriptorPool = state.descriptor_pool,
			pSetLayouts = raw_data(layouts[:]),
			descriptorSetCount = MAX_FRAMES_IN_FLIGHT,
		}

		assert_success(vk.AllocateDescriptorSets(state.device, &alloc_info, raw_data(state.descriptor_sets[:])))

		for i in 0..<MAX_FRAMES_IN_FLIGHT {
			buffer_info := vk.DescriptorBufferInfo {
				buffer = state.uniform_buffers[i],
				offset = 0,
				range = size_of(UniformBufferObject),
			}

			image_info := vk.DescriptorImageInfo {
				imageLayout = .SHADER_READ_ONLY_OPTIMAL,
				imageView = state.texture_image_view,
				sampler = state.texture_sampler,
			}

			descriptor_writes := [2]vk.WriteDescriptorSet {
					vk.WriteDescriptorSet {
					sType = .WRITE_DESCRIPTOR_SET,
					dstSet = state.descriptor_sets[i],
					dstBinding = 0,
					dstArrayElement = 0,
					descriptorCount = 1,
					descriptorType = .UNIFORM_BUFFER,
					pBufferInfo = &buffer_info,
				},
					vk.WriteDescriptorSet {
					sType = .WRITE_DESCRIPTOR_SET,
					dstSet = state.descriptor_sets[i],
					dstBinding = 1,
					dstArrayElement = 0,
					descriptorCount = 1,
					descriptorType = .COMBINED_IMAGE_SAMPLER,
					pImageInfo = &image_info
				}
			}

			vk.UpdateDescriptorSets(state.device, len(descriptor_writes), raw_data(descriptor_writes[:]), 0, nil)
		}
	} log.debug("Vk: descriptor sets created")


	{	// Command buffers
		allocate_info := vk.CommandBufferAllocateInfo {
			sType = .COMMAND_BUFFER_ALLOCATE_INFO,
			commandPool = state.command_pool,
			level = .PRIMARY,
			commandBufferCount = MAX_FRAMES_IN_FLIGHT,
		}

		assert_success(vk.AllocateCommandBuffers(state.device, &allocate_info, raw_data(state.command_buffers[:])))
	} log.debug("Vk: command buffers created")


	{	// Create sync objects
		semaphore_create_info := vk.SemaphoreCreateInfo {
			sType = .SEMAPHORE_CREATE_INFO
		}

		fence_info := vk.FenceCreateInfo {
			sType = .FENCE_CREATE_INFO,
			flags = {.SIGNALED},
		}

		for i in 0..<MAX_FRAMES_IN_FLIGHT {
			assert_success(vk.CreateSemaphore(state.device, &semaphore_create_info, nil, &state.image_available_semaphores[i]))
			assert_success(vk.CreateSemaphore(state.device, &semaphore_create_info, nil, &state.render_finished_semaphores[i]))
			assert_success(vk.CreateFence(state.device, &fence_info, nil, &state.in_flight_fences[i]))
		}
	} log.debug("Vk: sync objects created")


	return state
}

vk_draw :: proc() {
	assert_success(vk.WaitForFences(state.device, 1, &state.in_flight_fences[state.current_frame], true, max(u64)))
	
	image_index: u32
	result := vk.AcquireNextImageKHR(state.device, state.swapchain, max(u64), state.image_available_semaphores[state.current_frame], 0, &image_index)

	if result == .ERROR_OUT_OF_DATE_KHR {
		recreate_swapchain()
		return
	} else if result != .SUCCESS && result != .SUBOPTIMAL_KHR {
		log.panicf("Failed to acquire swapchain images: %v", result)
	}

	update_uniform_buffer(state.current_frame)

	assert_success(vk.ResetFences(state.device, 1, &state.in_flight_fences[state.current_frame]))

	assert_success(vk.ResetCommandBuffer(state.command_buffers[state.current_frame], nil))

	record_command_buffer(state.command_buffers[state.current_frame], image_index)

	submit_info := vk.SubmitInfo {
		sType = .SUBMIT_INFO,
		
		waitSemaphoreCount = 1,
		pWaitSemaphores = &state.image_available_semaphores[state.current_frame],
		pWaitDstStageMask = &vk.PipelineStageFlags{.COLOR_ATTACHMENT_OUTPUT},
		commandBufferCount = 1,
		pCommandBuffers = &state.command_buffers[state.current_frame],

		signalSemaphoreCount = 1,
		pSignalSemaphores    = &state.render_finished_semaphores[state.current_frame],
	}

	assert_success(vk.QueueSubmit(state.graphics_queue, 1, &submit_info, state.in_flight_fences[state.current_frame]))

	present_info := vk.PresentInfoKHR {
		sType = .PRESENT_INFO_KHR,
		waitSemaphoreCount = 1,
		pWaitSemaphores = &state.render_finished_semaphores[state.current_frame],
		swapchainCount = 1,
		pSwapchains = &state.swapchain,
		pImageIndices = &image_index,
		pResults = nil,
	}

	present_result := vk.QueuePresentKHR(state.present_queue, &present_info)

	if present_result == .ERROR_OUT_OF_DATE_KHR || present_result == .SUBOPTIMAL_KHR { //|| window.framebuffer_resized() {
		//window.set_framebuffer_resized(false)
		recreate_swapchain()
	} else if  present_result != .SUCCESS {
		log.panic("Failed to present swapchain image")
	}

	state.current_frame = (state.current_frame + 1) % MAX_FRAMES_IN_FLIGHT
}


record_command_buffer :: proc(command_buffer: vk.CommandBuffer, index: u32) {
	begin_info := vk.CommandBufferBeginInfo {
		sType = .COMMAND_BUFFER_BEGIN_INFO,
		flags = nil,
		pInheritanceInfo = nil,
	}

	assert_success(vk.BeginCommandBuffer(command_buffer, &begin_info))

	render_pass_info := vk.RenderPassBeginInfo {
		sType = .RENDER_PASS_BEGIN_INFO,
		renderPass = state.renderpass,
		framebuffer = state.swapchain_framebuffers[index],
	}

	render_pass_info.renderArea.offset = {0, 0}
	render_pass_info.renderArea.extent = state.swapchain_extent

	clear_values := [2]vk.ClearValue {}
	clear_values[0].color.float32 = {0, 0, 0, 0}
	clear_values[1].depthStencil = {1, 0}

	render_pass_info.clearValueCount = len(clear_values)
	render_pass_info.pClearValues = &clear_values[0]

	vk.CmdBeginRenderPass(command_buffer, &render_pass_info, .INLINE)
	vk.CmdBindPipeline(command_buffer, .GRAPHICS, state.graphics_pipeline)

	viewport := vk.Viewport {
		x = 0,
		y = 0,
		width = cast(f32)state.swapchain_extent.width,
		height = cast(f32)state.swapchain_extent.height,
		minDepth = 0,
		maxDepth = 1,
	}
	vk.CmdSetViewport(command_buffer, 0, 1, &viewport)

	scissor := vk.Rect2D {
		extent = state.swapchain_extent,
		offset = {0, 0}
	}
	vk.CmdSetScissor(command_buffer, 0, 1, &scissor)

	vk.CmdBindPipeline(command_buffer, .GRAPHICS, state.graphics_pipeline)
	vertex_buffers := []vk.Buffer { state.vertex_buffer }
	offsets := []vk.DeviceSize { 0 }

	vk.CmdBindVertexBuffers(command_buffer, 0, 1, raw_data(vertex_buffers), raw_data(offsets))
	vk.CmdBindIndexBuffer(command_buffer, state.index_buffer, 0, .UINT32)
	

	vk.CmdBindDescriptorSets(command_buffer, .GRAPHICS, state.pipeline_layout, 0, 1, &state.descriptor_sets[state.current_frame], 0, nil)

	vk.CmdDrawIndexed(command_buffer, cast(u32)len(state.model_indices), 1, 0, 0, 0)

	vk.CmdEndRenderPass(command_buffer)

	assert_success(vk.EndCommandBuffer(command_buffer))
}


update_uniform_buffer :: proc(current_image: u32) {
	dur := time.diff(state.start_time, time.now())

	ubo := UniformBufferObject {
		model = glsl.mat4Rotate({0.0, 0.0, 1.0}, f32(time.duration_seconds(dur)) * glsl.radians(f32(90.0))),
		view = glsl.mat4LookAt({2.0, 2.0, 2.0}, {0.0, 0.0, 0.0}, {0.0, 0.0, 1.0}),
		proj = glsl.mat4Perspective(glsl.radians(f32(45)), f32(state.swapchain_extent.width) / f32(state.swapchain_extent.height), 0.1, 10.0)
	}

	ubo.proj[1][1] *= -1

	mem.copy(state.uniform_buffers_mapped[current_image], &ubo, size_of(ubo))
}

recreate_swapchain :: proc() {
	
	width, height := 100, 100 //window.get_framebuffer_size()
	for width == 0 || height == 0 {
		width, height = 100, 100 //window.get_framebuffer_size()
		//window.wait_events()
		if close_requested() {
			break
		}
	}

	vk.DeviceWaitIdle(state.device)

	cleanup_swapchain()

	create_swapchain()
	create_image_views()
	create_depth_resources()
	create_frame_buffers()
}

create_frame_buffers :: proc() {
	resize(&state.swapchain_framebuffers, len(state.swapchain_views))

	for swapchain_image, i in state.swapchain_views {

		attachments := [2]vk.ImageView {
			swapchain_image,
			state.depth_image_view,
		}

		framebuffer_info := vk.FramebufferCreateInfo {
			sType = .FRAMEBUFFER_CREATE_INFO,
			renderPass = state.renderpass,
			attachmentCount = len(attachments),
			pAttachments = &attachments[0],
			width = state.swapchain_extent.width,
			height = state.swapchain_extent.height,
			layers = 1,
		}

		assert_success(vk.CreateFramebuffer(state.device, &framebuffer_info, nil, &state.swapchain_framebuffers[i]))
	}
}

create_depth_resources :: proc() {
	has_stencil_component :: proc(format: vk.Format) -> bool { return format == .D32_SFLOAT_S8_UINT || format == .D24_UNORM_S8_UINT }

	depth_format := find_depth_format()

	create_image(state.swapchain_extent.width, state.swapchain_extent.height, 1, depth_format, .OPTIMAL, {.DEPTH_STENCIL_ATTACHMENT}, {.DEVICE_LOCAL}, &state.depth_image, &state.depth_image_memory)

	state.depth_image_view = create_image_view(state.depth_image, depth_format, {.DEPTH}, 1)
}

create_image_views :: proc() {
	for image, i in state.swapchain_images {
		state.swapchain_views[i] = create_image_view(state.swapchain_images[i], state.swapchain_format.format, {.COLOR}, 1)
	}
}

create_swapchain :: proc() {
	choose_swap_surface_format :: proc(surface_formats: []vk.SurfaceFormatKHR) -> vk.SurfaceFormatKHR { 
		for format in surface_formats {
			if format.format == .B8G8R8A8_SRGB && format.colorSpace == .SRGB_NONLINEAR {
				return format
			}
		}
		return surface_formats[0]
	}

	choose_swapchain_present_mode :: proc(present_modes: []vk.PresentModeKHR) -> vk.PresentModeKHR {
		for mode in present_modes {
			if mode == .MAILBOX {
				return .MAILBOX
			}
		}
		return .FIFO
	}

	choose_swapchain_extent :: proc(capabilities: vk.SurfaceCapabilitiesKHR) -> vk.Extent2D {
		if capabilities.currentExtent.width != max(u32) {
			return capabilities.currentExtent
		} 
		
		width, height := 100, 100 //window.get_framebuffer_size()
		actual_extend := vk.Extent2D {
			width = cast(u32)width,
			height = cast(u32)height
		}

		actual_extend.width = clamp(actual_extend.width, capabilities.minImageExtent.width, capabilities.maxImageExtent.width)
		actual_extend.height = clamp(actual_extend.height, capabilities.minImageExtent.height, capabilities.maxImageExtent.height)

		return actual_extend
	}

	indices := find_queue_families(state.physical_device)
	details, result := query_swapchain_support(state.physical_device)
	if result != .SUCCESS {
		log.panicf("vulkan: query swapchain failed: %v", result)
	}

	surface_format := choose_swap_surface_format(details.surface_formats[:])
	present_mode := choose_swapchain_present_mode(details.present_modes[:])
	extent := choose_swapchain_extent(details.surface_capabilities)

	state.swapchain_format = surface_format
	state.swapchain_extent = extent

	image_count := details.surface_capabilities.minImageCount + 1
	if details.surface_capabilities.maxImageCount > 0 && image_count > details.surface_capabilities.maxImageCount {
		image_count = details.surface_capabilities.maxImageCount
	}

	swap_create_info := vk.SwapchainCreateInfoKHR {
		sType = .SWAPCHAIN_CREATE_INFO_KHR,
		surface = state.surface,
		minImageCount = image_count,
		imageFormat = surface_format.format,
		imageColorSpace = surface_format.colorSpace,
		imageExtent = extent,
		imageArrayLayers = 1,
		imageUsage = {.COLOR_ATTACHMENT},
		preTransform = details.surface_capabilities.currentTransform,
		compositeAlpha = {.OPAQUE},
		presentMode = present_mode,
		clipped = true,
		
		oldSwapchain = 0,
	}

	if indices.graphics_family.? != indices.present_family.? {
		swap_create_info.imageSharingMode = .CONCURRENT
		swap_create_info.queueFamilyIndexCount = 2
		swap_create_info.pQueueFamilyIndices = raw_data([]u32 { indices.graphics_family.?, indices.present_family.?})
	} else {
		swap_create_info.imageSharingMode = .EXCLUSIVE
		swap_create_info.queueFamilyIndexCount = 0
		swap_create_info.pQueueFamilyIndices = nil
	}

	assert_success(vk.CreateSwapchainKHR(state.device, &swap_create_info, nil, &state.swapchain))

	{
		count: u32
		assert_success(vk.GetSwapchainImagesKHR(state.device, state.swapchain, &count, nil))

		state.swapchain_images = make([]vk.Image, count)
		state.swapchain_views = make([]vk.ImageView, count)

		assert_success(vk.GetSwapchainImagesKHR(state.device, state.swapchain, &count, raw_data(state.swapchain_images)))
	}
}

cleanup_swapchain :: proc() {
	vk.DestroyImageView(state.device, state.depth_image_view, nil)
	vk.DestroyImage(state.device, state.depth_image, nil)
	vk.FreeMemory(state.device, state.depth_image_memory, nil)

	for frame_buffer in state.swapchain_framebuffers {
		vk.DestroyFramebuffer(state.device, frame_buffer, nil)
	}

	for image_view in state.swapchain_views {
		vk.DestroyImageView(state.device, image_view, nil)
	}

	vk.DestroySwapchainKHR(state.device, state.swapchain, nil)
}


create_buffer :: proc(size: vk.DeviceSize, usage: vk.BufferUsageFlags, properties: vk.MemoryPropertyFlags, buffer: ^vk.Buffer, buffer_memory: ^vk.DeviceMemory) {
	buffer_info := vk.BufferCreateInfo {
		sType = .BUFFER_CREATE_INFO,
		size = size,
		usage = usage,
		sharingMode = .EXCLUSIVE
	}

	assert_success(vk.CreateBuffer(state.device, &buffer_info, nil, buffer))

	mem_requirements: vk.MemoryRequirements
	vk.GetBufferMemoryRequirements(state.device, buffer^, &mem_requirements)

	alloc_info := vk.MemoryAllocateInfo {
		sType = .MEMORY_ALLOCATE_INFO,
		allocationSize = mem_requirements.size,
		memoryTypeIndex = find_memory_type(mem_requirements.memoryTypeBits, properties)
	}

	assert_success(vk.AllocateMemory(state.device, &alloc_info, nil, buffer_memory))

	vk.BindBufferMemory(state.device, buffer^, buffer_memory^, 0)
}

find_memory_type :: proc(filter: u32, properties: vk.MemoryPropertyFlags) -> u32 {
	mem_properties: vk.PhysicalDeviceMemoryProperties
	vk.GetPhysicalDeviceMemoryProperties(state.physical_device, &mem_properties)

	for i in 0..<mem_properties.memoryTypeCount {
		if (filter & i) == i && (properties & mem_properties.memoryTypes[i].propertyFlags) == properties {
			return i
		}
	}

	log.panicf("Failed to find suitable memory types")
}

create_image :: proc(width, height, mip_levels: u32, format: vk.Format, tiling: vk.ImageTiling, usage: vk.ImageUsageFlags, properties: vk.MemoryPropertyFlags, image: ^vk.Image, image_memory: ^vk.DeviceMemory) {
		
	image_info := vk.ImageCreateInfo {
		sType = .IMAGE_CREATE_INFO,
		imageType = .D2,
		extent = vk.Extent3D {
			width = width,
			height = height,
			depth = 1,
		},
		mipLevels = mip_levels,
		arrayLayers = 1,
		format = format,
		tiling = tiling,
		initialLayout = .UNDEFINED,
		usage = usage,
		sharingMode = .EXCLUSIVE,
		samples = {._1},
		flags = nil,
	}

	assert_success(vk.CreateImage(state.device, &image_info, nil, image))

	mem_reqs: vk.MemoryRequirements
	vk.GetImageMemoryRequirements(state.device, image^, &mem_reqs)

	alloc_info := vk.MemoryAllocateInfo {
		sType = .MEMORY_ALLOCATE_INFO,
		allocationSize = mem_reqs.size,
		memoryTypeIndex = find_memory_type(mem_reqs.memoryTypeBits, properties)
	}

	assert_success(vk.AllocateMemory(state.device, &alloc_info, nil, image_memory))

	assert_success(vk.BindImageMemory(state.device, image^, image_memory^, 0))
}


get_vertex_binding_description :: proc() -> vk.VertexInputBindingDescription {
	binding_description := vk.VertexInputBindingDescription {
		binding = 0,
		stride = cast(u32)size_of(Vertex),
		inputRate = .VERTEX,
	}

	return binding_description
}


get_vertex_attribute_description :: proc() -> [3]vk.VertexInputAttributeDescription {
	attribute_descriptions := [3]vk.VertexInputAttributeDescription {}

	attribute_descriptions[0].binding = 0
	attribute_descriptions[0].location = 0
	attribute_descriptions[0].format = .R32G32B32_SFLOAT
	attribute_descriptions[0].offset = cast(u32)offset_of(Vertex, position)

	attribute_descriptions[1].binding = 0;
	attribute_descriptions[1].location = 1;
	attribute_descriptions[1].format = .R32G32B32_SFLOAT
	attribute_descriptions[1].offset = cast(u32)offset_of(Vertex, color);

	attribute_descriptions[2].binding = 0;
	attribute_descriptions[2].location = 2;
	attribute_descriptions[2].format = .R32G32_SFLOAT
	attribute_descriptions[2].offset = cast(u32)offset_of(Vertex, tex_coord);

	return attribute_descriptions
}


find_depth_format :: proc() -> vk.Format {
	return find_supported_format({ .D32_SFLOAT, .D32_SFLOAT_S8_UINT, .D24_UNORM_S8_UINT}, .OPTIMAL, {.DEPTH_STENCIL_ATTACHMENT})
}

find_supported_format :: proc(candidates: []vk.Format, tiling: vk.ImageTiling, features: vk.FormatFeatureFlags) -> vk.Format {

	for format in candidates {

		props: vk.FormatProperties
		vk.GetPhysicalDeviceFormatProperties(state.physical_device, format, &props)

		if tiling == .LINEAR && (props.linearTilingFeatures & features) == features {
			return format
		} else if tiling == .OPTIMAL && (props.optimalTilingFeatures & features) == features {
			return format
		}
	}

	log.panic("Failed to find supported format")
}

create_image_view :: proc(image: vk.Image, format: vk.Format, aspect_mask: vk.ImageAspectFlags, mip_levels: u32) -> (view: vk.ImageView) {

	create_info := vk.ImageViewCreateInfo {
		sType = .IMAGE_VIEW_CREATE_INFO,
		image = image,
		viewType = .D2,
		format = format,
		subresourceRange = vk.ImageSubresourceRange {
			aspectMask = aspect_mask,
			baseMipLevel = 0,
			levelCount = mip_levels,
			baseArrayLayer = 0,
			layerCount = 1,
		}
	}

	assert_success(vk.CreateImageView(state.device, &create_info, nil, &view))

	return view
}

physical_device_extensions :: proc(device: vk.PhysicalDevice, allocator := context.temp_allocator,
) -> (
	exts: []vk.ExtensionProperties,
	res: vk.Result,
) {
	count: u32
	vk.EnumerateDeviceExtensionProperties(device, nil, &count, nil) or_return

	exts = make([]vk.ExtensionProperties, count, allocator)
	vk.EnumerateDeviceExtensionProperties(device, nil, &count, raw_data(exts)) or_return

	return
}

SwapchainDetails :: struct {
	surface_capabilities: vk.SurfaceCapabilitiesKHR,
	surface_formats: []vk.SurfaceFormatKHR,
	present_modes:[]vk.PresentModeKHR,
}

query_swapchain_support :: proc(device: vk.PhysicalDevice, allocator := context.temp_allocator) -> (details: SwapchainDetails, result: vk.Result) {

	vk.GetPhysicalDeviceSurfaceCapabilitiesKHR(device, state.surface, &details.surface_capabilities) or_return
	
	{
		count: u32
		vk.GetPhysicalDeviceSurfaceFormatsKHR(device, state.surface, &count, nil) or_return

		details.surface_formats = make([]vk.SurfaceFormatKHR, count)
		vk.GetPhysicalDeviceSurfaceFormatsKHR(device, state.surface, &count, raw_data(details.surface_formats)) or_return
	}
	
	{
		count: u32
		vk.GetPhysicalDeviceSurfacePresentModesKHR(device, state.surface, &count, nil) or_return

		details.present_modes = make([]vk.PresentModeKHR, count)
		vk.GetPhysicalDeviceSurfacePresentModesKHR(device, state.surface, &count, raw_data(details.present_modes)) or_return

	}

	return
}

QueueFamilyIndices :: struct {
	graphics_family: Maybe(u32),
	present_family: Maybe(u32),
}

find_queue_families :: proc(device: vk.PhysicalDevice) -> (indices: QueueFamilyIndices) {

	queue_family_count: u32
	vk.GetPhysicalDeviceQueueFamilyProperties(device, &queue_family_count, nil)
	queue_families := make([]vk.QueueFamilyProperties, queue_family_count, context.temp_allocator)
	vk.GetPhysicalDeviceQueueFamilyProperties(device, &queue_family_count, raw_data(queue_families))

	for queue_family, i in queue_families {

		if .GRAPHICS in queue_family.queueFlags {
			indices.graphics_family = cast(u32)i
		}

		present_support:b32
		vk.GetPhysicalDeviceSurfaceSupportKHR(device, cast(u32)i, state.surface, &present_support)

		if present_support {
			indices.present_family = cast(u32)i
		}

		_, has_graphics := indices.graphics_family.?

		if has_graphics && present_support {
			break
		}
	}

	return
}

assert_success :: proc(result: vk.Result, loc := #caller_location) {
	if result != .SUCCESS {
		log.panicf("vulkan failure: %v", result, location = loc)
	}
}

create_debug_messenger :: proc() {
	create_info: vk.DebugUtilsMessengerCreateInfoEXT = {
		sType = .DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT,
		messageSeverity = {vk.DebugUtilsMessageSeverityFlagEXT.VERBOSE, vk.DebugUtilsMessageSeverityFlagEXT.WARNING, vk.DebugUtilsMessageSeverityFlagEXT.ERROR },
		messageType = {vk.DebugUtilsMessageTypeFlagEXT.GENERAL, vk.DebugUtilsMessageTypeFlagEXT.VALIDATION, vk.DebugUtilsMessageTypeFlagEXT.PERFORMANCE},
	}

	create_info.pfnUserCallback = debug_message_callback

	debug_messenger: vk.DebugUtilsMessengerEXT
	assert_success(create_vk_debug_messenger(&create_info, nil, &debug_messenger))
	
	state.debug_messenger = debug_messenger
}

import "base:runtime"
// TODO swap context to the correct one
debug_message_callback :: proc "c" (severity: vk.DebugUtilsMessageSeverityFlagsEXT, type: vk.DebugUtilsMessageTypeFlagsEXT, callback_data: ^vk.DebugUtilsMessengerCallbackDataEXT, user_data: rawptr) -> b32 {
	
	if transmute(u32)severity >= cast(u32)vk.DebugUtilsMessageSeverityFlagEXT.WARNING {
		context = runtime.default_context()
		log.errorf("Validation layer: %v", callback_data.pMessage)

		if transmute(u32)severity == cast(u32)vk.DebugUtilsMessageSeverityFlagEXT.ERROR {
			log.panic()
		}
	}

	return false
}

create_vk_debug_messenger :: proc(create_info: ^vk.DebugUtilsMessengerCreateInfoEXT, alloc: ^vk.AllocationCallbacks, debug_messenger: ^vk.DebugUtilsMessengerEXT) -> vk.Result {

	generic := vk.GetInstanceProcAddr(state.instance, "vkCreateDebugUtilsMessengerEXT")
	func := cast(vk.ProcCreateDebugUtilsMessengerEXT)generic
	if func == nil {
		return vk.Result.ERROR_EXTENSION_NOT_PRESENT
	}
	return func(state.instance, create_info, alloc, debug_messenger)
}

generate_mipmaps :: proc(image: vk.Image, format: vk.Format, width, height, mip_levels: u32) {

	{
		props: vk.FormatProperties
		vk.GetPhysicalDeviceFormatProperties(state.physical_device, format, &props)

		if .SAMPLED_IMAGE_FILTER_LINEAR not_in props.optimalTilingFeatures {
			log.panic("Texture image format does not support linear blitting")
		}

		/* 

		There are two alternatives in this case. 
		You could implement a function that searches common texture image formats for one that does support linear blitting,
		or you could implement the mipmap generation in software with a library like stb_image_resize. Each mip 
		level can then be loaded into the image in the same way that you loaded the original image.

		It should be noted that it is uncommon in practice to generate the mipmap levels at runtime anyway.
		Usually they are pregenerated and stored in the texture file alongside the base level to improve loading speed.
		Implementing resizing in software and loading multiple levels from a file is left as an exercise to the reader.
		
		*/
	}

    command_buffer := begin_single_time_commands()

	barrier := vk.ImageMemoryBarrier {
		sType = .IMAGE_MEMORY_BARRIER,
		image = image,
		srcQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
		dstQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
		subresourceRange = {
			aspectMask = {.COLOR},
			baseArrayLayer = 0,
			layerCount = 1,
			levelCount = 1
		}
	}

	mip_width := i32(width)
	mip_height := i32(height)

	for i in 1..<mip_levels {
		barrier.subresourceRange.baseMipLevel = i - 1
		barrier.oldLayout = .TRANSFER_DST_OPTIMAL
		barrier.newLayout = .TRANSFER_SRC_OPTIMAL
		barrier.srcAccessMask = {.TRANSFER_WRITE}
		barrier.dstAccessMask = {.TRANSFER_READ}

		vk.CmdPipelineBarrier(command_buffer, {.TRANSFER}, {.TRANSFER}, {}, 0, nil, 0, nil, 1, &barrier)

		blit := vk.ImageBlit {
			srcOffsets = {{0, 0, 0}, {mip_width, mip_height, 1}},
			srcSubresource = {
				aspectMask = {.COLOR},
				mipLevel = i - 1,
				baseArrayLayer = 0,
				layerCount = 1
			},

			dstOffsets = {{0, 0, 0}, {mip_width > 1 ? mip_width / 2 : 1, mip_height > 1 ? mip_height / 2 : 1, 1}},
			dstSubresource = {
				aspectMask = {.COLOR},
				mipLevel = i,
				baseArrayLayer = 0,
				layerCount = 1
			},
		}

		vk.CmdBlitImage(command_buffer, image, .TRANSFER_SRC_OPTIMAL, image, .TRANSFER_DST_OPTIMAL, 1, &blit, .LINEAR)

		barrier.oldLayout = .TRANSFER_SRC_OPTIMAL
		barrier.newLayout = .SHADER_READ_ONLY_OPTIMAL
		barrier.srcAccessMask = {.TRANSFER_READ}
		barrier.dstAccessMask = {.SHADER_READ}

		vk.CmdPipelineBarrier(command_buffer, {.TRANSFER}, {.FRAGMENT_SHADER}, {}, 0, nil, 0, nil, 1, &barrier)

		if mip_width > 1 do mip_width /= 2
		if mip_height > 1 do mip_height /= 2
	}

	barrier.subresourceRange.baseMipLevel = mip_levels - 1
	barrier.oldLayout = .TRANSFER_DST_OPTIMAL
	barrier.newLayout = .SHADER_READ_ONLY_OPTIMAL
	barrier.srcAccessMask = {.TRANSFER_WRITE}
	barrier.dstAccessMask = {.SHADER_READ}

	vk.CmdPipelineBarrier(command_buffer, {.TRANSFER}, {.FRAGMENT_SHADER}, {}, 0, nil, 0, nil, 1, &barrier)

    end_single_time_commands(command_buffer)
}

begin_single_time_commands :: proc() -> vk.CommandBuffer {
	
	alloc_info := vk.CommandBufferAllocateInfo {
		sType = .COMMAND_BUFFER_ALLOCATE_INFO,
		level = .PRIMARY,
		commandPool = state.command_pool,
		commandBufferCount = 1,
	}

	command_buffer: vk.CommandBuffer
	assert_success(vk.AllocateCommandBuffers(state.device, &alloc_info, &command_buffer))

	begin_info := vk.CommandBufferBeginInfo {
		sType = .COMMAND_BUFFER_BEGIN_INFO,
		flags = {.ONE_TIME_SUBMIT},
	}

	assert_success(vk.BeginCommandBuffer(command_buffer, &begin_info))

	return command_buffer
}

end_single_time_commands ::proc(command_buffer: vk.CommandBuffer) {

	assert_success(vk.EndCommandBuffer(command_buffer))

	cmds := [1]vk.CommandBuffer{command_buffer}
	submit_info := vk.SubmitInfo {
		sType = .SUBMIT_INFO,
		pNext = nil,
		commandBufferCount = 1,
		pCommandBuffers = &cmds[0],
	}
	
	assert_success(vk.QueueSubmit(state.graphics_queue, 1, &submit_info, 0))

	assert_success(vk.QueueWaitIdle(state.graphics_queue))

	vk.FreeCommandBuffers(state.device, state.command_pool, 1, &cmds[0])
}

transition_image_layout :: proc(image: vk.Image, format: vk.Format, layout_old: vk.ImageLayout, layout_new: vk.ImageLayout, mip_levels: u32) {
	command_buffer := begin_single_time_commands()

	barrier := vk.ImageMemoryBarrier {
		sType = .IMAGE_MEMORY_BARRIER,
		oldLayout = layout_old,
		newLayout = layout_new,
		srcQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
		dstQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
		image = image,
		subresourceRange = vk.ImageSubresourceRange {
			aspectMask = {.COLOR},
			baseMipLevel = 0,
			levelCount = mip_levels,
			baseArrayLayer = 0,
			layerCount = 1,
		},
		srcAccessMask = {},
		dstAccessMask = {},
	}

	source_stage: vk.PipelineStageFlags
	destination_stage: vk.PipelineStageFlags

	if layout_old == .UNDEFINED && layout_new == .TRANSFER_DST_OPTIMAL {
		barrier.srcAccessMask = {}
		barrier.dstAccessMask = {.TRANSFER_WRITE}
		
		source_stage = {.TOP_OF_PIPE}
		destination_stage = {.TRANSFER}
	} else if layout_old == .TRANSFER_DST_OPTIMAL && layout_new == .SHADER_READ_ONLY_OPTIMAL {
		barrier.srcAccessMask = {.TRANSFER_WRITE}
		barrier.dstAccessMask = {.SHADER_READ}

		source_stage = {.TRANSFER}
		destination_stage = {.FRAGMENT_SHADER}
	} else {
		log.panic("Unsupported layout transition")
	}

	vk.CmdPipelineBarrier(command_buffer, source_stage, destination_stage, {}, 0, nil, 0, nil, 1, &barrier)

	end_single_time_commands(command_buffer)
}

copy_buffer_to_image :: proc(buffer: vk.Buffer, image: vk.Image, width, height: u32) {
	command_buffer := begin_single_time_commands()

	region := vk.BufferImageCopy {
		bufferOffset = 0,
		bufferRowLength = 0,
		bufferImageHeight = 0,

		imageSubresource = vk.ImageSubresourceLayers {
			aspectMask = {.COLOR},
			mipLevel = 0,
			baseArrayLayer = 0,
			layerCount = 1,
		},

		imageOffset = vk.Offset3D {0, 0, 0},
		imageExtent = vk.Extent3D {
			width = width,
			height = height,
			depth = 1
		}
	}

	vk.CmdCopyBufferToImage(command_buffer, buffer, image, .TRANSFER_DST_OPTIMAL, 1, &region)

	end_single_time_commands(command_buffer)
}

copy_buffer :: proc(src, dst: vk.Buffer, size: vk.DeviceSize) {
	command_buffer := begin_single_time_commands()

	copy_region := vk.BufferCopy {
		size = size,
	}
	
	vk.CmdCopyBuffer(command_buffer, src, dst, 1, &copy_region)

	end_single_time_commands(command_buffer)
}

