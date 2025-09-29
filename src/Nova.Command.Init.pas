unit Nova.Command.Init;

{$mode ObjFPC}{$H+}

interface

uses
  Nova.Command;

type

  { TInitCommand }

  TInitCommand = class(TBaseCommand)
  public
    procedure Execute; override;
    function Name: string; override;
    function Description: string; override;
  end;

implementation

uses
  Nova.Package,
  TermStyle;

  { TInitCommand }

procedure TInitCommand.Execute;
var
  Pkg: TNovaPackage;
  AuthorName, AuthorEmail: String;
begin
  // Banner
  writeln;
  writeln(render(
    '<span class="ml-1 p-1 bg-sky-700 text-sky-200">Welcome to the nova config generator</span>'));

  writeln;
  writeln(render('<span class="ml-2">This command will guide you through creating your <b>'
    + DEP_FILE + '</b> config</span>'));
  Writeln;

  Pkg := TNovaPackage.Create;
  try
    Pkg.Name := Prompt('Package name (vendor/name)', Pkg.DefaultPackageName, 'ml-2');
    Pkg.Description := Prompt('Description', Pkg.Description, 'ml-2');

    AuthorName := Prompt('Author', Pkg.DefaultAuthorName, 'ml-2', 'n');
    if AuthorName <> '' then
    begin
      AuthorEmail := Prompt('Email', Pkg.DefaultAuthorEmail, 'ml-2', 'n');
      Pkg.AddAuthor(AuthorName, AuthorEmail);
    end;

    Pkg.PackageType := Prompt('Package Type (e.g. library, project, metapackage)',
      Pkg.PackageType, 'ml-2');

    Pkg.License := Prompt('License', Pkg.License, 'ml-2');

    if Pkg.PackageType = 'project' then
      Pkg.AddSource(Prompt('Project file', Pkg.DefaultSourceFile, 'ml-2'));

    Pkg.SaveToFile;

    writeln;
    success('Generated <b>' + DEP_FILE + '</b> with config information.', 'bg-green-700 text-green-100 font-bold ml-1');
  finally
    Pkg.Free;
  end;

  // Next steps
  writeln(render(
    '<div class="ml-4">Add a new requirements to your project with: <i>nova require [vendor/package]</i></div>'));
  writeln(render(
    '<div class="ml-4">Visit the <a href="https://github.com/nova-packager/nova">nova project page</a> for more information.</div>'));
  writeln;
end;

function TInitCommand.name: string;
begin
  Result := 'init';
end;

function TInitCommand.Description: string;
begin
  Result := 'Initialize a new project interactively';
end;

end.
