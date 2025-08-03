## Spiking Neural Network Protocol (SNNP) - Version 1

This document defines the wire protocol for SNNP. It assumes peer discovery is handled by an external DHT.

## 1. Overview

- All messages are transmitted over UDP.
- Each UDP datagram contains exactly one SNNP message.
- All multi-byte fields use network byte order (big-endian).
- UUIDs conform to [RFC4122](https://www.rfc-editor.org/rfc/rfc4122) (16 bytes).

## 2. Message Header

Each message begins with the following header:

| Offset | Size | Field        | Description                           |
|--------|------|--------------|---------------------------------------|
| 0      | 4    | Magic        | 0x53 4E 4E 50 ("SNNP" in ASCII)       |
| 4      | 1    | Version      | Protocol version (uint8), `0x01`      |
| 5      | 1    | Msg Type     | See section 3                         |

## 3. Message Types

| Value | Name   | Purpose                        |
|-------|--------|--------------------------------|
| 0x01  | HELLO  | Node/group introduction        |
| 0x10  | SPIKE  | Spike event transmission       |

## 4. Message Formats

All messages start with the 6-byte header.  

### 4.1. HELLO (0x01)

Announces the sender's node UUID and neuron groups.

| Offset | Size    | Field            | Description                        |
|--------|---------|------------------|------------------------------------|
| 0      | 6       | Header           | See section 2                      |
| 6      | 16      | Node UUID        | RFC4122                            |
| 22     | 1       | Num Groups (n)   | Number of neuron groups (uint8)    |
| 23     | 16×n    | Group UUIDs      | n × 16 bytes (RFC4122 UUIDs)       |

### 4.2. SPIKE (0x10)

Transmits a spike event from a source neuron to a destination neuron.

| Offset | Size    | Field                | Description                      |
|--------|---------|----------------------|----------------------------------|
| 0      | 6       | Header               | See section 2                    |
| 6      | 16      | Src Group UUID       | Source neuron group UUID         |
| 22     | 16      | Dst Group UUID       | Destination neuron group UUID    |
| 38     | 2       | Src Neuron ID        | uint16, source-local             |
| 40     | 2       | Dst Neuron ID        | uint16, destination-local        |
| 42     | 8       | Timestamp (ms)       | uint64, ms since Unix epoch      |

## 5. Field Encoding

- **Magic:** 4 bytes, fixed value 0x534E4E50 ("SNNP" in ASCII)
- **Version:** uint8 (1 byte), indicates the SNNP protocol version. The initial version is `0x01`.
- **Msg Type:** uint8 (1 byte), see section 3.
- **UUIDs:** 16 bytes, RFC4122, big-endian
- **Neuron IDs:** uint16 (2 bytes), unique within group
- **Timestamps:** uint64 (8 bytes), milliseconds since Unix epoch (UTC)

## 6. Protocol Behavior

- **HELLO:** Sent periodically or when connecting to a new peer to announce node and neuron group UUIDs.
- **SPIKE:** Sent for each spike event from a source neuron to a destination neuron.

## 7. Extensibility

- Unknown magic values, versions, or message types MUST be ignored.
- Message types 0x02–0x0F, 0x11–0xFF are reserved for future use.
- Optional fields may be appended after mandatory fields, provided backward compatibility is maintained.
