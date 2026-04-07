program nova_bin;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  Nova.Command,
  Nova.Commands,
  SysUtils,
  TermStyle;

var
  CommandList: TCommandList;
  CmdName: string;
  Cmd: ICommand;
begin
  CommandList := TCommandList.Create;
  CmdName := LowerCase(ParamStr(1));

  try
    if (ParamCount = 0) or (CmdName = 'help') then
      // no command, show help
      CommandList.ListCommands
    else
    begin
      Cmd := CommandList.FindCommand(CmdName);

      if Cmd = nil then
      begin
        error('Unknown command: <i>' + CmdName + '</i>');
        CommandList.ListCommands;
      end
      else
        Cmd.Execute;
    end;
  finally
    CommandList.Free;
  end;
end.
