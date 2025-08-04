const std = @import("std");
const lif = @import("lif");
const neuron = @import("neuron.zig");
const print = std.debug.print;

const NetworkConfig = struct {
    neurons: u32 = 100,
    connections: f32 = 0.1, // connection probability
    duration: f32 = 1000.0, // ms
    dt: f32 = 0.1, // ms
    seed: u64 = 42,
    background_current: f32 = 1.5, // nA - background input current
    noise_strength: f32 = 0.5, // nA - noise amplitude
};

const Synapse = struct {
    target: u32,
    weight: f32,
    delay: f32, // ms
};

const NetworkSim = struct {
    neurons: []neuron.Neuron,
    synapses: [][]Synapse,
    spike_times: std.ArrayList(std.ArrayList(f32)),
    input_currents: []f32, // current input for each neuron this timestep
    config: NetworkConfig,
    rng: std.Random.DefaultPrng,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, config: NetworkConfig) !NetworkSim {
        var sim = NetworkSim{
            .neurons = try allocator.alloc(neuron.Neuron, config.neurons),
            .synapses = try allocator.alloc([]Synapse, config.neurons),
            .spike_times = std.ArrayList(std.ArrayList(f32)).init(allocator),
            .input_currents = try allocator.alloc(f32, config.neurons),
            .config = config,
            .rng = std.Random.DefaultPrng.init(config.seed),
            .allocator = allocator,
        };

        const params = lif.Params{};
        for (sim.neurons) |*n| {
            n.* = neuron.createLIF(params);
        }

        for (0..config.neurons) |_| {
            try sim.spike_times.append(std.ArrayList(f32).init(allocator));
        }

        @memset(sim.input_currents, 0.0);

        try sim.generateConnections();

        return sim;
    }

    fn generateConnections(self: *NetworkSim) !void {
        const random = self.rng.random();

        for (0..self.config.neurons) |i| {
            var connections = std.ArrayList(Synapse).init(self.allocator);

            for (0..self.config.neurons) |j| {
                if (i != j and random.float(f32) < self.config.connections) {
                    const weight = 0.8 + random.float(f32) * 0.4; // 0.8-1.2 nA
                    const delay = 1.0 + random.float(f32) * 4.0; // 1-5 ms
                    try connections.append(Synapse{
                        .target = @intCast(j),
                        .weight = weight,
                        .delay = delay,
                    });
                }
            }

            self.synapses[i] = try connections.toOwnedSlice();
        }
    }

    pub fn run(self: *NetworkSim) !void {
        const steps = @as(u32, @intFromFloat(self.config.duration / self.config.dt));
        var delayed_spikes = std.ArrayList(struct { time: f32, target: u32, weight: f32 }).init(self.allocator);
        defer delayed_spikes.deinit();

        print("network simulation:\n", .{});
        print("  neurons: {}\n", .{self.config.neurons});
        print("  connections: {d:.1}%\n", .{self.config.connections * 100});
        print("  duration: {d:.1}ms\n", .{self.config.duration});
        print("  dt: {d:.3}ms\n", .{self.config.dt});
        print("  background current: {d:.1}nA\n", .{self.config.background_current});

        for (0..steps) |step| {
            const t = @as(f32, @floatFromInt(step)) * self.config.dt;

            @memset(self.input_currents, self.config.background_current);

            // process delayed spikes
            var i: usize = 0;
            while (i < delayed_spikes.items.len) {
                if (delayed_spikes.items[i].time <= t) {
                    const spike = delayed_spikes.swapRemove(i);
                    self.input_currents[spike.target] += spike.weight;
                } else {
                    i += 1;
                }
            }

            // update neurons and check for spikes
            for (0..self.config.neurons) |neuron_id| {
                // add background noise
                const noise = (self.rng.random().float(f32) - 0.5) * self.config.noise_strength;
                const total_current = self.input_currents[neuron_id] + noise;

                if (self.neurons[neuron_id].step(total_current, self.config.dt)) {
                    // record spike
                    try self.spike_times.items[neuron_id].append(t);

                    // send spikes to connected neurons
                    for (self.synapses[neuron_id]) |synapse| {
                        try delayed_spikes.append(.{
                            .time = t + synapse.delay,
                            .target = synapse.target,
                            .weight = synapse.weight,
                        });
                    }
                }
            }

            if (step % (steps / 20) == 0) {
                const progress = @as(f32, @floatFromInt(step)) / @as(f32, @floatFromInt(steps)) * 100;
                print("  progress: {d:.0}%\r", .{progress});
            }
        }
        print("  progress: 100%\n", .{});
    }

    pub fn checkHealth(self: *NetworkSim) !void {
        var total_spikes: u32 = 0;
        var active_neurons: u32 = 0;
        var peak_rate: f32 = 0.0;
        var peak_neuron: usize = 0;
        var min_rate: f32 = std.math.floatMax(f32);

        for (0..self.config.neurons) |i| {
            const spike_count = self.spike_times.items[i].items.len;
            total_spikes += @intCast(spike_count);
            if (spike_count > 0) {
                active_neurons += 1;
                const rate = @as(f32, @floatFromInt(spike_count)) / (self.config.duration / 1000.0);
                if (rate > peak_rate) {
                    peak_rate = rate;
                    peak_neuron = i;
                }
                if (rate < min_rate) {
                    min_rate = rate;
                }
            }
        }

        // if no spikes at all, fail.
        if (total_spikes == 0 or active_neurons == 0) {
            print("\n[FAIL] No neurons spiked. Try increasing background current or reducing threshold.\n", .{});
            std.process.exit(1);
        }

        // if <2% of neurons are active, warn/fail.
        const activity = @as(f32, @floatFromInt(active_neurons)) / @as(f32, @floatFromInt(self.config.neurons));
        if (activity < 0.02) {
            print("\n[FAIL] Less than 2% of neurons are active ({}/{}). Network too silent.\n", .{ active_neurons, self.config.neurons });
            std.process.exit(2);
        }

        // if >95% of neurons are silent, warn.
        if (activity < 0.05) {
            print("\n[WARN] Less than 5% of neurons spiked. Network sparsely active.\n", .{});
        }

        // if >10% of neurons spike at >100Hz, warn about overactivity.
        var overactive: u32 = 0;
        for (0..self.config.neurons) |i| {
            const spike_count = self.spike_times.items[i].items.len;
            const rate = @as(f32, @floatFromInt(spike_count)) / (self.config.duration / 1000.0);
            if (rate > 100.0) overactive += 1;
        }
        if (@as(f32, @floatFromInt(overactive)) / @as(f32, @floatFromInt(self.config.neurons)) > 0.1) {
            print("\n[WARN] More than 10% of neurons are firing >100Hz. Network may be unstable.\n", .{});
        }

        // if all neurons spike at the same instant (within 1 dt), warn about synchrony.
        var synchrony: bool = false;
        if (active_neurons > 1) {
            var first_spike_time: ?f32 = null;
            var all_same = true;
            for (0..self.config.neurons) |i| {
                const spikes = self.spike_times.items[i];
                if (spikes.items.len > 0) {
                    if (first_spike_time == null) {
                        first_spike_time = spikes.items[0];
                    } else if (@abs(spikes.items[0] - first_spike_time.?) > self.config.dt + 1e-6) {
                        all_same = false;
                        break;
                    }
                }
            }
            if (all_same and first_spike_time != null) {
                synchrony = true;
                print("\n[WARN] All active neurons spiked at same time ({d:.3} ms). Possible synchrony artifact.\n", .{first_spike_time.?});
            }
        }

        // if all neurons spike at rates within 1Hz of each other, warn about lack of diversity.
        if (peak_rate - min_rate < 1.0 and active_neurons > 1) {
            print("\n[WARN] All spiking neurons have nearly identical rates ({d:.1}Hz). Lacking rate diversity.\n", .{peak_rate});
        }
    }

    pub fn printResults(self: *NetworkSim) void {
        var total_spikes: u32 = 0;
        var active_neurons: u32 = 0;

        print("\nresults:\n", .{});
        for (0..self.config.neurons) |i| {
            const spike_count = self.spike_times.items[i].items.len;
            total_spikes += @intCast(spike_count);
            if (spike_count > 0) active_neurons += 1;
        }

        const rate = @as(f32, @floatFromInt(total_spikes)) / (self.config.duration / 1000.0) / @as(f32, @floatFromInt(self.config.neurons));
        const activity = @as(f32, @floatFromInt(active_neurons)) / @as(f32, @floatFromInt(self.config.neurons));

        print("  total spikes: {}\n", .{total_spikes});
        print("  active neurons: {}/{} ({d:.1}%)\n", .{ active_neurons, self.config.neurons, activity * 100 });
        print("  mean rate: {d:.1}hz\n", .{rate});
        print("  network activity: {d:.1}hz\n", .{rate * @as(f32, @floatFromInt(self.config.neurons))});

        if (active_neurons > 0) {
            print("\ntop 5 active neurons:\n", .{});
            var neuron_rates = std.ArrayList(struct { id: u32, rate: f32 }).init(self.allocator);
            defer neuron_rates.deinit();

            for (0..self.config.neurons) |i| {
                const spike_count = self.spike_times.items[i].items.len;
                if (spike_count > 0) {
                    const neuron_rate = @as(f32, @floatFromInt(spike_count)) / (self.config.duration / 1000.0);
                    neuron_rates.append(.{ .id = @intCast(i), .rate = neuron_rate }) catch continue;
                }
            }

            std.mem.sort(@TypeOf(neuron_rates.items[0]), neuron_rates.items, {}, struct {
                fn lessThan(_: void, a: @TypeOf(neuron_rates.items[0]), b: @TypeOf(neuron_rates.items[0])) bool {
                    return a.rate > b.rate;
                }
            }.lessThan);

            for (neuron_rates.items[0..@min(5, neuron_rates.items.len)]) |nr| {
                print("  neuron {}: {d:.1}hz\n", .{ nr.id, nr.rate });
            }
        } else {
            print("\nno neurons spiked - try increasing background current or reducing threshold\n", .{});
        }
    }

    pub fn deinit(self: *NetworkSim) void {
        for (self.spike_times.items) |*spike_list| {
            spike_list.deinit();
        }
        self.spike_times.deinit();

        for (self.synapses) |synapses| {
            self.allocator.free(synapses);
        }
        self.allocator.free(self.synapses);
        self.allocator.free(self.neurons);
        self.allocator.free(self.input_currents);
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var config = NetworkConfig{};

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--neurons")) {
            i += 1;
            if (i < args.len) config.neurons = try std.fmt.parseInt(u32, args[i], 10);
        } else if (std.mem.eql(u8, args[i], "--connections")) {
            i += 1;
            if (i < args.len) config.connections = try std.fmt.parseFloat(f32, args[i]);
        } else if (std.mem.eql(u8, args[i], "--duration")) {
            i += 1;
            if (i < args.len) config.duration = try std.fmt.parseFloat(f32, args[i]);
        } else if (std.mem.eql(u8, args[i], "--current")) {
            i += 1;
            if (i < args.len) config.background_current = try std.fmt.parseFloat(f32, args[i]);
        } else if (std.mem.eql(u8, args[i], "--seed")) {
            i += 1;
            if (i < args.len) config.seed = try std.fmt.parseInt(u64, args[i], 10);
        } else if (std.mem.eql(u8, args[i], "--help")) {
            print("neural network simulator\n\n", .{});
            print("usage: sim-network [options]\n\n", .{});
            print("options:\n", .{});
            print("  --neurons n       number of neurons (default: 100)\n", .{});
            print("  --connections p   connection probability 0-1 (default: 0.1)\n", .{});
            print("  --duration t      simulation duration in ms (default: 1000)\n", .{});
            print("  --current i       background current in nA (default: 1.5)\n", .{});
            print("  --seed s          random seed (default: 42)\n", .{});
            print("  --help           show this help\n", .{});
            return;
        }
    }

    var sim = try NetworkSim.init(allocator, config);
    defer sim.deinit();
    try sim.run();
    sim.printResults();
    try sim.checkHealth();
}
