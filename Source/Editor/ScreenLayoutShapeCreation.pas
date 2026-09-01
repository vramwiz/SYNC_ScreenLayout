// 図形作成ツールの入力状態、プレビュー、新規レイヤー確定を管理する。
unit ScreenLayoutShapeCreation;

interface

uses
  System.Classes, System.Types, Vcl.Controls, ScreenLayoutDocument,
  ScreenLayoutEditorState, ScreenLayoutEditHistory;

type
  TVectArtShapeCreation = class
  private
    FActive: Boolean;
    FCanvasBounds: TRect;
    FCreationTool: TVectArtEditorTool;
    FCurrentPoint: TPoint;
    FDocument: TVectArtDocument;
    FEditorState: TVectArtEditorState;
    FEditHistory: TVectArtEditHistory;
    FModifiers: TShiftState;
    FPathPoints: TArray<TPoint>;
    FShapeVertexKinds: TArray<TScreenLayoutVertexKind>; // 確定済みShape頂点の種別。
    FNextShapeVertexKind: TScreenLayoutVertexKind;      // 次のクリックへ適用する種別。
    FStartPoint: TPoint;
    FZoom: Single;
    function ClampToCanvas(const Point: TPoint): TPoint;
    procedure CreateLine;
    procedure CreatePath(Closed: Boolean);
    procedure CreateRectangle;
    procedure CreateShape;
    function NextLineName: string;
    function NextPathName: string;
    function NextRectangleName: string;
    function NextShapeName: string;
    function BuildShapePreview(out Points: TArray<TPoint>): Boolean;
  public
    // 新規図形入力に必要なDocument、履歴、ツール、表示座標系を設定する。
    procedure Configure(ADocument: TVectArtDocument;
      AEditHistory: TVectArtEditHistory; AEditorState: TVectArtEditorState;
      const ACanvasBounds: TRect; AZoom: Single);
    // 現在の作成ツールに応じて入力開始または頂点追加を行う。
    function MouseDown(Button: TMouseButton; Shift: TShiftState;
      X, Y: Integer): Boolean;
    // 作成中プレビューの終点を更新する。
    function MouseMove(Shift: TShiftState; X, Y: Integer): Boolean;
    // ドラッグ作成中の図形を確定し、DocumentとUndo履歴へ反映する。
    function MouseUp(Button: TMouseButton; Shift: TShiftState;
      X, Y: Integer): Boolean;
    // 確定前のPath／Shape頂点列を破棄する。
    procedure CancelPath;
    // 頂点が足りる場合にPathまたはShapeを確定し、成功時にTrueを返す。
    function FinishPath(Closed: Boolean): Boolean;
    // 作成中のPath／Shapeプレビュー頂点を返す。
    function PreviewPath(out Points: TArray<TPoint>): Boolean;
    // ドラッグ作成中の矩形プレビュー範囲を返す。
    function PreviewRect: TRect;
    // ドラッグ作成中の直線プレビュー端点を返す。
    function PreviewLine(out StartPoint, EndPoint: TPoint): Boolean;
    // V／Bキーを次に確定するShape頂点の種別として受け付ける。
    function KeyDown(Key: Word; Shift: TShiftState): Boolean;
    property Active: Boolean read FActive;
  end;

implementation

uses
  System.Math, System.SysUtils,
  ScreenLayoutGeometry, ScreenLayoutLayerStructureCommands,
  ScreenLayoutShapeOperations;

const
  MIN_DRAG_SIZE = 3;
  PATH_CLOSE_DISTANCE = 8;
  SHAPE_PREVIEW_CURVE_STEPS = 16;

procedure ConfigureShapeContourSegments(var Contour: TScreenLayoutContour);
var
  I: Integer;
  NextIndex: Integer;
