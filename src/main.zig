const c = @cImport({
    @cInclude("glad/glad.h");
    @cInclude("GLFW/glfw3.h");
    @cInclude("OpenGL/gl.h");
    @cInclude("stb_image.h");
});
const std = @import("std");

const Texture = struct {
    id: u32,
    file_path: [*c]const u8,

    const Self = @This();

    pub fn load(path: [*c]const u8, channels: c_uint) !Self {
        var width: i32 = 0;
        var height: i32 = 0;
        var nr_channels: i32 = 0;
        const texture_data = c.stbi_load(path, &width, &height, &nr_channels, 0);
        if (texture_data == null) {
            return error.CouldNotLoadTexture;
        }

        var texture_id: u32 = 0;
        c.glGenTextures(1, &texture_id);
        c.glBindTexture(c.GL_TEXTURE_2D, texture_id);
        c.glTexImage2D(c.GL_TEXTURE_2D, 0, c.GL_RGB, width, height, 0, channels, c.GL_UNSIGNED_BYTE, texture_data);
        c.glGenerateMipmap(c.GL_TEXTURE_2D);
        c.stbi_image_free(texture_data);

        std.log.debug("Texture::load: loaded {s}", .{path});

        return .{ .id = texture_id, .file_path = path };
    }

    pub fn bind(self: *const Self) void {
        c.glBindTexture(c.GL_TEXTURE_2D, self.id);
    }
};

const Shader = struct {
    id: u32,

    const Self = @This();

    /// Loads and compiles the shader from the given path
    pub fn load(allocator: std.mem.Allocator, path: []const u8) !Self {
        var shaderType: u32 = 0;
        if (std.mem.endsWith(u8, path, ".vert")) {
            shaderType = c.GL_VERTEX_SHADER;
        } else if (std.mem.endsWith(u8, path, ".frag")) {
            shaderType = c.GL_FRAGMENT_SHADER;
        } else {
            std.log.err(
                "Shader::load: invalid file path {s}, expected <name>.<frag | vert>",
                .{path},
            );
            return error.InvalidShaderPath;
        }

        const shaderContents = try std.fs.cwd().readFileAllocOptions(allocator, path, 0x1000, null, @alignOf(u8), 0);
        defer allocator.free(shaderContents);
        const shaderId = c.glCreateShader(shaderType);

        c.glShaderSource(shaderId, 1, &shaderContents.ptr, null);
        c.glCompileShader(shaderId);

        var s: i32 = 1;
        var info: [512]u8 = undefined;
        c.glGetShaderiv(shaderId, c.GL_COMPILE_STATUS, &s);

        if (s != c.GL_TRUE) {
            c.glGetShaderInfoLog(shaderId, @sizeOf(@TypeOf(info)), null, &info);
            std.log.err("Shader::load: compilation error in {s}: {s}", .{ path, info });
            return error.ShaderCompilation;
        }

        std.log.debug("Shader::load: successfully loaded & compiled {s}", .{path});

        return .{ .id = shaderId };
    }

    pub fn delete(self: *const Self) void {
        c.glDeleteShader(self.id);
    }
};

const ShaderProgram = struct {
    id: u32,
    const Self = @This();

    pub fn create(
        vertex: Shader,
        fragment: Shader,
        // FIXME(msh): these feels weird and hacky, probably need an options struct or
        // something here
        color_number: u32,
        color_var: [:0]const u8,
    ) !Self {
        const programId = c.glCreateProgram();
        c.glAttachShader(programId, vertex.id);
        c.glAttachShader(programId, fragment.id);
        c.glBindFragDataLocation(programId, color_number, color_var);
        c.glLinkProgram(programId);

        var s: i32 = 1;
        var info: [512]u8 = undefined;
        c.glGetProgramiv(programId, c.GL_LINK_STATUS, &s);

        if (s != c.GL_TRUE) {
            c.glGetProgramInfoLog(programId, @sizeOf(@TypeOf(info)), null, &info);
            std.log.err("ShaderProgram::create: could not link program: {s}", .{info});
            return error.ShaderProgramLink;
        }

        vertex.delete();
        fragment.delete();

        return .{ .id = programId };
    }

    pub fn use(self: *const Self) void {
        c.glUseProgram(self.id);
    }
};

const vertices = [_]f32{
    // positions   // colors      // texture coords
    0.5, 0.5, 0.0, 1.0, 0.0, 0.0, 1.0, 1.0, // top right
    0.5, -0.5, 0.0, 0.0, 1.0, 0.0, 1.0, 0.0, // bottom right
    -0.5, -0.5, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, // bottom let
    -0.5, 0.5, 0.0, 1.0, 1.0, 0.0, 0.0, 1.0, // top let
};

fn render(
    shaderProgram: *const ShaderProgram,
    vao: u32,
    first_texture: u32,
    second_texture: u32,
) void {
    c.glClearColor(0.2, 0.3, 0.2, 1.0);
    c.glClear(c.GL_COLOR_BUFFER_BIT);

    shaderProgram.use();
    c.glBindVertexArray(vao);

    c.glActiveTexture(c.GL_TEXTURE0);
    c.glBindTexture(c.GL_TEXTURE_2D, first_texture);
    c.glActiveTexture(c.GL_TEXTURE1);
    c.glBindTexture(c.GL_TEXTURE_2D, second_texture);

    c.glDrawElements(c.GL_TRIANGLES, 6, c.GL_UNSIGNED_INT, null);
    c.glBindVertexArray(0);
}

