program nova;

{$mode objfpc}{$H+}

uses
  process,
  SysUtils,
  TermStyle,
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
        warning('Could not remove <b>' + FileName + '</b>');
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
        error('Backup failed, cannot apply update.');
        Halt(1);
      end;
    end;

    Z := TUnZipper.Create;
    try
      try
        Z.FileName := UPDATE_ZIP;
        Z.OutputPath := '.';
        Z.UnZipAllFiles;
        success('Update applied from <b>' + UPDATE_ZIP + '</b>');

        // Cleanup after successful update
        SafeDelete(UPDATE_ZIP);
        SafeDelete(NOVA_BAK);
      except
        on E: Exception do
        begin
          error('Update failed: <i>' + E.Message + '</i>');

          // Delete broken zip to prevent repeated failures
          SafeDelete(UPDATE_ZIP);

          // Rollback if backup exists
          if FileExists(NOVA_BAK) then
          begin
            SafeDelete(NOVA_BIN);
            RenameFile(NOVA_BAK, NOVA_BIN);
            warning('Rollback completed: previous version restored. Update ZIP has been removed.');

            writeln(render(
              '  You can safely attempt <b><i>nova self-update</i></b> again.'));
            writeln(render(
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

    banner('IMPORTANT NOTICE', 'text-white bg-red-500');
    writeln;

    AssignFile(F, MSG_FILE);
    try
      Reset(F);
      while not EOF(F) do
      begin
        ReadLn(F, Line);
        writeln(render(Line)); // styled via tags inside nova.msg
      end;
      CloseFile(F);
      writeln;
    except
      on E: Exception do
        warning('Could not read <b>' + MSG_FILE + '</b>: <i>' + E.Message + '</i>');
    end;
  end;

  // Run nova_bin with all CLI arguments
  procedure RunNova;
  var
    P: TProcess;
    i: integer;
  begin
    if not FileExists(NOVA_BIN) then
    begin
      error('Missing executable: <span class="bold">' + NOVA_BIN + '</span>');
      halt(1);
    end;

    ExitCode := 0;
    P := TProcess.Create(nil);
    try
      try
        P.Executable := NOVA_BIN;

        for i := 1 to ParamCount do
          P.Parameters.Add(ParamStr(i));

        P.Options := [];
        P.Execute;
        P.WaitOnExit;
        ExitCode := P.ExitStatus;
      except
        on E: Exception do
        begin
          error('Failed to run <span class="bold">' + NOVA_BIN + '</span>: <i>' + E.Message + '</i>');
          P.Free;
          halt(1);
        end;
      end;
    finally
      P.Free;
    end;
  end;

begin
  try
    ExtractUpdate;
    ShowMessage;

    RunNova;
  except
    on E: Exception do
    begin
      error('Unexpected fatal error: <i>' + E.Message + '</i>');
      halt(1);
    end;
  end;
end.
