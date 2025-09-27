unit test_GitCLI;

{$mode objfpc}{$H+}

interface

uses
  Classes,
  GitCLI,
  SysUtils,
  TapLib;

procedure register_git_tests;

implementation

var
  TestRepoDir: string;

const
  TESTURL = 'https://github.com/nova-packager/nova';

procedure setup_test_repo;
var
  Git: TGitCLI;
  Res: TGitResult;
begin
  TestRepoDir := IncludeTrailingPathDelimiter(GetCurrentDir) + 'testrepo';
  if DirectoryExists(TestRepoDir) then
    Exit; // already cloned

  Git := TGitCLI.Create(GetCurrentDir);
  try
    Res := Git.Clone(TESTURL, TestRepoDir);
    assert_true('clone success', Res.Success);
  finally
    Git.Free;
  end;
end;

procedure test_version;
var
  Git: TGitCLI;
  Res: TGitResult;
begin
  Git := TGitCLI.Create(TestRepoDir);
  try
    Res := Git.Version;
    assert_true('git version', Res.Success);
    assert_true('contains "git version"', pos('git version', Res.StdOut)>0);
  finally
    Git.Free;
  end;
end;

procedure test_status;
var
  Git: TGitCLI;
  Res: TGitResult;
begin
  Git := TGitCLI.Create(TestRepoDir);
  try
    Res := Git.Status;
    assert_true('git status', Res.Success);
    assert_true('on branch', pos('##', Res.StdOut)>0);
  finally
    Git.Free;
  end;
end;

procedure test_remote_url;
var
  Git: TGitCLI;
  Res: TGitResult;
begin
  Git := TGitCLI.Create(TestRepoDir);
  try
    Res := Git.GetRemoteURL('origin');
    assert_true('remote url success', Res.Success);
    assert_equal('github url', TESTURL, Res.StdOut);
  finally
    Git.Free;
  end;
end;

procedure test_checkout;
var
  Git: TGitCLI;
  Res: TGitResult;
begin
  Git := TGitCLI.Create(TestRepoDir);
  try
    Res := Git.Checkout('tags/v0.0.1');
    assert_true('checkout new branch', Res.Success or
      (Pos('already exists', Res.StdOut) > 0));
  finally
    Git.Free;
  end;
end;

procedure test_pull;
var
  Git: TGitCLI;
  Res: TGitResult;
begin
  Git := TGitCLI.Create(TestRepoDir);
  try
    Res := Git.Checkout('main');
    assert_true('checkout main again', Res.Success);

    Res := Git.Pull('origin', 'main');
    assert_true('pull exit code', Res.Success);
  finally
    Git.Free;
  end;
end;

procedure DeleteFolderRecursive(const Folder: string);
var
  SR: TSearchRec;
  Res: Integer;
  PathName: string;
begin
  if not DirectoryExists(Folder) then Exit;

  Res := FindFirst(IncludeTrailingPathDelimiter(Folder) + '*', faAnyFile, SR);
  while Res = 0 do
  begin
    PathName := IncludeTrailingPathDelimiter(Folder) + SR.Name;

    if (SR.Name <> '.') and (SR.Name <> '..') then
    begin
      if (SR.Attr and faDirectory) <> 0 then
        DeleteFolderRecursive(PathName)
      else
        SysUtils.DeleteFile(PathName);
    end;

    Res := FindNext(SR);
  end;
  FindClose(SR);

  // Finally, remove the empty folder itself
  RemoveDir(Folder);
end;

procedure cleanup_test_repo;
begin
  if DirectoryExists(TestRepoDir) then
  begin
    DeleteFolderRecursive(TestRepoDir);
    assert_true('cleanup testrepo folder', not DirectoryExists(TestRepoDir));
  end;
end;

procedure register_git_tests;
begin
  start_unit('GitCLI');

    register_test('setup repo', @setup_test_repo);
    register_test('version', @test_version);
    register_test('status', @test_status);
    register_test('remote-url', @test_remote_url);
    register_test('checkout', @test_checkout);
    register_test('pull', @test_pull);
    register_test('cleanup repo', @cleanup_test_repo);

  end_unit;
end;

end.
