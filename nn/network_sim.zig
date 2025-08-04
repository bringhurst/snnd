const std = @import("std");
const network_mod = @import("network");

const Network = network_mod.Network;
const NetworkConfig = network_mod.NetworkConfig;
const BenchmarkResult = network_mod.BenchmarkResult;
const DelayedSpike = network_mod.DelayedSpike;

pub const NetworkSim = struct {
    network: Network,
    start_time: i128 = 0,
    init_time: i128 = 0,
    simulation_time: i128 = 0,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, config: NetworkConfig) !Self {
        const start = std.time.nanoTimestamp();
        const network = try Network.init(allocator, config);
        const init_time = std.time.nanoTimestamp();

        return Self{
            .network = network,
            .start_time = start,
            .init_time = init_time,
            .simulation_time = 0,
        };
    }

    pub fn run(self: *Self) !void {
        const steps = @as(u32, @intFromFloat(self.network.config.duration / self.network.config.dt));

        var delayed_spikes = std.ArrayList(DelayedSpike).init(self.network.allocator);
        defer delayed_spikes.deinit();

        if (!self.network.config.benchmark_mode) {
            const print = std.debug.print;
            print("network simulation:\n", .{});
            print("  neurons: {}\n", .{self.network.config.neurons});
            print("  connections: {d:.1}%\n", .{self.network.config.connections * 100});
            print("  duration: {d:.1}ms\n", .{self.network.config.duration});
            print("  dt: {d:.3}ms\n", .{self.network.config.dt});
            print("  background current: {d:.1}nA\n", .{self.network.config.background_current});
        }

        for (0..steps) |step| {
            const t = @as(f32, @floatFromInt(step)) * self.network.config.dt;
            _ = try self.network.step(t, &delayed_spikes);

            if (!self.network.config.benchmark_mode and step % (steps / 20) == 0) {
                const progress = @as(f32, @floatFromInt(step)) / @as(f32, @floatFromInt(steps)) * 100;
                std.debug.print("  progress: {d:.0}%\r", .{progress});
            }
        }

        if (!self.network.config.benchmark_mode) {
            std.debug.print("  progress: 100%\n", .{});
        }

        self.simulation_time = std.time.nanoTimestamp();
    }

    pub fn printBenchmarkResults(self: *const Self) !void {
        const stats = self.network.getStatistics();

        const init_duration_ms = @as(f64, @floatFromInt(self.init_time - self.start_time)) / 1_000_000.0;
        const sim_duration_ms = @as(f64, @floatFromInt(self.simulation_time - self.init_time)) / 1_000_000.0;
        const total_duration_ms = @as(f64, @floatFromInt(self.simulation_time - self.start_time)) / 1_000_000.0;

        const spikes_per_ms = @as(f64, @floatFromInt(stats.total_spikes)) / sim_duration_ms;
        const neurons_per_ms = @as(f64, @floatFromInt(self.network.config.neurons)) / sim_duration_ms;

        const benchmark_results = [_]BenchmarkResult{
            .{ .name = "total-simulation-time", .unit = "ms", .value = total_duration_ms },
            .{ .name = "initialization-time", .unit = "ms", .value = init_duration_ms },
            .{ .name = "simulation-time", .unit = "ms", .value = sim_duration_ms },
            .{ .name = "mean-firing-rate", .unit = "Hz", .value = stats.mean_rate },
            .{ .name = "active-neuron-ratio", .unit = "ratio", .value = stats.activity_ratio },
            .{ .name = "total-spikes", .unit = "count", .value = @floatFromInt(stats.total_spikes) },
            .{ .name = "active-neurons", .unit = "count", .value = @floatFromInt(stats.active_neurons) },
            .{ .name = "total-synapses", .unit = "count", .value = @floatFromInt(stats.total_synapses) },
            .{ .name = "simulation-throughput-spikes", .unit = "spikes/ms", .value = spikes_per_ms },
            .{ .name = "simulation-throughput-neurons", .unit = "neurons/ms", .value = neurons_per_ms },
        };

        const stdout = std.io.getStdOut().writer();
        try stdout.print("[", .{});
        for (benchmark_results, 0..) |result, i| {
            if (i > 0) try stdout.print(",", .{});
            try stdout.print("{{\"name\":\"{s}\",\"unit\":\"{s}\",\"value\":{d:.6}}}", .{ result.name, result.unit, result.value });
        }
        try stdout.print("]\n", .{});
    }

    pub fn deinit(self: *Self) void {
        self.network.deinit();
    }
};

fn parseCommandLine(allocator: std.mem.Allocator) !NetworkConfig {
    var config = NetworkConfig{};
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--neurons")) {
            i += 1;
            if (i < args.len) config.neurons = try std.fmt.parseInt(u32, args[i], 10);
        } else if (std.mem.eql(u8, args[i], "--connections")) {
            i += 1;
            if (i < args.len) config.connections = try std.fmt.parseFloat(f32, args[i]);
        } else if (std.mem.eql(u8, args[i], "--duration")) {
            i += 1;
            if (i < args.len) config.duration = try std.fmt.parseFloat(f32, args[i]);
        } else if (std.mem.eql(u8, args[i], "--current")) {
            i += 1;
            if (i < args.len) config.background_current = try std.fmt.parseFloat(f32, args[i]);
        } else if (std.mem.eql(u8, args[i], "--seed")) {
            i += 1;
            if (i < args.len) config.seed = try std.fmt.parseInt(u64, args[i], 10);
        } else if (std.mem.eql(u8, args[i], "--benchmark")) {
            config.benchmark_mode = true;
        } else if (std.mem.eql(u8, args[i], "--help")) {
            const print = std.debug.print;
            print("neural network simulator\n\n", .{});
            print("usage: sim-network [options]\n\n", .{});
            print("options:\n", .{});
            print("  --neurons n       number of neurons (default: 100)\n", .{});
            print("  --connections p   connection probability 0-1 (default: 0.1)\n", .{});
            print("  --duration t      simulation duration in ms (default: 1000)\n", .{});
            print("  --current i       background current in nA (default: 1.5)\n", .{});
            print("  --seed s          random seed (default: 42)\n", .{});
            print("  --benchmark       output benchmark results in JSON format\n", .{});
            print("  --help           show this help\n", .{});
            std.process.exit(0);
        }
    }

    return config;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const config = try parseCommandLine(allocator);
    var sim = try NetworkSim.init(allocator, config);
    defer sim.deinit();

    try sim.run();

    if (config.benchmark_mode) {
        try sim.printBenchmarkResults();
    } else {
        sim.network.printResults();
        try sim.network.checkHealth();
    }
}
