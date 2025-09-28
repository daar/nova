unit Nova.Command;

{$mode objfpc}{$H+}

interface

uses
  Classes,
  SysUtils;

type
  { ICommand interface }
  ICommand = interface
    ['{C8B1590B-7E2E-4D8A-B7C3-F05B8F3C07F2}']
    procedure Execute;
    function name: string;
    function Description: string;
    procedure AddOption(const OptName, OptDesc: string);
    function OptionCount: integer;
    function Option(Index: integer): TObject;
  end;

  { TOption class }
  TOption = class
  public
    name: string;
    Description: string;
    constructor Create(const AName, ADescription: string);
  end;

  { TBaseCommand class }
  TBaseCommand = class(TInterfacedObject, ICommand)
  private
    FOptions: TList; // store TOption objects
  public
    constructor Create; virtual;
    destructor Destroy; override;

    // ICommand
    procedure Execute; virtual; abstract;
    function name: string; virtual; abstract;
    function Description: string; virtual; abstract;

    procedure AddOption(const OptName, OptDesc: string);
    function HasOption(const OptionName: string): Boolean;

    function OptionCount: integer;
    function Option(Index: integer): TObject;
  end;

  { Command Implementations }

  TRequireCommand = class(TBaseCommand)
  public
    constructor Create; override;
    procedure Execute; override;
    function name: string; override;
    function Description: string; override;
  end;

  TRemoveCommand = class(TBaseCommand)
  public
    procedure Execute; override;
    function name: string; override;
    function Description: string; override;
  end;

  TUpdateCommand = class(TBaseCommand)
  public
    constructor Create; override;
    procedure Execute; override;
    function name: string; override;
    function Description: string; override;
  end;

  TInstallCommand = class(TBaseCommand)
  public
    constructor Create; override;
    procedure Execute; override;
    function name: string; override;
    function Description: string; override;
  end;

implementation

uses
  fpjson,
  jsonscanner,
  process,
  TermStyle;

  { TOption }

constructor TOption.Create(const AName, ADescription: string);
begin
  name := AName;
  Description := ADescription;
end;

{ TBaseCommand }

constructor TBaseCommand.Create;
begin
  inherited Create;
  FOptions := TList.Create;
end;

destructor TBaseCommand.Destroy;
var
  i: integer;
begin
  for i := 0 to FOptions.Count - 1 do
    TObject(FOptions[i]).Free;
  FOptions.Free;
  inherited Destroy;
end;

procedure TBaseCommand.AddOption(const OptName, OptDesc: string);
begin
  FOptions.Add(TOption.Create(OptName, OptDesc));
end;

function TBaseCommand.HasOption(const OptionName: string): Boolean;
var
  i: Integer;
  CleanOpt: string;
begin
  Result := False;
  CleanOpt := LowerCase(OptionName);

  for i := 0 to ParamCount do
  begin
    if (LowerCase(ParamStr(i)) = CleanOpt) or
       (Pos(CleanOpt + '=', LowerCase(ParamStr(i))) = 1) then
      exit(true);
  end;
  exit(false);
end;

function TBaseCommand.OptionCount: integer;
begin
  Result := FOptions.Count;
end;

function TBaseCommand.Option(Index: integer): TObject;
begin
  //Result := FOptions[Index];
end;

{ TRequireCommand }

constructor TRequireCommand.Create;
begin
  inherited Create;
  AddOption('--dev', 'Include packages as development requirement');
end;

procedure TRequireCommand.Execute;
begin
  writeln('Executing "require" command...');
end;

function TRequireCommand.name: string;
begin
  Result := 'require';
end;

function TRequireCommand.Description: string;
begin
  Result := 'Add one or more packages as requirement';
end;

{ TRemoveCommand }

procedure TRemoveCommand.Execute;
begin
  writeln('Executing "remove" command...');
end;

function TRemoveCommand.name: string;
begin
  Result := 'remove';
end;

function TRemoveCommand.Description: string;
begin
  Result := 'Remove one or more packages';
end;

{ TUpdateCommand }

constructor TUpdateCommand.Create;
begin
  inherited Create;
  AddOption('--dev', 'Include as development requirement');
end;

procedure TUpdateCommand.Execute;
begin
  writeln('Executing "update" command...');
end;

function TUpdateCommand.name: string;
begin
  Result := 'update';
end;

function TUpdateCommand.Description: string;
begin
  Result := 'Update dependency versions and regenerate the lockfile';
end;

{ TInstallCommand }

constructor TInstallCommand.Create;
begin
  inherited Create;
  AddOption('--dev', 'Include packages as development requirement');
end;

procedure TInstallCommand.Execute;
begin
  writeln('Executing "install" command...');
end;

function TInstallCommand.name: string;
begin
  Result := 'install';
end;

function TInstallCommand.Description: string;
begin
  Result := 'Install all requirements and update lock file';
end;

end.
