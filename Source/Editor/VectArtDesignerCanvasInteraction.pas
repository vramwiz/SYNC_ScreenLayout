// 編集キャンバス上の選択、移動、リサイズ、中心回り回転を管理する。
unit VectArtDesignerCanvasInteraction;

interface

uses
  System.Classes, System.Generics.Collections, System.Types, Vcl.Controls,
  VectArtDesignerDocument, VectArtDesignerEditHistory,
  VectArtDesignerEditCommands,
  VectArtDesignerSelectionGeometry;

type
  TVectArtCanvasDragMode = (vcdmNone, vcdmMove, vcdmResize, vcdmRotate,
    vcdmRangeSelect, vcdmPathVertex);

  TVectArtCanvasInteraction = class
  private
    FCanvasBounds: TRect;
    FDocument: TVectArtDocument;
    FEditHistory: TVectArtEditHistory;
    FDragHandle: TVectArtSelectionHandle;
    FDragLayerIndex: Integer;
    FDragIsLine: Boolean;
    FDragIsImage: Boolean;
    FDragIsPath: Boolean;
    FDragMode: TVectArtCanvasDragMode;
    FMoveLayerIndices: TArray<Integer>;
    FMoveStartBounds: TArray<TRectF>;
    FMoveImageLayerIndices: TArray<Integer>;
    FMoveStartImagePoints: TArray<TVectArtImagePoints>;
    FDragStartBounds: TRectF;
    FDragStartLineEnd: TPointF;
    FDragStartLineStart: TPointF;
    FDragStartImagePoints: TVectArtImagePoints;
    FDragStartPathPoints: TArray<TPointF>;
    FPathVertexIndex: Integer;
    FDragStartMouse: TPoint;
    FAxisAlignedSelection: Boolean;
    FMoveOccurred: Boolean;
    FRotationStartMouseAngle: Single;
    FRotationStartValue: Single;
    FRangeCurrent: TPoint;
    FRangeStart: TPoint;
    FSelectionModeLayerIndex: Integer;
    FToggleSelectionModeOnClick: Boolean;
    FZoom: Single;
    procedure EndDrag;
    procedure ApplyRangeSelection;
    procedure ApplyResizeSelection(X, Y: Integer);
    procedure ApplyImageResize(X, Y: Integer);
    procedure CaptureMoveSelection;
    procedure CommitBoundsCommand;
    procedure CommitRotationCommand;
    procedure CommitLinePointsCommand;
    procedure CommitImagePointsCommand;
    procedure CommitPathPointsCommand;
    function AxisAlignedResizedBounds(X, Y: Integer;
      RotationDegrees: Single): TRectF;
    function GetDragging: Boolean;
    function GetRangeSelecting: Boolean;
    function GetRangeSelectionRect: TRect;
    function HitTestLayer(X, Y: Integer): Integer;
    function HitTestPathVertex(X, Y: Integer): Integer;
    function LayerScreenRect(Index: Integer): TRect;
    function ResizedBounds(X, Y: Integer): TRectF;
    function SelectionContainsLockedLayer: Boolean;
    function SelectedLayersFrameOffset: Integer;
    function SelectedLayerSelectionGeometry(
      out Geometry: TVectArtSelectionGeometry): Boolean;
    function SelectedLayersLogicalRect: TRectF;
    function SelectedLayersScreenRect: TRect;
    function ToLogicalX(Value: Single): Single;
    function ToLogicalY(Value: Single): Single;
    function ToScreenX(Value: Single): Integer;
    function ToScreenY(Value: Single): Integer;
  public
    constructor Create;
    procedure Configure(ADocument: TVectArtDocument;
      const ACanvasBounds: TRect; AZoom: Single);
    function CursorAt(X, Y: Integer): TCursor;
    function MouseDown(Button: TMouseButton; X, Y: Integer): Boolean;
      overload;
    function MouseDown(Button: TMouseButton; Shift: TShiftState;
      X, Y: Integer): Boolean; overload;
    function MouseMove(Shift: TShiftState; X, Y: Integer): Boolean;
    function MouseUp(Button: TMouseButton): Boolean;
    function SelectedPathVertexRects: TArray<TRect>;
    property Dragging: Boolean read GetDragging;
    property AxisAlignedSelection: Boolean read FAxisAlignedSelection;
    property EditHistory: TVectArtEditHistory read FEditHistory
      write FEditHistory;
    property RangeSelecting: Boolean read GetRangeSelecting;
    property RangeSelectionRect: TRect read GetRangeSelectionRect;
  end;

implementation

uses
  System.Math, VectArtDesignerGeometry;

const
  MIN_RECTANGLE_SIZE = 16.0;
  MOVE_DRAG_THRESHOLD = 6;
  PATH_VERTEX_HANDLE_SIZE = 9;

function ImagePointsBounds(const Points: TVectArtImagePoints): TRectF;
var
  I: Integer;
begin
  Result := TRectF.Create(Points[0], Points[0]);
  for I := 1 to High(Points) do
  begin
    Result.Left := Min(Result.Left, Points[I].X);
    Result.Top := Min(Result.Top, Points[I].Y);
    Result.Right := Max(Result.Right, Points[I].X);
    Result.Bottom := Max(Result.Bottom, Points[I].Y);
  end;
end;

function ClampImageDimension(Value, OriginalValue: Single): Single;
begin
  if Abs(Value) >= MIN_RECTANGLE_SIZE then
    Exit(Value);
  if not SameValue(Value, 0.0) then
    Result := Sign(Value) * MIN_RECTANGLE_SIZE
  else if OriginalValue < 0 then
    Result := -MIN_RECTANGLE_SIZE
  else
    Result := MIN_RECTANGLE_SIZE;
end;

function DistanceToSegment(const PointValue, StartPoint,
  EndPoint: TPointF): Single;
var
  DX: Single;
  DY: Single;
  Projection: Single;
  SegmentLengthSquared: Single;
begin
  DX := EndPoint.X - StartPoint.X;
  DY := EndPoint.Y - StartPoint.Y;
  SegmentLengthSquared := DX * DX + DY * DY;
  if SegmentLengthSquared > 0 then
    Projection := EnsureRange(((PointValue.X - StartPoint.X) * DX +
      (PointValue.Y - StartPoint.Y) * DY) / SegmentLengthSquared, 0.0, 1.0)
  else
    Projection := 0;
  Result := Hypot(PointValue.X - (StartPoint.X + Projection * DX),
    PointValue.Y - (StartPoint.Y + Projection * DY));
end;

constructor TVectArtCanvasInteraction.Create;
begin
  inherited Create;
  FDragLayerIndex := -1;
  FPathVertexIndex := -1;
  FSelectionModeLayerIndex := -1;
end;

procedure TVectArtCanvasInteraction.Configure(ADocument: TVectArtDocument;
  const ACanvasBounds: TRect; AZoom: Single);
var
  SelectedLayerIndex: Integer;
begin
  SelectedLayerIndex := -1;
  if (ADocument <> nil) and (ADocument.SelectionCount = 1) then
    SelectedLayerIndex := ADocument.SelectedIndex;
  if (ADocument <> FDocument) or
    (SelectedLayerIndex <> FSelectionModeLayerIndex) then
  begin
    FAxisAlignedSelection := False;
    FSelectionModeLayerIndex := SelectedLayerIndex;
  end;
  FDocument := ADocument;
  FCanvasBounds := ACanvasBounds;
  FZoom := AZoom;
end;

function TVectArtCanvasInteraction.ToLogicalX(Value: Single): Single;
begin
  Result := ScreenToLogicalX(Value, FCanvasBounds, FZoom,
    FDocument.CanvasLayer.Width);
end;

function TVectArtCanvasInteraction.ToLogicalY(Value: Single): Single;
begin
  Result := ScreenToLogicalY(Value, FCanvasBounds, FZoom,
    FDocument.CanvasLayer.Height);
end;

function TVectArtCanvasInteraction.ToScreenX(Value: Single): Integer;
begin
  Result := LogicalToScreenX(Value, FCanvasBounds, FZoom,
    FDocument.CanvasLayer.Width);
end;

function TVectArtCanvasInteraction.ToScreenY(Value: Single): Integer;
begin
  Result := LogicalToScreenY(Value, FCanvasBounds, FZoom,
    FDocument.CanvasLayer.Height);
end;

