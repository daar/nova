unit Nova.Git;

{$mode objfpc}{$H+}

interface

uses
  Classes,
  GitCLI,
  Nova.Utils,
  SysUtils;

type
  { TNovaGitResolver }

  TNovaGitResolver = class(TGitCLI)
  public
    function ResolveVersion(const Repo, Constraint: string): TVersion;
  end;

implementation

function TNovaGitResolver.ResolveVersion(const Repo, Constraint: string): TVersion;
var
  GitResult: TGitResult;
  Lines: TStringList;
  i: integer;
  Candidate, Best: string;
  CandidateVer, BestVer: TVersion;
  TagStart: integer;
begin
  // Fetch all tags from the remote GitHub repository
  GitResult := RunGitCommand(['ls-remote', '--tags',
    'https://github.com/' + Repo + '.git']);

  if not GitResult.Success then
    raise Exception.CreateFmt('Failed to fetch tags for repository "%s": %s',
      [Repo, GitResult.StdErr]);

  Lines := TStringList.Create;
  Best := '';
  try
    Lines.Text := GitResult.StdOut;

    for i := 0 to Lines.Count - 1 do
    begin
      TagStart := Pos('refs/tags/', Lines[i]);
      if TagStart > 0 then
      begin
        Candidate := Copy(Lines[i], TagStart + 10, MaxInt);
        CandidateVer := parse_version(Candidate);

        // Extract commit hash
        if Pos(#9, Lines[i]) > 0 then
          CandidateVer.hash := Trim(Copy(Lines[i], 1, Pos(#9, Lines[i]) - 1))
        else
          CandidateVer.hash := '';

        if matches_constraint(CandidateVer, Constraint) then
          if (Best = '') or (compare_versions(CandidateVer, BestVer) > 0) then
          begin
            Best := Candidate;
            BestVer := CandidateVer;
          end;
      end;
    end;

    if Best <> '' then
      Result := BestVer
    else
      // If no tag matches, fall back to parsing the constraint itself
      Result := parse_version(Constraint);

  finally
    Lines.Free;
  end;
end;

end.
