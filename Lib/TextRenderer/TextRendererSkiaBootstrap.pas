unit TextRendererSkiaBootstrap;

interface

// このユニットを含むEXEまたはDLLと同じ場所のSkiaランタイムを返す。
function BundledSkiaRuntimeFileName: string;

implementation

uses
  System.SysUtils,
  Winapi.Windows;

var
  BootstrapLibraryHandle: HMODULE;

function ModuleDirectory: string;
var
  Buffer: array[0..32767] of Char;
  PathLength: DWORD;
begin
  PathLength := GetModuleFileName(HInstance, Buffer, Length(Buffer));
  if PathLength = 0 then
    RaiseLastOSError;
  if PathLength >= DWORD(Length(Buffer)) then
    raise EPathTooLongException.Create('The plugin path is too long');
  SetString(Result, Buffer, PathLength);
  Result := ExtractFilePath(Result);
end;

procedure LoadBundledSkiaRuntime;
begin
  BootstrapLibraryHandle := LoadLibrary(PChar(BundledSkiaRuntimeFileName));
  if BootstrapLibraryHandle = 0 then
    raise EOSError.CreateFmt('Cannot load Skia runtime: %s (error %d)',
      [BundledSkiaRuntimeFileName, GetLastError]);
end;

function BundledSkiaRuntimeFileName: string;
begin
  Result := ModuleDirectory + 'sk4d.dll';
end;

initialization
  LoadBundledSkiaRuntime;

finalization
  if BootstrapLibraryHandle <> 0 then
    FreeLibrary(BootstrapLibraryHandle);

end.
