const std = @import("std");

pub const Neuron = union(enum) {
    lif: @import("lif").LIF,
    // izhikevich: @import("izhikevich").Izhikevich,
    // hodgkin_huxley: @import("hh").HodgkinHuxley,

    pub fn step(self: *Neuron, input_current: f64, dt: f64) bool {
        return switch (self.*) {
            .lif => |*lif| lif.step(input_current, dt),
        };
    }

    pub fn reset(self: *Neuron) void {
        switch (self.*) {
            .lif => |*lif| lif.reset(),
        }
    }

    pub fn voltage(self: *const Neuron) f64 {
        return switch (self.*) {
            .lif => |*lif| lif.voltage(),
        };
    }

    pub fn spiked(self: *const Neuron) bool {
        return switch (self.*) {
            .lif => |*lif| lif.spiked(),
        };
    }
};

pub fn createLIF(params: @import("lif").Params) Neuron {
    return Neuron{ .lif = @import("lif").LIF.init(params) };
}