function TVectArtCanvasInteraction.CursorAt(X, Y: Integer): TCursor;
var
  Geometry: TVectArtSelectionGeometry;
  Handle: TVectArtSelectionHandle;
  LayerIndex: Integer;
  SelectionRect: TRect;
begin
  Result := crDefault;
  if FDragMode = vcdmMove then
    Exit(crSizeAll);
  if FDragMode = vcdmResize then
    Exit(SelectionHandleCursor(FDragHandle));
  if FDragMode = vcdmRotate then
    Exit(RotationHandleCursor);
  if FDragMode = vcdmRangeSelect then
    Exit(crCross);
  if FDragMode = vcdmPathVertex then
    Exit(crSizeAll);
  if FDocument = nil then
    Exit;
  if HitTestPathVertex(X, Y) >= 0 then
    Exit(crSizeAll);
  SelectionRect := SelectedLayersScreenRect;
  if not SelectionRect.IsEmpty and not SelectionContainsLockedLayer then
  begin
    if not SelectedLayerSelectionGeometry(Geometry) then
      Geometry := BuildSelectionGeometry(SelectionRect,
        SelectedLayersFrameOffset);
    if not FAxisAlignedSelection and (FDocument.SelectionCount = 1) and
      ((FDocument[FDocument.SelectedIndex] is TVectArtRectangleLayer) or
       (FDocument[FDocument.SelectedIndex] is TVectArtImageLayer)) and
      HitTestRotationHandle(Point(X, Y), Geometry) then
      Exit(RotationHandleCursor);
    Handle := HitTestSelectionHandle(Point(X, Y), Geometry);
    if Handle <> vshNone then
      Exit(SelectionHandleCursor(Handle));
  end;
  LayerIndex := HitTestLayer(X, Y);
  if (LayerIndex >= 0) and not FDocument[LayerIndex].Locked and
    not SelectionContainsLockedLayer then
    Result := crSizeAll;
end;

procedure TVectArtCanvasInteraction.CommitRotationCommand;
var
  NewValue: Single;
begin
  if (FEditHistory = nil) or (FDocument = nil) or
    (FDragLayerIndex <= 0) or
    not (FDocument[FDragLayerIndex] is TVectArtRectangleLayer) then
    Exit;
  NewValue := TVectArtRectangleLayer(
    FDocument[FDragLayerIndex]).RotationDegrees;
  if not SameValue(FRotationStartValue, NewValue) then
    FEditHistory.AddApplied(TVectArtRotationCommand.Create(FDocument,
      FDragLayerIndex, FRotationStartValue, NewValue));
end;

procedure TVectArtCanvasInteraction.CommitLinePointsCommand;
var
  LineLayer: TVectArtLineLayer;
begin
  if (FEditHistory = nil) or (FDocument = nil) or
    (FDragLayerIndex <= 0) or
    not (FDocument[FDragLayerIndex] is TVectArtLineLayer) then
    Exit;
  LineLayer := TVectArtLineLayer(FDocument[FDragLayerIndex]);
  if SameValue(FDragStartLineStart.X, LineLayer.StartPoint.X) and
    SameValue(FDragStartLineStart.Y, LineLayer.StartPoint.Y) and
    SameValue(FDragStartLineEnd.X, LineLayer.EndPoint.X) and
    SameValue(FDragStartLineEnd.Y, LineLayer.EndPoint.Y) then
    Exit;
  FEditHistory.AddApplied(TVectArtLinePointsCommand.Create(FDocument,
    FDragLayerIndex, FDragStartLineStart, FDragStartLineEnd,
    LineLayer.StartPoint, LineLayer.EndPoint));
end;

procedure TVectArtCanvasInteraction.CommitPathPointsCommand;
var
  I: Integer;
  PathLayer: TVectArtPathLayer;
begin
  if (FEditHistory = nil) or (FDocument = nil) or
    (FDragLayerIndex <= 0) or
    not (FDocument[FDragLayerIndex] is TVectArtPathLayer) then
    Exit;
  PathLayer := TVectArtPathLayer(FDocument[FDragLayerIndex]);
  if Length(FDragStartPathPoints) = Length(PathLayer.Points) then
  begin
    if Length(FDragStartPathPoints) = 0 then
      Exit;
    for I := 0 to High(FDragStartPathPoints) do
      if not SameValue(FDragStartPathPoints[I].X, PathLayer.Points[I].X) or
        not SameValue(FDragStartPathPoints[I].Y, PathLayer.Points[I].Y) then
        Break;
    if I > High(FDragStartPathPoints) then
      Exit;
  end;
  FEditHistory.AddApplied(TVectArtPathPointsCommand.Create(FDocument,
    FDragLayerIndex, FDragStartPathPoints, PathLayer.Points));
end;

procedure TVectArtCanvasInteraction.CommitImagePointsCommand;
var
  I: Integer;
  ImageLayer: TVectArtImageLayer;
begin
  if (FEditHistory = nil) or (FDocument = nil) or
    (FDragLayerIndex <= 0) or
    not (FDocument[FDragLayerIndex] is TVectArtImageLayer) then
    Exit;
  ImageLayer := TVectArtImageLayer(FDocument[FDragLayerIndex]);
  for I := 0 to High(FDragStartImagePoints) do
    if not SameValue(FDragStartImagePoints[I].X, ImageLayer.Points[I].X) or
      not SameValue(FDragStartImagePoints[I].Y, ImageLayer.Points[I].Y) then
    begin
      FEditHistory.AddApplied(TVectArtImagePointsCommand.Create(FDocument,
        FDragLayerIndex, FDragStartImagePoints, ImageLayer.Points));
      Exit;
    end;
end;

procedure TVectArtCanvasInteraction.ApplyImageResize(X, Y: Integer);
const
  MIDDLE_COORDINATE = 0.5;
var
  Anchor: TPointF;
  AnchorS: Single;
  AnchorT: Single;
  Delta: TPointF;
  DragPoint: TPointF;
  NewOrigin: TPointF;
  NewPoints: TVectArtImagePoints;
  NewU: TPointF;
  NewV: TPointF;
  S: Single;
  T: Single;
  U: TPointF;
  ULength: Single;
  UUnit: TPointF;
  V: TPointF;
  VLength: Single;
  VUnit: TPointF;
begin
  if (FDocument = nil) or (FDragLayerIndex <= 0) or
    not (FDocument[FDragLayerIndex] is TVectArtImageLayer) then
    Exit;
  case FDragHandle of
    vshTopLeft:     begin S := 0; T := 0; end;
    vshTop:         begin S := MIDDLE_COORDINATE; T := 0; end;
    vshTopRight:    begin S := 1; T := 0; end;
    vshRight:       begin S := 1; T := MIDDLE_COORDINATE; end;
    vshBottomRight: begin S := 1; T := 1; end;
    vshBottom:      begin S := MIDDLE_COORDINATE; T := 1; end;
    vshBottomLeft:  begin S := 0; T := 1; end;
    vshLeft:        begin S := 0; T := MIDDLE_COORDINATE; end;
  else
    Exit;
  end;
  U := TPointF.Create(FDragStartImagePoints[1].X -
    FDragStartImagePoints[0].X, FDragStartImagePoints[1].Y -
    FDragStartImagePoints[0].Y);
  V := TPointF.Create(FDragStartImagePoints[3].X -
    FDragStartImagePoints[0].X, FDragStartImagePoints[3].Y -
    FDragStartImagePoints[0].Y);
  ULength := Hypot(U.X, U.Y);
  VLength := Hypot(V.X, V.Y);
  if (ULength <= 0) or (VLength <= 0) then
    Exit;
  UUnit := TPointF.Create(U.X / ULength, U.Y / ULength);
  VUnit := TPointF.Create(V.X / VLength, V.Y / VLength);
  AnchorS := 1 - S;
  AnchorT := 1 - T;
  Anchor := TPointF.Create(FDragStartImagePoints[0].X + AnchorS * U.X +
    AnchorT * V.X, FDragStartImagePoints[0].Y + AnchorS * U.Y +
    AnchorT * V.Y);
  Delta := TPointF.Create((X - FDragStartMouse.X) / FZoom,
    (Y - FDragStartMouse.Y) / FZoom);
  DragPoint := TPointF.Create(FDragStartImagePoints[0].X + S * U.X +
    T * V.X + Delta.X, FDragStartImagePoints[0].Y + S * U.Y +
    T * V.Y + Delta.Y);
  if not SameValue(S, MIDDLE_COORDINATE) then
    ULength := ClampImageDimension(
      ((DragPoint.X - Anchor.X) * UUnit.X +
       (DragPoint.Y - Anchor.Y) * UUnit.Y) / (S - AnchorS), ULength);
  if not SameValue(T, MIDDLE_COORDINATE) then
    VLength := ClampImageDimension(
      ((DragPoint.X - Anchor.X) * VUnit.X +
       (DragPoint.Y - Anchor.Y) * VUnit.Y) / (T - AnchorT), VLength);
  NewU := TPointF.Create(UUnit.X * ULength, UUnit.Y * ULength);
  NewV := TPointF.Create(VUnit.X * VLength, VUnit.Y * VLength);
  NewOrigin := TPointF.Create(Anchor.X - AnchorS * NewU.X -
    AnchorT * NewV.X, Anchor.Y - AnchorS * NewU.Y - AnchorT * NewV.Y);
  NewPoints[0] := NewOrigin;
  NewPoints[1] := TPointF.Create(NewOrigin.X + NewU.X,
    NewOrigin.Y + NewU.Y);
  NewPoints[2] := TPointF.Create(NewOrigin.X + NewU.X + NewV.X,
    NewOrigin.Y + NewU.Y + NewV.Y);
  NewPoints[3] := TPointF.Create(NewOrigin.X + NewV.X,
    NewOrigin.Y + NewV.Y);
  FDocument.SetImagePoints(FDragLayerIndex, NewPoints);
