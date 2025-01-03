#version 410 core

layout (location = 0) in vec3 position;
layout (location = 2) in vec2 textureCoord;

out vec2 TextureCoord;

uniform mat4 model;
uniform mat4 view;
uniform mat4 projection;

void main()
{
    TextureCoord = textureCoord;
    gl_Position = projection * view * model * vec4(position, 1.0);
}
