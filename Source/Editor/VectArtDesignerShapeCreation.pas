// 図形作成ツールの入力状態、プレビュー、新規レイヤー確定を管理する。
unit VectArtDesignerShapeCreation;

interface

uses
  System.Classes, System.Types, Vcl.Controls, VectArtDesignerDocument,
  VectArtDesignerEditorState, VectArtDesignerEditHistory;

type
  TVectArtShapeCreation = class
  private
    FActive: Boolean;
    FCanvasBounds: TRect;
    FCurrentPoint: TPoint;
    FDocument: TVectArtDocument;
    FEditorState: TVectArtEditorState;
    FEditHistory: TVectArtEditHistory;
    FModifiers: TShiftState;
    FPathPoints: TArray<TPoint>;
    FStartPoint: TPoint;
    FZoom: Single;
    function ClampToCanvas(const Point: TPoint): TPoint;
    procedure CreateLine;
    procedure CreatePath(Closed: Boolean);
    procedure CreateRectangle;
    function NextLineName: string;
    function NextPathName: string;
    function NextRectangleName: string;
  public
    procedure Configure(ADocument: TVectArtDocument;
      AEditHistory: TVectArtEditHistory; AEditorState: TVectArtEditorState;
      const ACanvasBounds: TRect; AZoom: Single);
    function MouseDown(Button: TMouseButton; Shift: TShiftState;
      X, Y: Integer): Boolean;
    function MouseMove(Shift: TShiftState; X, Y: Integer): Boolean;
    function MouseUp(Button: TMouseButton; Shift: TShiftState;
      X, Y: Integer): Boolean;
    procedure CancelPath;
    function FinishPath(Closed: Boolean): Boolean;
    function PreviewPath(out Points: TArray<TPoint>): Boolean;
    function PreviewRect: TRect;
    function PreviewLine(out StartPoint, EndPoint: TPoint): Boolean;
    property Active: Boolean read FActive;
  end;

implementation

uses
  System.Math, System.SysUtils,
  VectArtDesignerGeometry, VectArtDesignerLayerStructureCommands;

const
  MIN_DRAG_SIZE = 3;
  PATH_CLOSE_DISTANCE = 8;

procedure TVectArtShapeCreation.CancelPath;
begin
  FActive := False;
  SetLength(FPathPoints, 0);
end;

procedure TVectArtShapeCreation.CreateLine;
var
  AfterSelection: TArray<Integer>;
  BeforeSelection: TArray<Integer>;
  Data: TVectArtLineData;
  Index: Integer;
begin
  if Hypot(FCurrentPoint.X - FStartPoint.X,
    FCurrentPoint.Y - FStartPoint.Y) < MIN_DRAG_SIZE then
    Exit;
  Data.StartPoint := TPointF.Create(
    ScreenToLogicalX(FStartPoint.X, FCanvasBounds, FZoom,
      FDocument.CanvasLayer.Width),
    ScreenToLogicalY(FStartPoint.Y, FCanvasBounds, FZoom,
      FDocument.CanvasLayer.Height));
  Data.EndPoint := TPointF.Create(
    ScreenToLogicalX(FCurrentPoint.X, FCanvasBounds, FZoom,
      FDocument.CanvasLayer.Width),
    ScreenToLogicalY(FCurrentPoint.Y, FCanvasBounds, FZoom,
      FDocument.CanvasLayer.Height));
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
  Index := FDocument.InsertLine(FDocument.LayerCount, Data);
  FDocument.SetSelectedLayers([Index]);
  AfterSelection := FDocument.GetSelectedLayerIndices;
  if FEditHistory <> nil then
    FEditHistory.AddApplied(TVectArtInsertLineCommand.Create(FDocument,
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
  Data.Filled := Closed;
  Data.FillColor := FEditorState.RectangleFillColor;
  Data.LineCap := FEditorState.PathLineCap;
  Data.LineJoin := FEditorState.PathLineJoin;
  Data.MifAntiAlias := FEditorState.PathMifAntiAlias;
  Data.Locked := False;
  Data.Name := NextPathName;
  Data.Opacity := FEditorState.RectangleOpacity;
  Data.StrokeColor := FEditorState.RectangleStrokeColor;
  Data.MifStrokeStyle := FEditorState.RectangleMifStrokeStyle;
  Data.StrokeWidth := Max(FEditorState.RectangleStrokeWidth, 1.0);
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
    (AEditorState.CurrentTool <> vetPath)) then
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
  Data.StrokeColor := FEditorState.RectangleStrokeColor;
  Data.MifStrokeStyle := FEditorState.RectangleMifStrokeStyle;
  Data.StrokeWidth := FEditorState.RectangleStrokeWidth;
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
    (FEditorState.CurrentTool in [vetRectangle, vetLine, vetPath]) and
    (FZoom > 0) and
    PtInRect(FCanvasBounds, Point(X, Y));
  if not Result then
    Exit;
  PointValue := ClampToCanvas(Point(X, Y));
  if FEditorState.CurrentTool = vetPath then
  begin
    if (ssDouble in Shift) and (Length(FPathPoints) >= 2) then
    begin
      FinishPath(False);
      Exit;
    end;
    if not FActive then
    begin
      FActive := True;
      FPathPoints := [PointValue];
    end
    else if (Length(FPathPoints) >= 3) and
      (Hypot(PointValue.X - FPathPoints[0].X,
        PointValue.Y - FPathPoints[0].Y) <= PATH_CLOSE_DISTANCE) then
      FinishPath(True)
    else
    begin
      SetLength(FPathPoints, Length(FPathPoints) + 1);
      FPathPoints[High(FPathPoints)] := PointValue;
    end;
    FCurrentPoint := PointValue;
    Exit;
  end;
  FActive := True;
  FStartPoint := PointValue;
  FCurrentPoint := FStartPoint;
  FModifiers := Shift;
end;

function TVectArtShapeCreation.MouseMove(Shift: TShiftState;
  X, Y: Integer): Boolean;
begin
  Result := FActive;
  if not FActive then
    Exit;
  if (FEditorState <> nil) and (FEditorState.CurrentTool = vetPath) then
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
    (FEditorState.CurrentTool = vetPath) then
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
    (FEditorState.CurrentTool = vetPath) and (Length(FPathPoints) >= 2);
  if not Result then
    Exit;
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

function TVectArtShapeCreation.PreviewPath(
  out Points: TArray<TPoint>): Boolean;
begin
  Result := FActive and (FEditorState <> nil) and
    (FEditorState.CurrentTool = vetPath) and (Length(FPathPoints) > 0);
  if not Result then
  begin
    Points := nil;
    Exit;
  end;
  Points := Copy(FPathPoints);
  SetLength(Points, Length(Points) + 1);
  Points[High(Points)] := FCurrentPoint;
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
