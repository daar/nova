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
  Nova.Package.Spec,
  TermStyle;

  { TInitCommand }

procedure TInitCommand.Execute;
var
  Spec: TNovaPkgSpec;
begin
  // Banner
  writeln;
  writeln(render(
    '<span class="ml-1 p-1 bg-sky-700 text-sky-200">Welcome to the nova config generator</span>'));

  writeln;
  writeln(render('<span class="ml-2">This command will guide you through creating your <b>'
    + DEP_FILE + '</b> config</span>'));
  Writeln;

  Spec := TNovaPkgSpec.Create;
  try
    Spec.Name := Prompt('Package name (vendor/name)', Spec.Name, 'ml-2');
    Spec.Description := Prompt('Description', Spec.Description, 'ml-2');

    Spec.AuthorName := Prompt('Author', Spec.AuthorName, 'ml-2', 'n');
    if Spec.AuthorName <> '' then
      Spec.AuthorEmail := Prompt('Email', Spec.AuthorEmail, 'ml-2', 'n');

    Spec.PackageType := Prompt('Package Type (e.g. library, project, metapackage)',
      Spec.PackageType, 'ml-2');

    Spec.License := Prompt('License', Spec.License, 'ml-2');

    if Spec.PackageType = 'project' then
      Spec.ProgramFile := Prompt('Project file', Spec.ProgramFile, 'ml-2');

    Spec.SaveToFile;

    writeln;
    success('Generated <b>' + DEP_FILE + '</b> with config information.', 'bg-green-700 text-green-100 font-bold ml-1');
  finally
    Spec.Free;
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
