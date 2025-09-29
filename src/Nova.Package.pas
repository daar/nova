unit Nova.Package;

{$mode objfpc}{$H+}

interface

uses
  Classes,
  fpjson,
  jsonparser, SysUtils;

const
  DEP_FILE = 'nova.json';
  VENDOR_DIR = 'vendor';
  FPC_FILE = 'fpc.cfg';

type
  TAuthor = record
    Name: string;
    Email: string;
  end;

  TRequired = record
    Name: string;
    Constraint: string;
    Dev: boolean;
  end;

  TRequiredArray = array of TRequired;

  TResolved = record
    Name: string;
    Version: string;
    Commit: string;
    Dev: boolean;
    Source: array of string;
    Required: TRequiredArray;  // Names of other resolved packages this depends on
  end;

  TResolvedArray = array of TResolved;

  { TNovaPackage }

  TNovaPackage = class
  private
    FName: string;
    FLicense: string;
    FAuthors: array of TAuthor;
    FSource: TStringArray;
    FDescription: string;
    FPackageType: string;        // 'project', 'library', 'metapackage', etc.

    FRequired: TRequiredArray;   // from nova.json
    FResolved: TResolvedArray;   // from nova.lock

    FFileName: string;           // Full path to nova.json
    FFolder: string;             // Root folder for this package

    function JSONArrayToStringArray(JSONArr: TJSONArray): TStringArray;

    procedure LoadFromJSON(const Obj: TJSONObject);
    procedure SaveToJSON(Obj: TJSONObject);

    function IndexOfResolved(const Name: string): integer;
    function IndexOfRequired(const Name: string): integer;

    function FirstMeaningfulLine(const FileName: string): string;
    function IsProgramFile(const FileName: string): boolean;
    function FindProgramRecursive(const Folder, Ext: string): string;
  public
    constructor Create;
    destructor Destroy; override;

    property Name: string read FName write FName;
    property Description: string read FDescription write FDescription;
    property PackageType: string read FPackageType write FPackageType;
    property License: string read FLicense write FLicense;

    // --- File operations ---
    procedure LoadFromFile(const FullPath: string = DEP_FILE);
    procedure SaveToFile(const FullPath: string = DEP_FILE);

    // Add
    procedure AddAuthor(const AName, AEmail: string);
    procedure AddSource(const FileName: string);
    procedure AddRequired(const AName, Constraint: string; const Dev: boolean);
    procedure AddResolved(const AName, AVersion, Commit: string;
      Dev: boolean; const Source: array of string; const Required: TRequiredArray);

    // Defaults
    function DefaultAuthorName: string;
    function DefaultAuthorEmail: string;
    function DefaultSourceFile(const Folder: string = ''): string;
    function DefaultPackageName: string;

    // --- Required / Resolved ---
    function PackageAlreadyRegistered(const PackageName: string): Boolean;
    function RequiredCount: integer;
    function RequiredAt(Index: integer): TRequired;
    function ResolvedCount: integer;
    function ResolvedAt(Index: integer): TResolved;

    // --- Dependency handling ---
    function FindResolved(const AName: string): TResolved;
    function FindPackageRequirements(const AName: string): TRequiredArray;
  end;

implementation

uses
  GitCLI;

{ TNovaPackage }

constructor TNovaPackage.Create;
begin
  FName := '';
  FLicense := '';
  FDescription := '';
  FPackageType := 'library';
  SetLength(FAuthors, 0);
  SetLength(FRequired, 0);
  SetLength(FResolved, 0);
end;

destructor TNovaPackage.Destroy;
begin
  inherited Destroy;
end;

// --- File operations ---

procedure TNovaPackage.LoadFromFile(const FullPath: string);
var
  Data:    TJSONData;
  SL:      TStringList;
begin
  if not FileExists(FullPath) then Exit;
  SL := TStringList.Create;

  try
    SL.LoadFromFile(FullPath);
    Data := GetJSON(SL.Text);
    if Data is TJSONObject then
      LoadFromJSON(TJSONObject(Data));
  finally
    SL.Free;
    Data.Free;
  end;
end;