end;

procedure TVectArtCanvasInteraction.ApplyResizeSelection(X, Y: Integer);
var
  I: Integer;
  ImagePointIndex: Integer;
  NewBounds: TRectF;
  NewImagePoints: TVectArtImagePoints;
  NewSelectionBounds: TRectF;
  ScaleX: Single;
  ScaleY: Single;
  StartBounds: TRectF;
begin
  NewSelectionBounds := ResizedBounds(X, Y);
  ScaleX := NewSelectionBounds.Width / FDragStartBounds.Width;
  ScaleY := NewSelectionBounds.Height / FDragStartBounds.Height;
  for I := 0 to High(FMoveLayerIndices) do
  begin
    StartBounds := FMoveStartBounds[I];
    NewBounds.Left := NewSelectionBounds.Left +
      (StartBounds.Left - FDragStartBounds.Left) * ScaleX;
    NewBounds.Right := NewSelectionBounds.Left +
      (StartBounds.Right - FDragStartBounds.Left) * ScaleX;
    NewBounds.Top := NewSelectionBounds.Top +
      (StartBounds.Top - FDragStartBounds.Top) * ScaleY;
    NewBounds.Bottom := NewSelectionBounds.Top +
      (StartBounds.Bottom - FDragStartBounds.Top) * ScaleY;
    FDocument.SetRectangleBounds(FMoveLayerIndices[I], NewBounds);
  end;
  for I := 0 to High(FMoveImageLayerIndices) do
  begin
    for ImagePointIndex := 0 to High(NewImagePoints) do
      NewImagePoints[ImagePointIndex] := TPointF.Create(
        NewSelectionBounds.Left +
          (FMoveStartImagePoints[I][ImagePointIndex].X -
           FDragStartBounds.Left) * ScaleX,
        NewSelectionBounds.Top +
          (FMoveStartImagePoints[I][ImagePointIndex].Y -
           FDragStartBounds.Top) * ScaleY);
    FDocument.SetImagePoints(FMoveImageLayerIndices[I], NewImagePoints);
  end;
end;

procedure TVectArtCanvasInteraction.ApplyRangeSelection;
var
  I: Integer;
  Intersection: TRect;
  LayerRect: TRect;
  RangeRect: TRect;
  SelectedLayers: TList<Integer>;
begin
  if FDocument = nil then
    Exit;
  RangeRect := GetRangeSelectionRect;
  if (RangeRect.Width < 3) or (RangeRect.Height < 3) then
  begin
    FDocument.SetSelectedLayers([]);
    Exit;
  end;
  SelectedLayers := TList<Integer>.Create;
  try
    for I := 1 to FDocument.LayerCount - 1 do
      if FDocument[I].Visible and
        ((FDocument[I] is TVectArtRectangleLayer) or
         (FDocument[I] is TVectArtLineLayer) or
         (FDocument[I] is TVectArtPathLayer) or
         (FDocument[I] is TVectArtImageLayer)) then
      begin
        LayerRect := LayerScreenRect(I);
        if IntersectRect(Intersection, RangeRect, LayerRect) then
          SelectedLayers.Add(I);
      end;
    FDocument.SetSelectedLayers(SelectedLayers.ToArray);
  finally
    SelectedLayers.Free;
  end;
end;

procedure TVectArtCanvasInteraction.CaptureMoveSelection;
var
  I: Integer;
  ImageIndex: Integer;
  MoveIndex: Integer;
begin
  SetLength(FMoveLayerIndices, FDocument.SelectionCount);
  SetLength(FMoveStartBounds, FDocument.SelectionCount);
  SetLength(FMoveImageLayerIndices, FDocument.SelectionCount);
  SetLength(FMoveStartImagePoints, FDocument.SelectionCount);
  MoveIndex := 0;
  ImageIndex := 0;
  for I := 1 to FDocument.LayerCount - 1 do
    if FDocument.IsLayerSelected(I) then
    begin
      if FDocument[I] is TVectArtRectangleLayer then
      begin
        FMoveLayerIndices[MoveIndex] := I;
        FMoveStartBounds[MoveIndex] :=
          TVectArtRectangleLayer(FDocument[I]).Bounds;
        Inc(MoveIndex);
      end
      else if FDocument[I] is TVectArtImageLayer then
      begin
        FMoveImageLayerIndices[ImageIndex] := I;
        FMoveStartImagePoints[ImageIndex] :=
          TVectArtImageLayer(FDocument[I]).Points;
        Inc(ImageIndex);
      end;
    end;
  SetLength(FMoveLayerIndices, MoveIndex);
  SetLength(FMoveStartBounds, MoveIndex);
  SetLength(FMoveImageLayerIndices, ImageIndex);
  SetLength(FMoveStartImagePoints, ImageIndex);
end;

procedure TVectArtCanvasInteraction.CommitBoundsCommand;
var
  BoundsChanged: Boolean;
  Command: TVectArtCompoundCommand;
  I: Integer;
  ImageChanged: Boolean;
  ImageLayer: TVectArtImageLayer;
  ImagePointIndex: Integer;
  NewBounds: TArray<TRectF>;
begin
  if (FEditHistory = nil) or (FDocument = nil) or
    ((Length(FMoveLayerIndices) = 0) and
     (Length(FMoveImageLayerIndices) = 0)) then
    Exit;
  Command := TVectArtCompoundCommand.Create;
  SetLength(NewBounds, Length(FMoveLayerIndices));
  BoundsChanged := False;
  for I := 0 to High(FMoveLayerIndices) do
  begin
    NewBounds[I] := TVectArtRectangleLayer(
      FDocument[FMoveLayerIndices[I]]).Bounds;
    BoundsChanged := BoundsChanged or
      not SameValue(NewBounds[I].Left, FMoveStartBounds[I].Left) or
      not SameValue(NewBounds[I].Top, FMoveStartBounds[I].Top) or
      not SameValue(NewBounds[I].Right, FMoveStartBounds[I].Right) or
      not SameValue(NewBounds[I].Bottom, FMoveStartBounds[I].Bottom);
  end;
  if BoundsChanged then
    Command.Add(TVectArtBoundsCommand.Create(FDocument,
      FMoveLayerIndices, FMoveStartBounds, NewBounds));
  for I := 0 to High(FMoveImageLayerIndices) do
  begin
    ImageLayer := TVectArtImageLayer(FDocument[FMoveImageLayerIndices[I]]);
    ImageChanged := False;
    for ImagePointIndex := 0 to High(ImageLayer.Points) do
      ImageChanged := ImageChanged or
        not SameValue(FMoveStartImagePoints[I][ImagePointIndex].X,
          ImageLayer.Points[ImagePointIndex].X) or
        not SameValue(FMoveStartImagePoints[I][ImagePointIndex].Y,
          ImageLayer.Points[ImagePointIndex].Y);
    if ImageChanged then
      Command.Add(TVectArtImagePointsCommand.Create(FDocument,
        FMoveImageLayerIndices[I], FMoveStartImagePoints[I],
        ImageLayer.Points));
  end;
  if Command.Count > 0 then
    FEditHistory.AddApplied(Command)
  else
    Command.Free;
