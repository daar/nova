unit Nova.Command;

{$mode objfpc}{$H+}

interface

uses
  Classes,
  SysUtils;

type
  { ICommand interface }
  ICommand = interface
    ['{C8B1590B-7E2E-4D8A-B7C3-F05B8F3C07F2}']
    procedure Execute;
    function name: string;
    function Description: string;
    procedure AddOption(const OptName, OptDesc: string);
    function OptionCount: integer;
    function Option(Index: integer): TObject;
  end;

  { TOption class }
  TOption = class
  public
    name: string;
    Description: string;
    constructor Create(const AName, ADescription: string);
  end;

  { TBaseCommand class }
  TBaseCommand = class(TInterfacedObject, ICommand)
  private
    FOptions: TList; // store TOption objects
  public
    constructor Create; virtual;
    destructor Destroy; override;

    // ICommand
    procedure Execute; virtual; abstract;
    function name: string; virtual; abstract;
    function Description: string; virtual; abstract;

    procedure AddOption(const OptName, OptDesc: string);
    function HasOption(const OptionName: string): Boolean;

    function OptionCount: integer;
    function Option(Index: integer): TObject;
  end;

  { Command Implementations }

  TRemoveCommand = class(TBaseCommand)
  public
    procedure Execute; override;
    function name: string; override;
    function Description: string; override;
  end;

  TUpdateCommand = class(TBaseCommand)
  public
    constructor Create; override;
    procedure Execute; override;
    function name: string; override;
    function Description: string; override;
  end;

  TInstallCommand = class(TBaseCommand)
  public
    constructor Create; override;
    procedure Execute; override;
    function name: string; override;
    function Description: string; override;
  end;

implementation

uses
  fpjson,
  jsonscanner,
  process,
  TermStyle,
  Nova.Package,
  Nova.Utils,
  Nova.Git,
  GitCLI,
  FPCConfigWriter;

{ Helper procedure to build project-type packages }
procedure BuildProjectPackage(const PackagePath: string);
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

  { TOption }

constructor TOption.Create(const AName, ADescription: string);
begin
  name := AName;
  Description := ADescription;
end;

{ TBaseCommand }

constructor TBaseCommand.Create;
begin
  inherited Create;
  FOptions := TList.Create;
end;

destructor TBaseCommand.Destroy;
var
  i: integer;
begin
  for i := 0 to FOptions.Count - 1 do
    TObject(FOptions[i]).Free;
  FOptions.Free;
  inherited Destroy;
end;

procedure TBaseCommand.AddOption(const OptName, OptDesc: string);
begin
  FOptions.Add(TOption.Create(OptName, OptDesc));
end;

function TBaseCommand.HasOption(const OptionName: string): Boolean;
var
  i: Integer;
  CleanOpt: string;
begin
  Result := False;
  CleanOpt := LowerCase(OptionName);

  for i := 0 to ParamCount do
  begin
    if (LowerCase(ParamStr(i)) = CleanOpt) or
       (Pos(CleanOpt + '=', LowerCase(ParamStr(i))) = 1) then
      exit(true);
  end;
  exit(false);
end;

function TBaseCommand.OptionCount: integer;
begin
  Result := FOptions.Count;
end;

function TBaseCommand.Option(Index: integer): TObject;
begin
  //Result := FOptions[Index];
end;

{ TInstallCommand }

constructor TInstallCommand.Create;
begin
  inherited Create;
  AddOption('--dev', 'Include development dependencies');
end;

procedure TInstallCommand.Execute;
var
  NovaPkg: TNovaPackage;
  i: integer;
  Res: TResolved;
  TargetPath, RepoURL, TmpOutput: string;
  Git: TGitCLI;
  GitResult: TGitResult;
  InstalledCount: integer;
