with Ada.Text_IO; use Ada.Text_IO;
with Beacon.Framing; use Beacon.Framing;
with Beacon.Wire; use Beacon.Wire;

procedure Framing_Tests is
   Raw : Raw_Buffer := [others => 0];
   Encoded : Encoded_Buffer;
   Decoded : Raw_Buffer;
   Last, Count : Natural;
   Valid : Boolean;

   procedure Check (Length : Natural);

   procedure Check (Length : Natural) is
   begin
      Encode (Raw, Length, Encoded, Last);
      pragma Assert (Last <= Length + Length / 254 + 1);
      pragma Assert (for all I in 1 .. Last => Encoded (I) /= 0);
      Decode (Encoded, Last, Decoded, Count, Valid);
      pragma Assert (Valid and then Count = Length);
      pragma Assert (Decoded (1 .. Count) = Raw (1 .. Length));
   end Check;
begin
   for Length in 0 .. Max_Frame loop
      Raw := [others => 0];
      Check (Length);
      Raw := [others => 255];
      Check (Length);
      for I in Raw'Range loop
         Raw (I) := Byte (I mod 256);
      end loop;
      Check (Length);
   end loop;
   Raw := [others => 0];
   Raw (1 .. 5) := [0, 16#BE#, 16#AC#, 0, 255];
   Encode (Raw, 5, Encoded, Last);
   pragma Assert (Encoded (1 .. Last) = [1, 3, 16#BE#, 16#AC#, 2, 255]);
   Encoded := [others => 1];
   Decode (Encoded, 0, Decoded, Count, Valid);
   pragma Assert (not Valid and Count = 0);
   Encoded (1) := 0;
   Decode (Encoded, 1, Decoded, Count, Valid);
   pragma Assert (not Valid and Count = 0);
   Encoded (1) := 3;
   Decode (Encoded, 2, Decoded, Count, Valid);
   pragma Assert (not Valid and Count = 0);
   Encoded (2) := 0;
   Decode (Encoded, 3, Decoded, Count, Valid);
   pragma Assert (not Valid and Count = 0);
   Encoded := [others => 1];
   Decode (Encoded, Max_Encoded, Decoded, Count, Valid);
   pragma Assert (not Valid and Count = 0);
   Put_Line ("framing_tests: PASS (all lengths, zeros, nonzeros, malformed bodies)");
end Framing_Tests;
