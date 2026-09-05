program ScreenLayoutTextToolbarTest;

{$APPTYPE CONSOLE}

uses
  System.Math,
  System.SysUtils,
  System.Types,
  Winapi.Messages,
  Winapi.Windows,
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
    Check((Toolbar.StrokeWidthTrackBar.Left = 40) and
      (Toolbar.StrokeWidthTrackBar.Width = 94),
      'stroke width trackbar kept its unpositioned default bounds');
    Check((Toolbar.StrokeWidthEdit.Left = 142) and
      (Toolbar.StrokeWidthEdit.Width = 48),
      'stroke width edit kept its unpositioned default bounds');
    Check((Toolbar.DetailsButton.Left = 200) and
      (Toolbar.DetailsButton.Width = 60),
      'line details button kept its unpositioned default bounds');

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
    Check(Toolbar.TextAlignmentButton.Visible,
      'text alignment popup button was hidden for text selection');
    Check(not Toolbar.TextAlignmentPanel.Visible,
      'text alignment popup was initially visible');

    State.LineStrokeWidth := 7.5;
    State.ActivateTool(vetFreehand);
    Toolbar.RefreshState;
    Check(Toolbar.Visible,
      'toolbar was hidden for freehand while text remained selected');
    Check(Toolbar.StrokeWidthEdit.Visible,
      'freehand stroke width was hidden by selected-object UI');
    Check(not Toolbar.FontFamilyCombo.Visible,
      'selected text UI covered the freehand stroke settings');
    Check(Toolbar.StrokeWidthEdit.Text = '7.5',
      'freehand stroke width did not reflect the drawing default');
    State.ActivateTool(vetSelect);
    Toolbar.RefreshState;

    Check(not Toolbar.TextAlignmentCell(sltaTopLeft).Enabled,
      'top alignment remained enabled in whole-frame fit mode');
    Check(Toolbar.TextAlignmentCell(sltaMiddleLeft).Enabled,
      'horizontal alignment was disabled in whole-frame fit mode');
    Check(not Toolbar.TextAlignmentCell(sltaBottomRight).Enabled,
      'bottom alignment remained enabled in whole-frame fit mode');
    Toolbar.TextAlignmentButton.Click;
    Check(Toolbar.TextAlignmentPanel.Visible,
      'text alignment popup did not open');
    Toolbar.TextAlignmentButton.Click;
    Check(not Toolbar.TextAlignmentPanel.Visible,
      'text alignment popup did not close');

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

    Toolbar.ApplyTextAlignment(sltaMiddleCenter);
    Check(TScreenLayoutTextLayer(Document[1]).Alignment = sltaMiddleCenter,
      'text alignment was not applied');
    Check(Toolbar.TextAlignmentCell(sltaMiddleCenter).Selected,
      'alignment popup did not reflect the selected alignment');
    History.Undo;
    Check(TScreenLayoutTextLayer(Document[1]).Alignment = sltaTopLeft,
      'text alignment undo failed');
    History.Redo;
    Check(TScreenLayoutTextLayer(Document[1]).Alignment = sltaMiddleCenter,
      'text alignment redo failed');

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

    Toolbar.ApplyTextSpacing(True, 20.0);
    Check(TScreenLayoutTextLayer(Document[1]).LetterSpacingRatio =
      SCREEN_LAYOUT_TEXT_LETTER_SPACING_MAX,
      'letter spacing API exceeded its upper limit');
    History.Undo;
    Toolbar.ApplyTextSpacing(False, 20.0);
    Check(TScreenLayoutTextLayer(Document[1]).LineSpacingRatio =
      SCREEN_LAYOUT_TEXT_LINE_SPACING_MAX,
      'line spacing API exceeded its upper limit');
    History.Undo;

    TScreenLayoutTextLayer(Document[1]).TransformMode := slttmFrameFit;
    Json := SerializeVectArtDocument(Document);
    Check(Pos('"bold":true', Json) > 0,
      'bold style was not written to JSON');
    Check(Pos('"alignment":"middleCenter"', Json) > 0,
      'text alignment was not written to JSON');
    Check(Pos('"transformMode":"frameFit"', Json) > 0,
      'text transform mode was not written to JSON');
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
      Check(TScreenLayoutTextLayer(LoadedDocument[1]).Alignment =
        sltaMiddleCenter, 'text alignment was not restored from JSON');
      Check(TScreenLayoutTextLayer(LoadedDocument[1]).TransformMode =
        slttmFrameFit, 'text transform mode was not restored from JSON');
    finally
      LoadedDocument.Free;
    end;

    LegacyJson := StringReplace(Json, ',"bold":true', '', []);
    LegacyJson := StringReplace(LegacyJson,
      ',"alignment":"middleCenter"', '', []);
    LegacyJson := StringReplace(LegacyJson, ',"italic":false', '', []);
    LegacyJson := StringReplace(LegacyJson, ',"underline":false', '', []);
    LegacyJson := StringReplace(LegacyJson, ',"strikeOut":false', '', []);
    LegacyJson := StringReplace(LegacyJson,
      ',"letterSpacingRatio":0.25', '', []);
    LegacyJson := StringReplace(LegacyJson,
      ',"lineSpacingRatio":0.5', '', []);
    LegacyJson := StringReplace(LegacyJson,
      ',"transformMode":"frameFit"', '', []);
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
      Check(TScreenLayoutTextLayer(LoadedDocument[1]).Alignment =
        sltaTopLeft, 'missing alignment did not default to top-left');
      Check(TScreenLayoutTextLayer(LoadedDocument[1]).TransformMode =
        slttmUniformScale,
        'missing transform mode did not default to uniform scale');
    finally
      LoadedDocument.Free;
    end;

    Document.SetLayerLocked(1, True);
    Toolbar.RefreshState;
    Check(not Toolbar.FontFamilyCombo.Enabled,
      'font family combo remained enabled for a locked text layer');
    Check(not Toolbar.FontStyleButton(fsBold).Enabled,
      'font style button remained enabled for a locked text layer');
    Check(not Toolbar.TextAlignmentButton.Enabled,
      'alignment button remained enabled for a locked text layer');
  finally
    State.Free;
    History.Free;
    Document.Free;
    Form.Free;
  end;
