unit Nova.Command.Show;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Nova.Command, Nova.Package, TermStyle;

type
  { TShowCommand }

  TShowCommand = class(TBaseCommand)
  private
    FShowTree: Boolean;
    FPackage: TNovaPackage; // root package that contains Required and Resolved

    procedure LoadRootPackage;
    procedure PrintDependencies;
    procedure PrintDependency(var res: TResolved; var req: TRequired);
    procedure PrintDependencyTree(const Res: TResolved; const Prefix: string = ''; const IsLast: Boolean = True;
      Visited: TStringList = nil; const IsDev: Boolean = False);
    function FormatConstraint(const Constraint: string): string;
    function FormatVersion(const Res: TResolved): string;
    function GitStatusString(const Repo: string): string;
  public
    constructor Create; override;
    destructor Destroy; override;
    procedure Execute; override;
    function Name: string; override;
    function Description: string; override;
  end;

implementation

uses
  GitCLI;

{ TShowCommand }

constructor TShowCommand.Create;
begin
  inherited Create;
  AddOption('--tree', 'Show dependency tree instead of flat list');
  FShowTree := False;
  FPackage := TNovaPackage.Create;
end;

destructor TShowCommand.Destroy;
begin
  FPackage.Free;
  inherited Destroy;
end;

procedure TShowCommand.LoadRootPackage;
begin
  if not FileExists(DEP_FILE) then
    raise Exception.Create('No ' + DEP_FILE + ' found. Run "nova init" first.');
  FPackage.LoadFromFile(DEP_FILE);
end;

function TShowCommand.FormatConstraint(const Constraint: string): string;
begin
  if Constraint <> '' then
    Result := render('<span class="text-yellow-300">' + Constraint + '</span>')
  else
    Result := render('<span class="text-gray-400">-</span>');
end;

function TShowCommand.FormatVersion(const Res: TResolved): string;
var
  sVer, sCommit: string;
begin
  // Res.Name empty means not installed / not resolved
  if Res.Name = '' then
  begin
    Result := render('<span class="text-red-500">(not installed)</span>');
    Exit;
  end;

  sVer := Res.Version;
  sCommit := Res.Commit;

  if sVer <> '' then
    sVer := render('<span class="text-green-400">' + sVer + '</span>')
  else
    sVer := render('<span class="text-red-500">(unknown)</span>');

  if sCommit <> '' then
    sCommit := ' ' + render('<span class="text-blue-400">(' + Copy(sCommit, 1, 7) + ')</span>')
  else
    sCommit := '';

  Result := sVer + sCommit + GitStatusString(Res.Name);
end;

function TShowCommand.GitStatusString(const Repo: string): string;
var
  Lines: TStringList;
  i: Integer;
  HasM: boolean = false;
  HasD: boolean = false;
  HasQ: boolean = false;
  Git: TGitCLI;
  R: TGitResult;
  GitStatus: string;
begin
  Git := TGitCLI.Create('./vendor/' + Repo);

  try
    R := Git.Status;

    if not R.Success then
    begin
      Result := render('<span class="text-fuchsia-400 ml-1">E</span>');
      Exit;
    end;

    Lines := TStringList.Create;
    try
      Lines.Text := R.StdOut;
      for i := 0 to Lines.Count - 1 do
      begin
        if Pos('??', Lines[i]) = 1 then
          HasQ := True
        else if Pos('D', Trim(Lines[i])) = 1 then
          HasD := True
        else if Pos('M', Trim(Lines[i])) = 1 then
          HasM := True;
      end;
    finally
      Lines.Free;
    end;
  finally
    Git.Free;
  end;

  // Build the GitStatus string in order M, D, ?
  if HasM then GitStatus += '<span class="text-yellow-200">M</span>';
  if HasD then GitStatus += '<span class="text-red">D</span>';
  if HasQ then GitStatus += '<span class="text-green">?</span>';

  Result := render('<span class="ml-1">' + GitStatus + '</span>');
end;

procedure TShowCommand.PrintDependencyTree(const Res: TResolved; const Prefix: string; const IsLast: Boolean;
  Visited: TStringList; const IsDev: Boolean);
