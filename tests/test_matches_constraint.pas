unit test_matches_constraint;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, TapLib, Nova.Utils;

procedure register_matches_constraint_tests;

implementation

procedure test_caret;
begin
  assert_true('^0.3 matches 0.3.5', matches_constraint(parse_version('0.3.5'), '^0.3'));
  assert_true('^1.2 matches 1.2.0', matches_constraint(parse_version('1.2.0'), '^1.2'));
  assert_false('^1.2 fails 2.0.0', matches_constraint(parse_version('2.0.0'), '^1.2'));
end;

procedure test_tilde;
begin
  assert_true('~1.2 matches 1.2.5', matches_constraint(parse_version('1.2.5'), '~1.2'));
  assert_false('~1.2 fails 1.3.0', matches_constraint(parse_version('1.3.0'), '~1.2'));
end;

procedure test_gte;
begin
  assert_true('>=1.0 matches 1.2.0', matches_constraint(parse_version('1.2.0'), '>=1.0'));
  assert_true('>=1.0 matches 1.0.0', matches_constraint(parse_version('1.0.0'), '>=1.0'));
  assert_false('>=1.0 fails 0.9.9', matches_constraint(parse_version('0.9.9'), '>=1.0'));
end;

procedure test_equal;
begin
  assert_true('=1.2.3 matches 1.2.3', matches_constraint(parse_version('1.2.3'), '=1.2.3'));
  assert_false('=1.2.3 fails 1.2.4', matches_constraint(parse_version('1.2.4'), '=1.2.3'));
end;

procedure test_bare_version;
begin
  assert_true('1.2.3 matches 1.2.3', matches_constraint(parse_version('1.2.3'), '1.2.3'));
  assert_false('1.2.3 fails 1.2.4', matches_constraint(parse_version('1.2.4'), '1.2.3'));
end;

procedure test_empty;
begin
  assert_true('empty constraint matches anything', matches_constraint(parse_version('2.0.0'), ''));
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

procedure register_matches_constraint_tests;
begin
  start_unit('matches_constraint');

    register_test('caret', @test_caret);
    register_test('tilde', @test_tilde);
    register_test('gte', @test_gte);
    register_test('equal', @test_equal);
    register_test('bare version', @test_bare_version);
    register_test('empty', @test_empty);
    register_test('less than one', @test_less_than_one);

  end_unit;
end;

end.
