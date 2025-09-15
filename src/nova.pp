program nova;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}BaseUnix,{$ENDIF}
  Classes,
  fphttpclient,
  fpjson,
  jsonparser,
  opensslsockets,
  process,
  SysUtils;

const
  GITHUB_API = 'https://api.github.com/repos/nova-packager/nova/releases/latest';

  {$IFDEF WINDOWS}
  NOVA_BIN = './nova_bin.exe';
  {$ELSE}
  NOVA_BIN = './nova_bin';
  {$ENDIF}

var
  http: TFPHTTPClient;
  jsonResp: TJSONObject;
  latestTag, currentVersion: string;
  paramArr: array of TProcessString;
  i: integer;
  outputStr: ansistring;

  procedure RunNovaCommand(const exename: TProcessString;
  const commands: array of TProcessString);
  var
    AProcess: TProcess;
  begin
    AProcess := TProcess.Create(nil);
    try
      AProcess.Executable := exename;
      AProcess.Parameters.AddStrings(commands);
      AProcess.Options := []; // do NOT use poUsePipes, output goes straight to terminal
      AProcess.Execute;
      AProcess.WaitOnExit;
    finally
      AProcess.Free;
    end;
  end;

begin
  // Get current version from nova_bin -v
  if not RunCommand(NOVA_BIN, ['-v'], outputStr) then
    currentVersion := Trim(Copy(outputStr, Pos(' ', outputStr) + 1, MaxInt))
  else
    currentVersion := '0.0.0';

  // Fetch latest release info from GitHub
  http := TFPHTTPClient.Create(nil);
  try
    http.AddHeader('User-Agent', 'NovaSelfUpdate/1.0');
    jsonResp := TJSONObject(GetJSON(http.Get(GITHUB_API)));
    try
      latestTag := jsonResp.Get('tag_name', '');
    finally
      jsonResp.Free;
    end;
  finally
    http.Free;
  end;

  // Notify user of a new version
  if latestTag <> currentVersion then
  begin
    writeln('A new version of nova is now available: ', latestTag,
      ' (current: ', currentVersion, ').');
    writeln('Download the latest release at https://github.com/nova-packager/nova.');
    writeln;
  end;

  // Launch nova_bin with original parameters
  SetLength(paramArr, ParamCount);
  for i := 1 to ParamCount do
    paramArr[i - 1] := ansistring(ParamStr(i));

  RunNovaCommand(NOVA_BIN, paramArr);
end.
