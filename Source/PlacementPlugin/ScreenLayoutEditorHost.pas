// AviUtl2の編集要求、参照背景の受領、配置データの保存をUIスレッドで調整する。
unit ScreenLayoutEditorHost;

interface

uses
  AviUtl2FilterTypes, ScreenLayoutFilterContext, ScreenLayoutFrameCapture,
  System.SysUtils, Winapi.Messages, Winapi.Windows;

const
  SCREEN_LAYOUT_DATA_ITEM_NAME = '配置データ'; // 既存プロジェクトの保存キー。

type
  TScreenLayoutEditorHost = class
  private type
    TEditRequest = record
      Target: TScreenLayoutCaptureTarget; // クリック時の対象。ホストのポインターは保持しない。
      ObjectStart: Integer;              // 保存時にオブジェクトを探す開始フレーム。
      EffectName: string;                // 同名エフェクトの番号を含むホストの指定名。
      OriginalData: string;              // UIを開いている間の競合検出用。
      UpdatedData: string;               // 保存コールバックへ渡すJSON。
      CanvasWidth, CanvasHeight: Integer; // 背景を取得できなかった場合の寸法。
      Saved: Boolean;                    // 保存コールバックが設定変更に成功したか。
    end;
  private
    FCapture: TScreenLayoutFrameCapture;    // 描画スレッドとUIスレッドの受け渡し。
    FContexts: TScreenLayoutFilterContexts; // プラグインが所有する描画コンテキスト一覧。
    FEditHandle: PEDIT_HANDLE;              // ホストが所有する編集操作用ハンドル。
    FEditorOpen: Boolean;                  // モーダル編集中の再入を防ぐ。
    FLastRequestID: NativeUInt;             // UIスレッドで採番する要求ID。
    FPendingRequestID: NativeUInt;          // UIが現在待機中の要求ID。0なら待機なし。
    FRequest: TEditRequest;                 // UIスレッドだけが参照する編集要求。
    FWindow: HWND;                          // ホストUIスレッドの通知受信先。
    procedure OpenPendingEditor;
    procedure WindowProc(var Msg: TMessage);
    class procedure SaveLayout(Param: Pointer; Edit: PEDIT_SECTION); cdecl; static;
  public
    constructor Create(EditHandle: PEDIT_HANDLE; Contexts: TScreenLayoutFilterContexts);
    destructor Destroy; override;
    // ボタンの対象を記録し、停止中の有効区間内なら同じ位置の描画を依頼する。
    procedure BeginEdit(Edit: PEDIT_SECTION; Obj: OBJECT_HANDLE; Effect: LPCWSTR);
    // 一致する入力を取得し、UIへ非同期に通知する。描画側も取得済みRGBAを再利用できる。
    procedure CaptureInput(Video: PFILTER_PROC_VIDEO; out Pixels: TBytes);
  end;

implementation

uses
  System.Classes, System.UITypes, Vcl.Dialogs, Vcl.Forms,
  ScreenLayoutDocumentJson, ScreenLayoutMainForm, ScreenLayoutPluginDocument;

const
  WM_CAPTURE_READY = WM_APP + 153; // WParamは要求ID。画像は共有する所有バッファで渡す。
  CAPTURE_TIMEOUT_MS = 2500;       // この時間で保留を打ち切り、参照背景なしで開く。

function EnterEditorDpiContext: DPI_AWARENESS_CONTEXT;
begin
  try
    // 編集Formを96 DPI座標でWindowsに拡大させ、固定描画部品の寸法差を防ぐ。
    Result := SetThreadDpiAwarenessContext(
      DPI_AWARENESS_CONTEXT_UNAWARE_GDISCALED);
    if not IsValidDpiAwarenessContext(Result) then
      Result := SetThreadDpiAwarenessContext(DPI_AWARENESS_CONTEXT_UNAWARE);
  except
    // APIを持たない旧環境ではホストのDPIコンテキストを維持する。
    Result := Default(DPI_AWARENESS_CONTEXT);
  end;
end;

procedure RestoreEditorDpiContext(PreviousContext: DPI_AWARENESS_CONTEXT);
begin
  if not IsValidDpiAwarenessContext(PreviousContext) then
    Exit;
  try
    SetThreadDpiAwarenessContext(PreviousContext);
  except
    // 編集Formは破棄済みのため、復元APIが失敗しても終了処理を継続する。
  end;
end;

function ReadLayout(Edit: PEDIT_SECTION; Effect: EFFECT_HANDLE): string;
var
  Value: PAnsiChar;
begin
  Value := Edit^.GetEffectItemValue(Effect, SCREEN_LAYOUT_DATA_ITEM_NAME);
  if Value = nil then
    Exit('');
  Result := string(UTF8String(Value));
end;

