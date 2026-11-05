package body Beacon.Bridge is

   type Transport_Ref is access all Transport.Transport'Class;

   Rejected : Natural := 0 with Atomic;
   Undelivered : Natural := 0 with Atomic;

   type Subscriber_Ref is access Local.Subscriber;
   Gaps     : Natural := 0 with Atomic;
   Stopping : Boolean := False with Atomic;

   Poll_Timeout : constant Duration := 0.1;

   ------------
   -- Egress --
   ------------

   task type Egress_Task (Mode : Delivery_Mode) is
      entry Start (T : Transport_Ref);
   end Egress_Task;

   task body Egress_Task is
      Sub      : constant Subscriber_Ref := new Local.Subscriber (Mode);
      Net      : Transport_Ref;
      Msg      : Local.Message_Type;
      Payload  : Wire.Byte_Array (1 .. Wire.Max_Payload);
      PL       : Natural;
      Frame    : Wire.Byte_Array (1 .. Wire.Max_Frame);
      FL       : Natural;
      Sequence : Wire.Sequence_Type := 0;
      Got      : Boolean;
      use type Wire.Sequence_Type;
   begin
      accept Start (T : Transport_Ref) do
         Net := T;
         Local.Create_Subscriber (Sub.all);
      end Start;
      while not Stopping loop
         Local.Try_Receive (Sub.all, Msg, Got);
         if Got then
            Serialize (Msg, Payload, PL);
            Wire.Encode (Topic_Id, Sequence, Payload (1 .. PL), Frame, FL);
            Net.Send (Frame (1 .. FL));
            Sequence := Sequence + 1;
         else
            delay 0.001;
         end if;
      end loop;
   end Egress_Task;

   -------------
   -- Ingress --
   -------------

   task type Ingress_Task is
      entry Start (T : Transport_Ref);
   end Ingress_Task;

   task body Ingress_Task is
      Pub      : Local.Publisher;
      Net      : Transport_Ref;
      Frame    : Wire.Byte_Array (1 .. Wire.Max_Frame);
      Count    : Natural;
      Topic    : Wire.Topic_Id_Type;
      Seq      : Wire.Sequence_Type;
      Expected : Wire.Sequence_Type := 0;
      First    : Boolean := True;
      Payload  : Wire.Byte_Array (1 .. Wire.Max_Payload);
      PL       : Natural;
      Status   : Wire.Decode_Status;
      Msg      : Local.Message_Type;
      Valid    : Boolean;
      Accepted : Boolean;
      use type Wire.Decode_Status;
      use type Wire.Topic_Id_Type;
      use type Wire.Sequence_Type;
   begin
      accept Start (T : Transport_Ref) do
         Net := T;
         Local.Create_Publisher (Pub);
      end Start;
      while not Stopping loop
         Net.Receive (Frame, Count, Poll_Timeout);
         if Count > 0 then
            Wire.Decode (Frame (1 .. Count), Topic, Seq, Payload, PL, Status);
            if Status = Wire.Ok and then Topic = Topic_Id then
               if not First and then Seq /= Expected then
                  Gaps := Gaps + 1;
               end if;
               First := False;
               Expected := Seq + 1;
               Deserialize (Payload (1 .. PL), Msg, Valid);
               if Valid then
                  --  Try, not block: a stuck local subscriber must not
                  --  stall the network reader. Count incomplete fan-out
                  --  once per message, not once per refusing subscriber.
                  Local.Try_Publish (Pub, Msg, Accepted);
                  if not Accepted then
                     Undelivered := Undelivered + 1;
                  end if;
               else
                  Rejected := Rejected + 1;
               end if;
            else
               Rejected := Rejected + 1;
            end if;
         end if;
      end loop;
   end Ingress_Task;

   ---------------------------------------------------------------------

   type Egress_Access  is access Egress_Task;
   type Ingress_Access is access Ingress_Task;
   --  Allocated once per Start, never freed: the task lives until Stop
   --  and the program ends. Desktop only (src/net), so a heap is fine.

   Egress  : Egress_Access;
   Ingress : Ingress_Access;

   procedure Start_Egress
     (T    : not null access Transport.Transport'Class;
      Mode : Delivery_Mode) is
   begin
      if Stopping or else Egress /= null then
         raise Program_Error with "egress may only start once before Stop";
      end if;
      Egress := new Egress_Task (Mode);
      Egress.Start (Transport_Ref (T));
   end Start_Egress;

   procedure Start_Ingress
     (T : not null access Transport.Transport'Class) is
   begin
      if Stopping or else Ingress /= null then
         raise Program_Error with "ingress may only start once before Stop";
      end if;
      Ingress := new Ingress_Task;
      Ingress.Start (Transport_Ref (T));
   end Start_Ingress;

   procedure Stop is
   begin
      Stopping := True;
      --  Terminated also covers a task that exited through an exception.
      --  Keep T alive until both workers have stopped using it.
      while (Egress /= null and then not Egress.all'Terminated)
        or else (Ingress /= null and then not Ingress.all'Terminated)
      loop
         delay 0.001;
      end loop;
   end Stop;

   function Local_Delivery_Failures return Natural is (Undelivered);

   function Rejected_Frames return Natural is (Rejected);
   function Sequence_Gaps   return Natural is (Gaps);

end Beacon.Bridge;
