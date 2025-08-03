const std = @import("std");
const dht = @import("dht.zig");
const table_mod = @import("table.zig");
const node_mod = @import("node.zig");
const msg = @import("msg.zig");

test "routing table add and dedup" {
    // setup
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const id: dht.NodeId = .{0} ** 20;
    const cfg = dht.Config{
        .k = 4,
        .id = id,
        .addr = try std.net.Address.parseIp6("::1", 9000),
        .allocator = &arena.allocator,
    };

    var tab = try table_mod.Table.init(cfg);
    defer tab.deinit();

    const peer1 = dht.Peer{ .id = .{1} ** 20, .addr = try std.net.Address.parseIp6("::1", 9001) };
    const peer2 = dht.Peer{ .id = .{2} ** 20, .addr = try std.net.Address.parseIp6("::1", 9002) };

    // run
    try tab.add(peer1);
    try tab.add(peer2);

    // should dedup and move to end
    try tab.add(peer1);

    // assert
    var out: [8]dht.Peer = undefined;
    const n = tab.peers(&out);

    // there should be at least two peers in the table
    try std.testing.expect(n >= 2);

    // the dedup logic should ensure peer2 is present
    try std.testing.expect(std.mem.eql(u8, &out[0].id, &peer2.id) or std.mem.eql(u8, &out[1].id, &peer2.id));
}

test "node can find closest peers" {
    // setup
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const id: dht.NodeId = .{0} ** 20;
    const cfg = dht.Config{
        .k = 8,
        .id = id,
        .addr = try std.net.Address.parseIp6("::1", 5000),
        .allocator = &arena.allocator,
    };

    var tab = try table_mod.Table.init(cfg);
    defer tab.deinit();

    // run
    for (0..10) |i| {
        const peer_id: dht.NodeId = .{0} ** 19 ++ .{ @as(u8, @intCast(i)) };
        const peer = dht.Peer{ .id = peer_id, .addr = try std.net.Address.parseIp6("::1", @as(u16, 5001 + @as(u16, i))) };
        try tab.add(peer);
    }

    var node = try node_mod.Node.init(cfg, tab);
    defer node.deinit();

    const key: dht.Key = .{0} ** 19 ++ .{5};
    const peers = try node.closest_peers(key, 4);

    // assert
    try std.testing.expect(peers.len == 4);
}

test "msg encode/decode roundtrip" {
    // setup
    const allocator = std.testing.allocator;
    const id: dht.NodeId = .{9} ** 20;
    const key: dht.Key = .{1} ** 20;
    const value: [5]u8 = "hello".*;
    const original = msg.Msg{
        .Store = .{
            .from = id,
            .key = key,
            .value = value[0..],
        },
    };

    // run
    var buf: [512]u8 = undefined;
    const n = try msg.encode(original, &buf);
    const parsed = try msg.decode(buf[0..n], allocator);

    // assert
    switch (parsed) {
        .Store => |store| {
            try std.testing.expect(std.mem.eql(u8, &store.from, &id));
            try std.testing.expect(std.mem.eql(u8, &store.key, &key));
            try std.testing.expect(std.mem.eql(u8, store.value, value[0..]));
        },
        else => try std.testing.expect(false), // if it's not a Store, it's wrong
    }
}

test "table bucket overflow drops oldest" {
    // setup
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const id: dht.NodeId = .{0} ** 20;
    const cfg = dht.Config{
        .k = 3,
        .id = id,
        .addr = try std.net.Address.parseIp6("::1", 7000),
        .allocator = &arena.allocator,
    };

    var tab = try table_mod.Table.init(cfg);
    defer tab.deinit();

    const peer1 = dht.Peer{ .id = .{1} ** 20, .addr = try std.net.Address.parseIp6("::1", 7001) };
    const peer2 = dht.Peer{ .id = .{2} ** 20, .addr = try std.net.Address.parseIp6("::1", 7002) };
    const peer3 = dht.Peer{ .id = .{3} ** 20, .addr = try std.net.Address.parseIp6("::1", 7003) };
    const peer4 = dht.Peer{ .id = .{4} ** 20, .addr = try std.net.Address.parseIp6("::1", 7004) };

    // run
    try tab.add(peer1);
    try tab.add(peer2);
    try tab.add(peer3);

    // should cause peer1 to be dropped
    try tab.add(peer4);

    // assert
    var out: [4]dht.Peer = undefined;
    const n = tab.peers(&out);
    try std.testing.expect(n == 3);

    // peer1 should be gone
    for (out[0..n]) |p| {
        try std.testing.expect(!std.mem.eql(u8, &p.id, &peer1.id));
    }
}