function EditScreenLayout(const SerializedData: string;
  const Frame: TScreenLayoutCapturedFrame; CanvasWidth, CanvasHeight: Integer): string;
var
  Baseline: string;
  EditedData: string;
  EditorForm: TMainForm;
  ErrorMessage: string;
  PreviousDpiContext: DPI_AWARENESS_CONTEXT;
begin
  EditorForm := nil;
  PreviousDpiContext := EnterEditorDpiContext;
  try
    EditorForm := TMainForm.Create(nil);
    EditorForm.Caption := '画面レイアウト - 編集';
    EditorForm.Position := poScreenCenter;
    EditorForm.SetFileDropCaptionEnabled(True);
    EditorForm.SetCanvasSettingsVisible(False);
    EditorForm.EnableCodexPrompt;
    EditorForm.SetReferenceBackgroundRgba(Frame.Pixels, Frame.Width, Frame.Height);
    if not InitializeScreenLayoutPluginDocument(EditorForm.Document,
      SerializedData, CanvasWidth, CanvasHeight, ErrorMessage) then
      raise EInvalidOp.Create('画面レイアウトを編集できませんでした。'#13#10 + ErrorMessage);
    Baseline := SerializeVectArtDocument(EditorForm.Document);
    EditorForm.ShowModal;
    EditedData := SerializeVectArtDocument(EditorForm.Document);
    // 開閉だけで未設定値や既存のJSON表記を書き換えない。
    Result := SerializedData;
    if EditedData <> Baseline then
      Result := EditedData;
  finally
    EditorForm.Free;
    RestoreEditorDpiContext(PreviousDpiContext);
  end;
end;

constructor TScreenLayoutEditorHost.Create(EditHandle: PEDIT_HANDLE;
  Contexts: TScreenLayoutFilterContexts);
begin
  inherited Create;
  FEditHandle := EditHandle;
  FContexts := Contexts;
  FCapture := TScreenLayoutFrameCapture.Create;
  FWindow := AllocateHWnd(WindowProc);
  if FWindow = 0 then
    RaiseLastOSError;
end;

destructor TScreenLayoutEditorHost.Destroy;
var
  Frame: TScreenLayoutCapturedFrame;
begin
  if FWindow <> 0 then
  begin
    if FPendingRequestID <> 0 then
    begin
      KillTimer(FWindow, FPendingRequestID);
      FCapture.Take(FPendingRequestID, Frame);
    end;
    DeallocateHWnd(FWindow);
  end;
  FCapture.Free;
  inherited Destroy;
end;

procedure TScreenLayoutEditorHost.BeginEdit(Edit: PEDIT_SECTION;
  Obj: OBJECT_HANDLE; Effect: LPCWSTR);
var
  CanCapture: Boolean;
  Context: TScreenLayoutFilterContext;
  EffectHandle: EFFECT_HANDLE;
  Frame: TScreenLayoutCapturedFrame;
  Info: TEDIT_INFO;
  Location: TOBJECT_LAYER_FRAME;
  Target: TScreenLayoutCaptureTarget;
begin
  if FEditorOpen or (FPendingRequestID <> 0) then
    Exit;
  if (Edit = nil) or (Edit^.Info = nil) or (Obj = nil) or (Effect = nil) or
    not Assigned(Edit^.GetObjectLayerFrame) or not Assigned(Edit^.FindEffect) or
    not Assigned(Edit^.GetObjectID) or not Assigned(Edit^.GetEffectID) or
    not Assigned(Edit^.GetEffectItemValue) then
    raise EInvalidOp.Create('AviUtl2の編集対象を取得できませんでした。');

  EffectHandle := Edit^.FindEffect(Obj, Effect);
  if EffectHandle = nil then
    raise EInvalidOp.Create('画面レイアウトのエフェクトを取得できませんでした。');

  Info := Edit^.Info^;
  Location := Edit^.GetObjectLayerFrame(Obj);
  Target.SceneID := Info.SceneID;
  Target.Frame := Info.Frame;
  Target.ObjectLayer := Location.Layer;
  Target.ObjectID := Edit^.GetObjectID(Obj);
  Target.EffectID := Edit^.GetEffectID(EffectHandle);
  if (Target.ObjectID = 0) or (Target.EffectID = 0) then
    raise EInvalidOp.Create('AviUtl2の編集対象を識別できませんでした。');

  FRequest.Target := Target;
  FRequest.ObjectStart := Location.StartFrame;
  FRequest.EffectName := string(Effect);
  FRequest.OriginalData := ReadLayout(Edit, EffectHandle);
  Context := FContexts.FindByKey(Target.ObjectID, Target.EffectID);
  if (Context = nil) or not Context.CopyOutputSize(FRequest.CanvasWidth, FRequest.CanvasHeight) then
  begin
    FRequest.CanvasWidth := Info.Width;
    FRequest.CanvasHeight := Info.Height;
  end;

  CanCapture := Assigned(Edit^.SetCursorLayerFrame) and
    (FEditHandle^.GetEditState() = AVIUTL2_EDIT_STATE_EDIT) and
    (Target.Frame >= Location.StartFrame) and (Target.Frame <= Location.EndFrame);
  Inc(FLastRequestID);
  FPendingRequestID := FLastRequestID;
  try
    if CanCapture then
    begin
      if SetTimer(FWindow, FPendingRequestID, CAPTURE_TIMEOUT_MS, nil) = 0 then
        RaiseLastOSError;
      FCapture.Arm(Target, FPendingRequestID);
      // ホストが描画を呼べるよう、共有ロックを解放した状態で現在位置を再設定する。
      Edit^.SetCursorLayerFrame(Info.Layer, Info.Frame);
    end
    else if not PostMessage(FWindow, WM_CAPTURE_READY, WPARAM(FPendingRequestID), 0) then
      RaiseLastOSError;
  except
    KillTimer(FWindow, FPendingRequestID);
    FCapture.Take(FPendingRequestID, Frame);
    FPendingRequestID := 0;
    FRequest := Default(TEditRequest);
    raise;
  end;
end;

procedure TScreenLayoutEditorHost.CaptureInput(Video: PFILTER_PROC_VIDEO; out Pixels: TBytes);
var
  RequestID: NativeUInt;
begin
  RequestID := FCapture.Capture(Video, Pixels);
  if RequestID <> 0 then
    PostMessage(FWindow, WM_CAPTURE_READY, WPARAM(RequestID), 0);
end;

class procedure TScreenLayoutEditorHost.SaveLayout(Param: Pointer; Edit: PEDIT_SECTION);
var
  Effect: EFFECT_HANDLE;
  Obj: OBJECT_HANDLE;
  Request: ^TEditRequest;
  Value: UTF8String;
begin
  try
    Request := Param;
    if (Edit = nil) or (Edit^.Info = nil) or
      (Edit^.Info^.SceneID <> Request^.Target.SceneID) then
      Exit;
    Obj := Edit^.FindObject(Request^.Target.ObjectLayer, Request^.ObjectStart);
    if (Obj = nil) or (Edit^.GetObjectID(Obj) <> Request^.Target.ObjectID) then
      Exit;
    Effect := Edit^.FindEffect(Obj, PWideChar(Request^.EffectName));
    if (Effect = nil) or (Edit^.GetEffectID(Effect) <> Request^.Target.EffectID) or
      (ReadLayout(Edit, Effect) <> Request^.OriginalData) then
      Exit;
    Value := UTF8String(Request^.UpdatedData);
    Request^.Saved := Edit^.SetEffectItemValue(Effect, SCREEN_LAYOUT_DATA_ITEM_NAME, PAnsiChar(Value));
  except
    on E: Exception do
      OutputDebugString(PChar('SYNC_ScreenLayout: ' + E.Message));
  end;
end;

procedure TScreenLayoutEditorHost.OpenPendingEditor;
var
  Frame: TScreenLayoutCapturedFrame;
  Request: TEditRequest;
begin
  KillTimer(FWindow, FPendingRequestID);
  FCapture.Take(FPendingRequestID, Frame);
  FPendingRequestID := 0;
  Request := FRequest;
  FRequest := Default(TEditRequest);
  if Length(Frame.Pixels) <> 0 then
  begin
    Request.CanvasWidth := Frame.Width;
    Request.CanvasHeight := Frame.Height;
  end;

  FEditorOpen := True;
  try
    Request.UpdatedData := EditScreenLayout(Request.OriginalData, Frame,
      Request.CanvasWidth, Request.CanvasHeight);
    if (Request.UpdatedData <> Request.OriginalData) and
      (not FEditHandle^.CallEditSectionParam(@Request, SaveLayout) or not Request.Saved) then
      raise EInvalidOp.Create('配置データをAviUtl2へ保存できませんでした。編集対象を確認してください。');
  finally
    FEditorOpen := False;
  end;
end;

procedure TScreenLayoutEditorHost.WindowProc(var Msg: TMessage);
begin
  try
    case Msg.Msg of
      WM_CAPTURE_READY, WM_TIMER:
        if (FPendingRequestID <> 0) and (Msg.WParam = WPARAM(FPendingRequestID)) then
          OpenPendingEditor;
    else
      Msg.Result := DefWindowProc(FWindow, Msg.Msg, Msg.WParam, Msg.LParam);
    end;
  except
    on E: Exception do
      MessageDlg(E.Message, mtError, [mbOK], 0);
  end;
end;

end.
