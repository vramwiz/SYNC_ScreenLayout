// AviUtl2の文字列データと共通デザイナー画面を接続するプラグイン用ホスト。
unit ScreenLayoutEditorHost;

interface

uses
  System.SysUtils;

function EditScreenLayout(const SerializedData: string;
  const BackgroundPixels: TBytes; BackgroundWidth, BackgroundHeight: Integer;
  out UpdatedData, ErrorMessage: string): Boolean;

implementation

uses
  Vcl.Forms, VectArtDesignerDocumentJson,
  VectArtDesignerMainForm;

function EditScreenLayout(const SerializedData: string;
  const BackgroundPixels: TBytes; BackgroundWidth, BackgroundHeight: Integer;
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
      EditorForm.SetFileMenuVisible(False);
      EditorForm.SetReferenceBackgroundRgba(BackgroundPixels,
        BackgroundWidth, BackgroundHeight);
      if (SerializedData <> '') and
        not TryDeserializeVectArtDocument(SerializedData,
          EditorForm.Document, ErrorMessage) then
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
