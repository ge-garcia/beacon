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

   --  A full Reliable queue must block Publish until Receive frees a slot.
   declare
      package R_Topic is new Beacon.Topic
        (Message_Type => Reading, Queue_Depth => Depth, Max_Subscribers => 1);

      R_Pub    : R_Topic.Publisher;
      R_Sub    : aliased R_Topic.Subscriber (Reliable);
      Started  : Boolean := False;
      Finished : Boolean := False;

      task Blocked_Publisher is
         entry Start;
         entry Done;
      end Blocked_Publisher;

      task body Blocked_Publisher is
      begin
         accept Start;
         R_Topic.Publish (R_Pub, (Id => Depth + 1, Value => Float (Depth + 1)));
         accept Done;
      end Blocked_Publisher;
   begin
      R_Topic.Create_Publisher (R_Pub);
      R_Topic.Create_Subscriber (R_Sub);
      for I in 1 .. Depth loop
         R_Topic.Publish (R_Pub, (Id => I, Value => Float (I)));
      end loop;
      Check (R_Topic.Pending (R_Sub) = Depth, "reliable queue filled for blocking Publish");

      select
         Blocked_Publisher.Start;
         Started := True;
      or
         delay 1.0;
         Check (False, "reliable publisher starts");
      end select;

      if Started then
         --  The publisher accepts Done only after Publish returns. A timeout
         --  here shows that the full queue keeps the publisher waiting.
         select
            Blocked_Publisher.Done;
            Finished := True;
            Check (False, "reliable full: Publish blocks");
         or
            delay 0.1;
            Check (True, "reliable full: Publish blocks");
         end select;

         if R_Topic.Pending (R_Sub) > 0 then
            R_Topic.Receive (R_Sub, Msg);
            Check (Msg = (Id => 1, Value => 1.0),
                   "reliable: first value frees a slot");
         else
            Check (False, "reliable: first value frees a slot");
         end if;

         if not Finished then
            select
               Blocked_Publisher.Done;
               Finished := True;
               Check (True, "reliable: Publish resumes after Receive");
            or
               delay 1.0;
               Check (False, "reliable: Publish resumes after Receive");
            end select;
         end if;

         In_Order := True;
         for Expected in 2 .. Depth + 1 loop
            R_Topic.Try_Receive (R_Sub, Msg, Got);
            In_Order := In_Order and then Got
              and then Msg = (Id => Expected, Value => Float (Expected));
         end loop;
         Check (In_Order and then R_Topic.Pending (R_Sub) = 0,
                "reliable blocked Publish preserves exact FIFO order");
         Check (R_Topic.Dropped (R_Sub) = 0, "reliable blocked Publish drops nothing");
      end if;

      if not Finished then
         abort Blocked_Publisher;
      end if;
   end;

   New_Line;
   if Failures = 0 then
      Put_Line ("all passed");
   else
      Put_Line (Natural'Image (Failures) & " failure(s)");
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;
end Topic_Tests;
