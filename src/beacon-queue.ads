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

generic
   type Element_Type is private;
   Depth : Positive;
package Beacon.Queue
  with SPARK_Mode => On
is

   type Queue_Type is private;

   Empty_Queue : constant Queue_Type;
   --  The only correct initial value. The element slots are not
   --  initialized, because Element_Type may have no default value. The
   --  queue reads only the slots that hold elements.

   function Count (Q : Queue_Type) return Natural
     with Post => Count'Result <= Depth;

   function Is_Empty (Q : Queue_Type) return Boolean is (Count (Q) = 0);
   function Is_Full  (Q : Queue_Type) return Boolean is (Count (Q) = Depth);

   --  Used for Reliable delivery. The caller must make sure that Q is not
   --  full.
   procedure Push (Q : in out Queue_Type; Item : Element_Type)
     with Pre  => not Is_Full (Q),
          Post => Count (Q) = Count (Q'Old) + 1;

   --  Used for Best_Effort delivery. If Q is full, the oldest element is
   --  removed first and Dropped is True. This procedure never fails and
   --  never blocks.
   procedure Push_Dropping_Oldest
     (Q       : in out Queue_Type;
      Item    : Element_Type;
      Dropped : out Boolean)
     with Post => Dropped = Is_Full (Q'Old)
                  and then Count (Q) = Natural'Min (Count (Q'Old) + 1, Depth);

   procedure Pop (Q : in out Queue_Type; Item : out Element_Type)
     with Pre  => not Is_Empty (Q),
          Post => Count (Q) = Count (Q'Old) - 1;

private

   subtype Ring_Index is Natural range 0 .. Depth - 1;

   type Element_Array is array (Ring_Index) of Element_Type;

   type Queue_Type is record
      Buffer : Element_Array;
      Head   : Ring_Index := 0;   --  next slot to Pop
      Tail   : Ring_Index := 0;   --  next slot to Push
      Fill   : Natural range 0 .. Depth := 0;
   end record;
   --  Invariant for the proof:
   --    Tail = (Head + Fill) mod Depth
   --  Buffer is not initialized (see Empty_Queue). The queue reads only
   --  the slots Head .. Head + Fill - 1 (mod Depth). The proof will
   --  probably need Relaxed_Initialization on Buffer to state this.

   function Count (Q : Queue_Type) return Natural is (Q.Fill);

   pragma Warnings (Off, "component ""Buffer"" of type ""Element_Array"" is uninitialized");
   Empty_Queue : constant Queue_Type := (Buffer => <>, Head => 0, Tail => 0, Fill => 0);
   pragma Warnings (On, "component ""Buffer"" of type ""Element_Array"" is uninitialized");
   --  Buffer is not initialized on purpose. See the comment on Empty_Queue.

end Beacon.Queue;
