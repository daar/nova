unit Nova.Command.Show;

{$mode objfpc}{$H+}

interface

uses
  Nova.Command;

type

  { TShowCommand }

  TShowCommand = class(TBaseCommand)
  public
    constructor Create; override;
    procedure Execute; override;
    function Name: string; override;
    function Description: string; override;
  end;

implementation

{ TShowCommand }

constructor TShowCommand.Create;
begin
  inherited Create;
  AddOption('--tree', 'Show dependency tree instead of flat list');
end;

procedure TShowCommand.Execute;
begin
  writeln('Executing "show" command...');
end;

function TShowCommand.Name: string;
begin
  Result := 'show';
end;

function TShowCommand.Description: string;
begin
  Result := 'Show installed packages';
end;

end.
