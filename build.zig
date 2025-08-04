const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // dht modules
    const dht_mod = b.addModule("dht", .{
        .root_source_file = b.path("dht/dht.zig"),
    });
    const table_mod = b.addModule("table", .{
        .root_source_file = b.path("dht/table.zig"),
    });
    const node_mod = b.addModule("node", .{
        .root_source_file = b.path("dht/node.zig"),
    });
    const msg_mod = b.addModule("msg", .{
        .root_source_file = b.path("dht/msg.zig"),
    });
    const sim_mod = b.addModule("sim", .{
        .root_source_file = b.path("dht/sim.zig"),
    });

    // dht simulator
    const sim_exe = b.addExecutable(.{
        .name = "dht-sim",
        .root_source_file = b.path("dht/sim.zig"),
        .target = target,
        .optimize = optimize,
    });
    sim_exe.root_module.addImport("dht", dht_mod);
    sim_exe.root_module.addImport("table", table_mod);
    sim_exe.root_module.addImport("node", node_mod);
    sim_exe.root_module.addImport("msg", msg_mod);
    sim_exe.root_module.addImport("sim", sim_mod);
    b.installArtifact(sim_exe);

    // run dht simulator
    const run_sim = b.addRunArtifact(sim_exe);
    run_sim.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_sim.addArgs(args);
    }
    const run_step = b.step("sim", "Run the DHT simulator");
    run_step.dependOn(&run_sim.step);

    // dht tests
    const dht_tests = b.addTest(.{
        .root_source_file = b.path("dht/test.zig"),
        .target = target,
        .optimize = optimize,
    });
    dht_tests.root_module.addImport("dht", dht_mod);
    dht_tests.root_module.addImport("table", table_mod);
    dht_tests.root_module.addImport("node", node_mod);
    dht_tests.root_module.addImport("msg", msg_mod);
    dht_tests.root_module.addImport("sim", sim_mod);

    const test_step = b.step("test", "Run all tests");
    test_step.dependOn(&dht_tests.step);
}
