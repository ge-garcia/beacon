--  Beacon.Bridge: connects one Beacon.Topic instantiation to a Transport.
--
--  This is how "the network backend" works without touching
--  Beacon.Topic: a bridge is just another participant on the local
--  topic. Egress subscribes locally and forwards every message as a
--  frame. Ingress receives frames and publishes them locally.
--
--     process A                              process B
--     app Publisher -> Topic -> Egress ~~UDP~~> Ingress -> Topic -> app Subscriber
--
--  Consequences to notice:
--    * Ingress is the local Publisher on the receiving side, so an
--      application in process B cannot also publish on that topic
--      (single writer). That is intended.
--    * Delivery mode across the wire is whatever the Egress subscriber
--      was created with. Reliable egress can block the local publisher
--      if the network cannot keep up; UDP itself is still lossy. The
--      final report must be honest about this (compare to DDS RELIABLE).
--
--  Serialize/Deserialize are the only place Message_Type meets bytes.
--  They are supplied per instantiation, expected to be an overlay of a
--  record with a representation clause (design rule 6), not hand-packing.
--
--  One egress and one ingress per instantiation, each a task started
--  on demand. Stop asks both to finish; they exit after their current
--  operation (Ingress polls at 100 ms, idle Egress at 1 ms). Keep the
--  transport alive until the tasks terminate; Stop does not join them.

with Beacon.Topic;
with Beacon.Wire;
with Beacon.Transport;

generic
   with package Local is new Beacon.Topic (<>);
   Topic_Id : Wire.Topic_Id_Type;
   with procedure Serialize
     (Msg    : Local.Message_Type;
      Buffer : out Wire.Byte_Array;
      Last   : out Natural);
   with procedure Deserialize
     (Buffer : Wire.Byte_Array;
      Msg    : out Local.Message_Type;
      Valid  : out Boolean);
package Beacon.Bridge is

   --  Forward local publications to T. Registers a local Subscriber in
   --  Mode; counts toward Max_Subscribers. Registered before this returns.
   --  Transient transport saturation retries the same frame until sent or Stop.
   procedure Start_Egress
     (T    : not null access Transport.Transport'Class;
      Mode : Delivery_Mode)
     with Pre => Local.Subscriber_Count < Local.Max_Subscribers;

   --  Publish frames arriving on T (with matching Topic_Id) locally.
   --  Takes the local Publisher slot before this returns.
   procedure Start_Ingress
     (T : not null access Transport.Transport'Class)
     with Pre => not Local.Has_Publisher;

   procedure Stop;

   --  Frames received with a bad status or a foreign Topic_Id.
   function Rejected_Frames return Natural;

   --  Ingress frames whose Sequence was not previous + 1. This is the
   --  "how lossy is UDP really" number for the report.
   function Sequence_Gaps return Natural;

end Beacon.Bridge;
