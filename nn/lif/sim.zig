const std = @import("std");
const lif = @import("lif.zig");

pub const SimConfig = struct {
    duration_ms: f64 = 1000.0, // simulation duration
    dt_ms: f64 = 0.1, // timestep
    input_current: f64 = 5.0, // constant input current (nA)
    neuron_params: lif.Params = lif.Params{},
    output_file: ?[]const u8 = null, // file to save results
};

pub const SimResult = struct {
    spike_times: std.ArrayList(f64),
    voltage_trace: std.ArrayList(f64),
    time_points: std.ArrayList(f64),

    pub fn deinit(self: *SimResult) void {
        self.spike_times.deinit();
        self.voltage_trace.deinit();
        self.time_points.deinit();
    }
};

pub fn runSimulation(allocator: std.mem.Allocator, config: SimConfig) !SimResult {
    var neuron = lif.LIF.init(config.neuron_params);

    var result = SimResult{
        .spike_times = std.ArrayList(f64).init(allocator),
        .voltage_trace = std.ArrayList(f64).init(allocator),
        .time_points = std.ArrayList(f64).init(allocator),
    };

    var time: f64 = 0.0;
    const steps = @as(usize, @intFromFloat(config.duration_ms / config.dt_ms));

    for (0..steps) |_| {
        const spiked = neuron.step(config.input_current, config.dt_ms);

        if (spiked) {
            try result.spike_times.append(time);
        }

        try result.voltage_trace.append(neuron.voltage());
        try result.time_points.append(time);

        time += config.dt_ms;
    }

    return result;
}

pub fn calculateISI(spike_times: []const f64, allocator: std.mem.Allocator) ![]f64 {
    if (spike_times.len < 2) return &[_]f64{};

    var isis = try allocator.alloc(f64, spike_times.len - 1);
    for (0..isis.len) |i| {
        isis[i] = spike_times[i + 1] - spike_times[i];
    }
    return isis;
}

pub fn calculateFiringRate(spike_times: []const f64, duration_ms: f64) f64 {
    return @as(f64, @floatFromInt(spike_times.len)) / (duration_ms / 1000.0);
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var config = SimConfig{};

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--duration") and i + 1 < args.len) {
            config.duration_ms = try std.fmt.parseFloat(f64, args[i + 1]);
            i += 1;
        } else if (std.mem.eql(u8, args[i], "--current") and i + 1 < args.len) {
            config.input_current = try std.fmt.parseFloat(f64, args[i + 1]);
            i += 1;
        } else if (std.mem.eql(u8, args[i], "--dt") and i + 1 < args.len) {
            config.dt_ms = try std.fmt.parseFloat(f64, args[i + 1]);
            i += 1;
        } else if (std.mem.eql(u8, args[i], "--help")) {
            try printUsage();
            return;
        }
    }

    const stdout = std.io.getStdOut().writer();

    try stdout.print("LIF simulation:\n", .{});
    try stdout.print("  duration: {d:.1}ms\n", .{config.duration_ms});
    try stdout.print("  dt: {d:.3}ms\n", .{config.dt_ms});
    try stdout.print("  input: {d:.1}nA\n", .{config.input_current});

    var result = try runSimulation(allocator, config);
    defer result.deinit();

    const firing_rate = calculateFiringRate(result.spike_times.items, config.duration_ms);

    const isis = try calculateISI(result.spike_times.items, allocator);
    defer allocator.free(isis);

    var mean_isi: f64 = 0.0;
    if (isis.len > 0) {
        for (isis) |isi| mean_isi += isi;
        mean_isi /= @as(f64, @floatFromInt(isis.len));
    }

    try stdout.print("results:\n", .{});
    try stdout.print("  spikes: {}\n", .{result.spike_times.items.len});
    try stdout.print("  rate: {d:.1}Hz\n", .{firing_rate});
    try stdout.print("  mean ISI: {d:.1}ms\n", .{mean_isi});

    if (result.spike_times.items.len > 0) {
        try stdout.print("  first spike: {d:.1}ms\n", .{result.spike_times.items[0]});
        try stdout.print("  last spike: {d:.1}ms\n", .{result.spike_times.items[result.spike_times.items.len - 1]});
    }
}

fn printUsage() !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.print("LIF Neuron Simulator\n", .{});
    try stdout.print("usage: zig run sim.zig [options]\n", .{});
    try stdout.print("options:\n", .{});
    try stdout.print("  --duration MS    simulation duration (default: 1000)\n", .{});
    try stdout.print("  --current NA     input current (default: 5.0)\n", .{});
    try stdout.print("  --dt MS          timestep (default: 0.1)\n", .{});
    try stdout.print("  --help           show this help\n", .{});
}
