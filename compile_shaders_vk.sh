#!/bin/bash

# Path to glslc
GLSLC="$HOME/VulkanSDK/1.4.328.1/macOS/bin/glslc"

# Compile shaders
"$GLSLC" shaders/shader.vert -o shaders/vert.spv
"$GLSLC" shaders/shader.frag -o shaders/frag.spv

echo "Shaders compiled!"