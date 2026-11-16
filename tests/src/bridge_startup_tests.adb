--  Issue #14: startup must register egress before publication can begin.

with Ada.Command_Line;
with Ada.Text_IO; use Ada.Text_IO;
with Beacon; use Beacon;
with Beacon.Bridge;
with Beacon.Topic;
with Beacon.Transport;
with Beacon.Wire; use Beacon.Wire;

procedure Bridge_Startup_Tests is

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
      pragma Unreferenced (T, Timeout);
   begin
      Frame := [others => 0];
      Count := 0;
   end Receive;

   Net     : aliased Capture_Transport;
   Pub     : Local.Publisher;
   Frame   : Byte_Array (1 .. Max_Frame);
   Last    : Natural;
   Payload : Byte_Array (1 .. Max_Payload);
   PL      : Natural;
   Topic   : Topic_Id_Type;
   Seq     : Sequence_Type;
   Status  : Decode_Status;
   Ready   : Boolean;
   Got     : Boolean := False;

begin
   Local.Create_Publisher (Pub);
   Bridge.Start_Egress (Net'Access, Best_Effort);
   Ready := Local.Subscriber_Count = 1;
   --  No sleep or readiness polling before the first publication.
   Local.Publish (Pub, 42);
   select
      Capture.Read (Frame, Last);
      Got := True;
   or
      delay 2.0;
   end select;
   Bridge.Stop;

   if Got then
      Decode (Frame (1 .. Last), Topic, Seq, Payload, PL, Status);
      Got := Status = Ok and then Topic = 7 and then Seq = 0
        and then PL = 1 and then Payload (1) = 42;
   end if;
   if Ready and then Got then
      Put_Line ("bridge startup: registered on return; immediate message forwarded");
   else
      Put_Line ("FAIL: bridge startup readiness or immediate delivery");
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;
exception
   when others =>
      Bridge.Stop;
      raise;
end Bridge_Startup_Tests;
