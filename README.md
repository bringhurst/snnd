# Spiking Neural Network Daemon

> Our interests and our activities interpenetrate more and more. We are all consciously or unconsciously adapting ourselves to a single common world. - H.G. Wells

A reference [SNNP](SNNP.md) node.

```
dht/   # Distributed hash table
nn/    # Neuron models
proto/ # Protocol messages
util/  # Utilities
snnd/  # Server
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
