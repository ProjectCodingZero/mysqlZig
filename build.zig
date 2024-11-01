const std = @import("std");
// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});
    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});

    // This declares intent for the library to be installed into the standard
    // location when the user invokes the "install" step (the default step when
    // running `zig build`).
    const mysql_module = b.createModule(.{
        .root_source_file = b.path("src/mysql.zig"),
        .link_libc = true,
        .optimize = optimize,
        .target = target,
    });

    mysql_module.linkSystemLibrary("mysqlclient", .{});
    // This declares intent for the executable to be installed into the
    // standard location when the user invokes the "install" step (the default
    // step when running `zig build`).

    const connection_test = b.addTest(.{
        .name = "connection_test",
        .root_source_file = b.path("test/Connection.zig"),
        .target = target,
        .optimize = optimize,
    });
    connection_test.root_module.addImport("mysql", mysql_module);
    const test_cmd = b.addRunArtifact(connection_test);
    test_cmd.step.dependOn(b.getInstallStep());
    const test_step = b.step("test", "run the test");
    test_step.dependOn(&test_cmd.step);
}
