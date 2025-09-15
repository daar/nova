program nova_bin;

{$mode objfpc}{$H+}

uses
  {$IFDEF WINDOWS}Windows,{$ENDIF}
  Classes,
  fpjson,
  jsonparser,
  process,
  SysUtils;

const
  NOVA_VERSION = '1.0.0';
  VENDOR_DIR   = 'vendor';
  LOCK_FILE    = 'nova.lock';
  DEP_FILE     = 'nova.json';
  BIN_DIR      = 'bin';
  FPC_CONFIG   = 'fpc.cfg';

type
  pOption = ^TOption;

  TOption = record
    name: string;
    description: string;
  end;

  pCommand = ^TCommand;
  TCommandproc = procedure(cmd: pCommand);

  TCommand = record
    name: string;
    proc: TCommandproc;
    description: string;
    options: TFPList; // List of pOption
  end;

  TVersion = record
    major, minor, patch: integer;
    name: string;
    constraint: string;
    hash: string;
  end;

  pResolvedDep = ^TResolvedDep;

  TResolvedDep = record
    name: string;        // e.g. daar/linkedlist
    constraint: string;  // original constraint from nova.json (e.g. "^1.2.0")
    version: string;     // resolved exact version (e.g. "1.2.3")
    commit: string;      // commit hash if from git, otherwise empty
    repo: string;        // source repo/registry URL
    dev: boolean;        // wether it's a dev package
    source: string;      // source directory in repo (default src)
    bin: TStringList;    // executable path (e.g. "bin/nova.exe")
    requires: TFPList;   // list of pResolvedDep (recursive requirements)
  end;

  pLockFile = ^TLockFile;

  TLockFile = record
    RootName: string;       // Name of the root project
    RootVersion: string;    // Version of the root project
    requires: TFPList;  // List of pResolvedDep (top-level deps)
  end;

