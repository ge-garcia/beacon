--  Beacon.Queue: bounded FIFO ring buffer. SPARK proof target (Silver).
--
--  This package is plain data. It has no tasking, no protection, and no
--  I/O. Beacon.Topic puts one queue in each protected object. The ring
--  arithmetic is here, outside the protected type, so that the proof is
--  small and does not depend on the tasking runtime.
--
--  Design rule 3: Depth is fixed at instantiation. The queue does not
--  grow and does not use the heap.
--
--  The proposal used `type Ring_Index is mod Queue_Depth`. That is not
--  legal Ada: a modulus must be static, and a generic formal object is
--  not static. Ring_Index is a Natural subtype instead, and Next uses an
--  explicit `mod Depth`.
--
--  The postconditions state Count and the elements in the queue, through
--  the ghost function Element_At. The proof shows FIFO order and
--  drop-oldest.

generic
   type Element_Type is private;
   Depth : Positive;
package Beacon.Queue
  with SPARK_Mode => On
is

   type Queue_Type is private;

   Empty_Queue : constant Queue_Type;
   --  The only correct initial value. Each object of Queue_Type must start
   --  as Empty_Queue. The element slots are not initialized, because
   --  Element_Type may have no default value. The queue reads only the
   --  slots that hold elements.

   --  Number of elements in Q.
   function Count (Q : Queue_Type) return Natural
     with Post => Count'Result <= Depth;

   function Is_Empty (Q : Queue_Type) return Boolean is (Count (Q) = 0);
   function Is_Full  (Q : Queue_Type) return Boolean is (Count (Q) = Depth);

   --  The K-th oldest element of Q. Element_At (Q, 1) is the next element
   --  that Pop returns. Element_At (Q, Count (Q)) is the newest element.
   --  Only contracts and other ghost code can call it.
   function Element_At (Q : Queue_Type; K : Positive) return Element_Type
     with Ghost,
          Pre => K <= Count (Q);

   --  Adds Item at the tail. Used for Reliable delivery. The caller must
   --  make sure that Q is not full. The elements already in Q do not
   --  change.
   procedure Push (Q : in out Queue_Type; Item : Element_Type)
     with Pre  => not Is_Full (Q),
          Post => Count (Q) = Count (Q'Old) + 1
                  and then Element_At (Q, Count (Q)) = Item
                  and then (for all K in 1 .. Count (Q'Old) =>
                              Element_At (Q, K) = Element_At (Q'Old, K));

   --  Adds Item at the tail. Used for Best_Effort delivery. If Q is full,
   --  the oldest element is removed first and Dropped is True. This
   --  procedure always adds Item. All other elements stay in Q, in the
   --  same order.
   procedure Push_Dropping_Oldest
     (Q       : in out Queue_Type;
      Item    : Element_Type;
      Dropped : out Boolean)
     with Post => Dropped = Is_Full (Q'Old)
                  and then Count (Q) = (if Dropped then Count (Q'Old) else Count (Q'Old) + 1)
                  and then Element_At (Q, Count (Q)) = Item
                  and then (for all K in 1 .. Count (Q) - 1 =>
                              Element_At (Q, K) =
                                Element_At (Q'Old, (if Dropped then K + 1 else K)));

   --  Removes the oldest element and returns it in Item. The caller must
   --  make sure that Q is not empty. All other elements stay in Q, in the
   --  same order.
   procedure Pop (Q : in out Queue_Type; Item : out Element_Type)
     with Pre  => not Is_Empty (Q),
          Post => Count (Q) = Count (Q'Old) - 1
                  and then Item = Element_At (Q'Old, 1)
                  and then (for all K in 1 .. Count (Q) =>
                              Element_At (Q, K) = Element_At (Q'Old, K + 1));

private

   subtype Ring_Index is Natural range 0 .. Depth - 1;

   type Element_Array is array (Ring_Index) of Element_Type
     with Relaxed_Initialization;

   type Queue_Type is record
      Buffer : Element_Array;
      Head   : Ring_Index := 0;   --  next slot to Pop
      Tail   : Ring_Index := 0;   --  next slot to Push
      Fill   : Natural range 0 .. Depth := 0;
   end record
     with Type_Invariant => Is_Valid (Queue_Type);
   --  Invariant for the proof (Is_Valid):
   --    Tail = (Head + Fill) mod Depth
   --    The slots Head .. Head + Fill - 1 (mod Depth) are initialized.
   --  Buffer is not initialized (see Empty_Queue). The queue reads only
   --  these slots.

   --  Number of steps from slot From forward to slot To, with wraparound.
   --  It has no mod and cannot overflow.
   function Distance (From, To : Ring_Index) return Natural is
     (if From <= To then To - From else To + (Depth - From))
     with Ghost;

   --  True if slot I holds an element of Q.
   function Is_Occupied (Q : Queue_Type; I : Ring_Index) return Boolean is
     (Distance (Q.Head, I) < Q.Fill)
     with Ghost;

   function Is_Valid (Q : Queue_Type) return Boolean is
     (Distance (Q.Head, Q.Tail) = (if Q.Fill = Depth then 0 else Q.Fill)
      and then (for all I in Ring_Index =>
                  (if Is_Occupied (Q, I) then Q.Buffer (I)'Initialized)))
     with Ghost;

   --  The slot of the K-th oldest element: Head + K - 1, with
   --  wraparound. It has no mod and cannot overflow.
   function Slot (Q : Queue_Type; K : Positive) return Ring_Index is
     (if K - 1 < Depth - Q.Head then Q.Head + (K - 1) else (K - 1) - (Depth - Q.Head))
     with Ghost,
          Pre => K <= Depth;

   function Count (Q : Queue_Type) return Natural is (Q.Fill);

   function Element_At (Q : Queue_Type; K : Positive) return Element_Type is
     (Q.Buffer (Slot (Q, K)));

   pragma Warnings (Off, "component ""Buffer"" of type ""Element_Array"" is uninitialized");
   Empty_Queue : constant Queue_Type := (Buffer => <>, Head => 0, Tail => 0, Fill => 0);
   pragma Warnings (On, "component ""Buffer"" of type ""Element_Array"" is uninitialized");
   --  Buffer is not initialized on purpose. See the comment on Empty_Queue.

end Beacon.Queue;
