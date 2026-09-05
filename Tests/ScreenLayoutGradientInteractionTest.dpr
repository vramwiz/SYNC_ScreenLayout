program ScreenLayoutGradientInteractionTest;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.Types,
  Winapi.Windows,
  Vcl.Controls,
  Vcl.Graphics,
  ScreenLayoutDocument in '..\Source\Core\Model\ScreenLayoutDocument.pas',
  ScreenLayoutEditorState in
    '..\Source\Core\Model\ScreenLayoutEditorState.pas',
  ScreenLayoutEditHistory in
    '..\Source\Core\Commands\ScreenLayoutEditHistory.pas',
  ScreenLayoutGradientInteraction in
    '..\Source\Editor\Interaction\ScreenLayoutGradientInteraction.pas',
  ScreenLayoutPaintStyles in
    '..\Source\Core\Model\ScreenLayoutPaintStyles.pas';

procedure Check(Condition: Boolean; const MessageText: string);
begin
  if not Condition then
    raise Exception.Create(MessageText);
end;

procedure Run;
var
  Bitmap: TBitmap;
  Data: TVectArtRectangleData;
  Document: TVectArtDocument;
  EndPoint: TPoint;
  Interaction: TScreenLayoutGradientInteraction;
  History: TVectArtEditHistory;
  State: TVectArtEditorState;
  StartPoint: TPoint;
  Style: TScreenLayoutPaintStyle;
  Stops: TArray<TScreenLayoutGradientStop>;
