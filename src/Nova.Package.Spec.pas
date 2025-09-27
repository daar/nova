unit Nova.Package.Spec;

{$mode objfpc}{$H+}

interface

uses
  Classes,
  fpjson,
  jsonparser,
  SysUtils;

const
  DEP_FILE = 'nova.json';

type
  TNovaPkgSpec = class;

  TAuthor = record
    Name: string;
    Email: string;
  end;

  TDependency = record
    Spec: TNovaPkgSpec;
    Constraint: string;
  end;

  TDependencies = array of TDependency;

  { TNovaPkgSpec }

  TNovaPkgSpec = class
    Name: string;
    License: string;
    Authors: array of TAuthor;
    Description: string;

    PackageType: string;

    Require: TDependencies;
    RequireDev: TDependencies;
    Source: array of string;

    FileName: string;
    ProgramFile: string;

    constructor Create;

    procedure CreateDefault;
    procedure LoadFromFile;
    procedure SaveToFile;

    procedure AddAuthor(const AName, AEmail: string);
    function DefaultAuthorName: string;
    function DefaultAuthorEmail: string;

    function RequireCount: integer;
    function RequireAt(Index: integer): TDependency;
    function RequireDevCount: integer;
    function RequireDevAt(Index: integer): TDependency;
  private
    function DefaultPackageName: string;
  end;

function FindDefaultProgramFile(const Folder: string): string;

implementation

uses
  GitCLI;

  { === Helpers === }

function StringArrayToJSONArray(const A: array of string): TJSONArray;
var
  i: integer;
begin
  Result := TJSONArray.Create;
  for i := 0 to High(A) do
    Result.Add(A[i]);
end;

function GetEnvFallback(const Keys: array of string; const Default: string): string;
var
  i: integer;
begin
  for i := 0 to High(Keys) do
  begin
    Result := GetEnvironmentVariable(Keys[i]);
    if Result <> '' then Exit;
  end;
  Result := Default;
end;

{ === Pascal program detection === }

function FirstMeaningfulLine(const FileName: string): string;
var
  F:    TextFile;
  Line: string;
  InBlock: boolean;
begin
  Result := '';
  InBlock := False;
  AssignFile(F, FileName);
  {$I-}
  Reset(F);
  {$I+}
  if IOResult <> 0 then Exit;

  try
    while not EOF(F) do
    begin
      ReadLn(F, Line);
      Line := Trim(Line);
      if Line = '' then Continue;

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

      if Pos('//', Line) > 0 then
        Delete(Line, Pos('//', Line), MaxInt);

      Line := Trim(Line);
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

function IsProgramFile(const FileName: string): boolean;
var
  FirstLine: string;
begin
  FirstLine := LowerCase(FirstMeaningfulLine(FileName));
  Result := Copy(FirstLine, 1, 7) = 'program';
end;

function FindProgramRecursive(const Folder, Ext: string): string;
var
  SR: TSearchRec;
begin
  Result := '';
  if FindFirst(IncludeTrailingPathDelimiter(Folder) + '*', faAnyFile, SR) = 0 then
    repeat
      if (SR.name = '.') or (SR.name = '..') then Continue;

      if (SR.Attr and faDirectory) <> 0 then
      begin
        Result := FindProgramRecursive(Folder + PathDelim + SR.name, Ext);
        if Result <> '' then Break;
      end
      else if LowerCase(ExtractFileExt(SR.name)) = LowerCase(Ext) then
        if IsProgramFile(Folder + PathDelim + SR.name) then
        begin
          Result := Folder + PathDelim + SR.name;
          Break;
        end;
    until FindNext(SR) <> 0;
  FindClose(SR);
end;

function FindDefaultProgramFile(const Folder: string): string;
begin
  Result := FindProgramRecursive(Folder, '.pp');
  if Result = '' then
    Result := FindProgramRecursive(Folder, '.pas');
end;

{ === TNovaPkgSpec === }

constructor TNovaPkgSpec.Create;
var
  Folder: string;