var
  TreeChar, NewPrefix: string;
  i: Integer;
  childName: string;
  childRes: TResolved;
  createdVisited: Boolean;
  nameCol, constrCol, versionCol: string;
begin
  if Res.Name = '' then Exit;

  // Check for possible circular dependency
  if Visited.IndexOf(Res.Name) >= 0 then
  begin
    write(Prefix);
    //PrintDependency(Res, FPackage
    Writeln(render(Prefix + '└─ ' + Res.Name + ' ' + FormatVersion(Res) +
      ' <span class="text-yellow-300">[circular]</span>'));
    Exit;
  end;

  Visited.Add(Res.Name);

  // Recurse for all dependecies
  for i := 0 to High(Res.Required) do
  begin
    childName := Res.Required[i];
    childRes := FPackage.FindResolved(childName);
    PrintDependencyTree(childRes, Prefix + Prefix, i = High(Res.Required), Visited, childRes.Dev);
  end;


  //try
  //  if Visited.IndexOf(Res.Name) >= 0 then
  //  begin
  //    Writeln(render(Prefix + '└─ ' + Res.Name + ' ' + FormatVersion(Res) +
  //      ' <span class="text-yellow-300">[circular]</span>'));
  //    Exit;
  //  end;
  //
  //  Visited.Add(Res.Name);
  //
  //  if IsLast then
  //  begin
  //    TreeChar := '└─ ';
  //    NewPrefix := Prefix + '   ';
  //  end
  //  else
  //  begin
  //    TreeChar := '├─ ';
  //    NewPrefix := Prefix + '│  ';
  //  end;
  //
  //  // build aligned columns
  //  if IsDev then
  //    nameCol := Prefix + TreeChar +
  //      render('<span class="bg-fuchsia-600 text-slate-300">[dev]</span> ') +
  //      render('<span class="text-white">' + Res.Name + '</span>')
  //  else
  //    nameCol := Prefix + TreeChar + render('<span class="text-white">' + Res.Name + '</span>');
  //
  //  constrCol := FormatConstraint(''); // tree nodes don’t have constraints
  //  versionCol := FormatVersion(Res);
  //
  //  Write(nameCol:40);
  //  Write(constrCol:12);
  //  Writeln(' → ', versionCol);
  //
  //  // recurse
  //  for i := 0 to High(Res.Required) do
  //  begin
  //    childName := Res.Required[i];
  //    childRes := FPackage.FindResolved(childName);
  //    PrintDependencyTree(childRes, NewPrefix, i = High(Res.Required), Visited, childRes.Dev);
  //  end;
  //
  //  Visited.Delete(Visited.Count - 1);
  //finally
  //  if createdVisited then
  //    Visited.Free;
  //end;
end;

procedure TShowCommand.PrintDependencies;
var
  i: integer;
  req: TRequired;
  res: TResolved;
  Visited: TStringList;
begin
  if FPackage.RequiredCount = 0 then
  begin
    Writeln(render('<span class="text-red-500">No packages installed</span>'));
    Exit;
  end;

  Writeln(render('<span class="text-blue-400 font-bold">Installed packages:</span>'));
  Writeln;

  for i := 0 to FPackage.RequiredCount - 1 do
  begin
    req := FPackage.RequiredAt(i);
    res := FPackage.FindResolved(req.Name);

    PrintDependency(res, req);

    // show dependency tree for resolved packages
    Visited := TStringList.Create;
    try
      if (res.Name <> '') and FShowTree then
        PrintDependencyTree(res, '   ', True, Visited, req.Dev);
    finally
      Visited.Free;
    end;
  end;
end;

procedure TShowCommand.PrintDependency(var res: TResolved; var req: TRequired);
var
  marker: string;
begin
  if req.Dev then
    marker := render('<span class="text-red mx-1">[dev]</span> ')
  else
    marker := render('<span class="ml-5 mr-1">*</span> ');

  Write(marker, render('<span class="text-white">' + req.Name + '</span>'): 40);

  Write(FormatConstraint(req.Constraint): 30);
  Writeln(' → ', FormatVersion(res): 65);
end;

procedure TShowCommand.Execute;
begin
  FShowTree := HasOption('--tree');
  LoadRootPackage;
  PrintDependencies;
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

