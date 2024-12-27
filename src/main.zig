const c = @cImport({
    @cInclude("glad/glad.h");
    @cInclude("GLFW/glfw3.h");
    @cInclude("OpenGL/gl.h");
});
const std = @import("std");

const vertexShaderSource =
    \\ #version 410 core
    \\ layout (location = 0) in vec3 position;
    \\ void main()
    \\ {
    \\  gl_Position = vec4(position.x, position.y, position.z, 1.0);
    \\ }
;

const fragmentShaderSource =
    \\ #version 410 core
    \\ uniform vec3 triangleColor;
    \\ out vec4 outColor;
    \\ void main()
    \\ {
    \\  outColor = vec4(triangleColor, 1.0f);
    \\ }
;

const vertices = [_]f32{
    0.5, 0.5, 0.0, // top right
    0.5, -0.5, 0.0, // bottom right
    -0.5, -0.5, 0.0, // bottom left
    -0.5, 0.5, 0.0, // top left
};

const indices = [_]u32{
    0, 1, 3, // first triangle
    1, 2, 3, // second triangle
};

fn render(shaderProgram: u32, vao: u32) void {
    c.glClearColor(0.2, 0.3, 0.2, 1.0);
    c.glClear(c.GL_COLOR_BUFFER_BIT);

    c.glUseProgram(shaderProgram);
    c.glBindVertexArray(vao);

    const triangleColor = c.glGetUniformLocation(shaderProgram, "triangleColor");
    const t = c.glfwGetTime();
    const green = @sin(t / 2.0) + 0.5;
    c.glUniform3f(triangleColor, 0.0, @floatCast(green), 0.0);

    c.glDrawElements(c.GL_TRIANGLES, 6, c.GL_UNSIGNED_INT, null);
    c.glBindVertexArray(0);
}

fn glfwErrorCallback(code: i32, description: [*c]const u8) callconv(.C) void {
    _ = code;
    std.log.err("glfw error: {s}\n", .{description});
}

fn framebufferSizeCallback(window: ?*c.GLFWwindow, width: i32, height: i32) callconv(.C) void {
    _ = window;
    c.glViewport(0, 0, width, height);
}

pub fn main() void {
    if (c.glfwInit() != c.GLFW_TRUE) {
        std.log.err("could not init glfw", .{});
    }

    c.glfwWindowHint(c.GLFW_CONTEXT_VERSION_MAJOR, 4);
    c.glfwWindowHint(c.GLFW_CONTEXT_VERSION_MINOR, 1);
    c.glfwWindowHint(c.GLFW_OPENGL_PROFILE, c.GLFW_OPENGL_CORE_PROFILE);
    c.glfwWindowHint(c.GLFW_OPENGL_FORWARD_COMPAT, c.GL_TRUE);

    _ = c.glfwSetErrorCallback(glfwErrorCallback);

    const window = c.glfwCreateWindow(800, 600, "OpenGL Demo", null, null) orelse {
        std.log.err("could not create window\n", .{});
        return;
    };

    _ = c.glfwSetFramebufferSizeCallback(window, framebufferSizeCallback);
    c.glfwMakeContextCurrent(window);

    const version = c.gladLoadGL();
    if (version == 0) {
        std.log.err("failed to initialize opengl context", .{});
        return;
    }

    const vertexShader = c.glCreateShader(c.GL_VERTEX_SHADER);
    c.glShaderSource(vertexShader, 1, @ptrCast(&vertexShaderSource), null);
    c.glCompileShader(vertexShader);
    var s: i32 = 1;
    var info: [512]u8 = undefined;
    c.glGetShaderiv(vertexShader, c.GL_COMPILE_STATUS, &s);

    if (s != c.GL_TRUE) {
        c.glGetShaderInfoLog(vertexShader, @sizeOf(@TypeOf(info)), null, &info);
        std.log.err("could not compile vertex shader: {s}\n", .{info});
        return;
    }

    const fragmentShader = c.glCreateShader(c.GL_FRAGMENT_SHADER);
    c.glShaderSource(fragmentShader, 1, @ptrCast(&fragmentShaderSource), null);
    c.glCompileShader(fragmentShader);

    @memset(&info, 0x0);
    c.glGetShaderiv(fragmentShader, c.GL_COMPILE_STATUS, &s);
    if (s != c.GL_TRUE) {
        c.glGetShaderInfoLog(fragmentShader, @sizeOf(@TypeOf(info)), null, &info);
        std.log.err("could not compile fragment shader: {s}\n", .{info});
        return;
    }

    const shaderProgram = c.glCreateProgram();
    c.glAttachShader(shaderProgram, vertexShader);
    c.glAttachShader(shaderProgram, fragmentShader);
    // 0 by default, so we don't technically need this line:
    c.glBindFragDataLocation(shaderProgram, 0, "outColor");
    c.glLinkProgram(shaderProgram);

    c.glGetProgramiv(shaderProgram, c.GL_LINK_STATUS, &s);
    if (s != c.GL_TRUE) {
        c.glGetProgramInfoLog(shaderProgram, @sizeOf(@TypeOf(info)), null, &info);
        std.log.err("could not link program: {s}\n", .{info});
        return;
    }

    c.glDeleteShader(fragmentShader);
    c.glDeleteShader(vertexShader);

    // copy our vertices array into a buffer:
    var vbo: u32 = 0;
    c.glGenBuffers(1, &vbo);
    c.glBindBuffer(c.GL_ARRAY_BUFFER, vbo);
    c.glBufferData(c.GL_ARRAY_BUFFER, @sizeOf(@TypeOf(vertices)), &vertices, c.GL_STATIC_DRAW);

    // create a vertex array object for storing everything:
    var vao: u32 = 0;
    c.glGenVertexArrays(1, &vao);
    c.glBindVertexArray(vao);

    // create an element buffer:
    var ebo: u32 = 0;
    c.glGenBuffers(1, &ebo);
    c.glBindBuffer(c.GL_ELEMENT_ARRAY_BUFFER, ebo);
    c.glBufferData(c.GL_ELEMENT_ARRAY_BUFFER, @sizeOf(@TypeOf(indices)), &indices, c.GL_STATIC_DRAW);

    // set vertex attributes pointers
    const posAttribute = c.glGetAttribLocation(shaderProgram, "position");
    c.glVertexAttribPointer(@intCast(posAttribute), 3, c.GL_FLOAT, c.GL_FALSE, 3 * @sizeOf(f32), null);
    c.glEnableVertexAttribArray(@intCast(posAttribute));

    while (c.glfwWindowShouldClose(window) != c.GLFW_TRUE) {
        render(shaderProgram, vao);
        c.glfwSwapBuffers(window);
        c.glfwPollEvents();
    }

    std.debug.print("exited render loop", .{});
}
