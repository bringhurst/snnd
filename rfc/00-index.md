# Spiking Neural Network Protocol (SNNP) — Version 1

SNNP v1 is a binary protocol for distributed spiking neural networks.

## Table of contents
- [01-types-and-conventions](01-types-and-conventions.md) — types, encoding, capabilities, limits
- [02-datagram-mode.md](02-datagram-mode) — UDP profile and message formats
- [03-session-mode.md](03-session-mode) — QUIC/uTP profile, handshake, discovery, state machine
- [04-timing-and-learning.md](04-timing-and-learning) — interval semantics and reference iuSTDP rules
- [05-normalization-and-stability.md](05-normalization-and-stability) — inbound weight normalization and stability bounds
- [06-scalability-and-partitioning.md](06-scalability-and-partitioning) — addressing, subscription, batching, replay
- [07-security-and-privacy.md](07-security-and-privacy) — identities, auth, abuse model, privacy profiles
- [08-registries.md](08-registries) — assigned numbers for types and TLVs
- [09-test-vectors.md](09-test-vectors) — example encodings
