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

```
 +----------------+    +--------------+    +----------------+
 |                +----+ Kademlia DHT +----+                |
 |  snnd node A   |    +--------------+    |  snnd node B   |
 |                |                        |                |
 | neuron group A |     +------------+     | neuron group B |
 |                +-----+ UDP spikes +-----+                |
 +----------------+     +------------+     +----------------+
```

## Getting started

First, [setup a Zig toolchain](https://ziglang.org), then:

```
zig build test
```
