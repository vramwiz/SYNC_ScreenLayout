program ScreenLayoutTextToolbarTest;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.Types,
  Vcl.Forms,
  Vcl.Graphics,
  ScreenLayoutDocument in '..\Source\Core\Model\ScreenLayoutDocument.pas',
  ScreenLayoutEditorState in
    '..\Source\Core\Model\ScreenLayoutEditorState.pas',
  ScreenLayoutEditHistory in
    '..\Source\Core\Model\ScreenLayoutEditHistory.pas',
  ScreenLayoutDocumentJson in
    '..\Source\Persistence\ScreenLayoutDocumentJson.pas',
  ScreenLayoutLineToolbar in
    '..\Source\Shell\ScreenLayoutLineToolbar.pas';

procedure Check(Condition: Boolean; const MessageText: string);
begin
  if not Condition then
    raise Exception.Create(MessageText);
end;

procedure Run;
var
  Data: TScreenLayoutTextData;
  Document: TVectArtDocument;
  Form: TForm;
  History: TVectArtEditHistory;
  ErrorMessage: string;
  Json: string;
  LegacyJson: string;
  LoadedDocument: TVectArtDocument;
  NewFontFamily: string;
  State: TVectArtEditorState;
  Toolbar: TVectArtLineToolbarControl;
begin
  Form := TForm.Create(nil);
  Document := TVectArtDocument.Create;
  History := TVectArtEditHistory.Create;
  State := TVectArtEditorState.Create;
  try
    Toolbar := TVectArtLineToolbarControl.CreateForHost(Form, Form);
    Toolbar.Document := Document;
    Toolbar.EditHistory := History;
    Toolbar.EditorState := State;
    Check(Toolbar.FontFamilyCombo.Items.Count >= 2,
      'font family list is unexpectedly empty');

    Data := Default(TScreenLayoutTextData);
    Data.Bounds := TRectF.Create(-80, -20, 80, 20);
    Data.FontFamily := Toolbar.FontFamilyCombo.Items[0];
    Data.FontSize := 32;
    Data.Name := 'Text';
    Data.Opacity := 1.0;
    Data.Text := 'Sample';
    Data.TextColor := clWhite;
    Data.Visible := True;
    Data.WrapWidth := 160;
    Document.InsertText(1, Data);
    Document.SetSelectedLayers([1]);
    Toolbar.RefreshState;

    Check(Toolbar.Visible, 'toolbar was hidden for text selection');
    Check(Toolbar.FontFamilyCombo.Visible,
      'font family combo was hidden for text selection');
    Check(not Toolbar.StrokeWidthEdit.Visible,
      'stroke width edit remained visible for text selection');
    Check(Toolbar.FontFamilyCombo.ItemIndex = 0,
      'selected font family was not reflected in the combo');

    NewFontFamily := Toolbar.FontFamilyCombo.Items[1];
    Toolbar.ApplyFontFamily(NewFontFamily);
    Check(TScreenLayoutTextLayer(Document[1]).FontFamily = NewFontFamily,
      'font family was not applied');
    History.Undo;
    Check(TScreenLayoutTextLayer(Document[1]).FontFamily = Data.FontFamily,
      'font family undo failed');
    History.Redo;
    Check(TScreenLayoutTextLayer(Document[1]).FontFamily = NewFontFamily,
      'font family redo failed');

    Toolbar.ApplyFontStyle(fsBold, True);
    Check(fsBold in TScreenLayoutTextLayer(Document[1]).FontStyle,
      'bold style was not applied');
    Check(Toolbar.FontStyleButton(fsBold).Selected,
      'bold button did not reflect the selected style');
    History.Undo;
    Check(not (fsBold in TScreenLayoutTextLayer(Document[1]).FontStyle),
      'bold style undo failed');
    History.Redo;
    Check(fsBold in TScreenLayoutTextLayer(Document[1]).FontStyle,
      'bold style redo failed');

    Toolbar.ApplyTextSpacing(True, 0.25);
    Toolbar.ApplyTextSpacing(False, 0.5);
    Check(TScreenLayoutTextLayer(Document[1]).LetterSpacingRatio = 0.25,
      'letter spacing was not applied');
    Check(TScreenLayoutTextLayer(Document[1]).LineSpacingRatio = 0.5,
      'line spacing was not applied');
    History.Undo;
    Check(TScreenLayoutTextLayer(Document[1]).LineSpacingRatio = 0,
      'line spacing undo failed');
    History.Redo;
    Check(TScreenLayoutTextLayer(Document[1]).LineSpacingRatio = 0.5,
      'line spacing redo failed');

    Json := SerializeVectArtDocument(Document);
    Check(Pos('"bold":true', Json) > 0,
      'bold style was not written to JSON');
    LoadedDocument := TVectArtDocument.Create;
    try
      Check(TryDeserializeVectArtDocument(Json, LoadedDocument,
        ErrorMessage), 'styled text JSON could not be loaded: ' +
        ErrorMessage);
      Check(fsBold in
        TScreenLayoutTextLayer(LoadedDocument[1]).FontStyle,
        'bold style was not restored from JSON');
      Check(TScreenLayoutTextLayer(LoadedDocument[1]).LetterSpacingRatio =
        0.25, 'letter spacing was not restored from JSON');
      Check(TScreenLayoutTextLayer(LoadedDocument[1]).LineSpacingRatio =
        0.5, 'line spacing was not restored from JSON');
    finally
      LoadedDocument.Free;
    end;

    LegacyJson := StringReplace(Json, ',"bold":true', '', []);
    LegacyJson := StringReplace(LegacyJson, ',"italic":false', '', []);
    LegacyJson := StringReplace(LegacyJson, ',"underline":false', '', []);
    LegacyJson := StringReplace(LegacyJson, ',"strikeOut":false', '', []);
    LegacyJson := StringReplace(LegacyJson,
      ',"letterSpacingRatio":0.25', '', []);
    LegacyJson := StringReplace(LegacyJson,
      ',"lineSpacingRatio":0.5', '', []);
    LoadedDocument := TVectArtDocument.Create;
    try
      Check(TryDeserializeVectArtDocument(LegacyJson, LoadedDocument,
        ErrorMessage), 'existing version 15 JSON could not be loaded: ' +
        ErrorMessage);
      Check(TScreenLayoutTextLayer(LoadedDocument[1]).FontStyle = [],
        'missing style fields did not default to off');
      Check(TScreenLayoutTextLayer(LoadedDocument[1]).LetterSpacingRatio = 0,
        'missing letter spacing did not default to zero');
      Check(TScreenLayoutTextLayer(LoadedDocument[1]).LineSpacingRatio = 0,
        'missing line spacing did not default to zero');
    finally
      LoadedDocument.Free;
    end;

    Document.SetLayerLocked(1, True);
    Toolbar.RefreshState;
    Check(not Toolbar.FontFamilyCombo.Enabled,
      'font family combo remained enabled for a locked text layer');
    Check(not Toolbar.FontStyleButton(fsBold).Enabled,
      'font style button remained enabled for a locked text layer');
  finally
    State.Free;
    History.Free;
    Document.Free;
    Form.Free;
  end;
end;

begin
  Application.Initialize;
  try
    Run;
    Writeln('PASS');
  except
    on E: Exception do
    begin
      Writeln('FAIL: ' + E.ClassName + ': ' + E.Message);
      Halt(1);
    end;
  end;
end.
