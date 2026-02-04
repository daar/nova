unit GitCLI;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Process;

type
  { Structured result for Git commands }
  TGitResult = record
    ExitCode: Integer;
    StdOut: string;
    StdErr: string;
    Success: Boolean;
  end;

  TGitAsyncCallback = procedure(const Result: TGitResult) of object;

  { TGitCLI }
  TGitCLI = class
  private
    FRepositoryPath: string;
    FLastError: string;
  protected
    function RunGitCommand(const Args: array of string): TGitResult;
  public
    constructor Create(const ARepoPath: string);

    property LastError: string read FLastError;

    function Version: TGitResult;
    function Status: TGitResult;
    function Clone(const RepoURL, TargetDir: string): TGitResult;
    function CloneDepth(const RepoURL, TargetDir: string; Depth: integer): TGitResult;
    function Fetch(const Remote: string = 'origin'): TGitResult;
    function FetchTags: TGitResult;
    function CheckoutTag(const TagName: string): TGitResult;
    function Add(const Files: array of string): TGitResult;
    function Commit(const Message: string): TGitResult;
    function Push(const Remote, Branch: string): TGitResult;
    function Pull(const Remote, Branch: string): TGitResult;
    function Checkout(const Branch: string): TGitResult;
    function GetUserName: TGitResult;
    function GetUserEmail: TGitResult;

    // Remote info
    function GetRemoteURL(const RemoteName: string = 'origin'): TGitResult;

    // Async execution
    procedure RunGitCommandAsync(const Args: array of string; Callback: TGitAsyncCallback);
  end;

implementation

type
  { Worker thread for async execution }
  TGitWorker = class(TThread)
  private
    FArgs: array of string;
    FOwner: TGitCLI;
    FCallback: TGitAsyncCallback;
    FResult: TGitResult;
  protected
    procedure Execute; override;
    procedure DoCallback;
  public
    constructor Create(AOwner: TGitCLI; const Args: array of string; Callback: TGitAsyncCallback);
  end;

{ TGitCLI }

constructor TGitCLI.Create(const ARepoPath: string);
begin
  inherited Create;
  FRepositoryPath := ExpandFileName(ARepoPath);
  FLastError := '';
end;

function TGitCLI.RunGitCommand(const Args: array of string): TGitResult;
var
  Proc: TProcess;
  StdOutStream, StdErrStream: TStringList;
  i: Integer;
begin
  Result.ExitCode := -1;
  Result.StdOut := '';
  Result.StdErr := '';
  Result.Success := False;

  Proc := TProcess.Create(nil);
  StdOutStream := TStringList.Create;
  StdErrStream := TStringList.Create;
  try
    Proc.Executable := 'git';
    for i := Low(Args) to High(Args) do
      Proc.Parameters.Add(Args[i]);

    // Only set working directory if it exists (clone creates new dirs)
    if (FRepositoryPath <> '') and DirectoryExists(FRepositoryPath) then
      Proc.CurrentDirectory := FRepositoryPath;

    Proc.Options := [poUsePipes, poStderrToOutPut, poNoConsole];
    Proc.Execute;

    StdOutStream.LoadFromStream(Proc.Output);
    Result.StdOut := Trim(StdOutStream.Text);

    Proc.WaitOnExit;
    Result.ExitCode := Proc.ExitStatus;
    Result.Success := Result.ExitCode = 0;

    if not Result.Success then
      FLastError := Result.StdOut + LineEnding + Result.StdErr;

  finally
    StdOutStream.Free;
    StdErrStream.Free;
    Proc.Free;
  end;
end;

function TGitCLI.Version: TGitResult;
begin
  Result := RunGitCommand(['--version']);
end;

function TGitCLI.Status: TGitResult;
begin
  Result := RunGitCommand(['status', '--short', '--branch']);
end;

function TGitCLI.Clone(const RepoURL, TargetDir: string): TGitResult;
begin
  Result := RunGitCommand(['clone', RepoURL, TargetDir]);
end;

function TGitCLI.CloneDepth(const RepoURL, TargetDir: string; Depth: integer): TGitResult;
begin
  Result := RunGitCommand(['clone', '--depth', IntToStr(Depth), RepoURL, TargetDir]);
end;

function TGitCLI.Fetch(const Remote: string): TGitResult;
begin
  Result := RunGitCommand(['fetch', Remote]);
end;

function TGitCLI.FetchTags: TGitResult;
begin
  Result := RunGitCommand(['fetch', '--tags']);
end;

function TGitCLI.CheckoutTag(const TagName: string): TGitResult;
begin
  Result := RunGitCommand(['checkout', 'tags/' + TagName]);
end;

function TGitCLI.Add(const Files: array of string): TGitResult;
var
  Args: array of string;
  i: Integer;
begin
  SetLength(Args, Length(Files) + 1);
  Args[0] := 'add';
  for i := 0 to High(Files) do
    Args[i+1] := Files[i];
  Result := RunGitCommand(Args);
end;

function TGitCLI.Commit(const Message: string): TGitResult;
begin
  Result := RunGitCommand(['commit', '-m', Message]);
end;

function TGitCLI.Push(const Remote, Branch: string): TGitResult;
begin
  Result := RunGitCommand(['push', Remote, Branch]);
end;

function TGitCLI.Pull(const Remote, Branch: string): TGitResult;
begin
  Result := RunGitCommand(['pull', Remote, Branch]);
end;

function TGitCLI.Checkout(const Branch: string): TGitResult;
begin
  Result := RunGitCommand(['checkout', Branch]);
end;

function TGitCLI.GetUserName: TGitResult;
begin
  // Try local first
  Result := RunGitCommand(['config', '--get', 'user.name']);
  if not Result.Success then
    // Fallback to global
    Result := RunGitCommand(['config', '--global', '--get', 'user.name']);
end;

function TGitCLI.GetUserEmail: TGitResult;
begin
  // Try local first
  Result := RunGitCommand(['config', '--get', 'user.email']);
  if not Result.Success then
    // Fallback to global
    Result := RunGitCommand(['config', '--global', '--get', 'user.email']);
end;

function TGitCLI.GetRemoteURL(const RemoteName: string): TGitResult;
begin
  Result := RunGitCommand(['remote', 'get-url', RemoteName]);
end;

procedure TGitCLI.RunGitCommandAsync(const Args: array of string; Callback: TGitAsyncCallback);
begin
  TGitWorker.Create(Self, Args, Callback);
end;

{ TGitWorker }

constructor TGitWorker.Create(AOwner: TGitCLI; const Args: array of string; Callback: TGitAsyncCallback);
var
  i: Integer;
begin
  inherited Create(True);
  FreeOnTerminate := True;
  FOwner := AOwner;
  SetLength(FArgs, Length(Args));
  for i := Low(Args) to High(Args) do
    FArgs[i] := Args[i];
  FCallback := Callback;
  Start;
end;

procedure TGitWorker.Execute;
begin
  FResult := FOwner.RunGitCommand(FArgs);
  Synchronize(@DoCallback);
end;

procedure TGitWorker.DoCallback;
begin
  if Assigned(FCallback) then
    FCallback(FResult);
end;

end.

