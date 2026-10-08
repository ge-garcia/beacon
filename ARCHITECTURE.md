# Architecture

## Layers

```
application (demo/, or yours)
     |
Beacon.Topic  (generic)     Publisher, Subscriber (Mode), protected Bounded_Queue, static registry
     |
Beacon.Queue  (generic)     pure bounded ring buffer, no tasking          SPARK proof target
     |
Beacon                      Delivery_Mode                                 Pure, SPARK

--- src/net/, desktop only. The three packages above never refer to these. ---

Beacon.Bridge (generic)     Egress task: local Subscriber -> frames -> Transport
                            Ingress task: Transport -> frames -> local Publisher
     |               |
Beacon.Wire          Beacon.Transport         frame header by rep clause, CRC-32 / Send, Receive interface
                          |
                     Beacon.Transport.UDP     GNAT.Sockets multicast
```

Each package depends only on the packages below it. `Topic` and `Queue`
never use bytes. `Bridge` is a client of `Topic`, the same as an
application. The core packages do not know that a network exists.

## Why the ring buffer is outside the protected type

`Beacon.Queue` is plain data. It has no entries, no barriers, and no
runtime dependency. Its full interface is index arithmetic on a fixed
array, so it is the proof target. `Beacon.Topic` puts one queue in each
protected object and adds the barriers.

This split makes the work easier. The team proves the ring and tests the
protected wrapper. gnatprove can prove a protected type, but with more
difficulty.

`Empty_Queue` is the only correct initial value. `Buffer` is not
initialized on purpose, because `Element_Type` may have no default
value. The queue reads only the slots between `Head` and `Tail`. The
proof will need `Relaxed_Initialization` on `Buffer` to state this.

## Delivery modes

`Subscriber (Mode : Delivery_Mode)`. The mode is also a discriminant of
the protected queue. Thus each subscriber has its own `Push` entry
barrier: always open for `Best_Effort`, open when not full for
`Reliable`.

- Reliable: `Publish` blocks on that subscriber until it has room.
  `Try_Publish` sets `Delivered` to False and goes to the next
  subscriber. `Dropped` is always 0.
- Best_Effort: `Push` never blocks. When the queue is full, the oldest
  element is overwritten and `Drops` counts it.

Each topic instantiation has one writer. `Create_Publisher` refuses a
second writer.

`Publish` sends to the subscribers in registration order, with one
protected call for each subscriber. No lock covers all subscribers.
Thus a blocked Reliable subscriber stops publication to the subscribers
after it. If this is important, register Reliable subscribers first, or
use `Try_Publish`.

## The registry

The registry is a fixed array of `Max_Subscribers` access values.
`Create_Subscriber` adds `S'Unchecked_Access` to it. The registry is not
protected. Rules:

- Register at startup, before the first `Publish`.
- Register from one task only.

The in-process demo shows the failure when a program breaks these rules:
tasks activate before `main` registers. The demo prevents the failure
with a `Go` entry. A Week 4 decision is to keep this rule or to make
registration protected.

## Wire

Each datagram holds one frame. The 14-byte header has these fields:
magic, topic id, sequence, length, and CRC-32. The CRC-32 covers the
header (with the checksum field set to 0) and the payload.

The header is an Ada record with a representation clause and
`Scalar_Storage_Order => High_Order_First`. An overlay puts it on the
byte array. The declaration gives network byte order. No code swaps
bytes.

`Decode` never raises an exception for bad input. It returns one of these
statuses:

- `Too_Short`: fewer bytes than the header.
- `Bad_Magic`: the magic field is wrong.
- `Bad_Length`: the frame is not exactly header + length bytes.
- `Bad_Checksum`: the CRC-32 does not agree.
- `Ok`.

CRC-32 is the IEEE 802.3 CRC (the same as zlib and PNG). `wire_tests`
has a test vector.

## Bridge

`Start_Egress` and `Start_Ingress` each allocate one task. The tasks are
never freed. The bridge is desktop only, so the heap is permitted there.

- **Egress** polls `Try_Receive` on its local subscriber every 1 ms. It
  sends one frame for each message. The sequence number increases by 1
  for each frame.
- **Ingress** polls the transport with a 100 ms timeout. For each frame
  it decodes the frame, checks the topic id, counts sequence gaps,
  deserializes the message, and calls `Try_Publish` locally. A full local
  subscriber thus cannot stop the network reader.
- **Stop** sets a flag. Each task ends at its next poll.

Results:

- A Reliable egress subscriber lets a slow network block the
  application's publisher.
- A Best_Effort egress subscriber lets the bridge drop messages before
  the network does.
- Neither mode makes UDP reliable. Milestone 4 is to document this
  correctly.

## Transport

`Transport` is a limited interface with `Send` and `Receive (Timeout)`.
UDP is the only implementation. One `Unchecked_Conversion` converts
between `Wire.Byte_Array` and `Stream_Element_Array`. The two array
types have the same size, and the conversion occurs in one place only.

Recommended next steps:

- An in-memory loopback transport for tests. Write this first.
- A serial transport. This is Milestone 5.

## Codecs

The user supplies one codec (Serialize and Deserialize) for each message
type to the bridge instantiation. The demo's `Reading` has a
representation clause with `High_Order_First`. Thus:

- `Serialize` is `Overlay := Msg`.
- `Deserialize` is `Msg := Overlay`, after a `'Valid_Scalars` check.

Use this pattern for each codec. If a codec needs shifts and masks, the
message type needs a representation clause.

## What is not here, on purpose

- **Dynamic discovery.** Topics are generic instantiations. Participants
  are configured, not discovered.
- **QoS beyond the two modes.** There are no deadlines, no history depth
  for each reader, and no ownership.
- **Retransmission.** A reliable transport over UDP is a full project.
  Measure the real loss first.
- **An embedded network transport.** With `BEACON_NETWORK=no`, the core
  builds on each runtime that has protected entries (light tasking or
  full). A ZFP runtime cannot host `Beacon.Topic`. Use `Beacon.Queue`
  directly on ZFP.
