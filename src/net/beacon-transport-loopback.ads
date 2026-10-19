with Beacon.Queue;

package Beacon.Transport.Loopback is

   Capacity : constant := 16;
   Queue_Full : exception renames Would_Block;

   type Loopback_Transport is limited new Transport with private;

   --  Copies one datagram into the FIFO; raises Queue_Full without blocking
   --  when full, or Constraint_Error unless its length is in 1 .. Max_Frame.
   overriding procedure Send
     (T : in out Loopback_Transport; Frame : Wire.Byte_Array);

   --  Removes one datagram, or returns Count = 0 after Timeout (nonpositive
   --  means poll). An undersized buffer discards it and raises Constraint_Error.
   overriding procedure Receive
     (T       : in out Loopback_Transport;
      Frame   : out Wire.Byte_Array;
      Count   : out Natural;
      Timeout : Duration);

private

   type Datagram is record
      Bytes  : Wire.Byte_Array (1 .. Wire.Max_Frame) := [others => 0];
      Length : Natural range 0 .. Wire.Max_Frame := 0;
   end record;

   package Ring is new Beacon.Queue (Datagram, Capacity);

   protected type Mailbox is
      procedure Put (Item : Datagram);
      entry Get (Item : out Datagram);
   private
      Q : Ring.Queue_Type := Ring.Empty_Queue;
   end Mailbox;

   type Loopback_Transport is limited new Transport with record
      Inbox : Mailbox;
   end record;

end Beacon.Transport.Loopback;
