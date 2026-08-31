// DocumentとIBM WebArt Designer互換MIFの相互変換、および書出し互換性の判定を担当する。
// MIF保存では独自情報を出力せず、読み込み元の互換用ベクター情報を可能な範囲で再利用する。
unit VectArtDesignerMifDocument;

interface

uses
  System.SysUtils, VectArtDesignerDocument, VectArtDesignerMifContainer;

type
  TMifExportCompatibility = (mecExact, mecNeedsConfirmation, mecUnsupported);
  TMifExportIssueKind = (meikConversion, meikUnsupported, meikUnchecked);

  TMifExportIssue = record
    Kind: TMifExportIssueKind; // 変換、非対応、未判定の区分。
    LayerIndex: Integer;      // Document内の対象レイヤー位置。
    LayerName: string;        // 確認画面へ表示するレイヤー名。
    MessageText: string;      // 実際に行う変換または保存できない内容。
  end;

  TMifExportReport = record
    Compatibility: TMifExportCompatibility; // MIF生成全体の判定結果。
    Issues: TArray<TMifExportIssue>;         // 生成処理が検出した注意事項。
    procedure AddIssue(AKind: TMifExportIssueKind; ALayerIndex: Integer;
      const ALayerName, AMessageText: string);
    procedure Clear;
    function ToDisplayText: string;
  end;

// MIF内容をDocumentへ適用してMIF互換編集モードにする。両引数を所有しない。
function TryLoadVectArtDocumentFromMif(Container: TVectArtMifContainer;
  Document: TVectArtDocument; out ErrorMessage: string): Boolean;
// 現在のDocumentから新しいMIFを生成し、成功時の所有権を呼び出し側へ渡す。
function TryCreateVectArtMifFromDocument(Document: TVectArtDocument;
  out Container: TVectArtMifContainer; out ErrorMessage: string): Boolean; overload;
// SourceContainer内のRectangle互換情報を順番に再利用してMIFを生成する。両Containerを所有しない。
function TryCreateVectArtMifFromDocument(Document: TVectArtDocument;
  SourceContainer: TVectArtMifContainer; out Container: TVectArtMifContainer;
  out ErrorMessage: string): Boolean; overload;
// MIF生成と同じ処理で互換性を判定し、生成物と注意事項を同時に返す。
function TryCreateVectArtMifFromDocument(Document: TVectArtDocument;
  SourceContainer: TVectArtMifContainer; out Container: TVectArtMifContainer;
  out Report: TMifExportReport; out ErrorMessage: string): Boolean; overload;

implementation

uses
  System.Classes, System.Generics.Collections, System.Math,
  System.NetEncoding, System.Skia, System.Types, System.UITypes,
  Vcl.Graphics, Vcl.Imaging.pngimage, Winapi.Windows,
  VectArtDesignerDocumentJson, VectArtDesignerGeometry,
  VectArtDesignerRenderer;

const
  // 旧版が埋め込んだ編集情報は読み込みだけを継続し、互換保存には出力しない。
  DOCUMENT_TEXT_KEY = 'VectArtDesigner document';
  // WebArt Designer 7が四角形用に生成した76x1のvector IPNGをそのまま使用する。
  RECTANGLE_VECTOR_PNG_BASE64 =
    'iVBORw0KGgoAAAANSUhEUgAAAEwAAAABCAYAAAB0UUiZAAAACXBIWXMAAAsSAAALEgHS3X78' +
    'AAAAEnRFWHRvYmplY3QgdHlwZQB2ZWN0b3KhamnfAAAAPUlEQVR4nGNgYGBlYGBgZACBGA' +
    'cGBxAdBaWJA0wMfwPO/S+S/0+R3l8L5/zPjP9Pkl4QALmZdL3MxCtFAwBmBRfKcYTSHQAA' +
    'AABJRU5ErkJggg==';
  LINE_VECTOR_PNG_BASE64 =
    'iVBORw0KGgoAAAANSUhEUgAAAB8AAAABCAYAAAAmcnXSAAAACXBIWXMAAAsSAAALEgHS3X78' +
    'AAAAEnRFWHRvYmplY3QgdHlwZQB2ZWN0b3KhamnfAAAALklEQVR4nGNgYGBiYGBgZACBrg' +
    'YGBxBd4wChiQNMYHLCGwaH0NCw0JqjoUTrBQDb9wczCnO/awAAAABJRU5ErkJggg==';
  PNG_SIGNATURE: array[0..7] of Byte =
    ($89, $50, $4E, $47, $0D, $0A, $1A, $0A);

{ TMifExportReport }

procedure TMifExportReport.AddIssue(AKind: TMifExportIssueKind;
  ALayerIndex: Integer; const ALayerName, AMessageText: string);
var
  IssueIndex: Integer;
begin
  IssueIndex := Length(Issues);
  SetLength(Issues, IssueIndex + 1);
  Issues[IssueIndex].Kind := AKind;
  Issues[IssueIndex].LayerIndex := ALayerIndex;
  Issues[IssueIndex].LayerName := ALayerName;
  Issues[IssueIndex].MessageText := AMessageText;
  if AKind = meikUnsupported then
    Compatibility := mecUnsupported
  else if Compatibility = mecExact then
    Compatibility := mecNeedsConfirmation;
end;

procedure TMifExportReport.Clear;
begin
  Compatibility := mecExact;
  Issues := nil;
end;

function TMifExportReport.ToDisplayText: string;
const
  ISSUE_PREFIXES: array[TMifExportIssueKind] of string =
    ('変換', '非対応', '未判定');
var
  I: Integer;
  LayerText: string;
begin
  if Length(Issues) = 0 then
    Exit('MIFへ変換なしで書き出せます。');
  Result := '';
  for I := 0 to High(Issues) do
  begin
    if Issues[I].LayerName <> '' then
      LayerText := Format('「%s」', [Issues[I].LayerName])
    else
      LayerText := Format('レイヤー%d', [Issues[I].LayerIndex]);
    if Result <> '' then
      Result := Result + sLineBreak;
    Result := Result + Format('・[%s] %s: %s',
      [ISSUE_PREFIXES[Issues[I].Kind], LayerText, Issues[I].MessageText]);
  end;
end;

type
  TMifPathExportShape = (mpesUnsupported, mpesLine, mpesPath);

  TRectangleMifSource = record
    OriginalLeft: Integer;       // ベクターペイロードが使用する基準矩形の左端
    OriginalTop: Integer;        // ベクターペイロードが使用する基準矩形の上端
    OriginalRight: Integer;      // ベクターペイロードが使用する基準矩形の右端
    OriginalBottom: Integer;     // ベクターペイロードが使用する基準矩形の下端
    StrokeEnabled: Boolean;      // 元オブジェクトのストロークテクスチャ有効状態
    VectorPng: TBytes;           // 元オブジェクトのWebArtベクターペイロード
    StrokeTexturePng: TBytes;    // 元オブジェクトのストロークテクスチャ
    Valid: Boolean;              // 基準座標とペイロードを安全に再利用できる場合True
  end;

function ReadUInt32BE(const Bytes: TBytes; Offset: Integer): UInt32;
begin
  Result := (UInt32(Bytes[Offset]) shl 24) or
    (UInt32(Bytes[Offset + 1]) shl 16) or
    (UInt32(Bytes[Offset + 2]) shl 8) or UInt32(Bytes[Offset + 3]);
end;

function ReadDoubleBE(const Bytes: TBytes; Offset: Integer): Double;
var
  Bits: UInt64;
  I: Integer;
begin
  Bits := 0;
  for I := 0 to 7 do
    Bits := (Bits shl 8) or Bytes[Offset + I];
  Move(Bits, Result, SizeOf(Result));
end;

procedure WriteUInt32BE(var Bytes: TBytes; Offset: Integer; Value: UInt32);
begin
  Bytes[Offset] := Byte(Value shr 24);
  Bytes[Offset + 1] := Byte(Value shr 16);
  Bytes[Offset + 2] := Byte(Value shr 8);
  Bytes[Offset + 3] := Byte(Value);
end;

procedure WriteDoubleBE(var Bytes: TBytes; Offset: Integer; Value: Double);
var
  Bits: UInt64;
  I: Integer;
begin
  Move(Value, Bits, SizeOf(Bits));
  for I := 0 to 7 do
    Bytes[Offset + I] := Byte(Bits shr ((7 - I) * 8));
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
var
  I: Integer;
begin
  if Length(Bytes) < SizeOf(PNG_SIGNATURE) then
    Exit(False);
  for I := Low(PNG_SIGNATURE) to High(PNG_SIGNATURE) do
    if Bytes[I] <> PNG_SIGNATURE[I] then
      Exit(False);
  Result := True;
end;

function RemovePngChunk(const Png: TBytes;
  const RemovedChunkType: AnsiString): TBytes;
var
  ChunkLength: UInt32;
  ChunkType: AnsiString;
  Offset: Integer;
  Output: TMemoryStream;
  TotalLength: Integer;
begin
  if not IsPng(Png) then
    Exit(Copy(Png));
  Output := TMemoryStream.Create;
  try
    Output.WriteBuffer(Png[0], SizeOf(PNG_SIGNATURE));
    Offset := SizeOf(PNG_SIGNATURE);
    while Offset + 12 <= Length(Png) do
    begin
      ChunkLength := ReadUInt32BE(Png, Offset);
      if (ChunkLength > UInt32(High(Integer))) or
        (Int64(Offset) + ChunkLength + 12 > Length(Png)) then
        Exit(Copy(Png));
      TotalLength := Integer(ChunkLength) + 12;
      SetLength(ChunkType, 4);
      Move(Png[Offset + 4], ChunkType[1], 4);
      if ChunkType <> RemovedChunkType then
        Output.WriteBuffer(Png[Offset], TotalLength);
      Inc(Offset, TotalLength);
    end;
    if Offset <> Length(Png) then
      Exit(Copy(Png));
    SetLength(Result, Output.Size);
    if Output.Size > 0 then
    begin
      Output.Position := 0;
      Output.ReadBuffer(Result[0], Output.Size);
    end;
  finally
    Output.Free;
  end;
end;

function RemovePngMetadataKey(const Png: TBytes;
  const RemovedChunkType: AnsiString; const RemovedKey: string): TBytes;
var
  ChunkLength: UInt32;
  ChunkType: AnsiString;
  DataOffset: Integer;
  Key: string;
  NullOffset: Integer;
  Offset: Integer;
  Output: TMemoryStream;
  RemoveChunk: Boolean;
  TotalLength: Integer;
begin
  if not IsPng(Png) then
    Exit(Copy(Png));
  Output := TMemoryStream.Create;
  try
    Output.WriteBuffer(Png[0], SizeOf(PNG_SIGNATURE));
    Offset := SizeOf(PNG_SIGNATURE);
    while Offset + 12 <= Length(Png) do
    begin
      ChunkLength := ReadUInt32BE(Png, Offset);
      if (ChunkLength > UInt32(High(Integer))) or
        (Int64(Offset) + ChunkLength + 12 > Length(Png)) then
        Exit(Copy(Png));
      TotalLength := Integer(ChunkLength) + 12;
      SetLength(ChunkType, 4);
      Move(Png[Offset + 4], ChunkType[1], 4);
      RemoveChunk := False;
      if ChunkType = RemovedChunkType then
      begin
        DataOffset := Offset + 8;
        NullOffset := DataOffset;
        while (NullOffset < DataOffset + Integer(ChunkLength)) and
          (Png[NullOffset] <> 0) do
          Inc(NullOffset);
        if NullOffset < DataOffset + Integer(ChunkLength) then
        begin
          Key := TEncoding.ASCII.GetString(Png, DataOffset,
            NullOffset - DataOffset);
          RemoveChunk := Key = RemovedKey;
        end;
      end;
      if not RemoveChunk then
        Output.WriteBuffer(Png[Offset], TotalLength);
      Inc(Offset, TotalLength);
    end;
    if Offset <> Length(Png) then
      Exit(Copy(Png));
    SetLength(Result, Output.Size);
    if Output.Size > 0 then
    begin
      Output.Position := 0;
      Output.ReadBuffer(Result[0], Output.Size);
    end;
  finally
    Output.Free;
  end;
end;

function MakePngChunk(const ChunkType: AnsiString;
  const Data: TBytes): TBytes;
var
  I: Integer;
begin
  if Length(ChunkType) <> 4 then
    raise EArgumentException.Create('PNG chunk type must contain four bytes');
  SetLength(Result, Length(Data) + 12);
  WriteUInt32BE(Result, 0, UInt32(Length(Data)));
  for I := 1 to 4 do
    Result[3 + I] := Byte(ChunkType[I]);
  if Length(Data) > 0 then
    Move(Data[0], Result[8], Length(Data));
  WriteUInt32BE(Result, Length(Result) - 4,
    Crc32(Result, 4, Length(Data) + 4));
end;

function FindPngMetadataInsertOffset(const Png: TBytes): Integer;
var
  ChunkLength: UInt32;
  Offset: Integer;
