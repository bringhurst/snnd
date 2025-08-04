const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const modules = createModules(b);
    const executables = createExecutables(b, target, optimize, modules);

    createRunSteps(b, executables);
    createTestSteps(b, target, optimize, modules);
}

const Modules = struct {
    // dht
    dht: *std.Build.Module,
    table: *std.Build.Module,
    node: *std.Build.Module,
    msg: *std.Build.Module,
    sim: *std.Build.Module,

    // nn
    lif: *std.Build.Module,
};

const Executables = struct {
    dht_sim: *std.Build.Step.Compile,
    network_sim: *std.Build.Step.Compile,
};

fn createModules(b: *std.Build) Modules {
    return Modules{
        // dht modules
        .dht = b.addModule("dht", .{
            .root_source_file = b.path("dht/dht.zig"),
        }),
        .table = b.addModule("table", .{
            .root_source_file = b.path("dht/table.zig"),
        }),
        .node = b.addModule("node", .{
            .root_source_file = b.path("dht/node.zig"),
        }),
        .msg = b.addModule("msg", .{
            .root_source_file = b.path("dht/msg.zig"),
        }),
        .sim = b.addModule("sim", .{
            .root_source_file = b.path("dht/sim.zig"),
        }),

        // neuron modules
        .lif = b.addModule("lif", .{
            .root_source_file = b.path("nn/lif/lif.zig"),
        }),
    };
}

fn createExecutables(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode, modules: Modules) Executables {
    // dht simulator
    const dht_sim_exe = b.addExecutable(.{
        .name = "sim-dht",
        .root_source_file = b.path("dht/sim.zig"),
        .target = target,
        .optimize = optimize,
    });
    dht_sim_exe.root_module.addImport("dht", modules.dht);
    dht_sim_exe.root_module.addImport("table", modules.table);
    dht_sim_exe.root_module.addImport("node", modules.node);
    dht_sim_exe.root_module.addImport("msg", modules.msg);
    dht_sim_exe.root_module.addImport("sim", modules.sim);
    b.installArtifact(dht_sim_exe);

    // network simulator
    const network_sim_exe = b.addExecutable(.{
        .name = "sim-network",
        .root_source_file = b.path("nn/network.zig"),
        .target = target,
        .optimize = optimize,
    });
    network_sim_exe.root_module.addImport("lif", modules.lif);
    b.installArtifact(network_sim_exe);

    return Executables{
        .dht_sim = dht_sim_exe,
        .network_sim = network_sim_exe,
    };
}

fn createRunSteps(b: *std.Build, executables: Executables) void {
    // dht simulator run step
    const run_dht_sim = b.addRunArtifact(executables.dht_sim);
    run_dht_sim.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_dht_sim.addArgs(args);
    }
    const run_dht_step = b.step("sim-dht", "Run the DHT simulator");
    run_dht_step.dependOn(&run_dht_sim.step);

    // network simulator run step
    const run_network_sim = b.addRunArtifact(executables.network_sim);
    run_network_sim.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_network_sim.addArgs(args);
    }
    const run_network_step = b.step("sim-network", "Run the neural network simulator");
    run_network_step.dependOn(&run_network_sim.step);
}

fn createTestSteps(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode, modules: Modules) void {
    // dht tests
    const dht_tests = b.addTest(.{
        .root_source_file = b.path("dht/test.zig"),
        .target = target,
        .optimize = optimize,
    });
    dht_tests.root_module.addImport("dht", modules.dht);
    dht_tests.root_module.addImport("table", modules.table);
    dht_tests.root_module.addImport("node", modules.node);
    dht_tests.root_module.addImport("msg", modules.msg);
    dht_tests.root_module.addImport("sim", modules.sim);

    // neuron tests
    const lif_tests = b.addTest(.{
        .root_source_file = b.path("nn/lif/test.zig"),
        .target = target,
        .optimize = optimize,
    });
    lif_tests.root_module.addImport("lif", modules.lif);

    // test step
    const test_step = b.step("test", "Run all tests");
    test_step.dependOn(&dht_tests.step);
    test_step.dependOn(&lif_tests.step);
}
