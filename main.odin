package main

import "core:mem"
import "base:runtime"
import "core:strings"
import "core:fmt"
import vk "vendor:vulkan"
import "vendor:glfw"
import "core:slice"
import "core:os"
import "core:c"
import "core:log"
import "core:math/linalg"
import "core:math/linalg/glsl"

vert_shader_code :: #load("shaders/vert.spv")
frag_shader_code :: #load("shaders/frag.spv")

model :: "viking_room.obj"
model_tex :: "viking_room.png"

app: ^App
MAX_FRAMES_IN_FLIGHT :: 2

App :: struct {
    title: string,
    width: i32,
    height: i32,
    window: glfw.WindowHandle,
	start_time: time.Time,


	instance: vk.Instance,
	debug_messenger: vk.DebugUtilsMessengerEXT,

	surface: vk.SurfaceKHR,
	physical_device: vk.PhysicalDevice,
	device: vk.Device,
	
	graphics_queue: vk.Queue,
	present_queue: vk.Queue,
	transfer_queue: vk.Queue,
	graphics_family_index : u32,
	present_family_index : u32,
	
	swapchain: vk.SwapchainKHR,
	swapchain_images: []vk.Image,
	swapchain_format: vk.SurfaceFormatKHR,
	swapchain_extent: vk.Extent2D,
	swapchain_views: []vk.ImageView,
	
	render_pass: vk.RenderPass,
	
	descriptor_set_layout: vk.DescriptorSetLayout,
	pipeline_layout: vk.PipelineLayout,

	graphics_pipeline: vk.Pipeline,
	swapchain_framebuffers: [dynamic]vk.Framebuffer,
	command_pool: vk.CommandPool,

	command_buffers: [MAX_FRAMES_IN_FLIGHT]vk.CommandBuffer,
	image_available_semaphores: [MAX_FRAMES_IN_FLIGHT]vk.Semaphore,
	render_finished_semaphores: [MAX_FRAMES_IN_FLIGHT]vk.Semaphore,
	in_flight_fences: [MAX_FRAMES_IN_FLIGHT]vk.Fence,

	current_frame: u32,
	frame_buffer_resized: b32,

	vertex_buffer: vk.Buffer,
	vertex_buffer_memory: vk.DeviceMemory,

	index_buffer: vk.Buffer,
	index_buffer_memory: vk.DeviceMemory,

	uniform_buffers: [MAX_FRAMES_IN_FLIGHT]vk.Buffer,
	uniform_buffers_memory: [MAX_FRAMES_IN_FLIGHT]vk.DeviceMemory,
	uniform_buffers_mapped: [MAX_FRAMES_IN_FLIGHT]rawptr,

	descriptor_pool: vk.DescriptorPool,
	descriptor_sets: [MAX_FRAMES_IN_FLIGHT]vk.DescriptorSet,

	texture_image: vk.Image,
	texture_image_memory: vk.DeviceMemory,
	texture_image_view: vk.ImageView,
	texture_sampler: vk.Sampler,


	depth_image: vk.Image,
	depth_image_view: vk.ImageView,
	depth_image_memory: vk.DeviceMemory,
}

Vertex :: struct {
	position: glsl.vec3,
	color: glsl.vec3,
	tex_coord: glsl.vec2
}

VERTICES := []Vertex {
	{{-0.5, -0.5, 0.0}, {1.0, 0.0, 0.0}, {0.0, 0.0}},
    {{0.5, -0.5, 0.0}, {0.0, 1.0, 0.0}, {1.0, 0.0}},
    {{0.5, 0.5, 0.0}, {0.0, 0.0, 1.0}, {1.0, 1.0}},
    {{-0.5, 0.5, 0.0}, {1.0, 1.0, 1.0}, {0.0, 1.0}},

	{{-0.5, -0.5, -0.5}, {1.0, 0.0, 0.0}, {0.0, 0.0}},
    {{0.5, -0.5, -0.5}, {0.0, 1.0, 0.0}, {1.0, 0.0}},
    {{0.5, 0.5, -0.5}, {0.0, 0.0, 1.0}, {1.0, 1.0}},
    {{-0.5, 0.5, -0.5}, {1.0, 1.0, 1.0}, {0.0, 1.0}}
}

INDICES := []u32 {
	0, 1, 2, 2, 3, 0,

	4, 5, 6, 6, 7, 4
}

UniformBufferObject :: struct #align(16) {
	model: glsl.mat4,
	view: glsl.mat4,
	proj: glsl.mat4,
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

app_init :: proc(title: string, width, height: i32) {
	app = new(App)
    app^ = {
        title = title,
        width = width,
        height = height,
		start_time = time.now()
    }
}

glfw_error_callback :: proc "c" (code: i32, description: cstring) {
	context = runtime.default_context()
	log.errorf("glfw: %i: %s", code, description)
}

