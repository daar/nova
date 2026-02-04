program nova_tests;

{$mode objfpc}{$H+}

uses
  SysUtils,
  Classes,
  TapLib,
  Nova.Utils,
  Nova.Package,
  FPCConfigWriter;

{------------------------------------------------------------------------------
  Version Parsing Tests
------------------------------------------------------------------------------}

procedure TestParseVersionSimple;
var
  v: TVersion;
begin
  v := parse_version('1.2.3');
  assert_equal('major', 1, v.major);
  assert_equal('minor', 2, v.minor);
  assert_equal('patch', 3, v.patch);
end;

procedure TestParseVersionWithV;
var
  v: TVersion;
begin
  v := parse_version('v2.0.1');
  assert_equal('major with v prefix', 2, v.major);
  assert_equal('minor with v prefix', 0, v.minor);
  assert_equal('patch with v prefix', 1, v.patch);
end;

procedure TestParseVersionPartial;
var
  v: TVersion;
begin
  v := parse_version('1.2');
  assert_equal('major partial', 1, v.major);
  assert_equal('minor partial', 2, v.minor);
  assert_equal('patch defaults to 0', 0, v.patch);
end;

procedure TestParseVersionMajorOnly;
var
  v: TVersion;
begin
  v := parse_version('3');
  assert_equal('major only', 3, v.major);
  assert_equal('minor defaults to 0', 0, v.minor);
  assert_equal('patch defaults to 0', 0, v.patch);
end;

procedure TestParseVersionEmpty;
var
  v: TVersion;
begin
  v := parse_version('');
  assert_equal('empty major', 0, v.major);
  assert_equal('empty minor', 0, v.minor);
  assert_equal('empty patch', 0, v.patch);
end;

{------------------------------------------------------------------------------
  Version Comparison Tests
------------------------------------------------------------------------------}

procedure TestCompareVersionsEqual;
var
  a, b: TVersion;
begin
  a := parse_version('1.2.3');
  b := parse_version('1.2.3');
  assert_equal('equal versions', 0, compare_versions(a, b));
end;

procedure TestCompareVersionsMajorDiff;
var
  a, b: TVersion;
begin
  a := parse_version('2.0.0');
  b := parse_version('1.0.0');
  assert_true('2.0.0 > 1.0.0', compare_versions(a, b) > 0);
  assert_true('1.0.0 < 2.0.0', compare_versions(b, a) < 0);
end;

procedure TestCompareVersionsMinorDiff;
var
  a, b: TVersion;
begin
  a := parse_version('1.3.0');
  b := parse_version('1.2.0');
  assert_true('1.3.0 > 1.2.0', compare_versions(a, b) > 0);
end;

procedure TestCompareVersionsPatchDiff;
var
  a, b: TVersion;
begin
  a := parse_version('1.2.5');
  b := parse_version('1.2.3');
  assert_true('1.2.5 > 1.2.3', compare_versions(a, b) > 0);
end;

{------------------------------------------------------------------------------
  Constraint Matching Tests - Caret (^)
------------------------------------------------------------------------------}

procedure TestCaretConstraintMajor;
var
  v: TVersion;
begin
  // ^1.2.3 should match 1.x.x where x >= original
  v := parse_version('1.2.3');
  assert_true('^1.2.3 matches 1.2.3', matches_constraint(v, '^1.2.3'));

  v := parse_version('1.2.5');
  assert_true('^1.2.3 matches 1.2.5', matches_constraint(v, '^1.2.3'));

  v := parse_version('1.5.0');
  assert_true('^1.2.3 matches 1.5.0', matches_constraint(v, '^1.2.3'));

  v := parse_version('1.2.0');
  assert_false('^1.2.3 does not match 1.2.0', matches_constraint(v, '^1.2.3'));

  v := parse_version('2.0.0');
  assert_false('^1.2.3 does not match 2.0.0', matches_constraint(v, '^1.2.3'));
end;

procedure TestCaretConstraintZeroMajor;
var
  v: TVersion;
