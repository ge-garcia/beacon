# Expected behavior for Beacon's open design decisions

## Purpose

I reviewed the four open design decisions for Beacon.Topic.
For each decision, I describe the current behavior, an example scenario,
my recommendation, and the checks needed to verify the expected behavior.
This document supports Milestone 3 by defining behavior before implementation changes begin.

The recommendations are proposals for team review.
They do not represent approved decisions or completed code changes.
The test checks describe future work, not tests that have passed.

## Summary

| Decision | Current behavior | Proposed behavior | Decision status |
| --- | --- | --- | --- |
| Full Reliable queue during `Try_Publish` | Partial delivery; `Delivered = False` if any Reliable queue refuses the message | Keep partial delivery and specify retry limits | Proposed; awaiting review |
| Registration task safety | One task registers subscribers before publication | Protect registration; keep startup-only membership | Proposed; awaiting review |
| Receive timeout | `Receive` waits indefinitely; `Try_Receive` does not wait for data | Add an optional timed receive without removing existing operations | Proposed; awaiting review |
| Subscriber lifetime | Registry stores access values to caller-owned subscribers | Use fixed topic-owned queue storage with subscriber handles | Proposed; awaiting review |

## 1. Full Reliable queue during Try_Publish

### Current behavior

`Try_Publish` visits every registered subscriber.
A full Reliable queue refuses the new message.
Other subscribers still receive the message.
A full Best_Effort queue replaces its oldest message and increments its drop count.
`Delivered` is True only when all registered queues accept the message.
With no subscribers, `Delivered` is also True because no queue refuses it.

`Try_Publish` does not wait for queue space.
It still uses protected operations; this statement is not a guarantee of zero execution delay.
`Dropped` counts overwritten queued messages.
A refused new message does not increase a Reliable subscriber's `Dropped` count.

### Example scenario

Assume one publisher, no concurrent receives, and queue depth 3.
Register Reliable subscriber A and Best_Effort subscriber B.
Publish messages 10, 11, and 12 to both queues.
Receive all three messages from B, leaving A full and B empty.
Call `Try_Publish` with message 13.

| Observation | Expected result in the current implementation |
| --- | --- |
| A's queued messages | 10, 11, 12 |
| B's queued messages | 13 |
| `Delivered` | False |
| `Pending (A)` | 3 |
| `Pending (B)` | 1 |
| `Dropped (A)` | 0 |

### Proposed behavior and reason

I recommend keeping partial delivery.
Independent subscriber queues should accept messages when they can.
A slow reader should not prevent a `Try_Publish` attempt from serving other readers.
All-or-nothing behavior would require a separate coordination design across queues.

Document that False does not mean no subscriber received the message.
An application must not assume that retrying the whole message avoids duplicates.
An application that requires waiting for every local queue should use `Publish` and handle backpressure.
Acceptance into a queue does not mean the application processed the message.

### Future test checks

- Reproduce the example and verify each queue's contents and pending count.
- Check that the full Reliable queue retains its old messages in order.
- Repeat with two Reliable subscribers, one full and one empty.
- Verify that all queues with room accept the message and produce True.
- Fill B as well; verify its oldest message is replaced and its drop count increases once.
- Drain A, then retry message 13 without draining B; verify B can receive two copies of message 13.
- Verify the documented zero-subscriber result.

The existing topic tests cover parts of partial delivery and Best_Effort overflow.
It does not establish every check listed above.

## 2. Registration task safety

### Current behavior

The registry is a fixed array without a protected wrapper.
`Create_Subscriber` increments `Registered`, stores `S'Unchecked_Access`, and sets `S.Registered`.
The caller must register subscribers from one task before publication starts.
Concurrent registration is outside this contract and has no supported expected result.
Precondition checks do not coordinate separate tasks.

Design rule 4: topics and participants are configured at compile time or startup.
Protecting registration need not introduce runtime discovery or dynamic subscription.

### Example scenario

Assume `Max_Subscribers = 2`, with one subscriber already registered.
Two tasks attempt to register different subscribers at the same time.
Only one slot remains.
The current API requires the caller to prevent this overlap.
Do not treat a particular race result as a guaranteed current behavior.

### Proposed behavior and reason

I recommend protecting registry checks and updates as one operation.
Permit concurrent registration during startup, but freeze membership before publication.
Reject registration after the startup phase ends.
This preserves the static model and makes capacity checks safe under concurrent attempts.

For the example, exactly one registration should succeed.
The other attempt should report capacity exhaustion without changing the registry.
The team must choose the failure mechanism before implementation.
That mechanism could be a result value or a documented exception.

Create the publisher before publication starts.
If publisher creation can occur concurrently, protect the single-publisher claim too.
Current count-based postconditions may need revision because another task can register before a caller checks them.
Define concurrency-safe contracts as part of the API change.

Read the frozen membership under protection, then release the registry protection before delivery.
Do not call a potentially waiting queue `Push` from inside the protected registry operation.
Subscriber lifetime must remain valid independently of registry synchronization.

