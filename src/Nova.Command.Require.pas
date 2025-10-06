unit Nova.Command.Require;

{$mode ObjFPC}{$H+}

interface

uses
  Nova.Command;

type
  { TRequireCommand }

  TRequireCommand = class(TBaseCommand)
  public
    constructor Create; override;
    procedure Execute; override;
    function Name: string; override;
    function Description: string; override;
  end;

implementation

uses
  FPCConfigWriter,
  Nova.Package,
  Nova.Utils,
  SysUtils,
  TermStyle;

  { TRequireCommand }

constructor TRequireCommand.Create;
begin
  inherited Create;
  // Option to include dev dependencies
  AddOption('--dev', 'Include packages as development requirement');
end;

procedure TRequireCommand.Execute;
var
  PkgName, packageName, versionConstraint: string;
  DevFlag: boolean;
  NovaPkg: TNovaPackage;
  i:      integer;
  fpcCfg: TFPCConfigWriter;
  pkg: TResolved;
begin
  if ParamCount < 2 then
  begin
    error('No package specified.');
    Exit;
  end;

  PkgName := ParamStr(2);
  DevFlag := HasOption('--dev');

  writeln('-- Adding requirement: ', PkgName);
  if DevFlag then
    writeln('-- Marking as development dependency.');

  // Load current nova.json or package structure
  NovaPkg := TNovaPackage.Create;
  try
    NovaPkg.LoadFromFile;

    for i := 2 to argc do
    begin
      // Ignore the --dev argument
      if argv[i] = '--dev' then Continue;

      if argv[i] <> '' then
      begin
        SplitPackageSpec(argv[i], packageName, versionConstraint);
        pkg := NovaPkg.FindResolved(packageName);
        if pkg.Name = '' then
        begin
        //  if internal_require(pkgs, packageName, versionConstraint, dep, includeDev) then
        //    NovaPkg.AddRequired(packageName, dep^.constraint, includeDev);
        end
        else
          if not matches_constraint(parse_version(pkg.Version), versionConstraint) then
          begin
            error('Cannot install package "' + packageName + '" due to a version conflict.');
            writeln('The package is already installed with version ' + pkg.Version + ', which does not satisfy the required constraint ' + versionConstraint);
            writeln('Hint: Update or remove the conflicting dependency before proceeding.');
            exit;
          end
          else
          begin
            info('Skipping package "' + packageName + '" — it is already installed (version ' + pkg.Version + ') and satisfies constraint ' + versionConstraint + '.');
            writeln('Hint: Use "nova remove" followed by "nova install" to refresh it, or manually adjust nova.json to change the constraint.');
          end;
      end;
    end;

    // Save changes back to nova.json
    NovaPkg.SaveToFile;
    fpcCfg.WriteConfig(NovaPkg);

    success('Requirement added successfully.');
  finally
    NovaPkg.Free;
  end;
end;

function TRequireCommand.Name: string;
begin
  Result := 'require';
end;

function TRequireCommand.Description: string;
begin
  Result := 'Add one or more packages as requirement';
end;

end.
