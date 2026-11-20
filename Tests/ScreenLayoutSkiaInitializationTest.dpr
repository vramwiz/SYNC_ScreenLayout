program ScreenLayoutSkiaInitializationTest;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.IOUtils,
  TextRendererSkiaRuntime in '..\Lib\TextRenderer\TextRendererSkiaRuntime.pas',
  TextRendererSkiaBootstrap in '..\Lib\TextRenderer\TextRendererSkiaBootstrap.pas';

var
  MissingFile: string;
  Failed: Boolean;
begin
  try
    MissingFile := TPath.Combine(TPath.GetTempPath,
      TPath.GetRandomFileName + '\missing-sk4d.dll');
    Failed := False;
    try
      TTextRendererSkiaRuntime.Acquire(MissingFile);
    except
      on E: EOSError do
      begin
        Failed := True;
        if (Pos(MissingFile, E.Message) = 0) or
          (Pos('LoadLibrary', E.Message) = 0) or
          (Pos('126 (0x0000007E)', E.Message) = 0) then
          raise Exception.Create('Missing DLL diagnostic lacks path, stage or error code');
      end;
    end;
    if not Failed or TTextRendererSkiaRuntime.IsAcquired then
      raise Exception.Create('Failed acquisition retained runtime state');
    // A failed load must not prevent a later successful load and unload.
    TTextRendererSkiaRuntime.Acquire(BundledSkiaRuntimeFileName);
    try
      if not TTextRendererSkiaRuntime.IsAcquired then
        raise Exception.Create('Runtime was not acquired');
    finally
      TTextRendererSkiaRuntime.Release;
    end;
    if TTextRendererSkiaRuntime.IsAcquired then
      raise Exception.Create('Runtime was not released');
    Writeln('PASS: missing DLL diagnostic and recovery');
  except
    on E: Exception do
    begin
      Writeln(E.ClassName, ': ', E.Message);
      ExitCode := 1;
    end;
  end;
end.