fn glfwErrorCallback(code: i32, description: [*c]const u8) callconv(.C) void {
    _ = code;
    std.log.err("glfw error: {s}", .{description});
}

fn framebufferSizeCallback(window: ?*c.GLFWwindow, width: i32, height: i32) callconv(.C) void {
    _ = window;
    std.log.debug("framebuffer size changed to width={d}, height={d}", .{ width, height });
    c.glViewport(0, 0, width, height);
}

pub fn main() !void {
    if (c.glfwInit() != c.GLFW_TRUE) {
        std.log.err("could not init glfw", .{});
    }

    c.glfwWindowHint(c.GLFW_CONTEXT_VERSION_MAJOR, 4);
    c.glfwWindowHint(c.GLFW_CONTEXT_VERSION_MINOR, 1);
    c.glfwWindowHint(c.GLFW_OPENGL_PROFILE, c.GLFW_OPENGL_CORE_PROFILE);
    c.glfwWindowHint(c.GLFW_OPENGL_FORWARD_COMPAT, c.GL_TRUE);

    _ = c.glfwSetErrorCallback(glfwErrorCallback);

    const window = c.glfwCreateWindow(800, 600, "OpenGL Demo", null, null) orelse {
        std.log.err("could not create window", .{});
        return;
    };

    _ = c.glfwSetFramebufferSizeCallback(window, framebufferSizeCallback);
    c.glfwMakeContextCurrent(window);

    const version = c.gladLoadGL();
    if (version == 0) {
        std.log.err("failed to initialize opengl context", .{});
        return;
    }

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    const shaderProgram = try ShaderProgram.create(
        try Shader.load(allocator, "./src/triangle.vert"),
        try Shader.load(allocator, "./src/triangle.frag"),
        0,
        "outColor",
    );

    // copy our vertices array into a buffer:
    var vbo: u32 = 0;
    c.glGenBuffers(1, &vbo);
    c.glBindBuffer(c.GL_ARRAY_BUFFER, vbo);
    c.glBufferData(c.GL_ARRAY_BUFFER, @sizeOf(@TypeOf(vertices)), &vertices, c.GL_STATIC_DRAW);

    // create a vertex array object for storing everything:
    var vao: u32 = 0;
    c.glGenVertexArrays(1, &vao);
    c.glBindVertexArray(vao);

    // create an elements buffer for de-duplicating indexes:
    const indices = [_]u32{
        0, 1, 3,
        1, 2, 3,
    };

    var ebo: u32 = 0;
    c.glGenBuffers(1, &ebo);
    c.glBindBuffer(c.GL_ELEMENT_ARRAY_BUFFER, ebo);
    c.glBufferData(c.GL_ELEMENT_ARRAY_BUFFER, @sizeOf(@TypeOf(indices)), &indices, c.GL_STATIC_DRAW);

    // set vertex attributes pointers
    const posAttribute = c.glGetAttribLocation(shaderProgram.id, "position");
    c.glVertexAttribPointer(@intCast(posAttribute), 3, c.GL_FLOAT, c.GL_FALSE, 8 * @sizeOf(f32), null);
    c.glEnableVertexAttribArray(@intCast(posAttribute));

    const colorAttribute = c.glGetAttribLocation(shaderProgram.id, "color");
    c.glVertexAttribPointer(@intCast(colorAttribute), 3, c.GL_FLOAT, c.GL_FALSE, 8 * @sizeOf(f32), @ptrFromInt(3 * @sizeOf(f32)));
    c.glEnableVertexAttribArray(@intCast(colorAttribute));

    const textureCoordAttr = c.glGetAttribLocation(shaderProgram.id, "textureCoord");
    c.glVertexAttribPointer(@intCast(textureCoordAttr), 2, c.GL_FLOAT, c.GL_FALSE, 8 * @sizeOf(f32), @ptrFromInt(6 * @sizeOf(f32)));
    c.glEnableVertexAttribArray(@intCast(textureCoordAttr));

    c.stbi_set_flip_vertically_on_load(1);
    const container_img = try Texture.load("./assets/container.jpg", c.GL_RGB);
    const face_img = try Texture.load("./assets/face.png", c.GL_RGBA);

    // QUESTION: where do these numbers come from that we're setting?
    shaderProgram.use();
    c.glUniform1i(c.glGetUniformLocation(shaderProgram.id, "textureData1"), 0);
    c.glUniform1i(c.glGetUniformLocation(shaderProgram.id, "textureData2"), 1);

    while (c.glfwWindowShouldClose(window) != c.GLFW_TRUE) {
        render(&shaderProgram, vao, container_img.id, face_img.id);
        c.glfwSwapBuffers(window);
        c.glfwPollEvents();
    }

    std.log.debug("exited render loop", .{});
}
