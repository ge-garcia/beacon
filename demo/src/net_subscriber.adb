--  Network demo, receiving side.
--     net_subscriber [group] [port] [seconds]   defaults 239.255.0.1 5000 3
--  The application subscribes to the LOCAL topic exactly as in the
--  in-process demo. The bridge is the only thing that knows a network
--  exists. Prints every 500 ms, exits after Seconds.

with Ada.Command_Line;       use Ada.Command_Line;
with Ada.Real_Time;          use Ada.Real_Time;
with Ada.Text_IO;            use Ada.Text_IO;
with Beacon;                 use Beacon;
with Beacon.Bridge;
with Beacon.Transport.UDP;
with GNAT.Sockets;
with Telemetry;              use Telemetry;
with Telemetry.Codecs;       use Telemetry.Codecs;

procedure Net_Subscriber is

   package Temperature_Bridge is new Beacon.Bridge
     (Local       => Temperature_Topic,
      Topic_Id    => Temperature_Topic_Id,
      Serialize   => Serialize_Reading,
      Deserialize => Deserialize_Reading);

   Group : constant String := (if Argument_Count >= 1 then Argument (1) else "239.255.0.1");
   Port  : constant GNAT.Sockets.Port_Type :=
     (if Argument_Count >= 2 then GNAT.Sockets.Port_Type'Value (Argument (2)) else 5000);
   Secs  : constant Positive :=
     (if Argument_Count >= 3 then Positive'Value (Argument (3)) else 3);

   Net : aliased Beacon.Transport.UDP.UDP_Transport;
   Sub : aliased Temperature_Topic.Subscriber (Best_Effort);

   Deadline : constant Time := Clock + Seconds (Secs);
   Next_Report : Time := Clock + Milliseconds (500);
   R    : Reading;
   Got  : Boolean;
   Seen : Natural := 0;
   Last : Natural := 0;

begin
   Beacon.Transport.UDP.Open (Net, Group, Port);
   Temperature_Topic.Create_Subscriber (Sub);
   Temperature_Bridge.Start_Ingress (Net'Access);
   Put_Line ("net_subscriber: listening on " & Group & ":" & Port'Image);

   while Clock < Deadline loop
      Temperature_Topic.Try_Receive (Sub, R, Got);
      if Got then
         Seen := Seen + 1;
         Last := R.Sequence;
      else
         delay 0.001;
      end if;
      if Clock >= Next_Report then
         Put_Line ("  received" & Seen'Image & ", last seq" & Last'Image
                   & ", dropped locally" & Temperature_Topic.Dropped (Sub)'Image
                   & ", incomplete local deliveries"
                   & Temperature_Bridge.Local_Delivery_Failures'Image
                   & ", rejected frames" & Temperature_Bridge.Rejected_Frames'Image
                   & ", sequence gaps" & Temperature_Bridge.Sequence_Gaps'Image);
         Next_Report := Next_Report + Milliseconds (500);
      end if;
   end loop;

   Temperature_Bridge.Stop;
   Beacon.Transport.UDP.Close (Net);
   Put_Line ("net_subscriber: done," & Seen'Image & " readings");
end Net_Subscriber;
