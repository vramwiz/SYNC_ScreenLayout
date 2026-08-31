// AviUtl2へ「画面レイアウト」を登録し、編集ボタンとシリアライズ文字列項目だけを公開する。
unit ScreenLayoutFilterPlugin;

interface

uses
  System.SysUtils, AviUtl2FilterTypes;

// AviUtl2へ渡すフィルターテーブルを返す。
function GetScreenLayoutFilterTable: PFILTER_PLUGIN_TABLE;
// 将来の共通UI初期化に備えたDLL初期化境界。現段階では状態を持たない。
procedure InitializeScreenLayoutFilter;
// 将来の共通UI解放に備えたDLL終了境界。現段階では状態を持たない。
procedure FinalizeScreenLayoutFilter;

implementation

uses
  PluginFilterTable, ScreenLayoutEditorHost, ScreenLayoutFilterContext,
  System.UITypes, TextRendererSkiaBootstrap, TextRendererSkiaRuntime,
  Vcl.Dialogs;

const
  FILTER_EFFECT_NAME = '画面レイアウト';
  LAYOUT_DATA_ITEM_NAME = '配置データ';

var
  EditButton: TFILTER_ITEM_BUTTON;
  LayoutDataItem: TFILTER_ITEM_STRING;
  ScreenLayoutContexts: TScreenLayoutFilterContexts;
  ScreenLayoutSkiaAcquired: Boolean;

procedure EditButtonCallback(Edit: PEDIT_SECTION); cdecl;
var
  BackgroundHeight: Integer;
  BackgroundPixels: TBytes;
  BackgroundStatus: string;
  BackgroundWidth: Integer;
  Context: TScreenLayoutFilterContext;
  CurrentData: string;
  DataPointer: PAnsiChar;
  ErrorMessage: string;
  Obj: OBJECT_HANDLE;
  ObjectLocation: TOBJECT_LAYER_FRAME;
  UpdatedData: string;
  Utf8Data: UTF8String;
begin
  try
    if (Edit = nil) or not Assigned(Edit^.GetFocusObject) or
      not Assigned(Edit^.GetObjectLayerFrame) or
      not Assigned(Edit^.GetObjectItemValue) or
      not Assigned(Edit^.SetObjectItemValue) then
      raise EInvalidOp.Create('AviUtl2の編集APIを取得できませんでした。');
    Obj := Edit^.GetFocusObject();
    if Obj = nil then
      raise EInvalidOp.Create('編集対象のオブジェクトを取得できませんでした。');

    DataPointer := Edit^.GetObjectItemValue(Obj, FILTER_EFFECT_NAME,
      LAYOUT_DATA_ITEM_NAME);
    if DataPointer = nil then
      CurrentData := ''
    else
      CurrentData := string(UTF8String(DataPointer));

    BackgroundPixels := nil;
    BackgroundWidth := 0;
    BackgroundHeight := 0;
    ObjectLocation := Edit^.GetObjectLayerFrame(Obj);
    if ScreenLayoutContexts <> nil then
    begin
      Context := ScreenLayoutContexts.FindByObjectLocation(
        ObjectLocation.Layer, ObjectLocation.StartFrame,
        ObjectLocation.EndFrame);
      if Context <> nil then
        Context.CopyBackground(BackgroundPixels, BackgroundWidth,
          BackgroundHeight, BackgroundStatus);
    end;

    if not EditScreenLayout(CurrentData, BackgroundPixels,
      BackgroundWidth, BackgroundHeight, UpdatedData, ErrorMessage) then
      raise EInvalidOp.Create('画面レイアウトを編集できませんでした。'#13#10 +
        ErrorMessage);

    Utf8Data := UTF8String(UpdatedData);
    if not Edit^.SetObjectItemValue(Obj, FILTER_EFFECT_NAME,
      LAYOUT_DATA_ITEM_NAME, PAnsiChar(Utf8Data)) then
      raise EInvalidOp.Create('配置データをAviUtl2へ保存できませんでした。');
  except
    on E: Exception do
      MessageDlg(E.Message, mtError, [mbOK], 0);
  end;
end;

function PassThroughVideo(Video: PFILTER_PROC_VIDEO): Byte; cdecl;
var
  Context: TScreenLayoutFilterContext;
  SerializedData: string;
begin
  Result := 1;
  try
    // AviUtl2は呼び出し対象の現在値を項目レコードへ設定してから呼び出す。
    if LayoutDataItem.Value = nil then
      SerializedData := ''
    else
      SerializedData := string(LayoutDataItem.Value);
    if ScreenLayoutContexts <> nil then
    begin
      Context := ScreenLayoutContexts.GetContext(Video);
      if Context <> nil then
      begin
        Context.UpdateSerializedData(SerializedData);
        Context.CaptureBackground(Video);
        Context.RenderVideo(Video);
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
  FreeAndNil(ScreenLayoutContexts);
  if ScreenLayoutSkiaAcquired then
  begin
    TTextRendererSkiaRuntime.Release;
    ScreenLayoutSkiaAcquired := False;
  end;
end;

function GetScreenLayoutFilterTable: PFILTER_PLUGIN_TABLE;
begin
  if GTable.Name = nil then
  begin
    AddButton(EditButton, '編集', EditButtonCallback);
    AddString(LayoutDataItem, LAYOUT_DATA_ITEM_NAME, '');
    SetupPluginTable(FILTER_FLAG_VIDEO or FILTER_FLAG_FILTER,
      FILTER_EFFECT_NAME,
      'SYNC',
      '文字や線を配置する画面レイアウトフィルター',
      PassThroughVideo,
      nil);
  end;
  Result := @GTable;
end;

end.