var
  Commands: TFPList;
  jsonReq:  TJSONObject;

  { ------------------ Helper Functions ------------------ }

  procedure FreeCommands;
  var
    i, j: integer;
    cmd:  pCommand;
  begin
    if Commands <> nil then
    begin
      for i := 0 to Commands.Count - 1 do
      begin
        cmd := pCommand(Commands[i]);

        // Free options linked to this command
        if cmd^.options <> nil then
        begin
          for j := 0 to cmd^.options.Count - 1 do
            Dispose(pOption(cmd^.options[j]));
          cmd^.options.Free;
        end;

        Dispose(cmd);
      end;

      FreeAndNil(Commands);
    end;
  end;

  function run_and_capture(const Cmd: string; const Args: array of string): string;
  var
    P: TProcess;
    OutLines: TStringList;
  begin
    P := TProcess.Create(nil);
    OutLines := TStringList.Create;
    try
      P.Executable := Cmd;
      P.Parameters.AddStrings(Args);
      P.Options := [poWaitOnExit, poUsePipes];
      P.Execute;
      OutLines.LoadFromStream(P.Output);
      Result := Trim(OutLines.Text);
    finally
      P.Free;
      OutLines.Free;
    end;
  end;

  //  procedure RunCommand(const Cmd: string; const Args: array of string);
  //  begin
  //    writeln(run_and_capture(Cmd, Args));
  //  end;

  { ------------------ SemVer ------------------ }

  function parse_version(const S: string): TVersion;
  var
    Parts: TStringList;
    Clean: string;
  begin
    Result.Major := 0;
    Result.Minor := 0;
    Result.Patch := 0;

    Result.name := S;

    Clean := S;
    if (Length(Clean) > 0) and (Clean[1] = 'v') then
      Delete(Clean, 1, 1);

    Parts := TStringList.Create;
    try
      Parts.Delimiter := '.';
      Parts.StrictDelimiter := True;
      Parts.DelimitedText := Clean;

      if Parts.Count > 0 then
        Result.Major := StrToIntDef(Parts[0], 0);
      if Parts.Count > 1 then
        Result.Minor := StrToIntDef(Parts[1], 0);
      if Parts.Count > 2 then
        Result.Patch := StrToIntDef(Parts[2], 0);
    finally
      Parts.Free;
    end;
  end;

  function compare_versions(const A, B: TVersion): integer;
  begin
    if A.Major <> B.Major then exit(A.Major - B.Major);
    if A.Minor <> B.Minor then exit(A.Minor - B.Minor);
    Result := A.Patch - B.Patch;
  end;

  function matches_constraint(const Ver: TVersion; const Constraint: string): boolean;
  var
    Num:  string;
    CVer: TVersion;
  begin
    Result := False;
    if Constraint = '' then
      exit(True);

    if Pos('^', Constraint) = 1 then
    begin
      Num := Copy(Constraint, 2, MaxInt);
      CVer := parse_version(Num);
      Result := (Ver.Major = CVer.Major) and (compare_versions(Ver, CVer) >= 0);
    end
    else if Pos('~', Constraint) = 1 then
    begin
      Num := Copy(Constraint, 2, MaxInt);
      CVer := parse_version(Num);
      Result := (Ver.Major = CVer.Major) and (Ver.Minor = CVer.Minor) and
        (compare_versions(Ver, CVer) >= 0);
    end
    else if Pos('>=', Constraint) = 1 then
    begin
      Num := Copy(Constraint, 3, MaxInt);
      CVer := parse_version(Num);
      Result := compare_versions(Ver, CVer) >= 0;
    end
    else if Pos('=', Constraint) = 1 then
    begin
      Num := Copy(Constraint, 2, MaxInt);
      CVer := parse_version(Num);
      Result := compare_versions(Ver, CVer) = 0;
    end
    else
    begin
      CVer := parse_version(Constraint);
      Result := compare_versions(Ver, CVer) = 0;
    end;
  end;

  { ------------------ Git Resolver ------------------ }

  function resolve_version(const Repo, Constraint: string): TVersion;
  var
    Tags:  string;
    Lines: TStringList;
    i:     integer;
    Candidate, Best: string;
    CandidateVer, BestVer: TVersion;
  begin
    Tags := run_and_capture('git', ['ls-remote', '--tags',
      'https://github.com/' + Repo + '.git']);
    Lines := TStringList.Create;
    Best := '';
    try
      Lines.Text := Tags;
      for i := 0 to Lines.Count - 1 do
        if Pos('refs/tags/', Lines[i]) > 0 then
        begin
          Candidate := Copy(Lines[i], Pos('refs/tags/', Lines[i]) + 10, MaxInt);
          CandidateVer := parse_version(Candidate);
          CandidateVer.hash := Trim(Copy(Lines[i], 1, Pos(#9, Lines[i]) - 1));
          if matches_constraint(CandidateVer, Constraint) then
            if (Best = '') or (compare_versions(CandidateVer, BestVer) > 0) then
            begin
              Best := Candidate;
              BestVer := CandidateVer;
            end;
        end;

      if Best <> '' then Result := BestVer
      else
        Result := parse_version(Constraint);
    finally
      Lines.Free;
    end;
  end;

  procedure git_clone_or_update(const Repo, Path: string; const version, constraint, hash: string);
  begin
    if DirectoryExists(Path) then
    begin
      writeln('  -- Updating ', Repo, ':', constraint, ' → ', version, ' (' + Copy(hash, 1, 7) + ')');

      // Fetch all updates
      run_and_capture('git', ['-C', Path, 'fetch', '--all']);
      // Checkout the exact commit hash
      run_and_capture('git', ['-C', Path, 'checkout', hash]);
    end
    else
    begin
      writeln('  -- Installing ', Repo, ':', constraint, ' → ', version, ' (' + Copy(hash, 1, 7) + ')');

      // Clone the repository (full history required to checkout a commit hash)
      run_and_capture('git', ['clone', 'https://github.com/' + Repo + '.git', Path]);
      // Checkout the exact commit hash
      run_and_capture('git', ['-C', Path, 'checkout', hash]);
    end;
  end;

  { ------------------ JSON Helpers ------------------ }

  procedure save_json(const FName: string; jData: TJSONObject);
  var
    FS: TFileStream;
    S:  ansistring;
  begin
    FS := TFileStream.Create(FName, fmCreate);
    try
      S := ansistring(jData.FormatJSON());
      FS.WriteBuffer(S[1], Length(S));
    finally
      FS.Free;
    end;
  end;

  function create_or_load_json(const aFileName: string): TJSONObject;
  var
    ms: TMemoryStream;
  begin
    if FileExists(aFileName) then
    begin
      ms := TMemoryStream.Create;
      try
        ms.LoadFromFile(aFileName);
        Result := TJSONObject(GetJson(ms));
      finally
        ms.Free;
      end;
    end
    else
    begin
      Result := TJSONObject.Create;
      writeln('./', aFileName, ' has been created');
    end;
  end;

  { ------------------ Package Management ------------------ }

  function package_exists_in_section(const Section, packageName: string): boolean;
  var
    Obj: TJSONObject;
  begin
    Result := False;
    Obj := TJSONObject(jsonReq.FindPath(Section));
    if Obj <> nil then
      Result := Obj.IndexOfName(packageName) <> -1;
  end;

  function package_already_registered(const packageName: string): boolean;
  begin
    // Skip if package is already found
    if package_exists_in_section('require', packageName) or
      package_exists_in_section('require-dev', packageName) then
    begin
      writeln('Package "', packageName, '" is already present. Skipping.');
      exit(True);
    end;
    exit(False);
  end;

  procedure update_requirements_file(const packageName, versionConstraint: string;
  const includeDev: boolean);
  var
    jsonPkg: TJSONObject;
  begin
    // Update nova.json
    if includeDev then
    begin
      jsonPkg := TJSONObject(jsonReq.FindPath('require-dev'));
      if jsonPkg = nil then
      begin
        jsonPkg := TJSONObject.Create;
        jsonReq.Add('require-dev', jsonPkg);
      end;
    end
    else
    begin
      jsonPkg := TJSONObject(jsonReq.FindPath('require'));
      if jsonPkg = nil then
      begin
        jsonPkg := TJSONObject.Create;
        jsonReq.Add('require', jsonPkg);
      end;
    end;
    jsonPkg.Add(packageName, versionConstraint);
  end;

  function resolve_constraint(const packageName, versionConstraint: string): TVersion;
  begin
    // Resolve version from packageName
    Result := resolve_version(packageName, versionConstraint);

    // Determine versionConstraint
    if versionConstraint <> '' then
      Result.constraint := versionConstraint
    else
      // Default: caret constraint on Major.Minor
      Result.constraint := Format('^%d.%d', [Result.major, Result.minor]);
  end;

  procedure write_fpc_config(lock: pLockFile);
  var
    FPCLines: TStringList;

    procedure AddDepPaths(dep: pResolvedDep);
    var
      PathVal: string;
      i:   integer;
      sub: pResolvedDep;
    begin
      if dep = nil then exit;

      // Add the vendor path for this package
      PathVal := IncludeTrailingPathDelimiter(VENDOR_DIR) +
        StringReplace(dep^.name, '/', PathDelim, [rfReplaceAll]);

      if dep^.source <> '' then
        PathVal := IncludeTrailingPathDelimiter(PathVal) + dep^.source
      else
        PathVal := IncludeTrailingPathDelimiter(PathVal) + 'src';

      FPCLines.Add('-Fu ' + PathVal);

      // Recurse into nested dependencies
      for i := 0 to dep^.Requires.Count - 1 do
      begin
        sub := pResolvedDep(dep^.Requires[i]);
        AddDepPaths(sub);
      end;
    end;

  var
    i: integer;
    BaseConfig: string;
  begin
    FPCLines := TStringList.Create;
    try
      // Determine base/system fpc.cfg
      {$IFDEF UNIX}
      BaseConfig := '/etc/fpc.cfg';
      {$ENDIF}
      {$IFDEF MSWINDOWS}
      BaseConfig := IncludeTrailingPathDelimiter(GetEnvironmentVariable('FPCDIR')) +
        'bin' + PathDelim + 'i386-win32' + PathDelim + 'fpc.cfg';
      {$ENDIF}

      // Add auto-generated header
      FPCLines.Add('#');
      FPCLines.Add('# Config file generated by nova on ' + DateToStr(Date) +
        ' - ' + TimeToStr(Time));
      FPCLines.Add('#');
      FPCLines.Add('');

      // Include base config if it exists
      if (BaseConfig <> '') and FileExists(BaseConfig) then
      begin
        FPCLines.Add('# Include system/base FPC configuration');
        FPCLines.Add('#include ' + BaseConfig);
        FPCLines.Add('');
      end;

      FPCLines.Add('# Vendor package search paths');

      // Add all top-level requirements and their nested deps
      for i := 0 to lock^.requires.Count - 1 do
        AddDepPaths(pResolvedDep(lock^.requires[i]));

      // Save the generated config
      FPCLines.SaveToFile(FPC_CONFIG);
      writeln('Generated ', FPC_CONFIG);
    finally
      FPCLines.Free;
    end;
  end;

  function load_lock_file: pLockFile;

    function JSONToDep(const name: string; obj: TJSONObject): pResolvedDep;
    var
      dep: pResolvedDep;
      bins, reqs: TJSONObject;
      it:  TJSONEnum;
    begin
      New(dep);
      dep^.name := name;
      dep^.constraint := obj.Get('constraint', '');
      dep^.version := obj.Get('version', '');
      dep^.commit := obj.Get('commit', '');
      dep^.source := obj.Get('source', '');
      dep^.repo := obj.Get('repo', '');
      dep^.dev := obj.Get('dev', False);

      // Bin section
      dep^.Bin := TStringList.Create;
      bins := obj.Objects['bin'];
      if Assigned(bins) then
        for it in bins do
          dep^.Bin.Add(it.Key + '=' + it.Value.AsString);

      // Requires section (recursive)
      dep^.Requires := TFPList.Create;
      reqs := obj.Objects['requires'];
      if Assigned(reqs) then
        for it in reqs do
          dep^.Requires.Add(JSONToDep(it.Key, TJSONObject(it.Value)));

      Result := dep;
    end;

  var
    root, deps: TJSONObject;
    it:   TJSONEnum;
    lock: pLockFile;
    depsData: TJSONData;
  begin
    try
      root := create_or_load_json(LOCK_FILE);

      New(lock);
      lock^.RootName := root.Get('name', '');
      lock^.RootVersion := root.Get('version', '');
      lock^.requires := TFPList.Create;

      depsData := root.Find('requires');
      if Assigned(depsData) then
      begin
        deps := root.Objects['requires'];

        for it in deps do
          lock^.requires.Add(JSONToDep(it.Key, TJSONObject(it.Value)));
      end;

      Result := lock;
    finally
      root.Free;
    end;
  end;

  procedure save_lock_file(lock: pLockFile);

    function DepToJSON(dep: pResolvedDep): TJSONObject;
    var
      obj, bins, reqs: TJSONObject;
      i:   integer;
      sub: pResolvedDep;
    begin
      obj := TJSONObject.Create;
      obj.Add('constraint', dep^.Constraint);
      obj.Add('version', dep^.Version);
      obj.Add('commit', dep^.Commit);
      obj.Add('repo', dep^.repo);
      obj.Add('source', dep^.source);
      obj.Add('dev', dep^.dev);

      // Bin section
      bins := TJSONObject.Create;
      for i := 0 to dep^.Bin.Count - 1 do
        bins.Add(dep^.Bin.Names[i], dep^.Bin.ValueFromIndex[i]);
      obj.Add('bin', bins);

      // Requires section (recursive)
      reqs := TJSONObject.Create;
      for i := 0 to dep^.Requires.Count - 1 do
      begin
        sub := pResolvedDep(dep^.Requires[i]);
        reqs.Add(sub^.name, DepToJSON(sub));
      end;
      obj.Add('requires', reqs);

      Result := obj;
    end;

  var
    root, deps: TJSONObject;
    i:   integer;
    dep: pResolvedDep;
  begin
    if lock = nil then exit;

    root := TJSONObject.Create;
    try
      root.Add('name', lock^.RootName);
      root.Add('version', lock^.RootVersion);

      deps := TJSONObject.Create;
      for i := 0 to lock^.requires.Count - 1 do
      begin
        dep := pResolvedDep(lock^.requires[i]);
        deps.Add(dep^.name, DepToJSON(dep));
      end;
      root.Add('requires', deps);

      // Save JSON to file with indentation
      save_json(LOCK_FILE, root);
    finally
      root.Free;
    end;
  end;

  procedure free_lock_file(lock: PLockFile);

    procedure FreeResolvedDep(dep: pResolvedDep);
    var
      i:   integer;
      sub: pResolvedDep;
    begin
      if dep = nil then exit;

      // Free nested requires recursively
      if Assigned(dep^.Requires) then
      begin
        for i := 0 to dep^.Requires.Count - 1 do
        begin
          sub := pResolvedDep(dep^.Requires[i]);
          FreeResolvedDep(sub);
        end;
        dep^.Requires.Free;
      end;

      // Free bin mapping
      if Assigned(dep^.Bin) then
        dep^.Bin.Free;

      // Finally dispose the record itself
      Dispose(dep);
    end;

  var
    i:   integer;
    dep: pResolvedDep;
  begin
    if lock = nil then exit;

    // Free all top-level requires
    if Assigned(lock^.requires) then
    begin
      for i := 0 to lock^.requires.Count - 1 do
      begin
        dep := pResolvedDep(lock^.requires[i]);
        FreeResolvedDep(dep);
      end;
      lock^.requires.Free;
    end;

    // Finally free the lock file record
    Dispose(lock);
  end;

  function add_package_to_lock(lock: pLockFile; const name: string;
  const Version: TVersion; const Source: string = ''; const Repo: string = '';
  const dev: boolean = False): pResolvedDep;
  begin
    if lock = nil then exit;

    New(Result);
    Result^.name := name;
    Result^.Constraint := Version.constraint;
    Result^.Version := Version.name;
    Result^.Commit := Version.hash;
    Result^.source := Source;
    Result^.repo := Repo;
    Result^.Bin := TStringList.Create;
    Result^.Requires := TFPList.Create;
    Result^.dev := dev;

    lock^.requires.Add(Result);
  end;

  procedure purge_vendor_folder(lock: pLockFile);

  // Checks recursively whether 'name' exists anywhere in the lock file tree.
  function LockContainsPackage(const name: string): Boolean;
    function DepContains(dep: pResolvedDep): Boolean;
    var
      i: integer;
      sub: pResolvedDep;
    begin
      if dep = nil then
        Exit(False);
      if SameText(dep^.Name, name) then
        Exit(True);
      if Assigned(dep^.Requires) then
      begin
        for i := 0 to dep^.Requires.Count - 1 do
        begin
          sub := pResolvedDep(dep^.Requires[i]);
          if DepContains(sub) then
            Exit(True);
        end;
      end;
      Result := False;
    end;
  var
    i: integer;
    top: pResolvedDep;
  begin
    Result := False;
    if (lock = nil) or (lock^.requires = nil) then Exit;
    for i := 0 to lock^.requires.Count - 1 do
    begin
      top := pResolvedDep(lock^.requires[i]);
      if DepContains(top) then
        Exit(True);
    end;
  end;

  // Returns True if directory is empty (no files or subdirs except . and ..)
  function IsDirEmpty(const Dir: string): Boolean;
  var
    sr: TSearchRec;
    found: integer;
  begin
    Result := True;
    found := FindFirst(IncludeTrailingPathDelimiter(Dir) + '*', faAnyFile, sr);
    if found = 0 then
    begin
      try
        repeat
          if (sr.Name <> '.') and (sr.Name <> '..') then
          begin
            Result := False;
            Exit;
          end;
        until FindNext(sr) <> 0;
      finally
        FindClose(sr);
      end;
    end;
  end;

  // Remove empty parent directories up to VENDOR_DIR (recursively upward)
  procedure RemoveEmptyParents(startDir: string);
  var
    parent: string;
  begin
    parent := ExtractFileDir(startDir);
    // Stop if we reached vendor root or nothing sensible
    while (parent <> '') and (ExpandFileName(parent) <> ExpandFileName(VENDOR_DIR)) do
    begin
      if IsDirEmpty(parent) then
      begin
        // try remove and continue upward
        if RemoveDir(parent) then
          parent := ExtractFileDir(parent)
        else
          Exit; // cannot remove, stop
      end
      else
        Exit; // not empty -> stop
    end;
  end;

var
  srParent, srPkg: TSearchRec;
  parentDir, pkgDir: string;
  parentName, pkgName, repoName: string;
  foundParent: integer;
begin
  if (lock = nil) or (not DirectoryExists(VENDOR_DIR)) then
    Exit;

  // Iterate parents under vendor/
  foundParent := FindFirst(IncludeTrailingPathDelimiter(VENDOR_DIR) + '*', faDirectory, srParent);
  if foundParent <> 0 then Exit;
  try
    repeat
      // only directories, skip . and ..
      if (srParent.Attr and faDirectory) = 0 then Continue;
      if (srParent.Name = '.') or (srParent.Name = '..') then Continue;

      parentName := srParent.Name;
      parentDir := IncludeTrailingPathDelimiter(VENDOR_DIR) + parentName;

      // Iterate package directories inside each parent
      if DirectoryExists(parentDir) then
      begin
        if FindFirst(IncludeTrailingPathDelimiter(parentDir) + '*', faDirectory, srPkg) = 0 then
        begin
          try
            repeat
              if (srPkg.Attr and faDirectory) = 0 then Continue;
              if (srPkg.Name = '.') or (srPkg.Name = '..') then Continue;

              pkgName := srPkg.Name;
              // Construct repo name exactly as stored in the lock (parent/package)
              repoName := parentName + '/' + pkgName;

              // If package not present in lock -> delete it
              if not LockContainsPackage(repoName) then
              begin
                pkgDir := IncludeTrailingPathDelimiter(parentDir) + pkgName;
                {$IFDEF WINDOWS}
                run_and_capture('rmdir', ['/S','/Q', pkgDir]);
                {$ELSE}
                run_and_capture('rm', ['-rf', pkgDir]);
                {$ENDIF}
                writeln('Deleted vendor files for "', repoName, '".');
              end;
            until FindNext(srPkg) <> 0;
          finally
            FindClose(srPkg);
          end;
        end;

        // After processing all packages for this parent, remove the parent if it's empty
        if IsDirEmpty(parentDir) then
        begin
          // Try to remove parent folder
          if RemoveDir(parentDir) then
            writeln('Removed empty vendor parent "', parentName, '".')
          else
            // If RemoveDir failed (maybe not empty due to hidden files), attempt recursive removal as last resort
            begin
              {$IFDEF WINDOWS}
              run_and_capture('rmdir', ['/S','/Q', parentDir]);
              {$ELSE}
              run_and_capture('rm', ['-rf', parentDir]);
              {$ENDIF}
              writeln('Removed vendor parent "', parentName, '" (forced).');
            end;
          // Clean upward parents if any (stops at VENDOR_DIR)
          RemoveEmptyParents(parentDir);
        end;
      end;
    until FindNext(srParent) <> 0;
  finally
    FindClose(srParent);
  end;
end;

  function internal_remove_package(const Repo: string; lockFile: PLockFile): boolean;

    function RemoveRequirement(const Repo: string; root: TJSONObject;
    const section: string): boolean;
    var
      depsObj: TJSONObject;
    begin
      Result := False;

      if root = nil then
        exit;

      // Lazily ensure the section exists
      if root.Find(section) = nil then
        exit; // nothing to remove

      depsObj := root.Objects[section];

      if (depsObj <> nil) and (depsObj.IndexOfName(Repo) <> -1) then
      begin
        depsObj.Remove(depsObj.Find(Repo));
        Result := True;
      end;
    end;

    function IsOrphan(const Repo: string; lockFile: PLockFile): boolean;
    var
      i, j:     integer;
      dep, sub: pResolvedDep;
    begin
      // Check if Repo is referenced in any dependency's Requires list
      for i := 0 to lockFile^.requires.Count - 1 do
      begin
        dep := pResolvedDep(lockFile^.requires[i]);
        if dep^.name = Repo then
          Continue; // skip self

        if dep^.requires <> nil then
          for j := 0 to dep^.requires.Count - 1 do
          begin
            sub := pResolvedDep(dep^.requires[j]);
            if sub^.name = Repo then
              exit(False); // found as a dependency somewhere else
          end;
      end;
      Result := True; // not referenced anywhere → orphan
    end;

  var
    removed: boolean;
    i:   integer;
    dep: pResolvedDep;
  begin
    removed := RemoveRequirement(Repo, jsonReq, 'require') or
      RemoveRequirement(Repo, jsonReq, 'require-dev');

    if removed then
    begin
      writeln('Removed "', Repo, '" from ', DEP_FILE);

      // Look up Repo in lock file
      for i := lockFile^.requires.Count - 1 downto 0 do
      begin
        dep := pResolvedDep(lockFile^.requires[i]);
        if dep^.name = Repo then
          if IsOrphan(Repo, lockFile) then
          begin
            // Recursively remove its dependencies
            if dep^.requires <> nil then
              while dep^.requires.Count > 0 do
              begin
                internal_remove_package(pResolvedDep(dep^.requires[0])^.name, lockFile);
                dep^.requires.Delete(0);
              end;

            // Finally, remove the package itself from lock file
            lockFile^.requires.Delete(i);
            dispose(dep);

            Break;
          end;
      end;
    end
    else
      writeln('Package "', Repo, '" was not found.');

    exit(removed);
  end;

  function default_package_name: string;
  var
    UserName, FolderName: string;
    Path: string;
  begin
    // Get username
    {$IFDEF WINDOWS}
    SetLength(UserName, 256);
    if GetEnvironmentVariable('USERNAME', PChar(UserName), Length(UserName)) > 0 then
      UserName := Trim(PChar(UserName));
    {$ELSE}
    UserName := GetEnvironmentVariable('USER');
    {$ENDIF}

    if UserName = '' then
      UserName := 'user';

    // Get current folder name
    Path := GetCurrentDir;
    FolderName := ExtractFileName(Path);

    if FolderName = '' then
      FolderName := 'project';

    Result := LowerCase(UserName) + '/' + LowerCase(FolderName);
  end;

  function default_author: string;
  var
    FullName, Email: string;
  begin
    // Try to get author information from Git configuration
    FullName := GetEnvironmentVariable('GIT_AUTHOR_NAME');
    Email := GetEnvironmentVariable('GIT_AUTHOR_EMAIL');

    // If Git information is not available, fallback to environment variables
    if (FullName = '') or (Email = '') then
    begin
      FullName := GetEnvironmentVariable('USER');
      Email := GetEnvironmentVariable('EMAIL');
    end;

    // If both are still unavailable, fallback to system user information
    if (FullName = '') or (Email = '') then
    begin
      {$IFDEF WINDOWS}
      FullName := GetEnvironmentVariable('USERNAME');
      {$ELSE}
      FullName := GetEnvironmentVariable('USER');
      {$ENDIF}
      Email := 'user@example.com';
    end;

    // Return the formatted author string
    Result := FullName + ' <' + Email + '>';
  end;

  // TODO: Replace ReadLn with a full-featured line editor library to support backspace, cursor navigation, and interactive input.
  procedure CmdInit(cmd: pCommand);
  var
    JsonObj:     TJSONObject;
    PackageName, Version, License: string;
    description: string;
    AuthorName:  string;
  begin
    writeln('This command will guide you through creating you ', DEP_FILE, ' config.');
    writeln;

    Write('Package name (<vendor>/<name>) [', default_package_name, ']: ');
    ReadLn(PackageName);
    if PackageName = '' then
      PackageName := default_package_name;

    Write('Description []: ');
    ReadLn(description);

    Write('Author [', default_author, ']: ');
    ReadLn(AuthorName);
    if AuthorName = '' then
      AuthorName := default_author;

    Write('Project version [0.1.0]: ');
    ReadLn(Version);
    if Version = '' then
      Version := '0.1.0';

    Write('License [MIT]: ');
    ReadLn(License);
    if License = '' then
      License := 'MIT';

    JsonObj := TJSONObject.Create;
    try
      JsonObj.Add('name', PackageName);
      JsonObj.Add('version', Version);
      JsonObj.Add('license', License);
      JsonObj.Add('author', AuthorName);
      JsonObj.Add('description', description);
      JsonObj.Add('require', TJSONObject.Create);
      JsonObj.Add('require-dev', TJSONObject.Create);
      JsonObj.Add('bin', TJSONArray.Create);

      save_json(DEP_FILE, JsonObj);
      writeln('Created ', DEP_FILE, ' with basic information.');
    finally
      JsonObj.Free;
    end;

    writeln('You can now run `nova require <vendor/package>` to add requirements.');
  end;

  procedure print_version;
  begin
    writeln('nova ', NOVA_VERSION);
  end;

  procedure print_usage;
  var
    i, j: integer;
    cmd:  pCommand;
    opt:  pOption;
  begin
    print_version;
    writeln('Copyright (c) 2025 by Darius Blaszyk');
    writeln('Usage: nova <command> [options] [package[:version] ...]');
    writeln;

    writeln('Available commands:');
    for i := 0 to Commands.Count - 1 do
    begin
      cmd := pCommand(Commands[i]);
      writeln(Format('  %-15s %s', [cmd^.name, cmd^.description]));

      for j := 0 to cmd^.options.Count - 1 do
      begin
        opt := pOption(cmd^.options[j]);
        writeln(Format('    %-13s %s', [opt^.name, opt^.description]));
      end;
    end;

    writeln;
    writeln('Global options:');
    writeln(Format('  %-15s %s', ['-h, --help', 'Display this help message']));
    writeln(Format('  %-15s %s', ['-v, --version', 'Show nova version']));
    writeln;
    writeln('Examples:');
    writeln('  nova init');
    writeln('  nova require daar/linkedlist');
    writeln('  nova require daar/linkedlist:1.0.0 --dev');
    writeln('  nova show --tree');
  end;

  procedure split_package_spec(const fullParam: string;
    out packageName, versionConstraint: string);
  var
    sepPos: integer;
  begin
    sepPos := Pos(':', fullParam);

    if sepPos > 0 then
    begin
      packageName := Copy(fullParam, 1, sepPos - 1);
      versionConstraint := Copy(fullParam, sepPos + 1, Length(fullParam));
    end
    else
    begin
      // No version constraint specified
      packageName := fullParam;
      versionConstraint := '';
    end;
  end;

  function FindOrAddPackage(lockFile: PLockFile;
  const packageName, versionConstraint: string; const includeDev: boolean;
    out dep: pResolvedDep): boolean;
  var
    i: integer;
    existing: pResolvedDep;
    v: TVersion;
  begin
    // Look for existing package in lock file
    for i := 0 to lockFile^.requires.Count - 1 do
    begin
      existing := pResolvedDep(lockFile^.requires[i]);
      if existing^.name = packageName then
      begin
        // Conflict: existing version does not satisfy requested constraint
        if not matches_constraint(parse_version(existing^.Version),
          versionConstraint) then
        begin
          writeln('Error: Dependency conflict for ', packageName);
          writeln('  Existing: ', existing^.Version,
            ' (from lock file)');
          writeln('  Requested: ', versionConstraint,
            ' (cannot be satisfied)');

          //TODO : review design, still 17 unfreed memory blocks, this design seems to be cumbersome
          FreeCommands;
          free_lock_file(lockFile);

          halt(1);
        end;

        // Already satisfied
        dep := existing;
        exit(True);
      end;
    end;

    // If not found then resolve and add
    v := resolve_constraint(packageName, versionConstraint);

    dep := add_package_to_lock(lockFile, packageName, v, '', '', includeDev);

    Result := False; // means new package added
  end;

  function internal_require(lockFile: pLockFile;
  const packageName, versionConstraint: string; out dep: pResolvedDep;
  const includeDev: boolean): boolean;

    procedure ProcessDependencies(lockFile: PLockFile; depsObj: TJSONObject;
    const includeDev: boolean);
    var
      it:  TJSONEnum;
      dep: pResolvedDep;
    begin
      if not Assigned(depsObj) then exit;

      for it in depsObj do
        // Recursively install required package
        internal_require(lockFile, it.Key, it.Value.AsString, dep, includeDev);
    end;

  var
    v: TVersion;
    path, pkgFile: string;
    pkgJSON: TJSONObject;
  begin
    v := resolve_constraint(packageName, versionConstraint);

    // Already present and compatible, nothing to do
    if FindOrAddPackage(lockFile, packageName, v.constraint, includeDev, dep) then
      exit(True);

    // Resolve path and install
    path := VENDOR_DIR + PathDelim + StringReplace(packageName, '/',
      PathDelim, [rfReplaceAll]);
    git_clone_or_update(packageName, path, v.name, v.constraint, v.hash);


    //check if we need to descend recursively
    pkgFile := path + PathDelim + DEP_FILE;
    if fileexists(pkgFile) then
    begin
      //load pkgfile
      pkgJSON := create_or_load_json(pkgFile);

      //process all require packages
      ProcessDependencies(lockFile, pkgJSON.Objects['require'], False);

      //if includeDev, then process all require-dev packages
      if includeDev then
        ProcessDependencies(lockFile, pkgJSON.Objects['require-dev'], True);
    end;

    exit(True);
  end;

   procedure print_dependency_tree(const Repo: string; const Prefix: string;
    isDev: boolean);
  var
    Path, DepFile: string;
    JSONData, RequireObj, DevObj: TJSONObject;
    i: integer;
    ChildRepo, Constraint: string;
  begin
    Path := VENDOR_DIR + PathDelim + StringReplace(Repo, '/', PathDelim, [rfReplaceAll]);
    DepFile := Path + PathDelim + DEP_FILE;

    if not FileExists(DepFile) then exit;

    JSONData := create_or_load_json(DepFile);
    RequireObj := TJSONObject(JSONData.FindPath('require'));
    if RequireObj <> nil then
      for i := 0 to RequireObj.Count - 1 do
      begin
        ChildRepo := RequireObj.Names[i];
        Constraint := RequireObj.Items[i].AsString;
        writeln(Prefix, '└─ ', ChildRepo, ' ', Constraint);
        print_dependency_tree(ChildRepo, Prefix + '   ', False);
      end;

    if isDev then
    begin
      DevObj := TJSONObject(JSONData.FindPath('require-dev'));
      if DevObj <> nil then
        for i := 0 to DevObj.Count - 1 do
        begin
          ChildRepo := DevObj.Names[i];
          Constraint := DevObj.Items[i].AsString;
          writeln(Prefix, '└─ [dev] ', ChildRepo, ' ', Constraint);
          print_dependency_tree(ChildRepo, Prefix + '   ', True);
        end;
    end;

    JSONData.Free;
  end;

  procedure nova_list(showTree: boolean);
  var
    LockJson: TJSONObject;
    RequireObj, DevObj: TJSONObject;
    Repo, Constraint, Version, Commit: string;
    LockPkg:  TJSONObject;

    procedure print_section(Obj: TJSONObject; isDev: boolean);
    var
      j: integer;
    begin
      if Obj = nil then exit;
      for j := 0 to Obj.Count - 1 do
      begin
        Repo := Obj.Names[j];
        Constraint := Obj.Items[j].AsString;

        LockPkg := TJSONObject(LockJson.FindPath(Repo));
        if LockPkg <> nil then
        begin
          Version := LockPkg.Get('version', '');
          Commit := '(' + Copy(LockPkg.Get('hash', ''), 1, 7) + ')';
        end
        else
        begin
          Version := '(not installed)';
          Commit := '';
        end;

        if isDev then
          writeln('* [dev] ', Repo: 30, ' ', Constraint: 10, ' → ',
            Version, ' ', Commit)
        else
          writeln('* ', Repo: 30, ' ', Constraint: 10, ' → ', Version, ' ', Commit);

        if showTree then
          print_dependency_tree(Repo, '   ', isDev);
      end;
    end;

  begin
    if not FileExists(DEP_FILE) then
    begin
      writeln('No ', DEP_FILE, ' found. Run "nova init" first.');
      exit;
    end;

    if FileExists(LOCK_FILE) then
      LockJson := create_or_load_json(LOCK_FILE)
    else
      LockJson := TJSONObject.Create;

    try
      writeln('Installed packages:');
      writeln;

      RequireObj := TJSONObject(jsonReq.FindPath('require'));
      print_section(RequireObj, False);

      DevObj := TJSONObject(jsonReq.FindPath('require-dev'));
      print_section(DevObj, True);

      writeln;
    finally
      LockJson.Free;
    end;
  end;

  procedure RegisterOption(cmd: pCommand; const name, description: string);
  var
    opt: pOption;
    i:   integer;
  begin
    New(opt);
    opt^.name := name;
    opt^.description := description;

    i := 0;
    while (i < cmd^.options.Count) and
      (LowerCase(pOption(cmd^.options[i])^.name) < LowerCase(name)) do
      Inc(i);

    cmd^.options.Insert(i, opt);
  end;

  function RegisterCommand(const name, description: string;
    proc: TCommandproc): pCommand;
  var
    cmd: pCommand;
    i:   integer;
  begin
    New(cmd);
    cmd^.name := name;
    cmd^.description := description;
    cmd^.proc := proc;
    cmd^.options := TFPList.Create;

    i := 0;
    while (i < Commands.Count) and (LowerCase(pCommand(Commands[i])^.name) <
        LowerCase(name)) do
      Inc(i);

    Commands.Insert(i, cmd);
    Result := cmd;
  end;

  function HasOption(const optName: string): boolean;
  var
    i: integer;
  begin
    for i := 1 to argc - 1 do
      if argv[i] = optName then
        exit(True);
    exit(False);
  end;

  procedure CmdRequire(cmd: pCommand);
  var
    i:      integer;
    includeDev: boolean;
    change: boolean = False;
    packageName, versionConstraint: string;
    pkgs:   pLockFile;
    dep:    pResolvedDep;
  begin
    if argc < 2 then
    begin
      writeln('Please specify package(s) to require.');
      exit;
    end;

    includeDev := HasOption('--dev');

    pkgs := load_lock_file;

    for i := 2 to argc do
    begin
      // Ignore the --dev argument
      if argv[i] = '--dev' then Continue;

      if argv[i] <> '' then
      begin
        split_package_spec(argv[i], packageName, versionConstraint);
        if not package_already_registered(packageName) then
          if internal_require(pkgs, packageName, versionConstraint, dep, includeDev) then
          begin
            change := True;

            update_requirements_file(packageName, dep^.constraint, includeDev);
          end;
      end;
    end;

    if change then
    begin
      save_json(DEP_FILE, jsonReq);
      write_fpc_config(pkgs);
      save_lock_file(pkgs);
    end;

    free_lock_file(pkgs);
  end;

  procedure CmdRemove(cmd: pCommand);
  var
    i:    integer;
    removed: boolean = False;
    pkgs: pLockFile;
  begin
    if argc < 2 then
    begin
      writeln('Please specify package(s) to remove.');
      exit;
    end;

    pkgs := load_lock_file;

    for i := 2 to argc do
      if (argv[i] <> '') and internal_remove_package(argv[i], pkgs) then
        removed := True;

    if removed then
    begin
      save_json(DEP_FILE, jsonReq);
      write_fpc_config(pkgs);
      purge_vendor_folder(pkgs);
      save_lock_file(pkgs);
    end;

    free_lock_file(pkgs);
  end;

procedure CmdInstall(cmd: pCommand);
var
  includeDev: Boolean;
  lockFile: pLockFile;
  i: Integer;
  dep: pResolvedDep;
  path: string;
begin
  includeDev := HasOption('--dev');

  // Load lock file
  lockFile := load_lock_file;

  // Install all first-level dependencies (top-level in lock)
  for i := 0 to lockFile^.requires.Count - 1 do
  begin
    dep := pResolvedDep(lockFile^.requires[i]);

    // Skip dev dependencies if --dev not specified
    if dep^.dev and not includeDev then
      Continue;

    // Compute vendor path
    path := IncludeTrailingPathDelimiter(VENDOR_DIR) +
                StringReplace(dep^.Name, '/', PathDelim, [rfReplaceAll]);

    // Install via git clone or update
    git_clone_or_update(dep^.Name, path, dep^.version, dep^.constraint, dep^.commit);
  end;

  write_fpc_config(lockFile);

  // Free lock file and all package entries
  free_lock_file(lockFile);
end;

  procedure CmdUpdate(cmd: pCommand);

  function internal_update(var lockFile: pLockFile; packageName, versionConstraint: string; includeDev: boolean): boolean;
  var
    dep: pResolvedDep;
  begin
    Result := internal_require(lockFile, packageName, versionConstraint, dep, includeDev);
  end;

  var
    change: boolean;
    lockFile: pLockFile;
    requires, devRequires: TJSONObject;
    i: Integer;
    packageName, versionConstraint: String;
  begin
     //create empty lock file data structure
      New(lockFile);
      lockFile^.RootName := jsonReq.Get('name', '');
      lockFile^.RootVersion := jsonReq.Get('version', '');
      lockFile^.requires := TFPList.Create;

      // Process "require" section
      if jsonReq.Find('require') <> nil then
begin
      requires := jsonReq.Objects['require'];
      if Assigned(requires) then
      begin
        for i := 0 to requires.Count - 1 do
        begin
          packageName := requires.Names[i];
          versionConstraint := requires.Get(packageName, '');
          if internal_update(lockFile, packageName, versionConstraint, False) then
            change := True;
        end;
      end;
      end;

      // Process "require-dev" section
      if jsonReq.Find('require-dev') <> nil then
begin
      devRequires := jsonReq.Objects['require-dev'];
      if Assigned(devRequires) then
      begin
        for i := 0 to devRequires.Count - 1 do
        begin
          packageName := devRequires.Names[i];
          versionConstraint := devRequires.Get(packageName, '');
          if internal_update(lockFile, packageName, versionConstraint, True) then
            change := True;
        end;
      end;
      end;

    if change then
    begin
      save_json(DEP_FILE, jsonReq);
      write_fpc_config(lockFile);
      save_lock_file(lockFile);
    end;

    free_lock_file(lockFile);
  end;

  procedure CmdShow(cmd: pCommand);
  begin
    nova_list(HasOption('--tree'));
  end;

var
  cmdRec: pCommand;
  i:      integer;
begin
  Commands := TFPList.Create;

  // Register commands
  RegisterCommand('init', 'Initialize a new project interactively', @CmdInit);

  cmdRec := RegisterCommand('require', 'Add one or more packages as requirement',
    @CmdRequire);
  RegisterOption(cmdRec, '--dev', 'Include packages as development requirement');

  RegisterCommand('remove', 'Remove one or more packages', @CmdRemove);

  cmdRec := RegisterCommand('update',
    'Update dependency versions and regenerate the lockfile.', @CmdUpdate);
  RegisterOption(cmdRec, '--dev', 'Include as development requirement');

  cmdRec := RegisterCommand('install', 'Install all requirements and update lock file',
    @CmdInstall);
  RegisterOption(cmdRec, '--dev', 'Include packages as development requirement');

  cmdRec := RegisterCommand('show', 'Show installed packages', @CmdShow);
  RegisterOption(cmdRec, '--tree', 'Show dependency tree instead of flat list');

  // Check for global help
  for i := 1 to argc - 1 do  // skip argv[0] which is program name
    if (argv[i] = '-h') or (argv[i] = '--help') then
    begin
      print_usage;
      FreeCommands;
      halt(-1);
    end
    else
    if (argv[i] = '-v') or (argv[i] = '--version') then
    begin
      print_version;
      FreeCommands;
      halt(-1);
    end;

  if argc < 1 then
    print_usage;

  // Find the command
  cmdRec := nil;
  for i := 0 to Commands.Count - 1 do
    if pCommand(Commands[i])^.name = argv[1] then
    begin
      cmdRec := pCommand(Commands[i]);
      break;
    end;

  if cmdRec = nil then
  begin
    writeln('Unknown command: ', argv[1]);
    writeln;
    print_usage;
  end;

  // Load or create dependency file
  jsonReq := create_or_load_json(DEP_FILE);

  // Execute command
  cmdRec^.proc(cmdRec);

  jsonReq.Free;
  FreeCommands;

  writeln('done.');
end.