begin
  RecalculateScreenLayoutSmoothContour(Contour);
  for I := 0 to High(Contour.Vertices) do
  begin
    NextIndex := (I + 1) mod Length(Contour.Vertices);
    if (Contour.Vertices[I].Kind = slvkBezier) or
      (Contour.Vertices[NextIndex].Kind = slvkBezier) then
      Contour.Vertices[I].OutgoingSegment := slskCubicBezier
    else
      Contour.Vertices[I].OutgoingSegment := slskLine;
  end;
end;

function ShapeCubicPoint(const StartPoint, Control1, Control2,
  EndPoint: TPointF; Parameter: Single): TPointF;
var
  Inverse: Single;
begin
  Inverse := 1 - Parameter;
  Result := TPointF.Create(
    Inverse * Inverse * Inverse * StartPoint.X +
      3 * Inverse * Inverse * Parameter * Control1.X +
      3 * Inverse * Parameter * Parameter * Control2.X +
      Parameter * Parameter * Parameter * EndPoint.X,
    Inverse * Inverse * Inverse * StartPoint.Y +
      3 * Inverse * Inverse * Parameter * Control1.Y +
      3 * Inverse * Parameter * Parameter * Control2.Y +
      Parameter * Parameter * Parameter * EndPoint.Y);
end;

procedure TVectArtShapeCreation.CancelPath;
begin
  FActive := False;
  FCreationTool := vetSelect;
  SetLength(FPathPoints, 0);
  SetLength(FShapeVertexKinds, 0);
  FNextShapeVertexKind := slvkSharp;
end;

procedure TVectArtShapeCreation.CreateShape;
var
  AfterSelection: TArray<Integer>;
  BeforeSelection: TArray<Integer>;
  Data: TScreenLayoutShapeData;
  I: Integer;
  Index: Integer;
begin
  if Length(FPathPoints) < 3 then
    Exit;
  SetLength(Data.Contours, 1);
  SetLength(Data.Contours[0].Vertices, Length(FPathPoints));
  for I := 0 to High(FPathPoints) do
  begin
    Data.Contours[0].Vertices[I].Position := TPointF.Create(
      ScreenToLogicalX(FPathPoints[I].X, FCanvasBounds, FZoom,
        FDocument.CanvasLayer.Width),
      ScreenToLogicalY(FPathPoints[I].Y, FCanvasBounds, FZoom,
        FDocument.CanvasLayer.Height));
    if I <= High(FShapeVertexKinds) then
      Data.Contours[0].Vertices[I].Kind := FShapeVertexKinds[I]
    else
      Data.Contours[0].Vertices[I].Kind := slvkSharp;
  end;
  ConfigureShapeContourSegments(Data.Contours[0]);
  Data.FillColor := FEditorState.RectangleFillColor;
  Data.FillRule := slfrEvenOdd;
  Data.Locked := False;
  Data.MifAntiAlias := FEditorState.PathMifAntiAlias;
  Data.Name := NextShapeName;
  Data.Opacity := FEditorState.RectangleOpacity;
  Data.StrokeColor := FEditorState.LineStrokeColor;
  Data.StrokeJoin := FEditorState.LineJoin;
  Data.StrokeStyle := FEditorState.LineMifStrokeStyle;
  Data.StrokeWidth := FEditorState.LineStrokeWidth;
  Data.Visible := True;
  BeforeSelection := FDocument.GetSelectedLayerIndices;
  Index := FDocument.InsertShape(FDocument.LayerCount, Data);
  FDocument.SetSelectedLayers([Index]);
  AfterSelection := FDocument.GetSelectedLayerIndices;
  if FEditHistory <> nil then
    FEditHistory.AddApplied(TScreenLayoutInsertShapeCommand.Create(FDocument,
      Index, Data, BeforeSelection, AfterSelection));
end;

procedure TVectArtShapeCreation.CreateLine;
var
  AfterSelection: TArray<Integer>;
  BeforeSelection: TArray<Integer>;
  Data: TVectArtPathData;
  Index: Integer;
