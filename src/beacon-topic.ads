--  Beacon.Topic: one instantiation for each message type.
--
--     package Telemetry_Topic is new Beacon.Topic
--       (Message_Type => Telemetry_Reading, Queue_Depth => 32);
--
--  A publisher sends only Message_Type values, and a subscriber receives
--  only Message_Type values. No other path exists (design rule 1).
--
--  Static model (design rule 4): each instantiation has a fixed table of
--  Max_Subscribers entries. Rules for the user:
--    * Register each subscriber at startup, before the first Publish.
--    * Register from one task only. Registration is not task-safe.
--  Publishing is task-safe.
--
--  Single writer: each instantiation has one Publisher. Create_Publisher
--  refuses a second one.
--
--  Runtime: this package needs protected types with entries. Use a
--  light-tasking (Ravenscar or Jorvik) or full runtime. A ZFP runtime
--  cannot host this package; use Beacon.Queue directly on ZFP.

with Beacon.Queue;

generic
   type Message_Type is private;
   Queue_Depth     : Positive;
   Max_Subscribers : Positive := 8;
package Beacon.Topic is

   type Publisher is limited private;
   type Subscriber (Mode : Delivery_Mode) is limited private;

   ---------------
   -- Publisher --
   ---------------

   function Has_Publisher return Boolean;
   function Is_Created (P : Publisher) return Boolean;

   procedure Create_Publisher (P : in out Publisher)
     with Pre  => not Has_Publisher and then not Is_Created (P),
          Post => Has_Publisher and then Is_Created (P);

   --  Sends Msg to each registered subscriber, in registration order.
   --  Reliable subscriber with a full queue: Publish blocks until the
   --  queue has room.
   --  Best_Effort subscriber with a full queue: the oldest message is
   --  dropped and counted.
   procedure Publish (P : Publisher; Msg : Message_Type)
     with Pre => Is_Created (P);

   --  Sends Msg to each registered subscriber that has room, and does not
   --  block. Delivered is False if one or more Reliable subscribers were
   --  full. Those subscribers do not get Msg. All other subscribers get
   --  Msg (partial delivery).
   --  Open decision (README, Week 4): keep partial delivery, or change to
   --  all-or-nothing. Partial delivery is simpler and is the same as the
   --  per-reader queues of DDS.
   procedure Try_Publish
     (P         : Publisher;
      Msg       : Message_Type;
      Delivered : out Boolean)
     with Pre => Is_Created (P);

   ----------------
   -- Subscriber --
   ----------------

   function Subscriber_Count return Natural
     with Post => Subscriber_Count'Result <= Max_Subscribers;

   function Is_Registered (S : Subscriber) return Boolean;

   --  S must exist until the last Publish. Declare S at library level, or
   --  in the scope that contains the full run. The registry uses no heap,
   --  so it does not copy S.
   procedure Create_Subscriber (S : aliased in out Subscriber)
     with Pre  => Subscriber_Count < Max_Subscribers
                  and then not Is_Registered (S),
          Post => Subscriber_Count = Subscriber_Count'Old + 1
                  and then Is_Registered (S);

   --  If S is empty, Receive blocks until a message arrives.
   procedure Receive (S : in out Subscriber; Msg : out Message_Type)
     with Pre => Is_Registered (S);

   procedure Try_Receive
     (S       : in out Subscriber;
      Msg     : out Message_Type;
      Success : out Boolean)
     with Pre => Is_Registered (S);

   --  Number of messages in the queue of S.
   function Pending (S : Subscriber) return Natural;

   --  Number of messages that the queue of S has dropped since startup.
   --  This value is always 0 for a Reliable subscriber. This is the
   --  check for design rule 2.
   function Dropped (S : Subscriber) return Natural;

private

   package Ring is new Beacon.Queue (Message_Type, Queue_Depth);

   protected type Bounded_Queue (Mode : Delivery_Mode) is
      --  Push barrier: always open for Best_Effort. Open when not full
      --  for Reliable.
      entry Push (Msg : Message_Type);
      procedure Try_Push (Msg : Message_Type; Accepted : out Boolean);
      entry Pop (Msg : out Message_Type);
      procedure Try_Pop (Msg : out Message_Type; Success : out Boolean);
      function Count return Natural;
      function Drop_Count return Natural;
   private
      Q     : Ring.Queue_Type := Ring.Empty_Queue;
      Drops : Natural := 0;
   end Bounded_Queue;

   type Subscriber (Mode : Delivery_Mode) is limited record
      Queue      : Bounded_Queue (Mode);
      Registered : Boolean := False;
   end record;

   type Publisher is limited record
      Created : Boolean := False;
   end record;

end Beacon.Topic;
