const std = @import("std");
const zigglgen = @import("zigglgen");

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) !void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{ .preferred_optimize_mode = .ReleaseSafe });

    const lib = b.addSharedLibrary(.{
        .name = "retro_test_gl_shaders",
        // In this case the main source file is merely a path, however, in more
        // complicated build scripts, this could be a generated file.
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    lib.addIncludePath(b.path("include"));

    const use_gles = b.option(
        bool,
        "gles",
        "Target GL ES 2.0 instead of GL 2.0",
    ) orelse false;

    // Choose the OpenGL API, version, profile and extensions you want to generate bindings for.
    const gl_bindings = zigglgen.generateBindingsModule(
        b,
        o: { // -ptions
            var o = zigglgen.GeneratorOptions{ .api = .gles, .version = .@"2.0" };
            if (!use_gles) {
                o.api = .gl;
                o.extensions = &.{.ARB_framebuffer_object};
            }
            break :o o;
        },
    );

    // Import the generated module.
    lib.root_module.addImport("gl", gl_bindings);

    // This declares intent for the library to be installed into the standard
    // location when the user invokes the "install" step (the default step when
    // running `zig build`).
    const install_artifact = b.addInstallArtifact(
        lib,
        .{
            .dest_dir = .{
                .override = if (target.query.isNative())
                    .prefix
                else
                    .{ .custom = try target.query.zigTriple(b.allocator) },
            },
        },
    );
    b.getInstallStep().dependOn(&install_artifact.step);
}
