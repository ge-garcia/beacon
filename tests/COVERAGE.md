# Test coverage

## Bridge regression coverage

Status is based on local execution. Remote CI verification is pending.
All four bridge regression executables run in CI alongside the existing suites.
The regression tests use test-only capture/gated transports. The existing
transport and bridge suites exercise the reusable loopback transport.

| Behavior | Test executable | Status |
| --- | --- | --- |
| Egress registered when Start_Egress returns (#14) | bridge_startup_tests | Tested |
| Immediate first publication becomes a valid outgoing frame | bridge_startup_tests | Tested |
| Ingress publisher registered when Start_Ingress returns | bridge_ingress_tests | Tested |
| Full Reliable queue increments incomplete-delivery count (#17) | bridge_ingress_tests | Tested |
| Two refusing subscribers count once per incoming message | bridge_ingress_tests | Tested |
| Other subscriber receives despite partial failure | bridge_ingress_tests | Tested |
| Delivery resumes when Reliable queues are drained | bridge_ingress_tests | Tested |
| Successful delivery does not increment failure or rejection count | bridge_ingress_tests | Tested |
| Stop waits for in-flight Send (#18) | bridge_shutdown_tests | Tested |
| Stop waits for in-flight Receive (#18) | bridge_receive_shutdown_tests | Tested |
| Duplicate starts and restart after Stop are refused, both directions | Both shutdown tests | Tested |
| Repeated Stop is safe | Ingress and shutdown tests | Tested |
| Stop before any Start | Not covered | Pending |
| Worker exits through a transport/codec exception | Not covered | Pending |
| Both directions running in one bridge instantiation | Not covered | Pending |
| Reusable loopback transport integration | transport_tests and bridge_tests | Tested |
| Real LAN loss between two hosts | Requires two hosts | Pending |

The startup test publishes without sleeping or polling for readiness, then
waits at most two seconds for the frame and checks its topic, sequence, and
payload. It does not force all schedules of the original implementation.

The shutdown tests hold the transport operation behind a protected barrier.
A separate task calls Stop; it must not complete during a 100 ms observation
window while the barrier is closed, and must complete after release. This
makes the operation's lifetime explicit, although thread scheduling still
applies to the observing task. CI should retain an overall job timeout.

Both shutdown tests use `Shutdown_Test_Support.Operation_Gate`. The test
waits for entry, starts Stop, checks that Stop stays blocked, releases the
operation, and waits for completion. `Fail` prints and flushes a diagnostic
then exits with status 1. It does not wait for the Stopper task or call Stop
again, because either action could hide the failure behind a hung task.

## Negative controls (2026-11-04)

Temporary source copies were built with three intentional regressions. Each
compiled with warnings as errors and failed its corresponding test:

- Incorrect local-delivery accounting: ingress test failed.
- Stop waiting removed: send-shutdown test failed.
- Registration moved after the startup handshake with a 100 ms delay:
  startup test failed. The delay widens the original race; this is not a
  claim that the unmodified old implementation fails under every schedule.

Production working files were not replaced by these temporary variants.

## Existing suites

Run `alr test` from the repository root to build and run all ten executables.
The runner stops on the first failure or timeout.

queue_tests, topic_tests, and wire_tests pass locally. This document does not
claim exhaustive queue, topic, wire, or bridge coverage. Pending bridge rows
mean the full M4 coverage exit criterion is not yet satisfied.

| Test | Behavior checked |
| --- | --- |
| `queue_tests` | FIFO wraparound, bounded fill, and drop-oldest behavior. |
| `topic_tests` | Typed fan-out, best-effort overflow, nonblocking operations, and a full Reliable queue blocking `Publish` until `Receive` frees a slot. |
| `topic_load_tests` | Four independent topics publish concurrently; each Reliable subscriber receives every message in order with no drops after sustained backpressure. The duration defaults to two seconds and CI runs it for 60 seconds. A positive integer argument selects the duration in seconds. |
| `wire_tests` | Wire encoding, decoding, CRC, and rejection of invalid frames. |
| `transport_tests` | Loopback transport delivery, bounds, and full-queue behavior. |
| `bridge_tests` | Local bridge delivery, frame rejection, sequence gaps, and saturated egress retry. |

The load test checks message counts and order as well as `Dropped = 0`.
`Dropped = 0` alone does not prove that a message arrived, because
`Try_Publish` can refuse delivery to a full Reliable queue.

The load test waits for each publisher to finish before it accepts an empty
queue as fully drained.
