unit Nova.Command.Require;

{$mode ObjFPC}{$H+}

interface

uses
  Nova.Package,
  Nova.Command;

type
  { TRequireCommand }

  TRequireCommand = class(TBaseCommand)
  private
    FNovaPkg: TNovaPackage;
    FDevFlag: boolean;

    function ResolveAndInstall(const PackageName, VersionConstraint: string): boolean;
    function ClonePackage(const PackageName, TargetPath, Version: string): boolean;
    procedure ProcessSubDependencies(const PackagePath: string);
    procedure BuildProjectPackage(const PackagePath: string);
  public
    constructor Create; override;
    procedure Execute; override;
    function Name: string; override;
    function Description: string; override;
  end;

implementation

uses
  FPCConfigWriter,
  Nova.Utils,
  Nova.Git,
  GitCLI,
  Classes,
  SysUtils,
  Process,
  TermStyle;

{ TRequireCommand }

function TRequireCommand.ClonePackage(const PackageName, TargetPath, Version: string): boolean;
var
  Git: TGitCLI;
  GitResult: TGitResult;
  RepoURL: string;
begin
  Result := False;
  RepoURL := 'https://github.com/' + PackageName + '.git';

  // Create parent directories if needed
  ForceDirectories(ExtractFilePath(ExcludeTrailingPathDelimiter(TargetPath)));

  if DirectoryExists(TargetPath) then
  begin
    // Package already exists, update it
    info('Package "' + PackageName + '" already exists, updating...');
    Git := TGitCLI.Create(TargetPath);
    try
      GitResult := Git.Fetch('origin');
      if not GitResult.Success then
      begin
        error('Failed to fetch updates: ' + GitResult.StdErr);
        exit(False);
      end;

      GitResult := Git.FetchTags;
      if not GitResult.Success then
      begin
        error('Failed to fetch tags: ' + GitResult.StdErr);
        exit(False);
      end;

      // Checkout the specific version
      if Version <> '' then
      begin
        GitResult := Git.CheckoutTag(Version);
        if not GitResult.Success then
        begin
          // Try checking out as a branch
          GitResult := Git.Checkout(Version);
          if not GitResult.Success then
          begin
            error('Failed to checkout version ' + Version + ': ' + GitResult.StdErr);
            exit(False);
          end;
        end;
      end;

      Result := True;
    finally
      Git.Free;
    end;
  end
  else
  begin
    // Clone the repository
    writeln('  Cloning ', PackageName, '...');
    Git := TGitCLI.Create(GetCurrentDir);
    try
      GitResult := Git.Clone(RepoURL, TargetPath);
      if not GitResult.Success then
      begin
        error('Failed to clone repository: ' + GitResult.StdErr);
        exit(False);
      end;

      // Checkout the specific version if specified
      if Version <> '' then
      begin
        Git.Free;
        Git := TGitCLI.Create(TargetPath);

        GitResult := Git.FetchTags;
        GitResult := Git.CheckoutTag(Version);
        if not GitResult.Success then
        begin
          // Try checking out as a branch
          GitResult := Git.Checkout(Version);
          if not GitResult.Success then
            warning('Could not checkout version ' + Version + ', using default branch');
        end;
      end;

      Result := True;
    finally
      Git.Free;
    end;
  end;
end;

function TRequireCommand.ResolveAndInstall(const PackageName, VersionConstraint: string): boolean;
var
  Resolver: TNovaGitResolver;
  ResolvedVer: TVersion;
  TargetPath: string;
  SourceDirs: array of string;
  EmptyReqs: TRequiredArray;
begin
  Result := False;

  // Check if already resolved
  if FNovaPkg.FindResolved(PackageName).Name <> '' then
  begin
    info('Package "' + PackageName + '" is already installed.');
    exit(True);
  end;

  writeln('  Resolving ', PackageName, ' (', VersionConstraint, ')...');

  // Resolve the best matching version from GitHub tags
  Resolver := TNovaGitResolver.Create(GetCurrentDir);
  try
    try
      ResolvedVer := Resolver.ResolveVersion(PackageName, VersionConstraint);
      writeln('    -> Found version: ', ResolvedVer.name);
    except
      on E: Exception do
      begin
        error('Failed to resolve version: ' + E.Message);
        // Try to use constraint as-is (might be a branch name)
        ResolvedVer.name := VersionConstraint;
        ResolvedVer.hash := '';
      end;
    end;
  finally
    Resolver.Free;
  end;

  // Install to vendor directory
  TargetPath := IncludeTrailingPathDelimiter(VENDOR_DIR) +
    StringReplace(PackageName, '/', PathDelim, [rfReplaceAll]);

  if not ClonePackage(PackageName, TargetPath, ResolvedVer.name) then
    exit(False);

  // Add to required list
  if not FNovaPkg.PackageAlreadyRegistered(PackageName) then
    FNovaPkg.AddRequired(PackageName, VersionConstraint, FDevFlag);

  // Add to resolved list
  SetLength(SourceDirs, 1);
  SourceDirs[0] := 'src';
  SetLength(EmptyReqs, 0);
  FNovaPkg.AddResolved(PackageName, ResolvedVer.name, ResolvedVer.hash,
    FDevFlag, SourceDirs, EmptyReqs);

  // Process sub-dependencies
  ProcessSubDependencies(TargetPath);

  // Build project-type packages
  BuildProjectPackage(TargetPath);

  Result := True;
end;

