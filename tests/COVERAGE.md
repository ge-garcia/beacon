# Test coverage

| Test | Behavior checked |
| --- | --- |
| `queue_tests` | FIFO wraparound, bounded fill, and drop-oldest behavior. |
| `topic_tests` | Typed fan-out, best-effort overflow, nonblocking operations, and a full Reliable queue blocking `Publish` until `Receive` frees a slot. |
| `topic_load_tests` | Four independent topics publish concurrently; each Reliable subscriber receives every message in order with no drops after sustained backpressure. The duration defaults to 180 seconds and CI uses a two-second smoke run. |
| `wire_tests` | Wire encoding, decoding, CRC, and rejection of invalid frames. |
| `transport_tests` | Loopback transport delivery, bounds, and full-queue behavior. |
| `bridge_tests` | Local bridge delivery, frame rejection, sequence gaps, and saturated egress retry. |

The load test checks message counts and order as well as `Dropped = 0`.
`Dropped = 0` alone does not prove that a message arrived, because
`Try_Publish` can refuse delivery to a full Reliable queue.
