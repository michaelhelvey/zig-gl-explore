const zlm = @import("zlm");
const std = @import("std");
const c = @import("./c.zig").c;

const CAMERA_SPEED = 2.5;

pub const Camera = struct {
    up: zlm.Vec3,
    front: zlm.Vec3,
    position: zlm.Vec3,

    pitch: f32,
    yaw: f32,

    const Self = @This();

    pub fn default() Self {
        const default_pitch = 0.0;
        const default_yaw = -90.0; // "straight ahead"
        return .{
            .up = zlm.Vec3.new(0.0, 1.0, 0.0),
            .front = Self.directionVectorFromPitchAndYaw(default_pitch, default_yaw),
            .position = zlm.Vec3.new(0.0, 0.0, 3.0),
            .pitch = default_pitch,
            .yaw = default_yaw,
        };
    }

    fn directionVectorFromPitchAndYaw(pitch: f32, yaw: f32) zlm.Vec3 {
        const direction_vector = zlm.Vec3.new(
            @cos(zlm.toRadians(yaw)) * @cos(zlm.toRadians(pitch)),
            @sin(zlm.toRadians(pitch)),
            @sin(zlm.toRadians(yaw)) * @cos(zlm.toRadians(pitch)),
        );

        return direction_vector.normalize();
    }

    pub fn lookAt(self: *const Self) zlm.Mat4 {
        return zlm.Mat4.createLookAt(self.position, self.position.add(self.front), self.up);
    }
};

/// The default camera instance, exposed as a global so that we can access it in
/// the GLFW cursor callback.
pub var CAMERA = Camera.default();

/// Processes keyboard input before rendering
pub fn processInput(window: *c.GLFWwindow, deltaTime: f32) void {
    // TODO: move this stuff into the camera class
    const camera_speed = deltaTime * 2.5;
    if (c.glfwGetKey(window, c.GLFW_KEY_W) == c.GLFW_PRESS) {
        CAMERA.position = CAMERA.position.add(CAMERA.front.scale(camera_speed));
    }

    if (c.glfwGetKey(window, c.GLFW_KEY_S) == c.GLFW_PRESS) {
        CAMERA.position = CAMERA.position.sub(CAMERA.front.scale(camera_speed));
    }

    if (c.glfwGetKey(window, c.GLFW_KEY_A) == c.GLFW_PRESS) {
        CAMERA.position = CAMERA.position.sub(CAMERA.front.cross(CAMERA.up).normalize().scale(camera_speed));
    }

    if (c.glfwGetKey(window, c.GLFW_KEY_D) == c.GLFW_PRESS) {
        CAMERA.position = CAMERA.position.add(CAMERA.front.cross(CAMERA.up).normalize().scale(camera_speed));
    }
}

pub var MOUSE_X: f32 = 400.0;
pub var MOUSE_Y: f32 = 300.0;
var seen_mouse_event_before = false;

pub const LOOK_SENS: f32 = 0.1;

pub fn glfwMouseCallback(window: ?*c.GLFWwindow, x: f64, y: f64) callconv(.C) void {
    _ = window;

    if (!seen_mouse_event_before) {
        MOUSE_X = @floatCast(x);
        MOUSE_Y = @floatCast(y);
        seen_mouse_event_before = true;
    }

    const xoff = @as(f32, @floatCast(x - MOUSE_X)) * LOOK_SENS;
    const yoff = @as(f32, @floatCast(MOUSE_Y - y)) * LOOK_SENS;
    MOUSE_X = @floatCast(x);
    MOUSE_Y = @floatCast(y);

    CAMERA.yaw += xoff;
    CAMERA.pitch += yoff;
    CAMERA.pitch = std.math.clamp(CAMERA.pitch, -89.0, 89.0);

    CAMERA.front = Camera.directionVectorFromPitchAndYaw(CAMERA.pitch, CAMERA.yaw);
}

pub const Texture = struct {
    id: u32,
    file_path: [*c]const u8,

    const Self = @This();

    pub fn load(path: [:0]const u8) !Self {
        c.stbi_set_flip_vertically_on_load(1);
        var channels: c_uint = c.GL_RGB;
        if (std.mem.endsWith(u8, path, ".jpg")) {
            channels = c.GL_RGB;
        } else if (std.mem.endsWith(u8, path, ".jpeg")) {
            channels = c.GL_RGB;
        } else if (std.mem.endsWith(u8, path, ".png")) {
            channels = c.GL_RGBA;
        }
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

pub const Shader = struct {
    id: u32,

    const Self = @This();

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

pub const ShaderProgram = struct {
    id: u32,
    const Self = @This();

    pub fn create(
        vertex: Shader,
        fragment: Shader,
        color_number: u32,
        color_name: [:0]const u8,
    ) !Self {
        const programId = c.glCreateProgram();
        c.glAttachShader(programId, vertex.id);
        c.glAttachShader(programId, fragment.id);
        c.glBindFragDataLocation(programId, color_number, color_name);
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

fn glfwErrorCallback(code: i32, description: [*c]const u8) callconv(.C) void {
    _ = code;
    std.log.err("glfw error: {s}", .{description});
}

fn framebufferSizeCallback(window: ?*c.GLFWwindow, width: i32, height: i32) callconv(.C) void {
    _ = window;
    std.log.debug("framebuffer size changed to width={d}, height={d}", .{ width, height });
    c.glViewport(0, 0, width, height);
}

pub fn glInit() !*c.GLFWwindow {
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
        return error.WindowCreate;
    };

    _ = c.glfwSetFramebufferSizeCallback(window, framebufferSizeCallback);
    c.glfwMakeContextCurrent(window);
    c.glfwSetInputMode(window, c.GLFW_CURSOR, c.GLFW_CURSOR_DISABLED);
    _ = c.glfwSetCursorPosCallback(window, glfwMouseCallback);

    const version = c.gladLoadGL();
    if (version == 0) {
        std.log.err("failed to initialize opengl context", .{});
        return error.OpenGlInit;
    }

    c.glEnable(c.GL_DEPTH_TEST);

    return window;
}
