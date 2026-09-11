program ScreenLayoutStrokeOutlineTest;

{$APPTYPE CONSOLE}

uses
  System.Math,
  System.SysUtils,
  System.Types,
  Vcl.Graphics,
  ScreenLayoutDocument in
    '..\Source\Core\Model\ScreenLayoutDocument.pas',
  ScreenLayoutEditCommands in
    '..\Source\Core\Commands\ScreenLayoutEditCommands.pas',
  ScreenLayoutEditHistory in
    '..\Source\Core\Model\ScreenLayoutEditHistory.pas',
  ScreenLayoutEditorState in
    '..\Source\Core\Model\ScreenLayoutEditorState.pas',
  ScreenLayoutStrokeOutlineCommands in
    '..\Source\Core\Commands\Shape\ScreenLayoutStrokeOutlineCommands.pas',
  ScreenLayoutStrokeOutlineGeometry in
    '..\Source\Core\Geometry\Shape\ScreenLayoutStrokeOutlineGeometry.pas',
  ScreenLayoutShapeBooleanGeometry in
    '..\Source\Core\Geometry\Shape\ScreenLayoutShapeBooleanGeometry.pas',
  ScreenLayoutVariableWidthRenderer in
    '..\Source\Rendering\Paint\ScreenLayoutVariableWidthRenderer.pas',
  ScreenLayoutStrokeSampling in
    '..\Source\Rendering\Paint\Stroke\ScreenLayoutStrokeSampling.pas';

procedure Check(Condition: Boolean; const MessageText: string);
begin
  if not Condition then
    raise Exception.Create(MessageText);
end;

function NewPathData: TVectArtPathData;
begin
  Result := Default(TVectArtPathData);
  SetLength(Result.Vertices, 3);
  Result.Vertices[0].Position := TPointF.Create(0, 0);
  Result.Vertices[0].OutgoingSegment := slskLine;
  Result.Vertices[1].Position := TPointF.Create(50, 0);
  Result.Vertices[1].OutgoingSegment := slskCubicBezier;
  Result.Vertices[1].OutgoingControl := TPointF.Create(15, 0);
  Result.Vertices[2].Position := TPointF.Create(100, 30);
  Result.Vertices[2].IncomingControl := TPointF.Create(-15, 0);
  Result.Name := 'Open path';
  Result.Opacity := 0.75;
  Result.StrokeColor := clRed;
  Result.StrokeWidth := 20;
  Result.MifStrokeStyle := vssSolid;
  Result.LineCap := vlcRound;
  Result.Visible := True;
end;

procedure Run;
var
  Data: TVectArtPathData;
  Contours: TArray<TScreenLayoutContour>;
  CubicCount: Integer;
  Document: TVectArtDocument;
  History: TVectArtEditHistory;
  Original: TVectArtPathLayer;
  Shape: TScreenLayoutShapeLayer;
  State: TVectArtEditorState;
  I: Integer;
  J: Integer;
  VertexCount: Integer;
  MatchesCenterVertex: Boolean;
