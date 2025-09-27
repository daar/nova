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
    procedure PrintDependencyTree(
      const Dep: TDependency;
      const Prefix: string = '';
      const IsLast: Boolean = True;
      Visited: TStringList = nil;
      const IsDev: Boolean = False);
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

  FSpec.LoadFromFile(DEP_FILE);
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

procedure TShowCommand.PrintDependencyTree(
  const Dep: TDependency;
  const Prefix: string = '';
  const IsLast: Boolean = True;
  Visited: TStringList = nil;
  const IsDev: Boolean = False);
var
  DepPath: string;
  DepLock: TJSONObject;
  RequiresObj: TJSONObject;
  i, ChildrenCount: Integer;
  Child: TDependency;
  ms: TMemoryStream;
  AlreadyVisited: Boolean;
  VersionStr, CommitStr: string;
  TreeChar, NewPrefix: string;
begin
  // Initialize visited list on first call
  if Visited = nil then
    Visited := TStringList.Create;

  try
    // Circular dependency detection
    AlreadyVisited := Visited.IndexOf(Dep.Name) >= 0;
    if AlreadyVisited then
    begin
      Writeln(render(Prefix + '└─ ' + Dep.Name +
        ' <span class="text-yellow-300">(circular dependency)</span>'));
      Exit;
    end;

    Visited.Add(Dep.Name);

    // Determine tree characters
    if IsLast then
      TreeChar := '└─ '
    else
      TreeChar := '├─ ';

    if IsLast then
      NewPrefix := Prefix + '   '
    else
      NewPrefix := Prefix + '│  ';

    // Compute dependency path
    DepPath := IncludeTrailingPathDelimiter('vendor' + PathDelim + Dep.Name);

    // Load lock file
    DepLock := nil;
    if FileExists(DepPath + 'nova.lock') then
    begin
      ms := TMemoryStream.Create;
      try
        ms.LoadFromFile(DepPath + 'nova.lock');
        DepLock := TJSONObject(GetJson(ms));
      finally
        ms.Free;
      end;
    end;

    // Format version & commit
    VersionStr := '';
    CommitStr := '';
    if Assigned(DepLock) then
    begin
      if DepLock.Find('requires') <> nil then
      begin
        if DepLock.Objects['requires'].Find(Dep.Name) <> nil then
        begin
          VersionStr := DepLock.Objects['requires'].Objects[Dep.Name].Get('version','');
          CommitStr := DepLock.Objects['requires'].Objects[Dep.Name].Get('commit','');
        end;
      end;
    end;

    if VersionStr <> '' then
      VersionStr := render('<span class="text-green-400">' + VersionStr + '</span>')
    else
      VersionStr := render('<span class="text-red-500">(not installed)</span>');

    if CommitStr <> '' then
      CommitStr := render('<span class="text-blue-400">(' + Copy(CommitStr,1,7) + ')</span>')
    else
      CommitStr := '';

    // Print current dependency
    if IsDev then
    Writeln(render(
      Prefix + TreeChar +'<span class="bg-fuchsia-600 text-slate-300">[dev]</span> ') +
      Dep.Name + ' ' + VersionStr + ' ' + CommitStr)
      else
      Writeln(render(
        Prefix + TreeChar) +
        Dep.Name + ' ' + VersionStr + ' ' + CommitStr);

    // Recurse into normal requires
    if Assigned(DepLock) and (DepLock.Find('requires') <> nil) then
    begin
      RequiresObj := DepLock.Objects['requires'];
      ChildrenCount := RequiresObj.Count;
      for i := 0 to ChildrenCount - 1 do
      begin
        Child.Name := RequiresObj.Names[i];
        Child.Constraint := RequiresObj.Objects[Child.Name].Get('constraint','');
        PrintDependencyTree(Child, NewPrefix, i = ChildrenCount - 1, Visited, False);
      end;
    end;

    // Recurse into dev requires
    if Assigned(DepLock) and (DepLock.Find('require-dev') <> nil) then
    begin
      RequiresObj := DepLock.Objects['require-dev'];
      ChildrenCount := RequiresObj.Count;
      for i := 0 to ChildrenCount - 1 do
      begin
        Child.Name := RequiresObj.Names[i];
        Child.Constraint := RequiresObj.Objects[Child.Name].Get('constraint','');
        PrintDependencyTree(Child, NewPrefix, i = ChildrenCount - 1, Visited, True);
      end;
    end;

  finally
    DepLock.Free;
    if (Visited.Count = 1) then
      Visited.Free;
  end;
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

