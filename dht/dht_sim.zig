const std = @import("std");
const dht = @import("dht.zig");
const msg = @import("msg.zig");

pub const SimPeer = struct {
    dht: *dht.Dht,
    inbox: std.ArrayList(msg.Msg),
    peers_path: []u8,

    pub fn init(allocator: std.mem.Allocator, cfg: dht.Config) !*SimPeer {
        const self = try allocator.create(SimPeer);
        const owned_path = try allocator.dupe(u8, cfg.peers_path);

        var owned_cfg = cfg;
        owned_cfg.peers_path = owned_path;

        self.* = SimPeer{
            .dht = try dht.Dht.init(owned_cfg),
            .inbox = std.ArrayList(msg.Msg).init(allocator),
            .peers_path = owned_path,
        };
        return self;
    }

    pub fn deinit(self: *SimPeer, allocator: std.mem.Allocator) void {
        self.dht.deinit();
        self.inbox.deinit();
        allocator.free(self.peers_path);
        allocator.destroy(self);
    }

    pub fn send(_: *SimPeer, to: *SimPeer, m: msg.Msg) !void {
        try to.inbox.append(m);
    }

    pub fn recv_one(self: *SimPeer) !void {
        if (self.inbox.items.len == 0) return;
        _ = self.inbox.orderedRemove(0);
    }

    pub fn has_messages(self: *SimPeer) bool {
        return self.inbox.items.len > 0;
    }
};

pub const SimNet = struct {
    peers: std.ArrayList(*SimPeer),

    pub fn init(allocator: std.mem.Allocator) SimNet {
        return SimNet{ .peers = std.ArrayList(*SimPeer).init(allocator) };
    }

    pub fn deinit(self: *SimNet, allocator: std.mem.Allocator) void {
        for (self.peers.items) |peer| peer.deinit(allocator);
        self.peers.deinit();
    }

    pub fn add_peer(self: *SimNet, peer: *SimPeer) !void {
        try self.peers.append(peer);
    }

    pub fn step_all(self: *SimNet) !void {
        for (self.peers.items) |peer| try peer.recv_one();
    }

    pub fn any_pending(self: *SimNet) bool {
        for (self.peers.items) |peer| if (peer.has_messages()) return true;
        return false;
    }
};

pub const SimConfig = struct {
    duration_seconds: u64 = 30,
    num_peers: usize = 10,
    message_rate: u64 = 100,
    seed: u64 = 12345,
    benchmark_mode: bool = false, // NEW: benchmark output flag
};

pub const BenchmarkResult = struct {
    name: []const u8,
    unit: []const u8,
    value: f64,
};

pub const SimStats = struct {
    messages_sent: u64,
    messages_processed: u64,
    peer_connections: u64,
    simulation_time_ms: f64,
    setup_time_ms: f64,
    total_time_ms: f64,

    pub fn getMessageThroughput(self: SimStats) f64 {
        return @as(f64, @floatFromInt(self.messages_sent)) / (self.simulation_time_ms / 1000.0);
    }

    pub fn getProcessingThroughput(self: SimStats) f64 {
        return @as(f64, @floatFromInt(self.messages_processed)) / (self.simulation_time_ms / 1000.0);
    }
};

