## Spiking Neural Network Protocol (SNNP)

This document defines the wire protocol for SNNP. It assumes peer discovery is handled by an external DHT.

## 1. Overview

- All messages are transmitted over UDP.
- Each UDP datagram contains exactly one SNNP message.
- All multi-byte fields use network byte order (big-endian).
- UUIDs conform to RFC 4122 (16 bytes).

## 2. Message Types

Each message begins with a **1-byte type field**:

| Value | Name   | Purpose                        |
|-------|--------|--------------------------------|
| 0x01  | HELLO  | Node/group introduction        |
| 0x10  | SPIKE  | Spike event transmission       |

## 3. Message Formats

### 3.1. HELLO (0x01)

Announces the sender's node UUID and neuron groups.

| Offset | Size | Field            | Description                    |
|--------|------|------------------|--------------------------------|
| 0      | 1    | Msg Type (0x01)  | See section 2                  |
| 1      | 16   | Node UUID        | RFC4122                        |
| 17     | 1    | Num Groups (n)   | Number of neuron groups (uint8)|
| 18     | 16*n | Group UUIDs      | n × 16 bytes                   |

### 3.2. SPIKE (0x10)

Transmits a spike event from a source neuron to a destination neuron.

| Offset | Size | Field                | Description                      |
|--------|------|----------------------|----------------------------------|
| 0      | 1    | Msg Type (0x10)      |                                  |
| 1      | 16   | Src Group UUID       | Source neuron group UUID         |
| 17     | 2    | Src Neuron ID        | uint16, source-local             |
| 19     | 16   | Dst Group UUID       | Destination neuron group UUID    |
| 35     | 2    | Dst Neuron ID        | uint16, destination-local        |
| 37     | 8    | Timestamp (ms)       | uint64, ms since Unix epoch      |

## 4. Field Encoding

- **UUIDs:** 16 bytes, RFC4122, big-endian
- **Neuron IDs:** uint16 (2 bytes), unique within group
- **Timestamps:** uint64 (8 bytes), milliseconds since Unix epoch (UTC)

## 5. Protocol Behavior

- **HELLO:** Sent periodically or when connecting to a new peer to announce node and neuron group UUIDs.
- **SPIKE:** Sent for each spike event from a source neuron to a destination neuron.

## 6. Extensibility

- Unknown message types MUST be ignored.
- Message types 0x02–0x0F, 0x11–0xFF are reserved for future use.
- Optional fields may be appended after mandatory fields, provided backward compatibility is maintained.
