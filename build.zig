const std = @import("std");

const Scanner = @import("wayland").Scanner;

pub fn build(b: *std.Build) void {
    const scanner = Scanner.create(b, .{});
    scanner.addSystemProtocol("stable/xdg-shell/xdg-shell.xml");
    scanner.addSystemProtocol("stable/linux-dmabuf/linux-dmabuf-v1.xml");
    scanner.addSystemProtocol("stable/tablet/tablet-v2.xml");
    scanner.addSystemProtocol("staging/cursor-shape/cursor-shape-v1.xml");

    scanner.generate("wl_compositor", 4);
    scanner.generate("wl_output", 4);
    scanner.generate("wl_seat", 4);
    scanner.generate("wl_shm", 1);
    scanner.generate("xdg_wm_base", 7);
    scanner.generate("zwp_linux_dmabuf_v1", 5);
    // I don't actually want tablet_manager, but it's required for
    // cursor_shape_manager :<
    scanner.generate("zwp_tablet_manager_v2", 2);
    scanner.generate("wp_cursor_shape_manager_v1", 2);
    //scanner.generate("zwp_linux_buffer_params_v1", 5);
    //scanner.generate("zwp_linux_dmabuf_feedback_v1", 5);

    const wayland = b.createModule(.{ .root_source_file = scanner.result });

    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const charcoal = b.addModule("charcoal", .{
        .root_source_file = b.path("src/charcoal.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    charcoal.addImport("wayland", wayland);
    charcoal.linkSystemLibrary("wayland-client", .{});

    const charcoal_tests = b.addTest(.{ .root_module = charcoal });
    const run_charcoal_tests = b.addRunArtifact(charcoal_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_charcoal_tests.step);

    {
        const demo = b.createModule(.{
            .root_source_file = b.path("demo/demo.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "charcoal", .module = charcoal },
            },
        });
        const demo_exe = b.addExecutable(.{ .name = "demo", .root_module = demo });
        const demo_build_step = b.step("demo-build", "build demo test thing");
        demo_build_step.dependOn(&demo_exe.step);

        const text_run_cmd = b.addRunArtifact(demo_exe);
        const text_run_step = b.step("demo", "Run gui demo test thing");
        text_run_step.dependOn(&text_run_cmd.step);
    }
}