procedure TRequireCommand.ProcessSubDependencies(const PackagePath: string);
var
  SubPkg: TNovaPackage;
  SubPkgFile: string;
  i: integer;
  Req: TRequired;
begin
  SubPkgFile := IncludeTrailingPathDelimiter(PackagePath) + DEP_FILE;

  if not FileExists(SubPkgFile) then
    exit;

  SubPkg := TNovaPackage.Create;
  try
    SubPkg.LoadFromFile(SubPkgFile);

    // Process each required dependency
    for i := 0 to SubPkg.RequiredCount - 1 do
    begin
      Req := SubPkg.RequiredAt(i);

      // Skip dev dependencies unless we're in dev mode
      if Req.Dev and (not FDevFlag) then
        continue;

      // Recursively install
      ResolveAndInstall(Req.Name, Req.Constraint);
    end;
  finally
    SubPkg.Free;
  end;
end;

procedure TRequireCommand.BuildProjectPackage(const PackagePath: string);
var
  SubPkg: TNovaPackage;
  SubPkgFile: string;
  i: integer;
  SourceFile, ExeName, BinDir, TargetBin: string;
  CompileOutput: string;
  CompileSuccess: boolean;
begin
  SubPkgFile := IncludeTrailingPathDelimiter(PackagePath) + DEP_FILE;

  if not FileExists(SubPkgFile) then
    exit;

  SubPkg := TNovaPackage.Create;
  try
    SubPkg.LoadFromFile(SubPkgFile);

    // Only build project-type packages
    if LowerCase(SubPkg.PackageType) <> 'project' then
      exit;

    // Get source files from the package
    if SubPkg.SourceCount = 0 then
    begin
      warning('Project package has no source files defined');
      exit;
    end;

    // Create vendor/bin directory
    BinDir := IncludeTrailingPathDelimiter(VENDOR_DIR) + 'bin';
    ForceDirectories(BinDir);

    // Build each source file
    for i := 0 to SubPkg.SourceCount - 1 do
    begin
      SourceFile := IncludeTrailingPathDelimiter(PackagePath) + SubPkg.SourceAt(i);

      if not FileExists(SourceFile) then
      begin
        warning('Source file not found: ' + SourceFile);
        continue;
      end;

      // Determine output executable name
      ExeName := ChangeFileExt(ExtractFileName(SourceFile), '');
      {$IFDEF WINDOWS}
      ExeName := ExeName + '.exe';
      {$ENDIF}
      TargetBin := IncludeTrailingPathDelimiter(BinDir) + ExeName;

      writeln('  Building ', SubPkg.Name, ' -> ', ExeName, '...');

      // Compile with fpc
      CompileSuccess := RunCommand('fpc', [
        '-Fu' + IncludeTrailingPathDelimiter(PackagePath) + 'src',
        '-o' + TargetBin,
        SourceFile
      ], CompileOutput);

      if CompileSuccess then
      begin
        writeln('    Built: vendor/bin/', ExeName);
        // Clean up object file
        DeleteFile(ChangeFileExt(TargetBin, '.o'));
      end
      else
      begin
        error('Failed to build ' + SourceFile);
        writeln(CompileOutput);
      end;
    end;
  finally
    SubPkg.Free;
  end;
end;

constructor TRequireCommand.Create;
begin
  inherited Create;
  AddOption('--dev', 'Include packages as development requirement');
end;

procedure TRequireCommand.Execute;
var
  i: integer;
  PackageName, VersionConstraint: string;
  InstalledCount: integer;
begin
  if ParamCount < 2 then
  begin
    error('No package specified.');
    writeln('Usage: nova require <package-name>[:<version>] [--dev]');
    writeln('Example: nova require daar/linkedlist:^1.0');
    Exit;
  end;

  FDevFlag := HasOption('--dev');

  // Load current nova.json
  FNovaPkg := TNovaPackage.Create;
  try
    if FileExists(DEP_FILE) then
      FNovaPkg.LoadFromFile(DEP_FILE)
    else
    begin
      warning('No ' + DEP_FILE + ' found. Run "nova init" first or create one.');
      writeln('Creating a minimal nova.json...');
    end;

    writeln;
    writeln('Installing packages...');
    if FDevFlag then
      writeln('  (marking as development dependencies)');
    writeln;

    InstalledCount := 0;

    // Process each package argument
    for i := 2 to ParamCount do
    begin
      // Ignore option arguments
      if Pos('--', ParamStr(i)) = 1 then
        continue;

      SplitPackageSpec(ParamStr(i), PackageName, VersionConstraint);

      if PackageName = '' then
        continue;

      // Default constraint if not specified
      if VersionConstraint = '' then
        VersionConstraint := '*';

      if ResolveAndInstall(PackageName, VersionConstraint) then
        Inc(InstalledCount);
    end;

    // Save changes
    FNovaPkg.SaveToFile(DEP_FILE);

    // Generate fpc.cfg
    TFPCConfigWriter.WriteConfig(FNovaPkg, FPC_FILE);

    writeln;
    if InstalledCount > 0 then
      success(IntToStr(InstalledCount) + ' package(s) installed successfully.')
    else
      info('No new packages were installed.');

  finally
    FNovaPkg.Free;
  end;
end;

function TRequireCommand.Name: string;
begin
  Result := 'require';
end;

function TRequireCommand.Description: string;
begin
  Result := 'Add one or more packages as requirement';
end;

end.
