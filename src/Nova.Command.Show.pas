unit Nova.Command.Show;

{$mode objfpc}{$H+}

interface

uses
  Classes,
  SysUtils,
  fpjson,
  Nova.Command,
  Nova.Package.Spec,
  TermStyle;

type
  { TShowCommand }
  TShowCommand = class(TBaseCommand)
  private
    FShowTree: Boolean;
    FSpec: TNovaPkgSpec;
    FLockJson: TJSONObject;

    procedure LoadSpec;
    procedure LoadLockFile;
    procedure FreeLockFile;
    procedure PrintDependencies;
    procedure PrintDependency(const Dep: TDependency; IsDev: Boolean; Indent: string = '');
    procedure PrintDependencyTree(const Dep: TDependency; Indent: string = '');
    function FormatConstraint(const Dep: TDependency): string;
    function FormatVersion(const Repo: string; out Commit: string; out Installed: Boolean): string;
  public
    constructor Create; override;
    destructor Destroy; override;
    procedure Execute; override;
    function Name: string; override;
    function Description: string; override;
  end;

implementation

//uses
//  Nova.Utils;

{ TShowCommand }

constructor TShowCommand.Create;
begin
  inherited Create;
  AddOption('--tree', 'Show dependency tree instead of flat list');
  FShowTree := False;
  FLockJson := nil;
  FSpec := TNovaPkgSpec.Create;
end;

destructor TShowCommand.Destroy;
begin
  FreeLockFile;
  inherited Destroy;

  FSpec.Free;
end;

procedure TShowCommand.LoadSpec;
begin
  if not FileExists(DEP_FILE) then
    raise Exception.Create('No ' + DEP_FILE + ' found. Run "nova init" first.');

  FSpec.LoadFromFile;
end;

procedure TShowCommand.LoadLockFile;
var
  ms: TMemoryStream;
begin
  if FileExists('nova.lock') then
  begin
    ms := TMemoryStream.Create;
    try
      ms.LoadFromFile('nova.lock');
      FLockJson := TJSONObject(GetJson(ms));
    finally
      ms.Free;
    end;
  end
  else
    FLockJson := TJSONObject.Create;
end;

procedure TShowCommand.FreeLockFile;
begin
  if Assigned(FLockJson) then
    FreeAndNil(FLockJson);
end;

function TShowCommand.FormatConstraint(const Dep: TDependency): string;
begin
  if Dep.Constraint <> '' then
    Result := render('<span class="text-yellow-300">' + Dep.Constraint + '</span>')
  else
    Result := render('<span class="text-gray-400">-</span>');
end;

function TShowCommand.FormatVersion(const Repo: string; out Commit: string; out Installed: Boolean): string;
var
  RequiresObj: TJSONObject;
  LockPkg: TJSONObject;
begin
  RequiresObj := FLockJson.Objects['requires'];
  if Assigned(RequiresObj) and (RequiresObj.Find(Repo) <> nil) then
  begin
    LockPkg := RequiresObj.Objects[Repo];
    Result := render('<span class="text-green-400">' + LockPkg.Get('version','') + '</span>');
    Commit := render('<span class="text-blue-400">(' + Copy(LockPkg.Get('commit',''),1,7) + ')</span>');
    Installed := True;
  end
  else
  begin
    Result := render('<span class="text-red-500">(not installed)</span>');
    Commit := '';
    Installed := False;
  end;
end;

procedure TShowCommand.PrintDependency(const Dep: TDependency; IsDev: Boolean; Indent: string = '');
var
  Repo, Version, Commit: string;
  Installed: Boolean;
begin
  Repo := Dep.Name;

  Version := FormatVersion(Repo, Commit, Installed);

  if IsDev then
    Write(Indent, render('<span class="bg-fuchsia-600 text-slate-300">dev</span>'), ' ')
  else
    Write(Indent, render('<span class="bg-cyan-600 text-white ml-2">*</span>'), ' ');

  Write(render('<span class="text-white">' + Repo + '</span>'):50);
  Write(FormatConstraint(Dep):30, ' → ');
  Write(Version, ' ');
  if Commit <> '' then
    Write(Commit);

  if not Installed then
    Write(render('<span class="text-red-600"> [missing]</span>'));

  Writeln;

  if FShowTree then
    PrintDependencyTree(Dep, Indent + '   ');
end;

procedure TShowCommand.PrintDependencyTree(const Dep: TDependency; Indent: string = '');
var
  i: Integer;
begin
  for i := 0 to Dep.Spec.RequireCount - 1 do
    PrintDependency(Dep.Spec.RequireAt(i), False, Indent);

  for i := 0 to Dep.Spec.RequireDevCount - 1 do
    PrintDependency(Dep.Spec.RequireDevAt(i), True, Indent);
end;

procedure TShowCommand.PrintDependencies;
var
  i: Integer;
begin
  if (FSpec.RequireCount = 0) and (FSpec.RequireDevCount = 0) then
  begin
    warning('No packages installed');
    Writeln;
  end
  else
  begin
    Writeln(render('<span class="text-blue-400 font-bold">Installed packages:</span>'));
    Writeln;

    for i := 0 to FSpec.RequireCount - 1 do
      PrintDependency(FSpec.RequireAt(i), False);

    for i := 0 to FSpec.RequireDevCount - 1 do
      PrintDependency(FSpec.RequireDevAt(i), True);

    Writeln;
  end;
end;

procedure TShowCommand.Execute;
begin
  FShowTree := true; //GetOption('--tree') <> '';
  LoadSpec;
  LoadLockFile;
  try
    PrintDependencies;
  finally
    FreeLockFile;
  end;
end;

function TShowCommand.Name: string;
begin
  Result := 'show';
end;

function TShowCommand.Description: string;
begin
  Result := 'Show installed packages with dependency tree and status';
end;

end.

