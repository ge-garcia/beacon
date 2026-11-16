with Ada.Real_Time; use Ada.Real_Time;
with Interfaces.C.Strings;
with System;

package body Beacon.Transport.Serial is
   package C renames Interfaces.C;

   function Device_Open (Path : C.Strings.chars_ptr) return C.int
     with Import, Convention => C, External_Name => "beacon_serial_open";
   function Device_Read (Fd : C.int) return C.int
     with Import, Convention => C, External_Name => "beacon_serial_read";
   function Device_Write (Fd : C.int; Data : System.Address; Count : C.int) return C.int
     with Import, Convention => C, External_Name => "beacon_serial_write";
   procedure Device_Close (Fd : C.int)
     with Import, Convention => C, External_Name => "beacon_serial_close";

   function Frames_Sent (T : Serial_Transport) return Natural is (T.Sent);

   procedure Open (T : in out Serial_Transport; Device : String) is
      Path : C.Strings.chars_ptr;
   begin
      if T.Fd /= -1 then
         raise Serial_Error with "serial device is already open";
      end if;
      Path := C.Strings.New_String (Device);
      T.Fd := Device_Open (Path);
      C.Strings.Free (Path);
      if T.Fd = -1 then
         raise Serial_Error with "cannot open serial device: " & Device;
      end if;
      T.Used := 0;
      T.Sent := 0;
      T.Seeking := True;
   end Open;

   procedure Close (T : in out Serial_Transport) is
   begin
      if T.Fd /= -1 then
         Device_Close (T.Fd);
         T.Fd := Interfaces.C.int'(-1);
      end if;
   end Close;

   overriding procedure Send (T : in out Serial_Transport; Frame : Wire.Byte_Array) is
      Raw : Framing.Raw_Buffer := [others => 0];
      Body_Data : Framing.Encoded_Buffer;
      Packet : Wire.Byte_Array (1 .. Framing.Max_Encoded + 2) := [others => 0];
      Last : Natural;
      Sent : Natural := 0;
      Result : C.int;
      Deadline : constant Time := Clock + Seconds (2);
   begin
      if Frame'Length = 0 or else Frame'Length > Wire.Max_Frame then
         raise Constraint_Error with "invalid serial frame size";
      end if;
      Raw (1 .. Frame'Length) := Frame;
      Framing.Encode (Raw, Frame'Length, Body_Data, Last);
      Packet (2 .. Last + 1) := Body_Data (1 .. Last);
      while Sent < Last + 2 loop
         Result := Device_Write (T.Fd, Packet (Sent + 1)'Address, C.int (Last + 2 - Sent));
         if Result < 0 or else Clock >= Deadline then
            raise Serial_Error with "serial write failed or timed out";
         elsif Result = 0 then
            delay 0.001;
         else
            Sent := Sent + Natural (Result);
         end if;
      end loop;
      T.Sent := T.Sent + 1;
   end Send;

   overriding procedure Receive
     (T : in out Serial_Transport; Frame : out Wire.Byte_Array;
      Count : out Natural; Timeout : Duration)
   is
      Deadline : constant Time := Clock + To_Time_Span (Duration'Max (0.0, Timeout));
      Value : C.int;
      Raw : Framing.Raw_Buffer;
      Used : Natural;
      Valid : Boolean;
   begin
      Frame := [others => 0];
      Count := 0;
      loop
         Value := Device_Read (T.Fd);
         if Value = -1 then
            raise Serial_Error with "serial read failed";
         elsif Value = 0 then
            if not T.Seeking and then T.Used > 0 then
               Framing.Decode (T.Buffer, T.Used, Raw, Used, Valid);
               T.Used := 0;
               if Valid and then Used > 0 then
                  if Used > Frame'Length then
                     raise Constraint_Error with "serial receive buffer is too small";
                  end if;
                  Frame (Frame'First .. Frame'First + Used - 1) := Raw (1 .. Used);
                  Count := Used;
                  return;
               end if;
            end if;
            T.Seeking := False;
            T.Used := 0;
         elsif Value > 0 and then not T.Seeking then
            if T.Used = Framing.Max_Encoded then
               T.Seeking := True;
               T.Used := 0;
            else
               T.Used := T.Used + 1;
               T.Buffer (T.Used) := Wire.Byte (Value);
            end if;
         end if;
         exit when Clock >= Deadline;
         if Value = -2 then
            delay until (if Clock + Milliseconds (1) < Deadline
                         then Clock + Milliseconds (1) else Deadline);
         end if;
      end loop;
   end Receive;
end Beacon.Transport.Serial;
