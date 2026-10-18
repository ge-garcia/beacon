# Test coverage against the specs

This file compares the specs with the tests. The specs are the package
specs in `src/**/*.ads` and the text in `ARCHITECTURE.md`. Each row is
one behavior that a spec states.

First written on 2026-10-08, for seed commit `c7e44fd`. Each commit
that adds or changes a test updates its rows here.

## Terms

- **Tested**: a unit test in `tests/src/` checks the behavior.
- **Partly tested**: a unit test runs the behavior but does not check
  all of it. The Note column says which part is not checked.
- **Demo only**: no unit test checks the behavior. Only
  `demo/inproc_demo` or the UDP demo step in CI runs it.
- **Not tested**: no test and no demo checks the behavior.
- **Contracts**: all builds use `-gnata`, so the compiler checks each
  precondition and postcondition at runtime. Each test therefore also
  checks the contracts of the subprograms that it calls. This file does
  not list these checks separately.

## Beacon.Queue (`queue_tests`)

| Behavior                                                                    | Status        | Note                                  |
| --------------------------------------------------------------------------- | ------------- | ------------------------------------- |
| A new queue is empty. `Push` fills it to `Depth`. `Pop` returns FIFO order. | Tested        | ------------------------------------- |
| `Push` and `Pop` wrap around the end of the ring.                           | Tested        | ------------------------------------- |
| `Push_Dropping_Oldest` drops the oldest element when the queue is full.     | Tested        | ------------------------------------- |
| `Push_Dropping_Oldest` keeps the order after many drops in sequence.        | Tested        | `Head` wraps two times.               |
| `Push_Dropping_Oldest` works when `Head` is not at index 0.                 | Tested        | A `Pop` before the drop moves `Head`. |
| The queue works with `Depth = 1`.                                           | Tested        | `Next` uses `mod 1` in this case.     |
| `Pop` on an empty queue raises `Assertion_Error`.                           | Not tested    | Precondition.                         |
| `Push` on a full queue raises `Assertion_Error`.                            | Not tested    | Precondition.                         |

### Note for Milestone 1

The postconditions of `Beacon.Queue` state only the value of `Count`.
They do not state which elements are in the queue.

A Silver proof shows that no runtime error can occur. It does not show
functional behavior. Thus a Silver proof does not show these two
properties:

- `Pop` returns elements in FIFO order.
- `Push_Dropping_Oldest` drops the oldest element.

The unit tests are the only check of these properties. To prove them,
you must add functional contracts to `Beacon.Queue`.

## Beacon.Topic (`topic_tests`)

| Behavior                                                                                     | Status        | Note                                                                      |
| -------------------------------------------------------------------------------------------- | ------------- | ------------------------------------------------------------------------- |
| `Publish` sends the same typed value to each subscriber.                                     | Tested        | ------------------------------------------------------------------------- |
| `Try_Publish` on a full Reliable subscriber does not block and sets `Delivered` to False.    | Tested        | The test also checks that the queue does not change and `Dropped = 0`.    |
| `Try_Publish` on a full Best_Effort subscriber drops the oldest message and counts the drop. | Tested        | ------------------------------------------------------------------------- |
| `Try_Publish` gives the message to all subscribers that are not full.                        | Partly tested | The test does not check that the Best_Effort queue holds the new message. |
| `Try_Publish` sets `Delivered` to True when all subscribers are Best_Effort.                 | Not tested    | ------------------------------------------------------------------------- |
| `Publish` on a full Best_Effort subscriber drops the oldest message and does not block.      | Demo only     | This uses the `Push` entry. `Try_Publish` uses a different path.          |
| `Dropped` counts more than one drop.                                                         | Demo only     | ------------------------------------------------------------------------- |
| `Try_Receive` returns a message and `Pending` decreases by 1.                                | Not tested    | The test checks only the empty case.                                      |
| `Publish` with zero subscribers does nothing.                                                | Not tested    | ------------------------------------------------------------------------- |
| A second `Create_Publisher` raises `Assertion_Error`.                                        | Not tested    | Precondition. Single writer rule.                                         |
| `Create_Subscriber` past `Max_Subscribers` raises `Assertion_Error`.                         | Not tested    | Precondition.                                                             |
| `Publish` on a full Reliable subscriber blocks, then continues when the subscriber reads.    | Not tested    | Milestone 2. A TODO in `topic_tests.adb` records it.                      |
| Under a long, high load, `Dropped` stays 0 on each Reliable subscriber.                      | Not tested    | Milestone 2. The demo does not fill its Reliable queue (see below).       |
| `Receive` on an empty queue blocks, then continues when a message arrives.                   | Not tested    | Needs the Milestone 2 tasking test.                                       |
| A blocked Reliable subscriber stops delivery to the subscribers registered after it.         | Not tested    | Needs the Milestone 2 tasking test.                                       |

