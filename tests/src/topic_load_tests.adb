with Ada.Command_Line;
with Ada.Real_Time;    use Ada.Real_Time;
with Ada.Text_IO;      use Ada.Text_IO;
with Beacon;           use Beacon;
with Beacon.Topic;

--  Publish on four topics in parallel and check each Reliable subscriber
--  receives every message in order without drops.
procedure Topic_Load_Tests is

   Depth       : constant Positive := 4;
   Topic_Count : constant Positive := 4;

   type Outcome is record
      Sent      : Natural;
      Received  : Natural;
      Dropped   : Natural;
      Pending   : Natural;
      In_Order  : Boolean;
      Failed    : Boolean;
      Was_Full  : Boolean;
   end record;

   --  Each instance owns one topic, one publisher task, and one subscriber task.
   generic
   package Topic_Run is
      --  Register participants and fill the queue
      procedure Prepare;

      --  Publish until Deadline and drain the queue.
      procedure Start (Deadline : Time);

      --  Waits for both tasks; aborts them and report False at Timeout_At.
      procedure Wait_Until (Timeout_At : Time; Completed : out Boolean);

      --  Return the counts and checks after Wait_Until returns.
      function Result return Outcome;
   end Topic_Run;

   package body Topic_Run is
      package T is new Beacon.Topic
        (Message_Type => Natural, Queue_Depth => Depth, Max_Subscribers => 1);

      Pub : T.Publisher;
      Sub : aliased T.Subscriber (Reliable);
      Full_At_Start : Boolean := False;

      protected Progress is
         procedure Note_Sent;
         procedure Note_Received (Sequence : Natural);
         procedure Finish_Publisher;
         procedure Finish_Subscriber;
         procedure Note_Failure;
         function Publisher_Finished return Boolean;
         entry Wait_Done;
         procedure Snapshot
           (Sent, Received : out Natural; In_Order, Failed : out Boolean);
      private
         Sent_Count     : Natural := 0;
         Received_Count : Natural := 0;
         Ordered        : Boolean := True;
         Error          : Boolean := False;
         Pub_Done       : Boolean := False;
         Sub_Done       : Boolean := False;
      end Progress;

      protected body Progress is
         procedure Note_Sent is
         begin
            Sent_Count := Sent_Count + 1;
         end Note_Sent;

         procedure Note_Received (Sequence : Natural) is
         begin
            Received_Count := Received_Count + 1;
            Ordered := Ordered and then Sequence = Received_Count;
         end Note_Received;

         procedure Finish_Publisher is
         begin
            Pub_Done := True;
         end Finish_Publisher;

         procedure Finish_Subscriber is
         begin
            Sub_Done := True;
         end Finish_Subscriber;

         procedure Note_Failure is
         begin
            Error := True;
         end Note_Failure;

         function Publisher_Finished return Boolean is (Pub_Done);

         entry Wait_Done when Pub_Done and Sub_Done is
         begin
            null;
         end Wait_Done;

         procedure Snapshot
           (Sent, Received : out Natural; In_Order, Failed : out Boolean) is
         begin
            Sent := Sent_Count;
            Received := Received_Count;
            In_Order := Ordered;
            Failed := Error;
         end Snapshot;
      end Progress;

      task Publisher_Task is
         entry Go (Deadline : Time);
      end Publisher_Task;

      task Subscriber_Task is
         entry Go;
      end Subscriber_Task;

      task body Publisher_Task is
         Stop_At  : Time;
         --  Startup sends messages 1 through Depth; continue that sequence.
         Sequence : Natural := Depth;
      begin
         accept Go (Deadline : Time) do
            Stop_At := Deadline;
         end Go;
         while Clock < Stop_At loop
            Sequence := Sequence + 1;
            T.Publish (Pub, Sequence);
            Progress.Note_Sent;
         end loop;
         Progress.Finish_Publisher;
      exception
         when others =>
            Progress.Note_Failure;
            Progress.Finish_Publisher;
      end Publisher_Task;

      task body Subscriber_Task is
         Sequence : Natural;
         Got      : Boolean;
      begin
         accept Go;
         loop
            --  A nonblocking read lets the subscriber stop once the publisher
            --  finishes and the queue is empty.
            T.Try_Receive (Sub, Sequence, Got);
            if Got then
               Progress.Note_Received (Sequence);
               --  Slow the subscriber so the publisher must wait for queue space.
               delay 0.001;
            else
               --  The publisher can send its final message after the empty read.
               --  Recheck the queue only after the publisher has finished.
               exit when Progress.Publisher_Finished and then T.Pending (Sub) = 0;
               delay 0.001;
            end if;
         end loop;
         Progress.Finish_Subscriber;
      exception
         when others =>
            Progress.Note_Failure;
            Progress.Finish_Subscriber;
      end Subscriber_Task;

      procedure Prepare is
      begin
         T.Create_Publisher (Pub);
         T.Create_Subscriber (Sub);
         for Sequence in 1 .. Depth loop
            T.Publish (Pub, Sequence);
            Progress.Note_Sent;
         end loop;
         Full_At_Start := T.Pending (Sub) = Depth;
      end Prepare;

      procedure Start (Deadline : Time) is
      begin
         Publisher_Task.Go (Deadline);
         Subscriber_Task.Go;
      end Start;

      procedure Wait_Until (Timeout_At : Time; Completed : out Boolean) is
      begin
         --  Abort both tasks at the deadline so a blocked publisher cannot hang the test.
         select
            Progress.Wait_Done;
            Completed := True;
         or
            delay until Timeout_At;
            Completed := False;
            abort Publisher_Task, Subscriber_Task;
         end select;
      end Wait_Until;

      function Result return Outcome is
         Value : Outcome;
      begin
         Progress.Snapshot (Value.Sent, Value.Received, Value.In_Order, Value.Failed);
         Value.Dropped := T.Dropped (Sub);
         Value.Pending := T.Pending (Sub);
         Value.Was_Full := Full_At_Start;
         return Value;
      end Result;
   end Topic_Run;

   Run_For : Positive := 180;
   All_OK  : Boolean := True;

   procedure Check_Result (Id : Positive; Completed : Boolean; Value : Outcome);
   procedure Check_Result (Id : Positive; Completed : Boolean; Value : Outcome) is
      OK : constant Boolean := Completed and then not Value.Failed and then Value.Was_Full
        and then Value.Sent > Depth and then Value.Received = Value.Sent
        and then Value.In_Order and then Value.Dropped = 0 and then Value.Pending = 0;
   begin
      Put_Line ("topic" & Id'Image & ": sent" & Value.Sent'Image
                & ", received" & Value.Received'Image & ", dropped" & Value.Dropped'Image
                & ", pending" & Value.Pending'Image & (if OK then " ok" else " FAIL"));
      All_OK := All_OK and OK;
   end Check_Result;

begin
   if Ada.Command_Line.Argument_Count > 1 then
      Put_Line ("usage: topic_load_tests [seconds]");
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
      return;
   elsif Ada.Command_Line.Argument_Count = 1 then
      begin
         Run_For := Positive'Value (Ada.Command_Line.Argument (1));
      exception
         when Constraint_Error =>
            Put_Line ("usage: topic_load_tests [positive seconds]");
            Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
            return;
      end;
   end if;

   declare
      package Run_1 is new Topic_Run;
      package Run_2 is new Topic_Run;
      package Run_3 is new Topic_Run;
      package Run_4 is new Topic_Run;

      Deadline   : Time;
      Timeout_At : Time;
      Completed  : Boolean;
   begin
      --  Start each queue full. Publishers must wait until subscribers make room.
      Run_1.Prepare;
      Run_2.Prepare;
      Run_3.Prepare;
      Run_4.Prepare;

      Deadline := Clock + Seconds (Run_For);
      Timeout_At := Deadline + Seconds (10);
      Put_Line ("Beacon.Topic load test:" & Topic_Count'Image
                & " parallel topics for" & Run_For'Image & " seconds");

      Run_1.Start (Deadline);
      Run_2.Start (Deadline);
      Run_3.Start (Deadline);
      Run_4.Start (Deadline);

      --  All runs share one deadline, so a slow run gives later runs no extra time.
      Run_1.Wait_Until (Timeout_At, Completed);
      Check_Result (1, Completed, Run_1.Result);
      Run_2.Wait_Until (Timeout_At, Completed);
      Check_Result (2, Completed, Run_2.Result);
      Run_3.Wait_Until (Timeout_At, Completed);
      Check_Result (3, Completed, Run_3.Result);
      Run_4.Wait_Until (Timeout_At, Completed);
      Check_Result (4, Completed, Run_4.Result);
   end;

   if All_OK then
      Put_Line ("all passed");
   else
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;
end Topic_Load_Tests;
