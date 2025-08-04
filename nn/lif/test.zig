const std = @import("std");
const lif = @import("lif.zig");
const sim = @import("sim.zig");

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

    // Force a spike
    _ = neuron.step(10.0, 1.0);
    while (!neuron.spiked()) {
        _ = neuron.step(10.0, 0.1);
    }

    // Should be in refractory
    try std.testing.expect(neuron.inRefractory());

    // Should stay at reset during refrac
    _ = neuron.step(10.0, 1.0);
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

    // Test different input currents
    const currents = [_]f64{ 1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0 };
    var rates = std.ArrayList(f64).init(allocator);
    defer rates.deinit();

    for (currents) |current| {
        const config = sim.SimConfig{
            .duration_ms = 1000.0,
            .input_current = current,
            .dt_ms = 0.1,
        };

        var result = try sim.runSimulation(allocator, config);
        defer result.deinit();

        const rate = sim.calculateFiringRate(result.spike_times.items, config.duration_ms);
        try rates.append(rate);
    }

    // Firing rate should increase with input current
    for (1..rates.items.len) |i| {
        try std.testing.expect(rates.items[i] >= rates.items[i - 1]);
    }
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

    // Force spike
    neuron.v_mem = -55.0;
    _ = neuron.step(0.0, 0.1);

    // During refractory, large input shouldn't cause spike
    const spiked = neuron.step(100.0, 1.0); // huge input
    try std.testing.expect(!spiked);
    try std.testing.expectEqual(-75.0, neuron.voltage()); // stays at reset

    // After refractory, should be able to spike again
    _ = neuron.step(0.0, 2.0); // wait out refractory
    neuron.v_mem = -55.0;
    const spiked2 = neuron.step(0.0, 0.1);
    try std.testing.expect(spiked2);
}

test "simulation ISI calculation" {
    const allocator = std.testing.allocator;

    const spike_times = [_]f64{ 10.0, 25.0, 40.0, 60.0 };
    const isis = try sim.calculateISI(&spike_times, allocator);
    defer allocator.free(isis);

    try std.testing.expectEqual(@as(usize, 3), isis.len);
    try std.testing.expectEqual(15.0, isis[0]);
    try std.testing.expectEqual(15.0, isis[1]);
    try std.testing.expectEqual(20.0, isis[2]);
}

test "simulation firing rate" {
    const spike_times = [_]f64{ 100.0, 200.0, 300.0, 400.0 };
    const rate = sim.calculateFiringRate(&spike_times, 1000.0); // 1 second
    try std.testing.expectEqual(4.0, rate); // 4 Hz
}
