const std = @import("std");
const NodeId = @import("dht.zig").NodeId;
const Key = @import("dht.zig").Key;
const Value = @import("dht.zig").Value;
const Peer = @import("dht.zig").Peer;

pub const Msg = union(enum) {
    Ping: struct { from: NodeId },
    Pong: struct { from: NodeId },
    FindNode: struct { from: NodeId, target: NodeId },
    FoundNodes: struct { from: NodeId, nodes: []Peer },
    Store: struct { from: NodeId, key: Key, value: Value },
    StoreOk: struct { from: NodeId, key: Key },
    FindValue: struct { from: NodeId, key: Key },
    Value: struct { from: NodeId, key: Key, value: Value },
    NotFound: struct { from: NodeId, key: Key },
};

pub fn encode(msg: Msg, buf: []u8) !usize {
    var stream = std.io.fixedBufferStream(buf);
    const w = stream.writer();
    try w.writeByte(@intFromEnum(msg));
    switch (msg) {
        .Ping => |m| try w.writeAll(&m.from),
        .Pong => |m| try w.writeAll(&m.from),
        .FindNode => |m| {
            try w.writeAll(&m.from);
            try w.writeAll(&m.target);
        },
        .FoundNodes => |m| {
            try w.writeAll(&m.from);
            try w.writeInt(u16, @intCast(m.nodes.len), .little);
            for (m.nodes) |peer| {
                try w.writeAll(&peer.id);
                try writeAddr(w, peer.addr);
            }
        },
        .Store => |m| {
            try w.writeAll(&m.from);
            try w.writeAll(&m.key);
            try w.writeInt(u16, @intCast(m.value.len), .little);
            try w.writeAll(m.value);
        },
        .StoreOk => |m| {
            try w.writeAll(&m.from);
            try w.writeAll(&m.key);
        },
        .FindValue => |m| {
            try w.writeAll(&m.from);
            try w.writeAll(&m.key);
        },
        .Value => |m| {
            try w.writeAll(&m.from);
            try w.writeAll(&m.key);
            try w.writeInt(u16, @intCast(m.value.len), .little);
            try w.writeAll(m.value);
        },
        .NotFound => |m| {
            try w.writeAll(&m.from);
            try w.writeAll(&m.key);
        },
    }
    return stream.pos;
}

pub fn decode(buf: []const u8, allocator: std.mem.Allocator) !Msg {
    var stream = std.io.fixedBufferStream(buf);
    const r = stream.reader();
    const tag = try r.readByte();

    const msg_tag = std.meta.intToEnum(std.meta.Tag(Msg), tag) catch {
        return error.InvalidMsgTag;
    };

    return switch (msg_tag) {
        .Ping => Msg{ .Ping = .{ .from = try readId(r) } },
        .Pong => Msg{ .Pong = .{ .from = try readId(r) } },
        .FindNode => Msg{ .FindNode = .{ .from = try readId(r), .target = try readId(r) } },
        .FoundNodes => blk: {
            const from = try readId(r);
            const n = try r.readInt(u16, .little);
            const nodes = try allocator.alloc(Peer, n);
            for (nodes) |*peer| {
                peer.id = try readId(r);
                peer.addr = try readAddr(r);
            }
            break :blk Msg{ .FoundNodes = .{ .from = from, .nodes = nodes } };
        },
        .Store => blk: {
            const from = try readId(r);
            const key = try readKey(r);
            const vlen = try r.readInt(u16, .little);
            const value = try allocator.alloc(u8, vlen);
            try r.readNoEof(value);
            break :blk Msg{ .Store = .{ .from = from, .key = key, .value = value } };
        },
        .StoreOk => Msg{ .StoreOk = .{ .from = try readId(r), .key = try readKey(r) } },
        .FindValue => Msg{ .FindValue = .{ .from = try readId(r), .key = try readKey(r) } },
        .Value => blk: {
            const from = try readId(r);
            const key = try readKey(r);
            const vlen = try r.readInt(u16, .little);
            const value = try allocator.alloc(u8, vlen);
            try r.readNoEof(value);
            break :blk Msg{ .Value = .{ .from = from, .key = key, .value = value } };
        },
        .NotFound => Msg{ .NotFound = .{ .from = try readId(r), .key = try readKey(r) } },
    };
}

fn readId(r: anytype) !NodeId {
    var id: NodeId = undefined;
    try r.readNoEof(&id);
    return id;
}

fn readKey(r: anytype) !Key {
    var key: Key = undefined;
    try r.readNoEof(&key);
    return key;
}

fn writeAddr(w: anytype, addr: std.net.Address) !void {
    if (addr.any.family == std.posix.AF.INET) {
        // IPv4
        try w.writeByte(4);
        try w.writeAll(std.mem.asBytes(&addr.in.sa.addr));
        try w.writeInt(u16, std.mem.nativeToBig(u16, addr.in.sa.port), .little);
        try w.writeAll(&[_]u8{0} ** 11); // Pad to 17 bytes
    } else if (addr.any.family == std.posix.AF.INET6) {
        // IPv6
        try w.writeByte(6);
        try w.writeAll(addr.in6.sa.addr[0..15]); // Use only 15 bytes to fit format
        try w.writeInt(u16, std.mem.nativeToBig(u16, addr.in6.sa.port), .little);
    } else {
        // Unknown/Unix socket - use family 1
        try w.writeByte(1);
        try w.writeAll(&[_]u8{0} ** 17);
    }
}

fn readAddr(r: anytype) !std.net.Address {
    const family = try r.readByte();
    var buf: [17]u8 = undefined;
    try r.readNoEof(&buf);

    switch (family) {
        4 => { // IPv4
            const addr_bytes = buf[0..4].*;
            const port = std.mem.readInt(u16, buf[4..6], .little);
            return std.net.Address.initIp4(addr_bytes, std.mem.bigToNative(u16, port));
        },
        6 => { // IPv6
            var ipv6_bytes: [16]u8 = undefined;
            @memcpy(ipv6_bytes[0..15], buf[0..15]);
            ipv6_bytes[15] = 0;
            const port = std.mem.readInt(u16, buf[15..17], .little);
            return std.net.Address.initIp6(ipv6_bytes, std.mem.bigToNative(u16, port), 0, 0);
        },
        else => return error.UnsupportedAddressFamily,
    }
}
