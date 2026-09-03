program ScreenLayoutTextSpacingCanvasEditTest;

{$APPTYPE CONSOLE}

uses
  System.Classes,
  System.Math,
  System.SysUtils,
  System.Types,
  Vcl.Controls,
  Vcl.Graphics,
  ScreenLayoutCanvasInteraction in
    '..\Source\Editor\Interaction\ScreenLayoutCanvasInteraction.pas',
  ScreenLayoutDocument in '..\Source\Core\Model\ScreenLayoutDocument.pas',
  ScreenLayoutEditHistory in
    '..\Source\Core\Model\ScreenLayoutEditHistory.pas',
  ScreenLayoutTextCommands in
    '..\Source\Core\Commands\ScreenLayoutTextCommands.pas',
  TextRendererSkiaRuntime in
    '..\Lib\TextRenderer\TextRendererSkiaRuntime.pas';

procedure Check(Condition: Boolean; const MessageText: string);
begin
  if not Condition then
    raise Exception.Create(MessageText);
end;

function RectCenter(const Value: TRect): TPoint;
begin
  Result := Point((Value.Left + Value.Right) div 2,
    (Value.Top + Value.Bottom) div 2);
end;

procedure Drag(Interaction: TVectArtCanvasInteraction;
  const StartPoint, EndPoint: TPoint);
begin
  Check(Interaction.MouseDown(mbLeft, [], StartPoint.X, StartPoint.Y),
    'text spacing handle did not start a drag');
  Check(Interaction.MouseMove([ssLeft], EndPoint.X, EndPoint.Y),
    'text spacing drag was not handled');
  Check(Interaction.MouseUp(mbLeft),
    'text spacing drag was not committed');
end;

procedure Run;
var
  Data: TScreenLayoutTextData;
  Document: TVectArtDocument;
  Handles: TScreenLayoutTextSpacingHandles;
  History: TVectArtEditHistory;
  Interaction: TVectArtCanvasInteraction;
  StartPoint: TPoint;
  TextLayer: TScreenLayoutTextLayer;
