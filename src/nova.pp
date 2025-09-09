program nova;

{$mode objfpc}{$H+}

uses
  {$IFDEF WINDOWS}Windows,{$ENDIF}
  SysUtils,
  Classes,
  fpjson,
  jsonparser,
  process;

const
  NOVA_VERSION = '1.0.0';
  VENDOR_DIR = 'vendor';
  LOCK_FILE = 'nova.lock';
  DEP_FILE = 'nova.json';
  BIN_DIR = 'bin';

type
  TVersion = record
    Major, Minor, Patch: integer;
    hash: string;
    Name: string;
  end;

  pPackage = ^TPackage;

  TPackage = record
    Name: string;           // e.g. "laravel/pint"
    constraint: string;     // e.g. "^1.24"
    version: TVersion;      // resolved version, e.g. "1.24.0"
    hash: string;           // commit hash after cloning
    includeDev: boolean;    // whether it’s a dev dependency
    installed: boolean;     // whether the package was installed already
  end;

var
  jsonReq: TJSONObject;
  includeDev: boolean = False;


  //  { ------------------ Helper Functions ------------------ }

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

  //  { ------------------ SemVer ------------------ }

  function parse_version(const S: string): TVersion;
  var
    Parts: TStringList;
    Clean: string;
  begin
    Result.Major := 0;
    Result.Minor := 0;
    Result.Patch := 0;

    Result.Name := S;

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
    if A.Major <> B.Major then Exit(A.Major - B.Major);
    if A.Minor <> B.Minor then Exit(A.Minor - B.Minor);
    Result := A.Patch - B.Patch;
  end;

  function matches_constraint(const Ver: TVersion; const Constraint: string): boolean;
  var
    Num: string;
    CVer: TVersion;
  begin
    Result := False;
    if Constraint = '' then
      Exit(True);

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

  //  { ------------------ Git Resolver ------------------ }

  function resolve_version(const Repo, Constraint: string): TVersion;
  var
    Tags: string;
    Lines: TStringList;
    I: integer;
    Candidate, Best: string;
    CandidateVer, BestVer: TVersion;
  begin
    Tags := run_and_capture('git', ['ls-remote', '--tags',
      'https://github.com/' + Repo + '.git']);
    Lines := TStringList.Create;
    Best := '';
    try
      Lines.Text := Tags;
      for I := 0 to Lines.Count - 1 do
      begin
        if Pos('refs/tags/', Lines[I]) > 0 then
        begin
          Candidate := Copy(Lines[I], Pos('refs/tags/', Lines[I]) + 10, MaxInt);
          CandidateVer := parse_version(Candidate);
          CandidateVer.hash := Trim(Copy(Lines[I], 1, Pos(#9, Lines[I]) - 1));
          if matches_constraint(CandidateVer, Constraint) then
          begin
            if (Best = '') or (compare_versions(CandidateVer, BestVer) > 0) then
            begin
              Best := Candidate;
              BestVer := CandidateVer;
            end;
          end;
        end;
      end;

      if Best <> '' then Result := BestVer
      else
        Result := parse_version(Constraint);
    finally
      Lines.Free;
    end;
  end;

  //  function VersionToStr(version: TVersion): string;
  //  begin
  //    Result := Format('%d.%d.%d', [version.Major, version.Minor, version.Patch]);
  //  end;


  procedure git_clone_or_update(const Repo, Path: string; const ver: TVersion);
  begin
    if DirectoryExists(Path) then
    begin
      writeln('Updating ', Repo, '...');
      // Fetch all updates
      run_and_capture('git', ['-C', Path, 'fetch', '--all']);
      // Checkout the exact commit hash
      run_and_capture('git', ['-C', Path, 'checkout', ver.hash]);
    end
    else
    begin
      writeln('Cloning ', Repo, '@', ver.Name, '...');
      // Clone the repository (full history required to checkout a commit hash)
      run_and_capture('git', ['clone', 'https://github.com/' + Repo + '.git', Path]);
      // Checkout the exact commit hash
      run_and_capture('git', ['-C', Path, 'checkout', ver.hash]);
    end;
  end;

  //  { ------------------ JSON Helpers ------------------ }

  procedure save_json(const FName: string; jData: TJSONObject);
  var
    FS: TFileStream;
    S: ansistring;
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

  //  { ------------------ Package Management ------------------ }

  function package_exists(const Section, Repo: string): boolean;
  var
    Obj: TJSONObject;
  begin
    Result := False;
    Obj := TJSONObject(jsonReq.FindPath(Section));
    if Obj <> nil then
      Result := Obj.IndexOfName(Repo) <> -1;
  end;

  //  //procedure RequirePackage(const Repo, Constraint: string; Dev: boolean = False);
  //  //var
  //  //  Version: TVersion;
  //  //  Commit, Path, FinalConstraint: string;
  //  //  RequireObj, DevObj: TJSONObject;
  //  //begin
  //  //  // --- Load dependency file ---

  //  //  if package_exists(jsonReq, 'require', Repo) or
  //  //    package_exists(jsonReq, 'require-dev', Repo) then
  //  //  begin
  //  //    writeln('Package "', Repo, '" is already present. Skipping.');
  //  //    exit;
  //  //  end;

  //  //  // --- Resolve version ---
  //  //  Version := resolve_version(Repo, Constraint);

  //  //  // --- Decide on constraint ---
  //  //  if Constraint <> '' then
  //  //    FinalConstraint := Constraint
  //  //  else
  //  //    // Default: caret constraint on Major.Minor
  //  //    FinalConstraint := Format('^%d.%d', [Version.Major, Version.Minor]);

  //  //  // --- Update nova.json ---
  //  //  if Dev then
  //  //  begin
  //  //    DevObj := TJSONObject(jsonReq.FindPath('require-dev'));
  //  //    if DevObj = nil then
  //  //    begin
  //  //      DevObj := TJSONObject.Create;
  //  //      jsonReq.Add('require-dev', DevObj);
  //  //    end;
  //  //    DevObj.Add(Repo, FinalConstraint);
  //  //  end
  //  //  else
  //  //  begin
  //  //    RequireObj := TJSONObject(jsonReq.FindPath('require'));
  //  //    if RequireObj = nil then
  //  //    begin
  //  //      RequireObj := TJSONObject.Create;
  //  //      jsonReq.Add('require', RequireObj);
  //  //    end;
  //  //    RequireObj.Add(Repo, FinalConstraint);
  //  //  end;

  //  //  save_json(DEP_FILE, jsonReq);

  //  //  writeln('Using version ', FinalConstraint, ' for ', repo);
  //  //end;

  //  procedure CopyFile(fFrom, fTo: string);
  //  var
  //    SourceF, DestF: TFileStream;
  //  begin
  //    SourceF := TFileStream.Create(fFrom, fmOpenRead);
  //    DestF := TFileStream.Create(fTo, fmCreate);
  //    DestF.CopyFrom(SourceF, SourceF.Size);
  //    SourceF.Free;
  //    DestF.Free;
  //  end;

  //  procedure GenerateFPCConfig(const ConfigFile: string; const VendorDir, BinDir: string);
  //  var
  //    LockData: TJSONObject;
  //    Package, PathVal, BinFile: string;
  //    Keys: TStringList;
  //    I: integer;
  //    FS: TFileStream;
  //    FPCLines: TStringList;
  //  begin
  //    FPCLines := TStringList.Create;
  //    Keys := TStringList.Create;
  //    try
  //      // Load nova.lock
  //      LockData := create_or_load_json(LOCK_FILE);

  //      // Load nova.json
  //      if not FileExists(DEP_FILE) then
  //        Exit;

  //      // Collect keys from require + require-dev
  //      //if jsonReq.FindPath('require') <> nil then
  //      //  Keys.AddStrings(TJSONObject(jsonReq.FindPath('require')).Names);
  //      //if jsonReq.FindPath('require-dev') <> nil then
  //      //  Keys.AddStrings(TJSONObject(jsonReq.FindPath('require-dev')).Names);

  //      for I := 0 to Keys.Count - 1 do
  //      begin
  //        Package := Keys[I];

  //        // Determine package path in vendor
  //        PathVal := VendorDir + PathDelim + StringReplace(Package, '/',
  //          PathDelim, [rfReplaceAll]);

  //        // Check for bin override
  //        if (jsonReq.FindPath('bin') <> nil) and
  //          (TJSONObject(jsonReq.FindPath('bin')).IndexOfName(Package) <> -1) then
  //        begin
  //          BinFile := TJSONObject(jsonReq.FindPath('bin')).Get(Package, '');
  //          if FileExists(PathVal + PathDelim + BinFile) then
  //          begin
  //            // Copy binary to bin folder
  //            ForceDirectories(BinDir);
  //            CopyFile(PathVal + PathDelim + BinFile, BinDir + PathDelim + BinFile);
  //            writeln('Installed binary "', BinFile, '" to bin folder.');
  //          end;
  //        end
  //        else
  //        begin
  //          // Add path to fpc.cfg
  //          FPCLines.Add('-Fu' + PathVal);
  //        end;
  //      end;

  //      // write fpc.cfg
  //      FS := TFileStream.Create(ConfigFile, fmCreate);
  //      try
  //        FPCLines.SaveToStream(FS);
  //      finally
  //        FS.Free;
  //      end;

  //      writeln('Generated ', ConfigFile, ' with ', FPCLines.Count, ' paths.');
  //    finally
  //      FPCLines.Free;
  //      Keys.Free;
  //      LockData.Free;
  //    end;
  //  end;

  //  procedure RemovePackage(const Repo: string);
  //  var
  //    LockDeps: TJSONObject;
  //    RequireObj, DevObj: TJSONObject;
  //    Path: string;
  //    Removed: boolean;
  //  begin
  //    Removed := False;

  //    // --- Update lock file ---
  //    LockDeps := create_or_load_json(LOCK_FILE);
  //    try
  //      if LockDeps.IndexOfName(Repo) <> -1 then
  //      begin
  //        LockDeps.Remove(LockDeps.Find(Repo));
  //        save_json(LOCK_FILE, LockDeps);
  //        writeln('Removed "', Repo, '" from lock file.');
  //        Removed := True;
  //      end;
  //    finally
  //      LockDeps.Free;
  //    end;

  //      RequireObj := TJSONObject(jsonReq.FindPath('require'));
  //      if Assigned(RequireObj) and (RequireObj.IndexOfName(Repo) <> -1) then
  //      begin
  //        RequireObj.Remove(RequireObj.Find(Repo));
  //        Removed := True;
  //      end;

  //      DevObj := TJSONObject(jsonReq.FindPath('require-dev'));
  //      if Assigned(DevObj) and (DevObj.IndexOfName(Repo) <> -1) then
  //      begin
  //        DevObj.Remove(DevObj.Find(Repo));
  //        Removed := True;
  //      end;

  //      if Removed then
  //      begin
  //        save_json(DEP_FILE, jsonReq);
  //        writeln('Removed "', Repo, '" from nova.json.');
  //      end;

  //    // --- Remove vendor folder ---
  //    Path := VENDOR_DIR + PathDelim + StringReplace(Repo, '/',
  //      PathDelim, [rfReplaceAll]);
  //    if DirectoryExists(Path) then
  //    begin
  //      {$IFDEF WINDOWS}
  //      run_and_capture('rmdir', ['/S','/Q',Path]);
  //      {$ELSE}
  //      run_and_capture('rm', ['-rf', Path]);
  //      {$ENDIF}
  //      writeln('Deleted vendor files for "', Repo, '".');
  //    end;

  //    if not Removed then
  //      writeln('Package "', Repo, '" was not found.')
  //    else
  //    begin
  //      GenerateFPCConfig('fpc.cfg', VENDOR_DIR, VENDOR_DIR + PathDelim + BIN_DIR);
  //      writeln('fpc.cfg generated');
  //    end;
  //  end;

  //  procedure SelfUpdate;
  //  var
  //    Repo, Path, NewExe, CurrentExe: string;
  //  begin
  //    Repo := 'daar/nova';
  //    Path := '.nova_bin';
  //    ForceDirectories(Path);

  //    if DirectoryExists(Path + PathDelim + 'src') then
  //    begin
  //      run_and_capture('git', ['-C', Path + PathDelim + 'src', 'fetch', '--all']);
  //      run_and_capture('git', ['-C', Path + PathDelim + 'src', 'reset',
  //        '--hard', 'origin/main']);
  //    end
  //    else
  //      run_and_capture('git', ['clone', 'https://github.com/' + Repo +
  //        '.git', Path + PathDelim + 'src']);

  //    {$IFDEF WINDOWS}
  //  run_and_capture('fpc', [Path + PathDelim + 'src' + PathDelim + 'nova.pas', '-o' + Path + PathDelim + 'nova_new.exe']);
  //  NewExe := Path + PathDelim + 'nova_new.exe';
  //  CurrentExe := ParamStr(0);
  //  run_and_capture('nova-updater.exe', [CurrentExe, NewExe]);
  //    {$ELSE}
  //    run_and_capture('fpc', [Path + PathDelim + 'src' + PathDelim +
  //      'nova.pas', '-o' + Path + PathDelim + 'nova_new']);
  //    NewExe := Path + PathDelim + 'nova_new';
  //    CurrentExe := ParamStr(0);
  //    if FileExists(CurrentExe + '.old') then DeleteFile(CurrentExe + '.old');
  //    RenameFile(CurrentExe, CurrentExe + '.old');
  //    RenameFile(NewExe, CurrentExe);
  //    {$ENDIF}
  //  end;

  //  // Load nova.json
  //  // Query repositories (e.g., GitHub) for best version
  //  // Add package to "require" or "require-dev"
  //  // Save updated nova.json
  //  function UpdateNovaJson(packageName: string; versionConstraint: string;
  //    includeDev: boolean): boolean;
  //  var
  //    Version: TVersion;
  //    FinalConstraint: string;
  //    jsonReq, jsonPkg: TJSONObject;
  //  begin
  //    // --- Load or create dependency file ---
  //    jsonReq := create_or_load_json(DEP_FILE);

  //    //skip if package is already found
  //    if package_exists(jsonReq, 'require', packageName) or
  //      package_exists(jsonReq, 'require-dev', packageName) then
  //    begin
  //      writeln('Package "', packageName, '" is already present. Skipping.');
  //      exit;
  //    end;

  //    //determine versionConstraint
  //    if versionConstraint <> '' then
  //      FinalConstraint := versionConstraint
  //    else
  //    begin
  //      //resolve version from packageName
  //      Version := resolve_version(packageName, versionConstraint);

  //      //default: caret constraint on Major.Minor
  //      FinalConstraint := Format('^%d.%d', [Version.Major, Version.Minor]);
  //    end;

  //    //update nova.json
  //    if includeDev then
  //    begin
  //      jsonPkg := TJSONObject(jsonReq.FindPath('require-dev'));
  //      if jsonPkg = nil then
  //      begin
  //        jsonPkg := TJSONObject.Create;
  //        jsonReq.Add('require-dev', jsonPkg);
  //      end;
  //    end
  //    else
  //    begin
  //      jsonPkg := TJSONObject(jsonReq.FindPath('require'));
  //      if jsonPkg = nil then
  //      begin
  //        jsonPkg := TJSONObject.Create;
  //        jsonReq.Add('require', jsonPkg);
  //      end;
  //    end;
  //    jsonPkg.Add(packageName, FinalConstraint);

  //    save_json(DEP_FILE, jsonReq);

  //    writeln('Using version ', FinalConstraint, ' for ', packageName);
  //  end;

  //  procedure CollectKeys(Obj: TJSONObject; var pkgs: TFPList; includeDev: boolean);
  //  var
  //    i: integer;
  //    package: pPackage;
  //  begin
  //    if Obj = nil then
  //      exit;

  //    for i := 0 to Obj.Count - 1 do
  //    begin
  //      New(package);
  //      package^.includeDev := includeDev;
  //      package^.Name := Obj.Names[i];
  //      package^.constraint := Obj.Items[i].AsString;

  //      pkgs.Add(package);
  //    end;
  //  end;

  //  // Run dependency solver
  //  // Check all constraints from nova.json
  //  // Ensure compatibility with existing packages
  //  // If conflicts, abort with error
  //  procedure ResolveDependencies(var packages: TFPList; includeDev: boolean);
  //  var
  //    Visited: TStringList;

  //    procedure ResolvePackage(const Repo, Constraint: string; includeDev: boolean);
  //    var
  //      Resolved, DepFile, DepPath: string;
  //      Version: TVersion;
  //      PackageJson, RequireObj, DevObj: TJSONObject;
  //      //Keys: TStringList;
  //      I: integer;
  //      SubRepo, SubConstraint: string;
  //    begin
  //      // Avoid infinite loops
  //      if Visited.IndexOf(Repo) <> -1 then Exit;
  //      Visited.Add(Repo);

  //      // Resolve version
  //      Version := resolve_version(Repo, Constraint);

  //      if not matches_constraint(Version, Constraint) then
  //      begin
  //        writeln('❌ Conflict: Package "', Repo,
  //          '" could not satisfy constraint "', Constraint, '".');
  //        Halt(1);
  //      end;

  //      writeln('✓ ', Repo, ' resolved to ', Resolved,
  //        ' (constraint ', Constraint, ')');

  //      // Path to vendor folder
  //      DepPath := VENDOR_DIR + PathDelim + StringReplace(Repo, '/',
  //        PathDelim, [rfReplaceAll]);
  //      DepFile := DepPath + PathDelim + 'nova.json';

  //      // If package not yet fetched, clone temporarily for metadata
  //      if not FileExists(DepFile) then
  //      begin
  //        writeln('Fetching metadata for ', Repo, '...');
  //        //GitCloneOrUpdate(Repo, Resolved, DepPath);
  //      end;

  //      // If package has no nova.json, stop here
  //      if not FileExists(DepFile) then Exit;

  //      // Load package nova.json
  //      PackageJson := create_or_load_json(DepFile);
  //      //Keys := TStringList.Create;
  //      try
  //        // Normal dependencies
  //        RequireObj := TJSONObject(PackageJson.FindPath('require'));
  //        //if Assigned(RequireObj) then
  //        //  CollectKeys(RequireObj, Keys);

  //        // Dev dependencies (only if we’re resolving dev)
  //        if includeDev and (PackageJson.FindPath('require-dev') <> nil) then
  //        begin
  //          DevObj := TJSONObject(PackageJson.FindPath('require-dev'));
  //          //if Assigned(DevObj) then
  //          //  CollectKeys(DevObj, Keys);
  //        end;

  //        // Resolve sub-dependencies recursively
  //        //for I := 0 to Keys.Count - 1 do
  //        //begin
  //        //  SubRepo := Keys[I];
  //        //  SubConstraint := '';
  //        //  if Assigned(RequireObj) and (RequireObj.IndexOfName(SubRepo) <> -1) then
  //        //    SubConstraint := RequireObj.Get(SubRepo, '');
  //        //  if (SubConstraint = '') and Assigned(DevObj) and
  //        //    (DevObj.IndexOfName(SubRepo) <> -1) then
  //        //    SubConstraint := DevObj.Get(SubRepo, '');

  //        //  ResolvePackage(SubRepo, SubConstraint, includeDev);
  //        //end;
  //      finally
  //        //Keys.Free;
  //        PackageJson.Free;
  //      end;
  //    end;

  //  var
  //    RootJson: TJSONObject;
  //    RequireObj, DevObj: TJSONObject;
  //    //Keys: TStringList;
  //    I: integer;
  //    Repo, Constraint: string;
  //  begin
  //    if not FileExists(DEP_FILE) then
  //    begin
  //      writeln('No ', DEP_FILE, ' found. Nothing to resolve.');
  //      Exit;
  //    end;

  //    RootJson := create_or_load_json(DEP_FILE);
  //    Visited := TStringList.Create;
  //    try
  //      // Collect require
  //      RequireObj := TJSONObject(RootJson.FindPath('require'));
  //      if RequireObj <> nil then
  //        CollectKeys(RequireObj, packages, False);

  //      // Collect require-dev (only if requested)
  //      if includeDev then
  //      begin
  //        DevObj := TJSONObject(RootJson.FindPath('require-dev'));
  //        if DevObj <> nil then
  //          CollectKeys(DevObj, packages, True);
  //      end;

  //      if packages.Count = 0 then
  //      begin
  //        writeln('No dependencies found in ', DEP_FILE, '.');
  //        halt(1);
  //      end;

  //      writeln('Resolving dependencies recursively...');

  //      for I := 0 to packages.Count - 1 do
  //      begin
  //        Repo := TPackage(packages[I]^).Name;
  //        Constraint := TPackage(packages[I]^).constraint;

  //        ResolvePackage(Repo, Constraint, includeDev);
  //      end;

  //      writeln('All dependencies resolved successfully.');
  //    finally
  //      RootJson.Free;
  //      Visited.Free;
  //    end;
  //  end;

  //  // write resolved versions into nova.lock
  //  procedure UpdateNovaLock(const Packages: TFPList; includeDev: boolean);
  //  var
  //    LockObj, DepObj: TJSONObject;
  //    i: integer;
  //  begin
  //    LockObj := TJSONObject.Create;
  //    try
  //      for i := 0 to Packages.Count - 1 do
  //      begin
  //        DepObj := TJSONObject.Create;
  //        //DepObj.Add('version', TPackage(Packages[i]^).Version);
  //        DepObj.Add('commit', TPackage(Packages[i]^).Commit);
  //        DepObj.Add('dev', TPackage(Packages[i]^).includeDev);

  //        LockObj.Add(TPackage(Packages[i]^).Name, DepObj);
  //      end;

  //      save_json(LOCK_FILE, LockObj);
  //    finally
  //      LockObj.Free;
  //    end;
  //  end;

  //procedure nova_require(const packageName, versionConstraint: string; includeDev: boolean); forward;

  //  // Compare lock file with vendor directory
  //  // Download missing/updated packages (cache → download if needed)
  //  // Extract into vendor/
  //  procedure nova_install_packages(packageFile, versionConstraint: string; includeDev: boolean);
  //  var
  //    Section: TJSONObject;
  //    i: integer;
  //    repo, constraint, pathVal: string;
  //    version: TVersion;

  //    procedure ProcessSection(Obj: TJSONObject);
  //    var
  //      j: integer;
  //      r, c, p, subPkgFile: string;
  //      v: TVersion;
  //    begin
  //      if Obj = nil then Exit;
  //      for j := 0 to Obj.Count - 1 do
  //      begin
  //        r := Obj.Names[j];
  //        c := Obj.Items[j].AsString;
  //        p := VENDOR_DIR + PathDelim + StringReplace(r, '/', PathDelim, [rfReplaceAll]);
  //        v := resolve_version(r, c);
  //        GitCloneOrUpdate(r, p, v);

  //        // Check if this package has its own nova.json
  //        subPkgFile := p + PathDelim + 'nova.json';
  //        if FileExists(subPkgFile) then
  //        begin
  //          writeln('Found nested nova.json in ', pathVal, ', installing dependencies...');
  //          nova_require(subPkgFile,  includeDev); // recursive call
  //        end;
  //      end;
  //    end;

  //  begin
  //      // Process "require" section
  //      ProcessSection(TJSONObject(jsonReq.FindPath('require')));
  //      // Process "require-dev" if requested
  //      if includeDev then
  //        ProcessSection(TJSONObject(jsonReq.FindPath('require-dev')));
  //  end;

  //  procedure RegenerateFPCcfg();
  //  begin
  //    // Rebuild vendor/autoload.php
  //    // Update PSR-4, PSR-0 mappings, etc.
  //  end;

  //  procedure RunLifecycleScripts();
  //  begin
  //    // Execute post-install-cmd, post-update-cmd, etc.
  //  end;

  //  procedure nova_require(const packageName, versionConstraint: string; includeDev: boolean);
  //  var
  //    packages: TFPList;
  //    i: integer;
  //  begin
  //    packages := TFPList.Create;

  //    UpdateNovaJson(packageName, versionConstraint, includeDev);
  //    //ResolveDependencies(packages, includeDev);
  //    //UpdateNovaLock(packages, includeDev);
  //    nova_install_packages(DEP_FILE, versionConstraint, includeDev);
  //    RegenerateFPCcfg();
  //    RunLifecycleScripts();

  //    for i := 0 to packages.Count - 1 do
  //      Dispose(pPackage(packages[i]));
  //    packages.Free;
  //  end;

  function default_package_name: string;
  var
    UserName, FolderName: string;
    Path: string;
  begin
    // --- Get username ---
    {$IFDEF WINDOWS}
    SetLength(UserName, 256);
    if GetEnvironmentVariable('USERNAME', PChar(UserName), Length(UserName)) > 0 then
      UserName := Trim(PChar(UserName));
    {$ELSE}
    UserName := GetEnvironmentVariable('USER');
    {$ENDIF}

    if UserName = '' then
      UserName := 'user';

    // --- Get current folder name ---
    Path := GetCurrentDir;
    FolderName := ExtractFileName(Path);

    if FolderName = '' then
      FolderName := 'project';

    // --- Combine ---
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



  procedure initialize_nova_package;
  var
    JsonObj: TJSONObject;
    PackageName, Version, License: string;
    Description: string;
    AuthorName: string;
  begin
    writeln('This command will guide you through creating you ', DEP_FILE, ' config.');
    writeln;

    Write('Package name (<vendor>/<name>) [', default_package_name, ']: ');
    ReadLn(PackageName);
    if PackageName = '' then
      PackageName := default_package_name;

    Write('Description []: ');
    ReadLn(Description);

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
      JsonObj.Add('description', Description);
      JsonObj.Add('require', TJSONObject.Create);
      JsonObj.Add('require-dev', TJSONObject.Create);
      JsonObj.Add('bin', TJSONArray.Create);

      save_json(DEP_FILE, JsonObj);
      writeln('Created ', DEP_FILE, ' with basic information.');
    finally
      JsonObj.Free;
    end;

    writeln('You can now run `nova require <vendor/package>` to add dependencies.');
  end;

  procedure print_usage;
  begin
    writeln('Nova v', NOVA_VERSION);
    writeln('Copyright (c) 2025 by Darius Blaszyk');
    writeln('Usage: nova <command> [options] [package[:version] ...]');
    writeln;

    writeln('Available commands:');
    writeln('  init                 Initialize a new project interactively');
    writeln('  require <packages>   Add one or more packages to nova.json');
    writeln('  remove <packages>    Remove one or more packages from nova.json and vendor');
    writeln('  install              Install all dependencies from nova.json and update nova.lock');
    writeln('  show                 Show installed packages and their versions');
    writeln('  tree                 Show installed packages as a dependency tree');
    writeln('  self-update          Update the nova executable to the latest version');
    writeln;

    writeln('Options:');
    writeln('  --dev                Include packages as development dependencies');
    writeln('  -h, --help           Display this help message');
    halt(1);
  end;


  procedure split_package_spec(const fullParam: string;
  var packageName, versionConstraint: string);
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

  procedure nova_require(const packageName, versionConstraint: string);
  var
    Version: TVersion;
    FinalConstraint: string;
    jsonPkg: TJSONObject;
  begin
    //skip if package is already found
    if package_exists('require', packageName) or
      package_exists('require-dev', packageName) then
    begin
      writeln('Package "', packageName, '" is already present. Skipping.');
      exit;
    end;

    //determine versionConstraint
    if versionConstraint <> '' then
      FinalConstraint := versionConstraint
    else
    begin
      //resolve version from packageName
      Version := resolve_version(packageName, versionConstraint);

      //default: caret constraint on Major.Minor
      FinalConstraint := Format('^%d.%d', [Version.Major, Version.Minor]);
    end;

    //update nova.json
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
    jsonPkg.Add(packageName, FinalConstraint);

    save_json(DEP_FILE, jsonReq);

    writeln('Using version ', FinalConstraint, ' for ', packageName);
  end;

  procedure read_lock_file(jsonLock: TJSONObject; var Packages: TFPList);
  var
    LockObj: TJSONObject;
    i: integer;
    pkg: PPackage;
  begin
    Packages.Clear;

    for i := 0 to jsonLock.Count - 1 do
    begin
      LockObj := TJSONObject(jsonLock.Items[i]);
      if LockObj = nil then Continue;

      New(pkg);
      pkg^.Name := jsonLock.Names[i];
      pkg^.Constraint := LockObj.Get('constraint', '');
      pkg^.Version := parse_version(LockObj.Get('version', '0.0.0'));
      pkg^.Hash := LockObj.Get('hash', '');
      pkg^.includeDev := LockObj.Get('dev', False);
      pkg^.Installed := False; // not yet installed during this run
      Packages.Add(pkg);
    end;
  end;

  procedure write_lock_file(jsonLock: TJSONObject; Packages: TFPList);
  var
    PkgObj: TJSONObject;
    i: integer;
    pkg: PPackage;
  begin
    jsonLock.Clear;

    for i := 0 to Packages.Count - 1 do
    begin
      pkg := PPackage(Packages[i]);

      PkgObj := TJSONObject.Create;
      PkgObj.Add('constraint', pkg^.Constraint);
      PkgObj.Add('version', pkg^.Version.Name);
      PkgObj.Add('hash', pkg^.Hash);
      PkgObj.Add('dev', pkg^.includeDev);

      jsonLock.Add(pkg^.Name, PkgObj);
    end;

    save_json(LOCK_FILE, jsonLock);
  end;

  procedure internal_install_packages(const fname: string; pkgs: TFPList);
  //procedure internal_install_packages(const fname: string; pkgs: TFPList; includeDev: boolean = False);
  var
    RequireObj, DevObj: TJSONObject;
    i: integer;
    repo, constraint, path: string;
    version: TVersion;
    pkg: PPackage;
    j: integer;
    found, compatible: boolean;
    SubNova: string;
  begin
    // --- process require
    RequireObj := TJSONObject(jsonReq.FindPath('require'));
    if RequireObj <> nil then
    begin
      for i := 0 to RequireObj.Count - 1 do
      begin
        repo := RequireObj.Names[i];
        constraint := RequireObj.Items[i].AsString;
        found := False;
        compatible := False;

        // Look in existing pkgs (lockfile list)
        for j := 0 to pkgs.Count - 1 do
        begin
          pkg := PPackage(pkgs.Items[j]);
          if (pkg^.Name = repo) then
          begin
            found := True;
            if matches_constraint(pkg^.Version, constraint) then
            begin
              compatible := True;
              if not pkg^.Installed then
              begin
                pkg^.Installed := True;
                // Recursively check subdependencies
                SubNova :=
                  VENDOR_DIR + PathDelim + StringReplace(repo,
                  '/', PathDelim, [rfReplaceAll]) + PathDelim + 'nova.json';
                if FileExists(SubNova) then
                  internal_install_packages(SubNova, pkgs);
              end;
            end;
            Break;
          end;
        end;

        if found and (not compatible) then
        begin
          writeln('Version conflict for package ', repo,
            ' with constraint ', constraint);
          Halt(1);
        end;

        if not found then
        begin
          // Resolve and install
          version := resolve_version(repo, constraint);
          path := VENDOR_DIR + PathDelim + StringReplace(repo,
            '/', PathDelim, [rfReplaceAll]);
          git_clone_or_update(repo, path, version);

          New(pkg);
          pkg^.Name := repo;
          pkg^.Constraint := constraint;
          pkg^.Version := version;
          pkg^.Hash := version.Hash;
          pkg^.includeDev := False;
          pkg^.Installed := True;
          pkgs.Add(pkg);

          // Recursively check subdependencies
          SubNova := path + PathDelim + 'nova.json';
          if FileExists(SubNova) then
            internal_install_packages(SubNova, pkgs);
        end;
      end;
    end;

    // --- process require-dev (only if includeDev = True)
    if includeDev then
    begin
      DevObj := TJSONObject(jsonReq.FindPath('require-dev'));
      if DevObj <> nil then
      begin
        for i := 0 to DevObj.Count - 1 do
        begin
          repo := DevObj.Names[i];
          constraint := DevObj.Items[i].AsString;
          found := False;
          compatible := False;

          for j := 0 to pkgs.Count - 1 do
          begin
            pkg := PPackage(pkgs.Items[j]);
            if (pkg^.Name = repo) then
            begin
              found := True;
              if matches_constraint(pkg^.Version, constraint) then
              begin
                compatible := True;
                if not pkg^.Installed then
                begin
                  pkg^.Installed := True;
                  SubNova :=
                    VENDOR_DIR + PathDelim + StringReplace(repo,
                    '/', PathDelim, [rfReplaceAll]) + PathDelim + 'nova.json';
                  if FileExists(SubNova) then
                    internal_install_packages(SubNova, pkgs);
                end;
              end;
              Break;
            end;
          end;

          if found and (not compatible) then
          begin
            writeln('Version conflict for dev package ', repo,
              ' with constraint ', constraint);
            Halt(1);
          end;

          if not found then
          begin
            version := resolve_version(repo, constraint);
            path := VENDOR_DIR + PathDelim + StringReplace(repo,
              '/', PathDelim, [rfReplaceAll]);
            git_clone_or_update(repo, path, version);

            New(pkg);
            pkg^.Name := repo;
            pkg^.Constraint := constraint;
            pkg^.Version := version;
            pkg^.Hash := version.Hash;
            pkg^.includeDev := True;
            pkg^.Installed := True;
            pkgs.Add(pkg);

            SubNova := path + PathDelim + 'nova.json';
            if FileExists(SubNova) then
              internal_install_packages(SubNova, pkgs);
          end;
        end;
      end;
    end;
  end;


  procedure nova_install_packages;
  var
    pkgs: TFPList;
    jsonLock: TJSONObject;
    i: integer;
  begin
    pkgs := TFPList.Create;
    jsonLock := create_or_load_json(LOCK_FILE);
    read_lock_file(jsonLock, pkgs);

    //run internal install package procedure recursively, start with base nova.json
    internal_install_packages(DEP_FILE, pkgs);
    //write_fpc_config(pkgs);

    write_lock_file(jsonLock, pkgs);

    jsonLock.Free;

    //free all packages within the list
    for i := 0 to pkgs.Count - 1 do
      Dispose(pPackage(pkgs[i]));
    pkgs.Free;
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

    if not FileExists(DepFile) then Exit;

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
    LockPkg: TJSONObject;
    i: integer;

    procedure print_section(Obj: TJSONObject; isDev: boolean);
    var
      j: integer;
    begin
      if Obj = nil then Exit;
      for j := 0 to Obj.Count - 1 do
      begin
        Repo := Obj.Names[j];
        Constraint := Obj.Items[j].AsString;

        LockPkg := TJSONObject(LockJson.FindPath(Repo));
        if LockPkg <> nil then
        begin
          Version := LockPkg.Get('version', '');
          Commit := '(' + LockPkg.Get('commit', '') + ')';
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
      Exit;
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

var
  Cmd: string;
  i: integer;
  isHelp: boolean = False;
  package, version: string;
begin
  for i := 1 to ParamCount do
    if (ParamStr(i) = '-h') or (ParamStr(i) = '--help') then
      isHelp := True;

  if (ParamCount < 1) or isHelp then
    print_usage;

  // --- Load or create dependency file ---
  jsonReq := create_or_load_json(DEP_FILE);

  Cmd := ParamStr(1);

  // Detect --dev anywhere in the args
  for i := 2 to ParamCount do
    if ParamStr(i) = '--dev' then
      includeDev := True;

  if Cmd = 'require' then
  begin
    if ParamCount < 2 then
      writeln('Please specify package(s) to require.')
    else
    begin
      for i := 2 to ParamCount do
      begin
        //ignore --dev
        if ParamStr(i) = '--dev' then
          Continue;

        split_package_spec(ParamStr(i), package, version);
        nova_require(package, version);
      end;

      nova_install_packages;
    end;
  end
  //  else if Cmd = 'remove' then
  //  begin
  //    if ParamCount < 2 then
  //      writeln('Please specify package(s) to remove.')
  //    else
  //    begin
  //      for i := 2 to ParamCount do
  //      begin
  //        //ignore --dev
  //        if ParamStr(i) = '--dev' then
  //          Continue;

  //        RemovePackage(ParamStr(i));
  //      end;
  //    end;
  //  end
  else if Cmd = 'init' then
    initialize_nova_package
  else if Cmd = 'install' then
    nova_install_packages
  else if Cmd = 'show' then
    nova_list(False)
  else if Cmd = 'tree' then
    nova_list(True)
  //  else if (Cmd = 'self-update') or (Cmd = 'selfupdate') then
  //    SelfUpdate
  else
  begin
    jsonReq.Free;
    writeln('Unknown command: ', Cmd);
    writeln;
    print_usage;
  end;

  jsonReq.Free;
  writeln('done.');
end.
