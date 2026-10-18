--  Telemetry.Codecs: Serialize and Deserialize for each message type, for
--  the bridge. Desktop only (this package withs Beacon.Wire).
--
--  Each pair puts an overlay of the record (which has a representation
--  clause) on a Byte_Array of exactly Reading'Size / 8 bytes. Do not use
--  shifts and masks here. If you need them, the message type needs a
--  representation clause (design rule 6).

with Beacon.Wire;

package Telemetry.Codecs is

   Reading_Bytes : constant := 9;  --  Reading'Size / 8. The rep clause sets 72 bits.

   --  Writes Msg in network byte order to the first Reading_Bytes bytes of
   --  Buffer. Sets all other bytes of Buffer to 0. Last is the index of
   --  the last byte written.
   procedure Serialize_Reading
     (Msg    : Reading;
      Buffer : out Beacon.Wire.Byte_Array;
      Last   : out Natural)
     with Pre => Buffer'Length >= Reading_Bytes;

   --  Reads a Reading from Buffer. Valid is True only if Buffer is exactly
   --  Reading_Bytes long and each field holds a valid value. If Valid is
   --  False, Msg is (0, 0, 0.0).
   procedure Deserialize_Reading
     (Buffer : Beacon.Wire.Byte_Array;
      Msg    : out Reading;
      Valid  : out Boolean);

end Telemetry.Codecs;