begin
  if Hypot(FCurrentPoint.X - FStartPoint.X,
    FCurrentPoint.Y - FStartPoint.Y) < MIN_DRAG_SIZE then
    Exit;
  SetLength(Data.Points, 2);
  Data.Points[0] := TPointF.Create(
    ScreenToLogicalX(FStartPoint.X, FCanvasBounds, FZoom,
      FDocument.CanvasLayer.Width),
    ScreenToLogicalY(FStartPoint.Y, FCanvasBounds, FZoom,
      FDocument.CanvasLayer.Height));
  Data.Points[1] := TPointF.Create(
    ScreenToLogicalX(FCurrentPoint.X, FCanvasBounds, FZoom,
      FDocument.CanvasLayer.Width),
    ScreenToLogicalY(FCurrentPoint.Y, FCanvasBounds, FZoom,
      FDocument.CanvasLayer.Height));
  Data.Closed := False;
  Data.FillColor := FEditorState.RectangleFillColor;
  Data.Locked := False;
  Data.LineCap := FEditorState.LineCap;
  Data.LineJoin := FEditorState.LineJoin;
  Data.Name := NextLineName;
  Data.Opacity := FEditorState.RectangleOpacity;
  Data.StrokeColor := FEditorState.LineStrokeColor;
  Data.MifStrokeStyle := FEditorState.LineMifStrokeStyle;
  Data.StrokeWidth := FEditorState.LineStrokeWidth;
  Data.Visible := True;
  BeforeSelection := FDocument.GetSelectedLayerIndices;
  Index := FDocument.InsertPath(FDocument.LayerCount, Data);
  FDocument.SetSelectedLayers([Index]);
  AfterSelection := FDocument.GetSelectedLayerIndices;
  if FEditHistory <> nil then
    FEditHistory.AddApplied(TVectArtInsertPathCommand.Create(FDocument,
      Index, Data, BeforeSelection, AfterSelection));
end;

procedure TVectArtShapeCreation.CreatePath(Closed: Boolean);
var
  AfterSelection: TArray<Integer>;
  BeforeSelection: TArray<Integer>;
  Data: TVectArtPathData;
  I: Integer;
  Index: Integer;
begin
  if Length(FPathPoints) < 2 then
    Exit;
  if Closed and (Length(FPathPoints) < 3) then
    Closed := False;
  SetLength(Data.Points, Length(FPathPoints));
  for I := 0 to High(FPathPoints) do
    Data.Points[I] := TPointF.Create(
      ScreenToLogicalX(FPathPoints[I].X, FCanvasBounds, FZoom,
        FDocument.CanvasLayer.Width),
      ScreenToLogicalY(FPathPoints[I].Y, FCanvasBounds, FZoom,
        FDocument.CanvasLayer.Height));
  Data.Closed := Closed;
  Data.FillColor := FEditorState.RectangleFillColor;
  Data.LineCap := FEditorState.LineCap;
  Data.LineJoin := FEditorState.LineJoin;
  Data.MifAntiAlias := FEditorState.PathMifAntiAlias;
  Data.Locked := False;
  Data.Name := NextPathName;
  Data.Opacity := FEditorState.RectangleOpacity;
  Data.StrokeColor := FEditorState.LineStrokeColor;
  Data.MifStrokeStyle := FEditorState.LineMifStrokeStyle;
  Data.StrokeWidth := FEditorState.LineStrokeWidth;
  Data.Visible := True;
  BeforeSelection := FDocument.GetSelectedLayerIndices;
  Index := FDocument.InsertPath(FDocument.LayerCount, Data);
  FDocument.SetSelectedLayers([Index]);
  AfterSelection := FDocument.GetSelectedLayerIndices;
  if FEditHistory <> nil then
    FEditHistory.AddApplied(TVectArtInsertPathCommand.Create(FDocument,
      Index, Data, BeforeSelection, AfterSelection));
end;

function TVectArtShapeCreation.ClampToCanvas(const Point: TPoint): TPoint;
begin
  Result.X := EnsureRange(Point.X, FCanvasBounds.Left,
    FCanvasBounds.Right);
  Result.Y := EnsureRange(Point.Y, FCanvasBounds.Top,
    FCanvasBounds.Bottom);
