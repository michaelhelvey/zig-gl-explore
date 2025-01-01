const zlm = @import("zlm");
const c = @import("./c.zig").c;
const std = @import("std");
const vertices = @import("./cube.zig").cube_vertex_data;
const engine = @import("./utils.zig");

const cube_positions = [_]zlm.Vec3{
    zlm.Vec3.new(0.0, 0.0, 0.0),
    zlm.Vec3.new(2.0, 5.0, -15.0),
    zlm.Vec3.new(-1.5, -2.2, -2.5),
    zlm.Vec3.new(-3.8, -2.0, -12.3),
    zlm.Vec3.new(2.4, -0.4, -3.5),
    zlm.Vec3.new(-1.7, 3.0, -7.5),
    zlm.Vec3.new(1.3, -2.0, -2.5),
    zlm.Vec3.new(1.5, 2.0, -2.5),
    zlm.Vec3.new(1.5, 0.2, -1.5),
    zlm.Vec3.new(-1.3, 1.0, -1.5),
};

fn render(
    shaderProgram: *const engine.ShaderProgram,
    vao: u32,
) void {
    c.glClearColor(0.2, 0.3, 0.2, 1.0);
    c.glClear(c.GL_COLOR_BUFFER_BIT | c.GL_DEPTH_BUFFER_BIT);

    shaderProgram.use();
    c.glBindVertexArray(vao);

    const view = engine.CAMERA.lookAt();
    c.glUniformMatrix4fv(c.glGetUniformLocation(shaderProgram.id, "view"), 1, c.GL_FALSE, @ptrCast(&view.fields));

    for (cube_positions, 0..) |cube, i| {
        const translation = zlm.Mat4.createTranslation(cube);
        const angle: f32 = 20.0 * @as(f32, @floatFromInt(i + 1));
        const model = zlm.Mat4.createAngleAxis(zlm.Vec3.new(1.0, 0.3, 0.5), zlm.toRadians(angle)).mul(translation);
        c.glUniformMatrix4fv(c.glGetUniformLocation(shaderProgram.id, "model"), 1, c.GL_FALSE, @ptrCast(&model.fields));
        c.glDrawArrays(c.GL_TRIANGLES, 0, vertices.len);
    }

    c.glBindVertexArray(0);
}

pub fn main() !void {
    const window = try engine.glInit();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    const shaderProgram = try engine.ShaderProgram.create(
        try engine.Shader.load(allocator, "./src/basic.vert"),
        try engine.Shader.load(allocator, "./src/basic.frag"),
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

    // set vertex attributes pointers
    const posAttribute = c.glGetAttribLocation(shaderProgram.id, "position");
    c.glVertexAttribPointer(@intCast(posAttribute), 3, c.GL_FLOAT, c.GL_FALSE, 5 * @sizeOf(f32), null);
    c.glEnableVertexAttribArray(@intCast(posAttribute));

    const textureCoordAttr = c.glGetAttribLocation(shaderProgram.id, "textureCoord");
    c.glVertexAttribPointer(@intCast(textureCoordAttr), 2, c.GL_FLOAT, c.GL_FALSE, 5 * @sizeOf(f32), @ptrFromInt(3 * @sizeOf(f32)));
    c.glEnableVertexAttribArray(@intCast(textureCoordAttr));

    const container_img = try engine.Texture.load("./assets/container.jpg");
    const face_img = try engine.Texture.load("./assets/face.png");

    // QUESTION: these magic numbers feel pretty bad...is there some kind of more declarative way
    // to define textures?
    shaderProgram.use();
    c.glUniform1i(c.glGetUniformLocation(shaderProgram.id, "textureData1"), 0);
    c.glUniform1i(c.glGetUniformLocation(shaderProgram.id, "textureData2"), 1);

    c.glActiveTexture(c.GL_TEXTURE0);
    c.glBindTexture(c.GL_TEXTURE_2D, container_img.id);
    c.glActiveTexture(c.GL_TEXTURE1);
    c.glBindTexture(c.GL_TEXTURE_2D, face_img.id);

    const perspective = zlm.Mat4.createPerspective(zlm.toRadians(45.0), 800.0 / 600.0, 0.1, 100.0);
    c.glUniformMatrix4fv(c.glGetUniformLocation(shaderProgram.id, "projection"), 1, c.GL_FALSE, @ptrCast(&perspective.fields));

    var lastTime: f64 = 0;
    var deltaTime: f64 = 0;
    while (c.glfwWindowShouldClose(window) != c.GLFW_TRUE) {
        const currentTime = c.glfwGetTime();
        deltaTime = currentTime - lastTime;
        lastTime = currentTime;
        engine.processInput(window, @floatCast(deltaTime));
        render(&shaderProgram, vao);
        c.glfwSwapBuffers(window);
        c.glfwPollEvents();
    }

    std.log.debug("exited render loop", .{});
}
