program TestSuite;

{$mode objfpc}{$H+}

uses
  SysUtils,
  TapLib,
  test_GitCLI;

begin
  start_tests;

  register_git_tests;

  // run everything
  run_tests;

  // finalize
  end_tests;
end.