end;

procedure TVectArtShapeCreation.Configure(ADocument: TVectArtDocument;
  AEditHistory: TVectArtEditHistory; AEditorState: TVectArtEditorState;
  const ACanvasBounds: TRect; AZoom: Single);
begin
  if (Length(FPathPoints) > 0) and ((AEditorState = nil) or
    (AEditorState.CurrentTool <> FCreationTool)) then
    CancelPath;
  FDocument := ADocument;
  FEditHistory := AEditHistory;
  FEditorState := AEditorState;
  FCanvasBounds := ACanvasBounds;
  FZoom := AZoom;
end;

procedure TVectArtShapeCreation.CreateRectangle;
var
  AfterSelection: TArray<Integer>;
  BeforeSelection: TArray<Integer>;
  Data: TVectArtRectangleData;
  Index: Integer;
  LogicalBottom: Single;
  LogicalLeft: Single;
  LogicalRight: Single;
  LogicalTop: Single;
  ScreenBounds: TRect;
begin
  ScreenBounds := PreviewRect;
  if (ScreenBounds.Width < MIN_DRAG_SIZE) or
    (ScreenBounds.Height < MIN_DRAG_SIZE) then
    Exit;
  LogicalLeft := ScreenToLogicalX(ScreenBounds.Left, FCanvasBounds, FZoom,
    FDocument.CanvasLayer.Width);
  LogicalTop := ScreenToLogicalY(ScreenBounds.Top, FCanvasBounds, FZoom,
    FDocument.CanvasLayer.Height);
  LogicalRight := ScreenToLogicalX(ScreenBounds.Right, FCanvasBounds, FZoom,
    FDocument.CanvasLayer.Width);
  LogicalBottom := ScreenToLogicalY(ScreenBounds.Bottom, FCanvasBounds, FZoom,
    FDocument.CanvasLayer.Height);
  Data.Bounds := TRectF.Create(LogicalLeft, LogicalTop, LogicalRight,
    LogicalBottom);
  Data.FillColor := FEditorState.RectangleFillColor;
  Data.Locked := False;
  Data.Name := NextRectangleName;
  Data.Opacity := FEditorState.RectangleOpacity;
  Data.RotationDegrees := 0.0;
  Data.Visible := True;
  BeforeSelection := FDocument.GetSelectedLayerIndices;
  Index := FDocument.InsertRectangle(FDocument.LayerCount, Data);
  FDocument.SetSelectedLayers([Index]);
  AfterSelection := FDocument.GetSelectedLayerIndices;
  if FEditHistory <> nil then
    FEditHistory.AddApplied(TVectArtInsertRectangleCommand.Create(FDocument,
      Index, Data, BeforeSelection, AfterSelection));
end;

function TVectArtShapeCreation.MouseDown(Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer): Boolean;
var
  PointValue: TPoint;
begin
  Result := (Button = mbLeft) and (FDocument <> nil) and
    (FEditorState <> nil) and
    (FEditorState.CurrentTool in [vetRectangle, vetLine, vetPath,
      vetShape]) and
    (FZoom > 0) and
    PtInRect(FCanvasBounds, Point(X, Y));
  if not Result then
    Exit;
  PointValue := ClampToCanvas(Point(X, Y));
  if FEditorState.CurrentTool in [vetPath, vetShape] then
  begin
    if (ssDouble in Shift) and
      (((FEditorState.CurrentTool = vetShape) and
        (Length(FPathPoints) >= 3)) or
       ((FEditorState.CurrentTool = vetPath) and
        (Length(FPathPoints) >= 2))) then
    begin
      FinishPath(FEditorState.CurrentTool = vetShape);
      Exit;
    end;
    if not FActive then
    begin
      FActive := True;
      FCreationTool := FEditorState.CurrentTool;
      FPathPoints := [PointValue];
      if FCreationTool = vetShape then
        FShapeVertexKinds := [FNextShapeVertexKind]
      else
        SetLength(FShapeVertexKinds, 0);
    end
    else if (Length(FPathPoints) >= 3) and
      (Hypot(PointValue.X - FPathPoints[0].X,
        PointValue.Y - FPathPoints[0].Y) <= PATH_CLOSE_DISTANCE) then
      FinishPath(True)
    else
    begin
      SetLength(FPathPoints, Length(FPathPoints) + 1);
      FPathPoints[High(FPathPoints)] := PointValue;
      if FCreationTool = vetShape then
      begin
        SetLength(FShapeVertexKinds, Length(FPathPoints));
        FShapeVertexKinds[High(FShapeVertexKinds)] := FNextShapeVertexKind;
      end;
    end;
    FCurrentPoint := PointValue;
    Exit;
  end;
  FActive := True;
  FStartPoint := PointValue;
  FCurrentPoint := FStartPoint;
  FModifiers := Shift;