begin
  Result := -1;
  if not IsPng(Png) then
    Exit;
  Offset := 8;
  while Offset + 12 <= Length(Png) do
  begin
    ChunkLength := ReadUInt32BE(Png, Offset);
    if (ChunkLength > UInt32(High(Integer))) or
      (Int64(Offset) + ChunkLength + 12 > Length(Png)) then
      Exit;
    if ((Png[Offset + 4] = Ord('I')) and
        (Png[Offset + 5] = Ord('D')) and
        (Png[Offset + 6] = Ord('A')) and
        (Png[Offset + 7] = Ord('T'))) or
       ((Png[Offset + 4] = Ord('I')) and
        (Png[Offset + 5] = Ord('E')) and
        (Png[Offset + 6] = Ord('N')) and
        (Png[Offset + 7] = Ord('D'))) then
      Exit(Offset);
    Inc(Offset, Integer(ChunkLength) + 12);
  end;
end;

procedure InsertPngMetadataChunk(var Png: TBytes;
  const ChunkType: AnsiString; const Data: TBytes);
var
  Chunk: TBytes;
  InsertOffset: Integer;
  TailLength: Integer;
begin
  InsertOffset := FindPngMetadataInsertOffset(Png);
  if InsertOffset < 0 then
    raise EWriteError.Create('PNG IDAT or IEND chunk is missing');
  Chunk := MakePngChunk(ChunkType, Data);
  TailLength := Length(Png) - InsertOffset;
  SetLength(Png, Length(Png) + Length(Chunk));
  Move(Png[InsertOffset], Png[InsertOffset + Length(Chunk)], TailLength);
  Move(Chunk[0], Png[InsertOffset], Length(Chunk));
end;

