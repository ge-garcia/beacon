package Shutdown_Test_Support is
   --  Holds a transport operation until the test explicitly releases it.
   protected type Operation_Gate is
      procedure Enter_Operation;
      entry Wait_Entered;
      entry Await_Release;
      procedure Release_Operation;
      function Finished return Boolean;
      procedure Finish_Operation;
   private
      Entered  : Boolean := False;
      Released : Boolean := False;
      Done     : Boolean := False;
   end Operation_Gate;

   --  Prints the failure and exits without waiting for dependent tasks.
   --  A test of Stop cannot rely on Stop to clean up a failed test.
   procedure Fail (Message : String) with No_Return;
end Shutdown_Test_Support;
