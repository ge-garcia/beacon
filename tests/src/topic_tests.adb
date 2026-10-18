--  Tests for Beacon.Topic. Owner: validation engineer. Green by Week 8.
--  The Week 8 review question, verbatim: fill a reliable queue past
--  capacity and verify the documented behavior actually occurs.

with Ada.Command_Line;
with Ada.Text_IO;  use Ada.Text_IO;
with Beacon;       use Beacon;
with Beacon.Topic;

procedure Topic_Tests is

   Failures : Natural := 0;

   procedure Check (Cond : Boolean; Name : String);
   procedure Check (Cond : Boolean; Name : String) is
   begin
      if Cond then
         Put_Line ("  ok    " & Name);
      else
         Put_Line ("  FAIL  " & Name);
         Failures := Failures + 1;
      end if;
   end Check;

   type Reading is record
      Id    : Natural;
      Value : Float;
   end record;

   Depth : constant := 3;
   package T is new Beacon.Topic
     (Message_Type => Reading, Queue_Depth => Depth, Max_Subscribers => 2);

   --  A second topic with only a Best_Effort subscriber, so that Publish
   --  can fill the queue without blocking.
   package BE_Topic is new Beacon.Topic
     (Message_Type => Reading, Queue_Depth => Depth, Max_Subscribers => 1);

   Pub       : T.Publisher;
   Rel       : aliased T.Subscriber (Reliable);
   Best      : aliased T.Subscriber (Best_Effort);
   BE_Pub    : BE_Topic.Publisher;
   BE_Sub    : aliased BE_Topic.Subscriber (Best_Effort);
   Msg       : Reading;
   Got       : Boolean;
   Delivered : Boolean;
   In_Order  : Boolean;

begin
   Put_Line ("Beacon.Topic tests");

   T.Create_Publisher (Pub);
   T.Create_Subscriber (Rel);
   T.Create_Subscriber (Best);
   Check (T.Subscriber_Count = 2, "two subscribers registered");

   --  Fan-out: one publish, both receive the same typed value.
   T.Publish (Pub, (Id => 1, Value => 1.5));
   T.Receive (Rel, Msg);
   Check (Msg.Id = 1, "reliable subscriber receives typed value");
   T.Receive (Best, Msg);
   Check (Msg.Value = 1.5, "best-effort subscriber receives typed value");

   --  Fill both to capacity without draining.
   for I in 1 .. Depth loop
      T.Publish (Pub, (Id => I, Value => 0.0));
   end loop;
   Check (T.Pending (Rel) = Depth and then T.Pending (Best) = Depth,
          "both queues full");

   --  Overflow: Try_Publish must NOT block, must report the reliable
   --  refusal, and the best-effort side must drop its oldest.
   T.Try_Publish (Pub, (Id => 99, Value => 0.0), Delivered);
   Check (not Delivered, "reliable full: Try_Publish reports not delivered");
   Check (T.Pending (Rel) = Depth and then T.Dropped (Rel) = 0,
          "reliable: nothing dropped, nothing added");
   Check (T.Dropped (Best) = 1, "best-effort: exactly one drop counted");
   T.Receive (Best, Msg);
   Check (Msg.Id = 2, "best-effort: oldest (1) gone, 2 is now first");

   --  Reliable never lost anything: drain and check order.
   for Expected in 1 .. Depth loop
      T.Receive (Rel, Msg);
      if Msg.Id /= Expected then
         Failures := Failures + 1;
         Put_Line ("  FAIL  reliable order");
      end if;
   end loop;
   T.Try_Receive (Rel, Msg, Got);
   Check (not Got, "reliable drained, Try_Receive says empty");

   --  Publish on a full Best_Effort queue. Publish uses the Push entry,
   --  not the Try_Push procedure that Try_Publish uses. If Publish
   --  blocks, this test does not end.
   BE_Topic.Create_Publisher (BE_Pub);
   BE_Topic.Create_Subscriber (BE_Sub);
   for I in 1 .. Depth + 2 loop
      BE_Topic.Publish (BE_Pub, (Id => I, Value => 0.0));
   end loop;
   Check (BE_Topic.Pending (BE_Sub) = Depth and then BE_Topic.Dropped (BE_Sub) = 2,
          "best-effort full: Publish does not block and counts each drop");
   BE_Topic.Try_Publish (BE_Pub, (Id => Depth + 3, Value => 0.0), Delivered);
   Check (Delivered and then BE_Topic.Dropped (BE_Sub) = 3,
          "all subscribers best-effort: Try_Publish reports delivered");

   --  Try_Receive on a queue that holds messages. The queue holds the
   --  newest Depth messages.
   In_Order := True;
   for Expected in Depth + 1 .. Depth + 3 loop
      BE_Topic.Try_Receive (BE_Sub, Msg, Got);
      In_Order := In_Order and then Got and then Msg.Id = Expected
                  and then BE_Topic.Pending (BE_Sub) = Depth + 3 - Expected;
   end loop;
   Check (In_Order, "Try_Receive returns the oldest, Pending decreases by 1");

   --  TODO (weeks 5-8): blocking Publish on a full Reliable queue, from a
   --  separate task, verified to unblock when the subscriber drains.
   --  TODO (weeks 9-12): load test, N publishers tasks, sustained
   --  overflow, assert Dropped (Rel) = 0 at the end. Always.

   New_Line;
   if Failures = 0 then
      Put_Line ("all passed");
   else
      Put_Line (Natural'Image (Failures) & " failure(s)");
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;
end Topic_Tests;
