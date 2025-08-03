const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // dht
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

    const all_tests = b.step("test", "run all tests");
    all_tests.dependOn(&dht_tests.step);
}