begin
  Document := TVectArtDocument.Create;
  History := TVectArtEditHistory.Create;
  Interaction := TVectArtCanvasInteraction.Create;
  try
    Document.SetCanvasSize(200, 200);
    Data := Default(TScreenLayoutTextData);
    Data.Bounds := TRectF.Create(-50, -30, 50, 30);
    Data.FontFamily := 'Yu Gothic UI';
    Data.FontSize := 20;
    Data.Locked := False;
    Data.Name := 'Text';
    Data.Opacity := 1.0;
    Data.Text := 'AB' + sLineBreak + 'CD';
    Data.TextColor := clWhite;
    Data.Visible := True;
    Data.WrapWidth := 200;
    Document.InsertText(1, Data);
    Document.SetSelectedLayers([1]);
    Interaction.EditHistory := History;
    Interaction.Configure(Document, Rect(0, 0, 400, 400), 1.0);

    Check(Interaction.SelectedTextSpacingHandles(Handles),
      'text spacing handles were not available');
    Check(Handles.HasLineSpacing,
      'line spacing handle was hidden for multiline text');
    Check((RectCenter(Handles.LetterHandle).X = 229) and
      (RectCenter(Handles.LetterHandle).Y = 262),
      'letter spacing arrow was not placed between bottom handles');
    Check((RectCenter(Handles.LineHandle).X = 282) and
      (RectCenter(Handles.LineHandle).Y = 219),
      'line spacing arrow was not placed between right handles');
    Check((Handles.LetterLineStart.Y = Handles.LetterLineEnd.Y) and
      (Handles.LetterLineStart.X < Handles.LetterLineEnd.X),
      'letter spacing mark is not a horizontal arrow');
    Check((Handles.LineLineStart.X = Handles.LineLineEnd.X) and
      (Handles.LineLineStart.Y < Handles.LineLineEnd.Y),
      'line spacing mark is not a vertical arrow');
    Check(Handles.LetterLineStart.Y > 238,
      'letter spacing arrow overlaps the bottom selection line');
    Check(Handles.LineLineStart.X > 258,
      'line spacing arrow overlaps the right selection line');
    Check(Handles.LetterHandle.Top > 238 + 8,
      'letter spacing hit area is too close to the bottom frame');
    Check(Handles.LineHandle.Left > 258 + 8,
      'line spacing hit area is too close to the right frame');
    StartPoint := RectCenter(Handles.LetterHandle);
    Drag(Interaction, StartPoint, Point(StartPoint.X + 20, StartPoint.Y));
    TextLayer := TScreenLayoutTextLayer(Document[1]);
    Check(SameValue(TextLayer.LetterSpacingRatio, 1.0),
      'letter spacing drag did not use the font-size ratio');
    Check(History.CanUndo, 'letter spacing drag was not added to history');
    History.Undo;
    Check(SameValue(TextLayer.LetterSpacingRatio, 0.0),
      'letter spacing undo failed');
    Check(SameValue(TextLayer.Bounds.Left, Data.Bounds.Left) and
      SameValue(TextLayer.Bounds.Right, Data.Bounds.Right),
      'letter spacing undo did not restore bounds');
    History.Redo;
    Check(SameValue(TextLayer.LetterSpacingRatio, 1.0),
      'letter spacing redo failed');

    Interaction.Configure(Document, Rect(0, 0, 400, 400), 1.0);
    Check(Interaction.SelectedTextSpacingHandles(Handles),
      'text spacing handles disappeared after letter spacing');
    StartPoint := RectCenter(Handles.LineHandle);
    Drag(Interaction, StartPoint, Point(StartPoint.X, StartPoint.Y + 10));
    Check(SameValue(TextLayer.LineSpacingRatio, 0.5),
      'line spacing drag did not use the font-size ratio');
    History.Undo;
    Check(SameValue(TextLayer.LineSpacingRatio, 0.0),
      'line spacing undo failed');

    Interaction.Configure(Document, Rect(0, 0, 400, 400), 1.0);
    Check(Interaction.SelectedTextSpacingHandles(Handles),
      'text spacing handles disappeared before cancel test');
    StartPoint := RectCenter(Handles.LetterHandle);
    Check(Interaction.MouseDown(mbLeft, [], StartPoint.X, StartPoint.Y),
      'letter spacing cancel test did not start');
    Interaction.MouseMove([ssLeft], StartPoint.X + 10, StartPoint.Y);
    Check(Interaction.CancelTextSpacingDrag,
      'letter spacing drag was not canceled');
    Check(SameValue(TextLayer.LetterSpacingRatio, 1.0),
      'cancel did not restore letter spacing');

    Interaction.Configure(Document, Rect(0, 0, 400, 400), 1.0);
    Check(Interaction.SelectedTextSpacingHandles(Handles),
      'text spacing handles disappeared before reset test');
    StartPoint := RectCenter(Handles.LetterHandle);
    Interaction.MouseDown(mbLeft, [ssDouble], StartPoint.X, StartPoint.Y);
    Check(SameValue(TextLayer.LetterSpacingRatio, 0.0),
      'double-click did not reset letter spacing');
    History.Undo;
    Check(SameValue(TextLayer.LetterSpacingRatio, 1.0),
      'double-click reset undo failed');

    Data := CaptureScreenLayoutTextData(TextLayer);
    Data.LetterSpacingRatio := 0;
    Data.LineSpacingRatio := 0;
    Data.Text := 'AB' + sLineBreak + 'CD';
    Document.SetTextData(1, Data);
    Interaction.Configure(Document, Rect(0, 0, 400, 400), 1.0);
    Interaction.SelectedTextSpacingHandles(Handles);
    StartPoint := RectCenter(Handles.LetterHandle);
    Drag(Interaction, StartPoint, Point(StartPoint.X + 1000, StartPoint.Y));
    Check(SameValue(TextLayer.LetterSpacingRatio,
      SCREEN_LAYOUT_TEXT_LETTER_SPACING_MAX),
      'letter spacing drag exceeded its upper limit');
    History.Undo;

    Interaction.Configure(Document, Rect(0, 0, 400, 400), 1.0);
    Interaction.SelectedTextSpacingHandles(Handles);
    StartPoint := RectCenter(Handles.LineHandle);
    Drag(Interaction, StartPoint, Point(StartPoint.X, StartPoint.Y + 1000));
    Check(SameValue(TextLayer.LineSpacingRatio,
      SCREEN_LAYOUT_TEXT_LINE_SPACING_MAX),
      'line spacing drag exceeded its upper limit');
    History.Undo;

    Data := CaptureScreenLayoutTextData(TextLayer);
    Data.Text := 'A';
    Document.SetTextData(1, Data);
    Interaction.Configure(Document, Rect(0, 0, 400, 400), 1.0);
    Check(Interaction.SelectedTextSpacingHandles(Handles),
      'single-line text lost its letter spacing handle');
    Check(not Handles.HasLineSpacing,
      'line spacing handle remained visible for single-line text');
  finally
    Interaction.Free;
    History.Free;
    Document.Free;
  end;
end;

begin
  try
    TTextRendererSkiaRuntime.Acquire(
      ExtractFilePath(ParamStr(0)) + 'sk4d.dll');
    try
      Run;
    finally
      TTextRendererSkiaRuntime.Release;
    end;
    Writeln('PASS');
  except
    on E: Exception do
    begin
      Writeln('FAIL: ' + E.ClassName + ': ' + E.Message);
      Halt(1);
    end;
  end;
end.
