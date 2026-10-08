--  Telemetry.Codecs: Serialize and Deserialize for each message type, for
--  the bridge. Desktop only (this package withs Beacon.Wire).
--
--  Each pair puts an overlay of the record (which has a representation
--  clause) on a Byte_Array of exactly Reading'Size / 8 bytes. Do not use
--  shifts and masks here.

with Beacon.Wire;

package Telemetry.Codecs is

   Reading_Bytes : constant := 9;  --  Reading'Size / 8. The rep clause sets 72 bits.

   procedure Serialize_Reading
     (Msg    : Reading;
      Buffer : out Beacon.Wire.Byte_Array;
      Last   : out Natural)
     with Pre => Buffer'Length >= Reading_Bytes;

   procedure Deserialize_Reading
     (Buffer : Beacon.Wire.Byte_Array;
      Msg    : out Reading;
      Valid  : out Boolean);

end Telemetry.Codecs;