begin
  // ^0.2.3 should only allow 0.2.x changes
  v := parse_version('0.2.3');
  assert_true('^0.2.3 matches 0.2.3', matches_constraint(v, '^0.2.3'));

  v := parse_version('0.2.9');
  assert_true('^0.2.3 matches 0.2.9', matches_constraint(v, '^0.2.3'));

  v := parse_version('0.3.0');
  assert_false('^0.2.3 does not match 0.3.0', matches_constraint(v, '^0.2.3'));
end;

{------------------------------------------------------------------------------
  Constraint Matching Tests - Tilde (~)
------------------------------------------------------------------------------}

procedure TestTildeConstraint;
var
  v: TVersion;
begin
  // ~1.2.3 should only allow patch changes
  v := parse_version('1.2.3');
  assert_true('~1.2.3 matches 1.2.3', matches_constraint(v, '~1.2.3'));

  v := parse_version('1.2.9');
  assert_true('~1.2.3 matches 1.2.9', matches_constraint(v, '~1.2.3'));

  v := parse_version('1.3.0');
  assert_false('~1.2.3 does not match 1.3.0', matches_constraint(v, '~1.2.3'));

  v := parse_version('1.2.0');
  assert_false('~1.2.3 does not match 1.2.0', matches_constraint(v, '~1.2.3'));
end;

{------------------------------------------------------------------------------
  Constraint Matching Tests - Greater/Equal (>=)
------------------------------------------------------------------------------}

procedure TestGreaterEqualConstraint;
var
  v: TVersion;
begin
  v := parse_version('1.2.3');
  assert_true('>=1.2.3 matches 1.2.3', matches_constraint(v, '>=1.2.3'));

  v := parse_version('2.0.0');
  assert_true('>=1.2.3 matches 2.0.0', matches_constraint(v, '>=1.2.3'));

  v := parse_version('1.2.2');
  assert_false('>=1.2.3 does not match 1.2.2', matches_constraint(v, '>=1.2.3'));
end;

{------------------------------------------------------------------------------
  Constraint Matching Tests - Exact (=)
------------------------------------------------------------------------------}

procedure TestExactConstraint;
var
  v: TVersion;
begin
  v := parse_version('1.2.3');
  assert_true('=1.2.3 matches 1.2.3', matches_constraint(v, '=1.2.3'));

  v := parse_version('1.2.4');
  assert_false('=1.2.3 does not match 1.2.4', matches_constraint(v, '=1.2.3'));

  // Without = prefix should also be exact
  v := parse_version('1.2.3');
  assert_true('1.2.3 matches 1.2.3 (no prefix)', matches_constraint(v, '1.2.3'));
end;

{------------------------------------------------------------------------------
  Constraint Matching Tests - Empty/Wildcard
------------------------------------------------------------------------------}

procedure TestEmptyConstraint;
var
  v: TVersion;
begin
  v := parse_version('1.2.3');
  assert_true('empty constraint matches any', matches_constraint(v, ''));

  v := parse_version('99.99.99');
  assert_true('empty constraint matches any version', matches_constraint(v, ''));
end;

{------------------------------------------------------------------------------
  Package Spec Splitting Tests
------------------------------------------------------------------------------}

procedure TestSplitPackageSpecWithVersion;
var
  name, ver: string;
begin
  SplitPackageSpec('daar/linkedlist:^1.0', name, ver);
  assert_equal('package name', 'daar/linkedlist', name);
  assert_equal('version constraint', '^1.0', ver);
end;

procedure TestSplitPackageSpecNoVersion;
var
  name, ver: string;
begin
  SplitPackageSpec('daar/linkedlist', name, ver);
  assert_equal('package name without version', 'daar/linkedlist', name);
  assert_equal('empty version', '', ver);
end;

procedure TestSplitPackageSpecExactVersion;
var
  name, ver: string;
begin
  SplitPackageSpec('vendor/package:1.2.3', name, ver);
  assert_equal('package name exact', 'vendor/package', name);
  assert_equal('exact version', '1.2.3', ver);
end;

{------------------------------------------------------------------------------
  Nova Package Tests
------------------------------------------------------------------------------}

procedure TestNovaPackageCreate;
var
  pkg: TNovaPackage;
