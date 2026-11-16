with Ada.Command_Line; use Ada.Command_Line;
with Ada.Real_Time; use Ada.Real_Time;
with Ada.Text_IO; use Ada.Text_IO;
with Beacon;
with Beacon.Bridge;
with Beacon.Transport.Serial;
with Telemetry; use Telemetry;
with Telemetry.Codecs; use Telemetry.Codecs;

procedure Serial_Publisher is
   package Link is new Beacon.Bridge
     (Temperature_Topic, Temperature_Topic_Id, Serialize_Reading, Deserialize_Reading);
   Port : aliased Beacon.Transport.Serial.Serial_Transport;
   Pub : Temperature_Topic.Publisher;
   Count : constant Positive :=
     (if Argument_Count >= 2 then Positive'Value (Argument (2)) else 200);
   Deadline : Time;
begin
   if Argument_Count < 1 then
      Put_Line ("usage: serial_publisher DEVICE [COUNT]");
      Set_Exit_Status (Failure);
      return;
   end if;
   Beacon.Transport.Serial.Open (Port, Argument (1));
   Link.Start_Egress (Port'Access, Beacon.Reliable);
   Temperature_Topic.Create_Publisher (Pub);
   for Seq in 1 .. Count loop
      Temperature_Topic.Publish
        (Pub, (Sensor => 7, Sequence => Seq, Temperature => Float (Seq) / 10.0));
      delay 0.005;
   end loop;
   Deadline := Clock + Seconds (10);
   while Beacon.Transport.Serial.Frames_Sent (Port) < Count and then Clock < Deadline loop
      delay 0.001;
   end loop;
   Link.Stop;
   if Beacon.Transport.Serial.Frames_Sent (Port) /= Count then
      Set_Exit_Status (Failure);
   end if;
   Put_Line ("serial_publisher: sent" & Beacon.Transport.Serial.Frames_Sent (Port)'Image);
   Beacon.Transport.Serial.Close (Port);
exception
   when others =>
      Link.Stop;
      Beacon.Transport.Serial.Close (Port);
      raise;
end Serial_Publisher;
