pub const c = @cImport({
    @cInclude("glad/glad.h");
    @cInclude("GLFW/glfw3.h");
    @cInclude("OpenGL/gl.h");
    @cInclude("stb_image.h");
});
