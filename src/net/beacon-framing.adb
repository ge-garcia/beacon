package body Beacon.Framing with SPARK_Mode => On is
   use type Wire.Byte;

   procedure Encode
     (Data : Raw_Buffer; Count : Natural;
      Output : out Encoded_Buffer; Last : out Natural)
   is
      Code_At : Positive := 1;
      Code : Positive := 1;
      Next : Positive := 2;
      Blocks : Natural := 0 with Ghost;
   begin
      Output := [others => 0];
      for I in 1 .. Count loop
         if Data (I) = 0 then
            Output (Code_At) := Wire.Byte (Code);
            Code_At := Next;
            Next := Next + 1;
            Code := 1;
         else
            Output (Next) := Data (I);
            Next := Next + 1;
            Code := Code + 1;
            if Code = 255 then
               Output (Code_At) := 255;
               Code_At := Next;
               Next := Next + 1;
               Code := 1;
               Blocks := Blocks + 1;
            end if;
         end if;
         pragma Loop_Invariant (Code in 1 .. 254);
         pragma Loop_Invariant (Next = I + 2 + Blocks);
         pragma Loop_Invariant (Blocks * 254 + Code - 1 <= I);
         pragma Loop_Invariant (Code_At < Next);
         pragma Loop_Invariant (Next <= I + I / 254 + 2);
      end loop;
      Output (Code_At) := Wire.Byte (Code);
      Last := Next - 1;
   end Encode;

   procedure Decode
     (Data : Encoded_Buffer; Last : Natural;
      Output : out Raw_Buffer; Count : out Natural; Valid : out Boolean)
   is
      Pos : Positive := 1;
      Used : Natural := 0;
      Code : Natural;
   begin
      Output := [others => 0];
      Count := 0;
      Valid := False;
      if Last = 0 then
         return;
      end if;
      while Pos <= Last loop
         pragma Loop_Invariant (Pos in 1 .. Last + 1);
         pragma Loop_Invariant (Used <= Wire.Max_Frame);
         pragma Loop_Variant (Increases => Pos);
         Code := Natural (Data (Pos));
         Pos := Pos + 1;
         if Code = 0 or else Code - 1 > Last - Pos + 1 then
            return;
         end if;
         declare
            Start : constant Positive := Pos;
         begin
            for J in 1 .. Code - 1 loop
               pragma Loop_Invariant (Pos = Start + J - 1);
               pragma Loop_Invariant (Pos <= Last - (Code - 1 - J));
               pragma Loop_Invariant (Used <= Wire.Max_Frame);
               if Data (Pos) = 0 or else Used = Wire.Max_Frame then
                  return;
               end if;
               Used := Used + 1;
               Output (Used) := Data (Pos);
               Pos := Pos + 1;
            end loop;
         end;
         if Code < 255 and then Pos <= Last then
            if Used = Wire.Max_Frame then
               return;
            end if;
            Used := Used + 1;
            Output (Used) := 0;
         end if;
      end loop;
      Count := Used;
      Valid := True;
   end Decode;
end Beacon.Framing;