end;

procedure TVectArtCanvasInteraction.EndDrag;
begin
  FDragMode := vcdmNone;
  FDragHandle := vshNone;
  FDragLayerIndex := -1;
  FPathVertexIndex := -1;
  FDragIsLine := False;
  FDragIsImage := False;
  FDragIsPath := False;
  FMoveOccurred := False;
  FToggleSelectionModeOnClick := False;
  SetLength(FMoveLayerIndices, 0);
  SetLength(FMoveStartBounds, 0);
  SetLength(FMoveImageLayerIndices, 0);
  SetLength(FMoveStartImagePoints, 0);
  SetLength(FDragStartPathPoints, 0);
end;

function TVectArtCanvasInteraction.HitTestPathVertex(X, Y: Integer): Integer;
var
  I: Integer;
  Rects: TArray<TRect>;
begin
  Result := -1;
  Rects := SelectedPathVertexRects;
  for I := 0 to High(Rects) do
    if PtInRect(Rects[I], Point(X, Y)) then
      Exit(I);
end;

function TVectArtCanvasInteraction.GetDragging: Boolean;
begin
  Result := FDragMode <> vcdmNone;
end;

function TVectArtCanvasInteraction.GetRangeSelectionRect: TRect;
begin
  Result := Rect(Min(FRangeStart.X, FRangeCurrent.X),
    Min(FRangeStart.Y, FRangeCurrent.Y),
    Max(FRangeStart.X, FRangeCurrent.X),
    Max(FRangeStart.Y, FRangeCurrent.Y));
end;

function TVectArtCanvasInteraction.GetRangeSelecting: Boolean;
begin
  Result := FDragMode = vcdmRangeSelect;
end;

function TVectArtCanvasInteraction.HitTestLayer(X, Y: Integer): Integer;
var
  Distance: Single;
  DX: Single;
  DY: Single;
  I: Integer;
  J: Integer;
  Layer: TVectArtLayer;
  LineLayer: TVectArtLineLayer;
  LogicalX: Single;
  LogicalY: Single;
  PathLayer: TVectArtPathLayer;
  ImageLayer: TVectArtImageLayer;
  ImagePolygon: TArray<TPointF>;
  Projection: Single;
  RectangleLayer: TVectArtRectangleLayer;
  SegmentLengthSquared: Single;
  TestX: Single;
  TestY: Single;
begin
  Result := -1;
  if (FDocument = nil) or (FZoom <= 0) or
    not PtInRect(FCanvasBounds, Point(X, Y)) then
    Exit;
  LogicalX := ToLogicalX(X);
  LogicalY := ToLogicalY(Y);
  for I := FDocument.LayerCount - 1 downto 1 do
  begin
    Layer := FDocument[I];
    if not Layer.Visible then
      Continue;
    if Layer is TVectArtImageLayer then
    begin
      ImageLayer := TVectArtImageLayer(Layer);
      SetLength(ImagePolygon, Length(ImageLayer.Points));
      for J := 0 to High(ImageLayer.Points) do
        ImagePolygon[J] := ImageLayer.Points[J];
      if PointInPolygon(TPointF.Create(LogicalX, LogicalY),
        ImagePolygon) then
        Exit(I);
      Continue;
    end;
    if Layer is TVectArtLineLayer then
    begin
      LineLayer := TVectArtLineLayer(Layer);
      DX := LineLayer.EndPoint.X - LineLayer.StartPoint.X;
      DY := LineLayer.EndPoint.Y - LineLayer.StartPoint.Y;
      SegmentLengthSquared := DX * DX + DY * DY;
      if SegmentLengthSquared > 0 then
        Projection := EnsureRange(((LogicalX - LineLayer.StartPoint.X) * DX +
          (LogicalY - LineLayer.StartPoint.Y) * DY) /
          SegmentLengthSquared, 0.0, 1.0)
      else
        Projection := 0;
      TestX := LineLayer.StartPoint.X + Projection * DX;
      TestY := LineLayer.StartPoint.Y + Projection * DY;
      Distance := Hypot(LogicalX - TestX, LogicalY - TestY);
      if Distance <= Max(LineLayer.StrokeWidth * 0.5, 6 / FZoom) then
        Exit(I);
      Continue;
    end;
    if Layer is TVectArtPathLayer then
    begin
      PathLayer := TVectArtPathLayer(Layer);
      if PathLayer.Closed and PathLayer.Filled and
        PointInPolygon(TPointF.Create(LogicalX, LogicalY),
          PathLayer.Points) then
        Exit(I);
      for J := 0 to High(PathLayer.Points) - 1 do
        if DistanceToSegment(TPointF.Create(LogicalX, LogicalY),
          PathLayer.Points[J], PathLayer.Points[J + 1]) <=
          Max(PathLayer.StrokeWidth * 0.5, 6 / FZoom) then
          Exit(I);
      if PathLayer.Closed and (Length(PathLayer.Points) > 2) and
        (DistanceToSegment(TPointF.Create(LogicalX, LogicalY),
          PathLayer.Points[High(PathLayer.Points)], PathLayer.Points[0]) <=
          Max(PathLayer.StrokeWidth * 0.5, 6 / FZoom)) then
        Exit(I);
      Continue;
    end;
    if Layer is TVectArtRectangleLayer then
    begin
      RectangleLayer := TVectArtRectangleLayer(Layer);
      if PointInRotatedRectangle(TPointF.Create(LogicalX, LogicalY),
        RectangleLayer.Bounds, RectangleLayer.RotationDegrees) then
        Exit(I);
    end;
  end;
end;

function TVectArtCanvasInteraction.LayerScreenRect(Index: Integer): TRect;
var
  Bounds: TRectF;
  LineLayer: TVectArtLineLayer;
  ImageLayer: TVectArtImageLayer;
  PathLayer: TVectArtPathLayer;
  RectangleLayer: TVectArtRectangleLayer;
begin
  Result := TRect.Empty;
  if (FDocument = nil) or (Index <= 0) or
    (Index >= FDocument.LayerCount) or
    not ((FDocument[Index] is TVectArtRectangleLayer) or
      (FDocument[Index] is TVectArtLineLayer) or
      (FDocument[Index] is TVectArtPathLayer) or
      (FDocument[Index] is TVectArtImageLayer)) then
    Exit;
  if FDocument[Index] is TVectArtImageLayer then
  begin
    ImageLayer := TVectArtImageLayer(FDocument[Index]);
    Bounds := ImagePointsBounds(ImageLayer.Points);
    Result := Rect(ToScreenX(Bounds.Left), ToScreenY(Bounds.Top),
      ToScreenX(Bounds.Right), ToScreenY(Bounds.Bottom));
    Exit;
  end;
  if FDocument[Index] is TVectArtLineLayer then
  begin
    LineLayer := TVectArtLineLayer(FDocument[Index]);
    Result := Rect(ToScreenX(Min(LineLayer.StartPoint.X,
      LineLayer.EndPoint.X)), ToScreenY(Min(LineLayer.StartPoint.Y,
      LineLayer.EndPoint.Y)), ToScreenX(Max(LineLayer.StartPoint.X,
      LineLayer.EndPoint.X)), ToScreenY(Max(LineLayer.StartPoint.Y,
      LineLayer.EndPoint.Y)));
    if Result.Width = 0 then
      Inc(Result.Right);
    if Result.Height = 0 then
      Inc(Result.Bottom);
    Exit;
  end;
  if FDocument[Index] is TVectArtPathLayer then
  begin
    PathLayer := TVectArtPathLayer(FDocument[Index]);
    Bounds := PointsBounds(PathLayer.Points);
    Result := Rect(ToScreenX(Bounds.Left), ToScreenY(Bounds.Top),
      ToScreenX(Bounds.Right), ToScreenY(Bounds.Bottom));
    if Result.Width = 0 then
      Inc(Result.Right);
    if Result.Height = 0 then
      Inc(Result.Bottom);
    Exit;
  end;
  RectangleLayer := TVectArtRectangleLayer(FDocument[Index]);
  Bounds := QuadBounds(RectangleCorners(RectangleLayer.Bounds,
    RectangleLayer.RotationDegrees));
  Result := Rect(ToScreenX(Bounds.Left), ToScreenY(Bounds.Top),
    ToScreenX(Bounds.Right), ToScreenY(Bounds.Bottom));
