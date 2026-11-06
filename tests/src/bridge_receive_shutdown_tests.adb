--  Issue #18: Stop must wait for a held transport operation to finish.

with Ada.Assertions;
with Ada.Text_IO; use Ada.Text_IO;
with Beacon.Bridge;
with Beacon.Topic;
with Beacon.Transport;
with Beacon.Wire; use Beacon.Wire;

procedure Bridge_Receive_Shutdown_Tests is

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

   protected Gate is
      procedure Enter_Send;
      entry Wait_Entered;
      entry Await_Release;
      procedure Release_Send;
      function Finished return Boolean;
      procedure Finish_Send;
   private
      Entered  : Boolean := False;
      Released : Boolean := False;
      Done     : Boolean := False;
   end Gate;

   protected body Gate is
      procedure Enter_Send is
      begin
         Entered := True;
      end Enter_Send;
      entry Wait_Entered when Entered is
      begin
         null;
      end Wait_Entered;
      entry Await_Release when Released is
      begin
         null;
      end Await_Release;
      procedure Release_Send is
      begin
         Released := True;
      end Release_Send;
      function Finished return Boolean is (Done);
      procedure Finish_Send is
      begin
         Done := True;
      end Finish_Send;
   end Gate;

   type Capture_Transport is limited new Beacon.Transport.Transport with null record;
   overriding procedure Send (T : in out Capture_Transport; Frame : Byte_Array);
   overriding procedure Receive
     (T : in out Capture_Transport; Frame : out Byte_Array;
      Count : out Natural; Timeout : Duration);

   overriding procedure Send (T : in out Capture_Transport; Frame : Byte_Array) is
      pragma Unreferenced (T, Frame);
   begin
      null;
   end Send;

   overriding procedure Receive
     (T : in out Capture_Transport; Frame : out Byte_Array;
      Count : out Natural; Timeout : Duration)
   is
      pragma Unreferenced (T, Timeout);
   begin
      Gate.Enter_Send;
      Gate.Await_Release;
      Gate.Finish_Send;
      Frame := [others => 0];
      Count := 0;
   end Receive;

   Net : aliased Capture_Transport;
   Early : Boolean := False;
   Refused : Boolean := False;

   task Stopper is
      entry Go;
      entry Finished;
   end Stopper;

   task body Stopper is
   begin
      accept Go;
      Bridge.Stop;
      accept Finished;
   end Stopper;

begin
   Bridge.Start_Ingress (Net'Access);
   begin
      Bridge.Start_Ingress (Net'Access);
   exception
      when Program_Error | Ada.Assertions.Assertion_Error =>
         Refused := True;
   end;
   select
      Gate.Wait_Entered;
   or
      delay 2.0;
      Gate.Release_Send;
      Stopper.Go;
      Stopper.Finished;
      raise Program_Error with "ingress did not enter Receive";
   end select;
   Stopper.Go;
   --  Send is held by a barrier, not a guessed transport delay.
   select
      Stopper.Finished;
      Early := True;
   or
      delay 0.1;
   end select;
   Gate.Release_Send;
   if not Early then
      select
         Stopper.Finished;
      or
         delay 2.0;
         raise Program_Error with "Stop did not finish after Send returned";
      end select;
   end if;
   if Early or else not Gate.Finished or else not Refused then
      raise Program_Error with "shutdown coordination or duplicate start failed";
   end if;
   Refused := False;
   begin
      Bridge.Start_Ingress (Net'Access);
   exception
      when Program_Error | Ada.Assertions.Assertion_Error =>
         Refused := True;
   end;
   if not Refused then
      raise Program_Error with "restart after Stop was accepted";
   end if;
   Bridge.Stop;
   Put_Line ("bridge shutdown: waits for Receive; rejects duplicate start and restart");
end Bridge_Receive_Shutdown_Tests;
