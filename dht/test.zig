const std = @import("std");
const dht = @import("dht.zig");
const table_mod = @import("table.zig");
const node_mod = @import("node.zig");
const sim = @import("sim.zig");
const msg = @import("msg.zig");

test "peer persistence across sessions" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const id: dht.NodeId = .{0} ** 20;
    const path = "test_peers";
    // Write
    {
        const cfg = dht.Config{
            .k = 4,
            .id = id,
            .addr = try std.net.Address.parseIp6("::1", 9000),
            .allocator = allocator,
            .peers_path = path,
        };
        const tab = try table_mod.Table.init(cfg);
        defer tab.deinit();

        const peer1 = dht.Peer{ .id = .{1} ** 20, .addr = try std.net.Address.parseIp6("::1", 9001) };
        try tab.add(peer1);
        try tab.savePeers();
    }
    // Reload
    {
        const cfg = dht.Config{
            .k = 4,
            .id = id,
            .addr = try std.net.Address.parseIp6("::1", 9000),
            .allocator = allocator,
            .peers_path = path,
        };
        const tab = try table_mod.Table.init(cfg);
        defer tab.deinit();
        var out: [8]dht.Peer = undefined;
        const n = tab.peers(&out);
        try std.testing.expect(n == 1);

        // Create expected peer ID for comparison
        const expected_id: dht.NodeId = .{1} ** 20;
        try std.testing.expect(std.mem.eql(u8, &out[0].id, &expected_id));
    }
    // Cleanup file
    std.fs.cwd().deleteFile(path) catch {};
}

test "msg encode/decode roundtrip" {
    const allocator = std.testing.allocator;
    const id: dht.NodeId = .{9} ** 20;
    const key: dht.Key = .{1} ** 20;
    const value: [5]u8 = "hello".*;
    const original = msg.Msg{
        .Store = .{ .from = id, .key = key, .value = value[0..] },
    };

    var buf: [512]u8 = undefined;
    const n = try msg.encode(original, &buf);
    const parsed = try msg.decode(buf[0..n], allocator);
    defer allocator.free(parsed.Store.value);

    switch (parsed) {
        .Store => |store| {
            try std.testing.expect(std.mem.eql(u8, &store.from, &id));
            try std.testing.expect(std.mem.eql(u8, &store.key, &key));
            try std.testing.expect(std.mem.eql(u8, store.value, value[0..]));
        },
        else => try std.testing.expect(false),
    }
}

test "simulator deterministic delivery" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const id: dht.NodeId = .{0} ** 20;
    const cfg = dht.Config{
        .k = 4,
        .id = id,
        .addr = try std.net.Address.parseIp6("::1", 9000),
        .allocator = allocator,
    };

    var net = sim.SimNet.init(allocator);
    defer net.deinit(allocator);

    const peer1 = try sim.SimPeer.init(allocator, cfg);
    const peer2 = try sim.SimPeer.init(allocator, cfg);

    try net.add_peer(peer1);
    try net.add_peer(peer2);

    const test_msg = msg.Msg{ .Ping = .{ .from = id } };
    try sim.SimPeer.send(peer1, peer2, test_msg);

    try std.testing.expect(peer2.has_messages());
    try net.step_all();
    try std.testing.expect(!peer2.has_messages());
}
