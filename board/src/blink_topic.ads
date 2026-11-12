with Beacon;
with Beacon.Topic;

--  The LED state, sent through Beacon.Topic. Jorvik does not permit
--  local protected objects. Thus the instance and its subscriber are at
--  library level.
package Blink_Topic is

   package LED_State is new Beacon.Topic
     (Message_Type => Boolean, Queue_Depth => 4, Max_Subscribers => 1);

   Sub : aliased LED_State.Subscriber (Beacon.Reliable);

end Blink_Topic;
