#version 410 core

layout (location = 0) in vec3 position;
layout (location = 2) in vec2 textureCoord;

out vec2 TextureCoord;

uniform mat4 transform;

void main()
{
    TextureCoord = textureCoord;
    gl_Position = transform * vec4(position, 1.0);
}