end;

function TVectArtCanvasInteraction.SelectedLayersLogicalRect: TRectF;
var
  Bounds: TRectF;
  Found: Boolean;
  I: Integer;
  ImageLayer: TVectArtImageLayer;
  LineLayer: TVectArtLineLayer;
  PathLayer: TVectArtPathLayer;
  RectangleLayer: TVectArtRectangleLayer;
begin
  Result := TRectF.Empty;
  Found := False;
  if FDocument = nil then
    Exit;
  for I := 1 to FDocument.LayerCount - 1 do
    if FDocument.IsLayerSelected(I) and FDocument[I].Visible and
      ((FDocument[I] is TVectArtRectangleLayer) or
       (FDocument[I] is TVectArtLineLayer) or
       (FDocument[I] is TVectArtPathLayer) or
       (FDocument[I] is TVectArtImageLayer)) then
    begin
      if FDocument[I] is TVectArtRectangleLayer then
      begin
        RectangleLayer := TVectArtRectangleLayer(FDocument[I]);
        Bounds := QuadBounds(RectangleCorners(RectangleLayer.Bounds,
          RectangleLayer.RotationDegrees));
      end
      else if FDocument[I] is TVectArtLineLayer then
      begin
        LineLayer := TVectArtLineLayer(FDocument[I]);
        Bounds := TRectF.Create(Min(LineLayer.StartPoint.X,
          LineLayer.EndPoint.X), Min(LineLayer.StartPoint.Y,
          LineLayer.EndPoint.Y), Max(LineLayer.StartPoint.X,
          LineLayer.EndPoint.X), Max(LineLayer.StartPoint.Y,
          LineLayer.EndPoint.Y));
        if SameValue(Bounds.Left, Bounds.Right) then
          Bounds.Right := Bounds.Left + 0.001;
        if SameValue(Bounds.Top, Bounds.Bottom) then
          Bounds.Bottom := Bounds.Top + 0.001;
      end
      else if FDocument[I] is TVectArtPathLayer then
      begin
        PathLayer := TVectArtPathLayer(FDocument[I]);
        Bounds := PointsBounds(PathLayer.Points);
      end
      else
      begin
        ImageLayer := TVectArtImageLayer(FDocument[I]);
        Bounds := ImagePointsBounds(ImageLayer.Points);
      end;
      if not Found then
      begin
        Result := Bounds;
        Found := True;
      end
      else
      begin
        Result.Left := Min(Result.Left, Bounds.Left);
        Result.Top := Min(Result.Top, Bounds.Top);
        Result.Right := Max(Result.Right, Bounds.Right);
        Result.Bottom := Max(Result.Bottom, Bounds.Bottom);
      end;
    end;
end;

function TVectArtCanvasInteraction.SelectionContainsLockedLayer: Boolean;
var
  I: Integer;
begin
  Result := False;
  if FDocument = nil then
    Exit;
  for I := 1 to FDocument.LayerCount - 1 do
    if FDocument.IsLayerSelected(I) and FDocument[I].Locked then
      Exit(True);
end;

function TVectArtCanvasInteraction.SelectedLayersFrameOffset: Integer;
var
  I: Integer;
  PathLayer: TVectArtPathLayer;
  RectangleLayer: TVectArtRectangleLayer;
begin
  Result := SelectionFrameOffset(0, FZoom);
  if FDocument = nil then
    Exit;
  for I := 1 to FDocument.LayerCount - 1 do
    if FDocument.IsLayerSelected(I) and
      (FDocument[I] is TVectArtRectangleLayer) then
    begin
      RectangleLayer := TVectArtRectangleLayer(FDocument[I]);
      Result := Max(Result, SelectionFrameOffset(
        RectangleLayer.StrokeWidth, FZoom));
    end;
  for I := 1 to FDocument.LayerCount - 1 do
    if FDocument.IsLayerSelected(I) and
      (FDocument[I] is TVectArtPathLayer) then
    begin
      PathLayer := TVectArtPathLayer(FDocument[I]);
      Result := Max(Result, SelectionFrameOffset(PathLayer.StrokeWidth,
        FZoom));
    end;
end;

function TVectArtCanvasInteraction.SelectedLayerSelectionGeometry(
  out Geometry: TVectArtSelectionGeometry): Boolean;
var
  I: Integer;
  ImageLayer: TVectArtImageLayer;
  LineLayer: TVectArtLineLayer;
  LogicalQuad: TVectArtQuad;
  RectangleLayer: TVectArtRectangleLayer;
  ScreenQuad: TVectArtScreenQuad;
begin
  if (FDocument <> nil) and (FDocument.SelectionCount = 1) and
    (FDocument.SelectedIndex > 0) and
    (FDocument[FDocument.SelectedIndex] is TVectArtImageLayer) then
  begin
    ImageLayer := TVectArtImageLayer(FDocument[FDocument.SelectedIndex]);
    for I := 0 to High(ScreenQuad) do
      ScreenQuad[I] := Point(ToScreenX(ImageLayer.Points[I].X),
        ToScreenY(ImageLayer.Points[I].Y));
    Geometry := BuildRotatedSelectionGeometry(ScreenQuad,
      SelectionFrameOffset(0, FZoom));
    Exit(True);
  end;
  if (FDocument <> nil) and (FDocument.SelectionCount = 1) and
    (FDocument.SelectedIndex > 0) and
    (FDocument[FDocument.SelectedIndex] is TVectArtPathLayer) then
  begin
    Geometry := BuildPathSelectionGeometry(
      LayerScreenRect(FDocument.SelectedIndex),
      SelectionFrameOffset(TVectArtPathLayer(
        FDocument[FDocument.SelectedIndex]).StrokeWidth, FZoom));
    Exit(True);
  end;
  if (FDocument <> nil) and (FDocument.SelectionCount = 1) and
    (FDocument.SelectedIndex > 0) and
    (FDocument[FDocument.SelectedIndex] is TVectArtLineLayer) then
  begin
    LineLayer := TVectArtLineLayer(FDocument[FDocument.SelectedIndex]);
    Geometry := BuildLineSelectionGeometry(
      Point(ToScreenX(LineLayer.StartPoint.X),
        ToScreenY(LineLayer.StartPoint.Y)),
      Point(ToScreenX(LineLayer.EndPoint.X),
        ToScreenY(LineLayer.EndPoint.Y)));
    Exit(True);
  end;
  if FAxisAlignedSelection then
  begin
    Result := False;
    Exit;
  end;
  Result := (FDocument <> nil) and (FDocument.SelectionCount = 1) and
    (FDocument.SelectedIndex > 0) and
    (FDocument[FDocument.SelectedIndex] is TVectArtRectangleLayer);
  if not Result then
    Exit;
  RectangleLayer := TVectArtRectangleLayer(
    FDocument[FDocument.SelectedIndex]);
  LogicalQuad := RectangleCorners(RectangleLayer.Bounds,
    RectangleLayer.RotationDegrees);
  for I := 0 to High(ScreenQuad) do
    ScreenQuad[I] := Point(ToScreenX(LogicalQuad[I].X),
      ToScreenY(LogicalQuad[I].Y));
  Geometry := BuildRotatedSelectionGeometry(ScreenQuad,
    SelectionFrameOffset(RectangleLayer.StrokeWidth, FZoom));
end;

function TVectArtCanvasInteraction.SelectedLayersScreenRect: TRect;
var
  LogicalRect: TRectF;
begin
  Result := TRect.Empty;
  LogicalRect := SelectedLayersLogicalRect;
  if LogicalRect.IsEmpty then
    Exit;
  Result := Rect(ToScreenX(LogicalRect.Left), ToScreenY(LogicalRect.Top),
    ToScreenX(LogicalRect.Right), ToScreenY(LogicalRect.Bottom));
  if Result.Width = 0 then
    Inc(Result.Right);
  if Result.Height = 0 then
    Inc(Result.Bottom);
end;

function TVectArtCanvasInteraction.MouseDown(Button: TMouseButton;
  X, Y: Integer): Boolean;
begin
  Result := MouseDown(Button, [], X, Y);
end;

