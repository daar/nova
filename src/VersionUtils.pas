unit VersionUtils;

interface

type
  TVersion = class
    Major, Minor, Patch: Integer;
    Name, Constraint, Hash: string;
    constructor Create(const AVersion: string);
    function CompareTo(Other: TVersion): Integer;
    function MatchesConstraint(const ConstraintStr: string): Boolean;
  end;

implementation

constructor TVersion.Create(const AVersion: string);
begin
  // parse version string
end;

function TVersion.CompareTo(Other: TVersion): Integer;
begin
  // implement comparison
end;

function TVersion.MatchesConstraint(const ConstraintStr: string): Boolean;
begin
  // implement constraint matching (^, ~, >=, =)
end;

end.
