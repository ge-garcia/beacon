--  Beacon: typed publish-subscribe messaging.
--
--  Package map (dependencies point downward only):
--
--     Beacon.Topic  (generic)      typed Publisher/Subscriber, protected queue, static registry
--          |
--     Beacon.Queue  (generic)      pure bounded ring buffer            [SPARK proof target]
--
--     -- src/net/, desktop only, never referenced by the two above --
--
--     Beacon.Bridge (generic)      links one Topic instance to a Transport
--          |              |
--     Beacon.Wire      Beacon.Transport         frame header (rep clauses)   send/receive interface
--                          |
--                      Beacon.Transport.UDP     GNAT.Sockets multicast
--
--  The design rules are listed in README.md. Comments refer to them by number.
--
--  Design rule 1: a message type never crosses the public API as bytes.
--  Bytes exist only inside Beacon.Wire and Beacon.Bridge, and only on
--  their way to or from a socket.

package Beacon
  with Pure, SPARK_Mode => On
is

   --  Design rule 2: delivery mode is part of the subscriber's type.
   --    Reliable    a full queue blocks the publisher (or Try_Publish
   --                reports it). Nothing is ever dropped.
   --    Best_Effort a full queue drops the OLDEST queued message to make
   --                room. Drops are counted and observable.
   type Delivery_Mode is (Reliable, Best_Effort);

end Beacon;
