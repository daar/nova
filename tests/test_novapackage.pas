program test_novapackage;

{$mode objfpc}{$H+}

uses
  SysUtils, Classes, fpjson, jsonparser,
  Nova.Package,
  tap;

procedure test_add_and_retrieve;
var
  P: TNovaPackage;
  Req: TRequired;
  Res: TResolved;
begin
  P := TNovaPackage.Create;
  try
    P.Name := 'mypackage';
    P.Description := 'test description';
    P.PackageType := 'library';
    P.License := 'MIT';

    P.AddAuthor('Alice', 'alice@example.com');
    P.AddSource('src/main.pas');
    P.AddRequired('dep1', '^1.0', False);
    P.AddResolved('dep2', '1.2.3', 'abc123', False, ['src/dep2.pas'], []);

    ok(P.Name = 'mypackage', 'Name stored');
    ok(P.Description = 'test description', 'Description stored');
    ok(P.PackageType = 'library', 'PackageType stored');
    ok(P.License = 'MIT', 'License stored');

    ok(P.RequiredCount = 1, 'RequiredCount works');
    Req := P.RequiredAt(0);
    ok(Req.Name = 'dep1', 'Required name matches');
    ok(Req.Constraint = '^1.0', 'Required constraint matches');
    ok(Req.Dev = False, 'Required dev flag matches');

    ok(P.ResolvedCount = 1, 'ResolvedCount works');
    Res := P.ResolvedAt(0);
    ok(Res.Name = 'dep2', 'Resolved name matches');
    ok(Res.Version = '1.2.3', 'Resolved version matches');
    ok(Res.Commit = 'abc123', 'Resolved commit matches');
    ok(Length(Res.Source) = 1, 'Resolved source stored');
  finally
    P.Free;
  end;
end;

procedure test_json_roundtrip;
var
  P1, P2: TNovaPackage;
  JSONObj: TJSONObject;
  S: string;
begin
  P1 := TNovaPackage.Create;
  try
    P1.Name := 'roundtrip';
    P1.AddAuthor('Bob', 'bob@example.com');
    P1.AddRequired('depX', '>=2.0', True);

    JSONObj := TJSONObject.Create;
    try
      P1.SaveToJSON(JSONObj);
      S := JSONObj.FormatJSON;
    finally
      JSONObj.Free;
    end;
  finally
    P1.Free;
  end;

  // Now reload into a fresh object
  P2 := TNovaPackage.Create;
  try
    JSONObj := TJSONObject(GetJSON(S));
    try
      P2.LoadFromJSON(JSONObj);
    finally
      JSONObj.Free;
    end;

    ok(P2.Name = 'roundtrip', 'Name survived JSON roundtrip');
    ok(P2.RequiredCount = 1, 'Required survived JSON roundtrip');
    ok(P2.RequiredAt(0).Name = 'depX', 'Required name roundtrip ok');
    ok(P2.RequiredAt(0).Constraint = '>=2.0', 'Required constraint roundtrip ok');
    ok(P2.RequiredAt(0).Dev = True, 'Required dev flag roundtrip ok');
  finally
    P2.Free;
  end;
end;

procedure test_file_roundtrip;
var
  P1, P2: TNovaPackage;
  FN: string;
begin
  FN := 'test_nova.json';
  if FileExists(FN) then DeleteFile(FN);

  P1 := TNovaPackage.Create;
  try
    P1.Name := 'filetest';
    P1.AddAuthor('Carol', 'carol@example.com');
    P1.AddRequired('depZ', '~3.4', False);
    P1.SaveToFile(FN);
  finally
    P1.Free;
  end;

  ok(FileExists(FN), 'File written');

  P2 := TNovaPackage.Create;
  try
    P2.LoadFromFile(FN);
    ok(P2.Name = 'filetest', 'Name loaded from file');
    ok(P2.RequiredCount = 1, 'Required loaded from file');
    ok(P2.RequiredAt(0).Constraint = '~3.4', 'Constraint loaded from file');
  finally
    P2.Free;
  end;

  DeleteFile(FN);
end;

procedure test_helpers;
var
  P: TNovaPackage;
  Res: TResolved;
begin
  P := TNovaPackage.Create;
  try
    P.AddRequired('depA', '*', False);
    ok(P.PackageAlreadyRegistered('depA'), 'PackageAlreadyRegistered works');
    ok(not P.PackageAlreadyRegistered('depB'), 'PackageAlreadyRegistered false');

    P.AddResolved('depR', '1.0.0', 'deadbeef', False, [], []);
    Res := P.FindResolved('depR');
    ok(Res.Name = 'depR', 'FindResolved works');
    ok(P.FindResolved('missing').Name = '', 'FindResolved missing returns empty');

    ok(Length(P.FindPackageRequirements('depR')) = 0, 'FindPackageRequirements empty works');
  finally
    P.Free;
  end;
end;

procedure test_first_meaningful_line;
var
  FName: string;
  P: TNovaPackage;
  S: TStringList;
begin
  FName := 'testfile.pas';
  S := TStringList.Create;
  try
    S.Text := '{ comment only }'#10'program Demo;'#10'begin end.';
    S.SaveToFile(FName);
  finally
    S.Free;
  end;

  P := TNovaPackage.Create;
  try
    ok(P.FirstMeaningfulLine(FName) = 'program Demo;', 'FirstMeaningfulLine skips comments');
    ok(P.IsProgramFile(FName), 'IsProgramFile detects "program"');
  finally
    P.Free;
  end;

  DeleteFile(FName);
end;

begin
  plan(20);

  test_add_and_retrieve;
  test_json_roundtrip;
  test_file_roundtrip;
  test_helpers;
  test_first_meaningful_line;
end.