pub fn runSimulation(allocator: std.mem.Allocator, config: SimConfig) !SimStats {
    const total_start = std.time.nanoTimestamp();

    if (!config.benchmark_mode) {
        const stdout = std.io.getStdOut().writer();
        try stdout.print("Starting DHT simulation:\n", .{});
        try stdout.print("  Duration: {}s\n", .{config.duration_seconds});
        try stdout.print("  Peers: {}\n", .{config.num_peers});
        try stdout.print("  Message rate: {}/s\n", .{config.message_rate});
        try stdout.print("  Seed: {}\n", .{config.seed});
    }

    var prng = std.Random.DefaultPrng.init(config.seed);
    const random = prng.random();

    var net = SimNet.init(allocator);
    defer net.deinit(allocator);

    var peers = std.ArrayList(*SimPeer).init(allocator);
    defer peers.deinit();

    const setup_start = std.time.nanoTimestamp();

    for (0..config.num_peers) |i| {
        var id: dht.NodeId = undefined;
        random.bytes(&id);

        const peers_path = try std.fmt.allocPrint(allocator, ".dht_peers_{}", .{i});

        const cfg = dht.Config{
            .k = 8,
            .id = id,
            .addr = try std.net.Address.parseIp4("127.0.0.1", @intCast(8000 + i)),
            .allocator = allocator,
            .peers_path = peers_path,
        };

        const peer = try SimPeer.init(allocator, cfg);
        try peers.append(peer);
        try net.add_peer(peer);

        allocator.free(peers_path);
    }

    var peer_connections: u64 = 0;
    for (peers.items, 0..) |peer, i| {
        for (0..3) |_| {
            const other_idx = random.intRangeLessThan(usize, 0, peers.items.len);
            if (other_idx != i) {
                const other_peer = peers.items[other_idx];
                try peer.dht.add_peer(.{ .id = other_peer.dht.config.id, .addr = other_peer.dht.config.addr });
                peer_connections += 1;
            }
        }
    }

    const setup_end = std.time.nanoTimestamp();
    const setup_time_ms = @as(f64, @floatFromInt(setup_end - setup_start)) / 1_000_000.0;

    if (!config.benchmark_mode) {
        const stdout = std.io.getStdOut().writer();
        try stdout.print("Simulation running...\n", .{});
    }

    const sim_start = std.time.nanoTimestamp();
    const start_time = std.time.milliTimestamp();
    const end_time = start_time + @as(i64, @intCast(config.duration_seconds * 1000));

    var messages_sent: u64 = 0;
    var messages_processed: u64 = 0;
    var last_report = start_time;

    while (std.time.milliTimestamp() < end_time) {
        const messages_this_tick = config.message_rate / 10; // 10 ticks per second
        for (0..messages_this_tick) |_| {
            const from_idx = random.intRangeLessThan(usize, 0, peers.items.len);
            const to_idx = random.intRangeLessThan(usize, 0, peers.items.len);
            if (from_idx != to_idx) {
                const from_peer = peers.items[from_idx];
                const to_peer = peers.items[to_idx];

                const msg_type = random.intRangeLessThan(u8, 0, 3);
                const test_msg = switch (msg_type) {
                    0 => msg.Msg{ .Ping = .{ .from = from_peer.dht.config.id } },
                    1 => msg.Msg{ .FindNode = .{ .from = from_peer.dht.config.id, .target = to_peer.dht.config.id } },
                    else => msg.Msg{ .FindValue = .{ .from = from_peer.dht.config.id, .key = from_peer.dht.config.id } },
                };

                try SimPeer.send(from_peer, to_peer, test_msg);
                messages_sent += 1;
            }
        }

        const initial_pending = countPendingMessages(&net);
        try net.step_all();
        const final_pending = countPendingMessages(&net);
        messages_processed += initial_pending - final_pending;

        if (!config.benchmark_mode) {
            const now = std.time.milliTimestamp();
            if (now - last_report >= 5000) {
                const elapsed = @as(f64, @floatFromInt(now - start_time)) / 1000.0;
                const remaining = @as(f64, @floatFromInt(end_time - now)) / 1000.0;
                const stdout = std.io.getStdOut().writer();
                try stdout.print("Progress: {d:.1}s elapsed, {d:.1}s remaining, {} messages sent\n", .{ elapsed, remaining, messages_sent });
                last_report = now;
            }
        }

        std.time.sleep(100 * std.time.ns_per_ms);
    }

    const sim_end = std.time.nanoTimestamp();
    const simulation_time_ms = @as(f64, @floatFromInt(sim_end - sim_start)) / 1_000_000.0;
    const total_time_ms = @as(f64, @floatFromInt(sim_end - total_start)) / 1_000_000.0;

    const stats = SimStats{
        .messages_sent = messages_sent,
        .messages_processed = messages_processed,
        .peer_connections = peer_connections,
        .simulation_time_ms = simulation_time_ms,
        .setup_time_ms = setup_time_ms,
        .total_time_ms = total_time_ms,
    };

    if (!config.benchmark_mode) {
        const stdout = std.io.getStdOut().writer();
        try stdout.print("Simulation completed!\n", .{});
        try stdout.print("Total messages sent: {}\n", .{messages_sent});
        try stdout.print("Total messages processed: {}\n", .{messages_processed});
        try stdout.print("Average send rate: {d:.1} msg/s\n", .{stats.getMessageThroughput()});
        try stdout.print("Average processing rate: {d:.1} msg/s\n", .{stats.getProcessingThroughput()});
        try stdout.print("Setup time: {d:.2}ms\n", .{setup_time_ms});
        try stdout.print("Simulation time: {d:.2}ms\n", .{simulation_time_ms});
    }

    return stats;
}

