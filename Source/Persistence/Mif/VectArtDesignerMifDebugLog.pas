// Debugビルドで開いたMIFの外側チャンクとPNGメタデータを記録し、
// 他アプリとの読込互換性を調査するためのログを生成する。
unit VectArtDesignerMifDebugLog;

interface

uses
  VectArtDesignerMifContainer;

// Containerを所有せず、元MIFの隣へ解析ログを書き、成功時はログの絶対パスを返す。
function WriteMifOpenDebugLog(const MifFileName: string;
  Container: TVectArtMifContainer; const DocumentImportError: string): string;

implementation

uses
  System.Classes, System.DateUtils, System.IOUtils, System.Math,
  System.SysUtils;

function ReadUInt32BE(const Bytes: TBytes; Offset: Integer): UInt32;
begin
  Result := (UInt32(Bytes[Offset]) shl 24) or
    (UInt32(Bytes[Offset + 1]) shl 16) or
    (UInt32(Bytes[Offset + 2]) shl 8) or UInt32(Bytes[Offset + 3]);
end;

function ReadInt32BE(const Bytes: TBytes; Offset: Integer): Int32;
begin
  Result := Int32(ReadUInt32BE(Bytes, Offset));
end;

function ReadAscii(const Bytes: TBytes; Offset, Count: Integer): string;
var
  I: Integer;
begin
  SetLength(Result, Count);
  for I := 0 to Count - 1 do
    Result[I + 1] := Char(Bytes[Offset + I]);
end;

function BytesAsHex(const Bytes: TBytes; Offset, Count: Integer): string;
var
  I: Integer;
begin
  Result := '';
  for I := 0 to Count - 1 do
  begin
    if I > 0 then
      Result := Result + ' ';
    Result := Result + IntToHex(Bytes[Offset + I], 2);
  end;
end;

function Crc32(const Bytes: TBytes; Offset, Count: Integer): UInt32;
var
  BitIndex: Integer;
  I: Integer;
begin
  Result := $FFFFFFFF;
  for I := 0 to Count - 1 do
  begin
    Result := Result xor Bytes[Offset + I];
    for BitIndex := 0 to 7 do
      if (Result and 1) <> 0 then
        Result := (Result shr 1) xor $EDB88320
      else
        Result := Result shr 1;
  end;
  Result := not Result;
end;

function IsPng(const Bytes: TBytes): Boolean;
begin
  Result := (Length(Bytes) >= 8) and
    (BytesAsHex(Bytes, 0, 8) = '89 50 4E 47 0D 0A 1A 0A');
end;

function DecodeUtf8OrMarker(const Bytes: TBytes; Offset,
  Count: Integer): string;
