--  Tests for Beacon.Topic. Owner: validation engineer. Green by Week 8.
--  The Week 8 review question, verbatim: fill a reliable queue past
--  capacity and verify the documented behavior actually occurs.

pragma Initialize_Scalars;

with Ada.Assertions;
with Ada.Command_Line;
with Ada.Real_Time; use Ada.Real_Time;
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
   Result    : T.Msg_Result;
   BE_Result : BE_Topic.Msg_Result;
   Delivered : Boolean;
   In_Order  : Boolean;

   procedure Check_Timed_Receive (Mode : Delivery_Mode);
   procedure Check_Timed_Receive (Mode : Delivery_Mode) is
      package Timed is new Beacon.Topic
        (Message_Type => Reading, Queue_Depth => 2, Max_Subscribers => 1);

      Pub      : Timed.Publisher;
      Sub      : aliased Timed.Subscriber (Mode);
      Result   : Timed.Msg_Result;
      Timeouts : constant array (Positive range <>) of Duration :=
        [Duration'First, -1.0, 0.0, 0.02];
      Waits    : constant array (Positive range <>) of Duration := [2.0, Duration'Last];

      procedure Check_Constrained_Result (Rejected : in out Timed.Msg_Result);
      procedure Check_Constrained_Result (Rejected : in out Timed.Msg_Result) is
      begin
         for With_Timeout in Boolean loop
            begin
               if With_Timeout then
                  Timed.Receive (Sub, 0.0, Rejected);
               else
                  Timed.Try_Receive (Sub, Rejected);
               end if;
               Check (False, "constrained result rejected before receiving");
            exception
               when Ada.Assertions.Assertion_Error =>
                  Check (Timed.Pending (Sub) = 1 and then Timed.Dropped (Sub) = 0,
                         "constrained result rejected without consuming a message");
            end;
         end loop;
      end Check_Constrained_Result;
   begin
      Put_Line ("  timed receive: " & Mode'Image);
      Check (not Result.Success, "a default result has no message");
      Timed.Create_Publisher (Pub);
      Timed.Create_Subscriber (Sub);

      for Timeout of Timeouts loop
         declare
            Started : constant Time := Clock;
         begin
            Timed.Receive (Sub, Timeout, Result);
            Check (not Result.Success
                   and then Clock - Started >= To_Time_Span (Duration'Max (0.0, Timeout))
                   and then Clock - Started < Seconds (2),
                   "empty timed receive returns no message after its timeout");
         end;
         Check (Timed.Pending (Sub) = 0 and then Timed.Dropped (Sub) = 0,
                "timeout leaves the queue and drop count unchanged");

         --  An expired receive must not consume a later publication.
         Timed.Publish (Pub, (Id => 101, Value => 1.5));
         Timed.Publish (Pub, (Id => 102, Value => 2.5));
         Check (Timed.Pending (Sub) = 2, "messages remain queued after a timeout");
         for Expected in 101 .. 102 loop
            declare
               Started : constant Time := Clock;
            begin
               Timed.Receive (Sub, Timeout, Result);
               Check (Result.Success
                      and then Result.Msg =
                        (Id => Expected, Value => Float (Expected - 100) + 0.5)
                      and then Timed.Pending (Sub) = 102 - Expected
                      and then Clock - Started < Seconds (1),
                      "timed receive immediately returns the oldest queued value");
            end;
         end loop;
      end loop;

      Timed.Publish (Pub, (Id => 202, Value => 2.5));
      Timed.Receive (Sub, Duration'Last, Result);
      Check (Result.Success and then Result.Msg = (Id => 202, Value => 2.5),
             "a large timeout accepts a queued message");

      for Timeout of Waits loop
         declare
            task Sender is
               entry Go;
            end Sender;
            task body Sender is
            begin
               accept Go;
               delay 0.02;
               Timed.Publish (Pub, (Id => 303, Value => 3.5));
            end Sender;
            Started : Time;
         begin
            Sender.Go;
            Started := Clock;
            Timed.Receive (S => Sub, Timeout => Timeout, Result => Result);
            Check (Result.Success and then Result.Msg = (Id => 303, Value => 3.5)
                   and then Timed.Pending (Sub) = 0
                   and then Clock - Started < Seconds (1),
                   "publication satisfies a waiting timed receive");
         end;
      end loop;
      Check (Timed.Dropped (Sub) = 0, "timed receives do not count drops");

      declare
         Empty_Result   : Timed.Msg_Result (False);
         Aliased_Result : aliased Timed.Msg_Result;
         Ready_Result   : Timed.Msg_Result (True) :=
           (Success => True, Msg => (Id => 999, Value => 9.5));
      begin
         Timed.Publish (Pub, (Id => 404, Value => 4.5));
         Check_Constrained_Result (Empty_Result);
         Check_Constrained_Result (Ready_Result);
         Timed.Try_Receive (Sub, Result);
         Check (Result.Success and then Result.Msg = (Id => 404, Value => 4.5),
                "a valid result receives the message after constrained calls are rejected");

         Timed.Publish (Pub, (Id => 405, Value => 4.5));
         Timed.Try_Receive (Sub, Aliased_Result);
         Check (Aliased_Result.Success and then Aliased_Result.Msg.Id = 405,
                "an aliased unconstrained result receives a message");
         Timed.Receive (Sub, 0.0, Aliased_Result);
         Check (not Aliased_Result.Success, "an aliased result can become empty after timeout");
         Timed.Publish (Pub, (Id => 406, Value => 4.5));
         Timed.Receive (Sub, 0.0, Aliased_Result);
         Check (Aliased_Result.Success and then Aliased_Result.Msg.Id = 406,
                "an aliased result can receive another timed message");
         Timed.Try_Receive (Sub, Aliased_Result);
         Check (not Aliased_Result.Success, "an aliased result can become empty after polling");
      end;
   end Check_Timed_Receive;

   procedure Check_Predicate_Receive (Mode : Delivery_Mode);
   procedure Check_Predicate_Receive (Mode : Delivery_Mode) is
      type Payload is new Integer
        with Dynamic_Predicate => Payload in 1 .. 10;
      package Predicated is new Beacon.Topic (Payload, Queue_Depth => 1);

      Pub    : Predicated.Publisher;
      Sub    : aliased Predicated.Subscriber (Mode);
      Result : Predicated.Msg_Result;
   begin
      Predicated.Create_Publisher (Pub);
      Predicated.Create_Subscriber (Sub);
      Predicated.Try_Receive (Sub, Result);
      Check (not Result.Success, "empty predicated Try_Receive returns no message");
      Predicated.Receive (Sub, 0.0, Result);
      Check (not Result.Success, "empty predicated timed receive returns no message");
      Predicated.Publish (Pub, 7);
      Predicated.Try_Receive (Sub, Result);
      Check (Result.Success and then Result.Msg = 7, "Try_Receive preserves a payload predicate");
      Predicated.Try_Receive (Sub, Result);
      Check (not Result.Success, "empty Try_Receive clears a previous message result");
      Predicated.Publish (Pub, 8);
      Predicated.Receive (Sub, 0.02, Result);
      Check (Result.Success and then Result.Msg = 8, "timed receive preserves a payload predicate");
      Predicated.Receive (Sub, 0.002, Result);
      Check (not Result.Success, "timeout clears a previous message result");
   end Check_Predicate_Receive;

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
   T.Try_Receive (Rel, Result);
   Check (not Result.Success, "reliable drained, Try_Receive says empty");

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
      BE_Topic.Try_Receive (BE_Sub, BE_Result);
      In_Order := In_Order and then BE_Result.Success and then BE_Result.Msg.Id = Expected
                  and then BE_Topic.Pending (BE_Sub) = Depth + 3 - Expected;
   end loop;
   Check (In_Order, "Try_Receive returns the oldest, Pending decreases by 1");

   --  A full Reliable queue must block Publish until Receive frees a slot.
   declare
      package R_Topic is new Beacon.Topic
        (Message_Type => Reading, Queue_Depth => Depth, Max_Subscribers => 1);

      R_Pub    : R_Topic.Publisher;
      R_Sub    : aliased R_Topic.Subscriber (Reliable);
      R_Result : R_Topic.Msg_Result;
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
            R_Topic.Try_Receive (R_Sub, R_Result);
            In_Order := In_Order and then R_Result.Success
              and then R_Result.Msg = (Id => Expected, Value => Float (Expected));
         end loop;
         Check (In_Order and then R_Topic.Pending (R_Sub) = 0,
                "reliable blocked Publish preserves exact FIFO order");
         Check (R_Topic.Dropped (R_Sub) = 0, "reliable blocked Publish drops nothing");
      end if;

      if not Finished then
         abort Blocked_Publisher;
      end if;
   end;

   for Mode in Delivery_Mode loop
      Check_Timed_Receive (Mode);
      Check_Predicate_Receive (Mode);
   end loop;

   New_Line;
   if Failures = 0 then
      Put_Line ("all passed");
   else
      Put_Line (Natural'Image (Failures) & " failure(s)");
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;
end Topic_Tests;