end;

function TVectArtShapeCreation.KeyDown(Key: Word;
  Shift: TShiftState): Boolean;
begin
  Result := False;
  if (FEditorState = nil) or (FEditorState.CurrentTool <> vetShape) or
    ((Shift * [ssCtrl, ssAlt]) <> []) then
    Exit;
  if Key = Ord('V') then
    FNextShapeVertexKind := slvkSharp
  else if Key = Ord('B') then
    FNextShapeVertexKind := slvkBezier
  else
    Exit;
  Result := True;
end;

function TVectArtShapeCreation.MouseMove(Shift: TShiftState;
  X, Y: Integer): Boolean;
begin
  Result := FActive;
  if not FActive then
    Exit;
  if (FEditorState <> nil) and
    (FEditorState.CurrentTool in [vetPath, vetShape]) then
  begin
    FCurrentPoint := ClampToCanvas(Point(X, Y));
    Exit;
  end;
  if not (ssLeft in Shift) then
  begin
    FActive := False;
    Exit;
  end;
  FCurrentPoint := ClampToCanvas(Point(X, Y));
  FModifiers := Shift;
end;

function TVectArtShapeCreation.MouseUp(Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer): Boolean;
begin
  if FActive and (FEditorState <> nil) and
    (FEditorState.CurrentTool in [vetPath, vetShape]) then
    Exit(False);
  Result := (Button = mbLeft) and FActive;
  if not Result then
    Exit;
  FCurrentPoint := ClampToCanvas(Point(X, Y));
  FModifiers := Shift;
  if FEditorState.CurrentTool = vetLine then
    CreateLine
  else
    CreateRectangle;
  FActive := False;
end;

function TVectArtShapeCreation.FinishPath(Closed: Boolean): Boolean;
begin
  Result := FActive and (FEditorState <> nil) and
    (FEditorState.CurrentTool in [vetPath, vetShape]) and
    (Length(FPathPoints) >= 2);
  if not Result then
    Exit;
  if FEditorState.CurrentTool = vetShape then
  begin
    if Length(FPathPoints) < 3 then
      Exit(False);
    CreateShape;
  end
  else
    CreatePath(Closed);
  CancelPath;
end;

function TVectArtShapeCreation.NextLineName: string;
var
  Candidate: string;
  Found: Boolean;
  I: Integer;
  Number: Integer;
begin
  Number := 1;
  repeat
    Candidate := 'Line ' + Number.ToString;
    Found := False;
    for I := 1 to FDocument.LayerCount - 1 do
      if SameText(FDocument[I].Name, Candidate) then
      begin
        Found := True;
        Break;
      end;
    Inc(Number);
  until not Found;
  Result := Candidate;
end;

function TVectArtShapeCreation.NextPathName: string;
var
  Candidate: string;
  Found: Boolean;
  I: Integer;
  Number: Integer;
begin
  Number := 1;
  repeat
    Candidate := 'Path ' + Number.ToString;
    Found := False;
    for I := 1 to FDocument.LayerCount - 1 do
      if SameText(FDocument[I].Name, Candidate) then
      begin
        Found := True;
        Break;
      end;
    Inc(Number);
  until not Found;
  Result := Candidate;
