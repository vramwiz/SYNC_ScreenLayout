// AviUtl2へ「画面レイアウト」を登録し、映像処理と編集要求を接続する。
unit ScreenLayoutFilterPlugin;

interface

uses
  AviUtl2FilterTypes;

const
  SCREEN_LAYOUT_REQUIRED_HOST = 2011000; // callback2とオブジェクト／エフェクトIDを利用する下限。

// ホストの編集ハンドルを取得し、従来と同じ名前でフィルターを登録する。
procedure RegisterScreenLayoutFilter(Host: PHOST_APP_TABLE);
// AviUtl2がDLLをロードし終えた後に、Skiaランタイムとフィルター状態を初期化する。
procedure InitializeScreenLayoutFilter;
// 編集要求、フィルター状態、Skiaランタイムを解放する。
procedure FinalizeScreenLayoutFilter;

implementation

uses
  PluginFilterTable, ScreenLayoutEditorHost, ScreenLayoutFilterContext,
  System.SysUtils, System.UITypes, TextRendererSkiaBootstrap,
  TextRendererSkiaRuntime, Vcl.Dialogs, Winapi.Windows;

const
  FILTER_EFFECT_NAME = '画面レイアウト'; // 既存プロジェクトのエフェクト識別名。

var
  EditButton: TFILTER_ITEM_BUTTON;
  LayoutDataItem: TFILTER_ITEM_STRING;
  ScreenLayoutContexts: TScreenLayoutFilterContexts;
  ScreenLayoutEditor: TScreenLayoutEditorHost;
  ScreenLayoutSkiaAcquired: Boolean;

procedure EditButtonCallback(Edit: PEDIT_SECTION; Obj: OBJECT_HANDLE; Effect, Item: LPCWSTR); cdecl;
begin
  try
    ScreenLayoutEditor.BeginEdit(Edit, Obj, Effect);
  except
    on E: Exception do
      MessageDlg(E.Message, mtError, [mbOK], 0);
  end;
end;

function PassThroughVideo(Video: PFILTER_PROC_VIDEO): Byte; cdecl;
var
  CapturedInput: TBytes;
  Context: TScreenLayoutFilterContext;
  SerializedData: string;
begin
  Result := 1;
  try
    if ScreenLayoutEditor <> nil then
      try
        ScreenLayoutEditor.CaptureInput(Video, CapturedInput);
      except
        on E: Exception do
        begin
          CapturedInput := nil;
          OutputDebugString(PChar('SYNC_ScreenLayout: ' + E.Message));
        end;
      end;

    // AviUtl2は呼び出し対象の現在値を項目レコードへ設定してから呼び出す。
    SerializedData := string(LayoutDataItem.Value);
    if ScreenLayoutContexts <> nil then
    begin
      Context := ScreenLayoutContexts.GetContext(Video);
      if Context <> nil then
      begin
        Context.UpdateSerializedData(SerializedData);
        Context.RenderVideo(Video, CapturedInput);
      end;
    end;
  except
    // Delphi例外をAviUtl2の映像コールバック境界より外へ漏らさない。
  end;
end;

procedure InitializeScreenLayoutFilter;
begin
  if not ScreenLayoutSkiaAcquired then
  begin
    TTextRendererSkiaRuntime.Acquire(BundledSkiaRuntimeFileName);
    ScreenLayoutSkiaAcquired := True;
  end;
  try
    if ScreenLayoutContexts = nil then
      ScreenLayoutContexts := TScreenLayoutFilterContexts.Create;
  except
    if ScreenLayoutSkiaAcquired then
    begin
      TTextRendererSkiaRuntime.Release;
      ScreenLayoutSkiaAcquired := False;
    end;
    raise;
  end;
end;

procedure FinalizeScreenLayoutFilter;
begin
  FreeAndNil(ScreenLayoutEditor);
  FreeAndNil(ScreenLayoutContexts);
  if ScreenLayoutSkiaAcquired then
  begin
    TTextRendererSkiaRuntime.Release;
    ScreenLayoutSkiaAcquired := False;
  end;
end;

procedure RegisterScreenLayoutFilter(Host: PHOST_APP_TABLE);
var
  EditHandle: PEDIT_HANDLE;
begin
  if (Host = nil) or not Assigned(Host^.CreateEditHandle) or not Assigned(Host^.RegisterFilterPlugin) then
    raise EInvalidOp.Create('AviUtl2のプラグイン登録APIを取得できませんでした。');
  EditHandle := Host^.CreateEditHandle();
  if (EditHandle = nil) or not Assigned(EditHandle^.CallEditSectionParam) or
    not Assigned(EditHandle^.GetEditState) then
    raise EInvalidOp.Create('AviUtl2の編集APIを取得できませんでした。');

  ScreenLayoutEditor := TScreenLayoutEditorHost.Create(EditHandle, ScreenLayoutContexts);
  AddButton(EditButton, '編集', EditButtonCallback);
  AddString(LayoutDataItem, SCREEN_LAYOUT_DATA_ITEM_NAME, '');
  SetupPluginTable(FILTER_FLAG_VIDEO or FILTER_FLAG_FILTER,
    FILTER_EFFECT_NAME, 'SYNC', '文字や線を配置する画面レイアウトフィルター', PassThroughVideo, nil);
  Host^.RegisterFilterPlugin(@GTable);
end;

end.