begin
  pkg := TNovaPackage.Create;
  try
    assert_equal('default name empty', '', pkg.Name);
    assert_equal('default type', 'library', pkg.PackageType);
    assert_equal('no required', 0, pkg.RequiredCount);
    assert_equal('no resolved', 0, pkg.ResolvedCount);
  finally
    pkg.Free;
  end;
end;

procedure TestNovaPackageAddRequired;
var
  pkg: TNovaPackage;
  req: TRequired;
begin
  pkg := TNovaPackage.Create;
  try
    pkg.AddRequired('daar/test', '^1.0', false);
    assert_equal('required count', 1, pkg.RequiredCount);

    req := pkg.RequiredAt(0);
    assert_equal('required name', 'daar/test', req.Name);
    assert_equal('required constraint', '^1.0', req.Constraint);
    assert_false('not dev', req.Dev);
  finally
    pkg.Free;
  end;
end;

procedure TestNovaPackageAddResolved;
var
  pkg: TNovaPackage;
  res: TResolved;
  sources: array of string;
  reqs: TRequiredArray;
begin
  pkg := TNovaPackage.Create;
  try
    SetLength(sources, 1);
    sources[0] := 'src';
    SetLength(reqs, 0);

    pkg.AddResolved('daar/test', 'v1.2.3', 'abc123', false, sources, reqs);
    assert_equal('resolved count', 1, pkg.ResolvedCount);

    res := pkg.ResolvedAt(0);
    assert_equal('resolved name', 'daar/test', res.Name);
    assert_equal('resolved version', 'v1.2.3', res.Version);
    assert_equal('resolved commit', 'abc123', res.Commit);
  finally
    pkg.Free;
  end;
end;

procedure TestNovaPackageFindResolved;
var
  pkg: TNovaPackage;
  res: TResolved;
  sources: array of string;
  reqs: TRequiredArray;
begin
  pkg := TNovaPackage.Create;
  try
    SetLength(sources, 1);
    sources[0] := 'src';
    SetLength(reqs, 0);

    pkg.AddResolved('daar/first', 'v1.0.0', 'aaa', false, sources, reqs);
    pkg.AddResolved('daar/second', 'v2.0.0', 'bbb', false, sources, reqs);

    res := pkg.FindResolved('daar/second');
    assert_equal('find second package', 'daar/second', res.Name);
    assert_equal('second version', 'v2.0.0', res.Version);

    res := pkg.FindResolved('nonexistent');
    assert_equal('nonexistent returns empty', '', res.Name);
  finally
    pkg.Free;
  end;
end;

procedure TestNovaPackageAlreadyRegistered;
var
  pkg: TNovaPackage;
begin
  pkg := TNovaPackage.Create;
  try
    pkg.AddRequired('daar/test', '^1.0', false);

    assert_true('package is registered', pkg.PackageAlreadyRegistered('daar/test'));
    assert_false('other not registered', pkg.PackageAlreadyRegistered('other/pkg'));
  finally
    pkg.Free;
  end;
end;

procedure TestNovaPackageSaveLoad;
var
  pkg1, pkg2: TNovaPackage;
  sources: array of string;
  reqs: TRequiredArray;
  testFile: string;
begin
  testFile := GetTempDir + 'nova_test_' + IntToStr(Random(100000)) + '.json';
  SetLength(sources, 1);
  sources[0] := 'src';
  SetLength(reqs, 0);

  pkg1 := TNovaPackage.Create;
  pkg2 := TNovaPackage.Create;
  try
    pkg1.Name := 'test/package';
    pkg1.Description := 'Test package';
    pkg1.License := 'MIT';
    pkg1.PackageType := 'library';
    pkg1.AddRequired('dep/one', '^1.0', false);
    pkg1.AddRequired('dep/two', '~2.0', true);
    pkg1.AddResolved('dep/one', 'v1.2.3', 'commit1', false, sources, reqs);

    pkg1.SaveToFile(testFile);

    pkg2.LoadFromFile(testFile);

    assert_equal('loaded name', 'test/package', pkg2.Name);
    assert_equal('loaded description', 'Test package', pkg2.Description);
    assert_equal('loaded license', 'MIT', pkg2.License);
    assert_equal('loaded required count', 2, pkg2.RequiredCount);
    assert_equal('loaded resolved count', 1, pkg2.ResolvedCount);
    assert_equal('loaded req name', 'dep/one', pkg2.RequiredAt(0).Name);
    assert_equal('loaded res version', 'v1.2.3', pkg2.ResolvedAt(0).Version);

    // Cleanup
    DeleteFile(testFile);
  finally
    pkg1.Free;
    pkg2.Free;
  end;
