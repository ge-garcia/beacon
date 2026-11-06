--  Beacon.Transport: how a frame leaves and enters the process.
--
--  Beacon.Bridge talks to this interface. Implementations are UDP multicast
--  (Beacon.Transport.UDP) and an in-memory FIFO (Beacon.Transport.Loopback).

with Beacon.Wire;

package Beacon.Transport is

   type Transport is limited interface;

   Would_Block : exception;

   --  Sends one frame, or raises Would_Block without sending it when capacity
   --  is temporarily exhausted; the caller may retry the same frame.
   procedure Send
     (T : in out Transport; Frame : Wire.Byte_Array) is abstract;

   --  Blocks up to Timeout. Count = 0 on timeout.
   procedure Receive
     (T       : in out Transport;
      Frame   : out Wire.Byte_Array;
      Count   : out Natural;
      Timeout : Duration) is abstract;

end Beacon.Transport;
