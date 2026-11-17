with Ada.Real_Time;

package body Beacon.Topic is

   -------------------
   -- Bounded_Queue --
   -------------------

   protected body Bounded_Queue is

      procedure Update_Barriers is
      begin
         Full  := Ring.Is_Full (Q);
         Empty := Ring.Is_Empty (Q);
      end Update_Barriers;

      entry Push (Msg : Message_Type)
        when Mode = Best_Effort or else not Full
      is
         Dropped : Boolean;
      begin
         if Mode = Best_Effort then
            Ring.Push_Dropping_Oldest (Q, Msg, Dropped);
            if Dropped then
               Drops := Drops + 1;
            end if;
         else
            Ring.Push (Q, Msg);
         end if;
         Update_Barriers;
      end Push;

      procedure Try_Push (Msg : Message_Type; Accepted : out Boolean) is
         Dropped : Boolean;
      begin
         if Mode = Best_Effort then
            Ring.Push_Dropping_Oldest (Q, Msg, Dropped);
            if Dropped then
               Drops := Drops + 1;
            end if;
            Accepted := True;
         elsif Ring.Is_Full (Q) then
            Accepted := False;
         else
            Ring.Push (Q, Msg);
            Accepted := True;
         end if;
         Update_Barriers;
      end Try_Push;

      entry Pop (Msg : out Message_Type) when not Empty is
      begin
         Ring.Pop (Q, Msg);
         Update_Barriers;
      end Pop;

      procedure Try_Pop (Result : out Msg_Result) is
      begin
         if Ring.Is_Empty (Q) then
            Result := (Success => False);
         else
            declare
               Msg : Message_Type;
            begin
               Ring.Pop (Q, Msg);
               Result := (Success => True, Msg => Msg);
            end;
         end if;
         Update_Barriers;
      end Try_Pop;

      function Count return Natural is (Ring.Count (Q));
      function Drop_Count return Natural is (Drops);

   end Bounded_Queue;

   --------------
   -- Registry --
   --------------

   --  Fixed table. Create_Subscriber fills it at startup. The table is not
   --  protected on purpose. See the package spec.
   type Subscriber_Access is access all Subscriber;
   type Registry_Array is array (1 .. Max_Subscribers) of Subscriber_Access;

   Registry        : Registry_Array := [others => null];
   Registered      : Natural := 0;
   Publisher_Taken : Boolean := False;

   ---------------
   -- Publisher --
   ---------------

   function Has_Publisher return Boolean is (Publisher_Taken);
   function Is_Created (P : Publisher) return Boolean is (P.Created);

   procedure Create_Publisher (P : in out Publisher) is
   begin
      Publisher_Taken := True;
      P.Created := True;
   end Create_Publisher;

   procedure Publish (P : Publisher; Msg : Message_Type) is
      pragma Unreferenced (P);  --  P is used only by the precondition
   begin
      for I in 1 .. Registered loop
         Registry (I).Queue.Push (Msg);
      end loop;
   end Publish;

   procedure Try_Publish
     (P         : Publisher;
      Msg       : Message_Type;
      Delivered : out Boolean)
   is
      pragma Unreferenced (P);
      Accepted : Boolean;
   begin
      Delivered := True;
      for I in 1 .. Registered loop
         Registry (I).Queue.Try_Push (Msg, Accepted);
         Delivered := Delivered and Accepted;
      end loop;
   end Try_Publish;

   ----------------
   -- Subscriber --
   ----------------

   function Subscriber_Count return Natural is (Registered);
   function Is_Registered (S : Subscriber) return Boolean is (S.Registered);

   procedure Create_Subscriber (S : aliased in out Subscriber) is
   begin
      Registered := Registered + 1;
      Registry (Registered) := S'Unchecked_Access;
      S.Registered := True;
   end Create_Subscriber;

   procedure Receive (S : in out Subscriber; Msg : out Message_Type) is
   begin
      S.Queue.Pop (Msg);
   end Receive;

   procedure Receive
     (S       : in out Subscriber;
      Timeout : Duration;
      Result  : out Msg_Result)
   is
      use Ada.Real_Time;

      Started : constant Time := Clock;
      Elapsed : Duration;
   begin
      loop
         S.Queue.Try_Pop (Result);
         if Result.Success then
            return;
         end if;

         Elapsed := To_Duration (Clock - Started);
         if Elapsed >= Timeout then
            return;
         end if;

         --  Ravenscar and Jorvik forbid timed entry calls. Absolute delays
         --  also avoid Ravenscar's restriction on relative delays.
         delay until Clock + To_Time_Span (Duration'Min (0.001, Timeout - Elapsed));
      end loop;
   end Receive;

   procedure Try_Receive (S : in out Subscriber; Result : out Msg_Result) is
   begin
      S.Queue.Try_Pop (Result);
   end Try_Receive;

   function Pending (S : Subscriber) return Natural is (S.Queue.Count);
   function Dropped (S : Subscriber) return Natural is (S.Queue.Drop_Count);

end Beacon.Topic;