begin
  inherited Create;

  Name := DefaultPackageName;
  License := '';
  Description := '';
  PackageType := 'library';
  SetLength(Require, 0);
  SetLength(RequireDev, 0);
  SetLength(Source, 0);
  FileName := DEP_FILE;

  if DirectoryExists('./src') then Folder := './src'
  else
  if DirectoryExists('./source') then Folder := './source'
  else
    Folder := '.';

  ProgramFile := FindDefaultProgramFile(Folder);
end;

procedure TNovaPkgSpec.CreateDefault;
begin

end;

procedure TNovaPkgSpec.LoadFromFile;
var
  Data: TJSONData;
  O:    TJSONObject;
  S:    TStringList;
  AuthorRaw: string;
begin
  if FileName = '' then FileName := DEP_FILE;
  if not FileExists(FileName) then Exit;

  S := TStringList.Create;
  try
    S.LoadFromFile(FileName);
    Data := GetJSON(S.Text);
  finally
    S.Free;
  end;

  try
    if not (Data is TJSONObject) then Exit;
    O := TJSONObject(Data);

    name := O.Get('name', '');
    License := O.Get('license', '');

    // Read the array of name / email from authors
    if O.Find('authors') <> nil then
    begin
      // Raw := O.Arrays['authors'];
      // Authors := ...
    end;

    Description := O.Get('description', '');
    PackageType := O.Get('type', '');

    // Read the required packages array
    if O.Find('required') <> nil then
    begin
      // Raw := O.Arrays['required'];
      // Required := ...
    end;

    // Read the required-dev packages array
    if O.Find('required-dev') <> nil then
    begin
      // Raw := O.Arrays['required-dev'];
      // RequiredDev := ...
    end;

    if O.Find('source') <> nil then
    begin
      // Raw := O.Arrays['source'];
      // Source := ...
    end;

  finally
    Data.Free;
  end;
end;

procedure TNovaPkgSpec.SaveToFile;
var
  O, AuthorObj: TJSONObject;
  S: TStringList;
  AuthorsArray: TJSONArray;
  i: integer;
begin
  if FileName = '' then FileName := DEP_FILE;

  O := TJSONObject.Create;
  try
    O.Add('name', name);

    if Description <> '' then
      O.Add('description', Description);

    O.Add('type', PackageType);

    if License <> '' then
      O.Add('license', License);

    if Length(Authors) > 0 then
    begin
      AuthorsArray := TJSONArray.Create;

      for i := 0 to Length(Authors) - 1 do
      begin
        AuthorObj := TJSONObject.Create;
        AuthorObj.Add('name', Authors[i].Name);
        AuthorObj.Add('email', Authors[i].Email);
        AuthorsArray.Add(AuthorObj);
      end;

      // Add the authors array to the main JSON
      O.Add('authors', AuthorsArray);
    end;

    O.Add('require', TJSONObject.Create);
    O.Add('require-dev', TJSONObject.Create);

    if (PackageType = 'project') and (ProgramFile <> '') then
      O.Add('source', StringArrayToJSONArray([ProgramFile]));

    // Save JSON object
    S := TStringList.Create;
    try
      S.Text := O.FormatJSON;
      S.SaveToFile(FileName);
    finally
      S.Free;
    end;
  finally
    O.Free;
  end;
end;

procedure TNovaPkgSpec.AddAuthor(const AName, AEmail: string);
var
  len: integer;
begin
  len := Length(Authors);
  SetLength(Authors, len + 1);

  with Authors[len] do
  begin
    Name:= AName;
    Email:= AEmail;
  end;
end;

function TNovaPkgSpec.RequireCount: integer;
begin
  Result := Length(Require);
end;

function TNovaPkgSpec.RequireAt(Index: integer): TDependency;
begin
  Result := Require[Index];
end;

function TNovaPkgSpec.RequireDevCount: integer;
begin
  Result := Length(RequireDev);
end;

function TNovaPkgSpec.RequireDevAt(Index: integer): TDependency;
begin
  Result := RequireDev[Index];
end;

function TNovaPkgSpec.DefaultPackageName: string;
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

function TNovaPkgSpec.DefaultAuthorName: string;
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

function TNovaPkgSpec.DefaultAuthorEmail: string;
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

end.
