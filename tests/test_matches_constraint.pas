unit test_matches_constraint;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, TapLib, Nova.Utils;

procedure register_matches_constraint_tests;

implementation

procedure test_caret;
begin
  // Normal >=1.0.0
  assert_true('^0.3 matches 0.3.5', matches_constraint(parse_version('0.3.5'), '^0.3'));
  assert_true('^1.2 matches 1.2.0', matches_constraint(parse_version('1.2.0'), '^1.2'));
  assert_true('^1.2 matches 1.3.0', matches_constraint(parse_version('1.3.0'), '^1.2'));
  assert_false('^1.2 fails 2.0.0', matches_constraint(parse_version('2.0.0'), '^1.2'));

  // Pre-1.0.0: patch updates only
  assert_true('^0.3.0 matches 0.3.1', matches_constraint(parse_version('0.3.1'), '^0.3.0'));
  assert_false('^0.3.0 fails 0.4.0', matches_constraint(parse_version('0.4.0'), '^0.3.0'));
  assert_false('^0.3.0 fails 1.0.0', matches_constraint(parse_version('1.0.0'), '^0.3.0'));

  // 0.0.x edge
  assert_true('^0.0.5 matches 0.0.5', matches_constraint(parse_version('0.0.5'), '^0.0.5'));
  assert_false('^0.0.5 fails 0.0.6', matches_constraint(parse_version('0.0.6'), '^0.0.5'));
end;

procedure test_tilde;
begin
  assert_true('~1.2 matches 1.2.5', matches_constraint(parse_version('1.2.5'), '~1.2'));
  assert_false('~1.2 fails 1.3.0', matches_constraint(parse_version('1.3.0'), '~1.2'));

  // <1.0.0 behaves the same
  assert_true('~0.3 matches 0.3.2', matches_constraint(parse_version('0.3.2'), '~0.3'));
  assert_false('~0.3 fails 0.4.0', matches_constraint(parse_version('0.4.0'), '~0.3'));
end;

procedure test_gte;
begin
  assert_true('>=1.0 matches 1.2.0', matches_constraint(parse_version('1.2.0'), '>=1.0'));
  assert_true('>=1.0 matches 1.0.0', matches_constraint(parse_version('1.0.0'), '>=1.0'));
  assert_false('>=1.0 fails 0.9.9', matches_constraint(parse_version('0.9.9'), '>=1.0'));

  assert_true('>=0.3 matches 0.3.1', matches_constraint(parse_version('0.3.1'), '>=0.3'));
  assert_false('>=0.3 fails 0.2.9', matches_constraint(parse_version('0.2.9'), '>=0.3'));
end;

procedure test_equal;
begin
  assert_true('=1.2.3 matches 1.2.3', matches_constraint(parse_version('1.2.3'), '=1.2.3'));
  assert_false('=1.2.3 fails 1.2.4', matches_constraint(parse_version('1.2.4'), '=1.2.3'));
  assert_true('=0.3.0 matches 0.3.0', matches_constraint(parse_version('0.3.0'), '=0.3.0'));
end;

procedure test_bare_version;
begin
  assert_true('1.2.3 matches 1.2.3', matches_constraint(parse_version('1.2.3'), '1.2.3'));
  assert_false('1.2.3 fails 1.2.4', matches_constraint(parse_version('1.2.4'), '1.2.3'));
  assert_true('0.3.0 matches 0.3.0', matches_constraint(parse_version('0.3.0'), '0.3.0'));
end;

procedure test_empty;
begin
  assert_true('empty constraint matches anything', matches_constraint(parse_version('2.0.0'), ''));
  assert_true('empty constraint matches 0.3.0', matches_constraint(parse_version('0.3.0'), ''));
end;