begin
  Document := TVectArtDocument.Create;
  History := TVectArtEditHistory.Create;
  State := TVectArtEditorState.Create;
  try
    Data := NewPathData;
    Data.WidthPoints := UniformScreenLayoutStrokeWidthPoints;
    Data.WidthPoints[1].LeftScale := 0.25;
    Data.WidthPoints[1].RightScale := 0.5;
    Document.InsertPath(1, Data);
    Document.SelectedIndex := 1;
    Original := TVectArtPathLayer(Document[1]);
    Check(ExecuteScreenLayoutStrokeOutline(Document, State, History,
      Original), 'variable-width outline conversion failed');
    Check(Document[1] is TScreenLayoutShapeLayer,
      'outline result is not a Shape layer');
    Shape := TScreenLayoutShapeLayer(Document[1]);
    Check((Shape.ContourCount > 0) and (Shape.StrokeWidth = 0),
      'outline did not produce a fill-only closed contour');
    Check((ColorToRGB(Shape.FillColor) = ColorToRGB(clRed)) and
      SameValue(Shape.Opacity, 0.75),
      'stroke appearance was not transferred to the fill');
    Contours := Shape.Contours;
    CubicCount := 0;
    for I := 0 to High(Contours) do
      for J := 0 to High(Contours[I].Vertices) do
        if Contours[I].Vertices[J].OutgoingSegment = slskCubicBezier then
          Inc(CubicCount);
    Check(CubicCount >= 4,
      'round caps and joins were not converted to cubic Beziers');
    Check(History.CanUndo, 'conversion did not create Undo history');
    History.Undo;
    Check(Document[1] = Original,
      'Undo did not restore the original open Path');
    History.Redo;
    Check(Document[1] is TScreenLayoutShapeLayer,
      'Redo did not restore the outlined Shape');

    Data := NewPathData;
    Data.Name := 'Uniform round path';
    Data.WidthPoints := nil;
    SetLength(Data.Vertices, 2);
    Data.Vertices[1].Position := TPointF.Create(100, 0);
    Document.InsertPath(2, Data);
    Contours := BuildScreenLayoutStrokeOutlineContours(
      TVectArtPathLayer(Document[2]));
    CubicCount := 0;
    for I := 0 to High(Contours) do
      for J := 0 to High(Contours[I].Vertices) do
        if Contours[I].Vertices[J].OutgoingSegment = slskCubicBezier then
          Inc(CubicCount);
    Check(CubicCount = 4,
      'uniform round caps were not compacted to four cubic Beziers');

    Data.Name := 'Straight variable path';
    Data.WidthPoints := UniformScreenLayoutStrokeWidthPoints;
    Data.WidthPoints[1].LeftScale := 0.25;
    Data.WidthPoints[1].RightScale := 0.5;
    Document.InsertPath(3, Data);
    Contours := BuildScreenLayoutStrokeOutlineContours(
      TVectArtPathLayer(Document[3]));
    VertexCount := 0;
    for I := 0 to High(Contours) do
      Inc(VertexCount, Length(Contours[I].Vertices));
    Check(VertexCount <= 8,
      'straight variable outline retained its dense render samples');

    Data := NewPathData;
    Data.Name := 'Angled variable path';
    Data.Vertices[0].Position := TPointF.Create(0, 80);
    Data.Vertices[1].Position := TPointF.Create(50, 0);
    Data.Vertices[1].OutgoingSegment := slskLine;
    Data.Vertices[1].OutgoingControl := TPointF.Zero;
    Data.Vertices[2].Position := TPointF.Create(120, 80);
    Data.Vertices[2].IncomingControl := TPointF.Zero;
    Data.WidthPoints := UniformScreenLayoutStrokeWidthPoints;
    Document.InsertPath(4, Data);
    Contours := BuildScreenLayoutStrokeOutlineContours(
      TVectArtPathLayer(Document[4]));
    VertexCount := 0;
    for I := 0 to High(Contours) do
      Inc(VertexCount, Length(Contours[I].Vertices));
    Check(VertexCount <= 16, Format(
      'angled variable round outline retained too many points: %d',
      [VertexCount]));

    // 実機ログで再現した、均一幅の連続した鋭角2個を固定する。
    Data := NewPathData;
    Data.Name := 'Logged uniform angled path';
    SetLength(Data.Vertices, 4);
    Data.Vertices[0].Position := TPointF.Create(-699.891174, -177.584335);
    Data.Vertices[0].OutgoingSegment := slskLine;
    Data.Vertices[1].Position := TPointF.Create(-432.470093, -378.150177);
    Data.Vertices[1].OutgoingSegment := slskLine;
    Data.Vertices[2].Position := TPointF.Create(-100.282913, -177.584335);
    Data.Vertices[2].OutgoingSegment := slskLine;
    Data.Vertices[3].Position := TPointF.Create(68.944504, -346.811768);
    Data.StrokeWidth := 68;
    Data.WidthPoints := nil;
    Document.InsertPath(5, Data);
    Contours := BuildScreenLayoutStrokeOutlineContours(
      TVectArtPathLayer(Document[5]));
    MatchesCenterVertex := False;
    CubicCount := 0;
    for I := 0 to High(Contours) do
      for J := 0 to High(Contours[I].Vertices) do
      begin
        if Contours[I].Vertices[J].OutgoingSegment = slskCubicBezier then
          Inc(CubicCount);
        MatchesCenterVertex := MatchesCenterVertex or
          ((SameValue(Contours[I].Vertices[J].Position.X,
            Data.Vertices[1].Position.X, 0.001) and
            SameValue(Contours[I].Vertices[J].Position.Y,
            Data.Vertices[1].Position.Y, 0.001)) or
           (SameValue(Contours[I].Vertices[J].Position.X,
            Data.Vertices[2].Position.X, 0.001) and
            SameValue(Contours[I].Vertices[J].Position.Y,
            Data.Vertices[2].Position.Y, 0.001)));
      end;
    Check(not MatchesCenterVertex,
      'uniform outline inserted a center vertex and recreated an inner gap');
    Check(CubicCount >= 8,
      'round joins were not retained as editable cubic Beziers');

    Data := NewPathData;
    Data.Name := 'Dashed path';
    Data.MifStrokeStyle := vssDotted;
    Document.InsertPath(6, Data);
    Check(Length(BuildScreenLayoutStrokeOutlineContours(
      TVectArtPathLayer(Document[6]))) > 1,
      'dashed outline did not preserve separate dash contours');
    // DEBUGログの最終記録を鋭角の可変幅ケースにする。
    BuildScreenLayoutStrokeOutlineContours(TVectArtPathLayer(Document[5]));
  finally
    State.Free;
    History.Free;
    Document.Free;
  end;
end;

begin
  try
    Run;
    Writeln('ScreenLayoutStrokeOutlineTest PASS');
  except
    on E: Exception do
    begin
      Writeln(E.ClassName + ': ' + E.Message);
      ExitCode := 1;
    end;
  end;
end.
