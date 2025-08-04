const std = @import("std");
const lif = @import("lif.zig");

test "LIF basic functionality" {
    var neuron = lif.LIF.init(lif.Params{});

    // Should start at rest
    try std.testing.expectEqual(-70.0, neuron.voltage());
    try std.testing.expectEqual(false, neuron.spiked());

    // Small input shouldn't spike
    const spiked = neuron.step(1.0, 1.0);
    try std.testing.expectEqual(false, spiked);
    try std.testing.expect(neuron.voltage() > -70.0); // should depolarize

    // Reset should work
    neuron.reset();
    try std.testing.expectEqual(-70.0, neuron.voltage());
}

test "LIF spike generation" {
    var neuron = lif.LIF.init(lif.Params{});

    // Large input should cause spike
    var spiked = false;
    var steps: u32 = 0;
    while (!spiked and steps < 100) {
        spiked = neuron.step(10.0, 0.1); // 10nA input, 0.1ms timestep
        steps += 1;
    }

    try std.testing.expect(spiked);
    try std.testing.expectEqual(-75.0, neuron.voltage()); // should be at reset
}

test "LIF refractory period" {
    var neuron = lif.LIF.init(lif.Params{ .t_refrac = 5.0 });

    // Force a spike by stepping with large input
    var spiked = false;
    var steps: u32 = 0;
    while (!spiked and steps < 100) {
        spiked = neuron.step(10.0, 0.1);
        steps += 1;
    }
    try std.testing.expect(spiked);

    // Should be in refractory
    try std.testing.expect(neuron.inRefractory());

    // Should stay at reset during refrac
    const spiked2 = neuron.step(10.0, 1.0);
    try std.testing.expect(!spiked2);
    try std.testing.expectEqual(-75.0, neuron.voltage());

    // Step past refractory period
    _ = neuron.step(0.0, 10.0);
    try std.testing.expect(!neuron.inRefractory());
}

test "LIF membrane dynamics" {
    var neuron = lif.LIF.init(lif.Params{
        .tau_m = 20.0,
        .v_rest = -70.0,
        .r_m = 10.0,
    });

    // Test membrane integration with no input
    _ = neuron.step(0.0, 1.0);
    try std.testing.expectEqual(-70.0, neuron.voltage()); // should stay at rest

    // Test depolarization with positive input
    neuron.v_mem = -60.0; // set above rest
    _ = neuron.step(0.0, 1.0);
    try std.testing.expect(neuron.voltage() < -60.0); // should decay toward rest
    try std.testing.expect(neuron.voltage() > -70.0); // but not reach it in 1ms
}

test "LIF f-I curve" {
    const allocator = std.testing.allocator;

    // Test different input currents and measure firing rates
    const currents = [_]f64{ 1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0 };
    var rates = std.ArrayList(f64).init(allocator);
    defer rates.deinit();

    for (currents) |current| {
        var neuron = lif.LIF.init(lif.Params{});
        var spike_times = std.ArrayList(f64).init(allocator);
        defer spike_times.deinit();

        // Run simulation for 1 second
        const duration_ms = 1000.0;
        const dt_ms = 0.1;
        const steps = @as(u32, @intFromFloat(duration_ms / dt_ms));

        for (0..steps) |step| {
            const t = @as(f64, @floatFromInt(step)) * dt_ms;
            if (neuron.step(current, dt_ms)) {
                try spike_times.append(t);
            }
        }

        // Calculate firing rate (Hz)
        const rate = @as(f64, @floatFromInt(spike_times.items.len)) / (duration_ms / 1000.0);
        try rates.append(rate);
    }

    // Firing rate should generally increase with input current
    // (allowing for some variability due to discrete timesteps)
    var increasing_trend = true;
    for (1..rates.items.len) |i| {
        if (rates.items[i] < rates.items[i - 1] - 1.0) { // allow small decreases
            increasing_trend = false;
            break;
        }
    }
    try std.testing.expect(increasing_trend);
}

test "LIF threshold behavior" {
    var neuron = lif.LIF.init(lif.Params{
        .v_thresh = -55.0,
        .v_reset = -75.0,
    });

    // Set voltage just below threshold
    neuron.v_mem = -55.1;
    var spiked = neuron.step(0.0, 0.1);
    try std.testing.expect(!spiked);

    // Set voltage at threshold
    neuron.v_mem = -55.0;
    spiked = neuron.step(0.0, 0.1);
    try std.testing.expect(spiked);
    try std.testing.expectEqual(-75.0, neuron.voltage());
}

test "LIF refractory dynamics" {
    var neuron = lif.LIF.init(lif.Params{
        .t_refrac = 2.0,
        .v_reset = -75.0,
    });

    // Force spike by setting voltage to threshold
    neuron.v_mem = -55.0;
    const spiked1 = neuron.step(0.0, 0.1);
    try std.testing.expect(spiked1);

    // During refractory, large input shouldn't cause spike
    const spiked2 = neuron.step(100.0, 1.0); // huge input
    try std.testing.expect(!spiked2);
    try std.testing.expectEqual(-75.0, neuron.voltage()); // stays at reset

    // After refractory, should be able to spike again
    _ = neuron.step(0.0, 2.0); // wait out refractory
    neuron.v_mem = -55.0;
    const spiked3 = neuron.step(0.0, 0.1);
    try std.testing.expect(spiked3);
}

test "ISI calculation" {
    const allocator = std.testing.allocator;

    const spike_times = [_]f64{ 10.0, 25.0, 40.0, 60.0 };
    const isis = try calculateISI(&spike_times, allocator);
    defer allocator.free(isis);

    try std.testing.expectEqual(@as(usize, 3), isis.len);
    try std.testing.expectEqual(15.0, isis[0]);
    try std.testing.expectEqual(15.0, isis[1]);
    try std.testing.expectEqual(20.0, isis[2]);
}

test "firing rate calculation" {
    const spike_times = [_]f64{ 100.0, 200.0, 300.0, 400.0 };
    const rate = calculateFiringRate(&spike_times, 1000.0); // 1 second
    try std.testing.expectEqual(4.0, rate); // 4 Hz
}

// Helper functions for spike analysis
fn calculateISI(spike_times: []const f64, allocator: std.mem.Allocator) ![]f64 {
    if (spike_times.len < 2) return allocator.alloc(f64, 0);

    var isis = try allocator.alloc(f64, spike_times.len - 1);
    for (1..spike_times.len) |i| {
        isis[i - 1] = spike_times[i] - spike_times[i - 1];
    }
    return isis;
}

fn calculateFiringRate(spike_times: []const f64, duration_ms: f64) f64 {
    const duration_s = duration_ms / 1000.0;
    return @as(f64, @floatFromInt(spike_times.len)) / duration_s;
}
