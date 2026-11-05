# Test coverage

## Bridge regression coverage

Status is based on local execution. Remote CI verification is pending.
All four bridge executables run in CI alongside queue, topic, and wire tests.
The transports below are test-only capture/gated transports. They do not replace
or incorporate the teammate's unmerged reusable loopback transport.

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
| Reusable loopback transport integration | Teammate branch not merged | Pending |
| Real LAN loss between two hosts | Requires two hosts | Pending |

The startup test publishes without sleeping or polling for readiness, then
waits at most two seconds for the frame and checks its topic, sequence, and
payload. It does not force all schedules of the original implementation.

The shutdown tests hold the transport operation behind a protected barrier.
A separate task calls Stop; it must not complete during a 100 ms observation
window while the barrier is closed, and must complete after release. This
makes the operation's lifetime explicit, although thread scheduling still
applies to the observing task. CI should retain an overall job timeout.

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

queue_tests, topic_tests, and wire_tests pass locally. This document does not
claim exhaustive queue, topic, wire, or bridge coverage. Pending bridge rows
mean the full M4 coverage exit criterion is not yet satisfied.