procedure TNovaPackage.SaveToFile(const FullPath: string);
var
  FS: TFileStream;
  S:  string;
  JSONObj: TJSONObject;
begin
  JSONObj := TJSONObject.Create;
  SaveToJSON(JSONObj);

  S := JSONObj.FormatJSON;
  FS := TFileStream.Create(FullPath, fmCreate);
  try
    FS.WriteBuffer(Pointer(S)^, Length(S) * SizeOf(char));
  finally
    FS.Free;
  end;
end;

// --- JSON helpers ---

function TNovaPackage.JSONArrayToStringArray(JSONArr: TJSONArray): TStringArray;
var
  i: integer;
begin
  if JSONArr = nil then
  begin
    SetLength(Result, 0);
    Exit;
  end;

  SetLength(Result, JSONArr.Count);
  for i := 0 to JSONArr.Count - 1 do
    Result[i] := JSONArr.Strings[i];
end;

procedure TNovaPackage.LoadFromJSON(const Obj: TJSONObject);
var
  i, k:      integer;
  Raw, ReqArr:    TJSONArray;
  SourceArray: TStringArray;
  RequiredArray: TRequiredArray;
  ResObj, ReqObj: TJSONObject;
begin
  FName := Obj.Get('name', '');
  FLicense := Obj.Get('license', '');
  FDescription := Obj.Get('description', '');
  FPackageType := Obj.Get('type', 'library');

  // Authors
  if Obj.Find('authors') <> nil then
  begin
    Raw := Obj.Arrays['authors'];
    for i := 0 to Raw.Count - 1 do
      if Raw.Items[i] is TJSONObject then
        AddAuthor(
          TJSONObject(Raw.Items[i]).Get('name', ''),
          TJSONObject(Raw.Items[i]).Get('email', '')
          );
  end;

  // Source
  if Obj.Find('source') <> nil then
  begin
    Raw := Obj.Arrays['source'];
    for i := 0 to Raw.Count - 1 do
      if Raw.Items[i] <> nil then
        Self.AddSource(Raw.Items[i].AsString);
  end;

  // Required
  if Obj.Find('required') <> nil then
  begin
    Raw := Obj.Arrays['required'];
    for i := 0 to Raw.Count - 1 do
      if Raw.Items[i] is TJSONObject then
        AddRequired(
          TJSONObject(Raw.Items[i]).Get('name', ''),
          TJSONObject(Raw.Items[i]).Get('constraint', ''),
          TJSONObject(Raw.Items[i]).Get('dev', False)
          );
  end;

  // Resolved
  if Obj.Find('resolved') <> nil then
  begin
    Raw := Obj.Arrays['resolved'];
    for i := 0 to Raw.Count - 1 do
      if Raw.Items[i] is TJSONObject then
      begin
        ResObj := TJSONObject(Raw.Items[i]);

        // safely convert 'source' JSON array to string array
        if (ResObj.Find('source') <> nil) and (ResObj.Arrays['source'] <> nil) then
          SourceArray := JSONArrayToStringArray(ResObj.Arrays['source'])
        else
          SetLength(SourceArray, 0);

        // safely convert 'required' JSON array to string array
        if (ResObj.Find('required') <> nil) and (ResObj.Arrays['required'] <> nil) then
        begin
          ReqArr := ResObj.Arrays['required'];
          SetLength(RequiredArray, ReqArr.Count);
          for k := 0 to ReqArr.Count - 1 do
          begin
            if ReqArr.Items[k] is TJSONObject then
            begin
              ReqObj := TJSONObject(ReqArr.Items[k]);
              RequiredArray[k].Name := ReqObj.Get('name', '');
              RequiredArray[k].Constraint := ReqObj.Get('constraint', '');
              RequiredArray[k].Dev := ReqObj.Get('dev', False);
            end;
          end;
        end
        else
          SetLength(RequiredArray, 0);

        AddResolved(
          TJSONObject(Raw.Items[i]).Get('name', ''),
          TJSONObject(Raw.Items[i]).Get('version', ''),
          TJSONObject(Raw.Items[i]).Get('commit', ''),
          TJSONObject(Raw.Items[i]).Get('dev', False),
          SourceArray,
          RequiredArray
          );
      end;
  end;
