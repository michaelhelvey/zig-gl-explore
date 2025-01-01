const std = @import("std");

const Program = struct {
    path: []const u8,
    exe: []const u8,
};

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const programs = [_]Program{
        .{ .path = "./src/basic.zig", .exe = "basic" },
        .{ .path = "./src/lighting.zig", .exe = "lighting" },
    };

    for (programs) |program| {
        const exe = b.addExecutable(.{
            .root_source_file = b.path(program.path),
            .target = target,
            .optimize = optimize,
            .name = program.exe,
        });

        const zlm = b.dependency("zlm", .{});
        exe.root_module.addImport("zlm", zlm.module("zlm"));

        exe.addCSourceFiles(.{ .files = &[_][]const u8{ "./src/glad/src/glad.c", "./src/stb/stb_image.c" } });
        exe.addLibraryPath(std.Build.LazyPath{ .cwd_relative = "/opt/homebrew/lib" });
        exe.addSystemIncludePath(std.Build.LazyPath{ .cwd_relative = "/opt/homebrew/include" });
        exe.addSystemIncludePath(b.path("./src/glad/include"));
        exe.addSystemIncludePath(b.path("./src/stb"));
        exe.linkSystemLibrary("glfw3");
        exe.linkFramework("OpenGL");
        exe.linkLibC();

        b.installArtifact(exe);
    }
}
