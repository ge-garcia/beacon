package body Beacon.Transport.Loopback is

   protected body Mailbox is

      procedure Put (Item : Datagram) is
      begin
         if Ring.Is_Full (Q) then
            raise Queue_Full;
         end if;
         Ring.Push (Q, Item);
      end Put;

      entry Get (Item : out Datagram) when not Ring.Is_Empty (Q) is
      begin
         Ring.Pop (Q, Item);
      end Get;

   end Mailbox;

   overriding procedure Send
     (T : in out Loopback_Transport; Frame : Wire.Byte_Array)
   is
      Item : Datagram;
   begin
      if Frame'Length not in 1 .. Wire.Max_Frame then
         raise Constraint_Error;
      end if;
      Item.Length := Frame'Length;
      Item.Bytes (1 .. Item.Length) := Frame;
      T.Inbox.Put (Item);
   end Send;

   overriding procedure Receive
     (T       : in out Loopback_Transport;
      Frame   : out Wire.Byte_Array;
      Count   : out Natural;
      Timeout : Duration)
   is
      Item : Datagram;
   begin
      Frame := [others => 0];
      Count := 0;
      select
         T.Inbox.Get (Item);
      or
         delay Duration'Max (0.0, Timeout);
         return;
      end select;
      if Frame'Length < Item.Length then
         raise Constraint_Error;
      end if;
      Frame (Frame'First .. Frame'First + Item.Length - 1) := Item.Bytes (1 .. Item.Length);
      Count := Item.Length;
   end Receive;

end Beacon.Transport.Loopback;
