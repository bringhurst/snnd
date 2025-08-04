const std = @import("std");
const dht = @import("dht.zig");
const msg = @import("msg.zig");

pub const SimPeer = struct {
    dht: *dht.Dht,
    inbox: std.ArrayList(msg.Msg),

    pub fn init(allocator: std.mem.Allocator, cfg: dht.Config) !*SimPeer {
        const self = try allocator.create(SimPeer);
        self.* = SimPeer{
            .dht = try dht.Dht.init(cfg),
            .inbox = std.ArrayList(msg.Msg).init(allocator),
        };
        return self;
    }

    pub fn deinit(self: *SimPeer, allocator: std.mem.Allocator) void {
        self.dht.deinit();
        self.inbox.deinit();
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
