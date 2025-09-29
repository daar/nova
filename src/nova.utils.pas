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

procedure SplitPackageSpec(const FullParam: string; out PackageName, VersionConstraint: string);
function parse_version(const S: string): TVersion;
function compare_versions(const A, B: TVersion): integer;
function matches_constraint(const Ver: TVersion; const Constraint: string): Boolean;

implementation

procedure SplitPackageSpec(const FullParam: string; out PackageName, VersionConstraint: string);
var
  SepPos: Integer;
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

function matches_constraint(const Ver: TVersion; const Constraint: string): Boolean;
var
  Num: string;
  CVer: TVersion;

  function StripPrefix(const S: string; const Prefix: string): string;
  begin
    Result := Copy(S, Length(Prefix) + 1, MaxInt);
  end;

begin
  Result := False;

  // no constraint, always matches
  if Constraint = '' then
    Exit(True);

  if Copy(Constraint, 1, 1) = '^' then
  begin
    Num := StripPrefix(Constraint, '^');
    CVer := parse_version(Num);

    if CVer.Major = 0 then
    begin
      // pre-1.0.0: only patch-level compatible within same minor version
      Result := (Ver.Major = 0) and (Ver.Minor = CVer.Minor) and
        (compare_versions(Ver, CVer) >= 0);
    end
    else
    begin
      // normal: same major, >= specified
      Result := (Ver.Major = CVer.Major) and (compare_versions(Ver, CVer) >= 0);
    end;
  end
  else if Copy(Constraint, 1, 1) = '~' then
  begin
    Num := StripPrefix(Constraint, '~');
    CVer := parse_version(Num);
    // compatible with same major.minor version, >= specified version
    Result := (Ver.Major = CVer.Major) and (Ver.Minor = CVer.Minor) and
      (compare_versions(Ver, CVer) >= 0);
  end
  else if Copy(Constraint, 1, 2) = '>=' then
  begin
    Num := StripPrefix(Constraint, '>=');
    CVer := parse_version(Num);
    Result := compare_versions(Ver, CVer) >= 0;
  end
  else if Copy(Constraint, 1, 1) = '=' then
  begin
    Num := StripPrefix(Constraint, '=');
    CVer := parse_version(Num);
    Result := compare_versions(Ver, CVer) = 0;
  end
  else
  begin
    // bare version string interpreted as exact match
    CVer := parse_version(Constraint);
    Result := compare_versions(Ver, CVer) = 0;
  end;
end;

end.