begin
  if not FileExists('nova.json') then
  begin
    error('No nova.json found. Run "nova init" first.');
    exit;
  end;

  NovaPkg := TNovaPackage.Create;
  try
    NovaPkg.LoadFromFile('nova.json');

    if NovaPkg.ResolvedCount = 0 then
    begin
      info('No packages to install. Use "nova require <package>" to add dependencies.');
      exit;
    end;

    writeln('Installing ', NovaPkg.ResolvedCount, ' package(s)...');
    writeln;

    InstalledCount := 0;

    for i := 0 to NovaPkg.ResolvedCount - 1 do
    begin
      Res := NovaPkg.ResolvedAt(i);

      // Skip dev dependencies unless --dev flag is set
      if Res.Dev and (not HasOption('--dev')) then
        continue;

      TargetPath := IncludeTrailingPathDelimiter('vendor') +
        StringReplace(Res.Name, '/', PathDelim, [rfReplaceAll]);

      if DirectoryExists(TargetPath) then
      begin
        // Verify the install is valid (has a .git directory or nova.json)
        if DirectoryExists(IncludeTrailingPathDelimiter(TargetPath) + '.git') then
        begin
          writeln('  [OK] ', Res.Name, ' (', Res.Version, ')');
          // Build project packages even if already installed
          BuildProjectPackage(TargetPath);
          Inc(InstalledCount);
          continue;
        end
        else
        begin
          // Directory exists but is corrupt/incomplete — remove and reinstall
          writeln('  Reinstalling ', Res.Name, ' (incomplete install detected)...');
          RunCommand('rm', ['-rf', TargetPath], TmpOutput);
        end;
      end;

      writeln('  Installing ', Res.Name, ' (', Res.Version, ')...');

      RepoURL := 'https://github.com/' + Res.Name + '.git';
      ForceDirectories(ExtractFilePath(ExcludeTrailingPathDelimiter(TargetPath)));

      Git := TGitCLI.Create(GetCurrentDir);
      try
        GitResult := Git.Clone(RepoURL, TargetPath);
        if not GitResult.Success then
        begin
          error('Failed to clone ' + Res.Name + ': ' + GitResult.StdErr);
          continue;
        end;

        // Checkout specific version
        if Res.Version <> '' then
        begin
          Git.Free;
          Git := TGitCLI.Create(TargetPath);
          Git.FetchTags;
          GitResult := Git.CheckoutTag(Res.Version);
          if not GitResult.Success then
            Git.Checkout(Res.Version);
        end;

        Inc(InstalledCount);

        // Build project-type packages
        BuildProjectPackage(TargetPath);
      finally
        Git.Free;
      end;
    end;

    // Regenerate fpc.cfg
    TFPCConfigWriter.WriteConfig(NovaPkg, 'fpc.cfg');

    writeln;
    success(IntToStr(InstalledCount) + ' package(s) installed.');

  finally
    NovaPkg.Free;
  end;
end;

function TInstallCommand.name: string;
begin
  Result := 'install';
end;

function TInstallCommand.Description: string;
begin
  Result := 'Install all packages from nova.json';
end;

{ TUpdateCommand }

constructor TUpdateCommand.Create;
begin
  inherited Create;
  AddOption('--dev', 'Include development dependencies');
end;

procedure TUpdateCommand.Execute;
var
  NovaPkg: TNovaPackage;
  i: integer;
  Req: TRequired;
  Res: TResolved;
  TargetPath: string;
  Git: TGitCLI;
  GitResult: TGitResult;
  Resolver: TNovaGitResolver;
  NewVer: TVersion;
  UpdatedCount: integer;
  SourceDirs: array of string;
  EmptyReqs: TRequiredArray;
begin
  if not FileExists('nova.json') then
  begin
    error('No nova.json found. Run "nova init" first.');
    exit;
  end;

  NovaPkg := TNovaPackage.Create;
  try
    NovaPkg.LoadFromFile('nova.json');

    if NovaPkg.RequiredCount = 0 then
    begin
      info('No packages to update.');
      exit;
    end;

    writeln('Updating packages...');
    writeln;

    UpdatedCount := 0;

    // Clear resolved list and rebuild
    // (We'll rebuild by re-resolving all requirements)

    for i := 0 to NovaPkg.RequiredCount - 1 do
    begin
      Req := NovaPkg.RequiredAt(i);

      // Skip dev dependencies unless --dev flag is set
      if Req.Dev and (not HasOption('--dev')) then
        continue;

      writeln('  Checking ', Req.Name, '...');

      TargetPath := IncludeTrailingPathDelimiter('vendor') +
        StringReplace(Req.Name, '/', PathDelim, [rfReplaceAll]);

      // Resolve latest matching version
      Resolver := TNovaGitResolver.Create(GetCurrentDir);
      try
        try
          NewVer := Resolver.ResolveVersion(Req.Name, Req.Constraint);
        except
          on E: Exception do
          begin
            warning('Could not resolve ' + Req.Name + ': ' + E.Message);
            continue;
          end;
        end;
      finally
        Resolver.Free;
      end;

      // Check if we need to update
      Res := NovaPkg.FindResolved(Req.Name);
      if (Res.Name <> '') and (Res.Version = NewVer.name) then
      begin
        writeln('    Already at latest: ', NewVer.name);
        continue;
      end;

      writeln('    Updating to ', NewVer.name, '...');

      if DirectoryExists(TargetPath) then
      begin
        Git := TGitCLI.Create(TargetPath);
        try
          Git.Fetch('origin');
          Git.FetchTags;
          GitResult := Git.CheckoutTag(NewVer.name);
          if not GitResult.Success then
            Git.Checkout(NewVer.name);
        finally
          Git.Free;
        end;
      end;

      Inc(UpdatedCount);
    end;

    // Save changes
    NovaPkg.SaveToFile('nova.json');
    TFPCConfigWriter.WriteConfig(NovaPkg, 'fpc.cfg');

    writeln;
    if UpdatedCount > 0 then
      success(IntToStr(UpdatedCount) + ' package(s) updated.')
    else
      info('All packages are up to date.');

  finally
    NovaPkg.Free;
  end;
