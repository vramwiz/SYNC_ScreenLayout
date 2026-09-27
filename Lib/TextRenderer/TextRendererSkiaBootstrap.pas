// EXE／DLLと同じ配布単位にあるSkiaランタイムのパスを解決する。
unit TextRendererSkiaBootstrap;

interface

// このユニットを含むEXEまたはDLLと同じ場所のSkiaランタイムを返す。
function BundledSkiaRuntimeFileName: string;

implementation

uses
  System.SysUtils,
  Winapi.Windows;

function ModuleDirectory: string;
var
  Buffer: array[0..32767] of Char;
  ModuleHandle: HMODULE;
  PathLength: DWORD;
begin
  if IsLibrary then
    ModuleHandle := HInstance
  else
    ModuleHandle := GetModuleHandle(nil);
  PathLength := GetModuleFileName(ModuleHandle, Buffer, Length(Buffer));
  if PathLength = 0 then
    RaiseLastOSError;
  if PathLength >= DWORD(Length(Buffer)) then
    raise EPathTooLongException.Create('The plugin path is too long');
  SetString(Result, Buffer, PathLength);
  Result := ExtractFilePath(Result);
end;

function BundledSkiaRuntimeFileName: string;
var
  Candidate: string;
  ModulePath: string;
begin
  ModulePath := ModuleDirectory;
  Result := ModulePath + 'sk4d.dll';
  if FileExists(Result) then
    Exit;

  // DPR単体実行やビルド後コピー前のデバッグでは、ソースツリー内を使用する。
  Candidate := ExpandFileName(ModulePath + 'Lib\Skia\Win64\sk4d.dll');
  if FileExists(Candidate) then
    Exit(Candidate);
  Candidate := ExpandFileName(ModulePath +
    '..\..\..\Lib\Skia\Win64\sk4d.dll');
  if FileExists(Candidate) then
    Exit(Candidate);
  Candidate := ExpandFileName(GetCurrentDir +
    '\Lib\Skia\Win64\sk4d.dll');
  if FileExists(Candidate) then
    Result := Candidate;
end;

end.
