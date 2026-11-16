# Proof demo

This demo shows that the SPARK proof of `Beacon.Queue` finds bugs. Each
bug below is a small change in `src/beacon-queue.adb`. GNATprove fails
on each bug. No test has to run.

## The proof harness

GNATprove proves a generic package only through an instance of it. The
instance `Queue_Proof.Any` gets a `Depth` that the prover does not know,
so its proof holds for each `Depth` from 1 to `Positive'Last`.

## Run the demo

Do these steps in the `prove/` directory.

1. Run the proof on the correct code before the demo. GNATprove keeps
   the results, so the next runs are faster.

   ```sh
   alr -n exec -- gnatprove -P beacon_prove.gpr --mode=all --checks-as-errors=on
   ```

2. Make the change for one bug in `src/beacon-queue.adb`.
3. Run the same command again. Show the message.
4. Remove the change:

   ```sh
   git restore ../src/beacon-queue.adb
   ```

For a demo of 3 minutes, show bug 4 and bug 5. Bug 4 passes the Silver
proof, and only a functional contract finds it. Bug 5 passes all of the
tests.

A run with a bug takes about 35 seconds. GNATprove reuses the results of
an earlier run of the same code. Thus, if you run each bug once before
the demo, each run in the demo takes about 5 seconds.

## Planted bugs

| Bug                                        | Check that fails                           | Do the tests find it?      |
| ------------------------------------------ | ------------------------------------------ | -------------------------- |
| 1. Drop-oldest does not move the head      | Type invariant                             | Yes: a postcondition fails |
| 2. `Pop` reads the wrong slot              | Initialization and the `Pop` postcondition | Yes: a postcondition fails |
| 3. The ring does not wrap                  | The compiler rejects `Queue_Proof.One`     | The tests do not compile   |
| 4. Drop-oldest drops the newest            | The `Push_Dropping_Oldest` postcondition   | Yes: a postcondition fails |
| 5. `Push` computes `Tail` with an overflow | Overflow                                   | No                         |

The tests find bugs 1, 2 and 4 only through the contracts. The tests
compile with `-gnata`, so each postcondition runs at each call.

A `medium` message means that GNATprove cannot prove the check. When
GNATprove finds values that make the check fail, it shows them after
`e.g. when`.

### 1. Drop-oldest does not move the head

```diff
       if Dropped then
          --  Overwrite the oldest element: move Head past it. Fill does not change.
-         Q.Head := Next (Q.Head);
          Q.Buffer (Q.Tail) := Item;
```

```text
 medium: invariant check might fail, cannot prove Is_Valid (Queue_Type), in instantiation at queue_proof-any.ads:8
--> beacon-queue.ads:63:14
   63 |       procedure Push_Dropping_Oldest
      |                 ^
      + in inlined invariant at beacon-queue.ads:97, in instantiation at queue_proof-any.ads:8
      + for "Q" at the end of "Push_Dropping_Oldest" at beacon-queue.ads:64, in instantiation at queue_proof-any.ads:8
      + provers reached time limit before completing the proof
```

### 2. `Pop` reads the wrong slot

```diff
-      Item := Q.Buffer (Q.Head);
+      Item := Q.Buffer (Q.Tail);
```

```text
 medium: postcondition might fail, cannot prove Item = Element_At (Q'Old, 1), in instantiation at queue_proof-any.ads:8
--> beacon-queue.ads:80:28
   80 |                      and then Item = Element_At (Q'Old, 1)
      |                               ^~~~~~~~~~~~~~~~~~~~~~~~~~~
      + provers reached time limit before completing the proof

 medium: initialization check might fail, in instantiation at queue_proof-any.ads:8
--> beacon-queue.adb:34:16
   34 |          Item := Q.Buffer (Q.Tail);
      |                  ~^~~~~~~~~~~~
      + e.g. when Q = (Buffer => ?, Head => 0, Tail => 1, Fill => 1)
      and Q.Buffer'First = 0
      and Q.Buffer'Last = 1
      + provers reached time limit before completing the proof
```