end;

procedure TNovaPackage.SaveToJSON(Obj: TJSONObject);
var
  i, j: integer;
  AuthObj, ReqObj, ResObj: TJSONObject;
  AuthorsArray, RequiredArray, ResolvedArray, RequiredNames, SourceArray: TJSONArray;
begin
  Obj.Add('name', FName);
  Obj.Add('license', FLicense);
  Obj.Add('description', FDescription);
  Obj.Add('type', FPackageType);

  // Authors
  if Length(FAuthors) > 0 then
  begin
    AuthorsArray := TJSONArray.Create;
    for i := 0 to High(FAuthors) do
    begin
      AuthObj := TJSONObject.Create;
      AuthObj.Add('name', FAuthors[i].Name);
      AuthObj.Add('email', FAuthors[i].Email);
      AuthorsArray.Add(AuthObj);
    end;
    Obj.Add('authors', AuthorsArray);
  end;

  if Length(FSource) > 0 then
  begin
    SourceArray := TJSONArray.Create;
    for i := 0 to High(FSource) do
      SourceArray.Add(FSource[i]);
    Obj.Add('source', SourceArray);
  end;

  // Required
  if Length(FRequired) > 0 then
  begin
    RequiredArray := TJSONArray.Create;
    for i := 0 to High(FRequired) do
    begin
      ReqObj := TJSONObject.Create;
      ReqObj.Add('name', FRequired[i].Name);
      ReqObj.Add('constraint', FRequired[i].Constraint);
      ReqObj.Add('dev', FRequired[i].Dev);
      RequiredArray.Add(ReqObj);
    end;
    Obj.Add('required', RequiredArray);
  end;

  // Resolved
  if Length(FResolved) > 0 then
  begin
    ResolvedArray := TJSONArray.Create;
    for i := 0 to High(FResolved) do
    begin
      ResObj := TJSONObject.Create;
      ResObj.Add('name', FResolved[i].Name);
      ResObj.Add('version', FResolved[i].Version);
      ResObj.Add('commit', FResolved[i].Commit);
      ResObj.Add('dev', FResolved[i].Dev);

      if Length(FResolved[i].Required) > 0 then
      begin
        RequiredArray := TJSONArray.Create;
        for j := 0 to High(FResolved[i].Required) do
        begin
          ReqObj := TJSONObject.Create;
          ReqObj.Add('name', FResolved[i].Required[j].Name);
          ReqObj.Add('constraint', FResolved[i].Required[j].Constraint);
          ReqObj.Add('dev', FResolved[i].Required[j].Dev);
          RequiredArray.Add(ReqObj);
        end;
        ResObj.Add('required', RequiredArray);
      end;

      ResolvedArray.Add(ResObj);
    end;
    Obj.Add('resolved', ResolvedArray);
  end;
end;

// --- Required / Resolved management ---

procedure TNovaPackage.AddAuthor(const AName, AEmail: string);
var
  L: integer;
begin
  L := Length(FAuthors);
  SetLength(FAuthors, L + 1);
  FAuthors[L].Name := AName;
  FAuthors[L].Email := AEmail;
end;

function TNovaPackage.DefaultAuthorName: string;
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

function TNovaPackage.DefaultAuthorEmail: string;
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

function TNovaPackage.DefaultSourceFile(const Folder: string): string;
var
  SearchFolder: string;
begin
  if Folder = '' then
  begin
    if DirectoryExists('./src') then SearchFolder := './src'
    else
      if DirectoryExists('./source') then SearchFolder := './source'
        else
          SearchFolder := '.';
  end
  else
    SearchFolder := Folder;

  Result := FindProgramRecursive(SearchFolder, '.pp');
  if Result = '' then
    Result := FindProgramRecursive(SearchFolder, '.pas');
end;

function TNovaPackage.DefaultPackageName: string;
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

function TNovaPackage.PackageAlreadyRegistered(const PackageName: string
  ): Boolean;
var
  i: Integer;