begin
  Document := TVectArtDocument.Create;
  State := TVectArtEditorState.Create;
  Interaction := TScreenLayoutGradientInteraction.Create;
  History := TVectArtEditHistory.Create;
  Bitmap := TBitmap.Create;
  try
    Document.SetCanvasSize(200, 200);
    Data := Default(TVectArtRectangleData);
    Data.Bounds := TRectF.Create(-50, -25, 50, 25);
    Data.FillColor := clRed;
    Data.Name := 'Gradient';
    Data.Opacity := 1.0;
    Data.Visible := True;
    Style := TScreenLayoutPaintStyle.Solid(clRed);
    Style.PrepareLinearGradient(clRed);
    Style.Kind := slpkGradient;
    Style.GradientEndColor := clBlue;
    Data.PaintStyle := Style;
    Document.InsertRectangle(1, Data);
    Document.SetSelectedLayers([1]);
    State.CurrentTool := vetSelect;
    Interaction.Configure(Document, History, State,
      Rect(0, 0, 200, 200), 1.0);

    Check(Interaction.TryGetGuidePoints(StartPoint, EndPoint),
      'selected linear gradient guide was not available');
    Check((StartPoint.X = 50) and (StartPoint.Y = 100) and
      (EndPoint.X = 150) and (EndPoint.Y = 100),
      'default guide did not run left to right through the object center');
    Check(Interaction.HitTest(50, 100) = slgghStartPoint,
      'start handle did not take hit priority');
    Check(Interaction.HitTest(100, 104) = slgghLine,
      'guide line hit tolerance was not applied');
    Check(Interaction.CursorAt(50, 100) = crSizeAll,
      'endpoint hover did not use the move cursor');
    Check(Interaction.CursorAt(100, 100) = crCross,
      'line hover did not use the add-point cursor');

    Check(Interaction.MouseDown(mbLeft, 100, 100),
      'left click on the guide was not consumed');
    Check(Length(Document[1].PaintStyle.GetGradientStops) = 0,
      'line press added a stop before click or drag was determined');
    Check(Interaction.MouseUp(100, 100),
      'left click release on the guide was not consumed');
    Stops := Document[1].PaintStyle.GetGradientStops;
    Check((Length(Stops) = 1) and
      (Abs(Stops[0].Offset - 0.5) < 0.001) and
      (Abs(GetRValue(ColorToRGB(Stops[0].Color)) - 128) <= 1) and
      (Abs(GetBValue(ColorToRGB(Stops[0].Color)) - 128) <= 1),
      'added stop did not retain its offset and interpolated color');
    Check((State.SelectedGradientLayer = Document[1]) and
      (State.SelectedGradientStopId = Stops[0].Id),
      'new middle stop was not selected for color editing');
    Check(Interaction.HitTest(100, 100) = slgghMiddlePoint,
      'middle stop did not take hit priority over the guide');
    History.Undo;
    Check(Length(Document[1].PaintStyle.GetGradientStops) = 0,
      'add-stop undo did not remove the stop');
    History.Redo;
    Check(Length(Document[1].PaintStyle.GetGradientStops) = 1,
      'add-stop redo did not restore the stop');
    Check(Interaction.MouseDown(mbRight, 50, 100) and
      (Length(Document[1].PaintStyle.GetGradientStops) = 1),
      'right click removed or passed through the protected start endpoint');
    Check(Interaction.MouseDown(mbRight, 100, 100) and
      (Length(Document[1].PaintStyle.GetGradientStops) = 0),
      'right click did not remove the middle stop');
    History.Undo;
    Check(Length(Document[1].PaintStyle.GetGradientStops) = 1,
      'remove-stop undo did not restore the stop');

    Check(Interaction.MouseDown(mbLeft, 50, 100),
      'start endpoint drag did not begin');
    Check(State.SelectedGradientStopId =
      SCREEN_LAYOUT_GRADIENT_START_STOP_ID,
      'start endpoint was not selected for color editing');
    Check(Interaction.MouseMove([], 50, 50),
      'start endpoint drag did not update');
    Check(Interaction.MouseUp(50, 50),
      'start endpoint drag did not finish');
    Style := Document[1].PaintStyle;
    Check((Abs(Style.LinearStart.X) < 0.001) and
      (Abs(Style.LinearStart.Y + 0.5) < 0.001),
      'start endpoint did not move outside the object bounds');
    History.Undo;
    Check(Abs(Document[1].PaintStyle.LinearStart.Y - 0.5) < 0.001,
      'endpoint drag undo did not restore the guide');
    History.Redo;
    Check(Abs(Document[1].PaintStyle.LinearStart.Y + 0.5) < 0.001,
      'endpoint drag redo did not restore the moved guide');
    History.Undo;

    Check(Interaction.MouseDown(mbLeft, 100, 100),
      'middle-stop drag did not begin');
    Check(Interaction.MouseMove([], 125, 100),
      'middle-stop drag did not update');
    Check(Interaction.MouseUp(125, 100),
      'middle-stop drag did not finish');
    Stops := Document[1].PaintStyle.GetGradientStops;
    Check((Length(Stops) = 1) and
      (Abs(Stops[0].Offset - 0.75) < 0.001),
      'middle stop did not move along the guide');
    History.Undo;
    Stops := Document[1].PaintStyle.GetGradientStops;
    Check(Abs(Stops[0].Offset - 0.5) < 0.001,
      'middle-stop drag undo did not restore its offset');

    Check(Interaction.MouseDown(mbLeft, 75, 100),
      'guide-line drag did not begin');
    Check(Interaction.MouseMove([], 85, 110),
      'guide-line drag did not update');
    Check(Interaction.MouseUp(85, 110),
      'guide-line drag did not finish');
    Style := Document[1].PaintStyle;
    Check((Abs(Style.LinearStart.X - 0.1) < 0.001) and
      (Abs(Style.LinearStart.Y - 0.7) < 0.001) and
      (Abs(Style.LinearEnd.X - 1.1) < 0.001) and
      (Abs(Style.LinearEnd.Y - 0.7) < 0.001),
      'guide-line drag did not translate both endpoints');
    Check(Length(Style.GetGradientStops) = 1,
      'guide-line drag was mistaken for an add-stop click');
    History.Undo;
    Style := Document[1].PaintStyle;
    Check((Abs(Style.LinearStart.X) < 0.001) and
      (Abs(Style.LinearStart.Y - 0.5) < 0.001) and
      (Abs(Style.LinearEnd.X - 1.0) < 0.001) and
      (Abs(Style.LinearEnd.Y - 0.5) < 0.001),
      'guide-line drag undo did not restore both endpoints');

    TVectArtRectangleLayer(Document[1]).RotationDegrees := 90.0;
    Check(Interaction.TryGetGuidePoints(StartPoint, EndPoint) and
      (Abs(StartPoint.X - 100) <= 1) and
      (Abs(StartPoint.Y - 50) <= 1) and
      (Abs(EndPoint.X - 100) <= 1) and
      (Abs(EndPoint.Y - 150) <= 1),
      'rotated gradient guide did not follow the layer-local direction');
    Interaction.Configure(Document, History, State,
      Rect(0, 0, 400, 400), 2.0);
    Check(Interaction.TryGetGuidePoints(StartPoint, EndPoint) and
      (Abs(StartPoint.X - 200) <= 1) and
      (Abs(StartPoint.Y - 100) <= 1) and
      (Abs(EndPoint.X - 200) <= 1) and
      (Abs(EndPoint.Y - 300) <= 1),
      'zoomed gradient guide did not preserve its document direction');

    Stops := Document[1].PaintStyle.GetGradientStops;
    State.SelectGradientStop(Document[1], Stops[0].Id);
    Style := Document[1].PaintStyle;
    Style.RemoveGradientStop(Stops[0].Id);
    Document[1].PaintStyle := Style;
    State.ValidateSelectedGradientStop(Document);
    Check(State.SelectedGradientStopId =
      SCREEN_LAYOUT_GRADIENT_START_STOP_ID,
      'removed selected stop did not fall back to the start endpoint');
    Document.SetSelectedLayers([]);
    State.ValidateSelectedGradientStop(Document);
    Check(State.SelectedGradientLayer = nil,
      'gradient-stop selection survived object deselection');
    Document.SetSelectedLayers([1]);
    Interaction.Configure(Document, History, State,
      Rect(0, 0, 200, 200), 1.0);

    Bitmap.SetSize(200, 200);
    Interaction.Draw(Bitmap.Canvas);

    State.CurrentTool := vetRectangle;
    Check(not Interaction.TryGetGuidePoints(StartPoint, EndPoint),
      'gradient guide remained active during shape creation');
  finally
    Bitmap.Free;
    History.Free;
    Interaction.Free;
    State.Free;
    Document.Free;
  end;
end;

begin
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
