program nova;

{$mode objfpc}{$H+}

uses
  process,
  SysUtils,
  termstyle,
  zipper;

const
  {$IFDEF WINDOWS}
  NOVA_BIN = './nova_bin.exe';
  NOVA_BAK = './nova_bin.bak.exe';
  {$ELSE}
  NOVA_BIN   = './nova_bin';
  NOVA_BAK   = './nova_bin.bak';
  {$ENDIF}
  UPDATE_ZIP = 'nova-bin.zip';
  MSG_FILE   = 'nova.msg';

  // Helper to safely delete files
  procedure SafeDelete(const FileName: string);
  begin
    if FileExists(FileName) then
      if not DeleteFile(FileName) then
        tsWarn('Could not remove ' + FileName);
  end;

  // Extract update zip and handle rollback
  procedure ExtractUpdate;
  var
    Z: TUnZipper;
  begin
    if not FileExists(UPDATE_ZIP) then Exit;

    // Backup current binary
    if FileExists(NOVA_BIN) then
    begin
      SafeDelete(NOVA_BAK);
      if not RenameFile(NOVA_BIN, NOVA_BAK) then
      begin
        tsError('Backup failed, cannot apply update.');
        Halt(1);
      end;
    end;

    Z := TUnZipper.Create;
    try
      try
        Z.FileName := UPDATE_ZIP;
        Z.OutputPath := '.';
        Z.UnZipAllFiles;
        tsSuccess('Update applied from ' + UPDATE_ZIP);

        // Cleanup after successful update
        SafeDelete(UPDATE_ZIP);
        SafeDelete(NOVA_BAK);
      except
        on E: Exception do
        begin
          tsError('Update failed: ' + E.Message);

          // Delete broken zip to prevent repeated failures
          SafeDelete(UPDATE_ZIP);

          // Rollback if backup exists
          if FileExists(NOVA_BAK) then
          begin
            SafeDelete(NOVA_BIN);
            RenameFile(NOVA_BAK, NOVA_BIN);
            tsWarn('Rollback completed: previous version restored. Update ZIP has been removed.');

            writeln(ts(
              '  You can safely attempt <bold><italic>nova self-update</italic></bold> again.'));
            writeln(ts(
              '  If the update fails repeatedly, it is recommended to perform a fresh installation.'));
          end;

          Halt(1);
        end;
      end;
    finally
      Z.Free;
    end;
  end;

  // Display persistent message
  procedure ShowMessage;
  var
    F:    TextFile;
    Line: string;
  begin
    if not FileExists(MSG_FILE) then Exit;

    tsBanner('<bright_white bg:bright_red>', '</bright_white>', 'IMPORTANT NOTICE');
    writeln;

    AssignFile(F, MSG_FILE);
    try
      Reset(F);
      while not EOF(F) do
      begin
        ReadLn(F, Line);
        writeln(ts(Line)); // styled via tags inside nova.msg
      end;
      CloseFile(F);
      writeln;
    except
      on E: Exception do
        tsWarn('Could not read ' + MSG_FILE + ': ' + E.Message);
    end;
  end;

  // Run nova_bin with all CLI arguments
  procedure RunNova(const Args: array of string);
  var
    P: TProcess;
    i: integer;
  begin
    if not FileExists(NOVA_BIN) then
    begin
      tsError('Missing executable: ' + NOVA_BIN);
      halt(1);
    end;

    ExitCode := 0;
    P := TProcess.Create(nil);
    try
      try
        P.Executable := NOVA_BIN;
        for i := 0 to High(Args) do
          P.Parameters.Add(Args[i]);
        P.Options := [];
        P.Execute;
        P.WaitOnExit;
        ExitCode := P.ExitStatus;
      except
        on E: Exception do
        begin
          tsError('Failed to run nova_bin: ' + E.Message);
          P.Free;
          halt(1);
        end;
      end;
    finally
      P.Free;
    end;
  end;

var
  Args: array of string;
  i:    integer;
begin
  try
    ExtractUpdate;
    ShowMessage;

    SetLength(Args, ParamCount);
    for i := 1 to ParamCount do
      Args[i - 1] := ParamStr(i);

    RunNova(Args);
  except
    on E: Exception do
    begin
      tsError('Unexpected fatal error: ' + E.Message);
      halt(1);
    end;
  end;
end.
