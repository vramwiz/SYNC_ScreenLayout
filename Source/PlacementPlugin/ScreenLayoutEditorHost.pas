// AviUtl2の文字列データと共通デザイナー画面を接続するプラグイン用ホスト。
unit ScreenLayoutEditorHost;

interface

uses
  System.SysUtils;

// 保存値と参照背景を編集画面へ渡し、確定後のversion 14 JSONまたは失敗理由を返す。
function EditScreenLayout(const SerializedData: string;
  const BackgroundPixels: TBytes; BackgroundWidth, BackgroundHeight: Integer;
  CanvasWidth, CanvasHeight: Integer;
  out UpdatedData, ErrorMessage: string): Boolean;

implementation

uses
  Vcl.Forms, ScreenLayoutDocumentJson, ScreenLayoutPluginDocument,
  ScreenLayoutMainForm;

function EditScreenLayout(const SerializedData: string;
  const BackgroundPixels: TBytes; BackgroundWidth, BackgroundHeight: Integer;
  CanvasWidth, CanvasHeight: Integer;
  out UpdatedData, ErrorMessage: string): Boolean;
var
  EditorForm: TMainForm;
begin
  Result := False;
  UpdatedData := SerializedData;
  ErrorMessage := '';
  EditorForm := nil;
  try
    try
      EditorForm := TMainForm.Create(nil);
      EditorForm.Caption := '画面レイアウト - 編集';
      EditorForm.Position := poScreenCenter;
      EditorForm.SetFileDropCaptionEnabled(True);
      EditorForm.SetCanvasSettingsVisible(False);
      EditorForm.SetReferenceBackgroundRgba(BackgroundPixels,
        BackgroundWidth, BackgroundHeight);
      if not InitializeScreenLayoutPluginDocument(EditorForm.Document,
        SerializedData, CanvasWidth, CanvasHeight,
        ErrorMessage) then
        Exit;
      EditorForm.ShowModal;
      UpdatedData := SerializeVectArtDocument(EditorForm.Document);
      Result := True;
    except
      on E: Exception do
        ErrorMessage := E.Message;
    end;
  finally
    EditorForm.Free;
  end;
end;

end.
