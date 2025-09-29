unit test_SplitPackageSpec;

{$mode ObjFPC}{$H+}

interface

uses
  Classes,
  SysUtils,
  TapLib,
  Nova.Utils;

procedure register_splitpackagespec_tests;

implementation

procedure test_with_version;
var
  Name, Constraint: string;
begin
  SplitPackageSpec('vendor/package:^0.3', Name, Constraint);
  assert_equal('package name', 'vendor/package', Name);
  assert_equal('version constraint', '^0.3', Constraint);
end;

procedure test_without_version;
var
  Name, Constraint: string;
begin
  SplitPackageSpec('vendor/package', Name, Constraint);
  assert_equal('package name', 'vendor/package', Name);
  assert_equal('version constraint', '', Constraint);
end;

procedure test_empty_string;
var
  Name, Constraint: string;
begin
  SplitPackageSpec('', Name, Constraint);
  assert_equal('package name', '', Name);
  assert_equal('version constraint', '', Constraint);
end;

procedure register_splitpackagespec_tests;
begin
  start_unit('SplitPackageSpec');

    register_test('with version', @test_with_version);
    register_test('without version', @test_without_version);
    register_test('empty string', @test_empty_string);

  end_unit;
end;

end.