glfw_init :: proc() {
	
	glfw.SetErrorCallback(glfw_error_callback)

	if !glfw.Init() { 
		log.panic("GLFW: Failed to initialize")
	}

	glfw.WindowHint(glfw.CLIENT_API, glfw.NO_API)
	glfw.WindowHint(glfw.VISIBLE, glfw.TRUE)
	glfw.WindowHint(glfw.RESIZABLE, glfw.TRUE) //glfw.WindowHint(glfw.RESIZABLE, glfw.FALSE)

	window := glfw.CreateWindow(app.width, app.height, strings.clone_to_cstring(app.title, context.temp_allocator), nil, nil);

	if window == nil {
		log.panic("GLFW: Failed to create GLFW window")
	}

	glfw.SetWindowUserPointer(window, app)
	glfw.SetFramebufferSizeCallback(window, glfw_frame_buffer_resize_callback)

	app.window = window

	vk.load_proc_addresses_global(cast(rawptr)glfw.GetInstanceProcAddress)
	if vk.CreateInstance == nil {
		log.panic("Vulkan function pointers not loaded")
	}
}

glfw_frame_buffer_resize_callback :: proc "c" (window: glfw.WindowHandle, width, height: c.int) {
	app = cast(^App)glfw.GetWindowUserPointer(window);
    app.frame_buffer_resized = true;
}

create_surface :: proc() {
	assert_success(glfw.CreateWindowSurface(app.instance, app.window, nil, &app.surface))
}

