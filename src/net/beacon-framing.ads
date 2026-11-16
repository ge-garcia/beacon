--  COBS separates wire frames with zero bytes. A damaged length prefix can
--  lose synchronization; a delimiter lets the next frame restore it.
--  COBS removes zeros from the encoded body with bounded overhead.
with Beacon.Wire;

package Beacon.Framing with SPARK_Mode => On is
   Max_Encoded : constant := Wire.Max_Frame + Wire.Max_Frame / 254 + 1;
   subtype Raw_Buffer is Wire.Byte_Array (1 .. Wire.Max_Frame);
   subtype Encoded_Buffer is Wire.Byte_Array (1 .. Max_Encoded);

   --  Encodes Count bytes. Last excludes the zero delimiter.
   procedure Encode
     (Data : Raw_Buffer; Count : Natural;
      Output : out Encoded_Buffer; Last : out Natural)
     with Pre => Count <= Wire.Max_Frame,
          Post => Last in 1 .. Max_Encoded,
          Always_Terminates;

   --  Decodes a body without delimiters. Invalid input returns Valid = False.
   --  Use Output only when Valid is True; Count is zero on failure.
   procedure Decode
     (Data : Encoded_Buffer; Last : Natural;
      Output : out Raw_Buffer; Count : out Natural; Valid : out Boolean)
     with Pre => Last <= Max_Encoded,
          Post => Count <= Wire.Max_Frame and then (if not Valid then Count = 0),
          Always_Terminates;
end Beacon.Framing;
