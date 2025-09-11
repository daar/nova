program nova;

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
    Major, Minor, Patch: integer;
    hash: string;
    name: string;
  end;

  pPackage = ^TPackage;

  TPackage = record
    name: string;           // e.g. "laravel/pint"
    constraint: string;     // e.g. "^1.24"
    version: TVersion;      // resolved version, e.g. "1.24.0"
    hash: string;           // commit hash after cloning
    includeDev: boolean;    // whether it’s a dev dependency
    installed: boolean;     // whether the package was installed already
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
    I:     integer;
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
        if Pos('refs/tags/', Lines[I]) > 0 then
        begin
          Candidate := Copy(Lines[I], Pos('refs/tags/', Lines[I]) + 10, MaxInt);
          CandidateVer := parse_version(Candidate);
          CandidateVer.hash := Trim(Copy(Lines[I], 1, Pos(#9, Lines[I]) - 1));
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
      writeln('Cloning ', Repo, '@', ver.name, '...');
      // Clone the repository (full history required to checkout a commit hash)
      run_and_capture('git', ['clone', 'https://github.com/' + Repo + '.git', Path]);
      // Checkout the exact commit hash
      run_and_capture('git', ['-C', Path, 'checkout', ver.hash]);
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

  function package_exists(const Section, Repo: string): boolean;
  var
    Obj: TJSONObject;
  begin
    Result := False;
    Obj := TJSONObject(jsonReq.FindPath(Section));
    if Obj <> nil then
      Result := Obj.IndexOfName(Repo) <> -1;
  end;

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

  procedure write_fpc_config(packages: TFPList);
  var
    I:   integer;
    pkg: pPackage;
    PathVal: string;
    FPCLines: TStringList;
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

      // Include the base fpc.cfg if it exists
      if (BaseConfig <> '') and FileExists(BaseConfig) then
        FPCLines.Add('# Include system/base FPC configuration')
      else
        BaseConfig := '';

      if BaseConfig <> '' then
        FPCLines.Add('#include ' + BaseConfig);

      FPCLines.Add('');
      FPCLines.Add('# Vendor package search paths');

      // Add all package paths
      for I := 0 to packages.Count - 1 do
      begin
        pkg := pPackage(packages[I]);
        if pkg^.installed then
        begin
          PathVal := IncludeTrailingPathDelimiter(VENDOR_DIR) +
            StringReplace(pkg^.name, '/', PathDelim, [rfReplaceAll]);
          FPCLines.Add('-Fu ' + PathVal);
        end;
      end;

      // Save the generated config
      FPCLines.SaveToFile(FPC_CONFIG);
      writeln('Generated ', FPC_CONFIG);
    finally
      FPCLines.Free;
    end;
  end;

  procedure read_lock_file(jsonLock: TJSONObject; var Packages: TFPList);
  var
    LockObj: TJSONObject;
    i:   integer;
    pkg: pPackage;
  begin
    Packages.Clear;

    for i := 0 to jsonLock.Count - 1 do
    begin
      LockObj := TJSONObject(jsonLock.Items[i]);
      if LockObj = nil then Continue;

      New(pkg);
      pkg^.name := jsonLock.Names[i];
      pkg^.Constraint := LockObj.Get('constraint', '');
      pkg^.Version := parse_version(LockObj.Get('version', '0.0.0'));
      pkg^.Hash := LockObj.Get('hash', '');
      pkg^.includeDev := LockObj.Get('dev', False);
      pkg^.Installed := False; // Not yet installed during this run
      Packages.Add(pkg);
    end;
  end;

  procedure write_lock_file(jsonLock: TJSONObject; Packages: TFPList);
  var
    PkgObj: TJSONObject;
    i:      integer;
    pkg:    pPackage;
  begin
    jsonLock.Clear;

    for i := 0 to Packages.Count - 1 do
    begin
      pkg := pPackage(Packages[i]);

      if pkg^.installed then
      begin
        PkgObj := TJSONObject.Create;
        PkgObj.Add('constraint', pkg^.Constraint);
        PkgObj.Add('version', pkg^.Version.name);
        PkgObj.Add('hash', pkg^.Hash);
        PkgObj.Add('dev', pkg^.includeDev);

        jsonLock.Add(pkg^.name, PkgObj);
      end;
    end;

    save_json(LOCK_FILE, jsonLock);
  end;

  function internal_remove_package(const Repo: string): boolean;
  var
    removed: boolean = False;
    RequireObj, DevObj: TJSONObject;
  begin
    RequireObj := TJSONObject(jsonReq.FindPath('require'));
    if Assigned(RequireObj) and (RequireObj.IndexOfName(Repo) <> -1) then
    begin
      RequireObj.Remove(RequireObj.Find(Repo));
      removed := True;
    end;

    DevObj := TJSONObject(jsonReq.FindPath('require-dev'));
    if Assigned(DevObj) and (DevObj.IndexOfName(Repo) <> -1) then
    begin
      DevObj.Remove(DevObj.Find(Repo));
      removed := True;
    end;

    if removed then
      writeln('Removed "', Repo, '" from ', DEP_FILE)
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

    writeln('You can now run `nova require <vendor/package>` to add dependencies.');
  end;

  procedure print_version;
  begin
    writeln('nova v', NOVA_VERSION);
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

  function nova_require(const packageName, versionConstraint: string;
  const includeDev: boolean): boolean;
  var
    Version: TVersion;
    FinalConstraint: string;
    jsonPkg: TJSONObject;
  begin
    // Skip if package is already found
    if package_exists('require', packageName) or
      package_exists('require-dev', packageName) then
    begin
      writeln('Package "', packageName, '" is already present. Skipping.');
      exit(False);
    end;

    // Determine versionConstraint
    if versionConstraint <> '' then
      FinalConstraint := versionConstraint
    else
    begin
      // Resolve version from packageName
      Version := resolve_version(packageName, versionConstraint);

      // Default: caret constraint on Major.Minor
      FinalConstraint := Format('^%d.%d', [Version.Major, Version.Minor]);
    end;

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
    jsonPkg.Add(packageName, FinalConstraint);

    writeln('Using version ', FinalConstraint, ' for ', packageName);
    exit(True);
  end;

  procedure internal_install_packages(const fname: string; pkgs: TFPList;
  const includeDev: boolean);
  var
    RequireObj, DevObj, jsonData: TJSONObject;
    i:   integer;
    repo, constraint, path: string;
    version: TVersion;
    pkg: pPackage;
    j:   integer;
    found, compatible: boolean;
    SubNova: string;
  begin
    jsonData := create_or_load_json(fname);

    // process require
    RequireObj := TJSONObject(jsonData.FindPath('require'));
    if RequireObj <> nil then
      for i := 0 to RequireObj.Count - 1 do
      begin
        repo := RequireObj.Names[i];
        constraint := RequireObj.Items[i].AsString;
        found := False;
        compatible := False;

        // Look in existing pkgs (lockfile list)
        for j := 0 to pkgs.Count - 1 do
        begin
          pkg := pPackage(pkgs.Items[j]);
          if (pkg^.name = repo) then
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
                  '/', PathDelim, [rfReplaceAll]) + PathDelim + DEP_FILE;
                if FileExists(SubNova) then
                  internal_install_packages(SubNova, pkgs, includeDev);
              end;
            end;
            break;
          end;
        end;

        if found and (not compatible) then
        begin
          writeln('Version conflict for package ', repo,
            ' with constraint ', constraint);
          exit;
        end;

        if not found then
        begin
          // Resolve and install
          version := resolve_version(repo, constraint);
          path := VENDOR_DIR + PathDelim + StringReplace(repo,
            '/', PathDelim, [rfReplaceAll]);
          git_clone_or_update(repo, path, version);

          New(pkg);
          pkg^.name := repo;
          pkg^.Constraint := constraint;
          pkg^.Version := version;
          pkg^.Hash := version.Hash;
          pkg^.includeDev := False;
          pkg^.Installed := True;
          pkgs.Add(pkg);

          // Recursively check subdependencies
          SubNova := path + PathDelim + DEP_FILE;
          if FileExists(SubNova) then
            internal_install_packages(SubNova, pkgs, includeDev);
        end;
      end;

    // Process require-dev (only if includeDev = True)
    if includeDev then
    begin
      DevObj := TJSONObject(jsonData.FindPath('require-dev'));
      if DevObj <> nil then
        for i := 0 to DevObj.Count - 1 do
        begin
          repo := DevObj.Names[i];
          constraint := DevObj.Items[i].AsString;
          found := False;
          compatible := False;

          for j := 0 to pkgs.Count - 1 do
          begin
            pkg := pPackage(pkgs.Items[j]);
            if (pkg^.name = repo) then
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
                    '/', PathDelim, [rfReplaceAll]) + PathDelim + DEP_FILE;
                  if FileExists(SubNova) then
                    internal_install_packages(SubNova, pkgs, includeDev);
                end;
              end;
              break;
            end;
          end;

          if found and (not compatible) then
          begin
            writeln('Version conflict for dev package ', repo,
              ' with constraint ', constraint);
            exit;
          end;

          if not found then
          begin
            version := resolve_version(repo, constraint);
            path := VENDOR_DIR + PathDelim + StringReplace(repo,
              '/', PathDelim, [rfReplaceAll]);
            git_clone_or_update(repo, path, version);

            New(pkg);
            pkg^.name := repo;
            pkg^.Constraint := constraint;
            pkg^.Version := version;
            pkg^.Hash := version.Hash;
            pkg^.includeDev := True;
            pkg^.Installed := True;
            pkgs.Add(pkg);

            SubNova := path + PathDelim + DEP_FILE;
            if FileExists(SubNova) then
              internal_install_packages(SubNova, pkgs, includeDev);
          end;
        end;
    end;

    jsonData.Free;
  end;

  procedure purge_vendor_folder(pkgs: TFPList);
  // Delete parent folders up to VENDOR_DIR if they are empty
    procedure purge_empty_parent(Dir: string);
    var
      sr:      TSearchRec;
      parent:  string;
      isEmpty: boolean;
    begin
      parent := ExtractFileDir(Dir); // Go one level up (package_vendor)

      // Stop if we are at vendor root or above
      if (parent = '') or (ExpandFileName(parent) = ExpandFileName(VENDOR_DIR)) then
        exit;

      // Check if parent is empty
      isEmpty := True;
      if FindFirst(parent + PathDelim + '*', faAnyFile, sr) = 0 then
      begin
        repeat
          if (sr.name <> '.') and (sr.name <> '..') then
          begin
            isEmpty := False;
            break;
          end;
        until FindNext(sr) <> 0;
        FindClose(sr);
      end;

      // Remove parent if empty
      if isEmpty then
        RemoveDir(parent);
    end;

  var
    Repo, Path: string;
    i:   integer;
    pkg: pPackage;
  begin
    // Purge vendor folder from all orphaned packages
    for i := 0 to pkgs.Count - 1 do
    begin
      pkg := pPackage(pkgs[i]);

      if not pkg^.installed then
      begin
        repo := pkg^.name;

        Path := VENDOR_DIR + PathDelim + StringReplace(Repo, '/',
          PathDelim, [rfReplaceAll]);

        if DirectoryExists(Path) then
        begin
          {$IFDEF WINDOWS}
        run_and_capture('rmdir', ['/S','/Q',Path]);
          {$ELSE}
          run_and_capture('rm', ['-rf', Path]);
          {$ENDIF}
          writeln('Deleted vendor files for "', Repo, '".');

          // try to delete empty parents up to VENDOR_DIR
          purge_empty_parent(Path);
        end;
      end;
    end;
  end;

  procedure nova_install_packages(const includeDev: boolean);
  var
    pkgs: TFPList;
    jsonLock: TJSONObject;
    i: integer;
  begin
    pkgs := TFPList.Create;
    jsonLock := create_or_load_json(LOCK_FILE);
    read_lock_file(jsonLock, pkgs);

    // Run internal install package procedure recursively, start with base nova.json
    internal_install_packages(DEP_FILE, pkgs, includeDev);

    write_fpc_config(pkgs);

    purge_vendor_folder(pkgs);

    write_lock_file(jsonLock, pkgs);

    jsonLock.Free;

    // Free all packages within the list
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

  function HasOption(cmd: pCommand; const optName: string): boolean;
  var
    i:   integer;
    opt: pOption;
  begin
    for i := 0 to pCommand(cmd)^.options.Count - 1 do
    begin
      opt := pOption(pCommand(cmd)^.options[i]);
      if opt^.name = optName then
        exit(True);
    end;
    exit(False);
  end;

  procedure CmdRequire(cmd: pCommand);
  var
    i:     integer;
    package, version: string;
    includeDev: boolean;
    added: boolean = False;
  begin
    if argc < 2 then
    begin
      writeln('Please specify package(s) to require.');
      exit;
    end;

    includeDev := HasOption(cmd, '--dev');

    for i := 2 to argc do
    begin
      // Ignore the --dev argument
      if argv[i] = '--dev' then Continue;

      if argv[i] <> '' then
      begin
        split_package_spec(argv[i], package, version);

        if nova_require(package, version, includeDev) then
          added := True;
      end;
    end;

    if added then
    begin
      save_json(DEP_FILE, jsonReq);
      writeln('Run `nova install [--dev]` to install dependencies and complete setup.');
    end;
  end;

  procedure CmdRemove(cmd: pCommand);
  var
    i: integer;
    removed: boolean;
  begin
    if argc < 2 then
      writeln('Please specify package(s) to remove.')
    else
      for i := 2 to argc do
        if (argv[i] <> '') and internal_remove_package(argv[i]) then
            removed := True;

    if removed then
    begin
      save_json(DEP_FILE, jsonReq);
      writeln('Run `nova install [--dev]` to update and clean up dependencies.');
    end;
  end;

  procedure CmdInstall(cmd: pCommand);
  begin
    //nova_install_packages;
  end;

  procedure CmdShow(cmd: pCommand);
  var
    tree: boolean;
  begin
    tree := HasOption(cmd, '--tree');
    nova_list(tree);
  end;

var
  cmdRec: pCommand;
  i:      integer;
  arg:    string;
begin
  Commands := TFPList.Create;

  // Register commands
  RegisterCommand('init', 'Initialize a new project interactively', @CmdInit);

  cmdRec := RegisterCommand('require', 'Add one or more packages as dependencies',
    @CmdRequire);
  RegisterOption(cmdRec, '--dev', 'Include packages as development dependencies');

  RegisterCommand('remove', 'Remove one or more packages', @CmdRemove);
  RegisterCommand('install', 'Install all dependencies and update lock file',
    @CmdInstall);

  cmdRec := RegisterCommand('show', 'Show installed packages', @CmdShow);
  RegisterOption(cmdRec, '--tree', 'Show dependency tree instead of flat list');

  // Check for global help
  for i := 1 to argc - 1 do  // skip argv[0] which is program name
  begin
    arg := string(argv[i]);   // convert PChar to Pascal string

    if (arg = '-h') or (arg = '--help') then
    begin
      print_usage;
      FreeCommands;
      halt(-1);
    end
    else
    if (arg = '-v') or (arg = '--version') then
    begin
      print_version;
      FreeCommands;
      halt(-1);
    end;
  end;

  if argc < 1 then
    print_usage;

  // Find the command
  arg := string(argv[1]);
  cmdRec := nil;
  for i := 0 to Commands.Count - 1 do
    if pCommand(Commands[i])^.name = arg then
    begin
      cmdRec := pCommand(Commands[i]);
      break;
    end;

  if cmdRec = nil then
  begin
    writeln('Unknown command: ', arg);
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