pick_physical_device :: proc() {
	count: u32

	assert_success(vk.EnumeratePhysicalDevices(app.instance, &count, nil))

	if count == 0 {
		log.panic("vulkan: No GPUs found")
	}

	devices := make([]vk.PhysicalDevice, count, context.temp_allocator)
	assert_success(vk.EnumeratePhysicalDevices(app.instance, &count, raw_data(devices)))

	best_device_score := -1
	for device in devices {
		if score := score_physical_device(device); score > best_device_score {
			app.physical_device = device
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

	check_device_extention_support :: proc(device: vk.PhysicalDevice) -> b32 {

		count: u32
		vk.EnumerateDeviceExtensionProperties(device, nil, &count, nil)
		available_device_extensions := make([]vk.ExtensionProperties, count)
		vk.EnumerateDeviceExtensionProperties(device, nil, &count, raw_data(available_device_extensions))

		required_extensions_set: map[cstring] struct {}
		for e in REQUIRED_EXTENSIONS {
			required_extensions_set[e] = {}
		}

		for &available in available_device_extensions {
			delete_key(&required_extensions_set, cstring(&available.extensionName[0]))
		}

		return len(required_extensions_set) == 0
	}
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

		vk.GetPhysicalDeviceSurfaceCapabilitiesKHR(device, app.surface, &details.surface_capabilities) or_return
		
		{
			count: u32
			vk.GetPhysicalDeviceSurfaceFormatsKHR(device, app.surface, &count, nil) or_return

			details.surface_formats = make([]vk.SurfaceFormatKHR, count)
			vk.GetPhysicalDeviceSurfaceFormatsKHR(device, app.surface, &count, raw_data(details.surface_formats)) or_return
		}
		
		{
			count: u32
			vk.GetPhysicalDeviceSurfacePresentModesKHR(device, app.surface, &count, nil) or_return

			details.present_modes = make([]vk.PresentModeKHR, count)
			vk.GetPhysicalDeviceSurfacePresentModesKHR(device, app.surface, &count, raw_data(details.present_modes)) or_return

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
		vk.GetPhysicalDeviceSurfaceSupportKHR(device, cast(u32)i, app.surface, &present_support)

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

create_logical_device :: proc() {

	indices := find_queue_families(app.physical_device)

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
		
	assert_success(vk.CreateDevice(app.physical_device, &create_info, nil, &app.device))
	
	vk.GetDeviceQueue(app.device, indices.graphics_family.?, 0, &app.graphics_queue)
	vk.GetDeviceQueue(app.device, indices.present_family.?, 0, &app.present_queue)

	app.graphics_family_index = indices.graphics_family.?
	app.present_family_index = indices.present_family.?
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
		
		width, height := glfw.GetFramebufferSize(app.window)
		actual_extend := vk.Extent2D {
			width = cast(u32)width,
			height = cast(u32)height
		}

		actual_extend.width = clamp(actual_extend.width, capabilities.minImageExtent.width, capabilities.maxImageExtent.width)
		actual_extend.height = clamp(actual_extend.height, capabilities.minImageExtent.height, capabilities.maxImageExtent.height)

		return actual_extend
	
	}
 	
	indices := find_queue_families(app.physical_device)

	details, result := query_swapchain_support(app.physical_device)
	if result != .SUCCESS {
		log.panicf("vulkan: query swapchain failed: %v", result)
	}
	
	surface_format := choose_swap_surface_format(details.surface_formats[:])
	present_mode := choose_swapchain_present_mode(details.present_modes[:])
	extent := choose_swapchain_extent(details.surface_capabilities)

	app.swapchain_format = surface_format
	app.swapchain_extent = extent

	image_count := details.surface_capabilities.minImageCount + 1
	if details.surface_capabilities.maxImageCount > 0 && image_count > details.surface_capabilities.maxImageCount {
		image_count = details.surface_capabilities.maxImageCount
	}

	swap_create_info := vk.SwapchainCreateInfoKHR {
		sType = .SWAPCHAIN_CREATE_INFO_KHR,
		surface = app.surface,
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

	assert_success(vk.CreateSwapchainKHR(app.device, &swap_create_info, nil, &app.swapchain))
	
	{
		count: u32
		assert_success(vk.GetSwapchainImagesKHR(app.device, app.swapchain, &count, nil))

		app.swapchain_images = make([]vk.Image, count)
		app.swapchain_views = make([]vk.ImageView, count)

		assert_success(vk.GetSwapchainImagesKHR(app.device, app.swapchain, &count, raw_data(app.swapchain_images)))
	}
}

create_image_views :: proc() {

	for image, i in app.swapchain_images {

		app.swapchain_views[i] = create_image_view(app.swapchain_images[i], app.swapchain_format.format, {.COLOR})
	}
}

when ODIN_DEBUG {
create_vk_debug_messenger :: proc(create_info: ^vk.DebugUtilsMessengerCreateInfoEXT, alloc: ^vk.AllocationCallbacks, debug_messenger: ^vk.DebugUtilsMessengerEXT) -> vk.Result {

	generic := vk.GetInstanceProcAddr(app.instance, "vkCreateDebugUtilsMessengerEXT")
	func := cast(vk.ProcCreateDebugUtilsMessengerEXT)generic
	if func == nil {
		return vk.Result.ERROR_EXTENSION_NOT_PRESENT
	}
	return func(app.instance, create_info, alloc, debug_messenger)
}

debug_message_callback :: proc "c" (severity: vk.DebugUtilsMessageSeverityFlagsEXT, type: vk.DebugUtilsMessageTypeFlagsEXT, callback_data: ^vk.DebugUtilsMessengerCallbackDataEXT, user_data: rawptr) -> b32 {
	
	if transmute(u32)severity >= cast(u32)vk.DebugUtilsMessageSeverityFlagEXT.WARNING {
		context = runtime.default_context()
		log.errorf("Validation layer: %v", callback_data.pMessage)

		if transmute(u32)severity == cast(u32)vk.DebugUtilsMessageSeverityFlagEXT.ERROR {
			os.exit(1)
		}
	}

	return false
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
	
	app.debug_messenger = debug_messenger
}

} // ODIN_DEBUG


create_frame_buffers ::proc() {
	resize(&app.swapchain_framebuffers, len(app.swapchain_views))

	for swapchain_image, i in app.swapchain_views {

		attachments := [2]vk.ImageView {
			swapchain_image,
			app.depth_image_view,
		}

		framebuffer_info := vk.FramebufferCreateInfo {
			sType = .FRAMEBUFFER_CREATE_INFO,
			renderPass = app.render_pass,
			attachmentCount = len(attachments),
			pAttachments = &attachments[0],
			width = app.swapchain_extent.width,
			height = app.swapchain_extent.height,
			layers = 1,
		}

		assert_success(vk.CreateFramebuffer(app.device, &framebuffer_info, nil, &app.swapchain_framebuffers[i]))
	}
}

create_sync_objects :: proc() {
	semaphore_create_info := vk.SemaphoreCreateInfo {
		sType = .SEMAPHORE_CREATE_INFO
	}

	fence_info := vk.FenceCreateInfo {
		sType = .FENCE_CREATE_INFO,
		flags = {.SIGNALED},
	}

	for i in 0..<MAX_FRAMES_IN_FLIGHT {
		assert_success(vk.CreateSemaphore(app.device, &semaphore_create_info, nil, &app.image_available_semaphores[i]))
		assert_success(vk.CreateSemaphore(app.device, &semaphore_create_info, nil, &app.render_finished_semaphores[i]))
		assert_success(vk.CreateFence(app.device, &fence_info, nil, &app.in_flight_fences[i]))
	}
	
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
		renderPass = app.render_pass,
		framebuffer = app.swapchain_framebuffers[index],
	}

	render_pass_info.renderArea.offset = {0, 0}
	render_pass_info.renderArea.extent = app.swapchain_extent

	clear_values := [2]vk.ClearValue {}
	clear_values[0].color.float32 = {0, 0, 0, 0}
	clear_values[1].depthStencil = {1, 0}

	render_pass_info.clearValueCount = len(clear_values)
	render_pass_info.pClearValues = &clear_values[0]

	vk.CmdBeginRenderPass(command_buffer, &render_pass_info, .INLINE)
	vk.CmdBindPipeline(command_buffer, .GRAPHICS, app.graphics_pipeline)

	viewport := vk.Viewport {
		x = 0,
		y = 0,
		width = cast(f32)app.swapchain_extent.width,
		height = cast(f32)app.swapchain_extent.height,
		minDepth = 0,
		maxDepth = 1,
	}
	vk.CmdSetViewport(command_buffer, 0, 1, &viewport)

	scissor := vk.Rect2D {
		extent = app.swapchain_extent,
		offset = {0, 0}
	}
	vk.CmdSetScissor(command_buffer, 0, 1, &scissor)

	vk.CmdBindPipeline(command_buffer, .GRAPHICS, app.graphics_pipeline)
	vertex_buffers := []vk.Buffer { app.vertex_buffer }
	offsets := []vk.DeviceSize { 0 }

	vk.CmdBindVertexBuffers(command_buffer, 0, 1, raw_data(vertex_buffers), raw_data(offsets))
	vk.CmdBindIndexBuffer(command_buffer, app.index_buffer, 0, .UINT32)
	

	vk.CmdBindDescriptorSets(command_buffer, .GRAPHICS, app.pipeline_layout, 0, 1, &app.descriptor_sets[app.current_frame], 0, nil)

	vk.CmdDrawIndexed(command_buffer, cast(u32)len(INDICES), 1, 0, 0, 0)

	vk.CmdEndRenderPass(command_buffer)

	assert_success(vk.EndCommandBuffer(command_buffer))
}

create_command_buffers :: proc() {
	allocate_info := vk.CommandBufferAllocateInfo {
		sType = .COMMAND_BUFFER_ALLOCATE_INFO,
		commandPool = app.command_pool,
		level = .PRIMARY,
		commandBufferCount = MAX_FRAMES_IN_FLIGHT,
	}

	assert_success(vk.AllocateCommandBuffers(app.device, &allocate_info, raw_data(app.command_buffers[:])))
}

create_command_pool :: proc() {
	graphics_pool := vk.CommandPoolCreateInfo {
		sType = .COMMAND_POOL_CREATE_INFO,
		flags = {.RESET_COMMAND_BUFFER},
		queueFamilyIndex = app.graphics_family_index,
	}

	assert_success(vk.CreateCommandPool(app.device, &graphics_pool, nil, &app.command_pool))	
}

create_instance :: proc() {
	app_info := vk.ApplicationInfo {
		sType = .APPLICATION_INFO,

		pApplicationName = "MyApplication",
		applicationVersion = 0,
		
		pEngineName = "MyCustomEngine",
		engineVersion = 0,
		
		apiVersion = vk.API_VERSION_1_2,
	}

	create_info := vk.InstanceCreateInfo {
		sType = .INSTANCE_CREATE_INFO,
		pApplicationInfo = &app_info,
	}

	// Validation layers
when ODIN_DEBUG {
	required_layers: [dynamic]cstring
	append(&required_layers, "VK_LAYER_KHRONOS_validation")

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

	// Extensions 
	required_extensions := slice.clone_to_dynamic(glfw.GetRequiredInstanceExtensions(), context.temp_allocator)

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
			log.panicf("Extension: %v not found")
		}
	}

	create_info.enabledExtensionCount = u32(len(required_extensions))
	create_info.ppEnabledExtensionNames = raw_data(required_extensions)

	assert_success(vk.CreateInstance(&create_info, nil, &app.instance))

	vk.load_proc_addresses_instance(app.instance)
}

cleanup :: proc() {
	cleanup_swapchain()

	vk.DestroySampler(app.device, app.texture_sampler, nil)

	vk.DestroyImageView(app.device, app.texture_image_view, nil)

	vk.DestroyImage(app.device, app.texture_image, nil)
	vk.FreeMemory(app.device, app.texture_image_memory, nil)

	for i in 0..<MAX_FRAMES_IN_FLIGHT {
		vk.DestroyBuffer(app.device, app.uniform_buffers[i], nil)
		vk.FreeMemory(app.device, app.uniform_buffers_memory[i], nil)
	}

	vk.DestroyDescriptorPool(app.device, app.descriptor_pool, nil)
	vk.DestroyDescriptorSetLayout(app.device, app.descriptor_set_layout, nil)

	vk.DestroyBuffer(app.device, app.index_buffer, nil)
	vk.FreeMemory(app.device, app.index_buffer_memory, nil)

	vk.DestroyBuffer(app.device, app.vertex_buffer, nil)
	vk.FreeMemory(app.device, app.vertex_buffer_memory, nil)

	vk.DestroyPipeline(app.device, app.graphics_pipeline, nil)		// Pipeline
	vk.DestroyPipelineLayout(app.device, app.pipeline_layout, nil)	// Pipeline layout

	vk.DestroyRenderPass(app.device, app.render_pass, nil)			// Renderpass

	for i in 0..<MAX_FRAMES_IN_FLIGHT {
		vk.DestroySemaphore(app.device, app.image_available_semaphores[i], nil)
		vk.DestroySemaphore(app.device, app.render_finished_semaphores[i], nil)
		vk.DestroyFence(app.device, app.in_flight_fences[i], nil)
	}

	vk.DestroyCommandPool(app.device, app.command_pool, nil)

	vk.DestroyDevice(app.device, nil)								// Device


when ODIN_DEBUG { // Debug messenger
	generic := vk.GetInstanceProcAddr(app.instance, "vkDestroyDebugUtilsMessengerEXT") 
	func := cast(vk.ProcDestroyDebugUtilsMessengerEXT)generic
	if func != nil {
		func(app.instance, app.debug_messenger, nil);
	}	
}

	vk.DestroySurfaceKHR(app.instance, app.surface, nil)			// Surface
	vk.DestroyInstance(app.instance, nil)						// Vk Instance

	glfw.DestroyWindow(app.window)									// Window
    glfw.Terminate()												// GLFW Instance
}

main :: proc() {
	context.logger = log.create_console_logger()

	app_init("Vulkan", 800, 600) 						// reserve memory for App struct and setup some parameters
	defer free(app)

	glfw_init()											// Init GLFW window and load global vk function pointers
	defer cleanup()
	
	create_instance()
when ODIN_DEBUG {
	create_debug_messenger() 
} // ODIN_DEBUG
	create_surface()
	pick_physical_device()
	create_logical_device()
	create_swapchain()
	create_image_views()
	create_render_pass()
	create_descriptor_set_layout()
	create_graphics_pipeline()
	
	create_command_pool()

	create_depth_resources()
	create_frame_buffers()

	create_texture_image()
	create_texture_image_view()
	create_texture_sampler()

	create_vertex_buffer()
	create_index_buffer()
	create_uniform_buffer()
	create_descriptor_pool()
	create_descriptor_sets()


	create_command_buffers()
	create_sync_objects()

	
    for !glfw.WindowShouldClose(app.window) {
        free_all(context.temp_allocator)
		glfw.PollEvents()
		draw_frame()
    }

	vk.DeviceWaitIdle(app.device)

	log.destroy_console_logger(context.logger)
}


create_depth_resources :: proc() {

	has_stencil_component :: proc(format: vk.Format) -> bool { return format == .D32_SFLOAT_S8_UINT || format == .D24_UNORM_S8_UINT }

	depth_format := find_depth_format()

	create_image(app.swapchain_extent.width, app.swapchain_extent.height, depth_format, .OPTIMAL, {.DEPTH_STENCIL_ATTACHMENT}, {.DEVICE_LOCAL}, &app.depth_image, &app.depth_image_memory)

	app.depth_image_view = create_image_view(app.depth_image, depth_format, {.DEPTH})
}

find_depth_format :: proc() -> vk.Format {
	return find_supported_format({ .D32_SFLOAT, .D32_SFLOAT_S8_UINT, .D24_UNORM_S8_UINT}, .OPTIMAL, {.DEPTH_STENCIL_ATTACHMENT})
}

find_supported_format :: proc(candidates: []vk.Format, tiling: vk.ImageTiling, features: vk.FormatFeatureFlags) -> vk.Format {

	for format in candidates {

		props: vk.FormatProperties
		vk.GetPhysicalDeviceFormatProperties(app.physical_device, format, &props)

		if tiling == .LINEAR && (props.linearTilingFeatures & features) == features {
			return format
		} else if tiling == .OPTIMAL && (props.optimalTilingFeatures & features) == features {
			return format
		}
	}

	log.panic("Failed to find supported format")
}

create_texture_sampler :: proc() {
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
		maxLod = 0,
	}

	props: vk.PhysicalDeviceProperties
	vk.GetPhysicalDeviceProperties(app.physical_device, &props)

	features: vk.PhysicalDeviceFeatures
	vk.GetPhysicalDeviceFeatures(app.physical_device, &features)
	
	if features.samplerAnisotropy {
		sampler_info.anisotropyEnable = true
		sampler_info.maxAnisotropy = props.limits.maxSamplerAnisotropy
	} else {
		sampler_info.anisotropyEnable = false
		sampler_info.maxAnisotropy = 1.0
	}

	assert_success(vk.CreateSampler(app.device, &sampler_info, nil, &app.texture_sampler))
}

create_texture_image_view :: proc() {
	app.texture_image_view = create_image_view(app.texture_image, .R8G8B8A8_SRGB, {.COLOR})
}

create_image_view :: proc(image: vk.Image, format: vk.Format, aspect_mask: vk.ImageAspectFlags) -> (view: vk.ImageView) {

	create_info := vk.ImageViewCreateInfo {
		sType = .IMAGE_VIEW_CREATE_INFO,
		image = image,
		viewType = .D2,
		format = format,
		subresourceRange = vk.ImageSubresourceRange {
			aspectMask = aspect_mask,
			baseMipLevel = 0,
			levelCount = 1,
			baseArrayLayer = 0,
			layerCount = 1,
		}
	}

	assert_success(vk.CreateImageView(app.device, &create_info, nil, &view))

	return view
}


import "core:image/jpeg"
import stbi "vendor:stb/image"

create_texture_image :: proc() {

	w, h, c: i32

	pixels := stbi.load(model_tex, &w, &h, &c, 4)






	//import stbi "vendor:stb/image"  :::    pixels := stbi.load("textures/face.jpg", &width, &height, nil, 4)
	if image, err := jpeg.load_from_file("textures/face.jpg", options={.alpha_add_if_missing}); err == nil { 
		
		image_size := vk.DeviceSize(image.width * image.height * image.channels)

		staging_buffer: vk.Buffer
		staging_buffer_memory: vk.DeviceMemory

		create_buffer(image_size, {.TRANSFER_SRC}, {.HOST_VISIBLE, .HOST_COHERENT}, &staging_buffer, &staging_buffer_memory)

		data: rawptr
		vk.MapMemory(app.device, staging_buffer_memory, 0, image_size, {}, &data)
		mem.copy(data, &image.pixels.buf[0], int(image_size))
		vk.UnmapMemory(app.device, staging_buffer_memory)

		create_image(u32(image.width), u32(image.height), .R8G8B8A8_SRGB, .OPTIMAL, {.TRANSFER_DST, .SAMPLED}, {.DEVICE_LOCAL}, &app.texture_image, &app.texture_image_memory)

		transition_image_layout(app.texture_image, .R8G8B8A8_SRGB, .UNDEFINED, .TRANSFER_DST_OPTIMAL)
		copy_buffer_to_image(staging_buffer, app.texture_image, u32(image.width), u32(image.height))
		transition_image_layout(app.texture_image, .R8G8B8A8_SRGB, .TRANSFER_DST_OPTIMAL, .SHADER_READ_ONLY_OPTIMAL)

		vk.DestroyBuffer(app.device, staging_buffer, nil)
		vk.FreeMemory(app.device, staging_buffer_memory, nil)
	} else {
		log.panicf("Image load error: %v", err)
	}
}

begin_single_time_commands :: proc() -> vk.CommandBuffer {
	
	alloc_info := vk.CommandBufferAllocateInfo {
		sType = .COMMAND_BUFFER_ALLOCATE_INFO,
		level = .PRIMARY,
		commandPool = app.command_pool,
		commandBufferCount = 1,
	}

	command_buffer: vk.CommandBuffer
	assert_success(vk.AllocateCommandBuffers(app.device, &alloc_info, &command_buffer))

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
	
	assert_success(vk.QueueSubmit(app.graphics_queue, 1, &submit_info, 0))

	assert_success(vk.QueueWaitIdle(app.graphics_queue))

	vk.FreeCommandBuffers(app.device, app.command_pool, 1, &cmds[0])
}

create_image :: proc(width, height: u32, format: vk.Format, tiling: vk.ImageTiling, usage: vk.ImageUsageFlags, properties: vk.MemoryPropertyFlags, image: ^vk.Image, image_memory: ^vk.DeviceMemory) {
		
	image_info := vk.ImageCreateInfo {
		sType = .IMAGE_CREATE_INFO,
		imageType = .D2,
		extent = vk.Extent3D {
			width = width,
			height = height,
			depth = 1,
		},
		mipLevels = 1,
		arrayLayers = 1,
		format = format,
		tiling = tiling,
		initialLayout = .UNDEFINED,
		usage = usage,
		sharingMode = .EXCLUSIVE,
		samples = {._1},
		flags = nil,
	}

	assert_success(vk.CreateImage(app.device, &image_info, nil, image))

	mem_reqs: vk.MemoryRequirements
	vk.GetImageMemoryRequirements(app.device, image^, &mem_reqs)

	alloc_info := vk.MemoryAllocateInfo {
		sType = .MEMORY_ALLOCATE_INFO,
		allocationSize = mem_reqs.size,
		memoryTypeIndex = find_memory_type(mem_reqs.memoryTypeBits, properties)
	}

	assert_success(vk.AllocateMemory(app.device, &alloc_info, nil, image_memory))

	assert_success(vk.BindImageMemory(app.device, image^, image_memory^, 0))
}

create_descriptor_sets :: proc() {

	layouts := [2]vk.DescriptorSetLayout { 
		app.descriptor_set_layout,
		app.descriptor_set_layout
	}

	alloc_info := vk.DescriptorSetAllocateInfo {
		sType = .DESCRIPTOR_SET_ALLOCATE_INFO,
		descriptorPool = app.descriptor_pool,
		pSetLayouts = raw_data(layouts[:]),
		descriptorSetCount = MAX_FRAMES_IN_FLIGHT,
	}

	assert_success(vk.AllocateDescriptorSets(app.device, &alloc_info, raw_data(app.descriptor_sets[:])))

	for i in 0..<MAX_FRAMES_IN_FLIGHT {
		buffer_info := vk.DescriptorBufferInfo {
			buffer = app.uniform_buffers[i],
			offset = 0,
			range = size_of(UniformBufferObject),
		}

		image_info := vk.DescriptorImageInfo {
			imageLayout = .SHADER_READ_ONLY_OPTIMAL,
			imageView = app.texture_image_view,
			sampler = app.texture_sampler,
		}

		descriptor_writes := [2]vk.WriteDescriptorSet {
				vk.WriteDescriptorSet {
				sType = .WRITE_DESCRIPTOR_SET,
				dstSet = app.descriptor_sets[i],
				dstBinding = 0,
				dstArrayElement = 0,
				descriptorCount = 1,
				descriptorType = .UNIFORM_BUFFER,
				pBufferInfo = &buffer_info,
			},
				vk.WriteDescriptorSet {
				sType = .WRITE_DESCRIPTOR_SET,
				dstSet = app.descriptor_sets[i],
				dstBinding = 1,
				dstArrayElement = 0,
				descriptorCount = 1,
				descriptorType = .COMBINED_IMAGE_SAMPLER,
				pImageInfo = &image_info
			}
		}

		vk.UpdateDescriptorSets(app.device, len(descriptor_writes), raw_data(descriptor_writes[:]), 0, nil)
	}

}

create_descriptor_pool :: proc() {

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

	assert_success(vk.CreateDescriptorPool(app.device, &pool_info, nil, &app.descriptor_pool))
}

create_uniform_buffer :: proc() {

	buffer_size :vk.DeviceSize= size_of(UniformBufferObject)

	for i in 0..<MAX_FRAMES_IN_FLIGHT {

		create_buffer(buffer_size, {.UNIFORM_BUFFER}, {.HOST_VISIBLE, .HOST_COHERENT}, &app.uniform_buffers[i], &app.uniform_buffers_memory[i])
		assert_success(vk.MapMemory(app.device, app.uniform_buffers_memory[i], 0, buffer_size, {}, &app.uniform_buffers_mapped[i]))

	}
}

create_descriptor_set_layout :: proc() {
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
		pImmutableSamplers = nil,
		stageFlags = {.FRAGMENT},
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

	assert_success(vk.CreateDescriptorSetLayout(app.device, &create_info, nil, &app.descriptor_set_layout))
}

create_index_buffer :: proc() {
	buffer_size :vk.DeviceSize= size_of(u32) * size_of(INDICES)

	staging_buffer: vk.Buffer
	staging_buffer_memory: vk.DeviceMemory

	create_buffer(buffer_size, {.TRANSFER_SRC}, {.HOST_VISIBLE, .HOST_COHERENT}, &staging_buffer, &staging_buffer_memory)

	data: rawptr
	assert_success(vk.MapMemory(app.device, staging_buffer_memory, 0, buffer_size, {}, &data))
	mem.copy(data, raw_data(INDICES), cast(int)buffer_size)

	create_buffer(buffer_size, {.TRANSFER_DST, .INDEX_BUFFER}, {.DEVICE_LOCAL}, &app.index_buffer, &app.index_buffer_memory)

	copy_buffer(staging_buffer, app.index_buffer, buffer_size)

	vk.DestroyBuffer(app.device, staging_buffer, nil)
	vk.FreeMemory(app.device, staging_buffer_memory, nil)
}

create_vertex_buffer :: proc() {
	buffer_size :vk.DeviceSize=  size_of(Vertex) * size_of(VERTICES)

	staging_buffer: vk.Buffer
	staging_buffer_memory: vk.DeviceMemory

	create_buffer(buffer_size, {.TRANSFER_SRC}, {.HOST_VISIBLE, .HOST_COHERENT}, &staging_buffer, &staging_buffer_memory)

	data: rawptr
	assert_success(vk.MapMemory(app.device, staging_buffer_memory, 0, buffer_size, {}, &data))
	mem.copy(data, raw_data(VERTICES), cast(int)buffer_size)
	vk.UnmapMemory(app.device, staging_buffer_memory)

	create_buffer(buffer_size, {.TRANSFER_DST, .VERTEX_BUFFER}, {.DEVICE_LOCAL}, &app.vertex_buffer, &app.vertex_buffer_memory)

	copy_buffer(staging_buffer, app.vertex_buffer, buffer_size)

	vk.DestroyBuffer(app.device, staging_buffer, nil)
	vk.FreeMemory(app.device, staging_buffer_memory, nil)
}

transition_image_layout :: proc(image: vk.Image, format: vk.Format, layout_old: vk.ImageLayout, layout_new: vk.ImageLayout) {
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
			levelCount = 1,
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

create_buffer :: proc(size: vk.DeviceSize, usage: vk.BufferUsageFlags, properties: vk.MemoryPropertyFlags, buffer: ^vk.Buffer, buffer_memory: ^vk.DeviceMemory) {
	buffer_info := vk.BufferCreateInfo {
		sType = .BUFFER_CREATE_INFO,
		size = size,
		usage = usage,
		sharingMode = .EXCLUSIVE
	}

	assert_success(vk.CreateBuffer(app.device, &buffer_info, nil, buffer))

	mem_requirements: vk.MemoryRequirements
	vk.GetBufferMemoryRequirements(app.device, buffer^, &mem_requirements)

	alloc_info := vk.MemoryAllocateInfo {
		sType = .MEMORY_ALLOCATE_INFO,
		allocationSize = mem_requirements.size,
		memoryTypeIndex = find_memory_type(mem_requirements.memoryTypeBits, properties)
	}

	assert_success(vk.AllocateMemory(app.device, &alloc_info, nil, buffer_memory))

	vk.BindBufferMemory(app.device, buffer^, buffer_memory^, 0)
}

find_memory_type :: proc(filter: u32, properties: vk.MemoryPropertyFlags) -> u32 {
	mem_properties: vk.PhysicalDeviceMemoryProperties
	vk.GetPhysicalDeviceMemoryProperties(app.physical_device, &mem_properties)

	for i in 0..<mem_properties.memoryTypeCount {
		if (filter & i) == i && (properties & mem_properties.memoryTypes[i].propertyFlags) == properties {
			return i
		}
	}

	log.panicf("Failed to find suitable memory types")
}

update_uniform_buffer :: proc(current_image: u32) {
	dur := time.diff(app.start_time, time.now())

	ubo := UniformBufferObject {
		model = glsl.mat4Rotate({0.0, 0.0, 1.0}, f32(time.duration_seconds(dur)) * glsl.radians(f32(90.0))),
		view = glsl.mat4LookAt({2.0, 2.0, 2.0}, {0.0, 0.0, 0.0}, {0.0, 0.0, 1.0}),
		proj = glsl.mat4Perspective(glsl.radians(f32(45)), f32(app.swapchain_extent.width) / f32(app.swapchain_extent.height), 0.1, 10.0)
	}

	ubo.proj[1][1] *= -1

	mem.copy(app.uniform_buffers_mapped[current_image], &ubo, size_of(ubo))
}

import "core:time"

draw_frame :: proc() {

	assert_success(vk.WaitForFences(app.device, 1, &app.in_flight_fences[app.current_frame], true, max(u64)))
	
	image_index: u32
	result := vk.AcquireNextImageKHR(app.device, app.swapchain, max(u64), app.image_available_semaphores[app.current_frame], 0, &image_index)

	if result == .ERROR_OUT_OF_DATE_KHR {
		recreate_swapchain()
		return
	} else if result != .SUCCESS && result != .SUBOPTIMAL_KHR {
		log.panicf("Failed to acquire swapchain images: %v", result)
	}

	update_uniform_buffer(app.current_frame)

	assert_success(vk.ResetFences(app.device, 1, &app.in_flight_fences[app.current_frame]))

	assert_success(vk.ResetCommandBuffer(app.command_buffers[app.current_frame], nil))

	record_command_buffer(app.command_buffers[app.current_frame], image_index)

	

	submit_info := vk.SubmitInfo {
		sType = .SUBMIT_INFO,
		
		waitSemaphoreCount = 1,
		pWaitSemaphores = &app.image_available_semaphores[app.current_frame],
		pWaitDstStageMask = &vk.PipelineStageFlags{.COLOR_ATTACHMENT_OUTPUT},
		commandBufferCount = 1,
		pCommandBuffers = &app.command_buffers[app.current_frame],

		signalSemaphoreCount = 1,
		pSignalSemaphores    = &app.render_finished_semaphores[app.current_frame],
	}

	assert_success(vk.QueueSubmit(app.graphics_queue, 1, &submit_info, app.in_flight_fences[app.current_frame]))

	present_info := vk.PresentInfoKHR {
		sType = .PRESENT_INFO_KHR,
		waitSemaphoreCount = 1,
		pWaitSemaphores = &app.render_finished_semaphores[app.current_frame],
		swapchainCount = 1,
		pSwapchains = &app.swapchain,
		pImageIndices = &image_index,
		pResults = nil,
	}

	present_result := vk.QueuePresentKHR(app.present_queue, &present_info)

	if present_result == .ERROR_OUT_OF_DATE_KHR || present_result == .SUBOPTIMAL_KHR || app.frame_buffer_resized {
		app.frame_buffer_resized = false
		recreate_swapchain()
	} else if  present_result != .SUCCESS {
		log.panic("Failed to present swapchain image")
	}

	app.current_frame = (app.current_frame + 1) % MAX_FRAMES_IN_FLIGHT
}

cleanup_swapchain :: proc() {
	vk.DestroyImageView(app.device, app.depth_image_view, nil)
	vk.DestroyImage(app.device, app.depth_image, nil)
	vk.FreeMemory(app.device, app.depth_image_memory, nil)

	for frame_buffer in app.swapchain_framebuffers {
		vk.DestroyFramebuffer(app.device, frame_buffer, nil)
	}

	for image_view in app.swapchain_views {
		vk.DestroyImageView(app.device, image_view, nil)
	}

	vk.DestroySwapchainKHR(app.device, app.swapchain, nil)
}

recreate_swapchain :: proc() {
	
	width, height := glfw.GetFramebufferSize(app.window)
	for width == 0 || height == 0 {
		width, height = glfw.GetFramebufferSize(app.window)
		glfw.WaitEvents()
		if glfw.WindowShouldClose(app.window) {
			break
		}
	}

	vk.DeviceWaitIdle(app.device)

	cleanup_swapchain()

	create_swapchain()
	create_image_views()
	create_depth_resources()
	create_frame_buffers()
}

create_render_pass :: proc() {

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
		format = app.swapchain_format.format,
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

	assert_success(vk.CreateRenderPass(app.device, &render_pass_info, nil, &app.render_pass))
}

assert_success :: proc(result: vk.Result, loc := #caller_location) {
	if result != .SUCCESS {
		log.panicf("vulkan failure: %v", result, location = loc)
	}
}

create_graphics_pipeline :: proc() {

	create_shader_module :: proc(code: []byte) -> (shader_module: vk.ShaderModule) {
		as_u32 := slice.reinterpret([]u32, code)

		create_info: vk.ShaderModuleCreateInfo = {
			sType = .SHADER_MODULE_CREATE_INFO,
			codeSize = len(code),
			pCode = raw_data(as_u32)
		}

		assert_success(vk.CreateShaderModule(app.device, &create_info, nil, &shader_module))

		return
	}

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
		pSetLayouts = &app.descriptor_set_layout,
		pushConstantRangeCount = 0,
		pPushConstantRanges = nil,
	}

	assert_success(vk.CreatePipelineLayout(app.device, &pipeline_layout_info, nil, &app.pipeline_layout))

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
		layout = app.pipeline_layout,
		renderPass = app.render_pass,
		subpass = 0,
		basePipelineHandle = 0,
		basePipelineIndex = -1,
	}
	
	assert_success(vk.CreateGraphicsPipelines(app.device, 0, 1, &pipeline_info, nil, &app.graphics_pipeline))

	vk.DestroyShaderModule(app.device, vert_shader_module, nil)
	vk.DestroyShaderModule(app.device, frag_shader_module, nil)
}