end;

function TVectArtShapeCreation.NextShapeName: string;
var
  Candidate: string;
  Found: Boolean;
  I: Integer;
  Number: Integer;
begin
  Number := 1;
  repeat
    Candidate := 'Shape ' + Number.ToString;
    Found := False;
    for I := 1 to FDocument.LayerCount - 1 do
      if SameText(FDocument[I].Name, Candidate) then
      begin
        Found := True;
        Break;
      end;
    Inc(Number);
  until not Found;
  Result := Candidate;
end;

function TVectArtShapeCreation.PreviewPath(
  out Points: TArray<TPoint>): Boolean;
begin
  Result := FActive and (FEditorState <> nil) and
    (FEditorState.CurrentTool in [vetPath, vetShape]) and
    (Length(FPathPoints) > 0);
  if not Result then
  begin
    Points := nil;
    Exit;
  end;
  if FEditorState.CurrentTool = vetShape then
    Exit(BuildShapePreview(Points));
  Points := Copy(FPathPoints);
  SetLength(Points, Length(Points) + 1);
  Points[High(Points)] := FCurrentPoint;
end;

function TVectArtShapeCreation.BuildShapePreview(
  out Points: TArray<TPoint>): Boolean;
var
  Control1: TPointF;
  Control2: TPointF;
  Contour: TScreenLayoutContour;
  EndPoint: TPointF;
  I: Integer;
  NextIndex: Integer;
  OutputIndex: Integer;
  Parameter: Single;
  PreviewPoint: TPointF;
  StartPoint: TPointF;
  Step: Integer;
begin
  Result := FActive and (Length(FPathPoints) > 0);
  if not Result then
  begin
    Points := nil;
    Exit;
  end;
  SetLength(Contour.Vertices, Length(FPathPoints) + 1);
  for I := 0 to High(FPathPoints) do
  begin
    Contour.Vertices[I].Position := TPointF.Create(FPathPoints[I].X,
      FPathPoints[I].Y);
    if I <= High(FShapeVertexKinds) then
      Contour.Vertices[I].Kind := FShapeVertexKinds[I]
    else
      Contour.Vertices[I].Kind := slvkSharp;
  end;
  Contour.Vertices[High(Contour.Vertices)].Position :=
    TPointF.Create(FCurrentPoint.X, FCurrentPoint.Y);
  Contour.Vertices[High(Contour.Vertices)].Kind := FNextShapeVertexKind;
  ConfigureShapeContourSegments(Contour);
  SetLength(Points, 1 + High(Contour.Vertices) *
    SHAPE_PREVIEW_CURVE_STEPS);
  OutputIndex := 0;
  Points[OutputIndex] := Point(Round(Contour.Vertices[0].Position.X),
    Round(Contour.Vertices[0].Position.Y));
  for I := 0 to High(Contour.Vertices) - 1 do
  begin
    NextIndex := I + 1;
    StartPoint := Contour.Vertices[I].Position;
    EndPoint := Contour.Vertices[NextIndex].Position;
    if Contour.Vertices[I].OutgoingSegment = slskLine then
    begin
      Inc(OutputIndex);
      Points[OutputIndex] := Point(Round(EndPoint.X), Round(EndPoint.Y));
      Continue;
    end;
    Control1 := TPointF.Create(StartPoint.X +
      Contour.Vertices[I].OutgoingControl.X, StartPoint.Y +
      Contour.Vertices[I].OutgoingControl.Y);
    Control2 := TPointF.Create(EndPoint.X +
      Contour.Vertices[NextIndex].IncomingControl.X, EndPoint.Y +
      Contour.Vertices[NextIndex].IncomingControl.Y);
    for Step := 1 to SHAPE_PREVIEW_CURVE_STEPS do
    begin
      Parameter := Step / SHAPE_PREVIEW_CURVE_STEPS;
      PreviewPoint := ShapeCubicPoint(StartPoint, Control1, Control2,
        EndPoint, Parameter);
      Inc(OutputIndex);
      Points[OutputIndex] := Point(Round(PreviewPoint.X),
        Round(PreviewPoint.Y));
    end;
  end;
  SetLength(Points, OutputIndex + 1);
