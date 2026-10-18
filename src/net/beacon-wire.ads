--  Beacon.Wire: frame layout for the network backend.
--
--  Design rule 6: the header is a record with a representation clause.
--  The code uses no shifts and no masks. An overlay puts the header on
--  the first Header_Length bytes of a frame. Scalar_Storage_Order gives
--  network byte order (big-endian). No code swaps bytes by hand.
--
--  Frame layout. Status: draft. The Week 13 review must sign it off.
--  The checksum scheme (CRC-32) is already decided.
--
--     byte  size  field
--     0     2     Magic          16#BEAC#
--     2     2     Topic          Topic_Id_Type, set statically for each Bridge
--     4     4     Sequence       counts frames for each topic, wraps at 2**32
--     8     2     Length         number of payload bytes after the header
--     10    4     Checksum       CRC-32 of header (with Checksum = 0) + payload
--     14    L     Payload        L = Length, a serialized Message_Type
--
--  Only this package and Beacon.Bridge use bytes. Bytes never reach the
--  API of Beacon.Topic (design rule 1).

with Interfaces;
with System;

package Beacon.Wire is

   type Byte is mod 2 ** 8 with Size => 8;
   type Byte_Array is array (Positive range <>) of Byte with Pack;

   Max_Payload   : constant := 1024;
   Header_Length : constant := 14;
   Max_Frame     : constant := Header_Length + Max_Payload;

   Magic_Value : constant := 16#BEAC#;

   type Topic_Id_Type  is range 0 .. 2 ** 16 - 1 with Size => 16;
   type Sequence_Type  is mod 2 ** 32 with Size => 32;
   type Length_Type    is range 0 .. Max_Payload with Size => 16;
   type Checksum_Type  is mod 2 ** 32 with Size => 32;

   type Header is record
      Magic    : Interfaces.Unsigned_16;
      Topic    : Topic_Id_Type;
      Sequence : Sequence_Type;
      Length   : Length_Type;
      Checksum : Checksum_Type;
   end record
     with Size                 => Header_Length * 8,
          Bit_Order            => System.High_Order_First,
          Scalar_Storage_Order => System.High_Order_First;

   for Header use record
      Magic    at 0  range 0 .. 15;
      Topic    at 2  range 0 .. 15;
      Sequence at 4  range 0 .. 31;
      Length   at 8  range 0 .. 15;
      Checksum at 10 range 0 .. 31;
   end record;

   type Decode_Status is
     (Ok,
      Too_Short,        --  fewer than Header_Length bytes
      Bad_Magic,        --  Magic is not Magic_Value
      Bad_Length,       --  Length is above Max_Payload, or Frame is not
                        --  exactly Header_Length + Length bytes
      Bad_Checksum);    --  the checksum of header + payload does not agree

   --  CRC-32 (IEEE 802.3, the same as zlib). This scheme is decided.
   --  Test vector: "123456789" gives 16#CBF43926#.
   function Checksum (Data : Byte_Array) return Checksum_Type;

   --  Writes one frame (header + Payload) at the start of Frame. Last is
   --  the index of the last byte of the frame. Encode sets all other bytes
   --  of Frame to 0.
   procedure Encode
     (Topic    : Topic_Id_Type;
      Sequence : Sequence_Type;
      Payload  : Byte_Array;
      Frame    : out Byte_Array;
      Last     : out Natural)
     with Pre  => Payload'Length <= Max_Payload
                  and then Frame'Length >= Max_Frame,
          Post => Last = Frame'First + Header_Length + Payload'Length - 1;

   --  Reads one frame. Frame must be exactly one frame: Header_Length +
   --  Length bytes. If a datagram has more bytes, Status is Bad_Length.
   --  Decode never raises an exception for bad input. It always sets
   --  Status.
   --  Status = Ok: Topic and Sequence come from the header. The payload
   --  is in Payload (Payload'First .. Payload_Last).
   --  Other Status: Topic and Sequence are 0, Payload is all 0, and
   --  Payload_Last is Payload'First - 1.
   procedure Decode
     (Frame        : Byte_Array;
      Topic        : out Topic_Id_Type;
      Sequence     : out Sequence_Type;
      Payload      : out Byte_Array;
      Payload_Last : out Natural;
      Status       : out Decode_Status)
     with Pre => Payload'Length >= Max_Payload;

end Beacon.Wire;
