with Ada.Command_Line; use Ada.Command_Line;
with Ada.Real_Time; use Ada.Real_Time;
with Ada.Text_IO; use Ada.Text_IO;
with Beacon;
with Beacon.Bridge;
with Beacon.Transport.Serial;
with Telemetry; use Telemetry;
with Telemetry.Codecs; use Telemetry.Codecs;

procedure Serial_Subscriber is
   package Link is new Beacon.Bridge
     (Temperature_Topic, Temperature_Topic_Id, Serialize_Reading, Deserialize_Reading);
   Port : aliased Beacon.Transport.Serial.Serial_Transport;
   Sub : aliased Temperature_Topic.Subscriber (Beacon.Reliable);
   Count : constant Positive :=
     (if Argument_Count >= 2 then Positive'Value (Argument (2)) else 200);
   Seen : Natural := 0;
   Got : Boolean;
   Item : Reading;
   Deadline : Time;
begin
   if Argument_Count < 1 then
      Put_Line ("usage: serial_subscriber DEVICE [COUNT]");
      Set_Exit_Status (Failure);
      return;
   end if;
   Beacon.Transport.Serial.Open (Port, Argument (1));
   Temperature_Topic.Create_Subscriber (Sub);
   Link.Start_Ingress (Port'Access);
   Put_Line ("serial_subscriber: ready");
   Flush;
   Deadline := Clock + Seconds (15);
   while Seen < Count and then Clock < Deadline loop
      Temperature_Topic.Try_Receive (Sub, Item, Got);
      if Got then
         Seen := Seen + 1;
         if Item.Sensor /= 7 or else Item.Sequence /= Seen
           or else Item.Temperature /= Float (Seen) / 10.0
         then
            raise Program_Error with "serial reading differs from expected value";
         end if;
      else
         delay 0.001;
      end if;
   end loop;
   Link.Stop;
   Beacon.Transport.Serial.Close (Port);
   if Seen /= Count or else Link.Rejected_Frames /= 0
     or else Link.Local_Delivery_Failures /= 0 or else Link.Sequence_Gaps /= 0
   then
      Set_Exit_Status (Failure);
   end if;
   Put_Line ("serial_subscriber: received" & Seen'Image & " readings in order");
exception
   when others =>
      Link.Stop;
      Beacon.Transport.Serial.Close (Port);
      raise;
end Serial_Subscriber;
