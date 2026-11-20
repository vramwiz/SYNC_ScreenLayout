// 画面レイアウトのシリアライズ値と解析済みDocumentをAviUtl2オブジェクト単位で保持する。
unit ScreenLayoutFilterContext;

interface

uses
  AviUtl2FilterTypes, PluginFilterContextManager,
  System.SysUtils, Winapi.Windows, ScreenLayoutDocument, ScreenLayoutRenderer;

type
  TScreenLayoutFilterContext = class(TPluginFilterContextItem)
  private
    FDocument: TVectArtDocument;
    FLastAttemptedData: string;
    FLastError: string;
    FOutputBuffer: TVectArtRenderBuffer;
    FOutputHeight: Integer;                 // 最後に描画した有効な出力高さ。
    FOutputSizeLock: TRTLCriticalSection;   // 映像処理と設定画面の寸法共有を保護する。
    FOutputWidth: Integer;                  // 最後に描画した有効な出力幅。
    FOverlayBuffer: TVectArtRenderBuffer;
    FRenderedRevision: Int64;
    FSerializedData: string;
  public
    constructor Create;
    destructor Destroy; override;
    // 映像コールバックが最後に使用した有効な出力寸法をスレッド安全に返す。
    function CopyOutputSize(out Width, Height: Integer): Boolean;
    // RGBAを入力映像へ合成する。同じコールバックで取得済みなら入力を再利用する。
    function RenderVideo(Video: PFILTER_PROC_VIDEO; const CapturedInput: TBytes = nil): Boolean;
    // 設定値が変わったときだけDocumentを更新し、解析失敗時は直前の正常状態を保つ。
    function UpdateSerializedData(const Value: string): Boolean;
    property Document: TVectArtDocument read FDocument;
    property LastError: string read FLastError;
    property SerializedData: string read FSerializedData;
  end;

  TScreenLayoutFilterContexts = class(TPluginFilterContextList<TScreenLayoutFilterContext>);

implementation

uses
  ScreenLayoutDocumentJson;

constructor TScreenLayoutFilterContext.Create;
begin
  inherited Create;
  InitializeCriticalSection(FOutputSizeLock);
  FDocument := TVectArtDocument.Create;
  FOutputBuffer := TVectArtRenderBuffer.Create;
  FOverlayBuffer := TVectArtRenderBuffer.Create;
  FRenderedRevision := -1;
end;

destructor TScreenLayoutFilterContext.Destroy;
begin
  DeleteCriticalSection(FOutputSizeLock);
  FOverlayBuffer.Free;
  FOutputBuffer.Free;
  FDocument.Free;
  inherited Destroy;
end;

function TScreenLayoutFilterContext.RenderVideo(Video: PFILTER_PROC_VIDEO;
  const CapturedInput: TBytes): Boolean;
var
  ByteCount: NativeInt;
  Height: Integer;
  Width: Integer;
begin
  Result := False;
  if (Video = nil) or not Assigned(Video^.SetImageData) then
    Exit;
  Width := 0;
  Height := 0;
  if Video^.Object_ <> nil then
  begin
    Width := Video^.Object_^.Width;
    Height := Video^.Object_^.Height;
  end;
  if ((Width <= 0) or (Height <= 0)) and (Video^.Scene <> nil) then
  begin
    Width := Video^.Scene^.Width;
    Height := Video^.Scene^.Height;
  end;
  if (Width <= 0) or (Height <= 0) or
    (Width > 16384) or (Height > 16384) then
    Exit;
  EnterCriticalSection(FOutputSizeLock);
  try
    FOutputWidth := Width;
    FOutputHeight := Height;
  finally
    LeaveCriticalSection(FOutputSizeLock);
  end;

  if (FRenderedRevision <> FDocument.Revision) or
    (FOverlayBuffer.Width <> Width) or (FOverlayBuffer.Height <> Height) then
  begin
    RenderVectArtDocument(FDocument, FOverlayBuffer, Width, Height);
    FRenderedRevision := FDocument.Revision;
  end;
  FOutputBuffer.SetSize(Width, Height);
  ByteCount := NativeInt(Width) * Height * SizeOf(TPIXEL_RGBA);
  if Length(CapturedInput) = ByteCount then
    Move(CapturedInput[0], FOutputBuffer.Data^, ByteCount)
  else if Assigned(Video^.GetImageData) then
    Video^.GetImageData(PPIXEL_RGBA(FOutputBuffer.Data))
  else
    FOutputBuffer.Clear;
  CompositeVectArtRgba(FOverlayBuffer, FOutputBuffer.Data, Width, Height);
  Video^.SetImageData(PPIXEL_RGBA(FOutputBuffer.Data), Width, Height);
  Result := True;
end;

function TScreenLayoutFilterContext.CopyOutputSize(out Width,
  Height: Integer): Boolean;
begin
  EnterCriticalSection(FOutputSizeLock);
  try
    Width := FOutputWidth;
    Height := FOutputHeight;
  finally
    LeaveCriticalSection(FOutputSizeLock);
  end;
  Result := (Width > 0) and (Height > 0);
end;

function TScreenLayoutFilterContext.UpdateSerializedData(const Value: string): Boolean;
var
  ErrorMessage: string;
  NewDocument: TVectArtDocument;
begin
  if Value = FLastAttemptedData then
    Exit(FLastError = '');

  FLastAttemptedData := Value;
  FLastError := '';
  NewDocument := TVectArtDocument.Create;
  try
    if (Value <> '') and
      not TryDeserializeVectArtDocument(Value, NewDocument, ErrorMessage) then
    begin
      FLastError := ErrorMessage;
      Exit(False);
    end;
    FDocument.Free;
    FDocument := NewDocument;
    NewDocument := nil;
    FRenderedRevision := -1;
    FSerializedData := Value;
    Result := True;
  finally
    NewDocument.Free;
  end;
end;

end.
