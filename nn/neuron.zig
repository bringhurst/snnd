const std = @import("std");
const lif = @import("lif");

pub const Neuron = union(enum) {
    lif: lif.LIF,
    // izhikevich: @import("izhikevich").Izhikevich,
    // hodgkin_huxley: @import("hh").HodgkinHuxley,

    pub fn step(self: *Neuron, input_current: f64, dt: f64) bool {
        return switch (self.*) {
            .lif => |*lif_neuron| lif_neuron.step(input_current, dt),
        };
    }

    pub fn reset(self: *Neuron) void {
        switch (self.*) {
            .lif => |*lif_neuron| lif_neuron.reset(),
        }
    }

    pub fn voltage(self: *const Neuron) f64 {
        return switch (self.*) {
            .lif => |*lif_neuron| lif_neuron.voltage(),
        };
    }

    pub fn spiked(self: *const Neuron) bool {
        return switch (self.*) {
            .lif => |*lif_neuron| lif_neuron.spiked(),
        };
    }
};

pub fn createLIF(params: lif.Params) Neuron {
    return Neuron{ .lif = lif.LIF.init(params) };
}
