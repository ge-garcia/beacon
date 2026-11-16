--  Issue #18: Stop must wait for a held transport operation to finish.

with Ada.Assertions;
with Ada.Exceptions;
with Shutdown_Test_Support; use Shutdown_Test_Support;
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

   Gate : Operation_Gate;

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
      Gate.Enter_Operation;
      Gate.Await_Release;
      Gate.Finish_Operation;
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
   exception
      when Error : others =>
         Fail ("Stopper: " & Ada.Exceptions.Exception_Information (Error));
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
      Fail ("ingress did not enter Receive");
   end select;
   --  Start Stop only after the transport operation has entered the gate.
   Stopper.Go;
   --  Receive is held by the gate. Stop must remain blocked for this window.
   select
      Stopper.Finished;
      Early := True;
   or
      delay 0.1;
   end select;
   --  Releasing the operation must let Stop finish within two seconds.
   Gate.Release_Operation;
   if not Early then
      select
         Stopper.Finished;
      or
         delay 2.0;
         Fail ("Stop did not finish after Receive returned");
      end select;
   end if;
   if Early or else not Gate.Finished or else not Refused then
      Fail ("shutdown coordination or duplicate start failed");
   end if;
   Refused := False;
   begin
      Bridge.Start_Ingress (Net'Access);
   exception
      when Program_Error | Ada.Assertions.Assertion_Error =>
         Refused := True;
   end;
   if not Refused then
      Fail ("restart after Stop was accepted");
   end if;
   Bridge.Stop;
   Put_Line ("bridge shutdown: waits for Receive; rejects duplicate start and restart");
exception
   when Error : others =>
      Fail (Ada.Exceptions.Exception_Information (Error));
end Bridge_Receive_Shutdown_Tests;
