with Ada.Command_Line;
with Ada.Real_Time; use Ada.Real_Time;
with Ada.Text_IO; use Ada.Text_IO;
with Beacon; use Beacon;
with Beacon.Bridge;
with Beacon.Topic;
with Beacon.Transport.Loopback;
with Beacon.Wire; use Beacon.Wire;

procedure Bridge_Tests is

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

   procedure Serialize (Msg : Byte; Buffer : out Byte_Array; Last : out Natural);
   procedure Serialize (Msg : Byte; Buffer : out Byte_Array; Last : out Natural) is
   begin
      Buffer := [others => 0];
      Buffer (Buffer'First) := Msg;
      Last := Buffer'First;
   end Serialize;

   procedure Deserialize (Buffer : Byte_Array; Msg : out Byte; Valid : out Boolean);
   procedure Deserialize (Buffer : Byte_Array; Msg : out Byte; Valid : out Boolean) is
   begin
      Msg := 0;
      Valid := Buffer'Length = 1;
      if Valid then
         Msg := Buffer (Buffer'First);
      end if;
   end Deserialize;

   protected type Send_Stats is
      procedure Note_Saturation;
      function Count return Natural;
   private
      Saturations : Natural := 0;
   end Send_Stats;

   protected body Send_Stats is
      procedure Note_Saturation is
      begin
         Saturations := Saturations + 1;
      end Note_Saturation;

      function Count return Natural is (Saturations);
   end Send_Stats;

   type Observed_Transport is limited new Beacon.Transport.Transport with record
      FIFO  : Beacon.Transport.Loopback.Loopback_Transport;
      Stats : Send_Stats;
   end record;

   overriding procedure Send (T : in out Observed_Transport; Data : Byte_Array);
   overriding procedure Receive
     (T       : in out Observed_Transport;
      Data    : out Byte_Array;
      Count   : out Natural;
      Timeout : Duration);

   overriding procedure Send (T : in out Observed_Transport; Data : Byte_Array) is
   begin
      T.FIFO.Send (Data);
   exception
      when Beacon.Transport.Would_Block =>
         T.Stats.Note_Saturation;
         raise;
   end Send;

   overriding procedure Receive
     (T       : in out Observed_Transport;
      Data    : out Byte_Array;
      Count   : out Natural;
      Timeout : Duration) is
   begin
      T.FIFO.Receive (Data, Count, Timeout);
   end Receive;

   package Source is new Beacon.Topic (Byte, Queue_Depth => 8, Max_Subscribers => 1);
   package Destination is new Beacon.Topic (Byte, Queue_Depth => 8, Max_Subscribers => 1);
   package Injected is new Beacon.Topic (Byte, Queue_Depth => 8, Max_Subscribers => 1);
   package Egress is new Beacon.Bridge (Source, 7, Serialize, Deserialize);
   package Ingress is new Beacon.Bridge (Destination, 7, Serialize, Deserialize);
   package Validation is new Beacon.Bridge (Injected, 7, Serialize, Deserialize);
   package Saturated is new Beacon.Topic (Byte, Queue_Depth => 8, Max_Subscribers => 1);
   package Pressure is new Beacon.Bridge (Saturated, 7, Serialize, Deserialize);

   Full     : aliased Observed_Transport;
   Full_Pub : Saturated.Publisher;
   Link     : aliased Beacon.Transport.Loopback.Loopback_Transport;
   Input    : aliased Beacon.Transport.Loopback.Loopback_Transport;
   Pub      : Source.Publisher;
   Sub      : aliased Destination.Subscriber (Reliable);
   Checked  : aliased Injected.Subscriber (Reliable);
   Frame    : Byte_Array (1 .. Max_Frame);
   Last     : Natural;

   procedure Expect_Delivery (Expected : Byte);
   procedure Expect_Delivery (Expected : Byte) is
      Deadline : constant Time := Clock + Seconds (2);
      Msg      : Byte;
      Got      : Boolean;
   begin
      loop
         Destination.Try_Receive (Sub, Msg, Got);
         exit when Got or else Clock >= Deadline;
         delay 0.001;
      end loop;
      Check (Got and then Msg = Expected, "typed messages delivered in order");
   end Expect_Delivery;

   procedure Expect_Injected (Expected : Byte);
   procedure Expect_Injected (Expected : Byte) is
      Deadline : constant Time := Clock + Seconds (2);
      Msg      : Byte;
      Got      : Boolean;
   begin
      loop
         Injected.Try_Receive (Checked, Msg, Got);
         exit when Got or else Clock >= Deadline;
         delay 0.001;
      end loop;
      Check (Got and then Msg = Expected, "valid injected frame delivered");
   end Expect_Injected;

   procedure Await_Saturation (Minimum : Natural);
   procedure Await_Saturation (Minimum : Natural) is
      Deadline : constant Time := Clock + Seconds (2);
   begin
      while Full.Stats.Count < Minimum and then Clock < Deadline loop
         delay 0.001;
      end loop;
      Check (Full.Stats.Count >= Minimum, "saturated egress keeps retrying");
   end Await_Saturation;

   procedure Expect_Frame (Expected : Byte; Sequence : Sequence_Type);
   procedure Expect_Frame (Expected : Byte; Sequence : Sequence_Type) is
      Count   : Natural;
      Topic   : Topic_Id_Type;
      Seq     : Sequence_Type;
      Payload : Byte_Array (1 .. Max_Payload);
      PL      : Natural;
      Status  : Decode_Status;
   begin
      Full.Receive (Frame, Count, 2.0);
      Decode (Frame (1 .. Count), Topic, Seq, Payload, PL, Status);
      Check (Status = Ok and then Topic = 7 and then Seq = Sequence
             and then PL = 1 and then Payload (1) = Expected,
             "egress resumes without losing its frame or sequence");
   end Expect_Frame;

begin
   Put_Line ("Beacon.Bridge tests (no sockets)");
   Source.Create_Publisher (Pub);
   Destination.Create_Subscriber (Sub);
   Injected.Create_Subscriber (Checked);

   Ingress.Start_Ingress (Link'Access);
   Egress.Start_Egress (Link'Access, Reliable);
   Validation.Start_Ingress (Input'Access);
   Check (Source.Subscriber_Count = 1, "egress subscriber ready when Start returns");
   Check (Destination.Has_Publisher and then Injected.Has_Publisher,
          "ingress publishers ready when Start returns");

   for I in 1 .. 4 loop
      Source.Publish (Pub, Byte (I));
   end loop;
   for I in 1 .. 4 loop
      Expect_Delivery (Byte (I));
   end loop;
   Check (Ingress.Rejected_Frames = 0 and then Ingress.Sequence_Gaps = 0,
          "round trip has no rejections or gaps");

   Encode (7, 0, [10], Frame, Last);
   Input.Send (Frame (1 .. Last));
   Expect_Injected (10);
   Encode (7, 2, [20], Frame, Last);
   Input.Send (Frame (1 .. Last));
   Expect_Injected (20);
   Check (Validation.Sequence_Gaps = 1, "missing sequence counted");

   Input.Send ([0]);
   Encode (7, 3, [30], Frame, Last);
   Frame (Last) := Frame (Last) xor 1;
   Input.Send (Frame (1 .. Last));
   Encode (8, 3, [30], Frame, Last);
   Input.Send (Frame (1 .. Last));
   Encode (7, 3, [30, 31], Frame, Last);
   Input.Send (Frame (1 .. Last));
   Encode (7, 4, [40], Frame, Last);
   Input.Send (Frame (1 .. Last));
   Expect_Injected (40);
   Check (Validation.Rejected_Frames = 4,
          "short, corrupt, foreign-topic and invalid-codec frames rejected");
   Check (Validation.Sequence_Gaps = 1, "rejected wire frames do not change sequence tracking");
   Check (Injected.Pending (Checked) = 0, "rejected frames never published");

   for I in 1 .. Beacon.Transport.Loopback.Capacity loop
      Full.FIFO.Send ([0]);
   end loop;
   Saturated.Create_Publisher (Full_Pub);
   Pressure.Start_Egress (Full'Access, Reliable);
   Saturated.Publish (Full_Pub, 50);
   Await_Saturation (2);
   declare
      Count : Natural;
   begin
      for I in 1 .. Beacon.Transport.Loopback.Capacity loop
         Full.Receive (Frame, Count, 0.0);
         Check (Count = 1 and then Frame (1) = 0, "saturation preserves queued frames");
      end loop;
   end;
   Expect_Frame (50, 0);
   Saturated.Publish (Full_Pub, 51);
   Expect_Frame (51, 1);

   for I in 1 .. Beacon.Transport.Loopback.Capacity loop
      Full.FIFO.Send ([0]);
   end loop;
   declare
      Previous : constant Natural := Full.Stats.Count;
   begin
      Saturated.Publish (Full_Pub, 52);
      Await_Saturation (Previous + 2);
   end;
   Pressure.Stop;

   Egress.Stop;
   Ingress.Stop;
   Validation.Stop;

   if Failures = 0 then
      Put_Line ("all passed");
   else
      Put_Line (Natural'Image (Failures) & " failure(s)");
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;
exception
   when others =>
      Pressure.Stop;
      Egress.Stop;
      Ingress.Stop;
      Validation.Stop;
      raise;
end Bridge_Tests;