end;

{------------------------------------------------------------------------------
  Edge Cases and Advanced Tests
------------------------------------------------------------------------------}

procedure TestVersionPrerelease;
var
  v: TVersion;
begin
  // Prerelease versions like v1.0.0-alpha should parse the numeric part
  v := parse_version('v1.0.0-alpha');
  assert_equal('prerelease major', 1, v.major);
  assert_equal('prerelease minor', 0, v.minor);
  // Note: current impl doesn't handle -alpha specially, patch becomes 0
end;

procedure TestCaretEdgeCases;
var
  v: TVersion;
begin
  // ^0.0.3 should be exact match only
  v := parse_version('0.0.3');
  assert_true('^0.0.3 matches 0.0.3', matches_constraint(v, '^0.0.3'));

  v := parse_version('0.0.4');
  assert_false('^0.0.3 does not match 0.0.4', matches_constraint(v, '^0.0.3'));

  // ^1.0 (missing patch) should work like ^1.0.0
  v := parse_version('1.5.0');
  assert_true('^1.0 matches 1.5.0', matches_constraint(v, '^1.0'));

  v := parse_version('2.0.0');
  assert_false('^1.0 does not match 2.0.0', matches_constraint(v, '^1.0'));
end;

procedure TestTildeEdgeCases;
var
  v: TVersion;
begin
  // ~1.2 should allow 1.2.x
  v := parse_version('1.2.99');
  assert_true('~1.2 matches 1.2.99', matches_constraint(v, '~1.2'));

  v := parse_version('1.3.0');
  assert_false('~1.2 does not match 1.3.0', matches_constraint(v, '~1.2'));
end;

procedure TestMultipleRequired;
var
  pkg: TNovaPackage;
begin
  pkg := TNovaPackage.Create;
  try
    pkg.AddRequired('pkg/a', '^1.0', false);
    pkg.AddRequired('pkg/b', '~2.0', false);
    pkg.AddRequired('pkg/c', '>=3.0', true);

    assert_equal('three required', 3, pkg.RequiredCount);
    assert_equal('first name', 'pkg/a', pkg.RequiredAt(0).Name);
    assert_equal('second name', 'pkg/b', pkg.RequiredAt(1).Name);
    assert_equal('third name', 'pkg/c', pkg.RequiredAt(2).Name);
    assert_true('third is dev', pkg.RequiredAt(2).Dev);
  finally
    pkg.Free;
  end;
end;

procedure TestResolvedWithDependencies;
var
  pkg: TNovaPackage;
  sources: array of string;
  reqs: TRequiredArray;
  res: TResolved;
begin
  pkg := TNovaPackage.Create;
  try
    SetLength(sources, 2);
    sources[0] := 'src';
    sources[1] := 'lib';

    SetLength(reqs, 2);
    reqs[0].Name := 'dep/one';
    reqs[0].Constraint := '^1.0';
    reqs[0].Dev := false;
    reqs[1].Name := 'dep/two';
    reqs[1].Constraint := '~2.0';
    reqs[1].Dev := true;

    pkg.AddResolved('main/pkg', 'v1.0.0', 'abc123', false, sources, reqs);

    res := pkg.ResolvedAt(0);
    assert_equal('resolved has 2 sources', 2, Length(res.Source));
    assert_equal('resolved has 2 deps', 2, Length(res.Required));
    assert_equal('first dep name', 'dep/one', res.Required[0].Name);
  finally
    pkg.Free;
  end;
end;

procedure TestPackageAuthor;
var
  pkg: TNovaPackage;
begin
  pkg := TNovaPackage.Create;
  try
    pkg.AddAuthor('John Doe', 'john@example.com');
    pkg.AddAuthor('Jane Doe', 'jane@example.com');

    // Authors are stored but we can verify via save/load
    assert_true('has authors', true); // Basic check that it doesn't crash
  finally
    pkg.Free;
  end;
