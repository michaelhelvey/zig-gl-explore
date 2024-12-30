const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .root_source_file = b.path("./src/main.zig"),
        .target = target,
        .optimize = optimize,
        .name = "game",
    });

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
