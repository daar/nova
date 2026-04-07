unit Nova.Utils;

{$mode ObjFPC}{$H+}

interface

uses
  Classes,
  StrUtils,
  SysUtils;

type

  TVersion = record
    major, minor, patch: integer;
    name: string;
    constraint: string;
    hash: string;
  end;

procedure SplitPackageSpec(const FullParam: string;
  out PackageName, VersionConstraint: string);
function parse_version(const S: string): TVersion;
function compare_versions(const A, B: TVersion): integer;
function matches_constraint(const Ver: TVersion; const Constraint: string): boolean;

implementation

procedure SplitPackageSpec(const FullParam: string;
  out PackageName, VersionConstraint: string);
var
  SepPos: integer;
begin
  SepPos := Pos(':', FullParam);

  if SepPos > 0 then
  begin
    PackageName := Copy(FullParam, 1, SepPos - 1);
    VersionConstraint := Copy(FullParam, SepPos + 1, Length(FullParam) - SepPos);
  end
  else
  begin
    PackageName := FullParam;
    VersionConstraint := '';
  end;
end;

function parse_version(const S: string): TVersion;
var
  Parts: TStringList;
  Clean: string;
begin
  Result.Major := 0;
  Result.Minor := 0;
  Result.Patch := 0;

  Result.name := S;

  Clean := S;
  if (Length(Clean) > 0) and (Clean[1] = 'v') then
    Delete(Clean, 1, 1);

  Parts := TStringList.Create;
  try
    Parts.Delimiter := '.';
    Parts.StrictDelimiter := True;
    Parts.DelimitedText := Clean;

    if Parts.Count > 0 then
      Result.Major := StrToIntDef(Parts[0], 0);
    if Parts.Count > 1 then
      Result.Minor := StrToIntDef(Parts[1], 0);
    if Parts.Count > 2 then
      Result.Patch := StrToIntDef(Parts[2], 0);
  finally
    Parts.Free;
  end;
end;

function compare_versions(const A, B: TVersion): integer;
begin
  if A.Major <> B.Major then exit(A.Major - B.Major);
  if A.Minor <> B.Minor then exit(A.Minor - B.Minor);
  Result := A.Patch - B.Patch;
end;

function matches_constraint(const Ver: TVersion; const Constraint: string): boolean;
var
  Num, Clean: string;
  CVer: TVersion;
begin
  Clean := Trim(Constraint);
  if Clean = '' then
    exit(True);

  Result := False;

  if Pos('^', Clean) = 1 then
  begin
    Num := Trim(Copy(Clean, 2, MaxInt));
    if Num = '' then exit(False);
    CVer := parse_version(Num);

    if CVer.Major > 0 then
      Result := (Ver.Major = CVer.Major) and (compare_versions(Ver, CVer) >= 0)
    else if CVer.Minor > 0 then
      Result := (Ver.Major = 0) and (Ver.Minor = CVer.Minor) and
        (compare_versions(Ver, CVer) >= 0)
    else
      Result := (Ver.Major = 0) and (Ver.Minor = 0) and (Ver.Patch = CVer.Patch) and
        (compare_versions(Ver, CVer) >= 0);
  end
  else if Pos('~', Clean) = 1 then
  begin
    Num := Trim(Copy(Clean, 2, MaxInt));
    if Num = '' then exit(False);
    CVer := parse_version(Num);
    Result := (Ver.Major = CVer.Major) and (Ver.Minor = CVer.Minor) and
      (compare_versions(Ver, CVer) >= 0);
  end
  else if Pos('>=', Clean) = 1 then
  begin
    Num := Trim(Copy(Clean, 3, MaxInt));
    if Num = '' then exit(False);
    CVer := parse_version(Num);
    Result := compare_versions(Ver, CVer) >= 0;
  end
  else if Pos('=', Clean) = 1 then
  begin
    Num := Trim(Copy(Clean, 2, MaxInt));
    if Num = '' then exit(False);
    CVer := parse_version(Num);
    Result := compare_versions(Ver, CVer) = 0;
  end
  else
  begin
    CVer := parse_version(Clean);
    Result := compare_versions(Ver, CVer) = 0;
  end;
end;

end.
