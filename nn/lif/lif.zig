// Leaky Integrate-and-Fire neuron model

const std = @import("std");

pub const Params = struct {
    tau_m: f64 = 20.0, // membrane time constant (ms)
    v_rest: f64 = -70.0, // resting potential (mV)
    v_thresh: f64 = -55.0, // spike threshold (mV)
    v_reset: f64 = -75.0, // reset potential (mV)
    r_m: f64 = 10.0, // membrane resistance (MΩ)
    t_refrac: f64 = 2.0, // refractory period (ms)
};

pub const LIF = struct {
    params: Params,
    v_mem: f64, // membrane voltage (mV)
    t_last_spike: f64, // time of last spike (ms)
    time: f64, // current simulation time (ms)
    spike_flag: bool, // did neuron spike this timestep?

    pub fn init(params: Params) LIF {
        return LIF{
            .params = params,
            .v_mem = params.v_rest,
            .t_last_spike = -1000.0, // way in the past
            .time = 0.0,
            .spike_flag = false,
        };
    }

    /// Step the neuron forward by dt milliseconds
    /// Returns true if neuron spiked this timestep
    pub fn step(self: *LIF, i_input: f64, dt: f64) bool {
        self.time += dt;
        self.spike_flag = false;

        // Check if in refractory period
        if (self.time - self.t_last_spike < self.params.t_refrac) {
            self.v_mem = self.params.v_reset;
            return false;
        }

        // Integrate membrane equation: tau_m * dV/dt = -(V - V_rest) + R_m * I
        const dv_dt = (-(self.v_mem - self.params.v_rest) + self.params.r_m * i_input) / self.params.tau_m;
        self.v_mem += dv_dt * dt;

        // Check for spike
        if (self.v_mem >= self.params.v_thresh) {
            self.spike_flag = true;
            self.t_last_spike = self.time;
            self.v_mem = self.params.v_reset;
            return true;
        }

        return false;
    }

    pub fn reset(self: *LIF) void {
        self.v_mem = self.params.v_rest;
        self.t_last_spike = -1000.0;
        self.time = 0.0;
        self.spike_flag = false;
    }

    pub fn voltage(self: *const LIF) f64 {
        return self.v_mem;
    }

    pub fn spiked(self: *const LIF) bool {
        return self.spike_flag;
    }

    /// Check if neuron is in refractory period
    pub fn inRefractory(self: *const LIF) bool {
        return self.time - self.t_last_spike < self.params.t_refrac;
    }
};
