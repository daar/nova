program TestSuite;

{$mode objfpc}{$H+}

uses
  SysUtils,
  TapLib,
  test_GitCLI,
  test_SplitPackageSpec,
  test_matches_constraint;

begin
  start_tests;

  register_git_tests;
  register_splitpackagespec_tests;
  register_matches_constraint_tests;

  // run everything
  run_tests;

  // finalize
  end_tests;
end.
