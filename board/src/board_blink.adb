with Ada.Real_Time; use Ada.Real_Time;
with Blink_Topic;   use Blink_Topic;
with Pico;
with RP.GPIO;

--  Blinks the LED at 1 Hz. Each cycle publishes the next LED state, and
--  sets the LED from the state that the subscriber receives.
procedure Board_Blink
  with No_Return
is
   Pub   : LED_State.Publisher;
   State : Boolean := False;
   Next  : Time := Clock;
begin
   LED_State.Create_Publisher (Pub);
   LED_State.Create_Subscriber (Sub);
   Pico.LED.Configure (RP.GPIO.Output);

   loop
      LED_State.Publish (Pub, not State);
      LED_State.Receive (Sub, State);
      if State then
         Pico.LED.Set;
      else
         Pico.LED.Clear;
      end if;

      Next := Next + Milliseconds (500);
      delay until Next;
   end loop;
end Board_Blink;