function TextChunkData(const Key, Value: string): TBytes;
begin
  Result := TEncoding.UTF8.GetBytes(Key + #0 + Value);
end;

function WadaIntegerData(const Key: string; Value: Int32): TBytes;
var
  KeyBytes: TBytes;
begin
  KeyBytes := TEncoding.ASCII.GetBytes(Key);
  SetLength(Result, Length(KeyBytes) + 5);
  if Length(KeyBytes) > 0 then
    Move(KeyBytes[0], Result[0], Length(KeyBytes));
  Result[Length(KeyBytes)] := 0;
  WriteUInt32BE(Result, Length(KeyBytes) + 1, UInt32(Value));
end;

function WadaDoubleData(const Key: string; Value: Double): TBytes;
var
  KeyBytes: TBytes;
begin
  KeyBytes := TEncoding.ASCII.GetBytes(Key);
  SetLength(Result, Length(KeyBytes) + 9);
  if Length(KeyBytes) > 0 then
    Move(KeyBytes[0], Result[0], Length(KeyBytes));
  Result[Length(KeyBytes)] := 0;
  WriteDoubleBE(Result, Length(KeyBytes) + 1, Value);
end;

function WadaStringData(const Key, Value: string): TBytes;
var
  KeyBytes: TBytes;
  ValueBytes: TBytes;
begin
  KeyBytes := TEncoding.ASCII.GetBytes(Key);
  ValueBytes := TEncoding.UTF8.GetBytes(Value);
  SetLength(Result, Length(KeyBytes) + Length(ValueBytes) + 1);
  if Length(KeyBytes) > 0 then
    Move(KeyBytes[0], Result[0], Length(KeyBytes));
  Result[Length(KeyBytes)] := 0;
  if Length(ValueBytes) > 0 then
    Move(ValueBytes[0], Result[Length(KeyBytes) + 1], Length(ValueBytes));
end;

procedure AddText(var Png: TBytes; const Key, Value: string);
begin
  InsertPngMetadataChunk(Png, 'tEXt', TextChunkData(Key, Value));
end;

procedure AddWadaInteger(var Png: TBytes; const Key: string; Value: Int32);
begin
  InsertPngMetadataChunk(Png, 'waDA', WadaIntegerData(Key, Value));
end;

procedure AddWadaDouble(var Png: TBytes; const Key: string; Value: Double);
begin
  InsertPngMetadataChunk(Png, 'waDA', WadaDoubleData(Key, Value));
end;

procedure AddWadaString(var Png: TBytes; const Key, Value: string);
begin
  InsertPngMetadataChunk(Png, 'waDA', WadaStringData(Key, Value));
end;

procedure UpdateWadaInteger(var Png: TBytes; const Key: string;
  Value: Int32);
var
  ChunkLength: UInt32;
  DataOffset: Integer;
  ExistingKey: string;
  NullOffset: Integer;
  Offset: Integer;
begin
  if IsPng(Png) then
  begin
    Offset := SizeOf(PNG_SIGNATURE);
    while Offset + 12 <= Length(Png) do
    begin
      ChunkLength := ReadUInt32BE(Png, Offset);
      if (ChunkLength > UInt32(High(Integer))) or
        (Int64(Offset) + ChunkLength + 12 > Length(Png)) then
        Break;
      if TEncoding.ASCII.GetString(Png, Offset + 4, 4) = 'waDA' then
      begin
        DataOffset := Offset + 8;
        NullOffset := DataOffset;
        while (NullOffset < DataOffset + Integer(ChunkLength)) and
          (Png[NullOffset] <> 0) do
          Inc(NullOffset);
        if (NullOffset + 5 = DataOffset + Integer(ChunkLength)) then
        begin
          ExistingKey := TEncoding.ASCII.GetString(Png, DataOffset,
            NullOffset - DataOffset);
          if ExistingKey = Key then
          begin
            WriteUInt32BE(Png, NullOffset + 1, UInt32(Value));
            WriteUInt32BE(Png, DataOffset + Integer(ChunkLength),
              Crc32(Png, Offset + 4, Integer(ChunkLength) + 4));
            Exit;
          end;
        end;
      end;
      Inc(Offset, Integer(ChunkLength) + 12);
    end;
  end;
  AddWadaInteger(Png, Key, Value);
end;

procedure AddPhysicalDimensions(var Png: TBytes);
var
  Data: TBytes;
begin
  SetLength(Data, 9);
  WriteUInt32BE(Data, 0, 2834);
  WriteUInt32BE(Data, 4, 2834);
  Data[8] := 1;
  InsertPngMetadataChunk(Png, 'pHYs', Data);
end;

function EncodeRgba(const Pixels: Pointer; Width, Height: Integer): TBytes;
var
  ImageInfo: TSkImageInfo;
begin
  ImageInfo := TSkImageInfo.Create(Width, Height, TSkColorType.RGBA8888,
    TSkAlphaType.Unpremul);
  Result := TSkImageEncoder.Encode(ImageInfo, Pixels,
    NativeUInt(Width) * SizeOf(TVectArtRgbaPixel), TSkEncodedImageFormat.PNG);
  if Length(Result) = 0 then
    raise EWriteError.Create('PNG encoding failed');
  // WebArt製PNGに存在しないSkia固有のsBITは、厳密な読込側との互換性を優先して除去する。
  Result := RemovePngChunk(Result, 'sBIT');
end;

procedure CompositeCanvasBackground(Buffer: TVectArtRenderBuffer;
  Canvas: TVectArtCanvasLayer);
var
  Alpha: Cardinal;
  Background: TColor;
  BackgroundB: Cardinal;
  BackgroundG: Cardinal;
  BackgroundR: Cardinal;
  I: NativeInt;
  Pixel: PVectArtRgbaPixel;
begin
  if (Buffer = nil) or (Canvas = nil) or Canvas.Transparent then
    Exit;
  Background := ColorToRGB(Canvas.BackgroundColor);
  BackgroundR := GetRValue(Background);
  BackgroundG := GetGValue(Background);
  BackgroundB := GetBValue(Background);
  Pixel := Buffer.Data;
  for I := 0 to Buffer.PixelCount - 1 do
  begin
    Alpha := Pixel^.A;
    Pixel^.R := (Cardinal(Pixel^.R) * Alpha +
      BackgroundR * (255 - Alpha) + 127) div 255;
    Pixel^.G := (Cardinal(Pixel^.G) * Alpha +
      BackgroundG * (255 - Alpha) + 127) div 255;
    Pixel^.B := (Cardinal(Pixel^.B) * Alpha +
      BackgroundB * (255 - Alpha) + 127) div 255;
    Pixel^.A := 255;
    Inc(Pixel);
  end;
end;

function CreateCompositePng(Document: TVectArtDocument): TBytes;
var
  Buffer: TVectArtRenderBuffer;
  Canvas: TVectArtCanvasLayer;
begin
  Canvas := Document.CanvasLayer;
  Buffer := TVectArtRenderBuffer.Create;
  try
    RenderVectArtDocument(Document, Buffer, Canvas.Width, Canvas.Height);
    CompositeCanvasBackground(Buffer, Canvas);
    Result := EncodeRgba(Buffer.Data, Buffer.Width, Buffer.Height);
    AddPhysicalDimensions(Result);
    AddText(Result, 'application name', 'WebArt Designer');
    AddWadaInteger(Result, 'application version', 700);
    AddWadaInteger(Result, 'background page index', 0);
  finally
    Buffer.Free;
  end;
end;

function CreateSolidPng(Width, Height: Integer; Color: TColor): TBytes;
var
  ColorValue: TColor;
  I: Integer;
  Pixels: TArray<TVectArtRgbaPixel>;
begin
  Width := EnsureRange(Width, 1, 16384);
  Height := EnsureRange(Height, 1, 16384);
  SetLength(Pixels, Width * Height);
  ColorValue := ColorToRGB(Color);
  for I := 0 to High(Pixels) do
  begin
    Pixels[I].R := GetRValue(ColorValue);
    Pixels[I].G := GetGValue(ColorValue);
    Pixels[I].B := GetBValue(ColorValue);
    Pixels[I].A := 255;
  end;
  Result := EncodeRgba(@Pixels[0], Width, Height);
  AddPhysicalDimensions(Result);
end;

function CreateRectangleRasterPng(Rectangle: TVectArtRectangleLayer;
  Width, Height: Integer): TBytes;
var
  Canvas: ISkCanvas;
  DashIntervals: TArray<Single>;
  FillPaint: ISkPaint;
  ImageInfo: TSkImageInfo;
  Inset: Single;
  Pixels: TArray<TVectArtRgbaPixel>;
  RGBColor: TColor;
  StrokePaint: ISkPaint;
  Surface: ISkSurface;
begin
  Width := EnsureRange(Width, 1, 16384);
  Height := EnsureRange(Height, 1, 16384);
  SetLength(Pixels, Width * Height);
  ImageInfo := TSkImageInfo.Create(Width, Height, TSkColorType.RGBA8888,
    TSkAlphaType.Unpremul);
  Surface := TSkSurface.MakeRasterDirect(ImageInfo, @Pixels[0],
    NativeUInt(Width) * SizeOf(TVectArtRgbaPixel));
  if Surface = nil then
    raise EWriteError.Create('Cannot create rectangle PNG surface');
  Canvas := Surface.Canvas;
  Canvas.Clear(TAlphaColorRec.Null);
  FillPaint := TSkPaint.Create(TSkPaintStyle.Fill);
  FillPaint.AntiAlias := True;
  RGBColor := ColorToRGB(Rectangle.FillColor);
  FillPaint.Color := TAlphaColor($FF000000 or
    (Cardinal(GetRValue(RGBColor)) shl 16) or
    (Cardinal(GetGValue(RGBColor)) shl 8) or
    Cardinal(GetBValue(RGBColor)));
  Canvas.DrawRect(TRectF.Create(0, 0, Width, Height), FillPaint);
  if Rectangle.StrokeWidth > 0 then
  begin
    StrokePaint := TSkPaint.Create(TSkPaintStyle.Stroke);
    StrokePaint.AntiAlias := True;
    RGBColor := ColorToRGB(Rectangle.StrokeColor);
    StrokePaint.Color := TAlphaColor($FF000000 or
      (Cardinal(GetRValue(RGBColor)) shl 16) or
      (Cardinal(GetGValue(RGBColor)) shl 8) or
      Cardinal(GetBValue(RGBColor)));
    StrokePaint.StrokeWidth := Rectangle.StrokeWidth;
    DashIntervals := VectArtStrokeDashIntervals(Rectangle.MifStrokeStyle,
      Rectangle.StrokeWidth);
    if Length(DashIntervals) > 0 then
      StrokePaint.PathEffect := TSkPathEffect.MakeDash(DashIntervals, 0);
    if VectArtStrokeUsesRoundCaps(Rectangle.MifStrokeStyle) then
      StrokePaint.StrokeCap := TSkStrokeCap.Round
    else
      StrokePaint.StrokeCap := TSkStrokeCap.Butt;
    Inset := Min(Rectangle.StrokeWidth * 0.5,
      Min(Width, Height) * 0.5);
    Canvas.DrawRect(TRectF.Create(Inset, Inset, Width - Inset,
      Height - Inset), StrokePaint);
  end;
  Surface.Flush;
  Result := EncodeRgba(@Pixels[0], Width, Height);
  AddPhysicalDimensions(Result);
end;

function CreateLineRasterPng(Line: TVectArtLineLayer;
  out PlacementBounds: TRectF): TBytes;
var
  Canvas: ISkCanvas;
  DashIntervals: TArray<Single>;
  Height: Integer;
  ImageInfo: TSkImageInfo;
  MarkerGeometry: TVectArtMarkerGeometry;
  Padding: Single;
  Paint: ISkPaint;
  Pixels: TArray<TVectArtRgbaPixel>;
  RGBColor: TColor;
  Surface: ISkSurface;
  Width: Integer;

  procedure DrawMarker(Marker: TVectArtMifLineMarker; const Tip,
    InsidePoint: TPointF; MarkerSize: Single);
  var
    I: Integer;
    MarkerPathBuilder: ISkPathBuilder;
  begin
    MarkerGeometry := BuildMifLineMarkerGeometry(Ord(Marker), Tip, InsidePoint,
      Line.StrokeWidth, MarkerSize);
    if Length(MarkerGeometry.PrimaryPoints) < 2 then Exit;
    MarkerPathBuilder := TSkPathBuilder.Create;
    MarkerPathBuilder.MoveTo(MarkerGeometry.PrimaryPoints[0].X -
      PlacementBounds.Left, MarkerGeometry.PrimaryPoints[0].Y -
      PlacementBounds.Top);
    for I := 1 to High(MarkerGeometry.PrimaryPoints) do
      MarkerPathBuilder.LineTo(MarkerGeometry.PrimaryPoints[I].X -
        PlacementBounds.Left, MarkerGeometry.PrimaryPoints[I].Y -
        PlacementBounds.Top);
    if MarkerGeometry.PrimaryClosed then MarkerPathBuilder.Close;
    Paint.PathEffect := nil;
    if MarkerGeometry.Filled then
      Paint.Style := TSkPaintStyle.Fill
    else
    begin
      Paint.Style := TSkPaintStyle.Stroke;
      Paint.StrokeCap := TSkStrokeCap.Round;
      Paint.StrokeWidth := Max(Line.StrokeWidth, 0.1);
    end;
    Canvas.DrawPath(MarkerPathBuilder.Detach, Paint);
  end;
begin
  if (Line.MifStartMarker <> vlmNone) or (Line.MifEndMarker <> vlmNone) then
    Padding := Max(Max(Line.MifStartMarkerSize, Line.MifEndMarkerSize) *
      Max(Line.StrokeWidth, 2.0) + 2, 6.0)
  else
    Padding := Max(Line.StrokeWidth * 0.5 + 2, 2.0);
  PlacementBounds := TRectF.Create(Min(Line.StartPoint.X, Line.EndPoint.X) -
    Padding, Min(Line.StartPoint.Y, Line.EndPoint.Y) - Padding,
    Max(Line.StartPoint.X, Line.EndPoint.X) + Padding,
    Max(Line.StartPoint.Y, Line.EndPoint.Y) + Padding);
  Width := EnsureRange(Ceil(PlacementBounds.Width), 1, 16384);
  Height := EnsureRange(Ceil(PlacementBounds.Height), 1, 16384);
  SetLength(Pixels, Width * Height);
  ImageInfo := TSkImageInfo.Create(Width, Height, TSkColorType.RGBA8888,
    TSkAlphaType.Unpremul);
  Surface := TSkSurface.MakeRasterDirect(ImageInfo, @Pixels[0],
    NativeUInt(Width) * SizeOf(TVectArtRgbaPixel));
  if Surface = nil then
    raise EWriteError.Create('Cannot create line PNG surface');
  Canvas := Surface.Canvas;
  Canvas.Clear(TAlphaColorRec.Null);
  Paint := TSkPaint.Create(TSkPaintStyle.Stroke);
  Paint.AntiAlias := Line.MifAntiAlias;
  RGBColor := ColorToRGB(Line.StrokeColor);
  Paint.Color := TAlphaColor($FF000000 or
    (Cardinal(GetRValue(RGBColor)) shl 16) or
    (Cardinal(GetGValue(RGBColor)) shl 8) or Cardinal(GetBValue(RGBColor)));
  Paint.StrokeWidth := Line.StrokeWidth;
  DashIntervals := VectArtStrokeDashIntervals(Line.MifStrokeStyle,
    Line.StrokeWidth);
  if Length(DashIntervals) > 0 then
    Paint.PathEffect := TSkPathEffect.MakeDash(DashIntervals, 0);
  if VectArtStrokeUsesRoundCaps(Line.MifStrokeStyle) then
    Paint.StrokeCap := TSkStrokeCap.Round
  else
    case Line.LineCap of
      vlcSquare: Paint.StrokeCap := TSkStrokeCap.Square;
      vlcRound: Paint.StrokeCap := TSkStrokeCap.Round;
    else
      Paint.StrokeCap := TSkStrokeCap.Butt;
    end;
  case Line.LineJoin of
    vljBevel: Paint.StrokeJoin := TSkStrokeJoin.Bevel;
    vljRound: Paint.StrokeJoin := TSkStrokeJoin.Round;
  else
    Paint.StrokeJoin := TSkStrokeJoin.Miter;
  end;
  Canvas.DrawLine(TPointF.Create(Line.StartPoint.X - PlacementBounds.Left,
    Line.StartPoint.Y - PlacementBounds.Top), TPointF.Create(
    Line.EndPoint.X - PlacementBounds.Left,
    Line.EndPoint.Y - PlacementBounds.Top), Paint);
  DrawMarker(Line.MifStartMarker, Line.StartPoint, Line.EndPoint,
    Line.MifStartMarkerSize);
  DrawMarker(Line.MifEndMarker, Line.EndPoint, Line.StartPoint,
    Line.MifEndMarkerSize);
  Surface.Flush;
  Result := EncodeRgba(@Pixels[0], Width, Height);
  AddPhysicalDimensions(Result);
end;

function CreatePathRasterPng(PathLayer: TVectArtPathLayer;
  out PlacementBounds: TRectF): TBytes;
var
  Canvas: ISkCanvas;
  DashIntervals: TArray<Single>;
  FillPaint: ISkPaint;
  Height: Integer;
  I: Integer;
  ImageInfo: TSkImageInfo;
  Padding: Single;
  Path: ISkPath;
  PathBuilder: ISkPathBuilder;
  Pixels: TArray<TVectArtRgbaPixel>;
  RGBColor: TColor;
  StrokePaint: ISkPaint;
  Surface: ISkSurface;
  Width: Integer;
begin
  PlacementBounds := PointsBounds(PathLayer.Points);
  Padding := Max(PathLayer.StrokeWidth * 0.5 + 2, 2.0);
  PlacementBounds.Inflate(Padding, Padding);
  Width := EnsureRange(Ceil(PlacementBounds.Width), 1, 16384);
  Height := EnsureRange(Ceil(PlacementBounds.Height), 1, 16384);
  SetLength(Pixels, Width * Height);
  ImageInfo := TSkImageInfo.Create(Width, Height, TSkColorType.RGBA8888,
    TSkAlphaType.Unpremul);
  Surface := TSkSurface.MakeRasterDirect(ImageInfo, @Pixels[0],
    NativeUInt(Width) * SizeOf(TVectArtRgbaPixel));
  if Surface = nil then
    raise EWriteError.Create('Cannot create path PNG surface');
  Canvas := Surface.Canvas;
  Canvas.Clear(TAlphaColorRec.Null);
  PathBuilder := TSkPathBuilder.Create;
  PathBuilder.MoveTo(PathLayer.Points[0].X - PlacementBounds.Left,
    PathLayer.Points[0].Y - PlacementBounds.Top);
  for I := 1 to High(PathLayer.Points) do
    PathBuilder.LineTo(PathLayer.Points[I].X - PlacementBounds.Left,
      PathLayer.Points[I].Y - PlacementBounds.Top);
  if PathLayer.Closed then
    PathBuilder.Close;
  Path := PathBuilder.Detach;
  if PathLayer.Filled and PathLayer.Closed then
  begin
    FillPaint := TSkPaint.Create(TSkPaintStyle.Fill);
    FillPaint.AntiAlias := PathLayer.MifAntiAlias;
    RGBColor := ColorToRGB(PathLayer.FillColor);
    FillPaint.Color := TAlphaColor($FF000000 or
      (Cardinal(GetRValue(RGBColor)) shl 16) or
      (Cardinal(GetGValue(RGBColor)) shl 8) or Cardinal(GetBValue(RGBColor)));
    Canvas.DrawPath(Path, FillPaint);
  end;
  if PathLayer.StrokeWidth > 0 then
  begin
    StrokePaint := TSkPaint.Create(TSkPaintStyle.Stroke);
    StrokePaint.AntiAlias := PathLayer.MifAntiAlias;
    RGBColor := ColorToRGB(PathLayer.StrokeColor);
    StrokePaint.Color := TAlphaColor($FF000000 or
      (Cardinal(GetRValue(RGBColor)) shl 16) or
      (Cardinal(GetGValue(RGBColor)) shl 8) or Cardinal(GetBValue(RGBColor)));
    StrokePaint.StrokeWidth := PathLayer.StrokeWidth;
    DashIntervals := VectArtStrokeDashIntervals(PathLayer.MifStrokeStyle,
      PathLayer.StrokeWidth);
    if Length(DashIntervals) > 0 then
      StrokePaint.PathEffect := TSkPathEffect.MakeDash(DashIntervals, 0);
    if VectArtStrokeUsesRoundCaps(PathLayer.MifStrokeStyle) then
      StrokePaint.StrokeCap := TSkStrokeCap.Round
    else
      case PathLayer.LineCap of
        vlcSquare: StrokePaint.StrokeCap := TSkStrokeCap.Square;
        vlcRound: StrokePaint.StrokeCap := TSkStrokeCap.Round;
      else
        StrokePaint.StrokeCap := TSkStrokeCap.Butt;
      end;
    case PathLayer.LineJoin of
      vljBevel: StrokePaint.StrokeJoin := TSkStrokeJoin.Bevel;
      vljRound: StrokePaint.StrokeJoin := TSkStrokeJoin.Round;
    else
      StrokePaint.StrokeJoin := TSkStrokeJoin.Miter;
    end;
    Canvas.DrawPath(Path, StrokePaint);
  end;
  Surface.Flush;
  Result := EncodeRgba(@Pixels[0], Width, Height);
  AddPhysicalDimensions(Result);
end;

function MifImageCoordinate(Value: Single): Integer;
begin
  Result := Round(Value);
end;

procedure AddImagePlacementMetadata(var Png: TBytes;
  const Bounds: TRectF; Alpha: Integer; Hidden: Boolean); overload;
begin
  AddWadaInteger(Png, 'image position1 x', MifImageCoordinate(Bounds.Left));
  AddWadaInteger(Png, 'image position1 y', MifImageCoordinate(Bounds.Top));
  AddWadaInteger(Png, 'image position2 x', MifImageCoordinate(Bounds.Right));
  AddWadaInteger(Png, 'image position2 y', MifImageCoordinate(Bounds.Top));
  AddWadaInteger(Png, 'image position3 x', MifImageCoordinate(Bounds.Right));
  AddWadaInteger(Png, 'image position3 y', MifImageCoordinate(Bounds.Bottom));
  AddWadaInteger(Png, 'image position4 x', MifImageCoordinate(Bounds.Left));
  AddWadaInteger(Png, 'image position4 y', MifImageCoordinate(Bounds.Bottom));
  AddWadaInteger(Png, 'image alpha', EnsureRange(Alpha, 0, 255));
  AddWadaInteger(Png, 'image hidden', Ord(Hidden));
end;

procedure UpdateImagePlacementMetadata(var Png: TBytes;
  const Points: TVectArtImagePoints; Alpha: Integer; Hidden: Boolean);
var
  I: Integer;
begin
  for I := 0 to High(Points) do
  begin
    UpdateWadaInteger(Png, Format('image position%d x', [I + 1]),
      MifImageCoordinate(Points[I].X));
    UpdateWadaInteger(Png, Format('image position%d y', [I + 1]),
      MifImageCoordinate(Points[I].Y));
  end;
  UpdateWadaInteger(Png, 'image alpha', EnsureRange(Alpha, 0, 255));
  UpdateWadaInteger(Png, 'image hidden', Ord(Hidden));
end;

procedure AddImagePlacementMetadata(var Png: TBytes;
  const Quad: TVectArtQuad; Alpha: Integer; Hidden: Boolean); overload;
var
  I: Integer;
begin
  for I := 0 to High(Quad) do
  begin
    AddWadaInteger(Png, Format('image position%d x', [I + 1]),
      MifImageCoordinate(Quad[I].X));
    AddWadaInteger(Png, Format('image position%d y', [I + 1]),
      MifImageCoordinate(Quad[I].Y));
  end;
  AddWadaInteger(Png, 'image alpha', EnsureRange(Alpha, 0, 255));
  AddWadaInteger(Png, 'image hidden', Ord(Hidden));
end;

function CreateTexturePng(Color: TColor): TBytes;
var
  BgrColor: Int32;
begin
  Result := CreateSolidPng(64, 64, Color);
  AddText(Result, 'object type', 'texture');
  AddImagePlacementMetadata(Result, TRectF.Create(0, 0, 63, 63), 255,
    False);
  AddWadaString(Result, 'texture object type', 'color');
  BgrColor := ColorToRGB(Color);
  AddWadaInteger(Result, 'texture color1', BgrColor);
  AddWadaInteger(Result, 'texture color2', 0);
  AddWadaInteger(Result, 'texture angle', 0);
  AddWadaInteger(Result, 'texture level', 0);
  AddWadaString(Result, 'texture pathname', '@');
end;

function MifRectangleStrokeWidth(Value: Single): Double;
begin
  Result := Max(Value, 1.0);
end;

procedure AddRectangleVectorMetadata(var Png: TBytes;
  Rectangle: TVectArtRectangleLayer; Width, Height: Integer;
  const Source: TRectangleMifSource);
const
  TEMPLATE_LEFT = 113;
  TEMPLATE_TOP = 105;
  TEMPLATE_RIGHT = 289;
  TEMPLATE_BOTTOM = 202;
var
  OriginalBottom: Integer;
  OriginalLeft: Integer;
  OriginalRight: Integer;
  OriginalTop: Integer;
  PlacementBounds: TRectF;
  Quad: TVectArtQuad;
  ScaleX: Double;
  ScaleY: Double;
begin
  if Source.Valid then
  begin
    OriginalLeft := Source.OriginalLeft;
    OriginalTop := Source.OriginalTop;
    OriginalRight := Source.OriginalRight;
    OriginalBottom := Source.OriginalBottom;
  end
  else
  begin
    OriginalLeft := TEMPLATE_LEFT;
    OriginalTop := TEMPLATE_TOP;
    OriginalRight := TEMPLATE_RIGHT;
    OriginalBottom := TEMPLATE_BOTTOM;
  end;
  AddWadaInteger(Png, 'vector closed', 1);
  AddWadaInteger(Png, 'vector quality', 1);
  AddWadaInteger(Png, 'vector element type', 4);
  AddWadaInteger(Png, 'vector stroke style', Ord(Rectangle.MifStrokeStyle));
  AddWadaInteger(Png, 'vector stroke cap', 0);
  AddWadaInteger(Png, 'vector stroke join', 2);
  AddWadaInteger(Png, 'vector start stroke marker', 0);
  AddWadaInteger(Png, 'vector end stroke marker', 0);
  AddWadaInteger(Png, 'vector start marker size', 4);
  AddWadaInteger(Png, 'vector end marker size', 4);
  AddWadaDouble(Png, 'vector stroke width',
    MifRectangleStrokeWidth(Rectangle.StrokeWidth));
  ScaleX := Max(Width - 1, 0) / (OriginalRight - OriginalLeft);
  ScaleY := Max(Height - 1, 0) / (OriginalBottom - OriginalTop);
  PlacementBounds := TRectF.Create(Rectangle.Bounds.Left,
    Rectangle.Bounds.Top, Rectangle.Bounds.Left + Width - 1,
    Rectangle.Bounds.Top + Height - 1);
  Quad := RectangleCorners(PlacementBounds, Rectangle.RotationDegrees);
  AddWadaDouble(Png, 'vector matrix a',
    (Quad[1].X - Quad[0].X) / (OriginalRight - OriginalLeft));
  AddWadaDouble(Png, 'vector matrix b',
    (Quad[1].Y - Quad[0].Y) / (OriginalRight - OriginalLeft));
  AddWadaDouble(Png, 'vector matrix c',
    (Quad[3].X - Quad[0].X) / (OriginalBottom - OriginalTop));
  AddWadaDouble(Png, 'vector matrix d',
    (Quad[3].Y - Quad[0].Y) / (OriginalBottom - OriginalTop));
  AddWadaDouble(Png, 'vector matrix e', Quad[0].X -
    OriginalLeft * ScaleX * Cos(DegToRad(Rectangle.RotationDegrees)) +
    OriginalTop * ScaleY * Sin(DegToRad(Rectangle.RotationDegrees)));
  AddWadaDouble(Png, 'vector matrix f', Quad[0].Y -
    OriginalLeft * ScaleX * Sin(DegToRad(Rectangle.RotationDegrees)) -
    OriginalTop * ScaleY * Cos(DegToRad(Rectangle.RotationDegrees)));
  AddWadaInteger(Png, 'vector original position1 x', OriginalLeft);
  AddWadaInteger(Png, 'vector original position1 y', OriginalTop);
  AddWadaInteger(Png, 'vector original position2 x', OriginalRight);
  AddWadaInteger(Png, 'vector original position2 y', OriginalTop);
  AddWadaInteger(Png, 'vector original position3 x', OriginalRight);
  AddWadaInteger(Png, 'vector original position3 y', OriginalBottom);
  AddWadaInteger(Png, 'vector original position4 x', OriginalLeft);
  AddWadaInteger(Png, 'vector original position4 y', OriginalBottom);
  AddWadaInteger(Png, 'vector enable stroke texture',
    Ord(Rectangle.StrokeWidth > 0));
  AddWadaInteger(Png, 'vector enable fill texture', 1);
  AddWadaString(Png, 'vector effect object type', 'none');
end;

function MifAlpha(Opacity: Single): Integer;
begin
  Result := EnsureRange(Round(Opacity * 255), 0, 255);
end;

function MifRectangleDimension(Value: Single): Integer;
begin
  Result := Max(Round(Abs(Value)), 1);
end;

procedure AnalyzeRectangleExport(Rectangle: TVectArtRectangleLayer;
  LayerIndex, RectangleOrdinal: Integer; var Report: TMifExportReport);
var
  ExpectedName: string;
  Height: Integer;
  I: Integer;
  PlacementBounds: TRectF;
  PlacementQuad: TVectArtQuad;
  RoundedPlacement: Boolean;
  StoredOpacity: Single;
  Width: Integer;
begin
  ExpectedName := Format('Rectangle %d', [RectangleOrdinal]);
  if Rectangle.Name <> ExpectedName then
    Report.AddIssue(meikConversion, LayerIndex, Rectangle.Name,
      Format('レイヤー名はMIFへ保持されず、再読込時に「%s」になります。',
      [ExpectedName]));
  if Rectangle.Locked then
    Report.AddIssue(meikConversion, LayerIndex, Rectangle.Name,
      '編集ロックはMIFへ保持されません。');
  Width := MifRectangleDimension(Rectangle.Bounds.Width);
  Height := MifRectangleDimension(Rectangle.Bounds.Height);
  if (Rectangle.Bounds.Width < 0) or (Rectangle.Bounds.Height < 0) or
    not SameValue(Abs(Rectangle.Bounds.Width), Width, 0.000001) or
    not SameValue(Abs(Rectangle.Bounds.Height), Height, 0.000001) then
    Report.AddIssue(meikConversion, LayerIndex, Rectangle.Name,
      Format('幅と高さはMIF画像寸法の整数値%d×%dへ丸められます。',
      [Width, Height]));
  PlacementBounds := TRectF.Create(Rectangle.Bounds.Left,
    Rectangle.Bounds.Top, Rectangle.Bounds.Left + Width - 1,
    Rectangle.Bounds.Top + Height - 1);
  PlacementQuad := RectangleCorners(PlacementBounds,
    Rectangle.RotationDegrees);
  RoundedPlacement := False;
  for I := 0 to High(PlacementQuad) do
    if not SameValue(PlacementQuad[I].X,
      MifImageCoordinate(PlacementQuad[I].X), 0.000001) or
      not SameValue(PlacementQuad[I].Y,
      MifImageCoordinate(PlacementQuad[I].Y), 0.000001) then
    begin
      RoundedPlacement := True;
      Break;
    end;
  if RoundedPlacement then
    Report.AddIssue(meikConversion, LayerIndex, Rectangle.Name,
      '回転後の配置頂点はMIFの整数座標へ丸められます。');
  StoredOpacity := MifAlpha(Rectangle.Opacity) / 255.0;
  if not SameValue(Rectangle.Opacity, StoredOpacity, 0.000001) then
    Report.AddIssue(meikConversion, LayerIndex, Rectangle.Name,
      Format('不透明度はMIFの8bit値%dへ丸められます。',
      [MifAlpha(Rectangle.Opacity)]));
  if (Rectangle.StrokeWidth > 0) and not SameValue(Rectangle.StrokeWidth,
    MifRectangleStrokeWidth(Rectangle.StrokeWidth), 0.000001) then
    Report.AddIssue(meikConversion, LayerIndex, Rectangle.Name,
      '1未満の線幅はMIFでは1へ変換されます。')
  else if Rectangle.StrokeWidth < 0 then
    Report.AddIssue(meikConversion, LayerIndex, Rectangle.Name,
      '負の線幅はMIFでは線なしとして扱われます。');
end;

function CreateRectangleVectorPng(const Source: TRectangleMifSource): TBytes;
begin
  if Source.Valid then
    Result := Copy(Source.VectorPng)
  else
    Result := TNetEncoding.Base64.DecodeStringToBytes(
      RECTANGLE_VECTOR_PNG_BASE64);
  Result := RemovePngChunk(Result, 'sBIT');
end;

function CreateRectangleImagePng(Rectangle: TVectArtRectangleLayer;
  const Source: TRectangleMifSource): TBytes;
var
  Height: Integer;
  PlacementBounds: TRectF;
  PlacementQuad: TVectArtQuad;
  Width: Integer;
begin
  Width := MifRectangleDimension(Rectangle.Bounds.Width);
  Height := MifRectangleDimension(Rectangle.Bounds.Height);
  Result := CreateRectangleRasterPng(Rectangle, Width, Height);
  AddText(Result, 'object type', 'image');
  AddWadaString(Result, 'object subtype', 'vector');
  // WebArtの四隅座標はPNGの最終ピクセルを指すため、右端と下端は包含座標へ直す。
  PlacementBounds := TRectF.Create(Rectangle.Bounds.Left,
    Rectangle.Bounds.Top, Rectangle.Bounds.Left + Width - 1,
    Rectangle.Bounds.Top + Height - 1);
  PlacementQuad := RectangleCorners(PlacementBounds,
    Rectangle.RotationDegrees);
  AddImagePlacementMetadata(Result, PlacementQuad,
    MifAlpha(Rectangle.Opacity), not Rectangle.Visible);
  AddRectangleVectorMetadata(Result, Rectangle, Width, Height, Source);
end;

function CreateLineVectorPng: TBytes;
begin
  Result := TNetEncoding.Base64.DecodeStringToBytes(LINE_VECTOR_PNG_BASE64);
  Result := RemovePngChunk(Result, 'sBIT');
end;

function CreatePathVectorPng(PathLayer: TVectArtPathLayer): TBytes;
const
  RECORD_SIZE = 60;
var
  Command: UInt32;
  Count: UInt32;
  I: Integer;
  Offset: Integer;
  Pixels: TArray<TVectArtRgbaPixel>;
  Raw: TBytes;
  X: Double;
  Y: Double;
begin
  Count := Length(PathLayer.Points) + Ord(PathLayer.Closed);
  SetLength(Raw, 4 + Integer(Count) * RECORD_SIZE);
  Move(Count, Raw[0], SizeOf(Count));
  for I := 0 to High(PathLayer.Points) do
  begin
    Offset := 4 + I * RECORD_SIZE;
    if I = 0 then
      Command := 1
    else
      Command := 2;
    Move(Command, Raw[Offset], SizeOf(Command));
    X := PathLayer.Points[I].X;
    Y := PathLayer.Points[I].Y;
    Move(X, Raw[Offset + 4], SizeOf(X));
    Move(Y, Raw[Offset + 12], SizeOf(Y));
  end;
  if PathLayer.Closed then
  begin
    Offset := 4 + Length(PathLayer.Points) * RECORD_SIZE;
    Command := 3;
    Move(Command, Raw[Offset], SizeOf(Command));
  end;
  SetLength(Pixels, Length(Raw) div 4);
  for I := 0 to High(Pixels) do
  begin
    Pixels[I].R := Raw[I * 4 + 2];
    Pixels[I].G := Raw[I * 4 + 1];
    Pixels[I].B := Raw[I * 4];
    Pixels[I].A := Raw[I * 4 + 3];
  end;
  Result := EncodeRgba(@Pixels[0], Length(Pixels), 1);
  AddPhysicalDimensions(Result);
  AddText(Result, 'object type', 'vector');
end;

function MifPathExportShape(PathLayer: TVectArtPathLayer):
  TMifPathExportShape;
begin
  if Length(PathLayer.Points) < 2 then
    Result := mpesUnsupported
  else if Length(PathLayer.Points) = 2 then
    Result := mpesLine
  else
    Result := mpesPath;
end;

function MifPathFilled(PathLayer: TVectArtPathLayer): Boolean;
begin
  Result := PathLayer.Closed and PathLayer.Filled;
end;

function MifPathStrokeWidth(Value: Single): Double;
begin
  Result := Max(Value, 0.0);
end;

function MifLineStrokeWidth(Value: Single): Double; forward;

procedure AnalyzePathExport(PathLayer: TVectArtPathLayer; LayerIndex,
  PathOrdinal, ConvertedLineOrdinal: Integer; var Report: TMifExportReport);
var
  ExpectedName: string;
  ExportShape: TMifPathExportShape;
  StoredOpacity: Single;
begin
  ExportShape := MifPathExportShape(PathLayer);
  if ExportShape = mpesUnsupported then
  begin
    Report.AddIssue(meikUnsupported, LayerIndex, PathLayer.Name,
      '頂点が2個未満のPathはMIFへ書き出せません。');
    Exit;
  end;
  if ExportShape = mpesLine then
  begin
    Report.AddIssue(meikConversion, LayerIndex, PathLayer.Name,
      Format('2頂点のPathはMIF再読込時に「Line %d」へ変換されます。',
      [ConvertedLineOrdinal]));
    if PathLayer.Closed then
      Report.AddIssue(meikConversion, LayerIndex, PathLayer.Name,
        '2頂点Pathの閉じた状態はLineへの変換時に失われます。');
    if PathLayer.Filled then
      Report.AddIssue(meikConversion, LayerIndex, PathLayer.Name,
        '2頂点Pathの塗りはLineへの変換時に失われます。');
  end
  else
  begin
    ExpectedName := Format('Path %d', [PathOrdinal]);
    if PathLayer.Name <> ExpectedName then
      Report.AddIssue(meikConversion, LayerIndex, PathLayer.Name,
        Format('レイヤー名はMIFへ保持されず、再読込時に「%s」になります。',
        [ExpectedName]));
  end;
  if PathLayer.Locked then
    Report.AddIssue(meikConversion, LayerIndex, PathLayer.Name,
      '編集ロックはMIFへ保持されません。');
  StoredOpacity := MifAlpha(PathLayer.Opacity) / 255.0;
  if not SameValue(PathLayer.Opacity, StoredOpacity, 0.000001) then
    Report.AddIssue(meikConversion, LayerIndex, PathLayer.Name,
      Format('不透明度はMIFの8bit値%dへ丸められます。',
      [MifAlpha(PathLayer.Opacity)]));
  if (ExportShape = mpesPath) and
    (PathLayer.Filled <> MifPathFilled(PathLayer)) then
    Report.AddIssue(meikConversion, LayerIndex, PathLayer.Name,
      '開いたPathの塗りはMIFへ保持されず、塗りなしになります。');
  if ((ExportShape = mpesLine) and
    not SameValue(PathLayer.StrokeWidth,
    MifLineStrokeWidth(PathLayer.StrokeWidth), 0.000001)) or
    ((ExportShape = mpesPath) and
    not SameValue(PathLayer.StrokeWidth,
    MifPathStrokeWidth(PathLayer.StrokeWidth), 0.000001)) then
    Report.AddIssue(meikConversion, LayerIndex, PathLayer.Name,
      '線幅は変換先のMIF表現で使用できる最小値へ変換されます。');
end;

function CreatePathImagePng(PathLayer: TVectArtPathLayer): TBytes;
var
  Bounds: TRectF;
  OriginalBounds: TRectF;
begin
  Result := CreatePathRasterPng(PathLayer, Bounds);
  AddText(Result, 'object type', 'image');
  AddWadaString(Result, 'object subtype', 'vector');
  AddImagePlacementMetadata(Result, Bounds,
    MifAlpha(PathLayer.Opacity), not PathLayer.Visible);
  AddWadaInteger(Result, 'vector closed', Ord(PathLayer.Closed));
  AddWadaInteger(Result, 'vector quality', Ord(PathLayer.MifAntiAlias));
  AddWadaInteger(Result, 'vector element type', 6);
  AddWadaInteger(Result, 'vector stroke style', Ord(PathLayer.MifStrokeStyle));
  AddWadaInteger(Result, 'vector stroke cap', Ord(PathLayer.LineCap));
  AddWadaInteger(Result, 'vector stroke join', Ord(PathLayer.LineJoin));
  AddWadaInteger(Result, 'vector start stroke marker', 0);
  AddWadaInteger(Result, 'vector end stroke marker', 0);
  AddWadaInteger(Result, 'vector start marker size', 4);
  AddWadaInteger(Result, 'vector end marker size', 4);
  AddWadaDouble(Result, 'vector stroke width',
    MifPathStrokeWidth(PathLayer.StrokeWidth));
  AddWadaDouble(Result, 'vector matrix a', 1.0);
  AddWadaDouble(Result, 'vector matrix b', 0.0);
  AddWadaDouble(Result, 'vector matrix c', 0.0);
  AddWadaDouble(Result, 'vector matrix d', 1.0);
  AddWadaDouble(Result, 'vector matrix e', 0.0);
  AddWadaDouble(Result, 'vector matrix f', 0.0);
  OriginalBounds := PointsBounds(PathLayer.Points);
  AddWadaInteger(Result, 'vector original position1 x',
    Floor(OriginalBounds.Left));
  AddWadaInteger(Result, 'vector original position1 y',
    Floor(OriginalBounds.Top));
  AddWadaInteger(Result, 'vector original position2 x',
    Ceil(OriginalBounds.Right));
  AddWadaInteger(Result, 'vector original position2 y',
    Floor(OriginalBounds.Top));
  AddWadaInteger(Result, 'vector original position3 x',
    Ceil(OriginalBounds.Right));
  AddWadaInteger(Result, 'vector original position3 y',
    Ceil(OriginalBounds.Bottom));
  AddWadaInteger(Result, 'vector original position4 x',
    Floor(OriginalBounds.Left));
  AddWadaInteger(Result, 'vector original position4 y',
    Ceil(OriginalBounds.Bottom));
  AddWadaInteger(Result, 'vector enable stroke texture',
    Ord(PathLayer.StrokeWidth > 0));
  AddWadaInteger(Result, 'vector enable fill texture',
    Ord(MifPathFilled(PathLayer)));
  AddWadaString(Result, 'vector effect object type', 'none');
end;

function LineMarkerToMif(Value: TVectArtMifLineMarker): Integer;
begin
  case Value of
    vlmOpenArrow: Result := 1;
    vlmArrow: Result := 2;
    vlmWideArrow: Result := 3;
    vlmCircle: Result := 4;
    vlmDiamond: Result := 5;
    vlmConcaveArrow: Result := 6;
    vlmSmallArrow: Result := 7;
    vlmSlash: Result := 8;
    vlmStar: Result := 9;
  else
    Result := 0;
  end;
end;

function MifToLineMarker(Value: Integer): TVectArtMifLineMarker;
begin
  case Value of
    1: Result := vlmOpenArrow;
    2: Result := vlmArrow;
    3: Result := vlmWideArrow;
    4: Result := vlmCircle;
    5: Result := vlmDiamond;
    6: Result := vlmConcaveArrow;
    7: Result := vlmSmallArrow;
    8: Result := vlmSlash;
    9: Result := vlmStar;
  else
    Result := vlmNone;
  end;
end;

function MifLineMarkerSize(Value: Single): Integer;
begin
  Result := EnsureRange(Round(Value), 1, 20);
end;

function MifLineStrokeWidth(Value: Single): Double;
begin
  Result := Max(Value, 0.1);
end;

function CreateMifLineFromPath(PathLayer: TVectArtPathLayer):
  TVectArtLineLayer;
begin
  Result := TVectArtLineLayer.Create(PathLayer.Name, PathLayer.Points[0],
    PathLayer.Points[1]);
  Result.MifAntiAlias := PathLayer.MifAntiAlias;
  Result.LineCap := PathLayer.LineCap;
  Result.LineJoin := PathLayer.LineJoin;
  Result.Locked := PathLayer.Locked;
  Result.Opacity := PathLayer.Opacity;
  Result.StrokeColor := PathLayer.StrokeColor;
  Result.MifStrokeStyle := PathLayer.MifStrokeStyle;
  Result.StrokeWidth := MifLineStrokeWidth(PathLayer.StrokeWidth);
  Result.Visible := PathLayer.Visible;
end;

procedure AnalyzeLineExport(Line: TVectArtLineLayer; LayerIndex,
  LineOrdinal: Integer; var Report: TMifExportReport);
var
  ExpectedName: string;
  StoredOpacity: Single;
begin
  ExpectedName := Format('Line %d', [LineOrdinal]);
  if Line.Name <> ExpectedName then
    Report.AddIssue(meikConversion, LayerIndex, Line.Name,
      Format('レイヤー名はMIFへ保持されず、再読込時に「%s」になります。',
      [ExpectedName]));
  if Line.Locked then
    Report.AddIssue(meikConversion, LayerIndex, Line.Name,
      '編集ロックはMIFへ保持されません。');
  StoredOpacity := MifAlpha(Line.Opacity) / 255.0;
  if not SameValue(Line.Opacity, StoredOpacity, 0.000001) then
    Report.AddIssue(meikConversion, LayerIndex, Line.Name,
      Format('不透明度はMIFの8bit値%dへ丸められます。',
      [MifAlpha(Line.Opacity)]));
  if not SameValue(Line.MifStartMarkerSize,
    MifLineMarkerSize(Line.MifStartMarkerSize), 0.000001) then
    Report.AddIssue(meikConversion, LayerIndex, Line.Name,
      Format('始点マーカーサイズはMIFの整数値%dへ変換されます。',
      [MifLineMarkerSize(Line.MifStartMarkerSize)]));
  if not SameValue(Line.MifEndMarkerSize,
    MifLineMarkerSize(Line.MifEndMarkerSize), 0.000001) then
    Report.AddIssue(meikConversion, LayerIndex, Line.Name,
      Format('終点マーカーサイズはMIFの整数値%dへ変換されます。',
      [MifLineMarkerSize(Line.MifEndMarkerSize)]));
  if not SameValue(Line.StrokeWidth,
    MifLineStrokeWidth(Line.StrokeWidth), 0.000001) then
    Report.AddIssue(meikConversion, LayerIndex, Line.Name,
      '0.1未満の線幅はMIFでは0.1へ変換されます。');
end;

function CreateLineImagePng(Line: TVectArtLineLayer): TBytes;
const
  ORIGINAL_LEFT = 848;
  ORIGINAL_TOP = 452;
  ORIGINAL_RIGHT = 1082;
  ORIGINAL_BOTTOM = 460;
var
  CenterY: Double;
  DirectionLength: Double;
  MatrixA: Double;
  MatrixB: Double;
  MatrixC: Double;
  MatrixD: Double;
  MatrixE: Double;
  MatrixF: Double;
  PlacementBounds: TRectF;
begin
  Result := CreateLineRasterPng(Line, PlacementBounds);
  AddText(Result, 'object type', 'image');
  AddWadaString(Result, 'object subtype', 'vector');
  AddImagePlacementMetadata(Result, PlacementBounds,
    MifAlpha(Line.Opacity), not Line.Visible);
  AddWadaInteger(Result, 'vector closed', 0);
  AddWadaInteger(Result, 'vector quality', Ord(Line.MifAntiAlias));
  AddWadaInteger(Result, 'vector element type', 6);
  AddWadaInteger(Result, 'vector stroke style', Ord(Line.MifStrokeStyle));
  AddWadaInteger(Result, 'vector stroke cap', Ord(Line.LineCap));
  AddWadaInteger(Result, 'vector stroke join', Ord(Line.LineJoin));
  AddWadaInteger(Result, 'vector start stroke marker',
    LineMarkerToMif(Line.MifStartMarker));
  AddWadaInteger(Result, 'vector end stroke marker',
    LineMarkerToMif(Line.MifEndMarker));
  AddWadaInteger(Result, 'vector start marker size',
    MifLineMarkerSize(Line.MifStartMarkerSize));
  AddWadaInteger(Result, 'vector end marker size',
    MifLineMarkerSize(Line.MifEndMarkerSize));
  AddWadaDouble(Result, 'vector stroke width',
    MifLineStrokeWidth(Line.StrokeWidth));
  MatrixA := (Line.EndPoint.X - Line.StartPoint.X) /
    (ORIGINAL_RIGHT - ORIGINAL_LEFT);
  MatrixB := (Line.EndPoint.Y - Line.StartPoint.Y) /
    (ORIGINAL_RIGHT - ORIGINAL_LEFT);
  DirectionLength := Hypot(MatrixA, MatrixB);
  if DirectionLength > 0 then
  begin
    MatrixC := -MatrixB / DirectionLength;
    MatrixD := MatrixA / DirectionLength;
  end
  else
  begin
    MatrixC := 0;
    MatrixD := 1;
  end;
  CenterY := (ORIGINAL_TOP + ORIGINAL_BOTTOM) * 0.5;
  MatrixE := Line.StartPoint.X - MatrixA * ORIGINAL_LEFT -
    MatrixC * CenterY;
  MatrixF := Line.StartPoint.Y - MatrixB * ORIGINAL_LEFT -
    MatrixD * CenterY;
  AddWadaDouble(Result, 'vector matrix a', MatrixA);
  AddWadaDouble(Result, 'vector matrix b', MatrixB);
  AddWadaDouble(Result, 'vector matrix c', MatrixC);
  AddWadaDouble(Result, 'vector matrix d', MatrixD);
  AddWadaDouble(Result, 'vector matrix e', MatrixE);
  AddWadaDouble(Result, 'vector matrix f', MatrixF);
  AddWadaInteger(Result, 'vector original position1 x', ORIGINAL_LEFT);
  AddWadaInteger(Result, 'vector original position1 y', ORIGINAL_TOP);
  AddWadaInteger(Result, 'vector original position2 x', ORIGINAL_RIGHT);
  AddWadaInteger(Result, 'vector original position2 y', ORIGINAL_TOP);
  AddWadaInteger(Result, 'vector original position3 x', ORIGINAL_RIGHT);
  AddWadaInteger(Result, 'vector original position3 y', ORIGINAL_BOTTOM);
  AddWadaInteger(Result, 'vector original position4 x', ORIGINAL_LEFT);
  AddWadaInteger(Result, 'vector original position4 y', ORIGINAL_BOTTOM);
  AddWadaInteger(Result, 'vector enable stroke texture', 1);
  AddWadaInteger(Result, 'vector enable fill texture', 0);
  AddWadaString(Result, 'vector effect object type', 'none');
end;

function TryReadTextValue(const Png: TBytes; const RequiredKey: string;
  out Value: string): Boolean;
var
  ChunkLength: UInt32;
  ChunkType: AnsiString;
  DataOffset: Integer;
  Key: string;
  NullOffset: Integer;
  Offset: Integer;
begin
  Result := False;
  Value := '';
  if not IsPng(Png) then
    Exit;
  Offset := 8;
  while Offset + 12 <= Length(Png) do
  begin
    ChunkLength := ReadUInt32BE(Png, Offset);
    if (ChunkLength > UInt32(High(Integer))) or
      (Int64(Offset) + ChunkLength + 12 > Length(Png)) then
      Exit;
    SetLength(ChunkType, 4);
    Move(Png[Offset + 4], ChunkType[1], 4);
    if ChunkType = 'tEXt' then
    begin
      DataOffset := Offset + 8;
      NullOffset := DataOffset;
      while (NullOffset < DataOffset + Integer(ChunkLength)) and
        (Png[NullOffset] <> 0) do
        Inc(NullOffset);
      if NullOffset < DataOffset + Integer(ChunkLength) then
      begin
        Key := TEncoding.UTF8.GetString(Png, DataOffset,
          NullOffset - DataOffset);
        if Key = RequiredKey then
        begin
          Value := TEncoding.UTF8.GetString(Png, NullOffset + 1,
            DataOffset + Integer(ChunkLength) - NullOffset - 1);
          Exit(True);
        end;
      end;
    end;
    Inc(Offset, Integer(ChunkLength) + 12);
  end;
end;

function TryReadPngMetadata(const Png: TBytes; const RequiredChunkType,
  RequiredKey: string; out Value: TBytes): Boolean;
var
  ChunkLength: UInt32;
  ChunkType: string;
  DataOffset: Integer;
  Key: string;
  NullOffset: Integer;
  Offset: Integer;
  ValueCount: Integer;
begin
  Result := False;
  Value := nil;
  if not IsPng(Png) then
    Exit;
  Offset := 8;
  while Offset + 12 <= Length(Png) do
  begin
    ChunkLength := ReadUInt32BE(Png, Offset);
    if (ChunkLength > UInt32(High(Integer))) or
      (Int64(Offset) + ChunkLength + 12 > Length(Png)) then
      Exit;
    ChunkType := TEncoding.ASCII.GetString(Png, Offset + 4, 4);
    if ChunkType = RequiredChunkType then
    begin
      DataOffset := Offset + 8;
      NullOffset := DataOffset;
      while (NullOffset < DataOffset + Integer(ChunkLength)) and
        (Png[NullOffset] <> 0) do
        Inc(NullOffset);
      if NullOffset < DataOffset + Integer(ChunkLength) then
      begin
        Key := TEncoding.ASCII.GetString(Png, DataOffset,
          NullOffset - DataOffset);
        if Key = RequiredKey then
        begin
          ValueCount := DataOffset + Integer(ChunkLength) - NullOffset - 1;
          SetLength(Value, ValueCount);
          if ValueCount > 0 then
            Move(Png[NullOffset + 1], Value[0], ValueCount);
          Exit(True);
        end;
      end;
    end;
    Inc(Offset, Integer(ChunkLength) + 12);
  end;
end;

function TryReadPngString(const Png: TBytes; const ChunkType, Key: string;
  out Value: string): Boolean;
var
  Bytes: TBytes;
begin
  Result := TryReadPngMetadata(Png, ChunkType, Key, Bytes);
  if not Result then
  begin
    Value := '';
    Exit;
  end;
  if Length(Bytes) = 0 then
    Value := ''
  else if TEncoding.UTF8.IsBufferValid(@Bytes[0], Length(Bytes)) then
    Value := TEncoding.UTF8.GetString(Bytes)
  else
  begin
    Value := '';
    Result := False;
  end;
end;

function TryReadPngInteger(const Png: TBytes; const Key: string;
  out Value: Int32): Boolean;
var
  Bytes: TBytes;
begin
  Result := TryReadPngMetadata(Png, 'waDA', Key, Bytes) and
    (Length(Bytes) = 4);
  if Result then
    Value := Int32(ReadUInt32BE(Bytes, 0))
  else
    Value := 0;
end;

function TryReadPngDouble(const Png: TBytes; const Key: string;
  out Value: Double): Boolean;
var
  Bytes: TBytes;
begin
  Result := TryReadPngMetadata(Png, 'waDA', Key, Bytes) and
    (Length(Bytes) = 8);
  if Result then
    Value := ReadDoubleBE(Bytes, 0)
  else
    Value := 0.0;
end;

function TryReadWebArtVectorPoints(const Png: TBytes;
  out Points: TArray<TPointF>; out Closed: Boolean): Boolean;
const
  RECORD_SIZE = 60;
var
  Command: UInt32;
  Count: UInt32;
  I: Integer;
  Offset: Integer;
  PixelColor: TColor;
  PointList: TList<TPointF>;
  PngImage: TPngImage;
  Raw: TBytes;
  Stream: TBytesStream;
  X: Double;
  Y: Double;
begin
  Result := False;
  Points := nil;
  Closed := False;
  PngImage := TPngImage.Create;
  Stream := TBytesStream.Create(Png);
  try
    PngImage.LoadFromStream(Stream);
    if (PngImage.Height <> 1) or (PngImage.Width < 1) or
      (PngImage.Width > 1000000) then
      Exit;
    SetLength(Raw, PngImage.Width * 4);
    for I := 0 to PngImage.Width - 1 do
    begin
      PixelColor := ColorToRGB(PngImage.Pixels[I, 0]);
      Raw[I * 4] := GetBValue(PixelColor);
      Raw[I * 4 + 1] := GetGValue(PixelColor);
      Raw[I * 4 + 2] := GetRValue(PixelColor);
      if PngImage.AlphaScanline[0] <> nil then
        Raw[I * 4 + 3] := PngImage.AlphaScanline[0]^[I]
      else
        Raw[I * 4 + 3] := 255;
    end;
  finally
    Stream.Free;
    PngImage.Free;
  end;
  if Length(Raw) < 4 then
    Exit;
  Move(Raw[0], Count, SizeOf(Count));
  if (Count = 0) or (Count > 1000000) or
    (UInt64(4) + UInt64(Count) * RECORD_SIZE > UInt64(Length(Raw))) then
    Exit;
  PointList := TList<TPointF>.Create;
  try
    for I := 0 to Integer(Count) - 1 do
    begin
      Offset := 4 + I * RECORD_SIZE;
      Move(Raw[Offset], Command, SizeOf(Command));
      case Command of
        1, 2:
          begin
            Move(Raw[Offset + 4], X, SizeOf(X));
            Move(Raw[Offset + 12], Y, SizeOf(Y));
            if not IsNan(X) and not IsInfinite(X) and
              not IsNan(Y) and not IsInfinite(Y) then
              PointList.Add(TPointF.Create(X, Y));
          end;
        3:
          Closed := True;
      else
        Exit;
      end;
    end;
    Result := PointList.Count >= 2;
    if Result then
      Points := PointList.ToArray;
  finally
    PointList.Free;
  end;
end;

procedure CollectRectangleSources(Container: TVectArtMifContainer;
  Sources: TList<TRectangleMifSource>);
var
  Bottom: Int32;
  ElementType: Int32;
  I: Integer;
  Left: Int32;
  ObjectSubtype: string;
  ObjectType: string;
  Right: Int32;
  Source: TRectangleMifSource;
  StrokeEnabled: Int32;
  Top: Int32;
begin
  if (Container = nil) or (Sources = nil) then
    Exit;
  for I := 2 to Container.ChunkCount - 2 do
  begin
    if (Container[I].Tag <> 'IPNG') or
      not TryReadPngString(Container[I].Data, 'tEXt', 'object type',
        ObjectType) or not SameText(ObjectType, 'image') or
      not TryReadPngString(Container[I].Data, 'waDA', 'object subtype',
        ObjectSubtype) or not SameText(ObjectSubtype, 'vector') or
      not TryReadPngInteger(Container[I].Data, 'vector element type',
        ElementType) or (ElementType <> 4) then
      Continue;
    Source := Default(TRectangleMifSource);
    StrokeEnabled := 0;
    TryReadPngInteger(Container[I].Data, 'vector enable stroke texture',
      StrokeEnabled);
    Source.StrokeEnabled := StrokeEnabled <> 0;
    Source.Valid := (I + 2 < Container.ChunkCount) and
      (Container[I + 2].Tag = 'IPNG') and IsPng(Container[I + 2].Data) and
      TryReadPngInteger(Container[I].Data, 'vector original position1 x',
        Left) and
      TryReadPngInteger(Container[I].Data, 'vector original position1 y',
        Top) and
      TryReadPngInteger(Container[I].Data, 'vector original position3 x',
        Right) and
      TryReadPngInteger(Container[I].Data, 'vector original position3 y',
        Bottom) and (Right <> Left) and (Bottom <> Top);
    if Source.Valid then
    begin
      Source.OriginalLeft := Left;
      Source.OriginalTop := Top;
      Source.OriginalRight := Right;
      Source.OriginalBottom := Bottom;
      Source.VectorPng := Copy(Container[I + 2].Data);
      if (I + 3 < Container.ChunkCount) and
        (Container[I + 3].Tag = 'IPNG') and IsPng(Container[I + 3].Data) then
        Source.StrokeTexturePng := Copy(Container[I + 3].Data);
    end;
    Sources.Add(Source);
  end;
end;

function TryReadPngSize(const Png: TBytes; out Width,
  Height: Integer): Boolean;
begin
  Result := IsPng(Png) and (Length(Png) >= 33) and
    (TEncoding.ASCII.GetString(Png, 12, 4) = 'IHDR');
  if Result then
  begin
    Width := Integer(ReadUInt32BE(Png, 16));
    Height := Integer(ReadUInt32BE(Png, 20));
    Result := (Width > 0) and (Height > 0);
  end
  else
  begin
    Width := 0;
    Height := 0;
  end;
end;

function IsDecodablePng(const Png: TBytes): Boolean;
var
  PngImage: TPngImage;
  Stream: TBytesStream;
begin
  Result := False;
  if not IsPng(Png) then
    Exit;
  PngImage := TPngImage.Create;
  Stream := TBytesStream.Create(Png);
  try
    try
      PngImage.LoadFromStream(Stream);
      Result := (PngImage.Width > 0) and (PngImage.Height > 0);
    except
      Result := False;
    end;
  finally
    Stream.Free;
    PngImage.Free;
  end;
end;

function TryPrepareImagePngForMif(ImageLayer: TVectArtImageLayer;
  LayerIndex, ImageOrdinal: Integer; var Report: TMifExportReport;
  out Png: TBytes): Boolean;
var
  ExpectedName: string;
  ExpectedObjectType: string;
  I: Integer;
  ObjectSubtype: string;
  StoredOpacity: Single;
begin
  Result := False;
  Png := nil;
  if not IsDecodablePng(ImageLayer.PngData) or
    (FindPngMetadataInsertOffset(ImageLayer.PngData) < 0) then
  begin
    Report.AddIssue(meikUnsupported, LayerIndex, ImageLayer.Name,
      'PNG本体が破損しているか、MIFへ格納できるPNG構造ではありません。');
    Exit;
  end;
  if ImageLayer.SourceKind = visLogo then
  begin
    ExpectedName := Format('Logo %d', [ImageOrdinal]);
    ExpectedObjectType := 'logo';
  end
  else
  begin
    ExpectedName := Format('Image %d', [ImageOrdinal]);
    ExpectedObjectType := 'image';
  end;
  if ImageLayer.Name <> ExpectedName then
    Report.AddIssue(meikConversion, LayerIndex, ImageLayer.Name,
      Format('レイヤー名はMIFへ保持されず、再読込時に「%s」になります。',
      [ExpectedName]));
  if ImageLayer.Locked then
    Report.AddIssue(meikConversion, LayerIndex, ImageLayer.Name,
      '編集ロックはMIFへ保持されません。');
  StoredOpacity := MifAlpha(ImageLayer.Opacity) / 255.0;
  if not SameValue(ImageLayer.Opacity, StoredOpacity, 0.000001) then
    Report.AddIssue(meikConversion, LayerIndex, ImageLayer.Name,
      Format('不透明度はMIFの8bit値%dへ丸められます。',
      [MifAlpha(ImageLayer.Opacity)]));
  for I := 0 to High(ImageLayer.Points) do
    if not SameValue(ImageLayer.Points[I].X,
      MifImageCoordinate(ImageLayer.Points[I].X), 0.000001) or
      not SameValue(ImageLayer.Points[I].Y,
      MifImageCoordinate(ImageLayer.Points[I].Y), 0.000001) then
    begin
      Report.AddIssue(meikConversion, LayerIndex, ImageLayer.Name,
        '画像の四隅はMIFの整数座標へ丸められます。');
      Break;
    end;
  Png := Copy(ImageLayer.PngData);
  Png := RemovePngMetadataKey(Png, 'tEXt', 'object type');
  AddText(Png, 'object type', ExpectedObjectType);
  ObjectSubtype := '';
  if TryReadPngString(Png, 'waDA', 'object subtype', ObjectSubtype) and
    SameText(ObjectSubtype, 'vector') then
    Png := RemovePngMetadataKey(Png, 'waDA', 'object subtype');
  UpdateImagePlacementMetadata(Png, ImageLayer.Points,
    MifAlpha(ImageLayer.Opacity), not ImageLayer.Visible);
  Result := True;
end;

function TryImportWebArtDocument(Container: TVectArtMifContainer;
  Document: TVectArtDocument; out ErrorMessage: string): Boolean;
var
  Alpha: Int32;
  ApplicationName: string;
  BackgroundColor: Int32;
  Bottom: Int32;
  CanvasHeight: Integer;
  CanvasWidth: Integer;
  ClosedValue: Int32;
  Data: TVectArtRectangleData;
  Discarded: TVectArtRectangleData;
  DiscardedLine: TVectArtLineData;
  DiscardedPath: TVectArtPathData;
  DiscardedImage: TVectArtImageData;
  ElementType: Int32;
  MifEndMarker: Int32;
  MifEndMarkerSize: Int32;
  FillColor: Int32;
  FillEnabled: Int32;
  Hidden: Int32;
  I: Integer;
  ImageData: TVectArtImageData;
  Images: TList<TVectArtImageData>;
  Left: Int32;
  LineData: TVectArtLineData;
  Lines: TList<TVectArtLineData>;
  LayerOrder: TList<Integer>;
  MatrixA: Double;
  MatrixB: Double;
  MatrixC: Double;
  MatrixD: Double;
  MatrixE: Double;
  MatrixF: Double;
  OriginalBottom: Int32;
  OriginalLeft: Int32;
  OriginalRight: Int32;
  OriginalTop: Int32;
  Position2X: Int32;
  Position2Y: Int32;
  Position4X: Int32;
  Position4Y: Int32;
  ObjectSubtype: string;
  ObjectType: string;
  PathClosed: Boolean;
  PathData: TVectArtPathData;
  Paths: TList<TVectArtPathData>;
  Rectangles: TList<TVectArtRectangleData>;
  Right: Int32;
  StrokeColor: Int32;
  StrokeCap: Int32;
  StrokeJoin: Int32;
  MifStartMarker: Int32;
  MifStartMarkerSize: Int32;
  StrokeEnabled: Int32;
  MifStrokeStyle: Int32;
  StrokeWidth: Double;
  Top: Int32;
  VectorPoints: TArray<TPointF>;
  VectorQuality: Int32;
begin
  Result := False;
  ErrorMessage := '';
  if (Container.ChunkCount < 3) or (Container[1].Tag <> 'IPNG') or
    not TryReadPngString(Container[1].Data, 'tEXt', 'application name',
      ApplicationName) or not SameText(ApplicationName, 'WebArt Designer') or
    not TryReadPngSize(Container[1].Data, CanvasWidth, CanvasHeight) then
  begin
    ErrorMessage := 'WebArt Designer MIF metadata was not found';
    Exit;
  end;

  BackgroundColor := ColorToRGB(clWhite);
  if (Container[2].Tag = 'IPNG') then
    TryReadPngInteger(Container[2].Data, 'texture color1', BackgroundColor);
  Rectangles := TList<TVectArtRectangleData>.Create;
  Lines := TList<TVectArtLineData>.Create;
  Paths := TList<TVectArtPathData>.Create;
  Images := TList<TVectArtImageData>.Create;
  LayerOrder := TList<Integer>.Create;
  try
    for I := 2 to Container.ChunkCount - 2 do
    begin
      if (Container[I].Tag <> 'IPNG') or
        not TryReadPngString(Container[I].Data, 'tEXt', 'object type',
          ObjectType) then
        Continue;
      ObjectSubtype := '';
      TryReadPngString(Container[I].Data, 'waDA', 'object subtype',
        ObjectSubtype);
      if not TryReadPngInteger(Container[I].Data, 'image position1 x', Left) or
        not TryReadPngInteger(Container[I].Data, 'image position1 y', Top) or
        not TryReadPngInteger(Container[I].Data, 'image position2 x', Position2X) or
        not TryReadPngInteger(Container[I].Data, 'image position2 y', Position2Y) or
        not TryReadPngInteger(Container[I].Data, 'image position3 x', Right) or
        not TryReadPngInteger(Container[I].Data, 'image position3 y', Bottom) or
        not TryReadPngInteger(Container[I].Data, 'image position4 x', Position4X) or
        not TryReadPngInteger(Container[I].Data, 'image position4 y', Position4Y)
      then
        Continue;
      if SameText(ObjectType, 'logo') or
        (SameText(ObjectType, 'image') and
          not SameText(ObjectSubtype, 'vector')) then
      begin
        Alpha := 255;
        Hidden := 0;
        TryReadPngInteger(Container[I].Data, 'image alpha', Alpha);
        TryReadPngInteger(Container[I].Data, 'image hidden', Hidden);
        if SameText(ObjectType, 'logo') then
        begin
          ImageData.Name := Format('Logo %d', [Images.Count + 1]);
          ImageData.SourceKind := visLogo;
        end
        else
        begin
          ImageData.Name := Format('Image %d', [Images.Count + 1]);
          ImageData.SourceKind := visImage;
        end;
        ImageData.PngData := Copy(Container[I].Data);
        ImageData.Points[0] := TPointF.Create(Left, Top);
        ImageData.Points[1] := TPointF.Create(Position2X, Position2Y);
        ImageData.Points[2] := TPointF.Create(Right, Bottom);
        ImageData.Points[3] := TPointF.Create(Position4X, Position4Y);
        ImageData.Opacity := EnsureRange(Alpha / 255.0, 0.0, 1.0);
        ImageData.Visible := Hidden = 0;
        ImageData.Locked := False;
        Images.Add(ImageData);
        LayerOrder.Add(-(2000000 + Images.Count));
        Continue;
      end;
      if not SameText(ObjectType, 'image') or
        not SameText(ObjectSubtype, 'vector') or
        not TryReadPngInteger(Container[I].Data, 'vector element type',
          ElementType) or not (ElementType in [4, 6]) then
        Continue;
      FillColor := ColorToRGB(clWhite);
      if (I + 1 < Container.ChunkCount) and
        (Container[I + 1].Tag = 'IPNG') then
        TryReadPngInteger(Container[I + 1].Data, 'texture color1', FillColor);
      Alpha := 255;
      Hidden := 0;
      TryReadPngInteger(Container[I].Data, 'image alpha', Alpha);
      TryReadPngInteger(Container[I].Data, 'image hidden', Hidden);
      StrokeEnabled := 0;
      MifStartMarker := 0;
      MifStartMarkerSize := 4;
      FillEnabled := 0;
      MifEndMarker := 0;
      MifEndMarkerSize := 4;
      MifStrokeStyle := 0;
      StrokeCap := 0;
      StrokeJoin := 0;
      StrokeWidth := 1.0;
      VectorQuality := 1;
      TryReadPngInteger(Container[I].Data,
        'vector enable stroke texture', StrokeEnabled);
      TryReadPngInteger(Container[I].Data,
        'vector enable fill texture', FillEnabled);
      TryReadPngInteger(Container[I].Data, 'vector stroke style',
        MifStrokeStyle);
      TryReadPngInteger(Container[I].Data, 'vector stroke cap', StrokeCap);
      TryReadPngInteger(Container[I].Data, 'vector end stroke marker',
        MifEndMarker);
      TryReadPngInteger(Container[I].Data, 'vector start stroke marker',
        MifStartMarker);
      TryReadPngInteger(Container[I].Data, 'vector start marker size',
        MifStartMarkerSize);
      TryReadPngInteger(Container[I].Data, 'vector end marker size',
        MifEndMarkerSize);
      TryReadPngInteger(Container[I].Data, 'vector quality', VectorQuality);
      TryReadPngInteger(Container[I].Data, 'vector stroke join', StrokeJoin);
      TryReadPngDouble(Container[I].Data, 'vector stroke width',
        StrokeWidth);
      StrokeColor := ColorToRGB(clBlack);
      if (StrokeEnabled <> 0) and (I + 3 < Container.ChunkCount) and
        (Container[I + 3].Tag = 'IPNG') then
        TryReadPngInteger(Container[I + 3].Data, 'texture color1',
          StrokeColor);
      if ElementType = 6 then
      begin
        VectorPoints := nil;
        PathClosed := False;
        if (I + 2 < Container.ChunkCount) and
          (Container[I + 2].Tag = 'IPNG') and
          TryReadWebArtVectorPoints(Container[I + 2].Data, VectorPoints,
            PathClosed) and (Length(VectorPoints) > 2) then
        begin
          ClosedValue := 0;
          TryReadPngInteger(Container[I].Data, 'vector closed', ClosedValue);
          PathClosed := PathClosed or (ClosedValue <> 0);
          MatrixA := 1.0;
          MatrixB := 0.0;
          MatrixC := 0.0;
          MatrixD := 1.0;
          MatrixE := 0.0;
          MatrixF := 0.0;
          TryReadPngDouble(Container[I].Data, 'vector matrix a', MatrixA);
          TryReadPngDouble(Container[I].Data, 'vector matrix b', MatrixB);
          TryReadPngDouble(Container[I].Data, 'vector matrix c', MatrixC);
          TryReadPngDouble(Container[I].Data, 'vector matrix d', MatrixD);
          TryReadPngDouble(Container[I].Data, 'vector matrix e', MatrixE);
          TryReadPngDouble(Container[I].Data, 'vector matrix f', MatrixF);
          for Position2X := 0 to High(VectorPoints) do
            VectorPoints[Position2X] := TPointF.Create(
              MatrixA * VectorPoints[Position2X].X +
                MatrixC * VectorPoints[Position2X].Y + MatrixE,
              MatrixB * VectorPoints[Position2X].X +
                MatrixD * VectorPoints[Position2X].Y + MatrixF);
          PathData.Name := Format('Path %d', [Paths.Count + 1]);
          PathData.Points := Copy(VectorPoints);
          PathData.Closed := PathClosed;
          PathData.Filled := PathClosed and (FillEnabled <> 0);
          PathData.FillColor := TColor(FillColor);
          PathData.Opacity := EnsureRange(Alpha / 255.0, 0.0, 1.0);
          PathData.MifAntiAlias := VectorQuality <> 0;
          if InRange(StrokeCap, Ord(Low(TVectArtLineCap)),
            Ord(High(TVectArtLineCap))) then
            PathData.LineCap := TVectArtLineCap(StrokeCap)
          else
            PathData.LineCap := vlcButt;
          if InRange(StrokeJoin, Ord(Low(TVectArtLineJoin)),
            Ord(High(TVectArtLineJoin))) then
            PathData.LineJoin := TVectArtLineJoin(StrokeJoin)
          else
            PathData.LineJoin := vljMiter;
          PathData.StrokeColor := TColor(StrokeColor);
          if InRange(MifStrokeStyle, Ord(Low(TVectArtMifStrokeStyle)),
            Ord(High(TVectArtMifStrokeStyle))) then
            PathData.MifStrokeStyle := TVectArtMifStrokeStyle(MifStrokeStyle)
          else
            PathData.MifStrokeStyle := vssSolid;
          if StrokeEnabled <> 0 then
            PathData.StrokeWidth := MifPathStrokeWidth(StrokeWidth)
          else
            PathData.StrokeWidth := 0.0;
          PathData.Visible := Hidden = 0;
          PathData.Locked := False;
          Paths.Add(PathData);
          LayerOrder.Add(-(1000000 + Paths.Count));
          Continue;
        end;
        if not TryReadPngInteger(Container[I].Data,
          'vector original position1 x', OriginalLeft) or
          not TryReadPngInteger(Container[I].Data,
          'vector original position1 y', OriginalTop) or
          not TryReadPngInteger(Container[I].Data,
          'vector original position3 x', OriginalRight) or
          not TryReadPngInteger(Container[I].Data,
          'vector original position3 y', OriginalBottom) then
          Continue;
        MatrixA := 1.0;
        MatrixB := 0.0;
        MatrixC := 0.0;
        MatrixD := 1.0;
        MatrixE := 0.0;
        MatrixF := 0.0;
        TryReadPngDouble(Container[I].Data, 'vector matrix a', MatrixA);
        TryReadPngDouble(Container[I].Data, 'vector matrix b', MatrixB);
        TryReadPngDouble(Container[I].Data, 'vector matrix c', MatrixC);
        TryReadPngDouble(Container[I].Data, 'vector matrix d', MatrixD);
        TryReadPngDouble(Container[I].Data, 'vector matrix e', MatrixE);
        TryReadPngDouble(Container[I].Data, 'vector matrix f', MatrixF);
        LineData.Name := Format('Line %d', [Lines.Count + 1]);
        LineData.StartPoint := TPointF.Create(
          MatrixA * OriginalLeft + MatrixC *
            ((OriginalTop + OriginalBottom) * 0.5) + MatrixE,
          MatrixB * OriginalLeft + MatrixD *
            ((OriginalTop + OriginalBottom) * 0.5) + MatrixF);
        LineData.EndPoint := TPointF.Create(
          MatrixA * OriginalRight + MatrixC *
            ((OriginalTop + OriginalBottom) * 0.5) + MatrixE,
          MatrixB * OriginalRight + MatrixD *
            ((OriginalTop + OriginalBottom) * 0.5) + MatrixF);
        LineData.Opacity := EnsureRange(Alpha / 255.0, 0.0, 1.0);
        LineData.MifAntiAlias := VectorQuality <> 0;
        LineData.MifEndMarker := MifToLineMarker(MifEndMarker);
        LineData.MifEndMarkerSize := Max(MifEndMarkerSize, 1);
        LineData.MifStartMarker := MifToLineMarker(MifStartMarker);
        LineData.MifStartMarkerSize := Max(MifStartMarkerSize, 1);
        if InRange(StrokeCap, Ord(Low(TVectArtLineCap)),
          Ord(High(TVectArtLineCap))) then
          LineData.LineCap := TVectArtLineCap(StrokeCap)
        else
          LineData.LineCap := vlcButt;
        if InRange(StrokeJoin, Ord(Low(TVectArtLineJoin)),
          Ord(High(TVectArtLineJoin))) then
          LineData.LineJoin := TVectArtLineJoin(StrokeJoin)
        else
          LineData.LineJoin := vljMiter;
        LineData.StrokeColor := TColor(StrokeColor);
        if InRange(MifStrokeStyle, Ord(Low(TVectArtMifStrokeStyle)),
          Ord(High(TVectArtMifStrokeStyle))) then
          LineData.MifStrokeStyle := TVectArtMifStrokeStyle(MifStrokeStyle)
        else
          LineData.MifStrokeStyle := vssSolid;
        LineData.StrokeWidth := MifLineStrokeWidth(StrokeWidth);
        LineData.Visible := Hidden = 0;
        LineData.Locked := False;
        Lines.Add(LineData);
        LayerOrder.Add(-Lines.Count);
        Continue;
      end;
      Data.Name := Format('Rectangle %d', [Rectangles.Count + 1]);
      if (Position2Y = Top) and (Position4X = Left) then
        Data.Bounds := TRectF.Create(Min(Left, Right), Min(Top, Bottom),
          Max(Left, Right) + 1, Max(Top, Bottom) + 1)
      else
        Data.Bounds := TRectF.Create(
          (Left + Position2X + Right + Position4X) * 0.25 -
            (Hypot(Position2X - Left, Position2Y - Top) + 1) * 0.5,
          (Top + Position2Y + Bottom + Position4Y) * 0.25 -
            (Hypot(Position4X - Left, Position4Y - Top) + 1) * 0.5,
          (Left + Position2X + Right + Position4X) * 0.25 +
            (Hypot(Position2X - Left, Position2Y - Top) + 1) * 0.5,
          (Top + Position2Y + Bottom + Position4Y) * 0.25 +
            (Hypot(Position4X - Left, Position4Y - Top) + 1) * 0.5);
      Data.FillColor := TColor(FillColor);
      Data.Opacity := EnsureRange(Alpha / 255.0, 0.0, 1.0);
      Data.RotationDegrees := RadToDeg(ArcTan2(Position2Y - Top,
        Position2X - Left));
      Data.StrokeColor := TColor(StrokeColor);
      if InRange(MifStrokeStyle, Ord(Low(TVectArtMifStrokeStyle)),
        Ord(High(TVectArtMifStrokeStyle))) then
        Data.MifStrokeStyle := TVectArtMifStrokeStyle(MifStrokeStyle)
      else
        Data.MifStrokeStyle := vssSolid;
      if StrokeEnabled <> 0 then
        Data.StrokeWidth := Max(StrokeWidth, 0.0)
      else
        Data.StrokeWidth := 0.0;
      Data.Visible := Hidden = 0;
      Data.Locked := False;
      Rectangles.Add(Data);
      LayerOrder.Add(Rectangles.Count);
    end;

    while Document.LayerCount > 1 do
      if Document[Document.LayerCount - 1] is TVectArtRectangleLayer then
        Document.RemoveRectangle(Document.LayerCount - 1, Discarded)
      else if Document[Document.LayerCount - 1] is TVectArtLineLayer then
        Document.RemoveLine(Document.LayerCount - 1, DiscardedLine)
      else if Document[Document.LayerCount - 1] is TVectArtPathLayer then
        Document.RemovePath(Document.LayerCount - 1, DiscardedPath)
      else if Document[Document.LayerCount - 1] is TVectArtImageLayer then
        Document.RemoveImage(Document.LayerCount - 1, DiscardedImage)
      else
        raise EInvalidOp.Create('Document contains an unsupported layer');
    Document.CanvasLayer.Width := CanvasWidth;
    Document.CanvasLayer.Height := CanvasHeight;
    Document.CanvasLayer.BackgroundColor := TColor(BackgroundColor);
    Document.CanvasLayer.Transparent := False;
    for I in LayerOrder do
      if I > 0 then
        Document.InsertRectangle(Document.LayerCount, Rectangles[I - 1])
      else if I <= -2000000 then
        Document.InsertImage(Document.LayerCount,
          Images[-I - 2000001])
      else if I <= -1000000 then
        Document.InsertPath(Document.LayerCount,
          Paths[-I - 1000001])
      else
        Document.InsertLine(Document.LayerCount, Lines[-I - 1]);
    Document.SelectedIndex := -1;
    Document.Changed;
    Result := True;
  finally
    LayerOrder.Free;
    Lines.Free;
    Paths.Free;
    Images.Free;
    Rectangles.Free;
  end;
end;

function TryLoadVectArtDocumentFromMif(Container: TVectArtMifContainer;
  Document: TVectArtDocument; out ErrorMessage: string): Boolean;
var
  I: Integer;
  Json: string;
begin
  Result := False;
  ErrorMessage := '';
  if Container = nil then
  begin
    ErrorMessage := 'MIF container is not assigned';
    Exit;
  end;
  if Document = nil then
  begin
    ErrorMessage := 'Document is not assigned';
    Exit;
  end;
  for I := 0 to Container.ChunkCount - 1 do
    if (Container[I].Tag = 'IPNG') and
      TryReadTextValue(Container[I].Data, DOCUMENT_TEXT_KEY, Json) then
    begin
      Result := TryDeserializeVectArtDocument(Json, Document, ErrorMessage);
      if Result then
        Document.EditingMode := vemMifCompatible;
      Exit;
    end;
  Result := TryImportWebArtDocument(Container, Document, ErrorMessage);
  if Result then
    Document.EditingMode := vemMifCompatible;
end;

function TryCreateVectArtMifFromDocument(Document: TVectArtDocument;
  out Container: TVectArtMifContainer; out ErrorMessage: string): Boolean;
begin
  Result := TryCreateVectArtMifFromDocument(Document, nil, Container,
    ErrorMessage);
end;

function TryCreateVectArtMifFromDocument(Document: TVectArtDocument;
  SourceContainer: TVectArtMifContainer; out Container: TVectArtMifContainer;
  out ErrorMessage: string): Boolean;
var
  Report: TMifExportReport;
begin
  Result := TryCreateVectArtMifFromDocument(Document, SourceContainer,
    Container, Report, ErrorMessage);
end;

function TryCreateVectArtMifFromDocument(Document: TVectArtDocument;
  SourceContainer: TVectArtMifContainer; out Container: TVectArtMifContainer;
  out Report: TMifExportReport; out ErrorMessage: string): Boolean;
var
  Candidate: TVectArtMifContainer;
  Canvas: TVectArtCanvasLayer;
  ConvertedLine: TVectArtLineLayer;
  Header: TBytes;
  I: Integer;
  ImageIndex: Integer;
  ImagePng: TBytes;
  Layer: TVectArtLayer;
  Line: TVectArtLineLayer;
  LineIndex: Integer;
  ContentChunkCount: Integer;
  PathExportShape: TMifPathExportShape;
  PathIndex: Integer;
  PathLayer: TVectArtPathLayer;
  PreparedImagePngs: TArray<TBytes>;
  Rectangle: TVectArtRectangleLayer;
  RectangleIndex: Integer;
  RectangleSource: TRectangleMifSource;
  RectangleSources: TList<TRectangleMifSource>;
begin
  Result := False;
  Container := nil;
  Report.Clear;
  ErrorMessage := '';
  Candidate := nil;
  RectangleSources := TList<TRectangleMifSource>.Create;
  try
    try
      if Document = nil then
        raise EArgumentNilException.Create('Document');
      Canvas := Document.CanvasLayer;
      if Canvas = nil then
        raise EInvalidOp.Create('Document canvas is missing');
      if Canvas.Transparent then
        Report.AddIssue(meikConversion, 0, Canvas.Name,
          '透明キャンバスはMIF再読込時に不透明になります。');
      SetLength(PreparedImagePngs, Document.LayerCount);
      ImageIndex := 0;
      for I := 1 to Document.LayerCount - 1 do
        if Document[I] is TVectArtImageLayer then
        begin
          Inc(ImageIndex);
          TryPrepareImagePngForMif(TVectArtImageLayer(Document[I]), I,
            ImageIndex, Report, PreparedImagePngs[I]);
        end;
      if Report.Compatibility = mecUnsupported then
      begin
        ErrorMessage := 'MIFへ書き出せない項目があります。';
        Exit;
      end;
      CollectRectangleSources(SourceContainer, RectangleSources);
      Candidate := TVectArtMifContainer.Create;
      ContentChunkCount := 0;
      for I := 1 to Document.LayerCount - 1 do
      begin
        if Document[I] is TVectArtImageLayer then
          Inc(ContentChunkCount, 2)
        else if (Document[I] is TVectArtRectangleLayer) or
          (Document[I] is TVectArtLineLayer) or
          ((Document[I] is TVectArtPathLayer) and
          (MifPathExportShape(TVectArtPathLayer(Document[I])) <>
          mpesUnsupported)) then
          Inc(ContentChunkCount, 4);
      end;
      SetLength(Header, 4);
      // MHDRはヘッダーと終端を除く外側チャンク数を保持する。
      WriteUInt32BE(Header, 0, 2 + ContentChunkCount);
      Candidate.AddChunk('MHDR', Header);
      Candidate.AddChunk('IPNG', CreateCompositePng(Document));
      Candidate.AddChunk('IPNG', CreateTexturePng(Canvas.BackgroundColor));
      LineIndex := 0;
      PathIndex := 0;
      RectangleIndex := 0;
      for I := 1 to Document.LayerCount - 1 do
      begin
        Layer := Document[I];
        if Layer is TVectArtImageLayer then
        begin
          ImagePng := Copy(PreparedImagePngs[I]);
          Candidate.AddChunk('IPNG', ImagePng);
          Candidate.AddChunk('IPNG', CreateTexturePng(clWhite));
          Continue;
        end;
        if Layer is TVectArtLineLayer then
        begin
          Line := TVectArtLineLayer(Layer);
          AnalyzeLineExport(Line, I, LineIndex + 1, Report);
          Candidate.AddChunk('IPNG', CreateLineImagePng(Line));
          Candidate.AddChunk('IPNG', CreateTexturePng(clWhite));
          Candidate.AddChunk('IPNG', CreateLineVectorPng);
          Candidate.AddChunk('IPNG', CreateTexturePng(Line.StrokeColor));
          Inc(LineIndex);
          Continue;
        end;
        if Layer is TVectArtPathLayer then
        begin
          PathLayer := TVectArtPathLayer(Layer);
          PathExportShape := MifPathExportShape(PathLayer);
          AnalyzePathExport(PathLayer, I, PathIndex + 1, LineIndex + 1,
            Report);
          if PathExportShape = mpesUnsupported then
            Continue;
          if PathExportShape = mpesLine then
          begin
            ConvertedLine := CreateMifLineFromPath(PathLayer);
            try
              Candidate.AddChunk('IPNG', CreateLineImagePng(ConvertedLine));
              Candidate.AddChunk('IPNG', CreateTexturePng(clWhite));
              Candidate.AddChunk('IPNG', CreateLineVectorPng);
              Candidate.AddChunk('IPNG',
                CreateTexturePng(ConvertedLine.StrokeColor));
            finally
              ConvertedLine.Free;
            end;
            Inc(LineIndex)
          end
          else
          begin
            Candidate.AddChunk('IPNG', CreatePathImagePng(PathLayer));
            Candidate.AddChunk('IPNG',
              CreateTexturePng(PathLayer.FillColor));
            Candidate.AddChunk('IPNG', CreatePathVectorPng(PathLayer));
            Candidate.AddChunk('IPNG',
              CreateTexturePng(PathLayer.StrokeColor));
            Inc(PathIndex);
          end;
          Continue;
        end;
        if not (Layer is TVectArtRectangleLayer) then
        begin
          Report.AddIssue(meikUnsupported, I, Layer.Name,
            'このレイヤー種類はMIF Writerが対応していません。');
          Continue;
        end;
        Rectangle := TVectArtRectangleLayer(Layer);
        AnalyzeRectangleExport(Rectangle, I, RectangleIndex + 1, Report);
        RectangleSource := Default(TRectangleMifSource);
        if RectangleIndex < RectangleSources.Count then
          RectangleSource := RectangleSources[RectangleIndex];
        Candidate.AddChunk('IPNG', CreateRectangleImagePng(Rectangle,
          RectangleSource));
        Candidate.AddChunk('IPNG', CreateTexturePng(Rectangle.FillColor));
        Candidate.AddChunk('IPNG', CreateRectangleVectorPng(RectangleSource));
        Candidate.AddChunk('IPNG', CreateTexturePng(Rectangle.StrokeColor));
        Inc(RectangleIndex);
      end;
      Candidate.AddChunk('MEND', nil);
      if Report.Compatibility = mecUnsupported then
      begin
        ErrorMessage := 'MIFへ書き出せない項目があります。';
        Exit;
      end;
      Container := Candidate;
      Candidate := nil;
      Result := True;
    except
      on E: Exception do
        ErrorMessage := E.Message;
    end;
  finally
    RectangleSources.Free;
    Candidate.Free;
  end;
end;

end.
