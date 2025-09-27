unit Nova.Command.Init;

{$mode ObjFPC}{$H+}

interface

uses
  Classes,
  SysUtils,
  Nova.Command;

type

{ TInitCommand }

TInitCommand = class(TBaseCommand)
public
  procedure Execute; override;
  function name: string; override;
  function Description: string; override;
private
  function DefaultPackageName: string;
  function DefaultAuthor: string;
  function DefaultEmail: string;

  function FirstMeaningfulLine(const FileName: string): string;
  function IsProgramFile(const FileName: string): Boolean;
  function FindProgramRecursive(const Folder, Ext: string): string;
public
  function FindDefaultProgramFile(const Folder: string): string;
end;

implementation

uses
  fpjson,
  jsonscanner,
  process,
  GitCLI,
  TermStyle;

{ TInitCommand }

procedure TInitCommand.Execute;
var
  JsonObj, AuthorObj: TJSONObject;
  AuthorsArray: TJSONArray;
  PackageName, License, ADescription, AuthorName, AuthorEmail,
  PackageType, SrcFolder: string;
begin
  // Banner
  writeln;
  writeln(render(
    '<span class="ml-1 p-1 bg-sky-700 text-sky-200">Welcome to the nova config generator</span>'));

  writeln;
  writeln(render('<span class="ml-2">This command will guide you through creating your <b>'
    + DEP_FILE + '</b> config</span>'));
  Writeln;

  //Prompts
  PackageName := prompt('Package name (vendor/name)', DefaultPackageName, 'ml-2');

  ADescription := prompt('Description', '', 'ml-2');
  AuthorName := prompt('Author', DefaultAuthor, 'ml-2', 'n');
  if AuthorName <> 'n' then
    AuthorEmail := prompt('Email', DefaultEmail, 'ml-2', 'n');

  PackageType := prompt('Package Type (e.g. library, project, metapackage)',
    'library', 'ml-2');
  PackageType := Lowercase(PackageType);
  if (PackageType <> 'library') and (PackageType <> 'project') and
    (PackageType <> 'metapackage') then
  begin
    writeln(render('Invalid package type chosen, default set to <i>library</i>'));
    PackageType := 'library';
  end;
  License := prompt('License', '', 'ml-2');

  if PackageType = 'project' then
  begin
    if DirectoryExists('./src') then SrcFolder := './src';
    if DirectoryExists('./source') then SrcFolder := './source';

    SrcFolder := FindDefaultProgramFile(SrcFolder);

    SrcFolder := prompt('Source file', SrcFolder, 'ml-2');
  end;

  // Build JSON
  JsonObj := TJSONObject.Create;
  try
    JsonObj.Add('name', PackageName);

    if ADescription <> '' then
      JsonObj.Add('description', ADescription);

    JsonObj.Add('type', PackageType);

    if License <> '' then
      JsonObj.Add('license', License);

    // Only add author if not skipped
    if AuthorName <> 'n' then
    begin
      AuthorObj := TJSONObject.Create;
      AuthorObj.Add('name', AuthorName);
      AuthorObj.Add('email', AuthorEmail);
      AuthorsArray := TJSONArray.Create;
      AuthorsArray.Add(AuthorObj);

      // Add the authors array to the main JSON
      JsonObj.Add('authors', AuthorsArray);
    end;

    JsonObj.Add('require', TJSONObject.Create);
    JsonObj.Add('require-dev', TJSONObject.Create);

    if SrcFolder <> '' then
      JsonObj.Add('source', SrcFolder);

    writeln;
    writeln(JsonObj.FormatJSON());
    //save_json(DEP_FILE, JsonObj);
    writeln;
    success('Generated <b>' + DEP_FILE + '</b> with basic information.');
  finally
    JsonObj.Free;
  end;

  // Next steps
  writeln(render(
    '<div class="ml-4">Add a new requirements to your project with: <i>nova require [vendor/package]</i></div>'));
  writeln(render(
    '<div class="ml-4">Visit the <a href="https://github.com/nova-packager/nova">nova project page</a> for more information.</div>'));
  writeln;
end;

function TInitCommand.name: string;
begin
  Result := 'init';
end;

function TInitCommand.Description: string;
begin
  Result := 'Initialize a new project interactively';
end;

function TInitCommand.DefaultPackageName: string;
var
  Git: TGitCLI;
  Res: TGitResult;
  RemoteURL: string;
  P:   integer;
  UserName, FolderName, Path: string;
begin
  Path := GetCurrentDir;

  // --- First: check if inside a git repo ---
  Git := TGitCLI.Create(Path);
  try
    Res := Git.GetRemoteURL('origin');
    if Res.Success then
    begin
      RemoteURL := Trim(Res.StdOut);
      if RemoteURL <> '' then
      begin
        // --- Handle SSH style: git@github.com:user/repo.git ---
        if (Pos('@', RemoteURL) > 0) and (Pos(':', RemoteURL) > 0) then
        begin
          P := Pos(':', RemoteURL);
          RemoteURL := Copy(RemoteURL, P + 1, MaxInt);
        end
        else
        begin
          // --- Handle HTTPS style: https://github.com/user/repo.git ---
          P := Pos('//', RemoteURL);
          if P > 0 then
            RemoteURL := Copy(RemoteURL, P + 2, MaxInt); // strip scheme
          P := Pos('/', RemoteURL);
          if P > 0 then
            RemoteURL := Copy(RemoteURL, P + 1, MaxInt); // strip host
        end;

        // Remove .git if present
        if RemoteURL.EndsWith('.git') then
          Delete(RemoteURL, Length(RemoteURL) - 3, 4);

        exit(LowerCase(RemoteURL));
      end;
    end
    else
    begin
      // --- Fallback: username/foldername ---
      {$IFDEF WINDOWS}
        SetLength(UserName, 256);
        if GetEnvironmentVariable('USERNAME', PChar(UserName), Length(UserName)) > 0 then
          UserName := Trim(PChar(UserName));
      {$ELSE}
      UserName := GetEnvironmentVariable('USER');
      {$ENDIF}

      if UserName = '' then
        UserName := 'user';

      FolderName := ExtractFileName(Path);
      if FolderName = '' then
        FolderName := 'project';

      exit(LowerCase(UserName + '/' + FolderName));
    end;
  finally
    Git.Free;
  end;
