// 編集要求と描画コールバックを照合し、フィルター入力を一度だけUIへ渡す。
unit ScreenLayoutFrameCapture;

interface

uses
  AviUtl2FilterTypes, System.SyncObjs, System.SysUtils;

type
  TScreenLayoutCaptureTarget = record
    SceneID: Integer;    // 編集対象のシーン。
    Frame: Integer;      // クリック時のシーン基準フレーム。
    ObjectLayer: Integer; // エフェクトを所有するオブジェクトのレイヤー。
    ObjectID: Int64;     // 所有オブジェクトの起動中の固有ID。
    EffectID: Int64;     // 対象エフェクトの起動中の固有ID。
  end;

  TScreenLayoutCapturedFrame = record
    Width, Height: Integer; // フィルターへ渡された画像寸法。
    Pixels: TBytes;         // 所有する密詰めRGBA。公開後は読み取り専用。
  end;

  TScreenLayoutFrameCapture = class
  private
    FArmed: Integer;                     // 要求がない映像コールバックはロックを取らない。
    FLock: TCriticalSection;             // 対象、要求ID、返信を保護する。
    FReply: TScreenLayoutCapturedFrame;  // 受領までの完成済み画像。
    FRequestID: NativeUInt;              // 0は待機中の要求なし。
    FTarget: TScreenLayoutCaptureTarget; // 対象の識別情報。ホストのハンドルは保持しない。
    function Claim(Video: PFILTER_PROC_VIDEO): NativeUInt;
  public
    constructor Create;
    destructor Destroy; override;
    // 1件の取得要求を登録し、それ以前の要求と未受領画像を破棄する。
    procedure Arm(const Target: TScreenLayoutCaptureTarget; RequestID: NativeUInt);
    // 一致した映像コールバックだけが、重ね描き前の画像を所有バッファへ取得する。
    // UIへ通知すべき要求IDを返し、取得済み画像は出力用の入力としても共有する。
    function Capture(Video: PFILTER_PROC_VIDEO; out Pixels: TBytes): NativeUInt;
    // 該当する要求を終了し、到着済みの画像があればUIへ所有権を渡す。
    procedure Take(RequestID: NativeUInt; out Frame: TScreenLayoutCapturedFrame);
  end;

implementation

const
  MAX_CAPTURE_DIMENSION = 16384; // 映像出力と同じ有効寸法の上限。

constructor TScreenLayoutFrameCapture.Create;
begin
  inherited Create;
  FLock := TCriticalSection.Create;
end;

destructor TScreenLayoutFrameCapture.Destroy;
begin
  FLock.Free;
  inherited Destroy;
end;

procedure TScreenLayoutFrameCapture.Arm(const Target: TScreenLayoutCaptureTarget;
  RequestID: NativeUInt);
begin
  FLock.Acquire;
  try
    FReply := Default(TScreenLayoutCapturedFrame);
    FRequestID := RequestID;
    FTarget := Target;
    TInterlocked.Exchange(FArmed, 1);
  finally
    FLock.Release;
  end;
end;

function TScreenLayoutFrameCapture.Claim(Video: PFILTER_PROC_VIDEO): NativeUInt;
begin
  Result := 0;
  if (TInterlocked.CompareExchange(FArmed, 0, 0) = 0) or
    (Video = nil) or (Video^.Scene = nil) or (Video^.Object_ = nil) then
    Exit;

  FLock.Acquire;
  try
    if (FArmed <> 0) and (Video^.Scene^.ID = FTarget.SceneID) and
      (Video^.Scene^.OriginID = FTarget.SceneID) and
      ((Video^.Scene^.Flag and SCENE_FLAG_REFERENCE_FRAME) = 0) and
      (Video^.Object_^.OriginFrame = FTarget.Frame) and
      (Video^.Object_^.EffectLayer = FTarget.ObjectLayer) and
      (Video^.Object_^.ID = FTarget.ObjectID) and
      (Video^.Object_^.EffectID = FTarget.EffectID) then
    begin
      TInterlocked.Exchange(FArmed, 0);
      Result := FRequestID;
    end;
  finally
    FLock.Release;
  end;
end;

function TScreenLayoutFrameCapture.Capture(Video: PFILTER_PROC_VIDEO;
  out Pixels: TBytes): NativeUInt;
var
  Frame: TScreenLayoutCapturedFrame;
  Height, Width: Integer;
  RequestID: NativeUInt;
begin
  Result := 0;
  Pixels := nil;
  RequestID := Claim(Video);
  if RequestID = 0 then
    Exit;

  Width := Video^.Object_^.Width;
  Height := Video^.Object_^.Height;
  if Assigned(Video^.GetImageData) and (Width > 0) and (Height > 0) and
    (Width <= MAX_CAPTURE_DIMENSION) and (Height <= MAX_CAPTURE_DIMENSION) then
  begin
    SetLength(Pixels, NativeInt(Width) * Height * SizeOf(TPIXEL_RGBA));
    Video^.GetImageData(PPIXEL_RGBA(Pixels));
    Frame.Width := Width;
    Frame.Height := Height;
    Frame.Pixels := Pixels;
  end
  else
    Frame := Default(TScreenLayoutCapturedFrame);

  FLock.Acquire;
  try
    // 取得中に要求が失効しても、現在の映像の合成には取得済みの入力を使える。
    if FRequestID = RequestID then
    begin
      FReply := Frame;
      Result := RequestID;
    end;
  finally
    FLock.Release;
  end;
end;

procedure TScreenLayoutFrameCapture.Take(RequestID: NativeUInt; out Frame: TScreenLayoutCapturedFrame);
begin
  Frame := Default(TScreenLayoutCapturedFrame);
  FLock.Acquire;
  try
    if (RequestID <> 0) and (FRequestID = RequestID) then
    begin
      TInterlocked.Exchange(FArmed, 0);
      FRequestID := 0;
      Frame := FReply;
      FReply := Default(TScreenLayoutCapturedFrame);
    end;
  finally
    FLock.Release;
  end;
end;

end.
