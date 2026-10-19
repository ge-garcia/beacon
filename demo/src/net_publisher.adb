--  Network demo, sending side.
--     net_publisher [group] [port] [count]     defaults 239.255.0.1 5000 200
--  Run net_subscriber in another process with the same group and port.
--  Publishes Count readings at 1 kHz through a Best_Effort egress bridge,
--  then stops.

with Ada.Command_Line;       use Ada.Command_Line;
with Ada.Text_IO;            use Ada.Text_IO;
with Beacon;                 use Beacon;
with Beacon.Bridge;
with Beacon.Transport.UDP;
with GNAT.Sockets;
with Telemetry;              use Telemetry;
with Telemetry.Codecs;       use Telemetry.Codecs;

procedure Net_Publisher is

   package Temperature_Bridge is new Beacon.Bridge
     (Local       => Temperature_Topic,
      Topic_Id    => Temperature_Topic_Id,
      Serialize   => Serialize_Reading,
      Deserialize => Deserialize_Reading);

   Group : constant String := (if Argument_Count >= 1 then Argument (1) else "239.255.0.1");
   Port  : constant GNAT.Sockets.Port_Type :=
     (if Argument_Count >= 2 then GNAT.Sockets.Port_Type'Value (Argument (2)) else 5000);
   Count : constant Positive :=
     (if Argument_Count >= 3 then Positive'Value (Argument (3)) else 200);

   Net : aliased Beacon.Transport.UDP.UDP_Transport;
   Pub : Temperature_Topic.Publisher;

begin
   Beacon.Transport.UDP.Open (Net, Group, Port);
   Temperature_Bridge.Start_Egress (Net'Access, Best_Effort);
   Temperature_Topic.Create_Publisher (Pub);

   Put_Line ("net_publisher: " & Group & ":" & Port'Image & "," & Count'Image & " readings");
   for Seq in 1 .. Count loop
      Temperature_Topic.Publish
        (Pub, (Sensor => 7, Sequence => Seq, Temperature => Float (Seq) / 10.0));
      delay 0.001;
   end loop;
   delay 0.2;  --  give the egress task time to send the queued readings
   Temperature_Bridge.Stop;
   Beacon.Transport.UDP.Close (Net);
   Put_Line ("net_publisher: done");
end Net_Publisher;
