const std = @import("std");
const lif = @import("lif");
const neuron = @import("neuron");

pub const NetworkConfig = struct {
    neurons: u32 = 100,
    connections: f32 = 0.1, // connection probability
    duration: f32 = 1000.0, // ms
    dt: f32 = 0.1, // ms
    seed: u64 = 42,
    background_current: f32 = 1.5, // nA - background input current
    noise_strength: f32 = 0.5, // nA - noise amplitude
    benchmark_mode: bool = false,
};

pub const Synapse = struct {
    target: u32,
    weight: f32,
    delay: f32, // ms
};

pub const BenchmarkResult = struct {
    name: []const u8,
    unit: []const u8,
    value: f64,
};

pub const DelayedSpike = struct {
    time: f32,
    target: u32,
    weight: f32,
};

pub const Network = struct {
    neurons: []neuron.Neuron,
    synapses: [][]Synapse,
    spike_times: std.ArrayList(std.ArrayList(f32)),
    input_currents: []f32,
    config: NetworkConfig,
    rng: std.Random.DefaultPrng,
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, config: NetworkConfig) !Self {
        var network = Self{
            .neurons = try allocator.alloc(neuron.Neuron, config.neurons),
            .synapses = try allocator.alloc([]Synapse, config.neurons),
            .spike_times = std.ArrayList(std.ArrayList(f32)).init(allocator),
            .input_currents = try allocator.alloc(f32, config.neurons),
            .config = config,
            .rng = std.Random.DefaultPrng.init(config.seed),
            .allocator = allocator,
        };

        const params = lif.Params{};
        for (network.neurons) |*n| {
            n.* = neuron.createLIF(params);
        }

        for (0..config.neurons) |_| {
            try network.spike_times.append(std.ArrayList(f32).init(allocator));
        }

        @memset(network.input_currents, 0.0);
        try network.generateConnections();

        return network;
    }

    fn generateConnections(self: *Self) !void {
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

    pub fn step(self: *Self, time: f32, delayed_spikes: *std.ArrayList(DelayedSpike)) !u32 {
        @memset(self.input_currents, self.config.background_current);

        // Process delayed spikes
        var spike_idx: usize = 0;
        while (spike_idx < delayed_spikes.items.len) {
            if (delayed_spikes.items[spike_idx].time <= time) {
                const spike = delayed_spikes.swapRemove(spike_idx);
                self.input_currents[spike.target] += spike.weight;
            } else {
                spike_idx += 1;
            }
        }

        var new_spikes: u32 = 0;

        // Update neurons and detect spikes
        for (0..self.config.neurons) |neuron_id| {
            // Add background noise
            const noise = (self.rng.random().float(f32) - 0.5) * self.config.noise_strength;
            const total_current = self.input_currents[neuron_id] + noise;

            if (self.neurons[neuron_id].step(total_current, self.config.dt)) {
                new_spikes += 1;

                // Record spike
                try self.spike_times.items[neuron_id].append(time);

                // Schedule outgoing spikes
                for (self.synapses[neuron_id]) |synapse| {
                    try delayed_spikes.append(.{
                        .time = time + synapse.delay,
                        .target = synapse.target,
                        .weight = synapse.weight,
                    });
                }
            }
        }

        return new_spikes;
    }

    pub fn getStatistics(self: *const Self) struct {
        total_spikes: u32,
        active_neurons: u32,
        mean_rate: f32,
        activity_ratio: f32,
        total_synapses: u32,
    } {
        var total_spikes: u32 = 0;
        var active_neurons: u32 = 0;
        var total_synapses: u32 = 0;

        for (0..self.config.neurons) |i| {
            const spike_count = self.spike_times.items[i].items.len;
            total_spikes += @intCast(spike_count);
            if (spike_count > 0) active_neurons += 1;
            total_synapses += @intCast(self.synapses[i].len);
        }

        const mean_rate = @as(f32, @floatFromInt(total_spikes)) / (self.config.duration / 1000.0) / @as(f32, @floatFromInt(self.config.neurons));
        const activity_ratio = @as(f32, @floatFromInt(active_neurons)) / @as(f32, @floatFromInt(self.config.neurons));

        return .{
            .total_spikes = total_spikes,
            .active_neurons = active_neurons,
            .mean_rate = mean_rate,
            .activity_ratio = activity_ratio,
            .total_synapses = total_synapses,
        };
    }

    pub fn checkHealth(self: *const Self) !void {
        const stats = self.getStatistics();
        const print = std.debug.print;

        // If no spikes at all, fail
        if (stats.total_spikes == 0 or stats.active_neurons == 0) {
            if (!self.config.benchmark_mode) {
                print("\n[FAIL] No neurons spiked. Try increasing background current or reducing threshold.\n", .{});
            }
            std.process.exit(1);
        }

        // If <2% of neurons are active, warn/fail
        if (stats.activity_ratio < 0.02) {
            if (!self.config.benchmark_mode) {
                print("\n[FAIL] Less than 2% of neurons are active ({}/{}). Network too silent.\n", .{ stats.active_neurons, self.config.neurons });
            }
            std.process.exit(2);
        }

        // Additional health checks in non-benchmark mode
        if (!self.config.benchmark_mode) {
            if (stats.activity_ratio < 0.05) {
                print("\n[WARN] Less than 5% of neurons spiked. Network sparsely active.\n", .{});
            }

            // Check for overactivity
            var overactive: u32 = 0;
            for (0..self.config.neurons) |i| {
                const spike_count = self.spike_times.items[i].items.len;
                const rate = @as(f32, @floatFromInt(spike_count)) / (self.config.duration / 1000.0);
                if (rate > 100.0) overactive += 1;
            }
            if (@as(f32, @floatFromInt(overactive)) / @as(f32, @floatFromInt(self.config.neurons)) > 0.1) {
                print("\n[WARN] More than 10% of neurons are firing >100Hz. Network may be unstable.\n", .{});
            }

            // Check for synchrony
            if (stats.active_neurons > 1) {
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
                    print("\n[WARN] All active neurons spiked at same time ({d:.3} ms). Possible synchrony artifact.\n", .{first_spike_time.?});
                }
            }
        }
    }

    pub fn printResults(self: *const Self) void {
        const stats = self.getStatistics();
        const print = std.debug.print;

        if (self.config.benchmark_mode) return;

        print("\nresults:\n", .{});
        print("  total spikes: {}\n", .{stats.total_spikes});
        print("  active neurons: {}/{} ({d:.1}%)\n", .{ stats.active_neurons, self.config.neurons, stats.activity_ratio * 100 });
        print("  mean rate: {d:.1}hz\n", .{stats.mean_rate});
        print("  network activity: {d:.1}hz\n", .{stats.mean_rate * @as(f32, @floatFromInt(self.config.neurons))});

        if (stats.active_neurons > 0) {
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

    pub fn deinit(self: *Self) void {
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
