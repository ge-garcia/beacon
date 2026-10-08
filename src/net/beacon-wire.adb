package body Beacon.Wire is

   use type Interfaces.Unsigned_16;

   --  Header has Scalar_Storage_Order High_Order_First. Byte_Array has no
   --  storage order. The overlay of a Header on a Byte_Array is the byte
   --  order conversion that we want, so this warning is not useful here.
   pragma Warnings (Off, "overlay changes scalar storage order");

   --  CRC-32 (IEEE 802.3, reflected), without a lookup table. This is the
   --  same polynomial as zlib and PNG. The checksum scheme is decided.
   function Checksum (Data : Byte_Array) return Checksum_Type is
      Poly : constant Checksum_Type := 16#EDB88320#;
      C    : Checksum_Type := 16#FFFFFFFF#;
   begin
      for B of Data loop
         C := C xor Checksum_Type (B);
         for Bit in 1 .. 8 loop
            if (C and 1) = 1 then
               C := (C / 2) xor Poly;
            else
               C := C / 2;
            end if;
         end loop;
      end loop;
      return C xor 16#FFFFFFFF#;
   end Checksum;

   ------------
   -- Encode --
   ------------

   procedure Encode
     (Topic    : Topic_Id_Type;
      Sequence : Sequence_Type;
      Payload  : Byte_Array;
      Frame    : out Byte_Array;
      Last     : out Natural)
   is
      First : constant Positive := Frame'First;
      --  Write the header through this overlay only. Do not pack bytes by hand.
      H : Header with Import, Address => Frame (First)'Address;
   begin
      Frame := [others => 0];
      Last  := First + Header_Length + Payload'Length - 1;
      H := (Magic    => Magic_Value,
            Topic    => Topic,
            Sequence => Sequence,
            Length   => Payload'Length,
            Checksum => 0);
      Frame (First + Header_Length .. Last) := Payload;
      H.Checksum := Checksum (Frame (First .. Last));
   end Encode;

   ------------
   -- Decode --
   ------------

   procedure Decode
     (Frame        : Byte_Array;
      Topic        : out Topic_Id_Type;
      Sequence     : out Sequence_Type;
      Payload      : out Byte_Array;
      Payload_Last : out Natural;
      Status       : out Decode_Status)
   is
      First : constant Positive := Frame'First;
   begin
      Topic        := 0;
      Sequence     := 0;
      Payload      := [others => 0];
      Payload_Last := Payload'First - 1;

      if Frame'Length < Header_Length then
         Status := Too_Short;
         return;
      end if;

      declare
         H : Header with Import, Address => Frame (First)'Address;
      begin
         if not H.Magic'Valid or else H.Magic /= Magic_Value then
            Status := Bad_Magic;
            return;
         end if;
         if not H.Length'Valid
           or else Header_Length + Natural (H.Length) /= Frame'Length
         then
            Status := Bad_Length;
            return;
         end if;

         --  Calculate the checksum again with the Checksum field set to 0.
         --  Use a copy, because Frame is an in parameter.
         declare
            Copy : Byte_Array (1 .. Frame'Length) := Frame;
            HC   : Header with Import, Address => Copy (1)'Address;
            Sent : constant Checksum_Type := HC.Checksum;
         begin
            HC.Checksum := 0;
            if Checksum (Copy) /= Sent then
               Status := Bad_Checksum;
               return;
            end if;
         end;

         Topic    := H.Topic;
         Sequence := H.Sequence;
         Payload_Last := Payload'First + Natural (H.Length) - 1;
         Payload (Payload'First .. Payload_Last) :=
           Frame (First + Header_Length .. Frame'Last);
         Status := Ok;
      end;
   end Decode;

end Beacon.Wire;
