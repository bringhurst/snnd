const std = @import("std");
const dht = @import("dht.zig");
const table_mod = @import("table.zig");
const node_mod = @import("node.zig");
const msg = @import("msg.zig");

test "dht basic initialization and cleanup" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const id: dht.NodeId = .{0} ** 20;
    const cfg = dht.Config{
        .k = 8,
        .id = id,
        .addr = try std.net.Address.parseIp4("127.0.0.1", 8000),
        .allocator = allocator,
        .peers_path = "test_dht_peers",
    };

    const dht_node = try dht.Dht.init(cfg);
    defer dht_node.deinit();

    // Test that the node was initialized correctly
    try std.testing.expect(std.mem.eql(u8, &dht_node.config.id, &id));
    try std.testing.expect(dht_node.config.k == 8);

    // Cleanup test file
    std.fs.cwd().deleteFile("test_dht_peers") catch {};
}

test "dht store and lookup" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const id: dht.NodeId = .{1} ** 20;
    const cfg = dht.Config{
        .k = 8,
        .id = id,
        .addr = try std.net.Address.parseIp4("127.0.0.1", 8001),
        .allocator = allocator,
        .peers_path = "test_store_peers",
    };

    const dht_node = try dht.Dht.init(cfg);
    defer dht_node.deinit();

    const key: dht.Key = .{2} ** 20;
    const value = "test_value";

    // Store a value
    try dht_node.store(key, value);

    // Look it up
    var buf: [256]u8 = undefined;
    const n = try dht_node.lookup(key, &buf);
    try std.testing.expect(n == value.len);
    try std.testing.expect(std.mem.eql(u8, buf[0..n], value));

    // Test lookup of non-existent key
    const missing_key: dht.Key = .{3} ** 20;
    const missing_n = try dht_node.lookup(missing_key, &buf);
    try std.testing.expect(missing_n == 0);

    // Cleanup test file
    std.fs.cwd().deleteFile("test_store_peers") catch {};
}

test "dht peer management" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const id: dht.NodeId = .{4} ** 20;
    const cfg = dht.Config{
        .k = 4,
        .id = id,
        .addr = try std.net.Address.parseIp4("127.0.0.1", 8002),
        .allocator = allocator,
        .peers_path = "test_peer_mgmt",
    };

    const dht_node = try dht.Dht.init(cfg);
    defer dht_node.deinit();

    // Add some peers
    const peer1 = dht.Peer{
        .id = .{5} ** 20,
        .addr = try std.net.Address.parseIp4("127.0.0.1", 8003),
    };
    const peer2 = dht.Peer{
        .id = .{6} ** 20,
        .addr = try std.net.Address.parseIp4("127.0.0.1", 8004),
    };

    try dht_node.add_peer(peer1);
    try dht_node.add_peer(peer2);

    // Get peers back
    var peer_buf: [10]dht.Peer = undefined;
    const peer_count = dht_node.peers(&peer_buf);
    try std.testing.expect(peer_count == 2);

    // Check that peers were added correctly
    var found_peer1 = false;
    var found_peer2 = false;
    for (peer_buf[0..peer_count]) |peer| {
        if (std.mem.eql(u8, &peer.id, &peer1.id)) found_peer1 = true;
        if (std.mem.eql(u8, &peer.id, &peer2.id)) found_peer2 = true;
    }
    try std.testing.expect(found_peer1);
    try std.testing.expect(found_peer2);

    // Cleanup test file
    std.fs.cwd().deleteFile("test_peer_mgmt") catch {};
}

test "table peer persistence across sessions" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const id: dht.NodeId = .{0} ** 20;
    const path = "test_persistence_peers";

    // Write session
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

    // Read session
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

        const expected_id: dht.NodeId = .{1} ** 20;
        try std.testing.expect(std.mem.eql(u8, &out[0].id, &expected_id));
    }

    // Cleanup file
    std.fs.cwd().deleteFile(path) catch {};
}

