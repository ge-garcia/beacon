--  Tests for Beacon.Wire. Owner: network engineer. Green by Week 16.

with Ada.Command_Line;
with Ada.Text_IO;  use Ada.Text_IO;
with Beacon.Wire;  use Beacon.Wire;

procedure Wire_Tests is

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

   Frame    : Byte_Array (1 .. Max_Frame);
   Last     : Natural;
   Payload  : Byte_Array (1 .. Max_Payload);
   PL       : Natural;
   Topic    : Topic_Id_Type;
   Seq      : Sequence_Type;
   Status   : Decode_Status;

   Sample : constant Byte_Array (1 .. 4) := [16#DE#, 16#AD#, 16#BE#, 16#EF#];

begin
   Put_Line ("Beacon.Wire tests");

   Check (Header'Size = Header_Length * 8, "header is exactly 14 bytes");

   declare
      V : constant Byte_Array (1 .. 9) :=
        [16#31#, 16#32#, 16#33#, 16#34#, 16#35#, 16#36#, 16#37#, 16#38#, 16#39#];
   begin
      Check (Checksum (V) = 16#CBF43926#, "CRC-32 of '123456789'");
   end;

   Encode (Topic => 7, Sequence => 42, Payload => Sample,
           Frame => Frame, Last => Last);
   Check (Last = Header_Length + 4, "frame length = header + payload");
   Check (Frame (1) = 16#BE# and then Frame (2) = 16#AC#,
          "magic is big-endian on the wire");

   Decode (Frame (1 .. Last), Topic, Seq, Payload, PL, Status);
   Check (Status = Ok, "round trip Ok");
   Check (Topic = 7 and then Seq = 42, "header fields survive");
   Check (PL = 4 and then Payload (1 .. 4) = Sample, "payload survives");

   Decode (Frame (1 .. Header_Length - 1), Topic, Seq, Payload, PL, Status);
   Check (Status = Too_Short, "short frame rejected");

   Decode (Frame (1 .. Last - 1), Topic, Seq, Payload, PL, Status);
   Check (Status = Bad_Length, "declared length past end rejected");

   Frame (Header_Length + 1) := Frame (Header_Length + 1) xor 16#FF#;
   Decode (Frame (1 .. Last), Topic, Seq, Payload, PL, Status);
   Check (Status = Bad_Checksum, "flipped payload byte rejected");

   --  Decode reads frames from the network, so test each way that it
   --  rejects a frame. Each case starts from a new good frame.
   --  Frame (I) holds wire byte I - 1.

   Encode (Topic => 7, Sequence => 42, Payload => Sample, Frame => Frame, Last => Last);
   Frame (1) := 16#00#;
   Decode (Frame (1 .. Last), Topic, Seq, Payload, PL, Status);
   Check (Status = Bad_Magic, "wrong magic rejected");

   Encode (Topic => 7, Sequence => 42, Payload => Sample, Frame => Frame, Last => Last);
   Decode (Frame (1 .. Last + 1), Topic, Seq, Payload, PL, Status);
   Check (Status = Bad_Length, "trailing byte after the frame rejected");

   Encode (Topic => 7, Sequence => 42, Payload => Sample, Frame => Frame, Last => Last);
   Frame (9 .. 10) := [16#04#, 16#01#];  --  Length = Max_Payload + 1
   Decode (Frame (1 .. Last), Topic, Seq, Payload, PL, Status);
   Check (Status = Bad_Length, "Length field above Max_Payload rejected");

   Encode (Topic => 7, Sequence => 42, Payload => Sample, Frame => Frame, Last => Last);
   Frame (5) := Frame (5) xor 16#FF#;  --  first byte of Sequence
   Decode (Frame (1 .. Last), Topic, Seq, Payload, PL, Status);
   Check (Status = Bad_Checksum, "flipped header byte rejected");

   New_Line;
   if Failures = 0 then
      Put_Line ("all passed");
   else
      Put_Line (Natural'Image (Failures) & " failure(s)");
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;
end Wire_Tests;