end;

function TUpdateCommand.name: string;
begin
  Result := 'update';
end;

function TUpdateCommand.Description: string;
begin
  Result := 'Update all packages to latest matching versions';
end;

{ TRemoveCommand }

procedure TRemoveCommand.Execute;
var
  NovaPkg, SubPkg: TNovaPackage;
  PackageName: string;
  TargetPath, SubPkgFile: string;
  BinPath, ExeName: string;
  j: integer;
begin
  if ParamCount < 2 then
  begin
    error('No package specified.');
    writeln('Usage: nova remove <package-name>');
    exit;
  end;

  PackageName := ParamStr(2);

  if not FileExists('nova.json') then
  begin
    error('No nova.json found.');
    exit;
  end;

  NovaPkg := TNovaPackage.Create;
  try
    NovaPkg.LoadFromFile('nova.json');

    if not NovaPkg.PackageAlreadyRegistered(PackageName) then
    begin
      error('Package "' + PackageName + '" is not installed.');
      exit;
    end;

    writeln('Removing ', PackageName, '...');

    // Remove from vendor directory
    TargetPath := IncludeTrailingPathDelimiter('vendor') +
      StringReplace(PackageName, '/', PathDelim, [rfReplaceAll]);

    // Before removing, check if it's a project type and remove binaries
    SubPkgFile := IncludeTrailingPathDelimiter(TargetPath) + DEP_FILE;
    if FileExists(SubPkgFile) then
    begin
      SubPkg := TNovaPackage.Create;
      try
        SubPkg.LoadFromFile(SubPkgFile);

        // Remove binaries for project-type packages
        if LowerCase(SubPkg.PackageType) = 'project' then
        begin
          for j := 0 to SubPkg.SourceCount - 1 do
          begin
            ExeName := ChangeFileExt(ExtractFileName(SubPkg.SourceAt(j)), '');
            {$IFDEF WINDOWS}
            ExeName := ExeName + '.exe';
            {$ENDIF}
            BinPath := IncludeTrailingPathDelimiter(VENDOR_DIR) + 'bin' + PathDelim + ExeName;

            if FileExists(BinPath) then
            begin
              DeleteFile(BinPath);
              writeln('  Removed vendor/bin/', ExeName);
            end;
          end;
        end;
      finally
        SubPkg.Free;
      end;
    end;

    if DirectoryExists(TargetPath) then
    begin
      // Simple directory removal (could use more robust method)
      {$IFDEF UNIX}
      ExecuteProcess('/bin/rm', ['-rf', TargetPath]);
      {$ELSE}
      ExecuteProcess('cmd', ['/c', 'rmdir', '/s', '/q', TargetPath]);
      {$ENDIF}
      writeln('  Removed from vendor/');
    end;

    // Remove from required and resolved lists
    NovaPkg.RemoveRequired(PackageName);
    NovaPkg.RemoveResolved(PackageName);

    // Save updated nova.json
    NovaPkg.SaveToFile('nova.json');
    writeln('  Updated nova.json');

    // Regenerate fpc.cfg
    TFPCConfigWriter.WriteConfig(NovaPkg, 'fpc.cfg');

    success('Package "' + PackageName + '" removed.');

  finally
    NovaPkg.Free;
  end;
end;

function TRemoveCommand.name: string;
begin
  Result := 'remove';
end;

function TRemoveCommand.Description: string;
begin
  Result := 'Remove a package from the project';
end;

end.
