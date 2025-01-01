const zlm = @import("zlm");
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

    /// Loads an image from the given path using stb_image
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

var camera_pitch: f32 = 0.0;
var camera_yaw: f32 = -90.0;

const Camera = struct {
    up: zlm.Vec3,
    front: zlm.Vec3,
    position: zlm.Vec3,

    const Self = @This();

    pub fn default() Self {
        return .{
            // TODO: we should really use the pitch and yaw values when calculating front here,
            // rather than doing it for the first time on mouse callback, and having them
            // "just happen" to be right because we hard-coded yaw to -90 (straight ahead??)
            .up = zlm.Vec3.new(0.0, 1.0, 0.0),
            .front = zlm.Vec3.new(0.0, 0.0, -1.0),
            .position = zlm.Vec3.new(0.0, 0.0, 3.0),
        };
    }

    pub fn lookAt(self: *const Self) zlm.Mat4 {
        return zlm.Mat4.createLookAt(self.position, self.position.add(self.front), self.up);
    }
};
var camera = Camera.default();

const vertices = [_]f32{
    -0.5, -0.5, -0.5, 0.0, 0.0,
    0.5,  -0.5, -0.5, 1.0, 0.0,
    0.5,  0.5,  -0.5, 1.0, 1.0,
    0.5,  0.5,  -0.5, 1.0, 1.0,
    -0.5, 0.5,  -0.5, 0.0, 1.0,
    -0.5, -0.5, -0.5, 0.0, 0.0,

    -0.5, -0.5, 0.5,  0.0, 0.0,
    0.5,  -0.5, 0.5,  1.0, 0.0,
    0.5,  0.5,  0.5,  1.0, 1.0,
    0.5,  0.5,  0.5,  1.0, 1.0,
    -0.5, 0.5,  0.5,  0.0, 1.0,
    -0.5, -0.5, 0.5,  0.0, 0.0,

    -0.5, 0.5,  0.5,  1.0, 0.0,
    -0.5, 0.5,  -0.5, 1.0, 1.0,
    -0.5, -0.5, -0.5, 0.0, 1.0,
    -0.5, -0.5, -0.5, 0.0, 1.0,
    -0.5, -0.5, 0.5,  0.0, 0.0,
    -0.5, 0.5,  0.5,  1.0, 0.0,

    0.5,  0.5,  0.5,  1.0, 0.0,
    0.5,  0.5,  -0.5, 1.0, 1.0,
    0.5,  -0.5, -0.5, 0.0, 1.0,
    0.5,  -0.5, -0.5, 0.0, 1.0,
    0.5,  -0.5, 0.5,  0.0, 0.0,
    0.5,  0.5,  0.5,  1.0, 0.0,

    -0.5, -0.5, -0.5, 0.0, 1.0,
    0.5,  -0.5, -0.5, 1.0, 1.0,
    0.5,  -0.5, 0.5,  1.0, 0.0,
    0.5,  -0.5, 0.5,  1.0, 0.0,
    -0.5, -0.5, 0.5,  0.0, 0.0,
    -0.5, -0.5, -0.5, 0.0, 1.0,

    -0.5, 0.5,  -0.5, 0.0, 1.0,
    0.5,  0.5,  -0.5, 1.0, 1.0,
    0.5,  0.5,  0.5,  1.0, 0.0,
    0.5,  0.5,  0.5,  1.0, 0.0,
    -0.5, 0.5,  0.5,  0.0, 0.0,
    -0.5, 0.5,  -0.5, 0.0, 1.0,
};

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
    shaderProgram: *const ShaderProgram,
    vao: u32,
) void {
    c.glClearColor(0.2, 0.3, 0.2, 1.0);
    c.glClear(c.GL_COLOR_BUFFER_BIT | c.GL_DEPTH_BUFFER_BIT);

    shaderProgram.use();
    c.glBindVertexArray(vao);

    const view = camera.lookAt();
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

fn glfwErrorCallback(code: i32, description: [*c]const u8) callconv(.C) void {
    _ = code;
    std.log.err("glfw error: {s}", .{description});
}

fn framebufferSizeCallback(window: ?*c.GLFWwindow, width: i32, height: i32) callconv(.C) void {
    _ = window;
    std.log.debug("framebuffer size changed to width={d}, height={d}", .{ width, height });
    c.glViewport(0, 0, width, height);
}

fn processInput(window: *c.GLFWwindow, deltaTime: f32) void {
    // TODO: move this stuff into the camera class
    const camera_speed = deltaTime * 2.5;
    if (c.glfwGetKey(window, c.GLFW_KEY_W) == c.GLFW_PRESS) {
        camera.position = camera.position.add(camera.front.scale(camera_speed));
    }

    if (c.glfwGetKey(window, c.GLFW_KEY_S) == c.GLFW_PRESS) {
        camera.position = camera.position.sub(camera.front.scale(camera_speed));
    }

    if (c.glfwGetKey(window, c.GLFW_KEY_A) == c.GLFW_PRESS) {
        camera.position = camera.position.sub(camera.front.cross(camera.up).normalize().scale(camera_speed));
    }

    if (c.glfwGetKey(window, c.GLFW_KEY_D) == c.GLFW_PRESS) {
        camera.position = camera.position.add(camera.front.cross(camera.up).normalize().scale(camera_speed));
    }
}

// TODO: set this to the center of the window based on our defined size
var mouse_x: f32 = 400.0;
var mouse_y: f32 = 300.0;
var first_mouse = true;

fn mouseCallback(window: ?*c.GLFWwindow, x: f64, y: f64) callconv(.C) void {
    _ = window;
    // calculate the distance between the x and y of the last frame
    // add the offsets to the camera's pitch and yaw values
    // add constraints to the min/max pitch values
    // set the camera's new direction vector
    if (first_mouse) {
        mouse_x = @floatCast(x);
        mouse_y = @floatCast(y);
        first_mouse = false;
    }
    const sens = 0.1;
    var xoff: f64 = x - mouse_x;
    var yoff: f64 = mouse_y - y; // reversed since postive y movement = y > previous_y
    mouse_x = @floatCast(x);
    mouse_y = @floatCast(y);

    xoff = xoff * sens;
    yoff = yoff * sens;

    camera_yaw += @floatCast(xoff);
    camera_pitch += @floatCast(yoff);

    std.log.debug("yaw = {d}, pitch = {d}", .{ camera_yaw, camera_pitch });

    camera_pitch = std.math.clamp(camera_pitch, -89.0, 89.0);
    const direction_vector = zlm.Vec3.new(
        @cos(zlm.toRadians(camera_yaw)) * @cos(zlm.toRadians(camera_pitch)),
        @sin(zlm.toRadians(camera_pitch)),
        @sin(zlm.toRadians(camera_yaw)) * @cos(zlm.toRadians(camera_pitch)),
    );

    camera.front = direction_vector.normalize();
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
    c.glfwSetInputMode(window, c.GLFW_CURSOR, c.GLFW_CURSOR_DISABLED);
    _ = c.glfwSetCursorPosCallback(window, mouseCallback);

    const version = c.gladLoadGL();
    if (version == 0) {
        std.log.err("failed to initialize opengl context", .{});
        return;
    }

    c.glEnable(c.GL_DEPTH_TEST);

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    const shaderProgram = try ShaderProgram.create(
        try Shader.load(allocator, "./src/basic.vert"),
        try Shader.load(allocator, "./src/basic.frag"),
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

    c.stbi_set_flip_vertically_on_load(1);
    const container_img = try Texture.load("./assets/container.jpg", c.GL_RGB);
    const face_img = try Texture.load("./assets/face.png", c.GL_RGBA);

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
        processInput(window, @floatCast(deltaTime));
        render(&shaderProgram, vao);
        c.glfwSwapBuffers(window);
        c.glfwPollEvents();
    }

    std.log.debug("exited render loop", .{});
}