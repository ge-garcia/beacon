--  Telemetry: the message types and topic instantiations for all demo
--  programs. This file is the static topic registry (design rule 4). A
--  program that withs it knows each topic and each type at compile time.

with Beacon.Topic;
with System;

package Telemetry is

   type Sensor_Id is range 0 .. 255 with Size => 8;

   --  This record has a representation clause. Thus the codec can use an
   --  overlay and does not pack bytes by hand.
   type Reading is record
      Sensor      : Sensor_Id;
      Sequence    : Natural;
      Temperature : Float;
   end record
     with Size                 => 72,
          Bit_Order            => System.High_Order_First,
          Scalar_Storage_Order => System.High_Order_First;
   --  Scalar_Storage_Order gives network byte order.
   for Reading use record
      Sensor      at 0 range 0 .. 7;
      Sequence    at 1 range 0 .. 31;
      Temperature at 5 range 0 .. 31;
   end record;

   type Command_Kind is (Start, Stop, Reset);
   type Command is record
      Kind   : Command_Kind;
      Target : Sensor_Id;
   end record;

   --  High rate. Only the newest value is important. Subscribers use
   --  Best_Effort.
   package Temperature_Topic is new Beacon.Topic
     (Message_Type => Reading, Queue_Depth => 32);

   --  Low rate. Each message is important. Subscribers use Reliable.
   package Command_Topic is new Beacon.Topic
     (Message_Type => Command, Queue_Depth => 8);

   --  Wire topic ids for the network demo. Each instantiation has its own id.
   Temperature_Topic_Id : constant := 1;
   Command_Topic_Id     : constant := 2;

end Telemetry;