begin
  if Count = 0 then
    Exit('');
  if not TEncoding.UTF8.IsBufferValid(@Bytes[Offset], Count) then
    Exit('<non-UTF8>');
  Result := TEncoding.UTF8.GetString(Bytes, Offset, Count);
  Result := StringReplace(Result, #13, '\r', [rfReplaceAll]);
  Result := StringReplace(Result, #10, '\n', [rfReplaceAll]);
  Result := StringReplace(Result, #9, '\t', [rfReplaceAll]);
end;

procedure WriteMetadata(Writer: TStreamWriter; const Bytes: TBytes;
  ChunkType: string; DataOffset, DataLength: Integer);
var
  Key: string;
  NullOffset: Integer;
  ValueCount: Integer;
  ValueOffset: Integer;
begin
  if (ChunkType <> 'tEXt') and (ChunkType <> 'waDA') then
    Exit;
  NullOffset := DataOffset;
  while (NullOffset < DataOffset + DataLength) and
    (Bytes[NullOffset] <> 0) do
    Inc(NullOffset);
  if NullOffset >= DataOffset + DataLength then
  begin
    Writer.WriteLine('      metadata: NUL separator missing');
    Exit;
  end;
  Key := ReadAscii(Bytes, DataOffset, NullOffset - DataOffset);
  ValueOffset := NullOffset + 1;
  ValueCount := DataOffset + DataLength - ValueOffset;
  if ChunkType = 'waDA' then
    Key := 'waDA' + Key;
  Writer.WriteLine('      key: ' + Key);
  Writer.WriteLine('      value bytes: ' + IntToStr(ValueCount));
  if ValueCount = 4 then
    Writer.WriteLine(Format('      int32-be: %d (0x%s)',
      [ReadInt32BE(Bytes, ValueOffset),
       BytesAsHex(Bytes, ValueOffset, ValueCount)]))
  else
  begin
    Writer.WriteLine('      text: ' +
      DecodeUtf8OrMarker(Bytes, ValueOffset, ValueCount));
    Writer.WriteLine('      hex: ' +
      BytesAsHex(Bytes, ValueOffset, Min(ValueCount, 256)));
    if ValueCount > 256 then
      Writer.WriteLine('      hex truncated: true');
  end;
end;

procedure WritePng(Writer: TStreamWriter; const Bytes: TBytes;
  PngIndex: Integer);
var
  ChunkCrc: UInt32;
  ChunkLength: UInt32;
  ChunkType: string;
  ComputedCrc: UInt32;
  DataOffset: Integer;
  Offset: Integer;
begin
  Writer.WriteLine(Format('  PNG[%d]: bytes=%d signature=%s',
    [PngIndex, Length(Bytes), BoolToStr(IsPng(Bytes), True)]));
  if not IsPng(Bytes) then
    Exit;
  Offset := 8;
  while Offset < Length(Bytes) do
  begin
    if Length(Bytes) - Offset < 12 then
    begin
      Writer.WriteLine('    ERROR: incomplete PNG chunk header');
      Exit;
    end;
    ChunkLength := ReadUInt32BE(Bytes, Offset);
    if (ChunkLength > UInt32(High(Integer))) or
      (Int64(ChunkLength) + 12 > Length(Bytes) - Offset) then
    begin
      Writer.WriteLine('    ERROR: PNG chunk exceeds boundary');
      Exit;
    end;
    ChunkType := ReadAscii(Bytes, Offset + 4, 4);
    DataOffset := Offset + 8;
    ChunkCrc := ReadUInt32BE(Bytes, DataOffset + Integer(ChunkLength));
    ComputedCrc := Crc32(Bytes, Offset + 4, Integer(ChunkLength) + 4);
    Writer.WriteLine(Format('    offset=0x%s type=%s data=%d crc=%s',
      [IntToHex(Offset, 8), ChunkType, ChunkLength,
       BoolToStr(ChunkCrc = ComputedCrc, True)]));
    if (ChunkType = 'IHDR') and (ChunkLength = 13) then
      Writer.WriteLine(Format('      size: %d x %d bitDepth=%d colorType=%d',
        [ReadUInt32BE(Bytes, DataOffset),
         ReadUInt32BE(Bytes, DataOffset + 4), Bytes[DataOffset + 8],
         Bytes[DataOffset + 9]]));
    WriteMetadata(Writer, Bytes, ChunkType, DataOffset,
      Integer(ChunkLength));
    Inc(Offset, Integer(ChunkLength) + 12);
  end;
end;

function WriteMifOpenDebugLog(const MifFileName: string;
  Container: TVectArtMifContainer; const DocumentImportError: string): string;
var
  I: Integer;
  PngIndex: Integer;
  Writer: TStreamWriter;
begin
  Result := '';
  if Container = nil then
    Exit;
  try
    Result := ExpandFileName(MifFileName + '.open.log');
    Writer := TStreamWriter.Create(Result, False, TEncoding.UTF8);
    try
      Writer.WriteLine('# VectArtDesigner MIF open debug log');
      Writer.WriteLine('time: ' + DateToISO8601(Now, False));
      Writer.WriteLine('file: ' + ExpandFileName(MifFileName));
      if TFile.Exists(MifFileName) then
        Writer.WriteLine('file bytes: ' +
          IntToStr(TFile.GetSize(MifFileName)));
      Writer.WriteLine('outer chunks: ' + IntToStr(Container.ChunkCount));
      if DocumentImportError = '' then
        Writer.WriteLine('document import: SUCCESS')
      else
        Writer.WriteLine('document import: FAILED - ' + DocumentImportError);
      Writer.WriteLine;
      PngIndex := 0;
      for I := 0 to Container.ChunkCount - 1 do
      begin
        Writer.WriteLine(Format('Chunk[%d]: tag=%s data=%d',
          [I, string(Container[I].Tag), Length(Container[I].Data)]));
        if Container[I].Tag = 'IPNG' then
        begin
          WritePng(Writer, Container[I].Data, PngIndex);
          Inc(PngIndex);
        end;
      end;
    finally
      Writer.Free;
    end;
  except
    Result := '';
  end;
end;

end.
