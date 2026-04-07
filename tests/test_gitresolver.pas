unit test_GitResolver;

{$mode objfpc}{$H+}

interface

uses
Classes, SysUtils, TapLib, GitResolverCLI, VersionUtils;

procedure register_git_resolver_tests;

implementation

const
TEST_REPO = 'nova-packager/nova'; // GitHub repo to resolve versions from

procedure test_resolve_version_exact;
var
Git: TGitResolverCLI;
Ver: TVersion;
begin
Git := TGitResolverCLI.Create('.');
try
Ver := Git.ResolveVersion(TEST_REPO, '=0.0.1');
assert_true('exact version major=0', Ver.Major = 0);
assert_true('exact version minor=0', Ver.Minor = 0);
assert_true('exact version patch=1', Ver.Patch = 1);
finally
Git.Free;
end;
end;

procedure test_resolve_version_caret;
var
Git: TGitResolverCLI;
Ver: TVersion;
begin
Git := TGitResolverCLI.Create('.');
try
Ver := Git.ResolveVersion(TEST_REPO, '^0.1.0');
assert_true('caret major=0', Ver.Major = 0);
assert_true('caret minor>=1', Ver.Minor >= 1);
finally
Git.Free;
end;
end;

procedure test_resolve_version_tilde;
var
Git: TGitResolverCLI;
Ver: TVersion;
begin
Git := TGitResolverCLI.Create('.');
try
Ver := Git.ResolveVersion(TEST_REPO, '~0.0.1');
assert_true('tilde major=0', Ver.Major = 0);
assert_true('tilde minor=0', Ver.Minor = 0);
assert_true('tilde patch>=1', Ver.Patch >= 1);
finally
Git.Free;
end;
end;

procedure test_resolve_version_ge;
var
Git: TGitResolverCLI;
Ver: TVersion;
begin
Git := TGitResolverCLI.Create('.');
try
Ver := Git.ResolveVersion(TEST_REPO, '>=0.0.1');
assert_true('greater or equal major>=0', Ver.Major >= 0);
finally
Git.Free;
end;
end;

procedure test_resolve_version_latest;
var
Git: TGitResolverCLI;
Ver: TVersion;
begin
Git := TGitResolverCLI.Create('.');
try
Ver := Git.ResolveVersion(TEST_REPO, '');
assert_true('latest version found', (Ver.Major >= 0) and (Ver.Minor >= 0));
assert_true('hash not empty', Ver.hash <> '');
finally
Git.Free;
end;
end;

procedure register_git_resolver_tests;
begin
start_unit('GitResolverCLI');

```
register_test('resolve exact version', @test_resolve_version_exact);
register_test('resolve caret constraint', @test_resolve_version_caret);
register_test('resolve tilde constraint', @test_resolve_version_tilde);
register_test('resolve >= constraint', @test_resolve_version_ge);
register_test('resolve latest (no constraint)', @test_resolve_version_latest);
```

end_unit;
end;

end.
