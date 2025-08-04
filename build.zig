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

    // neuron modules
    const lif_mod = b.addModule("lif", .{
        .root_source_file = b.path("nn/lif/lif.zig"),
    });
    const lif_sim_mod = b.addModule("lif_sim", .{
        .root_source_file = b.path("nn/lif/sim.zig"),
    });

    // dht simulator
    const dht_sim_exe = b.addExecutable(.{
        .name = "sim-dht",
        .root_source_file = b.path("dht/sim.zig"),
        .target = target,
        .optimize = optimize,
    });
    dht_sim_exe.root_module.addImport("dht", dht_mod);
    dht_sim_exe.root_module.addImport("table", table_mod);
    dht_sim_exe.root_module.addImport("node", node_mod);
    dht_sim_exe.root_module.addImport("msg", msg_mod);
    dht_sim_exe.root_module.addImport("sim", sim_mod);
    b.installArtifact(dht_sim_exe);

    // lif simulator
    const lif_sim_exe = b.addExecutable(.{
        .name = "sim-neuron-lif",
        .root_source_file = b.path("nn/lif/sim.zig"),
        .target = target,
        .optimize = optimize,
    });
    lif_sim_exe.root_module.addImport("lif", lif_mod);
    b.installArtifact(lif_sim_exe);

    // run dht simulator
    const run_dht_sim = b.addRunArtifact(dht_sim_exe);
    run_dht_sim.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_dht_sim.addArgs(args);
    }
    const run_dht_step = b.step("sim-dht", "Run the DHT simulator");
    run_dht_step.dependOn(&run_dht_sim.step);

    // run lif simulator
    const run_lif_sim = b.addRunArtifact(lif_sim_exe);
    run_lif_sim.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_lif_sim.addArgs(args);
    }
    const run_lif_step = b.step("sim-neuron-lif", "Run the LIF neuron simulator");
    run_lif_step.dependOn(&run_lif_sim.step);

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

    // lif tests
    const lif_tests = b.addTest(.{
        .root_source_file = b.path("nn/lif/test.zig"),
        .target = target,
        .optimize = optimize,
    });
    lif_tests.root_module.addImport("lif", lif_mod);
    lif_tests.root_module.addImport("sim", lif_sim_mod);

    const test_step = b.step("test", "Run all tests");
    test_step.dependOn(&dht_tests.step);
    test_step.dependOn(&lif_tests.step);
}