### 3. The ring does not wrap

```diff
    function Next (I : Ring_Index) return Ring_Index is
-     ((I + 1) mod Depth);
+     (I + 1);
```

The compiler finds this bug before the proof starts. In
`Queue_Proof.One`, `Depth` is 1, so `I + 1` is always 1. The value 1 is
not in `Ring_Index`.

```text
 error: instantiation error at beacon-queue.adb:6
--> queue_proof-one.ads:8:01
    8 |    package Queue_Proof.One is new Beacon.Queue (Element_Type => Integer, Depth => 1);
      |    ^
      + value not in range of type "Ring_Index" defined at beacon-queue.ads:86, instance at line 8
      + Constraint_Error would have been raised at run time
```

### 4. Drop-oldest drops the newest

```diff
       if Dropped then
          --  Overwrite the oldest element: move Head past it. Fill does not change.
-         Q.Head := Next (Q.Head);
-         Q.Buffer (Q.Tail) := Item;
-         Q.Tail := Next (Q.Tail);
+         Q.Buffer (if Q.Tail = 0 then Depth - 1 else Q.Tail - 1) := Item;
```

The queue stays valid, so the Silver proof passes. Only the
`Push_Dropping_Oldest` postcondition fails.

```text
 medium: postcondition might fail, cannot prove Element_At (Q, K) = Element_At (Q'Old, (if Dropped then K + 1 else K)), in instantiation at queue_proof-any.ads:8
--> beacon-queue.ads:71:31
   71 |                                  Element_At (Q, K) =
      |                                  ^~~~~~~~~~~~~~~~~~~
   72 |                                    Element_At (Q'Old, (if Dropped then K + 1 else K)));
      |                                    ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
      + provers reached time limit before completing the proof
```

### 5. `Push` computes `Tail` with an overflow

```diff
       Q.Buffer (Q.Tail) := Item;
-      Q.Tail := Next (Q.Tail);
+      Q.Tail := (Q.Head + Q.Fill + 1) mod Depth;
       Q.Fill := Q.Fill + 1;
```

The new line gives the correct slot, but `Q.Head + Q.Fill + 1` can be
more than `Integer'Last`. The tests and the demos use a `Depth` of 32
or less. Thus, all of them pass. `Queue_Proof.Any` finds the overflow
at `Depth = Positive'Last`.

```text
 medium: overflow check might fail, cannot prove upper bound for Q.Head + Q.Fill, in instantiation at queue_proof-any.ads:8
--> beacon-queue.adb:11:25
   11 |          Q.Tail := (Q.Head + Q.Fill + 1) mod Depth;
      |                     ~~~~~~~^~~~~
      + reason for check: result of addition must fit in a 32-bits machine integer
      + provers reached time limit before completing the proof

 medium: overflow check might fail, cannot prove upper bound for (Q.Head + Q.Fill + 1), in instantiation at queue_proof-any.ads:8
--> beacon-queue.adb:11:34
   11 |          Q.Tail := (Q.Head + Q.Fill + 1) mod Depth;
      |                     ~~~~~~~~~~~~~~~~^~~
      + e.g. when Depth = Positive'Last
      and Q = (Buffer => ?, Head => Integer'Last-1, Tail => 0, Fill => 1)
      and Q.Buffer'First = 0
      and Q.Buffer'Last = Integer'Last-1
      + reason for check: result of addition must fit in a 32-bits machine integer
      + provers reached time limit before completing the proof
```

## CI run

The branch `gg/proof-demo-bug` has bug 5. It does not merge. In its CI
run, the build, the tests and the demos pass, and the step "SPARK proof
of Beacon.Queue" fails:
<https://github.com/ge-garcia/beacon/actions/runs/43113090094/job/130833967307>
