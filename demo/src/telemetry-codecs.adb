package body Telemetry.Codecs is

   --  Reading has Scalar_Storage_Order High_Order_First. The byte array has
   --  no storage order. The overlay is the byte order conversion that we
   --  want, so this warning is not useful here.
   pragma Warnings (Off, "overlay changes scalar storage order");

   procedure Serialize_Reading
     (Msg    : Reading;
      Buffer : out Beacon.Wire.Byte_Array;
      Last   : out Natural)
   is
      Overlay : Reading with Import, Address => Buffer (Buffer'First)'Address;
   begin
      Buffer := [others => 0];
      Overlay := Msg;
      Last := Buffer'First + Reading_Bytes - 1;
   end Serialize_Reading;

   procedure Deserialize_Reading
     (Buffer : Beacon.Wire.Byte_Array;
      Msg    : out Reading;
      Valid  : out Boolean)
   is
   begin
      Msg := (Sensor => 0, Sequence => 0, Temperature => 0.0);
      Valid := False;
      if Buffer'Length /= Reading_Bytes then
         return;
      end if;
      declare
         Overlay : Reading with Import, Address => Buffer (Buffer'First)'Address;
      begin
         if Overlay'Valid_Scalars then
            Msg := Overlay;
            Valid := True;
         end if;
      end;
   end Deserialize_Reading;

end Telemetry.Codecs;