end;

function TInitCommand.DefaultAuthor: string;
var
  Git:      TGitCLI;
  ResName:  TGitResult;
  FullName: string;
  Path:     string;
begin
  Path := GetCurrentDir;
  Git := TGitCLI.Create(Path);
  try
    // --- Try to get Git local/global user information ---
    ResName := Git.GetUserName;

    FullName := Trim(ResName.StdOut);

    // --- Fallback to environment variables if Git info not available ---
    if FullName = '' then
      FullName := GetEnvironmentVariable('GIT_AUTHOR_NAME');

    // --- Fallback to generic environment/user info ---
    if FullName = '' then
    begin
      {$IFDEF WINDOWS}
      FullName := GetEnvironmentVariable('USERNAME');
      {$ELSE}
      FullName := GetEnvironmentVariable('USER');
      {$ENDIF}
      if FullName = '' then
        FullName := 'user';
    end;

    // --- Return formatted author ---
    Result := FullName;
  finally
    Git.Free;
  end;
end;

function TInitCommand.DefaultEmail: string;
var
  Git:      TGitCLI;
  ResEmail: TGitResult;
  Email:    string;
  Path:     string;
begin
  Path := GetCurrentDir;
  Git := TGitCLI.Create(Path);
  try
    // --- Try to get Git local/global user information ---
    ResEmail := Git.GetUserEmail;

    Email := Trim(ResEmail.StdOut);

    // --- Fallback to environment variables if Git info not available ---
    if Email = '' then
      Email := GetEnvironmentVariable('GIT_AUTHOR_EMAIL');

    // --- Fallback to generic environment/user info ---
    if Email = '' then
      Email := GetEnvironmentVariable('EMAIL');

    if Email = '' then
      Email := 'user@example.com';

    // --- Return formatted author ---
    Result := Email;
  finally
    Git.Free;
  end;
end;

function TInitCommand.FirstMeaningfulLine(const FileName: string): string;
var
  F: TextFile;
  Line: string;
  InBlock: Boolean;
begin
  Result := '';
  InBlock := False;

  AssignFile(F, FileName);
  {$I-} Reset(F); {$I+}
  if IOResult <> 0 then Exit;

  try
    while not Eof(F) do
    begin
      ReadLn(F, Line);
      Line := Trim(Line);

      if Line = '' then Continue;

      // Handle block comments { ... } or (* ... *)
      if InBlock then
      begin
        if (Pos('}', Line) > 0) or (Pos('*)', Line) > 0) then
          InBlock := False;
        Continue;
      end;

      if (Line[1] = '{') or (Pos('(*', Line) = 1) then
      begin
        if not ((Line.EndsWith('}')) or (Line.EndsWith('*)'))) then
          InBlock := True;
        Continue;
      end;

      // Strip // comments
      if Pos('//', Line) > 0 then
        Delete(Line, Pos('//', Line), MaxInt);

      if Line <> '' then
      begin
        Result := Line;
        Exit;
      end;
    end;
  finally
    CloseFile(F);
  end;
end;

function TInitCommand.IsProgramFile(const FileName: string): Boolean;
var
  FirstLine: string;
begin
  FirstLine := LowerCase(FirstMeaningfulLine(FileName));
  Result := Copy(FirstLine, 1, 7) = 'program';
end;

function TInitCommand.FindProgramRecursive(const Folder, Ext: string): string;
var
  SR: TSearchRec;
begin
  Result := '';
  if FindFirst(IncludeTrailingPathDelimiter(Folder) + '*', faAnyFile, SR) = 0 then
  repeat
    if (SR.Name = '.') or (SR.Name = '..') then Continue;

    if (SR.Attr and faDirectory) <> 0 then
    begin
      // search subdirectory
      Result := FindProgramRecursive(Folder + PathDelim + SR.Name, Ext);
      if Result <> '' then Break;
    end
    else if Lowercase(ExtractFileExt(SR.Name)) = Ext.ToLower then
    begin
      if IsProgramFile(Folder + PathDelim + SR.Name) then
      begin
        Result := Folder + PathDelim + SR.Name;
        Break;
      end;
    end;
  until FindNext(SR) <> 0;
  FindClose(SR);
end;

function TInitCommand.FindDefaultProgramFile(const Folder: string): string;
begin
  // Prefer .pp, then .pas
  Result := FindProgramRecursive(Folder, '.pp');
  if Result = '' then
    Result := FindProgramRecursive(Folder, '.pas');
end;

end.

