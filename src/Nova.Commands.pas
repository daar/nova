unit Nova.Commands;

{$mode objfpc}{$H+}

interface

uses
  Classes,
  Nova.Command,
  Nova.Command.Init,
  Nova.Command.Show,
  SysUtils,
  TermStyle;

type
  { TCommandList }
  TCommandList = class
  private
    FCommands: TInterfaceList; // store ICommand interfaces
  public
    constructor Create;
    destructor Destroy; override;

    procedure RegisterCommand(Cmd: ICommand);
    function FindCommand(const CmdName: string): ICommand;
    procedure ListCommands;
  end;

implementation

{---------------- TCommandList -----------------}

constructor TCommandList.Create;
begin
  inherited Create;
  FCommands := TInterfaceList.Create;

  // Register all commands
  RegisterCommand(TInitCommand.Create);
  RegisterCommand(TRequireCommand.Create);
  RegisterCommand(TRemoveCommand.Create);
  RegisterCommand(TUpdateCommand.Create);
  RegisterCommand(TInstallCommand.Create);
  RegisterCommand(TShowCommand.Create);
end;

destructor TCommandList.Destroy;
begin
  FCommands.Free;
  inherited Destroy;
end;

procedure TCommandList.RegisterCommand(Cmd: ICommand);
begin
  FCommands.Add(Cmd);
end;

function TCommandList.FindCommand(const CmdName: string): ICommand;
var
  i:   integer;
  Cmd: ICommand;
begin
  Result := nil;
  for i := 0 to FCommands.Count - 1 do
  begin
    Cmd := ICommand(FCommands[i]);
    if Cmd.name = CmdName then
    begin
      Result := Cmd;
      Exit;
    end;
  end;
end;

procedure TCommandList.ListCommands;
var
  i:   integer;
  Cmd: ICommand;
begin
  // Banner
  Writeln('Nova ', {$I version.inc});
  Writeln('Copyright (c) 2025 by Darius Blaszyk');
  Writeln;

  // Usage
  Writeln(render('<b>USAGE</b>'));
  Writeln(render('  nova [<span class="text-yellow-600">command-name</span>] [<span class="text-yellow-600">command-options ...</span>]'));
  Writeln;

  // Commands
  Writeln(render('<b>COMMANDS</b>'));
  for i := 0 to FCommands.Count - 1 do
  begin
    Cmd := ICommand(FCommands[i]);
    Writeln(render(Format('<span class="text-green-700">  %-15s</span> %s', [Cmd.name, Cmd.Description])));
  end;
  Writeln(render(Format('<span class="text-green-700">  %-15s</span> %s',
    ['help', 'Display this help message'])));
  Writeln(render(Format('<span class="text-green-700">  %-15s</span> %s', ['version', 'Show nova version'])));
  Writeln;

  // Examples
  Writeln(render('<b>EXAMPLES</b>'));
  Writeln(render('<span class="text-cyan-400">  nova init</span>'));
  Writeln(render('<span class="text-cyan-400">  nova require daar/linkedlist</span>'));
  Writeln(render('<span class="text-cyan-400">  nova require daar/linkedlist:1.0.0 --dev</span>'));
  Writeln(render('<span class="text-cyan-400">  nova show --tree</span>'));
  Writeln;
end;

end.
