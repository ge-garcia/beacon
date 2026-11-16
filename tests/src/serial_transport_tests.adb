with Ada.Command_Line; use Ada.Command_Line;
with Ada.Real_Time; use Ada.Real_Time;
with Ada.Text_IO; use Ada.Text_IO;
with Beacon.Transport.Serial; use Beacon.Transport.Serial;
with Beacon.Wire; use Beacon.Wire;

procedure Serial_Transport_Tests is
   Port : Serial_Transport;
   Buffer : Byte_Array (5 .. Max_Frame + 4);
   Count : Natural;
   Started : Time;
   Topic : Topic_Id_Type;
   Sequence : Sequence_Type;
   Payload : Byte_Array (1 .. Max_Payload);
   Last : Natural;
   Status : Decode_Status;
begin
   Open (Port, Argument (1));
   Put_Line ("ready");
   Flush;
   Started := Clock;
   Receive (Port, Buffer, Count, 0.2);
   pragma Assert (Count = 0 and then Clock - Started < Seconds (1));
   Put_Line ("partial retained");
   Flush;
   Receive (Port, Buffer, Count, 2.0);
   pragma Assert (Count = 5 and then Buffer (5 .. 9) = [0, 17, 19, 255, 0]);
   Receive (Port, Buffer, Count, 2.0);
   pragma Assert (Count = 3 and then Buffer (5 .. 7) = [42, 0, 43]);
   Send (Port, Buffer (5 .. 7));
   pragma Assert (Frames_Sent (Port) = 1);
   Started := Clock;
   Receive (Port, Buffer, Count, 0.02);
   pragma Assert (Count = 0 and then Clock - Started < Seconds (1));
   Put_Line ("ready for checksum recovery");
   Flush;
   Receive (Port, Buffer, Count, 2.0);
   pragma Assert (Count > 0);
   Decode (Buffer (5 .. 4 + Count), Topic, Sequence, Payload, Last, Status);
   pragma Assert (Status = Bad_Checksum);
   Receive (Port, Buffer, Count, 2.0);
   pragma Assert (Count > 0);
   Decode (Buffer (5 .. 4 + Count), Topic, Sequence, Payload, Last, Status);
   pragma Assert
     (Status = Ok and then Topic = 7 and then Sequence = 1
      and then Last = 3 and then Payload (1 .. 3) = [42, 0, 43]);
   Close (Port);
   Close (Port);
   Put_Line ("serial_transport_tests: PASS");
exception
   when others =>
      Close (Port);
      raise;
end Serial_Transport_Tests;
