// DHT Public API

const std = @import("std");

/// Identifier for a node in the DHT.
/// Generate one randomly or hash something unique.
pub const NodeId = [20]u8;

/// Remote node you can talk to.
/// Fill in id and addr from bootstrap or discovery.
pub const Peer = struct {
    id: NodeId,
    addr: std.net.Address,
};

/// Locates a value in the DHT.
pub const Key = [20]u8;

/// Bytes you want to store in the DHT.
pub const Value = []const u8;

/// Basic config for a DHT node.
/// Fill this out, then call Dht.init().
pub const Config = struct {
    // How many peers per bucket.
    k: usize = 20,

    // Who we are.
    id: NodeId,

    // Where we listen.
    addr: std.net.Address,

    // Who pays for memory
    allocator: std.mem.Allocator,

    // Peers saved from the last session.
    peers_path: []const u8 = ".dht_peers",
};

/// The main handle for the DHT.
/// Call init(), use it, then deinit().
pub const Dht = struct {
    config: Config,
    table: *Table,
    node: *Node,

    /// Set up your node.
    /// Call once. Check for errors.
    pub fn init(cfg: Config) !*Dht {
        const dht_ptr = try cfg.allocator.create(Dht);
        dht_ptr.config = cfg;
        dht_ptr.table = try Table.init(cfg);
        dht_ptr.node = try Node.init(cfg, dht_ptr.table);
        return dht_ptr;
    }

    /// Clean up everything you got from init.
    /// Always call when you're done.
    pub fn deinit(self: *Dht) void {
        self.node.deinit();
        self.table.deinit();
        self.config.allocator.destroy(self);
    }

    /// Save a value in the DHT.
    /// Give it a key and value. Best effort. Not forever.
    pub fn store(self: *Dht, key: Key, value: Value) !void {
        return self.node.store(key, value);
    }

    /// Find a value by key.
    /// Pass the key and a buffer for the answer. Returns bytes written.
    pub fn lookup(self: *Dht, key: Key, buf: []u8) !usize {
        return self.node.lookup(key, buf);
    }

    /// Learn about a new peer.
    /// Call when you meet a peer. No harm if already known.
    pub fn add_peer(self: *Dht, peer: Peer) !void {
        return self.table.add(peer);
    }

    /// List some peers you know.
    /// Pass a buffer, it gets filled up with peers. Returns count.
    pub fn peers(self: *Dht, out: []Peer) usize {
        return self.table.peers(out);
    }
};

// Routing table logic.
const Table = @import("table.zig").Table;

// DHT protocol logic.
const Node = @import("node.zig").Node;
