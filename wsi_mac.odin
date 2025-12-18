package main

import "vendor:glfw"
import vk "vendor:vulkan"

// MAC GLFW -> VULKAN

VULKAN_WSI_MAC :: VulkanWSI {
	get_global_proc_addresses = mac_vk_global_addresses,
	get_required_instance_extensions = mac_vk_required_exts,
	create_surface = mac_vk_create_surface,
}

mac_vk_global_addresses :: proc() -> rawptr {
	return rawptr(glfw.GetInstanceProcAddress)
}

mac_vk_required_exts :: proc() -> []cstring {
	return glfw.GetRequiredInstanceExtensions()
}

mac_vk_create_surface :: proc(window: rawptr, instance: vk.Instance, surface: ^vk.SurfaceKHR) -> vk.Result {
	return glfw.CreateWindowSurface(instance, glfw.WindowHandle(window), nil, surface)
}