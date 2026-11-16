with Ada.Text_IO;
with GNAT.OS_Lib;

package body Shutdown_Test_Support is
   protected body Operation_Gate is
      procedure Enter_Operation is
      begin
         Entered := True;
      end Enter_Operation;
      entry Wait_Entered when Entered is
      begin
         null;
      end Wait_Entered;
      entry Await_Release when Released is
      begin
         null;
      end Await_Release;
      procedure Release_Operation is
      begin
         Released := True;
      end Release_Operation;
      function Finished return Boolean is (Done);
      procedure Finish_Operation is
      begin
         Done := True;
      end Finish_Operation;
   end Operation_Gate;

   procedure Fail (Message : String) is
   begin
      Ada.Text_IO.Put_Line (Ada.Text_IO.Standard_Error, "FAIL: " & Message);
      Ada.Text_IO.Flush (Ada.Text_IO.Standard_Error);
      GNAT.OS_Lib.OS_Exit (1);
   end Fail;
end Shutdown_Test_Support;