### Future test checks

- Release concurrent registration tasks through a shared start signal.
- Verify that each successful registration occupies one distinct slot.
- At the capacity boundary, verify exactly one winner and a count equal to `Max_Subscribers`.
- Verify that duplicate registration fails without changing the count.
- Verify that registration after startup fails without changing membership.
- After startup, publish one message and verify every registered subscriber receives one copy.
- If concurrent publisher creation is supported, verify exactly one publisher claim succeeds.

Use explicit task signals to coordinate tests.
Do not rely only on arbitrary delays to create or detect overlap.
Keep concurrent-registration tests separate from tests of the current single-task startup contract.

## 3. Receive with a timeout

### Current behavior

`Receive` calls `S.Queue.Pop`.
The Pop barrier opens only when the queue is not empty.
An empty queue can therefore make Receive wait indefinitely.
`Try_Receive` checks once and returns False when the queue is empty.
The caller must ignore `Msg` when Success is False.
The current API does not include a timed Receive overload.

### Example scenario

A registered subscriber has an empty queue.
The application wants to wait for a message for up to one second.
Under the current API, it must choose indefinite `Receive` or repeated calls to `Try_Receive`.
It cannot pass a timeout to `Receive`.

### Proposed behavior and reason

I recommend adding an optional `Receive (S, Msg, Timeout, Success)` operation.
Keep the existing blocking and immediate operations.
The timed operation lets callers periodically check shutdown requests or perform other work.

Proposed contract:

- Timeout must be nonnegative.
- A zero timeout performs one immediate `Try_Receive` attempt.
- Success is True only when the operation removes one message.
- If no message becomes available before timeout selection, Success is False.
- The caller must ignore Msg when Success is False.
- A failed receive must not consume a message that arrives later.

For example, a message available after 0.2 seconds should satisfy a one-second wait.
An empty queue throughout that wait should produce False.
Timeout describes the waiting behavior, not an exact wall-clock completion deadline.
Tests must allow documented scheduling tolerance at the timeout boundary.

The implementation must preserve the core's supported runtime profiles.
If timed entry calls are unavailable on a target profile, isolate the feature in an optional package.
Confirm the compiler and runtime restrictions before selecting the implementation.

### Future test checks

- Verify that an already queued message returns with True and decreases Pending by one.
- Verify that an empty queue times out with False.
- Publish before the deadline and verify the caller receives the correct message.
- After a timeout, publish a message and verify a later receive can obtain it.
- Verify zero-time behavior on both empty and nonempty queues.
- Verify that negative timeouts violate the chosen contract without consuming data.
- Retest existing Receive and Try_Receive behavior and supported runtime builds.

These checks describe the proposed API.
They require the timed overload before they can be implemented as executable tests.

## 4. Dangling subscriber access

### Current behavior

The registry references the caller's Subscriber object; it does not copy the object.
The subscriber must remain alive while any operation can access it.
The current API has no unregister operation.
A subscriber that ends its lifetime too early can leave an invalid registry reference.
No crash, exception, or successful delivery is a valid guaranteed outcome after that contract violation.

### Example scenario

A nested scope creates and registers an aliased subscriber.
The scope ends while the topic remains available.
A later Publish still finds the subscriber's registry entry.
In the current design, this use violates the documented lifetime rule.

### Proposed behavior and reason

I recommend storing a fixed set of protected queue slots within the topic instantiation.
Let a Subscriber hold a handle identifying a slot.
Allocate slots during startup and keep them alive for the run.
The registry would no longer point to caller-owned Subscriber records.

Design rule 3: queue depth and subscriber capacity remain bounded.
The redesign must not allocate growing storage or add heap allocation to the core.
The design must preserve each subscriber's Reliable or Best_Effort mode.
The team must review how slot representation preserves the mode before implementation.

If a caller's handle leaves scope, the slot remains allocated.
This prevents a dangling pointer, but it does not remove the subscription.
A Reliable slot without a reader can still fill and block Publish.
Callers must therefore keep servicing Reliable subscriptions for the run.

This proposal does not add slot release or reuse.
Dynamic teardown would require coordination with all in-flight operations.
A protected registry alone does not solve subscriber lifetime.

### Future test checks

- Register through a nested-scope handle, then end that handle's scope.
- Verify that subsequent access uses topic-owned storage rather than a destroyed caller object.
- Use a Best_Effort slot for this scenario so an unread full queue cannot hang the test.
- Verify that a departed handle's slot still counts against fixed capacity.
- Verify that invalid or unregistered handles are rejected before queue access.
- Verify Reliable backpressure, Best_Effort drop-oldest behavior, and per-subscriber queue independence.
- Verify that a full unread Reliable slot still follows the documented blocking behavior.

Do not use the current dangling-reference design to run this proposed lifetime-safety test.
Add it only after the ownership redesign supplies the required guarantees.
