const std = @import("std");
const dht = @import("dht.zig");

pub const Table = struct {
    k: usize,
    id: dht.NodeId,
    allocator: std.mem.Allocator,
    peer_list: std.ArrayList(dht.Peer),
    peers_path: []const u8,

    pub fn init(cfg: dht.Config) !*Table {
        const self = try cfg.allocator.create(Table);
        self.* = Table{
            .k = cfg.k,
            .id = cfg.id,
            .allocator = cfg.allocator,
            .peer_list = std.ArrayList(dht.Peer).init(cfg.allocator),
            .peers_path = cfg.peers_path,
        };
        self.loadPeers() catch {};
        return self;
    }

    pub fn deinit(self: *Table) void {
        self.savePeers() catch {};
        self.peer_list.deinit();
        self.allocator.destroy(self);
    }

    pub fn add(self: *Table, peer: dht.Peer) !void {
        for (self.peer_list.items) |*p| {
            if (std.mem.eql(u8, &p.id, &peer.id)) return;
        }
        if (self.peer_list.items.len >= self.k) {
            _ = self.peer_list.orderedRemove(0); // Remove oldest
        }
        try self.peer_list.append(peer);
    }

    pub fn peers(self: *Table, out: []dht.Peer) usize {
        const n = @min(self.peer_list.items.len, out.len);
        @memcpy(out[0..n], self.peer_list.items[0..n]);
        return n;
    }

    fn loadPeers(self: *Table) !void {
        const file = std.fs.cwd().openFile(self.peers_path, .{}) catch return;
        defer file.close();
        var buf: [1024]u8 = undefined;
        const n = try file.readAll(&buf);
        var i: usize = 0;

        while (i + 38 <= n) : (i += 38) {
            var id: dht.NodeId = undefined;
            @memcpy(&id, buf[i..][0..20]);

            var addr_stream = std.io.fixedBufferStream(buf[i + 20 ..][0..18]);
            const addr = readAddrFromStream(addr_stream.reader()) catch continue;

            try self.peer_list.append(.{ .id = id, .addr = addr });
        }
    }

    pub fn savePeers(self: *Table) !void {
        const file = try std.fs.cwd().createFile(self.peers_path, .{ .truncate = true });
        defer file.close();

        for (self.peer_list.items) |peer| {
            try file.writeAll(&peer.id);

            var addr_buf: [18]u8 = undefined;
            var addr_stream = std.io.fixedBufferStream(&addr_buf);
            try writeAddrToStream(addr_stream.writer(), peer.addr);
            try file.writeAll(&addr_buf);
        }
    }

    fn writeAddrToStream(w: anytype, addr: std.net.Address) !void {
        if (addr.any.family == std.posix.AF.INET) {
            // IPv4
            try w.writeByte(4);
            try w.writeAll(std.mem.asBytes(&addr.in.sa.addr));
            try w.writeInt(u16, std.mem.nativeToBig(u16, addr.in.sa.port), .little);
            try w.writeAll(&[_]u8{0} ** 11); // Pad to 17 bytes
        } else if (addr.any.family == std.posix.AF.INET6) {
            // IPv6
            try w.writeByte(6);
            try w.writeAll(addr.in6.sa.addr[0..15]);
            try w.writeInt(u16, std.mem.nativeToBig(u16, addr.in6.sa.port), .little);
        } else {
            // Unknown/Unix socket
            try w.writeByte(1);
            try w.writeAll(&[_]u8{0} ** 17);
        }
    }

    fn readAddrFromStream(r: anytype) !std.net.Address {
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
};
