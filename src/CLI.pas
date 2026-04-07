unit CLI;

uses
  Classes;

type
  TCommand = class
    Name, Description: string;
    procedure Execute; virtual; abstract;
  end;

  TCLI = class
  private
    FCommands: TObjectList;
  public
    constructor Create;
    destructor Destroy; override;
    procedure RegisterCommand(Cmd: TCommand);
    procedure Run;
    procedure ShowUsage;
    procedure ShowVersion;
  end;

implementation

constructor TCLI.Create;
begin
  FCommands := TObjectList.Create(True);
end;

destructor TCLI.Destroy;
begin
  FCommands.Free;
  inherited;
end;

procedure TCLI.RegisterCommand(Cmd: TCommand);
begin
  FCommands.Add(Cmd);
end;

procedure TCLI.Run;
begin
  // parse argv and execute appropriate command
end;

procedure TCLI.ShowUsage;
begin
end;

procedure TCLI.ShowVersion;
begin
end;

end.
