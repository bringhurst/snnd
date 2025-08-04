const std = @import("std");
const dht = @import("dht.zig");
const table_mod = @import("table.zig");

pub const Node = struct {
    table: *table_mod.Table,
    store_map: std.AutoHashMap(dht.Key, dht.Value),
    allocator: std.mem.Allocator,

    pub fn init(cfg: dht.Config, table: *table_mod.Table) !*Node {
        const node = try cfg.allocator.create(Node);
        node.* = Node{
            .table = table,
            .store_map = std.AutoHashMap(dht.Key, dht.Value).init(cfg.allocator),
            .allocator = cfg.allocator,
        };
        return node;
    }

    pub fn deinit(self: *Node) void {
        self.store_map.deinit();
        self.allocator.destroy(self);
    }

    pub fn store(self: *Node, key: dht.Key, value: dht.Value) !void {
        try self.store_map.put(key, value);
    }

    pub fn lookup(self: *Node, key: dht.Key, buf: []u8) !usize {
        if (self.store_map.get(key)) |v| {
            const n = @min(v.len, buf.len);
            @memcpy(buf[0..n], v[0..n]);
            return n;
        }
        return 0;
    }
};
