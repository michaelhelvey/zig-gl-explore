#version 410 core

layout (location = 0) in vec3 position;
layout (location = 1) in vec3 color;
layout (location = 2) in vec2 textureCoord;

out vec3 Color;
out vec2 TextureCoord;

void main()
{
    Color = color;
    TextureCoord = textureCoord;
    gl_Position = vec4(position, 1.0);
}
