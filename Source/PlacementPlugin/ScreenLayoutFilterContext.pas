// 画面レイアウトのシリアライズ値と解析済みDocumentをAviUtl2オブジェクト単位で保持する。
unit ScreenLayoutFilterContext;

interface

uses
  AviUtl2FilterTypes, PluginFilterContextManager, ScreenLayoutFrameCapture,
  System.SysUtils, VectArtDesignerDocument, VectArtDesignerRenderer;

type
  TScreenLayoutFilterContext = class(TPluginFilterContextItem)
  private
    FFrameCapture: TScreenLayoutFrameCapture;
    FDocument: TVectArtDocument;
    FLastAttemptedData: string;
    FLastError: string;
    FOutputBuffer: TVectArtRenderBuffer;
    FOverlayBuffer: TVectArtRenderBuffer;
    FRenderedRevision: Int64;
    FSerializedData: string;
  public
    constructor Create;
    destructor Destroy; override;
    // 対象オブジェクト評価時のAviUtl2合成済み背景を更新する。
    procedure CaptureBackground(Video: PFILTER_PROC_VIDEO);
    // 設定画面が使用する最新背景を呼び出し側所有の配列で返す。
    function CopyBackground(out Pixels: TBytes; out Width, Height: Integer;
      out Status: string): Boolean;
    // 共通レンダラーのRGBAを入力映像へ合成してAviUtl2へ返す。
    function RenderVideo(Video: PFILTER_PROC_VIDEO): Boolean;
    // 設定値が変わったときだけDocumentを更新し、解析失敗時は直前の正常状態を保つ。
    function UpdateSerializedData(const Value: string): Boolean;
    property Document: TVectArtDocument read FDocument;
    property LastError: string read FLastError;
    property SerializedData: string read FSerializedData;
  end;

  TScreenLayoutFilterContexts = class(TPluginFilterContextList<TScreenLayoutFilterContext>);

implementation

uses
  VectArtDesignerDocumentJson;

constructor TScreenLayoutFilterContext.Create;
begin
  inherited Create;
  FDocument := TVectArtDocument.Create;
  FFrameCapture := TScreenLayoutFrameCapture.Create;
  FOutputBuffer := TVectArtRenderBuffer.Create;
  FOverlayBuffer := TVectArtRenderBuffer.Create;
  FRenderedRevision := -1;
end;

destructor TScreenLayoutFilterContext.Destroy;
begin
  FOverlayBuffer.Free;
  FOutputBuffer.Free;
  FFrameCapture.Free;
  FDocument.Free;
  inherited Destroy;
end;

function TScreenLayoutFilterContext.RenderVideo(
  Video: PFILTER_PROC_VIDEO): Boolean;
var
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

  if (FRenderedRevision <> FDocument.Revision) or
    (FOverlayBuffer.Width <> Width) or (FOverlayBuffer.Height <> Height) then
  begin
    RenderVectArtDocument(FDocument, FOverlayBuffer, Width, Height);
    FRenderedRevision := FDocument.Revision;
  end;
  FOutputBuffer.SetSize(Width, Height);
  if Assigned(Video^.GetImageData) then
    Video^.GetImageData(PPIXEL_RGBA(FOutputBuffer.Data))
  else
    FOutputBuffer.Clear;
  CompositeVectArtRgba(FOverlayBuffer, FOutputBuffer.Data, Width, Height);
  Video^.SetImageData(PPIXEL_RGBA(FOutputBuffer.Data), Width, Height);
  Result := True;
end;

procedure TScreenLayoutFilterContext.CaptureBackground(
  Video: PFILTER_PROC_VIDEO);
begin
  FFrameCapture.Capture(Video);
end;

function TScreenLayoutFilterContext.CopyBackground(out Pixels: TBytes;
  out Width, Height: Integer; out Status: string): Boolean;
begin
  Result := FFrameCapture.CopyRgba(Pixels, Width, Height, Status);
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
