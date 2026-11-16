with Beacon.Framing;
with Interfaces.C;

package Beacon.Transport.Serial is
   type Serial_Transport is limited new Transport with private;
   Serial_Error : exception;

   --  Opens a POSIX device at 115200 baud, eight data bits, no parity, one stop
   --  bit, and no flow control. Call once before starting the bridge workers.
   procedure Open (T : in out Serial_Transport; Device : String);

   --  Closes the device. Stop all bridge workers before calling Close.
   procedure Close (T : in out Serial_Transport);

   --  Sends a COBS body between zero delimiters. Errors, including a two-second
   --  write timeout, raise Serial_Error and can leave a partial frame on the link.
   --  The next Send starts with zero so the receiver can recover.
   overriding procedure Send (T : in out Serial_Transport; Frame : Wire.Byte_Array);

   --  Returns one decoded body, or Count = 0 at the deadline. Partial bodies
   --  survive timeouts. Invalid or oversized bodies are discarded through zero.
   --  One task may receive while another sends; each direction has one caller.
   overriding procedure Receive
     (T : in out Serial_Transport; Frame : out Wire.Byte_Array;
      Count : out Natural; Timeout : Duration);

   --  Returns the number of complete frames written to the device.
   function Frames_Sent (T : Serial_Transport) return Natural;

private
   use type Interfaces.C.int;

   type Serial_Transport is limited new Transport with record
      Fd : Interfaces.C.int := Interfaces.C.int'(-1);
      Buffer : Framing.Encoded_Buffer := [others => 0];
      Sent : Natural := 0 with Atomic;
      Used : Natural := 0;
      Seeking : Boolean := True;
   end record;
end Beacon.Transport.Serial;