procedure test_less_than_one;
begin
  // Versions <1.0.0, caret only allows patch updates
  assert_true('^0.3.0 matches 0.3.1', matches_constraint(parse_version('0.3.1'), '^0.3.0'));
  assert_false('^0.3.0 fails 0.4.0', matches_constraint(parse_version('0.4.0'), '^0.3.0'));
  assert_false('^0.3.0 fails 1.0.0', matches_constraint(parse_version('1.0.0'), '^0.3.0'));

  // Tilde behaves normally even for <1.0.0
  assert_true('~0.3 matches 0.3.5', matches_constraint(parse_version('0.3.5'), '~0.3'));
  assert_false('~0.3 fails 0.4.0', matches_constraint(parse_version('0.4.0'), '~0.3'));
end;

procedure test_malformed_constraints;
var
  Ver: TVersion;
begin
  Ver := parse_version('1.2.3');

  // Completely empty or whitespace
  assert_true('empty string', matches_constraint(Ver, ''));
  assert_true('spaces only', matches_constraint(Ver, '   '));

  // Missing version after operator
  assert_false('^ without version', matches_constraint(Ver, '^'));
  assert_false('~ without version', matches_constraint(Ver, '~'));
  assert_false('>= without version', matches_constraint(Ver, '>='));
  assert_false('= without version', matches_constraint(Ver, '='));

  // Random invalid strings
  assert_false('invalid string', matches_constraint(Ver, 'foobar'));
  assert_false('numeric garbage', matches_constraint(Ver, '1..2'));
  assert_false('symbols only', matches_constraint(Ver, '!@#$'));
end;

procedure test_multi_digit_versions;
begin
  // Caret
  assert_true('^1.9 matches 1.10.0', matches_constraint(parse_version('1.10.0'), '^1.9'));
  assert_false('^1.10 fails 2.0.0', matches_constraint(parse_version('2.0.0'), '^1.10'));

  // Tilde
  assert_true('~1.10 matches 1.10.5', matches_constraint(parse_version('1.10.5'), '~1.10'));
  assert_false('~1.10 fails 1.11.0', matches_constraint(parse_version('1.11.0'), '~1.10'));

  // >=
  assert_true('>=1.9.5 matches 1.10.0', matches_constraint(parse_version('1.10.0'), '>=1.9.5'));
  assert_false('>=1.10.5 fails 1.10.4', matches_constraint(parse_version('1.10.4'), '>=1.10.5'));

  // Bare version
  assert_true('1.10.0 matches 1.10.0', matches_constraint(parse_version('1.10.0'), '1.10.0'));
  assert_false('1.10.0 fails 1.9.5', matches_constraint(parse_version('1.9.5'), '1.10.0'));
end;

procedure test_fuzz_versions;
var
  Major, Minor, Patch: Integer;
  VerStr, Constraint: string;
  Ver: TVersion;
begin
  Randomize;

  // Generate versions from 0.0.0 to 2.5.2
  for Major := 0 to 2 do
    for Minor := 0 to 5 do
      for Patch := 0 to 2 do
      begin
        VerStr := Format('%d.%d.%d', [Major, Minor, Patch]);
        Ver := parse_version(VerStr);

        case Random(5) of
          0: Constraint := '^' + VerStr;
          1: Constraint := '~' + VerStr;
          2: Constraint := '>=' + VerStr;
          3: Constraint := '=' + VerStr;
          4: Constraint := VerStr;
        end;

        try
          // Ensure it returns boolean and does not crash
          assert_true('fuzz test returns boolean', matches_constraint(Ver, Constraint) in [True, False]);
        except
          on E: Exception do
            assert_true('fuzz test: no exceptions', False);
        end;
      end;
end;

procedure register_matches_constraint_tests;
begin
  start_unit('matches_constraint');

    register_test('caret', @test_caret);
    register_test('tilde', @test_tilde);
    register_test('gte', @test_gte);
    register_test('equal', @test_equal);
    register_test('bare version', @test_bare_version);
    register_test('empty', @test_empty);
    register_test('malformed/invalid', @test_malformed_constraints);
    register_test('less than one', @test_less_than_one);
    register_test('multi-digit versions', @test_multi_digit_versions);
    register_test('fuzz versions', @test_fuzz_versions);

  end_unit;
end;

end.