end;

function TVectArtShapeCreation.PreviewLine(out StartPoint,
  EndPoint: TPoint): Boolean;
begin
  Result := FActive and (FEditorState <> nil) and
    (FEditorState.CurrentTool = vetLine);
  if not Result then
    Exit;
  StartPoint := FStartPoint;
  EndPoint := FCurrentPoint;
end;

function TVectArtShapeCreation.NextRectangleName: string;
var
  Candidate: string;
  Found: Boolean;
  I: Integer;
  Number: Integer;
begin
  Number := 1;
  repeat
    Candidate := 'Rectangle ' + Number.ToString;
    Found := False;
    for I := 1 to FDocument.LayerCount - 1 do
      if SameText(FDocument[I].Name, Candidate) then
      begin
        Found := True;
        Break;
      end;
    Inc(Number);
  until not Found;
  Result := Candidate;
end;

function TVectArtShapeCreation.PreviewRect: TRect;
var
  DeltaX: Integer;
  DeltaY: Integer;
  HalfHeight: Integer;
  HalfWidth: Integer;
  MaxHalfHeight: Integer;
  MaxHalfWidth: Integer;
  Size: Integer;
  TargetX: Integer;
  TargetY: Integer;
begin
  if not FActive or (FEditorState = nil) or
    (FEditorState.CurrentTool <> vetRectangle) then
    Exit(TRect.Empty);
  DeltaX := FCurrentPoint.X - FStartPoint.X;
  DeltaY := FCurrentPoint.Y - FStartPoint.Y;
  if ssAlt in FModifiers then
  begin
    MaxHalfWidth := Min(FStartPoint.X - FCanvasBounds.Left,
      FCanvasBounds.Right - FStartPoint.X);
    MaxHalfHeight := Min(FStartPoint.Y - FCanvasBounds.Top,
      FCanvasBounds.Bottom - FStartPoint.Y);
    HalfWidth := Min(Abs(DeltaX), MaxHalfWidth);
    HalfHeight := Min(Abs(DeltaY), MaxHalfHeight);
    if ssShift in FModifiers then
    begin
      Size := Min(Max(HalfWidth, HalfHeight),
        Min(MaxHalfWidth, MaxHalfHeight));
      HalfWidth := Size;
      HalfHeight := Size;
    end;
    Exit(Rect(FStartPoint.X - HalfWidth, FStartPoint.Y - HalfHeight,
      FStartPoint.X + HalfWidth, FStartPoint.Y + HalfHeight));
  end;
  TargetX := FCurrentPoint.X;
  TargetY := FCurrentPoint.Y;
  if ssShift in FModifiers then
  begin
    Size := Max(Abs(DeltaX), Abs(DeltaY));
    if DeltaX < 0 then
      Size := Min(Size, FStartPoint.X - FCanvasBounds.Left)
    else
      Size := Min(Size, FCanvasBounds.Right - FStartPoint.X);
    if DeltaY < 0 then
      Size := Min(Size, FStartPoint.Y - FCanvasBounds.Top)
    else
      Size := Min(Size, FCanvasBounds.Bottom - FStartPoint.Y);
    if DeltaX < 0 then
      TargetX := FStartPoint.X - Size
    else
      TargetX := FStartPoint.X + Size;
    if DeltaY < 0 then
      TargetY := FStartPoint.Y - Size
    else
      TargetY := FStartPoint.Y + Size;
  end;
  Result := Rect(Min(FStartPoint.X, TargetX),
    Min(FStartPoint.Y, TargetY), Max(FStartPoint.X, TargetX),
    Max(FStartPoint.Y, TargetY));
end;

end.