function TVectArtCanvasInteraction.MouseDown(Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer): Boolean;
var
  CenterX: Single;
  CenterY: Single;
  Geometry: TVectArtSelectionGeometry;
  ImageBounds: TRectF;
  ImageLayer: TVectArtImageLayer;
  RectangleLayer: TVectArtRectangleLayer;
  SelectionRect: TRect;
  WasSelected: Boolean;
begin
  Result := False;
  if (Button <> mbLeft) or (FDocument = nil) or (FZoom <= 0) then
    Exit;
  if ssCtrl in Shift then
  begin
    FDragLayerIndex := HitTestLayer(X, Y);
    if FDragLayerIndex > 0 then
      FDocument.ToggleSelectedLayer(FDragLayerIndex);
    FDragLayerIndex := -1;
    // 選択だけでドラッグは開始しないため、Canvasへマウスキャプチャを要求しない。
    Exit(False);
  end;
  FPathVertexIndex := HitTestPathVertex(X, Y);
  if (FPathVertexIndex >= 0) and not SelectionContainsLockedLayer then
  begin
    FDragMode := vcdmPathVertex;
    FDragLayerIndex := FDocument.SelectedIndex;
    FDragIsPath := True;
    FDragStartPathPoints := Copy(TVectArtPathLayer(
      FDocument[FDragLayerIndex]).Points);
    FDragStartMouse := Point(X, Y);
    Exit(True);
  end;
  SelectionRect := SelectedLayersScreenRect;
  if not SelectionRect.IsEmpty and not SelectionContainsLockedLayer then
  begin
    if not SelectedLayerSelectionGeometry(Geometry) then
      Geometry := BuildSelectionGeometry(SelectionRect,
        SelectedLayersFrameOffset);
    if not FAxisAlignedSelection and (FDocument.SelectionCount = 1) and
      HitTestRotationHandle(Point(X, Y), Geometry) and
      ((FDocument[FDocument.SelectedIndex] is TVectArtRectangleLayer) or
       (FDocument[FDocument.SelectedIndex] is TVectArtImageLayer)) then
    begin
      FDragMode := vcdmRotate;
      FDragLayerIndex := FDocument.SelectedIndex;
      FDragIsImage := FDocument[FDragLayerIndex] is TVectArtImageLayer;
      if FDragIsImage then
      begin
        ImageLayer := TVectArtImageLayer(FDocument[FDragLayerIndex]);
        FDragStartImagePoints := ImageLayer.Points;
        ImageBounds := ImagePointsBounds(ImageLayer.Points);
        FRotationStartValue := 0;
        CenterX := ToScreenX((ImageBounds.Left + ImageBounds.Right) * 0.5);
        CenterY := ToScreenY((ImageBounds.Top + ImageBounds.Bottom) * 0.5);
      end
      else
      begin
        RectangleLayer := TVectArtRectangleLayer(
          FDocument[FDragLayerIndex]);
        FRotationStartValue := RectangleLayer.RotationDegrees;
        CenterX := ToScreenX((RectangleLayer.Bounds.Left +
          RectangleLayer.Bounds.Right) * 0.5);
        CenterY := ToScreenY((RectangleLayer.Bounds.Top +
          RectangleLayer.Bounds.Bottom) * 0.5);
      end;
      FRotationStartMouseAngle := RadToDeg(ArcTan2(Y - CenterY,
        X - CenterX));
    end
    else
    begin
      FDragHandle := HitTestSelectionHandle(Point(X, Y), Geometry);
      if FDragHandle <> vshNone then
      begin
        FDragMode := vcdmResize;
        FDragLayerIndex := FDocument.SelectedIndex;
        FDragIsLine := (FDocument.SelectionCount = 1) and
          (FDocument[FDragLayerIndex] is TVectArtLineLayer);
        FDragIsImage := (FDocument.SelectionCount = 1) and
          (FDocument[FDragLayerIndex] is TVectArtImageLayer);
        if FDragIsLine then
        begin
          FDragStartLineStart := TVectArtLineLayer(
            FDocument[FDragLayerIndex]).StartPoint;
          FDragStartLineEnd := TVectArtLineLayer(
            FDocument[FDragLayerIndex]).EndPoint;
        end
        else if FDragIsImage then
          FDragStartImagePoints := TVectArtImageLayer(
            FDocument[FDragLayerIndex]).Points
        else
          CaptureMoveSelection;
        if not FDragIsLine and (FDocument.SelectionCount = 1) and
          (FDocument[FDragLayerIndex] is TVectArtRectangleLayer) then
          FDragStartBounds := TVectArtRectangleLayer(
            FDocument[FDragLayerIndex]).Bounds
        else
          FDragStartBounds := SelectedLayersLogicalRect;
      end;
    end;
  end;
  if FDragMode = vcdmNone then
  begin
    FDragLayerIndex := HitTestLayer(X, Y);
    if FDragLayerIndex < 0 then
    begin
      FDocument.SelectedIndex := -1;
      if not PtInRect(FCanvasBounds, Point(X, Y)) then
        Exit;
      FDragMode := vcdmRangeSelect;
      FRangeStart := Point(X, Y);
      FRangeCurrent := FRangeStart;
      Exit(True);
    end
    else
    begin
      WasSelected := FDocument.IsLayerSelected(FDragLayerIndex);
      FToggleSelectionModeOnClick := WasSelected and
        (FDocument.SelectionCount = 1) and
        (FDocument.SelectedIndex = FDragLayerIndex) and
        (FDocument[FDragLayerIndex] is TVectArtRectangleLayer);
      // 選択済みの図形をつかんだ場合は複数選択を維持する。
      if not FDocument.IsLayerSelected(FDragLayerIndex) then
        FDocument.SelectedIndex := FDragLayerIndex;
      if FDocument[FDragLayerIndex].Locked or
        SelectionContainsLockedLayer then
      begin
        FDragLayerIndex := -1;
        Exit(False);
      end;
      FDragMode := vcdmMove;
      FDragIsLine := (FDocument.SelectionCount = 1) and
        (FDocument[FDragLayerIndex] is TVectArtLineLayer);
      FDragIsImage := (FDocument.SelectionCount = 1) and
        (FDocument[FDragLayerIndex] is TVectArtImageLayer);
      FDragIsPath := (FDocument.SelectionCount = 1) and
        (FDocument[FDragLayerIndex] is TVectArtPathLayer);
      if FDragIsLine then
      begin
        FDragStartLineStart := TVectArtLineLayer(
          FDocument[FDragLayerIndex]).StartPoint;
        FDragStartLineEnd := TVectArtLineLayer(
          FDocument[FDragLayerIndex]).EndPoint;
      end
      else if FDragIsPath then
        FDragStartPathPoints := Copy(TVectArtPathLayer(
          FDocument[FDragLayerIndex]).Points)
      else if FDragIsImage then
        FDragStartImagePoints := TVectArtImageLayer(
          FDocument[FDragLayerIndex]).Points
      else
        CaptureMoveSelection;
    end;
  end;
  FDragStartMouse := Point(X, Y);
  Result := True;
end;

function TVectArtCanvasInteraction.MouseMove(Shift: TShiftState;
  X, Y: Integer): Boolean;
var
  CenterX: Single;
  CenterY: Single;
  CurrentMouseAngle: Single;
  DX: Single;
  DY: Single;
  I: Integer;
  ImagePointIndex: Integer;
  LineLength: Single;
  LineUnitX: Single;
  LineUnitY: Single;
  LogicalHandleDistance: Single;
  LogicalMouseX: Single;
  LogicalMouseY: Single;
  NewBounds: TRectF;
  NewImagePoints: TVectArtImagePoints;
  NewPathPoints: TArray<TPointF>;
  ImageBounds: TRectF;
  RectangleLayer: TVectArtRectangleLayer;