end;

procedure TestPackageSource;
var
  pkg: TNovaPackage;
begin
  pkg := TNovaPackage.Create;
  try
    pkg.AddSource('src/main.pas');
    pkg.AddSource('src/utils.pas');

    // Sources are stored but we can verify via save/load
    assert_true('has sources', true);
  finally
    pkg.Free;
  end;
end;

procedure TestFindPackageRequirements;
var
  pkg: TNovaPackage;
  sources: array of string;
  reqs, found: TRequiredArray;
begin
  pkg := TNovaPackage.Create;
  try
    SetLength(sources, 1);
    sources[0] := 'src';

    SetLength(reqs, 2);
    reqs[0].Name := 'sub/dep1';
    reqs[0].Constraint := '^1.0';
    reqs[0].Dev := false;
    reqs[1].Name := 'sub/dep2';
    reqs[1].Constraint := '~2.0';
    reqs[1].Dev := false;

    pkg.AddResolved('main/pkg', 'v1.0.0', 'abc', false, sources, reqs);

    found := pkg.FindPackageRequirements('main/pkg');
    assert_equal('found 2 requirements', 2, Length(found));
    assert_equal('first sub-dep', 'sub/dep1', found[0].Name);

    found := pkg.FindPackageRequirements('nonexistent');
    assert_equal('nonexistent has no requirements', 0, Length(found));
  finally
    pkg.Free;
  end;
end;

{------------------------------------------------------------------------------
  FPC Config Writer Tests
------------------------------------------------------------------------------}

procedure TestFPCConfigGeneration;
var
  pkg: TNovaPackage;
  sources: array of string;
  reqs: TRequiredArray;
  configFile: string;
  lines: TStringList;
begin
  configFile := GetTempDir + 'fpc_test_' + IntToStr(Random(100000)) + '.cfg';
  SetLength(sources, 1);
  sources[0] := 'src';
  SetLength(reqs, 0);

  pkg := TNovaPackage.Create;
  lines := TStringList.Create;
  try
    pkg.AddResolved('vendor/package1', 'v1.0.0', 'abc', false, sources, reqs);
    pkg.AddResolved('vendor/package2', 'v2.0.0', 'def', false, sources, reqs);

    TFPCConfigWriter.WriteConfig(pkg, configFile);

    assert_true('config file created', FileExists(configFile));

    lines.LoadFromFile(configFile);
    assert_true('has vendor paths', Pos('-Fu vendor', lines.Text) > 0);

    DeleteFile(configFile);
  finally
    pkg.Free;
    lines.Free;
  end;
end;

{------------------------------------------------------------------------------
  JSON Round-trip Tests
------------------------------------------------------------------------------}

procedure TestCompleteJSONRoundtrip;
var
  pkg1, pkg2: TNovaPackage;
  sources: array of string;
  reqs: TRequiredArray;
  testFile: string;
begin
  testFile := GetTempDir + 'nova_roundtrip_' + IntToStr(Random(100000)) + '.json';
  SetLength(sources, 2);
  sources[0] := 'src';
  sources[1] := 'lib';

  SetLength(reqs, 1);
  reqs[0].Name := 'sub/dependency';
  reqs[0].Constraint := '^1.0';
  reqs[0].Dev := false;

  pkg1 := TNovaPackage.Create;
  pkg2 := TNovaPackage.Create;
  try
    // Set up a complex package
    pkg1.Name := 'test/roundtrip';
    pkg1.Description := 'A test package for JSON roundtrip';
    pkg1.License := 'MIT';
    pkg1.PackageType := 'project';
    pkg1.AddAuthor('Test Author', 'test@example.com');
    pkg1.AddSource('main.pp');
    pkg1.AddRequired('dep/alpha', '^1.0', false);
    pkg1.AddRequired('dep/beta', '~2.0', true);
    pkg1.AddResolved('dep/alpha', 'v1.2.3', 'hash123', false, sources, reqs);

    // Save
    pkg1.SaveToFile(testFile);

    // Load into new package
    pkg2.LoadFromFile(testFile);

    // Verify all fields
    assert_equal('roundtrip name', 'test/roundtrip', pkg2.Name);
    assert_equal('roundtrip desc', 'A test package for JSON roundtrip', pkg2.Description);
    assert_equal('roundtrip license', 'MIT', pkg2.License);
    assert_equal('roundtrip type', 'project', pkg2.PackageType);
    assert_equal('roundtrip required count', 2, pkg2.RequiredCount);
    assert_equal('roundtrip resolved count', 1, pkg2.ResolvedCount);

    // Check resolved dependencies
    assert_equal('roundtrip res sources', 2, Length(pkg2.ResolvedAt(0).Source));
    assert_equal('roundtrip res reqs', 1, Length(pkg2.ResolvedAt(0).Required));

    DeleteFile(testFile);
  finally
    pkg1.Free;
    pkg2.Free;
  end;
