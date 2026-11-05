with Ada.Command_Line;
with Ada.Real_Time; use Ada.Real_Time;
with Ada.Text_IO; use Ada.Text_IO;
with Beacon.Transport.Loopback; use Beacon.Transport.Loopback;
with Beacon.Wire; use Beacon.Wire;

procedure Transport_Tests is

   Failures : Natural := 0;
   T        : Loopback_Transport;
   Other    : Loopback_Transport;
   Buffer   : Byte_Array (7 .. Max_Frame + 6);
   Count    : Natural;

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

begin
   Put_Line ("Beacon.Transport.Loopback tests");

   T.Receive (Buffer, Count, 0.0);
   Check (Count = 0 and then Buffer = [Buffer'Range => 0], "empty immediate poll");
   T.Receive (Buffer, Count, -1.0);
   Check (Count = 0, "negative timeout polls");
   declare
      Started : constant Time := Clock;
   begin
      T.Receive (Buffer, Count, 0.02);
      Check (Count = 0 and then Clock - Started >= Milliseconds (20), "empty timed receive");
   end;

   declare
      Sample : Byte_Array (3 .. 5) := [11, 22, 33];
   begin
      T.Send (Sample);
      Sample := [others => 99];
      Other.Receive (Buffer, Count, 0.0);
      Check (Count = 0, "instances are isolated");
      T.Receive (Buffer, Count, 0.0);
      Check (Count = 3 and then Buffer (7 .. 9) = Byte_Array'[11, 22, 33],
             "send copies bytes and receive respects lower bound");
      Check (Buffer (10 .. Buffer'Last) = [10 .. Buffer'Last => 0], "unused bytes are zero");
   end;

   declare
      Sample : Byte_Array (1 .. Max_Frame);
   begin
      for I in Sample'Range loop
         Sample (I) := Byte (I mod 256);
      end loop;
      T.Send (Sample);
      T.Receive (Buffer, Count, 0.0);
      Check (Count = Max_Frame and then Buffer = Sample, "maximum datagram survives");
   end;

   for I in 1 .. Capacity loop
      T.Send ([Byte (I)]);
   end loop;
   begin
      T.Send ([99]);
      Check (False, "full FIFO raises Queue_Full");
   exception
      when Queue_Full => Check (True, "full FIFO raises Queue_Full");
   end;
   for I in 1 .. Capacity loop
      T.Receive (Buffer, Count, 0.0);
      Check (Count = 1 and then Buffer (7) = Byte (I), "FIFO preserves queued datagrams");
   end loop;
   T.Send ([42]);
   T.Receive (Buffer, Count, 0.0);
   Check (Count = 1 and then Buffer (7) = 42, "FIFO reusable after draining");

   declare
      Oversized : constant Byte_Array (1 .. Max_Frame + 1) := [others => 0];
   begin
      T.Send (Oversized);
      Check (False, "oversized send rejected");
   exception
      when Constraint_Error => Check (True, "oversized send rejected");
   end;
   begin
      T.Send (Byte_Array'(1 .. 0 => 0));
      Check (False, "empty send rejected");
   exception
      when Constraint_Error => Check (True, "empty send rejected");
   end;
   T.Send ([1, 2]);
   declare
      Small : Byte_Array (1 .. 1);
   begin
      T.Receive (Small, Count, 0.0);
      Check (False, "undersized receive rejected");
   exception
      when Constraint_Error => Check (True, "undersized receive rejected");
   end;
   T.Receive (Buffer, Count, 0.0);
   Check (Count = 0, "undersized receive discards the datagram");

   declare
      task Sender is
         entry Go;
      end Sender;
      task body Sender is
      begin
         accept Go;
         delay 0.02;
         T.Send ([77]);
      end Sender;
   begin
      Sender.Go;
      T.Receive (Buffer, Count, 1.0);
      Check (Count = 1 and then Buffer (7) = 77, "send wakes waiting receive");
   end;

   if Failures = 0 then
      Put_Line ("all passed");
   else
      Put_Line (Natural'Image (Failures) & " failure(s)");
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;
end Transport_Tests;