end;

procedure CheckTextPathAttachmentToolbar;
var
  Document: TVectArtDocument;
  Form: TForm;
  History: TVectArtEditHistory;
  Layer: TScreenLayoutTextPathLayer;
  State: TVectArtEditorState;
  Toolbar: TVectArtLineToolbarControl;
  Vertices: TArray<TScreenLayoutVertex>;
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
    SetLength(Vertices, 2);
    Vertices[0].Position := TPointF.Create(-50, 0);
    Vertices[0].Kind := slvkSharp;
    Vertices[0].OutgoingSegment := slskLine;
    Vertices[1].Position := TPointF.Create(50, 0);
    Vertices[1].Kind := slvkSharp;
    Vertices[1].OutgoingSegment := slskLine;
    Layer := TScreenLayoutTextPathLayer.Create('Text Path',
      TRectF.Create(-50, -20, 50, 0), 'Text', 'Yu Gothic UI', 20, 0,
      clWhite, Vertices);
    Document.InsertLayer(1, Layer);
    Document.SetSelectedLayers([1]);
    Toolbar.RefreshState;

    Check(not Toolbar.TextAlignmentButton.Visible,
      'normal text alignment remained visible for text path selection');
    Check(Toolbar.TextPathAttachmentButton.Visible,
      'text path attachment button was hidden');
    Check(Toolbar.TextPathAttachmentCell(sltpaBottom).Selected,
      'bottom attachment was not reflected in the popup');
    Toolbar.TextPathAttachmentButton.Click;
    Check(Toolbar.TextPathAttachmentPanel.Visible,
      'text path attachment popup did not open');
    Toolbar.TextPathAttachmentButton.Click;
    Check(not Toolbar.TextPathAttachmentPanel.Visible,
      'text path attachment popup did not close');

    Toolbar.ApplyTextPathAttachment(sltpaLeft);
    Check(Layer.Attachment = sltpaLeft,
      'text path attachment was not applied');
    Check(Toolbar.TextPathAttachmentCell(sltpaLeft).Selected,
      'text path attachment popup did not reflect the selected side');
    History.Undo;
    Check(Layer.Attachment = sltpaBottom,
      'text path attachment undo failed');
    History.Redo;
    Check(Layer.Attachment = sltpaLeft,
      'text path attachment redo failed');

    Document.SetLayerLocked(1, True);
    Toolbar.RefreshState;
    Check(not Toolbar.TextPathAttachmentButton.Enabled,
      'text path attachment remained enabled for a locked layer');
  finally
    State.Free;
    History.Free;
    Document.Free;
    Form.Free;
  end;
end;

procedure CheckLineTrackBarDrag;
var
  Document: TVectArtDocument;
  Form: TForm;
  History: TVectArtEditHistory;
  Layer: TScreenLayoutRectangleLineLayer;
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
    Layer := TScreenLayoutRectangleLineLayer.Create('Line',
      TRectF.Create(-50, -30, 50, 30));
    Document.InsertLayer(1, Layer);
    Document.SetSelectedLayers([1]);
    Toolbar.RefreshState;
    Form.Show;

    Toolbar.StrokeWidthTrackBar.Perform(WM_LBUTTONDOWN, MK_LBUTTON,
      LPARAM(8 or (17 shl 16)));
    Toolbar.StrokeWidthTrackBar.Perform(WM_MOUSEMOVE, MK_LBUTTON,
      LPARAM(47 or (17 shl 16)));
    Check(Toolbar.StrokeWidthEdit.Text = FormatFloat('0.##',
      Toolbar.StrokeWidthTrackBar.Position / 10),
      'stroke width text did not update during trackbar drag');
    Check(SameValue(Layer.StrokeWidth,
      Toolbar.StrokeWidthTrackBar.Position / 10),
      'selected line width did not update during trackbar drag');
    Check(not History.CanUndo,
      'trackbar drag recorded history before mouse up');
    Toolbar.StrokeWidthTrackBar.Perform(WM_LBUTTONUP, 0,
      LPARAM(47 or (17 shl 16)));
    Check(History.CanUndo,
      'trackbar drag did not record one history item on mouse up');
    History.Undo;
    Check(SameValue(Layer.StrokeWidth, 1.0),
      'trackbar drag undo did not restore the original width');
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
    CheckTextPathAttachmentToolbar;
    CheckLineTrackBarDrag;
    Writeln('PASS');
  except
    on E: Exception do
    begin
      Writeln('FAIL: ' + E.ClassName + ': ' + E.Message);
      Halt(1);
    end;
  end;
end.
