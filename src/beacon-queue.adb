package body Beacon.Queue
  with SPARK_Mode => On
is

   function Next (I : Ring_Index) return Ring_Index is
     ((I + 1) mod Depth);

   procedure Push (Q : in out Queue_Type; Item : Element_Type) is
   begin
      Q.Buffer (Q.Tail) := Item;
      Q.Tail := Next (Q.Tail);
      Q.Fill := Q.Fill + 1;
   end Push;

   procedure Push_Dropping_Oldest
     (Q       : in out Queue_Type;
      Item    : Element_Type;
      Dropped : out Boolean)
   is
   begin
      Dropped := Is_Full (Q);
      if Dropped then
         --  Overwrite the oldest element: move Head past it. Fill does not change.
         Q.Head := Next (Q.Head);
         Q.Buffer (Q.Tail) := Item;
         Q.Tail := Next (Q.Tail);
      else
         Push (Q, Item);
      end if;
   end Push_Dropping_Oldest;

   procedure Pop (Q : in out Queue_Type; Item : out Element_Type) is
   begin
      Item := Q.Buffer (Q.Head);
      Q.Head := Next (Q.Head);
      Q.Fill := Q.Fill - 1;
   end Pop;

end Beacon.Queue;