begin
  Result := False;
  for i := 0 to High(FRequired) do
  begin
    if SameText(FRequired[i].Name, PackageName) then
    begin
      Result := True;
      Exit;
    end;
  end;
end;

procedure TNovaPackage.AddSource(const FileName: string);
var
  l: integer;
begin
  l := Length(FSource);
  SetLength(FSource, l + 1);
  FSource[l] := FileName;
end;

procedure TNovaPackage.AddRequired(const AName, Constraint: string;
  const Dev: boolean);
var
  l: integer;
begin
  l := Length(FRequired);
  SetLength(FRequired, l + 1);
  FRequired[l].Name := AName;
  FRequired[l].Constraint := Constraint;
  FRequired[l].Dev := Dev;
end;

procedure TNovaPackage.AddResolved(const AName, AVersion, Commit: string;
  Dev: boolean; const Source: array of string;
  const Required: TRequiredArray);
var
  l, i: integer;
begin
  l := Length(FResolved);
  SetLength(FResolved, l + 1);
  FResolved[l].Name := AName;
  FResolved[l].Version := AVersion;
  FResolved[l].Commit := Commit;
  FResolved[l].Dev := Dev;

  SetLength(FResolved[l].Source, Length(Source));
  for i := 0 to High(Source) do
    FResolved[l].Source[i] := Source[i];

  SetLength(FResolved[l].Required, Length(Required));
  for i := 0 to High(Required) do
    FResolved[l].Required[i] := Required[i];
end;

function TNovaPackage.RequiredCount: integer;
begin
  Result := Length(FRequired);
end;

function TNovaPackage.RequiredAt(Index: integer): TRequired;
begin
  Result := FRequired[Index];
end;

function TNovaPackage.ResolvedCount: integer;
begin
  Result := Length(FResolved);
end;

function TNovaPackage.ResolvedAt(Index: integer): TResolved;
begin
  Result := FResolved[Index];
end;

// --- Helpers ---

function TNovaPackage.IndexOfResolved(const Name: string): integer;
var
  i: integer;
begin
  Result := -1;
  for i := 0 to High(FResolved) do
    if FResolved[i].Name = Name then Exit(i);
end;

function TNovaPackage.IndexOfRequired(const Name: string): integer;
var
  i: integer;
begin
  Result := -1;
  for i := 0 to High(FRequired) do
    if FRequired[i].Name = Name then Exit(i);
end;

function TNovaPackage.FirstMeaningfulLine(const FileName: string): string;
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

function TNovaPackage.IsProgramFile(const FileName: string): boolean;
var
  FirstLine: string;
begin
  FirstLine := LowerCase(FirstMeaningfulLine(FileName));
  Result := Copy(FirstLine, 1, 7) = 'program';
end;

function TNovaPackage.FindProgramRecursive(const Folder, Ext: string): string;
var
  SR: TSearchRec;
begin
  Result := '';
  if FindFirst(IncludeTrailingPathDelimiter(Folder) + '*', faAnyFile, SR) = 0 then
    repeat
      if (SR.Name = '.') or (SR.Name = '..') then Continue;

      if (SR.Attr and faDirectory) <> 0 then
      begin
        Result := FindProgramRecursive(Folder + PathDelim + SR.Name, Ext);
        if Result <> '' then Break;
      end
      else if LowerCase(ExtractFileExt(SR.Name)) = LowerCase(Ext) then
        if IsProgramFile(Folder + PathDelim + SR.Name) then
        begin
          Result := Folder + PathDelim + SR.Name;
          Break;
        end;
    until FindNext(SR) <> 0;
  FindClose(SR);
end;

function TNovaPackage.FindResolved(const AName: string): TResolved;
var
  idx: integer;
begin
  idx := IndexOfResolved(AName);
  if idx >= 0 then
    Result := FResolved[idx]
  else
    Result.Name := '';
end;

function TNovaPackage.FindPackageRequirements(const AName: string): TRequiredArray;
var
  i: integer;
begin
  SetLength(Result, 0);
  for i := 0 to High(FResolved) do
  begin
    if SameText(FResolved[i].Name, AName) then
    begin
      Result := FResolved[i].Required;
      Exit;
    end;
  end;
end;

end.