The in-process demo does not test Reliable under load. The controller
publishes at 10 Hz and the main task reads at 100 Hz. Thus the Reliable
queue never becomes full.

## Beacon.Wire (`wire_tests`)

| Behavior                                                                               | Status     | Note                                     |
| -------------------------------------------------------------------------------------- | ---------- | ---------------------------------------- |
| The header is 14 bytes.                                                                | Tested     | ---------------------------------------- |
| `Checksum` gives the CRC-32 test vector for "123456789".                               | Tested     | ---------------------------------------- |
| `Decode` returns the fields that `Encode` wrote. `Last` agrees with the postcondition. | Tested     | ---------------------------------------- |
| `Magic` is big-endian at bytes 0 and 1.                                                | Tested     | ---------------------------------------- |
| `Topic`, `Sequence`, `Length`, and `Checksum` are big-endian at their offsets.         | Not tested | Only `Magic` is checked.                 |
| A frame shorter than the header gives `Too_Short`.                                     | Tested     | ---------------------------------------- |
| A frame shorter than header + `Length` gives `Bad_Length`.                             | Tested     | ---------------------------------------- |
| A frame longer than header + `Length` gives `Bad_Length`.                              | Not tested | The spec states this rule.               |
| A `Length` field above `Max_Payload` gives `Bad_Length`.                               | Not tested | `'Valid` check on the field.             |
| A wrong magic value gives `Bad_Magic`.                                                 | Not tested | ---------------------------------------- |
| A changed payload byte gives `Bad_Checksum`.                                           | Tested     | ---------------------------------------- |
| A changed header byte gives `Bad_Checksum`.                                            | Not tested | ---------------------------------------- |
| On each error status, `Decode` sets its outputs to zero.                               | Not tested | ---------------------------------------- |
| `Encode` and `Decode` work with an empty payload.                                      | Not tested | ---------------------------------------- |
| `Encode` and `Decode` work with a payload of `Max_Payload` bytes.                      | Not tested | ---------------------------------------- |
| `Encode` and `Decode` work when `Frame'First` or `Payload'First` is not 1.             | Not tested | The header overlay is then at an offset. |

## Beacon.Bridge and Beacon.Transport.UDP

No unit test checks these packages. Only the UDP demo step in CI runs
them. That step uses one Best_Effort egress and one ingress on loopback.
It sends 200 readings and checks only the final count in the log.

| Behavior                                                                    | Status     | Note                                             |
| --------------------------------------------------------------------------- | ---------- | ------------------------------------------------ |
| Egress sends one frame for each local message. The sequence increases by 1. | Demo only  | ------------------------------------------------ |
| Ingress publishes each decoded frame on the local topic.                    | Demo only  | ------------------------------------------------ |
| `Rejected_Frames` counts frames with a bad status.                          | Not tested | ------------------------------------------------ |
| `Rejected_Frames` counts frames with a different `Topic_Id`.                | Not tested | ------------------------------------------------ |
| `Rejected_Frames` counts frames that `Deserialize` rejects.                 | Not tested | ------------------------------------------------ |
| `Sequence_Gaps` counts each sequence that is not previous + 1.              | Not tested | The demo prints the value but does not check it. |
| `Sequence_Gaps` is correct when the sequence wraps at 2\*\*32.              | Not tested | ------------------------------------------------ |
| Egress works with a Reliable subscriber.                                    | Not tested | ------------------------------------------------ |
| `Stop` ends the egress task and the ingress task.                           | Not tested | `Stop` does not wait for the tasks.              |
| UDP `Receive` sets `Count` to 0 when the timeout ends.                      | Not tested | ------------------------------------------------ |

To test the bridge without sockets, you must first write an in-memory
loopback `Transport`. `ARCHITECTURE.md` recommends this transport.

## Codecs (`demo/src/telemetry-codecs`)

No test checks these behaviors:

- `Deserialize_Reading` returns the value that `Serialize_Reading` wrote.
- `Deserialize_Reading` sets `Valid` to False when the buffer length is wrong.
- `Deserialize_Reading` sets `Valid` to False when a field is not a valid value.

The codecs are demo code. But each new codec copies this pattern, so a
defect here can occur again in other codecs.

## Build profile

`tests.gpr` lists `wire_tests` as a main program. `wire_tests` needs
`src/net/`. Thus the tests do not build with `BEACON_NETWORK=no`.

Result: no test runs `Beacon.Queue` or `Beacon.Topic` in the embedded
profile, which is the profile that these packages are for.
