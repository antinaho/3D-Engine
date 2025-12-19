#version 450

// Binding
layout(binding = 1) uniform sampler2D texSampler;

// In
layout(location = 0) in vec3 fragColor;
layout(location = 1) in vec2 fragTexCoord;

// Out
layout(location = 0) out vec4 outColor;

void main() {
    outColor = texture(texSampler, fragTexCoord);
    //outColor = vec4(fragTexCoord, 0.0, 1.0);
}