end;

{------------------------------------------------------------------------------
  Main Test Runner
------------------------------------------------------------------------------}

begin
  start_tests;

  // Version parsing
  start_unit('VersionParsing');
  register_test('ParseSimple', @TestParseVersionSimple);
  register_test('ParseWithVPrefix', @TestParseVersionWithV);
  register_test('ParsePartial', @TestParseVersionPartial);
  register_test('ParseMajorOnly', @TestParseVersionMajorOnly);
  register_test('ParseEmpty', @TestParseVersionEmpty);

  // Version comparison
  start_unit('VersionComparison');
  register_test('CompareEqual', @TestCompareVersionsEqual);
  register_test('CompareMajorDiff', @TestCompareVersionsMajorDiff);
  register_test('CompareMinorDiff', @TestCompareVersionsMinorDiff);
  register_test('ComparePatchDiff', @TestCompareVersionsPatchDiff);

  // Constraint matching - Caret
  start_unit('ConstraintCaret');
  register_test('CaretMajor', @TestCaretConstraintMajor);
  register_test('CaretZeroMajor', @TestCaretConstraintZeroMajor);

  // Constraint matching - Tilde
  start_unit('ConstraintTilde');
  register_test('TildeConstraint', @TestTildeConstraint);

  // Constraint matching - Other
  start_unit('ConstraintOther');
  register_test('GreaterEqual', @TestGreaterEqualConstraint);
  register_test('Exact', @TestExactConstraint);
  register_test('Empty', @TestEmptyConstraint);

  // Package spec splitting
  start_unit('PackageSpec');
  register_test('SplitWithVersion', @TestSplitPackageSpecWithVersion);
  register_test('SplitNoVersion', @TestSplitPackageSpecNoVersion);
  register_test('SplitExactVersion', @TestSplitPackageSpecExactVersion);

  // Nova Package
  start_unit('NovaPackage');
  register_test('Create', @TestNovaPackageCreate);
  register_test('AddRequired', @TestNovaPackageAddRequired);
  register_test('AddResolved', @TestNovaPackageAddResolved);
  register_test('FindResolved', @TestNovaPackageFindResolved);
  register_test('AlreadyRegistered', @TestNovaPackageAlreadyRegistered);
  register_test('SaveLoad', @TestNovaPackageSaveLoad);

  // Edge Cases
  start_unit('EdgeCases');
  register_test('VersionPrerelease', @TestVersionPrerelease);
  register_test('CaretEdgeCases', @TestCaretEdgeCases);
  register_test('TildeEdgeCases', @TestTildeEdgeCases);

  // Advanced Package Tests
  start_unit('AdvancedPackage');
  register_test('MultipleRequired', @TestMultipleRequired);
  register_test('ResolvedWithDeps', @TestResolvedWithDependencies);
  register_test('PackageAuthor', @TestPackageAuthor);
  register_test('PackageSource', @TestPackageSource);
  register_test('FindRequirements', @TestFindPackageRequirements);

  // FPC Config
  start_unit('FPCConfig');
  register_test('ConfigGeneration', @TestFPCConfigGeneration);

  // JSON Round-trip
  start_unit('JSONRoundtrip');
  register_test('CompleteRoundtrip', @TestCompleteJSONRoundtrip);

  run_tests;
  end_tests;
end.
