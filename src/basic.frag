#version 410 core

in vec3 Color;
in vec2 TextureCoord;
out vec4 outColor;

uniform sampler2D textureData1;
uniform sampler2D textureData2;

void main() {
	outColor = mix(texture(textureData1, TextureCoord), texture(textureData2, TextureCoord), 0.2);
}
