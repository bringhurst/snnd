# Spiking Neural Network Daemon

A reference [SNNP](SNNP.md) node.

```
dht/   # Distributed hash table
nn/    # Neuron models
proto/ # Protocol messages
util/  # Utilities
snnd/  # Daemon
snnc/  # Client
```

## Getting started

First, [setup a Zig toolchain](https://ziglang.org), then:

```
zig build test
```