test "table k-bucket limit enforcement" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const id: dht.NodeId = .{7} ** 20;
    const cfg = dht.Config{
        .k = 3, // Small k for easy testing
        .id = id,
        .addr = try std.net.Address.parseIp4("127.0.0.1", 8005),
        .allocator = allocator,
        .peers_path = "test_k_limit",
    };

    const tab = try table_mod.Table.init(cfg);
    defer tab.deinit();

    // Add more peers than k allows
    for (0..5) |i| {
        var peer_id: dht.NodeId = .{0} ** 20;
        peer_id[0] = @intCast(i + 10);
        const peer = dht.Peer{
            .id = peer_id,
            .addr = try std.net.Address.parseIp4("127.0.0.1", @intCast(8100 + i)),
        };
        try tab.add(peer);
    }

    // Should only have k peers
    var peer_buf: [10]dht.Peer = undefined;
    const peer_count = tab.peers(&peer_buf);
    try std.testing.expect(peer_count == 3); // Should equal k

    // Cleanup test file
    std.fs.cwd().deleteFile("test_k_limit") catch {};
}

test "msg encode/decode roundtrip ping" {
    const allocator = std.testing.allocator;
    const id: dht.NodeId = .{8} ** 20;
    const original = msg.Msg{ .Ping = .{ .from = id } };

    var buf: [512]u8 = undefined;
    const n = try msg.encode(original, &buf);
    const parsed = try msg.decode(buf[0..n], allocator);

    switch (parsed) {
        .Ping => |ping| {
            try std.testing.expect(std.mem.eql(u8, &ping.from, &id));
        },
        else => try std.testing.expect(false),
    }
}

test "msg encode/decode roundtrip store" {
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

test "msg encode/decode roundtrip find node" {
    const allocator = std.testing.allocator;
    const from_id: dht.NodeId = .{10} ** 20;
    const target_id: dht.NodeId = .{11} ** 20;
    const original = msg.Msg{
        .FindNode = .{ .from = from_id, .target = target_id },
    };

    var buf: [512]u8 = undefined;
    const n = try msg.encode(original, &buf);
    const parsed = try msg.decode(buf[0..n], allocator);

    switch (parsed) {
        .FindNode => |find_node| {
            try std.testing.expect(std.mem.eql(u8, &find_node.from, &from_id));
            try std.testing.expect(std.mem.eql(u8, &find_node.target, &target_id));
        },
        else => try std.testing.expect(false),
    }
}

test "node store and lookup functionality" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const cfg = dht.Config{
        .k = 8,
        .id = .{12} ** 20,
        .addr = try std.net.Address.parseIp4("127.0.0.1", 8006),
        .allocator = allocator,
        .peers_path = "test_node_store",
    };

    const tab = try table_mod.Table.init(cfg);
    defer tab.deinit();

    const node = try node_mod.Node.init(cfg, tab);
    defer node.deinit();

    const key: dht.Key = .{13} ** 20;
    const value = "node_test_value";

    // Store and retrieve
    try node.store(key, value);

    var buf: [256]u8 = undefined;
    const n = try node.lookup(key, &buf);
    try std.testing.expect(n == value.len);
    try std.testing.expect(std.mem.eql(u8, buf[0..n], value));

    // Test multiple values
    const key2: dht.Key = .{14} ** 20;
    const value2 = "second_value";
    try node.store(key2, value2);

    const n2 = try node.lookup(key2, &buf);
    try std.testing.expect(n2 == value2.len);
    try std.testing.expect(std.mem.eql(u8, buf[0..n2], value2));

    // Original value should still be there
    const n1_again = try node.lookup(key, &buf);
    try std.testing.expect(n1_again == value.len);
    try std.testing.expect(std.mem.eql(u8, buf[0..n1_again], value));

    // Cleanup test file
    std.fs.cwd().deleteFile("test_node_store") catch {};
}
