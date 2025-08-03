## Spiking Neural Network Protocol (SNNP) - Version 1

This document defines the SNNP wire protocol for distributed [SNNs](https://en.wikipedia.org/wiki/Spiking_neural_network).

It assumes peer discovery is handled by an external [DHT](https://en.wikipedia.org/wiki/Distributed_hash_table).

## 1. Overview

- All messages are transmitted over UDP.
- Each UDP datagram contains exactly one SNNP message.
- All multi-byte fields use network byte order (big-endian).
- UUIDs conform to [RFC9562](https://www.rfc-editor.org/rfc/rfc9562) (16 bytes).

## 2. Message Header

Each message begins with the following header:

| Offset | Size | Field        | Description                               |
|--------|------|--------------|-------------------------------------------|
| 0      | 4    | Magic        | `0x534E4E50` ("SNNP" in ASCII)           |
| 4      | 1    | Version      | Protocol version (uint8), `0x01`          |
| 5      | 1    | Msg Type     | See section 3                             |
| 6      | 2    | Reserved     | Reserved for future use, MUST be zero     |

## 3. Message Types

| Value | Name   | Purpose                        |
|-------|--------|--------------------------------|
| 0x01  | HELLO  | Node/group introduction        |
| 0x10  | SPIKE  | Spike event transmission       |

## 4. Message Formats

All messages start with the 8-byte header.

### 4.1. HELLO (0x01)

Announces the sender's node UUID and neuron groups.

| Offset | Size    | Field              | Description                           |
|--------|---------|--------------------|---------------------------------------|
| 0      | 8       | Header             | See section 2                         |
| 8      | 16      | Node UUID          | RFC9562                               |
| 24     | 1       | Num Groups (n)     | Number of neuron groups (uint8)       |
| 25     | 3       | Reserved           | Reserved for future use, MUST be zero |
| 28     | 16×n    | Group UUIDs        | n × 16 bytes (RFC9562 UUIDs)          |

### 4.2. SPIKE (0x10)

Transmits a spike event from a source neuron to a destination neuron.

| Offset | Size    | Field                | Description                      |
|--------|---------|----------------------|----------------------------------|
| 0      | 8       | Header               | See section 2                    |
| 8      | 16      | Src Group UUID       | Source neuron group UUID         |
| 24     | 16      | Dst Group UUID       | Destination neuron group UUID    |
| 40     | 2       | Src Neuron ID        | uint16, source-local             |
| 42     | 2       | Dst Neuron ID        | uint16, destination-local        |
| 44     | 8       | Timestamp (ms)       | uint64, ms since Unix epoch      |

## 5. Field Encoding

- **Magic:** 4 bytes, fixed value `0x534E4E50` ("SNNP" in ASCII)
- **Version:** uint8 (1 byte), indicates the protocol version, fixed value `0x01`.
- **Msg Type:** uint8 (1 byte), see section 3.
- **Reserved:** 2 bytes in header, 3 bytes in HELLO message, MUST be set to zero and ignored by receivers.
- **UUIDs:** 16 bytes, RFC9562, big-endian
- **Neuron IDs:** uint16 (2 bytes), unique within group
- **Timestamps:** uint64 (8 bytes), milliseconds since Unix epoch (UTC)

## 6. Protocol Behavior

- **HELLO:** Sent periodically or when connecting to a new peer to announce node and neuron group UUIDs.
- **SPIKE:** Sent for each spike event from a source neuron to a destination neuron.

## 7. Extensibility

- Unknown magic values, versions, or message types MUST be ignored.
- Message types `0x02`-`0x0F`, `0x11`-`0xFF` are reserved for future use.
- Reserved fields MUST be ignored by receivers.
- Optional fields may be appended after mandatory fields, provided backward compatibility is maintained.
