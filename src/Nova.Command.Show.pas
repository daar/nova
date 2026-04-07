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
    procedure PrintDependencyTree(const AName: string; const IsLast: Boolean;
      Visited: TStringList; const Level: byte = 1);
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
    //Result := render('<span class="text-red-500">(not installed)</span>');
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
  Git: TGitCLI;
  R: TGitResult;
begin
  Git := TGitCLI.Create('./vendor/' + Repo);

  Result := '';

  try
    R := Git.Status;

    if not R.Success then
    begin
      Result := render('<span class="text-yellow-200 ml-1">[error]</span>');
      Exit;
    end;

    Lines := TStringList.Create;
    try
      Lines.Text := R.StdOut;
      if Lines.Count >= 2 then
        Result := render('<span class="text-yellow-200 ml-1">[modified]</span>');
    finally
      Lines.Free;
    end;
  finally
    Git.Free;
  end;
end;

procedure TShowCommand.PrintDependencyTree(const AName: string;
  const IsLast: Boolean; Visited: TStringList; const Level: byte);
var
  i: Integer;
  childName, Prefix: string;
  childRes, Res: TResolved;
begin
  Res := FPackage.FindResolved(AName);
  Prefix := StringOfChar(' ', Level * 3);

  if Res.Name = '' then
  begin
    Writeln(render(Prefix + '        └─' + AName + ' <span class="text-red-500">(not installed)</span>'));
    Exit;
  end;

  // Check for possible circular dependency
  if Visited.IndexOf(Res.Name) >= 0 then
  begin
    Writeln(render(Prefix + '        └─' + Res.Name + ' ' + FormatVersion(Res) +
      ' <span class="text-yellow-300">[circular]</span>'));
    Exit;
  end;

  Visited.Add(Res.Name);

  // Recurse for all dependecies
  for i := 0 to High(Res.Required) do
  begin
    childName := Res.Required[i].Name;
    PrintDependencyTree(childName, i = High(Res.Required), Visited, Level + 1);
  end;

  Writeln(render(Prefix + '       └─' + Res.Name + ' ' + FormatVersion(Res)));
end;

procedure TShowCommand.PrintDependencies;
var
  i: integer;
  req: TRequired;
  res: TResolved;
  Visited: TStringList;
  preq: TRequiredArray;
  pkgname: TRequired;
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
    if  FShowTree then
    begin
      Visited := TStringList.Create;
      try
        preq := FPackage.FindPackageRequirements(req.Name);
          for pkgname in preq do
            PrintDependencyTree(pkgname.Name,True, Visited);
      finally
        Visited.Free;
      end;
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

