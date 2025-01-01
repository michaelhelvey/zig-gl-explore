const zlm = @import("zlm");
const c = @cImport({
    @cInclude("glad/glad.h");
    @cInclude("GLFW/glfw3.h");
    @cInclude("OpenGL/gl.h");
    @cInclude("stb_image.h");
});
const std = @import("std");

const WINDOW_HEIGHT = 600;
const WINDOW_WIDTH = 800;

fn render() void {
    c.glClearColor(0.3, 0.2, 0.1, 1.0);
    c.glClear(c.GL_COLOR_BUFFER_BIT);
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

    const window = c.glfwCreateWindow(WINDOW_WIDTH, WINDOW_HEIGHT, "OpenGL Lighting", null, null) orelse {
        std.log.err("could not create window", .{});
        return;
    };

    c.glfwMakeContextCurrent(window);
    _ = c.glfwSetFramebufferSizeCallback(window, framebufferSizeCallback);

    const version = c.gladLoadGL();
    if (version == 0) {
        std.log.err("failed to initialize opengl context", .{});
        return;
    }

    var lastTime: f64 = 0;
    var deltaTime: f64 = 0;
    while (c.glfwWindowShouldClose(window) != c.GLFW_TRUE) {
        const currentTime = c.glfwGetTime();
        deltaTime = currentTime - lastTime;
        lastTime = currentTime;
        render();
        c.glfwSwapBuffers(window);
        c.glfwPollEvents();
    }

    std.log.debug("exited render loop", .{});
}