begin
  Result := False;
  if FDragMode = vcdmNone then
    Exit;
  if not (ssLeft in Shift) then
  begin
    EndDrag;
    Exit(True);
  end;
  if FDragMode = vcdmRangeSelect then
  begin
    FRangeCurrent := Point(X, Y);
    Exit(True);
  end;
  if FDragMode = vcdmPathVertex then
  begin
    if (FDragLayerIndex <= 0) or (FPathVertexIndex < 0) or
      not (FDocument[FDragLayerIndex] is TVectArtPathLayer) then
      Exit(True);
    NewPathPoints := Copy(FDragStartPathPoints);
    NewPathPoints[FPathVertexIndex] := TPointF.Create(
      EnsureRange(ToLogicalX(X), FDocument.CanvasLayer.Width * -0.5,
        FDocument.CanvasLayer.Width * 0.5),
      EnsureRange(ToLogicalY(Y), FDocument.CanvasLayer.Height * -0.5,
        FDocument.CanvasLayer.Height * 0.5));
    FDocument.SetPathPoints(FDragLayerIndex, NewPathPoints);
    Exit(True);
  end;
  if FDragMode = vcdmMove then
  begin
    if (Abs(X - FDragStartMouse.X) < MOVE_DRAG_THRESHOLD) and
      (Abs(Y - FDragStartMouse.Y) < MOVE_DRAG_THRESHOLD) then
      Exit(True);
    FMoveOccurred := True;
    DX := (X - FDragStartMouse.X) / FZoom;
    DY := (Y - FDragStartMouse.Y) / FZoom;
    if FDragIsImage then
    begin
      for I := 0 to High(NewImagePoints) do
        NewImagePoints[I] := TPointF.Create(
          FDragStartImagePoints[I].X + DX,
          FDragStartImagePoints[I].Y + DY);
      FDocument.SetImagePoints(FDragLayerIndex, NewImagePoints);
      Exit(True);
    end;
    if FDragIsPath then
    begin
      SetLength(NewPathPoints, Length(FDragStartPathPoints));
      for I := 0 to High(FDragStartPathPoints) do
        NewPathPoints[I] := TPointF.Create(FDragStartPathPoints[I].X + DX,
          FDragStartPathPoints[I].Y + DY);
      FDocument.SetPathPoints(FDragLayerIndex, NewPathPoints);
      Exit(True);
    end;
    if FDragIsLine then
    begin
      FDocument.SetLinePoints(FDragLayerIndex,
        TPointF.Create(FDragStartLineStart.X + DX,
          FDragStartLineStart.Y + DY),
        TPointF.Create(FDragStartLineEnd.X + DX,
          FDragStartLineEnd.Y + DY));
      Exit(True);
    end;
    for I := 0 to High(FMoveLayerIndices) do
    begin
      NewBounds := FMoveStartBounds[I];
      NewBounds.Offset(DX, DY);
      FDocument.SetRectangleBounds(FMoveLayerIndices[I], NewBounds);
    end;
    for I := 0 to High(FMoveImageLayerIndices) do
    begin
      for ImagePointIndex := 0 to High(NewImagePoints) do
        NewImagePoints[ImagePointIndex] := TPointF.Create(
          FMoveStartImagePoints[I][ImagePointIndex].X + DX,
          FMoveStartImagePoints[I][ImagePointIndex].Y + DY);
      FDocument.SetImagePoints(FMoveImageLayerIndices[I], NewImagePoints);
    end;
    Exit(True);
  end
  else if FDragMode = vcdmRotate then
  begin
    if FDragLayerIndex <= 0 then
      Exit(True);
    if FDragIsImage and
      (FDocument[FDragLayerIndex] is TVectArtImageLayer) then
    begin
      ImageBounds := ImagePointsBounds(FDragStartImagePoints);
      CenterX := ToScreenX((ImageBounds.Left + ImageBounds.Right) * 0.5);
      CenterY := ToScreenY((ImageBounds.Top + ImageBounds.Bottom) * 0.5);
      CurrentMouseAngle := RadToDeg(ArcTan2(Y - CenterY, X - CenterX));
      for I := 0 to High(NewImagePoints) do
        NewImagePoints[I] := RotatePointAround(FDragStartImagePoints[I],
          TPointF.Create((ImageBounds.Left + ImageBounds.Right) * 0.5,
            (ImageBounds.Top + ImageBounds.Bottom) * 0.5),
          CurrentMouseAngle - FRotationStartMouseAngle);
      FDocument.SetImagePoints(FDragLayerIndex, NewImagePoints);
      Exit(True);
    end;
    if not (FDocument[FDragLayerIndex] is TVectArtRectangleLayer) then
      Exit(True);
    RectangleLayer := TVectArtRectangleLayer(FDocument[FDragLayerIndex]);
    CenterX := ToScreenX((RectangleLayer.Bounds.Left +
      RectangleLayer.Bounds.Right) * 0.5);
    CenterY := ToScreenY((RectangleLayer.Bounds.Top +
      RectangleLayer.Bounds.Bottom) * 0.5);
    CurrentMouseAngle := RadToDeg(ArcTan2(Y - CenterY, X - CenterX));
    FDocument.SetRectangleRotation(FDragLayerIndex,
      FRotationStartValue + CurrentMouseAngle - FRotationStartMouseAngle);
    Exit(True);
  end
  else if FDragIsImage then
    ApplyImageResize(X, Y)
  else if FDragIsLine then
  begin
    LineLength := Hypot(FDragStartLineEnd.X - FDragStartLineStart.X,
      FDragStartLineEnd.Y - FDragStartLineStart.Y);
    if LineLength > 0 then
    begin
      LineUnitX := (FDragStartLineEnd.X - FDragStartLineStart.X) /
        LineLength;
      LineUnitY := (FDragStartLineEnd.Y - FDragStartLineStart.Y) /
        LineLength;
    end
    else
    begin
      LineUnitX := 1;
      LineUnitY := 0;
    end;
    LogicalHandleDistance := LineSelectionHandleDistance / FZoom;
    LogicalMouseX := ToLogicalX(X);
    LogicalMouseY := ToLogicalY(Y);
    if FDragHandle = vshTopLeft then
      FDocument.SetLinePoints(FDragLayerIndex,
        TPointF.Create(LogicalMouseX + LineUnitX * LogicalHandleDistance,
          LogicalMouseY + LineUnitY * LogicalHandleDistance),
        FDragStartLineEnd)
    else if FDragHandle = vshBottomRight then
      FDocument.SetLinePoints(FDragLayerIndex, FDragStartLineStart,
        TPointF.Create(LogicalMouseX - LineUnitX * LogicalHandleDistance,
          LogicalMouseY - LineUnitY * LogicalHandleDistance));
  end
  else
    ApplyResizeSelection(X, Y);
  Result := True;
end;

function TVectArtCanvasInteraction.MouseUp(Button: TMouseButton): Boolean;
begin
  Result := (Button = mbLeft) and (FDragMode <> vcdmNone);
  if Result then
  begin
    if FDragMode = vcdmRangeSelect then
      ApplyRangeSelection;
    if FDragMode in [vcdmMove, vcdmResize, vcdmPathVertex] then
      if FDragIsImage then
        CommitImagePointsCommand
      else if FDragIsPath then
        CommitPathPointsCommand
      else if FDragIsLine then
        CommitLinePointsCommand
      else
        CommitBoundsCommand;
    if FDragMode = vcdmRotate then
      if FDragIsImage then
        CommitImagePointsCommand
      else
        CommitRotationCommand;
    if FToggleSelectionModeOnClick and not FMoveOccurred then
      FAxisAlignedSelection := not FAxisAlignedSelection;
    EndDrag;
  end;
end;

function TVectArtCanvasInteraction.SelectedPathVertexRects: TArray<TRect>;
var
  HalfSize: Integer;
  I: Integer;
  PathLayer: TVectArtPathLayer;
  X: Integer;
  Y: Integer;
begin
  Result := nil;
  if (FDocument = nil) or (FDocument.SelectionCount <> 1) or
    (FDocument.SelectedIndex <= 0) or
    not (FDocument[FDocument.SelectedIndex] is TVectArtPathLayer) then
    Exit;
  PathLayer := TVectArtPathLayer(FDocument[FDocument.SelectedIndex]);
  if PathLayer.Locked then
    Exit;
  SetLength(Result, Length(PathLayer.Points));
  HalfSize := PATH_VERTEX_HANDLE_SIZE div 2;
  for I := 0 to High(PathLayer.Points) do
  begin
    X := ToScreenX(PathLayer.Points[I].X);
    Y := ToScreenY(PathLayer.Points[I].Y);
    Result[I] := Rect(X - HalfSize, Y - HalfSize,
      X - HalfSize + PATH_VERTEX_HANDLE_SIZE,
      Y - HalfSize + PATH_VERTEX_HANDLE_SIZE);
  end;
end;

function TVectArtCanvasInteraction.AxisAlignedResizedBounds(X, Y: Integer;
  RotationDegrees: Single): TRectF;