fn countPendingMessages(net: *SimNet) u64 {
    var count: u64 = 0;
    for (net.peers.items) |peer| {
        count += @intCast(peer.inbox.items.len);
    }
    return count;
}

pub fn printBenchmarkResults(stats: SimStats) !void {
    const benchmark_results = [_]BenchmarkResult{
        .{ .name = "total-simulation-time", .unit = "ms", .value = stats.total_time_ms },
        .{ .name = "setup-time", .unit = "ms", .value = stats.setup_time_ms },
        .{ .name = "simulation-time", .unit = "ms", .value = stats.simulation_time_ms },
        .{ .name = "messages-sent", .unit = "count", .value = @floatFromInt(stats.messages_sent) },
        .{ .name = "messages-processed", .unit = "count", .value = @floatFromInt(stats.messages_processed) },
        .{ .name = "peer-connections", .unit = "count", .value = @floatFromInt(stats.peer_connections) },
        .{ .name = "message-throughput", .unit = "msg/s", .value = stats.getMessageThroughput() },
        .{ .name = "processing-throughput", .unit = "msg/s", .value = stats.getProcessingThroughput() },
        .{ .name = "message-efficiency", .unit = "ratio", .value = @as(f64, @floatFromInt(stats.messages_processed)) / @as(f64, @floatFromInt(stats.messages_sent)) },
    };

    const stdout = std.io.getStdOut().writer();
    try stdout.print("[", .{});
    for (benchmark_results, 0..) |result, i| {
        if (i > 0) try stdout.print(",", .{});
        try stdout.print("{{\"name\":\"{s}\",\"unit\":\"{s}\",\"value\":{d:.6}}}", .{ result.name, result.unit, result.value });
    }
    try stdout.print("]\n", .{});
}

fn printUsage() !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.print("DHT Simulator\n", .{});
    try stdout.print("\n", .{});
    try stdout.print("Usage: zig run sim.zig [options]\n", .{});
    try stdout.print("\n", .{});
    try stdout.print("Options:\n", .{});
    try stdout.print("  --duration SECONDS   Run simulation for N seconds (default: 30)\n", .{});
    try stdout.print("  --peers COUNT       Number of DHT peers to simulate (default: 10)\n", .{});
    try stdout.print("  --rate MSGS/SEC     Message rate per second (default: 100)\n", .{});
    try stdout.print("  --seed NUMBER       Random seed for deterministic runs (default: 12345)\n", .{});
    try stdout.print("  --benchmark         Output benchmark results in JSON format\n", .{});
    try stdout.print("  --help              Show this help\n", .{});
    try stdout.print("\n", .{});
    try stdout.print("Examples:\n", .{});
    try stdout.print("  zig run sim.zig -- --duration 60 --peers 20\n", .{});
    try stdout.print("  zig run sim.zig -- --duration 300 --rate 50 --seed 42\n", .{});
    try stdout.print("  zig run sim.zig -- --duration 120 --peers 50 --benchmark\n", .{});
    try stdout.print("\n", .{});
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
            config.duration_seconds = try std.fmt.parseInt(u64, args[i + 1], 10);
            i += 1;
        } else if (std.mem.eql(u8, args[i], "--peers") and i + 1 < args.len) {
            config.num_peers = try std.fmt.parseInt(usize, args[i + 1], 10);
            i += 1;
        } else if (std.mem.eql(u8, args[i], "--rate") and i + 1 < args.len) {
            config.message_rate = try std.fmt.parseInt(u64, args[i + 1], 10);
            i += 1;
        } else if (std.mem.eql(u8, args[i], "--seed") and i + 1 < args.len) {
            config.seed = try std.fmt.parseInt(u64, args[i + 1], 10);
            i += 1;
        } else if (std.mem.eql(u8, args[i], "--benchmark")) {
            config.benchmark_mode = true;
        } else if (std.mem.eql(u8, args[i], "--help")) {
            try printUsage();
            std.process.exit(0);
        }
    }

    const stats = try runSimulation(allocator, config);

    if (config.benchmark_mode) {
        try printBenchmarkResults(stats);
    }
}
