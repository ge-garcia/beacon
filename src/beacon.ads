--  Beacon: typed publish-subscribe messaging.
--
--  Package map. Each package depends only on the packages below it.
--
--     Beacon.Topic  (generic)      typed Publisher and Subscriber, protected queue, registry
--          |
--     Beacon.Queue  (generic)      bounded ring buffer, no tasking     [SPARK proof target]
--          |
--     Beacon                       Delivery_Mode
--
--     -- src/net/: desktop only. The packages above never refer to these. --
--
--     Beacon.Bridge (generic)      connects one Topic instance to a Transport
--          |              |
--     Beacon.Wire      Beacon.Transport         frame header (rep clause)   Send/Receive interface
--                          |
--                      Beacon.Transport.UDP     UDP multicast (GNAT.Sockets)
--
--  The design rules are listed in README.md. Comments refer to them by number.
--
--  Design rule 1: a message never crosses the public API as bytes.
--  Only Beacon.Wire and Beacon.Bridge use bytes, and only to send a
--  frame to a socket or to read a frame from a socket.

package Beacon
  with Pure, SPARK_Mode => On
is

   --  Design rule 2: the delivery mode is part of the subscriber type.
   --    Reliable     When the queue is full, Publish blocks and
   --                 Try_Publish reports the refusal. Beacon.Topic never
   --                 drops a message for a Reliable subscriber.
   --    Best_Effort  When the queue is full, the OLDEST message is dropped
   --                 to make room. Dropped counts each drop.
   type Delivery_Mode is (Reliable, Best_Effort);

end Beacon;