var
  Cosine: Single;
  DesiredOuter: TRectF;
  Determinant: Single;
  DX: Single;
  DY: Single;
  NewCenter: TPointF;
  NewHeight: Single;
  NewWidth: Single;
  OriginalOuter: TRectF;
  OuterHeight: Single;
  OuterWidth: Single;
  Scale: Single;
  Sine: Single;
begin
  OriginalOuter := QuadBounds(RectangleCorners(FDragStartBounds,
    RotationDegrees));
  DesiredOuter := OriginalOuter;
  DX := (X - FDragStartMouse.X) / FZoom;
  DY := (Y - FDragStartMouse.Y) / FZoom;
  if FDragHandle in [vshTopLeft, vshLeft, vshBottomLeft] then
    DesiredOuter.Left := Min(DesiredOuter.Left + DX,
      DesiredOuter.Right - MIN_RECTANGLE_SIZE)
  else if FDragHandle in [vshTopRight, vshRight, vshBottomRight] then
    DesiredOuter.Right := Max(DesiredOuter.Right + DX,
      DesiredOuter.Left + MIN_RECTANGLE_SIZE);
  if FDragHandle in [vshTopLeft, vshTop, vshTopRight] then
    DesiredOuter.Top := Min(DesiredOuter.Top + DY,
      DesiredOuter.Bottom - MIN_RECTANGLE_SIZE)
  else if FDragHandle in [vshBottomLeft, vshBottom, vshBottomRight] then
    DesiredOuter.Bottom := Max(DesiredOuter.Bottom + DY,
      DesiredOuter.Top + MIN_RECTANGLE_SIZE);

  Cosine := Abs(Cos(DegToRad(RotationDegrees)));
  Sine := Abs(Sin(DegToRad(RotationDegrees)));
  Determinant := Cosine * Cosine - Sine * Sine;
  if Abs(Determinant) > 0.05 then
  begin
    NewWidth := (Cosine * DesiredOuter.Width -
      Sine * DesiredOuter.Height) / Determinant;
    NewHeight := (Cosine * DesiredOuter.Height -
      Sine * DesiredOuter.Width) / Determinant;
  end
  else
  begin
    NewWidth := -1;
    NewHeight := -1;
  end;
  if (NewWidth < MIN_RECTANGLE_SIZE) or
    (NewHeight < MIN_RECTANGLE_SIZE) then
  begin
    // 45度付近や成立しない外接寸法では縦横比を保って破綻を避ける。
    Scale := Max(DesiredOuter.Width / Max(OriginalOuter.Width, 0.001),
      DesiredOuter.Height / Max(OriginalOuter.Height, 0.001));
    NewWidth := FDragStartBounds.Width * Scale;
    NewHeight := FDragStartBounds.Height * Scale;
  end;
  NewWidth := Max(NewWidth, MIN_RECTANGLE_SIZE);
  NewHeight := Max(NewHeight, MIN_RECTANGLE_SIZE);
  OuterWidth := Cosine * NewWidth + Sine * NewHeight;
  OuterHeight := Sine * NewWidth + Cosine * NewHeight;
  NewCenter := TPointF.Create(
    (DesiredOuter.Left + DesiredOuter.Right) * 0.5,
    (DesiredOuter.Top + DesiredOuter.Bottom) * 0.5);
  if FDragHandle in [vshTopLeft, vshLeft, vshBottomLeft] then
    NewCenter.X := DesiredOuter.Right - OuterWidth * 0.5
  else if FDragHandle in [vshTopRight, vshRight, vshBottomRight] then
    NewCenter.X := DesiredOuter.Left + OuterWidth * 0.5;
  if FDragHandle in [vshTopLeft, vshTop, vshTopRight] then
    NewCenter.Y := DesiredOuter.Bottom - OuterHeight * 0.5
  else if FDragHandle in [vshBottomLeft, vshBottom, vshBottomRight] then
    NewCenter.Y := DesiredOuter.Top + OuterHeight * 0.5;
  Result := TRectF.Create(NewCenter.X - NewWidth * 0.5,
    NewCenter.Y - NewHeight * 0.5, NewCenter.X + NewWidth * 0.5,
    NewCenter.Y + NewHeight * 0.5);
end;

function TVectArtCanvasInteraction.ResizedBounds(X, Y: Integer): TRectF;
var
  Anchor: TPointF;
  Center: TPointF;
  CurrentLogical: TPointF;
  DX: Single;
  DY: Single;
  LocalCurrent: TPointF;
  LocalStart: TPointF;
  NewAnchor: TPointF;
  NewCenter: TPointF;
  RectangleLayer: TVectArtRectangleLayer;
  RotationDegrees: Single;
  StartAnchor: TPointF;
  StartLogical: TPointF;
begin
  Result := FDragStartBounds;
  RotationDegrees := 0.0;
  if (FDocument <> nil) and (FDocument.SelectionCount = 1) and
    (FDragLayerIndex > 0) and
    (FDocument[FDragLayerIndex] is TVectArtRectangleLayer) then
  begin
    RectangleLayer := TVectArtRectangleLayer(FDocument[FDragLayerIndex]);
    RotationDegrees := RectangleLayer.RotationDegrees;
  end;
  if FAxisAlignedSelection and not SameValue(RotationDegrees, 0.0) then
    Exit(AxisAlignedResizedBounds(X, Y, RotationDegrees));
  if SameValue(RotationDegrees, 0.0) then
  begin
    DX := (X - FDragStartMouse.X) / FZoom;
    DY := (Y - FDragStartMouse.Y) / FZoom;
  end
  else
  begin
    Center := TPointF.Create((FDragStartBounds.Left +
      FDragStartBounds.Right) * 0.5, (FDragStartBounds.Top +
      FDragStartBounds.Bottom) * 0.5);
    StartLogical := TPointF.Create(ToLogicalX(FDragStartMouse.X),
      ToLogicalY(FDragStartMouse.Y));
    CurrentLogical := TPointF.Create(ToLogicalX(X), ToLogicalY(Y));
    LocalStart := RotatePointAround(StartLogical, Center, -RotationDegrees);
    LocalCurrent := RotatePointAround(CurrentLogical, Center,
      -RotationDegrees);
    DX := LocalCurrent.X - LocalStart.X;
    DY := LocalCurrent.Y - LocalStart.Y;
  end;
  if FDragHandle in [vshTopLeft, vshLeft, vshBottomLeft] then
    Result.Left := Min(FDragStartBounds.Left + DX,
      FDragStartBounds.Right - MIN_RECTANGLE_SIZE);
  if FDragHandle in [vshTopRight, vshRight, vshBottomRight] then
    Result.Right := Max(FDragStartBounds.Right + DX,
      FDragStartBounds.Left + MIN_RECTANGLE_SIZE);
  if FDragHandle in [vshTopLeft, vshTop, vshTopRight] then
    Result.Top := Min(FDragStartBounds.Top + DY,
      FDragStartBounds.Bottom - MIN_RECTANGLE_SIZE);
  if FDragHandle in [vshBottomLeft, vshBottom, vshBottomRight] then
    Result.Bottom := Max(FDragStartBounds.Bottom + DY,
      FDragStartBounds.Top + MIN_RECTANGLE_SIZE);
  if not SameValue(RotationDegrees, 0.0) then
  begin
    Anchor := Center;
    if FDragHandle in [vshTopLeft, vshLeft, vshBottomLeft] then
      Anchor.X := FDragStartBounds.Right
    else if FDragHandle in [vshTopRight, vshRight, vshBottomRight] then
      Anchor.X := FDragStartBounds.Left;
    if FDragHandle in [vshTopLeft, vshTop, vshTopRight] then
      Anchor.Y := FDragStartBounds.Bottom
    else if FDragHandle in [vshBottomLeft, vshBottom, vshBottomRight] then
      Anchor.Y := FDragStartBounds.Top;
    NewCenter := TPointF.Create((Result.Left + Result.Right) * 0.5,
      (Result.Top + Result.Bottom) * 0.5);
    StartAnchor := RotatePointAround(Anchor, Center, RotationDegrees);
    NewAnchor := RotatePointAround(Anchor, NewCenter, RotationDegrees);
    Result.Offset(StartAnchor.X - NewAnchor.X,
      StartAnchor.Y - NewAnchor.Y);
  end;
end;

end.
