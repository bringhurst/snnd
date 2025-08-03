# Spiking Neural Network Daemon

> Our interests and our activities interpenetrate more and more. We are all consciously or unconsciously adapting ourselves to a single common world. - H.G. Wells

A reference [SNNP](SNNP.md) node.

### Layout
```
dht/   # Distributed hash table
nn/    # Neuron models
proto/ # Protocol messages
util/  # Utilities
snnd/  # Server
snnc/  # Client
```

### Flow

DHT finds peers, IDs passed through the map hash, spikes travel in bursts.
```
 +----------------+    +--------------+    +----------------+
 |                +----+ Kademlia DHT +----+                |
 |  snnd node A   |    +--------------+    |  snnd node B   |
 |                |                        |                |
 | neuron group A |     +------------+     | neuron group B |
 |                +-----+ UDP spikes +-----+                |
 +----------------+     +------------+     +----------------+
```

### Building

First, [setup a Zig toolchain](https://ziglang.org), then:

```
zig build test
```
