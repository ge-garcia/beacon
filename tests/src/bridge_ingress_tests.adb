--  Issue #17: count incomplete local delivery without blocking ingress.

with Ada.Text_IO; use Ada.Text_IO;
with Beacon; use Beacon;
with Beacon.Bridge;
with Beacon.Topic;
with Beacon.Transport;
with Beacon.Wire; use Beacon.Wire;

procedure Bridge_Ingress_Tests is

   package Local is new Beacon.Topic (Byte, Queue_Depth => 1);

   procedure Serialize (Msg : Byte; Buffer : out Byte_Array; Last : out Natural);
   procedure Deserialize (Buffer : Byte_Array; Msg : out Byte; Valid : out Boolean);

   procedure Serialize (Msg : Byte; Buffer : out Byte_Array; Last : out Natural) is
   begin
      Buffer := [others => 0];
      Last := Buffer'First;
      Buffer (Last) := Msg;
   end Serialize;

   procedure Deserialize (Buffer : Byte_Array; Msg : out Byte; Valid : out Boolean) is
   begin
      Valid := Buffer'Length = 1;
      Msg := (if Valid then Buffer (Buffer'First) else 0);
   end Deserialize;

   package Bridge is new Beacon.Bridge (Local, 7, Serialize, Deserialize);

   --  Capture one outgoing frame without sockets or a reusable transport.
   protected Capture is
      procedure Store (Frame : Byte_Array);
      entry Read (Frame : out Byte_Array; Last : out Natural);
   private
      Saved : Byte_Array (1 .. Max_Frame) := [others => 0];
      Size  : Natural := 0;
   end Capture;

   protected body Capture is
      procedure Store (Frame : Byte_Array) is
      begin
         Saved (1 .. Frame'Length) := Frame;
         Size := Frame'Length;
      end Store;

      entry Read (Frame : out Byte_Array; Last : out Natural) when Size > 0 is
      begin
         Frame := Saved;
         Last := Size;
         Size := 0;
      end Read;
   end Capture;

   type Capture_Transport is limited new Beacon.Transport.Transport with null record;
   overriding procedure Send (T : in out Capture_Transport; Frame : Byte_Array);
   overriding procedure Receive
     (T : in out Capture_Transport; Frame : out Byte_Array;
      Count : out Natural; Timeout : Duration);

   overriding procedure Send (T : in out Capture_Transport; Frame : Byte_Array) is
      pragma Unreferenced (T);
   begin
      Capture.Store (Frame);
   end Send;

   overriding procedure Receive
     (T : in out Capture_Transport; Frame : out Byte_Array;
      Count : out Natural; Timeout : Duration)
   is
      pragma Unreferenced (T);
   begin
      Frame := [others => 0];
      Count := 0;
      select
         Capture.Read (Frame, Count);
      or
         delay Timeout;
      end select;
   end Receive;

   Net   : aliased Capture_Transport;
   Rel   : aliased Local.Subscriber (Reliable);
   Rel_2 : aliased Local.Subscriber (Reliable);
   Best  : aliased Local.Subscriber (Best_Effort);
   Frame : Byte_Array (1 .. Max_Frame);
   Last  : Natural;
   Msg   : Byte;
   Got   : Boolean;

   procedure Check (Condition : Boolean; Name : String);
   procedure Check (Condition : Boolean; Name : String) is
   begin
      if not Condition then
         raise Program_Error with Name;
      end if;
      Put_Line ("  ok    " & Name);
   end Check;

   procedure Deliver (Sequence : Sequence_Type; Value : Byte);
   procedure Deliver (Sequence : Sequence_Type; Value : Byte) is
   begin
      Encode (7, Sequence, [Value], Frame, Last);
      Net.Send (Frame (1 .. Last));
   end Deliver;

begin
   Local.Create_Subscriber (Rel);
   Local.Create_Subscriber (Rel_2);
   Local.Create_Subscriber (Best);
   Bridge.Start_Ingress (Net'Access);
   Check (Local.Has_Publisher, "ingress ready on return");
   Deliver (0, 41);
   for Attempt in 1 .. 2000 loop
      exit when Local.Pending (Best) = 1;
      delay 0.001;
   end loop;
   Check (Local.Pending (Rel) = 1, "first delivery fills reliable queue");
   Check (Bridge.Local_Delivery_Failures = 0, "successful delivery not counted");
   Deliver (1, 42);
   for Attempt in 1 .. 2000 loop
      exit when Bridge.Local_Delivery_Failures = 1;
      delay 0.001;
   end loop;
   Check (Bridge.Local_Delivery_Failures = 1, "one incomplete publication counted");
   Local.Try_Receive (Best, Msg, Got);
   Check (Got and then Msg = 42, "other subscriber still receives latest message");
   Local.Try_Receive (Rel, Msg, Got);
   Check (Got and then Msg = 41, "reliable queue preserves first message");
   Local.Try_Receive (Rel_2, Msg, Got);
   Check (Got and then Msg = 41, "two refusals still count as one publication");
   Check (Local.Dropped (Rel) = 0, "local reliable drop count remains zero");
   Check (Bridge.Rejected_Frames = 0, "valid frame is not counted as rejected");
   Deliver (2, 43);
   for Attempt in 1 .. 2000 loop
      exit when Local.Pending (Best) = 1;
      delay 0.001;
   end loop;
   Bridge.Stop;
   Local.Try_Receive (Rel, Msg, Got);
   Check (Got and then Msg = 43, "ingress continues after failed local delivery");
   Check (Bridge.Local_Delivery_Failures = 1, "counter stays cumulative after recovery");
   Bridge.Stop;
   Put_Line ("bridge ingress tests passed");
exception
   when others =>
      Bridge.Stop;
      raise;
end Bridge_Ingress_Tests;
