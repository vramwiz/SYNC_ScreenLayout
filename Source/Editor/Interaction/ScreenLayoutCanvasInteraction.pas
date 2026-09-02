// 編集キャンバス上の選択、範囲選択、共通変形と各編集操作への入力振り分けを管理する。
unit ScreenLayoutCanvasInteraction;

interface

uses
  System.Classes, System.Generics.Collections, System.Types, Vcl.Controls,
  ScreenLayoutDocument, ScreenLayoutEditHistory,
  ScreenLayoutEditCommands,
  ScreenLayoutPathInteraction, ScreenLayoutSelectionGeometry,
  ScreenLayoutShapeInteraction;

type
  TVectArtCanvasDragMode = (vcdmNone, vcdmMove, vcdmResize, vcdmRotate,
    vcdmRangeSelect, vcdmRoundedRadius, vcdmRoundedCornerRadius,
    vcdmArcStartAngle, vcdmArcEndAngle,
    vcdmPathVertex, vcdmPathBezierHandle, vcdmShapeVertex,
    vcdmShapeBezierHandle);

  TScreenLayoutArcAngleHandles = record
    StartHandle: TRect; // 開始角を変更する画面座標上のハンドル。
    EndHandle: TRect;   // 終了角を変更する画面座標上のハンドル。
  end;

  TScreenLayoutRoundedCorner = (slrcNone, slrcTopLeft, slrcTopRight,
    slrcBottomRight, slrcBottomLeft);

  TScreenLayoutRoundedCornerHandle = record
    Bounds: TRect;                       // 画面座標での表示・当たり判定範囲。
    Corner: TScreenLayoutRoundedCorner; // このハンドルが調整する隅。
    Selected: Boolean;                  // 個別調整の対象として選択中ならTrue。
  end;

  TScreenLayoutBezierHandleKind =
    ScreenLayoutShapeInteraction.TScreenLayoutBezierHandleKind;
  TScreenLayoutBezierHandles =
    ScreenLayoutShapeInteraction.TScreenLayoutBezierHandles;
  TScreenLayoutVertexKindButton =
    ScreenLayoutShapeInteraction.TScreenLayoutVertexKindButton;

  TVectArtCanvasInteraction = class
  private
    FCanvasBounds: TRect;
    FDocument: TVectArtDocument;
    FEditHistory: TVectArtEditHistory;
    FDragHandle: TVectArtSelectionHandle;
    FDragLayerIndex: Integer;
    FDragIsImage: Boolean;
    FDragIsPath: Boolean;
    FDragIsShape: Boolean; // 単一Shapeの輪郭を直接変形している状態。
    FDragMode: TVectArtCanvasDragMode;
    FMoveLayerIndices: TArray<Integer>;
    FMoveStartBounds: TArray<TRectF>;
    FMoveImageLayerIndices: TArray<Integer>;
    FMoveStartImagePoints: TArray<TVectArtImagePoints>;
    FMovePathLayerIndices: TArray<Integer>;
    FMoveStartPathVertices: TArray<TArray<TScreenLayoutVertex>>;
    FMoveShapeLayerIndices: TArray<Integer>; // 複数選択中のShapeレイヤー番号。
    FMoveStartShapeContours: TArray<TArray<TScreenLayoutContour>>; // ドラッグ開始時の輪郭群。
    FDragStartBounds: TRectF;
    FArcStartAngle: Single;
    FArcStartSweep: Single;
    FDragStartImagePoints: TVectArtImagePoints;
    FDragStartPathVertices: TArray<TScreenLayoutVertex>;
    FDragStartShapeContours: TArray<TScreenLayoutContour>; // 単一Shapeの変更前輪郭。
    FPathInteraction: TScreenLayoutPathInteraction;
    FShapeInteraction: TScreenLayoutShapeInteraction;
    FDragStartMouse: TPoint;
    FAxisAlignedSelection: Boolean;
    FMoveOccurred: Boolean;
    FRotationStartMouseAngle: Single;
    FRotationStartValue: Single;
    FRoundedRadiusStartValue: TScreenLayoutCornerRadii;
    FSelectedRoundedCorner: TScreenLayoutRoundedCorner;
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
    procedure CommitArcAnglesCommand;
    procedure CommitRotationCommand;
    procedure CommitRoundedRadiusCommand;
    procedure CommitImagePointsCommand;
    procedure CommitPathVerticesCommand;
    procedure CommitShapeContoursCommand;
    function AxisAlignedResizedBounds(X, Y: Integer;
      RotationDegrees: Single): TRectF;
    function GetDragging: Boolean;
    function GetRangeSelecting: Boolean;
    function GetRangeSelectionRect: TRect;
    procedure SetEditHistory(Value: TVectArtEditHistory);
    function HitTestLayer(X, Y: Integer): Integer;
    function LayerScreenRect(Index: Integer): TRect;
    function ResizedBounds(X, Y: Integer): TRectF;
    function SelectionContainsLockedLayer: Boolean;
    function SelectedLayersFrameOffset: Integer;
    function SelectedLayerSelectionGeometry(
      out Geometry: TVectArtSelectionGeometry): Boolean;
    function SelectedLayersLogicalRect: TRectF;
    function SelectedLayersScreenRect: TRect;
    function SelectedArcAngleHandlesCore(
      out Handles: TScreenLayoutArcAngleHandles): Boolean;
    function SelectedRoundedRectangleCornerHandles:
      TArray<TScreenLayoutRoundedCornerHandle>;
    function SelectedRoundedRectangleRadiusHandle(
      out HandleRect: TRect): Boolean;
    function ToLogicalX(Value: Single): Single;
    function ToLogicalY(Value: Single): Single;
    function ToScreenX(Value: Single): Integer;
    function ToScreenY(Value: Single): Integer;
  public
    constructor Create;
    destructor Destroy; override;
    // 操作対象と論理座標変換に必要な現在のキャンバス状態を設定する。
    procedure Configure(ADocument: TVectArtDocument;
      const ACanvasBounds: TRect; AZoom: Single);
    // 現在位置で開始できる編集操作に対応したカーソルを返す。
    function CursorAt(X, Y: Integer): TCursor;
    // 修飾キーなしの押下を処理し、マウスキャプチャが必要ならTrueを返す。
    function MouseDown(Button: TMouseButton; X, Y: Integer): Boolean;
      overload;
    // 選択変更またはドラッグを開始し、マウスキャプチャが必要ならTrueを返す。
    function MouseDown(Button: TMouseButton; Shift: TShiftState;
      X, Y: Integer): Boolean; overload;
    // 進行中のドラッグをDocumentへ反映し、再描画が必要ならTrueを返す。
    function MouseMove(Shift: TShiftState; X, Y: Integer): Boolean;
    // ドラッグ結果をUndo履歴へ確定し、操作を終了した場合にTrueを返す。
    function MouseUp(Button: TMouseButton): Boolean;
    // 単一選択されたPathのアンカーを画面座標の矩形列として返す。
    function SelectedPathVertexRects: TArray<TRect>;
    // 単一選択されたShapeの全輪郭アンカーを画面座標の矩形列として返す。
    function SelectedShapeVertexRects: TArray<TRect>;
    // 選択頂点の外側へ表示する鋭角／ベジェ種別ボタンを返す。
    function SelectedShapeVertexKindButtons:
      TArray<TScreenLayoutVertexKindButton>;
    // 種別編集対象として選択されたPath／Shapeアンカーの画面座標を返す。
    function SelectedShapeVertexRect(out VertexRect: TRect): Boolean;
    // 選択中のベジェ頂点について、接線と両側の制御ハンドルを返す。
    function SelectedShapeBezierHandles(
      out Handles: TScreenLayoutBezierHandles): Boolean;
    // 単一選択中の楕円弧について、開始角と終了角の編集ハンドルを返す。
    function SelectedArcAngleHandles(
      out Handles: TScreenLayoutArcAngleHandles): Boolean;
    // 単一選択中の角丸四角について、4隅共通の半径ハンドルを返す。
    function RoundedRectangleRadiusHandle(out HandleRect: TRect): Boolean;
    // 4隅の個別半径を選択・調整するハンドルを返す。
    function RoundedRectangleCornerHandles:
      TArray<TScreenLayoutRoundedCornerHandle>;
    property Dragging: Boolean read GetDragging;
    property AxisAlignedSelection: Boolean read FAxisAlignedSelection;
    property EditHistory: TVectArtEditHistory read FEditHistory
      write SetEditHistory;
    property RangeSelecting: Boolean read GetRangeSelecting;
    property RangeSelectionRect: TRect read GetRangeSelectionRect;
  end;

implementation

uses
  System.Math, System.Skia, ScreenLayoutEllipseGeometry,
  ScreenLayoutGeometry, ScreenLayoutInteractionGeometry,
  ScreenLayoutShapeEditCommands, ScreenLayoutPathOperations,
  ScreenLayoutShapeOperations,
  ScreenLayoutShapePath;

const
  MIN_RECTANGLE_SIZE = 16.0;
  MOVE_DRAG_THRESHOLD = 6;
  ROUNDED_RADIUS_HANDLE_SIZE = 10;
  ROUNDED_RADIUS_HANDLE_MIN_OFFSET = 12;
  ROUNDED_CORNER_HANDLE_SIZE = 8;
  ROUNDED_CORNER_HANDLE_MIN_OFFSET = 22;
  ARC_ANGLE_HANDLE_SIZE = 12;

function RoundedCornerCursor(
  Corner: TScreenLayoutRoundedCorner): TCursor;
begin
  if Corner in [slrcTopRight, slrcBottomLeft] then
    Result := crSizeNESW
  else
    Result := crSizeNWSE;
end;


constructor TVectArtCanvasInteraction.Create;
begin
  inherited Create;
  FPathInteraction := TScreenLayoutPathInteraction.Create;
  FShapeInteraction := TScreenLayoutShapeInteraction.Create;
  FDragLayerIndex := -1;
  FSelectionModeLayerIndex := -1;
end;

destructor TVectArtCanvasInteraction.Destroy;
begin
  FPathInteraction.Free;
  FShapeInteraction.Free;
  inherited Destroy;
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
    FSelectedRoundedCorner := slrcNone;
    FSelectionModeLayerIndex := SelectedLayerIndex;
  end;
  FDocument := ADocument;
  FCanvasBounds := ACanvasBounds;
  FZoom := AZoom;
  FPathInteraction.Configure(ADocument, FEditHistory, ACanvasBounds, AZoom);
  FShapeInteraction.Configure(ADocument, FEditHistory, ACanvasBounds, AZoom);
end;

procedure TVectArtCanvasInteraction.SetEditHistory(Value: TVectArtEditHistory);
begin
  FEditHistory := Value;
  FPathInteraction.Configure(FDocument, Value, FCanvasBounds, FZoom);
  FShapeInteraction.Configure(FDocument, Value, FCanvasBounds, FZoom);
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

function TVectArtCanvasInteraction.SelectedArcAngleHandlesCore(
  out Handles: TScreenLayoutArcAngleHandles): Boolean;
var
  ArcLayer: TScreenLayoutArcLayer;
  Bounds: TRectF;
  EndPoint: TPointF;
  HalfSize: Integer;
  RotationDegrees: Single;
  ShapeLayer: TScreenLayoutEllipseArcShapeLayer;
  StartAngleDegrees: Single;
  StartPoint: TPointF;
  SweepAngleDegrees: Single;
begin
  Handles.StartHandle := TRect.Empty;
  Handles.EndHandle := TRect.Empty;
  Result := (FDocument <> nil) and (FZoom > 0) and
    (FDocument.SelectionCount = 1) and (FDocument.SelectedIndex > 0) and
    ((FDocument[FDocument.SelectedIndex] is TScreenLayoutArcLayer) or
     (FDocument[FDocument.SelectedIndex] is
       TScreenLayoutEllipseArcShapeLayer));
  if not Result then
    Exit;
  if FDocument[FDocument.SelectedIndex] is TScreenLayoutArcLayer then
  begin
    ArcLayer := TScreenLayoutArcLayer(FDocument[FDocument.SelectedIndex]);
    Bounds := ArcLayer.Bounds;
    RotationDegrees := ArcLayer.RotationDegrees;
    StartAngleDegrees := ArcLayer.StartAngleDegrees;
    SweepAngleDegrees := ArcLayer.SweepAngleDegrees;
  end
  else
  begin
    ShapeLayer := TScreenLayoutEllipseArcShapeLayer(
      FDocument[FDocument.SelectedIndex]);
    Bounds := ShapeLayer.Bounds;
    RotationDegrees := ShapeLayer.RotationDegrees;
    StartAngleDegrees := ShapeLayer.StartAngleDegrees;
    SweepAngleDegrees := ShapeLayer.SweepAngleDegrees;
  end;
  StartPoint := ScreenLayoutEllipsePoint(Bounds, RotationDegrees,
    StartAngleDegrees);
  EndPoint := ScreenLayoutArcEndPoint(Bounds, RotationDegrees,
    StartAngleDegrees, SweepAngleDegrees);
  HalfSize := ARC_ANGLE_HANDLE_SIZE div 2;
  Handles.StartHandle := Rect(ToScreenX(StartPoint.X) - HalfSize,
    ToScreenY(StartPoint.Y) - HalfSize,
    ToScreenX(StartPoint.X) - HalfSize + ARC_ANGLE_HANDLE_SIZE,
    ToScreenY(StartPoint.Y) - HalfSize + ARC_ANGLE_HANDLE_SIZE);
  Handles.EndHandle := Rect(ToScreenX(EndPoint.X) - HalfSize,
    ToScreenY(EndPoint.Y) - HalfSize,
    ToScreenX(EndPoint.X) - HalfSize + ARC_ANGLE_HANDLE_SIZE,
    ToScreenY(EndPoint.Y) - HalfSize + ARC_ANGLE_HANDLE_SIZE);
end;

function TVectArtCanvasInteraction.SelectedArcAngleHandles(
  out Handles: TScreenLayoutArcAngleHandles): Boolean;
begin
  Result := SelectedArcAngleHandlesCore(Handles);
end;

function TVectArtCanvasInteraction.SelectedRoundedRectangleRadiusHandle(
  out HandleRect: TRect): Boolean;
var
  Bounds: TRectF;
  Center: TPointF;
  HandlePoint: TPointF;
  HalfSize: Integer;
  Inset: Single;
  Radii: TScreenLayoutCornerRadii;
  RotationDegrees: Single;
begin
  HandleRect := TRect.Empty;
  Result := (FDocument <> nil) and (FZoom > 0) and
    (FDocument.SelectionCount = 1) and (FDocument.SelectedIndex > 0) and
    RoundedRectangleValues(FDocument[FDocument.SelectedIndex], Bounds,
      Radii, RotationDegrees);
  if not Result then
    Exit;
  Inset := ROUNDED_RADIUS_HANDLE_MIN_OFFSET / FZoom;
  Inset := Min(Inset, Bounds.Height * 0.5);
  Center := TPointF.Create((Bounds.Left + Bounds.Right) * 0.5,
    (Bounds.Top + Bounds.Bottom) * 0.5);
  HandlePoint := RotatePointAround(TPointF.Create(Center.X,
    Bounds.Top + Inset), Center, RotationDegrees);
  HalfSize := ROUNDED_RADIUS_HANDLE_SIZE div 2;
  HandleRect := Rect(ToScreenX(HandlePoint.X) - HalfSize,
    ToScreenY(HandlePoint.Y) - HalfSize,
    ToScreenX(HandlePoint.X) - HalfSize + ROUNDED_RADIUS_HANDLE_SIZE,
    ToScreenY(HandlePoint.Y) - HalfSize + ROUNDED_RADIUS_HANDLE_SIZE);
end;

function TVectArtCanvasInteraction.SelectedRoundedRectangleCornerHandles:
  TArray<TScreenLayoutRoundedCornerHandle>;
var
  Bounds: TRectF;
  Center: TPointF;
  Corner: TScreenLayoutRoundedCorner;
  DisplayRadius: Single;
  HandlePoint: TPointF;
  HalfSize: Integer;
  Radii: TScreenLayoutCornerRadii;
  Radius: Single;
  RotationDegrees: Single;
begin
  SetLength(Result, 0);
  if (FDocument = nil) or (FZoom <= 0) or
    (FDocument.SelectionCount <> 1) or (FDocument.SelectedIndex <= 0) or
    not RoundedRectangleValues(FDocument[FDocument.SelectedIndex], Bounds,
      Radii, RotationDegrees) then
    Exit;
  Center := TPointF.Create((Bounds.Left + Bounds.Right) * 0.5,
    (Bounds.Top + Bounds.Bottom) * 0.5);
  HalfSize := ROUNDED_CORNER_HANDLE_SIZE div 2;
  SetLength(Result, 4);
  for Corner := slrcTopLeft to slrcBottomLeft do
  begin
    case Corner of
      slrcTopLeft: Radius := Radii.TopLeft;
      slrcTopRight: Radius := Radii.TopRight;
      slrcBottomRight: Radius := Radii.BottomRight;
    else
      Radius := Radii.BottomLeft;
    end;
    DisplayRadius := Max(Radius,
      ROUNDED_CORNER_HANDLE_MIN_OFFSET / FZoom);
    DisplayRadius := Min(DisplayRadius,
      Min(Bounds.Width, Bounds.Height));
    case Corner of
      slrcTopLeft:
        HandlePoint := TPointF.Create(Bounds.Left + DisplayRadius,
          Bounds.Top + DisplayRadius);
      slrcTopRight:
        HandlePoint := TPointF.Create(Bounds.Right - DisplayRadius,
          Bounds.Top + DisplayRadius);
      slrcBottomRight:
        HandlePoint := TPointF.Create(Bounds.Right - DisplayRadius,
          Bounds.Bottom - DisplayRadius);
    else
      HandlePoint := TPointF.Create(Bounds.Left + DisplayRadius,
        Bounds.Bottom - DisplayRadius);
    end;
    HandlePoint := RotatePointAround(HandlePoint, Center,
      RotationDegrees);
    Result[Ord(Corner) - 1].Bounds := Rect(
      ToScreenX(HandlePoint.X) - HalfSize,
      ToScreenY(HandlePoint.Y) - HalfSize,
      ToScreenX(HandlePoint.X) - HalfSize + ROUNDED_CORNER_HANDLE_SIZE,
      ToScreenY(HandlePoint.Y) - HalfSize + ROUNDED_CORNER_HANDLE_SIZE);
    Result[Ord(Corner) - 1].Corner := Corner;
    Result[Ord(Corner) - 1].Selected :=
      Corner = FSelectedRoundedCorner;
  end;
end;

function TVectArtCanvasInteraction.CursorAt(X, Y: Integer): TCursor;
var
  ArcHandles: TScreenLayoutArcAngleHandles;
  CornerHandle: TScreenLayoutRoundedCornerHandle;
  CornerHandles: TArray<TScreenLayoutRoundedCornerHandle>;
  Geometry: TVectArtSelectionGeometry;
  Handle: TVectArtSelectionHandle;
  LayerIndex: Integer;
  SelectionRect: TRect;
  VertexCursor: TCursor;
begin
  Result := crDefault;
  if FDragMode = vcdmMove then
    Exit(crSizeAll);
  if FDragMode = vcdmResize then
    Exit(SelectionHandleCursor(FDragHandle));
  if FDragMode = vcdmRotate then
    Exit(RotationHandleCursor);
  if FDragMode = vcdmRoundedRadius then
    Exit(crSizeWE);
  if FDragMode = vcdmRoundedCornerRadius then
    Exit(RoundedCornerCursor(FSelectedRoundedCorner));
  if FDragMode in [vcdmArcStartAngle, vcdmArcEndAngle] then
    Exit(crCross);
  if FDragMode = vcdmRangeSelect then
    Exit(crCross);
  if FDragMode in [vcdmPathVertex, vcdmPathBezierHandle, vcdmShapeVertex,
    vcdmShapeBezierHandle] then
    Exit(crSizeAll);
  if FDocument = nil then
    Exit;
  if FPathInteraction.CursorAt(X, Y, VertexCursor) then
    Exit(VertexCursor);
  if FShapeInteraction.CursorAt(X, Y, VertexCursor) then
    Exit(VertexCursor);
  if SelectedArcAngleHandlesCore(ArcHandles) and
    not FDocument[FDocument.SelectedIndex].Locked and
    (PtInRect(ArcHandles.StartHandle, Point(X, Y)) or
     PtInRect(ArcHandles.EndHandle, Point(X, Y))) then
    Exit(crCross);
  if SelectedRoundedRectangleRadiusHandle(SelectionRect) and
    not FDocument[FDocument.SelectedIndex].Locked and
    PtInRect(SelectionRect, Point(X, Y)) then
    Exit(crSizeWE);
  CornerHandles := SelectedRoundedRectangleCornerHandles;
  for CornerHandle in CornerHandles do
    if not FDocument[FDocument.SelectedIndex].Locked and
      PtInRect(CornerHandle.Bounds, Point(X, Y)) then
      Exit(RoundedCornerCursor(CornerHandle.Corner));
  SelectionRect := SelectedLayersScreenRect;
  if not SelectionRect.IsEmpty and not SelectionContainsLockedLayer then
  begin
    if not SelectedLayerSelectionGeometry(Geometry) then
      Geometry := BuildSelectionGeometry(SelectionRect,
        SelectedLayersFrameOffset);
    if not FAxisAlignedSelection and (FDocument.SelectionCount = 1) and
      ((FDocument[FDocument.SelectedIndex] is TScreenLayoutRectangleLineLayer) or
       (FDocument[FDocument.SelectedIndex] is TVectArtRectangleLayer) or
       (FDocument[FDocument.SelectedIndex] is TScreenLayoutArcLayer) or
       (FDocument[FDocument.SelectedIndex] is TVectArtImageLayer) or
       (FDocument[FDocument.SelectedIndex] is TVectArtPathLayer) or
       (FDocument[FDocument.SelectedIndex] is TScreenLayoutShapeLayer)) and
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
  ArcLayer: TScreenLayoutArcLayer;
  NewValue: Single;
  RectangleLine: TScreenLayoutRectangleLineLayer;
begin
  if (FEditHistory = nil) or (FDocument = nil) or
    (FDragLayerIndex <= 0) then
    Exit;
  if FDocument[FDragLayerIndex] is TScreenLayoutRectangleLineLayer then
  begin
    RectangleLine := TScreenLayoutRectangleLineLayer(
      FDocument[FDragLayerIndex]);
    NewValue := RectangleLine.RotationDegrees;
  end
  else if FDocument[FDragLayerIndex] is TScreenLayoutArcLayer then
  begin
    ArcLayer := TScreenLayoutArcLayer(FDocument[FDragLayerIndex]);
    NewValue := ArcLayer.RotationDegrees;
  end
  else if FDocument[FDragLayerIndex] is TVectArtRectangleLayer then
    NewValue := TVectArtRectangleLayer(
      FDocument[FDragLayerIndex]).RotationDegrees
  else
    Exit;
  if not SameValue(FRotationStartValue, NewValue) then
    FEditHistory.AddApplied(TVectArtRotationCommand.Create(FDocument,
      FDragLayerIndex, FRotationStartValue, NewValue));
end;

procedure TVectArtCanvasInteraction.CommitArcAnglesCommand;
var
  ArcLayer: TScreenLayoutArcLayer;
  NewStartAngle: Single;
  NewSweepAngle: Single;
  ShapeLayer: TScreenLayoutEllipseArcShapeLayer;
begin
  if (FEditHistory = nil) or (FDocument = nil) or
    (FDragLayerIndex <= 0) or
    not ((FDocument[FDragLayerIndex] is TScreenLayoutArcLayer) or
      (FDocument[FDragLayerIndex] is TScreenLayoutEllipseArcShapeLayer)) then
    Exit;
  if FDocument[FDragLayerIndex] is TScreenLayoutArcLayer then
  begin
    ArcLayer := TScreenLayoutArcLayer(FDocument[FDragLayerIndex]);
    NewStartAngle := ArcLayer.StartAngleDegrees;
    NewSweepAngle := ArcLayer.SweepAngleDegrees;
  end
  else
  begin
    ShapeLayer := TScreenLayoutEllipseArcShapeLayer(
      FDocument[FDragLayerIndex]);
    NewStartAngle := ShapeLayer.StartAngleDegrees;
    NewSweepAngle := ShapeLayer.SweepAngleDegrees;
  end;
  if not SameValue(FArcStartAngle, NewStartAngle) or
    not SameValue(FArcStartSweep, NewSweepAngle) then
    FEditHistory.AddApplied(TScreenLayoutArcAnglesCommand.Create(FDocument,
      FDragLayerIndex, FArcStartAngle, FArcStartSweep,
      NewStartAngle, NewSweepAngle));
end;

procedure TVectArtCanvasInteraction.CommitRoundedRadiusCommand;
var
  Bounds: TRectF;
  NewValue: TScreenLayoutCornerRadii;
  RotationDegrees: Single;
begin
  if (FEditHistory = nil) or (FDocument = nil) or
    (FDragLayerIndex <= 0) or not RoundedRectangleValues(
      FDocument[FDragLayerIndex], Bounds, NewValue, RotationDegrees) then
    Exit;
  if not SameValue(FRoundedRadiusStartValue.TopLeft, NewValue.TopLeft) or
    not SameValue(FRoundedRadiusStartValue.TopRight, NewValue.TopRight) or
    not SameValue(FRoundedRadiusStartValue.BottomRight,
      NewValue.BottomRight) or
    not SameValue(FRoundedRadiusStartValue.BottomLeft,
      NewValue.BottomLeft) then
    FEditHistory.AddApplied(TScreenLayoutRoundedRectangleRadiiCommand.Create(
      FDocument, FDragLayerIndex, FRoundedRadiusStartValue, NewValue));
end;

procedure TVectArtCanvasInteraction.CommitPathVerticesCommand;
var
  PathLayer: TVectArtPathLayer;
begin
  if (FEditHistory = nil) or (FDocument = nil) or
    (FDragLayerIndex <= 0) or
    not (FDocument[FDragLayerIndex] is TVectArtPathLayer) then
    Exit;
  PathLayer := TVectArtPathLayer(FDocument[FDragLayerIndex]);
  if not ScreenLayoutPathVerticesEqual(FDragStartPathVertices,
    PathLayer.Vertices) then
    FEditHistory.AddApplied(TScreenLayoutPathVerticesCommand.Create(FDocument,
      FDragLayerIndex, FDragStartPathVertices, PathLayer.Vertices));
end;

procedure TVectArtCanvasInteraction.CommitShapeContoursCommand;
var
  ShapeLayer: TScreenLayoutShapeLayer;
begin
  if (FEditHistory = nil) or (FDocument = nil) or
    (FDragLayerIndex <= 0) or
    not (FDocument[FDragLayerIndex] is TScreenLayoutShapeLayer) then
    Exit;
  ShapeLayer := TScreenLayoutShapeLayer(FDocument[FDragLayerIndex]);
  if not ScreenLayoutShapeContoursEqual(FDragStartShapeContours,
    ShapeLayer.Contours) then
    FEditHistory.AddApplied(TScreenLayoutShapeContoursCommand.Create(
      FDocument, FDragLayerIndex, FDragStartShapeContours,
      ShapeLayer.Contours));
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
  NewPathVertices: TArray<TScreenLayoutVertex>;
  NewSelectionBounds: TRectF;
  NewShapeContours: TArray<TScreenLayoutContour>;
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
    if FDocument[FMoveLayerIndices[I]] is TScreenLayoutRectangleLineLayer then
      FDocument.SetRectangleLineBounds(FMoveLayerIndices[I], NewBounds)
    else if FDocument[FMoveLayerIndices[I]] is TScreenLayoutArcLayer then
      FDocument.SetArcBounds(FMoveLayerIndices[I], NewBounds)
    else
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
  if FDragIsPath then
  begin
    NewPathVertices := ScaleScreenLayoutPathVertices(
      FDragStartPathVertices, FDragStartBounds, NewSelectionBounds);
    FDocument.SetPathVertices(FDragLayerIndex, NewPathVertices);
  end;
  if FDragIsShape then
  begin
    NewShapeContours := ScaleScreenLayoutShapeContours(
      FDragStartShapeContours, FDragStartBounds, NewSelectionBounds);
    FDocument.SetShapeContours(FDragLayerIndex, NewShapeContours);
  end;
  for I := 0 to High(FMovePathLayerIndices) do
  begin
    NewPathVertices := ScaleScreenLayoutPathVertices(
      FMoveStartPathVertices[I], FDragStartBounds, NewSelectionBounds);
    FDocument.SetPathVertices(FMovePathLayerIndices[I], NewPathVertices);
  end;
  for I := 0 to High(FMoveShapeLayerIndices) do
  begin
    NewShapeContours := ScaleScreenLayoutShapeContours(
      FMoveStartShapeContours[I], FDragStartBounds, NewSelectionBounds);
    FDocument.SetShapeContours(FMoveShapeLayerIndices[I],
      NewShapeContours);
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
        ((FDocument[I] is TScreenLayoutRectangleLineLayer) or
         (FDocument[I] is TVectArtRectangleLayer) or
         (FDocument[I] is TScreenLayoutArcLayer) or
         (FDocument[I] is TVectArtPathLayer) or
         (FDocument[I] is TScreenLayoutShapeLayer) or
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
  PathIndex: Integer;
  ShapeIndex: Integer;
begin
  SetLength(FMoveLayerIndices, FDocument.SelectionCount);
  SetLength(FMoveStartBounds, FDocument.SelectionCount);
  SetLength(FMoveImageLayerIndices, FDocument.SelectionCount);
  SetLength(FMoveStartImagePoints, FDocument.SelectionCount);
  SetLength(FMovePathLayerIndices, FDocument.SelectionCount);
  SetLength(FMoveStartPathVertices, FDocument.SelectionCount);
  SetLength(FMoveShapeLayerIndices, FDocument.SelectionCount);
  SetLength(FMoveStartShapeContours, FDocument.SelectionCount);
  MoveIndex := 0;
  ImageIndex := 0;
  PathIndex := 0;
  ShapeIndex := 0;
  for I := 1 to FDocument.LayerCount - 1 do
    if FDocument.IsLayerSelected(I) then
    begin
      if (FDocument[I] is TScreenLayoutRectangleLineLayer) or
        (FDocument[I] is TVectArtRectangleLayer) or
        (FDocument[I] is TScreenLayoutArcLayer) then
      begin
        FMoveLayerIndices[MoveIndex] := I;
        if FDocument[I] is TScreenLayoutRectangleLineLayer then
          FMoveStartBounds[MoveIndex] :=
            TScreenLayoutRectangleLineLayer(FDocument[I]).Bounds
        else if FDocument[I] is TScreenLayoutArcLayer then
          FMoveStartBounds[MoveIndex] :=
            TScreenLayoutArcLayer(FDocument[I]).Bounds
        else
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
      end
      else if FDocument[I] is TVectArtPathLayer then
      begin
        FMovePathLayerIndices[PathIndex] := I;
        FMoveStartPathVertices[PathIndex] :=
          TVectArtPathLayer(FDocument[I]).Vertices;
        Inc(PathIndex);
      end
      else if FDocument[I] is TScreenLayoutShapeLayer then
      begin
        FMoveShapeLayerIndices[ShapeIndex] := I;
        FMoveStartShapeContours[ShapeIndex] :=
          CloneScreenLayoutShapeContours(TScreenLayoutShapeLayer(
            FDocument[I]).Contours);
        Inc(ShapeIndex);
      end;
    end;
  SetLength(FMoveLayerIndices, MoveIndex);
  SetLength(FMoveStartBounds, MoveIndex);
  SetLength(FMoveImageLayerIndices, ImageIndex);
  SetLength(FMoveStartImagePoints, ImageIndex);
  SetLength(FMovePathLayerIndices, PathIndex);
  SetLength(FMoveStartPathVertices, PathIndex);
  SetLength(FMoveShapeLayerIndices, ShapeIndex);
  SetLength(FMoveStartShapeContours, ShapeIndex);
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
  PathLayer: TVectArtPathLayer;
  ShapeLayer: TScreenLayoutShapeLayer;
begin
  if (FEditHistory = nil) or (FDocument = nil) or
    ((Length(FMoveLayerIndices) = 0) and
     (Length(FMoveImageLayerIndices) = 0) and
     (Length(FMovePathLayerIndices) = 0) and
     (Length(FMoveShapeLayerIndices) = 0)) then
    Exit;
  Command := TVectArtCompoundCommand.Create;
  SetLength(NewBounds, Length(FMoveLayerIndices));
  BoundsChanged := False;
  for I := 0 to High(FMoveLayerIndices) do
  begin
    if FDocument[FMoveLayerIndices[I]] is TScreenLayoutRectangleLineLayer then
      NewBounds[I] := TScreenLayoutRectangleLineLayer(
        FDocument[FMoveLayerIndices[I]]).Bounds
    else if FDocument[FMoveLayerIndices[I]] is TScreenLayoutArcLayer then
      NewBounds[I] := TScreenLayoutArcLayer(
        FDocument[FMoveLayerIndices[I]]).Bounds
    else
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
  for I := 0 to High(FMovePathLayerIndices) do
  begin
    PathLayer := TVectArtPathLayer(FDocument[FMovePathLayerIndices[I]]);
    if not ScreenLayoutPathVerticesEqual(FMoveStartPathVertices[I],
      PathLayer.Vertices) then
      Command.Add(TScreenLayoutPathVerticesCommand.Create(FDocument,
        FMovePathLayerIndices[I], FMoveStartPathVertices[I],
        PathLayer.Vertices));
  end;
  for I := 0 to High(FMoveShapeLayerIndices) do
  begin
    ShapeLayer := TScreenLayoutShapeLayer(
      FDocument[FMoveShapeLayerIndices[I]]);
    if not ScreenLayoutShapeContoursEqual(FMoveStartShapeContours[I],
      ShapeLayer.Contours) then
      Command.Add(TScreenLayoutShapeContoursCommand.Create(FDocument,
        FMoveShapeLayerIndices[I], FMoveStartShapeContours[I],
        ShapeLayer.Contours));
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
  FPathInteraction.EndDrag;
  FShapeInteraction.EndDrag;
  FDragIsImage := False;
  FDragIsPath := False;
  FDragIsShape := False;
  FMoveOccurred := False;
  FToggleSelectionModeOnClick := False;
  SetLength(FMoveLayerIndices, 0);
  SetLength(FMoveStartBounds, 0);
  SetLength(FMoveImageLayerIndices, 0);
  SetLength(FMoveStartImagePoints, 0);
  SetLength(FMovePathLayerIndices, 0);
  SetLength(FMoveStartPathVertices, 0);
  SetLength(FMoveShapeLayerIndices, 0);
  SetLength(FMoveStartShapeContours, 0);
  SetLength(FDragStartPathVertices, 0);
  SetLength(FDragStartShapeContours, 0);
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
  ArcLayer: TScreenLayoutArcLayer;
  I: Integer;
  J: Integer;
  Layer: TVectArtLayer;
  LogicalX: Single;
  LogicalY: Single;
  PathLayer: TVectArtPathLayer;
  PathVertices: TArray<TScreenLayoutVertex>;
  ImageLayer: TVectArtImageLayer;
  ImagePolygon: TArray<TPointF>;
  EllipseLayer: TScreenLayoutEllipseLayer;
  EllipseArcShape: TScreenLayoutEllipseArcShapeLayer;
  RectangleLine: TScreenLayoutRectangleLineLayer;
  RectangleLineCorners: TVectArtQuad;
  RectangleLayer: TVectArtRectangleLayer;
  ShapeLayer: TScreenLayoutShapeLayer;
  ShapePath: ISkPath;
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
    if Layer is TScreenLayoutShapeLayer then
    begin
      ShapeLayer := TScreenLayoutShapeLayer(Layer);
      ShapePath := BuildScreenLayoutShapePath(ShapeLayer);
      if ShapePath.Contains(LogicalX, LogicalY) then
        Exit(I);
      Continue;
    end;
    if Layer is TVectArtPathLayer then
    begin
      PathLayer := TVectArtPathLayer(Layer);
      PathVertices := PathLayer.Vertices;
      if PathLayer.Closed and
        PointInPolygon(TPointF.Create(LogicalX, LogicalY),
          FlattenScreenLayoutPathVertices(PathVertices, 24)) then
        Exit(I);
      if not PathLayer.Closed and
        (ScreenLayoutPathDistanceToPoint(PathVertices,
          TPointF.Create(LogicalX, LogicalY)) <=
          Max(PathLayer.StrokeWidth * 0.5, 6 / FZoom)) then
        Exit(I);
      Continue;
    end;
    if Layer is TScreenLayoutEllipseLayer then
    begin
      EllipseLayer := TScreenLayoutEllipseLayer(Layer);
      if PointInScreenLayoutEllipse(TPointF.Create(LogicalX, LogicalY),
        EllipseLayer.Bounds, EllipseLayer.RotationDegrees) then
        Exit(I);
      Continue;
    end;
    if Layer is TScreenLayoutEllipseArcShapeLayer then
    begin
      EllipseArcShape := TScreenLayoutEllipseArcShapeLayer(Layer);
      ShapePath := BuildScreenLayoutEllipseArcShapePath(EllipseArcShape);
      if ShapePath.Contains(LogicalX, LogicalY) then
        Exit(I);
      Continue;
    end;
    if Layer is TScreenLayoutArcLayer then
    begin
      ArcLayer := TScreenLayoutArcLayer(Layer);
      if ArcDistanceToPoint(ArcLayer, TPointF.Create(LogicalX, LogicalY)) <=
        Max(ArcLayer.StrokeWidth * 0.5, 6 / FZoom) then
        Exit(I);
      Continue;
    end;
    if Layer is TScreenLayoutRectangleLineLayer then
    begin
      RectangleLine := TScreenLayoutRectangleLineLayer(Layer);
      if (Layer is TScreenLayoutEllipseLineLayer) and
        (EllipseLineDistanceToPoint(TScreenLayoutEllipseLineLayer(Layer),
          TPointF.Create(LogicalX, LogicalY)) <=
          Max(RectangleLine.StrokeWidth * 0.5, 6 / FZoom)) then
        Exit(I);
      if Layer is TScreenLayoutEllipseLineLayer then
        Continue;
      if (Layer is TScreenLayoutRoundedRectangleLineLayer) and
        (RoundedRectangleLineDistanceToPoint(
          TScreenLayoutRoundedRectangleLineLayer(Layer),
          TPointF.Create(LogicalX, LogicalY)) <=
          Max(RectangleLine.StrokeWidth * 0.5, 6 / FZoom)) then
        Exit(I);
      if Layer is TScreenLayoutRoundedRectangleLineLayer then
        Continue;
      RectangleLineCorners := RectangleCorners(RectangleLine.Bounds,
        RectangleLine.RotationDegrees);
      for J := 0 to High(RectangleLineCorners) do
        if DistanceToSegment(TPointF.Create(LogicalX, LogicalY),
          RectangleLineCorners[J], RectangleLineCorners[(J + 1) mod 4]) <=
          Max(RectangleLine.StrokeWidth * 0.5, 6 / FZoom) then
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
  ArcLayer: TScreenLayoutArcLayer;
  Bounds: TRectF;
  ImageLayer: TVectArtImageLayer;
  PathLayer: TVectArtPathLayer;
  RectangleLine: TScreenLayoutRectangleLineLayer;
  RectangleLayer: TVectArtRectangleLayer;
  ShapeLayer: TScreenLayoutShapeLayer;
begin
  Result := TRect.Empty;
  if (FDocument = nil) or (Index <= 0) or
    (Index >= FDocument.LayerCount) or
    not ((FDocument[Index] is TScreenLayoutRectangleLineLayer) or
      (FDocument[Index] is TVectArtRectangleLayer) or
      (FDocument[Index] is TScreenLayoutArcLayer) or
      (FDocument[Index] is TVectArtPathLayer) or
      (FDocument[Index] is TScreenLayoutShapeLayer) or
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
  if FDocument[Index] is TVectArtPathLayer then
  begin
    PathLayer := TVectArtPathLayer(FDocument[Index]);
    Bounds := ScreenLayoutPathVerticesBounds(PathLayer.Vertices);
    Result := Rect(ToScreenX(Bounds.Left), ToScreenY(Bounds.Top),
      ToScreenX(Bounds.Right), ToScreenY(Bounds.Bottom));
    if Result.Width = 0 then
      Inc(Result.Right);
    if Result.Height = 0 then
      Inc(Result.Bottom);
    Exit;
  end;
  if FDocument[Index] is TScreenLayoutShapeLayer then
  begin
    ShapeLayer := TScreenLayoutShapeLayer(FDocument[Index]);
    Bounds := ScreenLayoutShapeContoursBounds(ShapeLayer.Contours);
    Result := Rect(ToScreenX(Bounds.Left), ToScreenY(Bounds.Top),
      ToScreenX(Bounds.Right), ToScreenY(Bounds.Bottom));
    if Result.Width = 0 then
      Inc(Result.Right);
    if Result.Height = 0 then
      Inc(Result.Bottom);
    Exit;
  end;
  if FDocument[Index] is TScreenLayoutRectangleLineLayer then
  begin
    RectangleLine := TScreenLayoutRectangleLineLayer(FDocument[Index]);
    Bounds := QuadBounds(RectangleCorners(RectangleLine.Bounds,
      RectangleLine.RotationDegrees));
    Result := Rect(ToScreenX(Bounds.Left), ToScreenY(Bounds.Top),
      ToScreenX(Bounds.Right), ToScreenY(Bounds.Bottom));
    Exit;
  end;
  if FDocument[Index] is TScreenLayoutArcLayer then
  begin
    ArcLayer := TScreenLayoutArcLayer(FDocument[Index]);
    Bounds := ScreenLayoutEllipseBounds(ArcLayer.Bounds,
      ArcLayer.RotationDegrees);
    Result := Rect(ToScreenX(Bounds.Left), ToScreenY(Bounds.Top),
      ToScreenX(Bounds.Right), ToScreenY(Bounds.Bottom));
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
  ArcLayer: TScreenLayoutArcLayer;
  Bounds: TRectF;
  Found: Boolean;
  I: Integer;
  ImageLayer: TVectArtImageLayer;
  PathLayer: TVectArtPathLayer;
  RectangleLine: TScreenLayoutRectangleLineLayer;
  RectangleLayer: TVectArtRectangleLayer;
  ShapeLayer: TScreenLayoutShapeLayer;
begin
  Result := TRectF.Empty;
  Found := False;
  if FDocument = nil then
    Exit;
  for I := 1 to FDocument.LayerCount - 1 do
    if FDocument.IsLayerSelected(I) and FDocument[I].Visible and
      ((FDocument[I] is TScreenLayoutRectangleLineLayer) or
       (FDocument[I] is TVectArtRectangleLayer) or
       (FDocument[I] is TScreenLayoutArcLayer) or
       (FDocument[I] is TVectArtPathLayer) or
       (FDocument[I] is TScreenLayoutShapeLayer) or
       (FDocument[I] is TVectArtImageLayer)) then
    begin
      if FDocument[I] is TScreenLayoutRectangleLineLayer then
      begin
        RectangleLine := TScreenLayoutRectangleLineLayer(FDocument[I]);
        Bounds := QuadBounds(RectangleCorners(RectangleLine.Bounds,
          RectangleLine.RotationDegrees));
      end
      else if FDocument[I] is TScreenLayoutArcLayer then
      begin
        ArcLayer := TScreenLayoutArcLayer(FDocument[I]);
        Bounds := ScreenLayoutEllipseBounds(ArcLayer.Bounds,
          ArcLayer.RotationDegrees);
      end
      else if FDocument[I] is TVectArtRectangleLayer then
      begin
        RectangleLayer := TVectArtRectangleLayer(FDocument[I]);
        Bounds := QuadBounds(RectangleCorners(RectangleLayer.Bounds,
          RectangleLayer.RotationDegrees));
      end
      else if FDocument[I] is TVectArtPathLayer then
      begin
        PathLayer := TVectArtPathLayer(FDocument[I]);
        Bounds := ScreenLayoutPathVerticesBounds(PathLayer.Vertices);
      end
      else if FDocument[I] is TScreenLayoutShapeLayer then
      begin
        ShapeLayer := TScreenLayoutShapeLayer(FDocument[I]);
        Bounds := ScreenLayoutShapeContoursBounds(ShapeLayer.Contours);
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
  ArcLayer: TScreenLayoutArcLayer;
  I: Integer;
  PathLayer: TVectArtPathLayer;
  RectangleLine: TScreenLayoutRectangleLineLayer;
  ShapeLayer: TScreenLayoutShapeLayer;
begin
  Result := SelectionFrameOffset(0, FZoom);
  if FDocument = nil then
    Exit;
  for I := 1 to FDocument.LayerCount - 1 do
    if FDocument.IsLayerSelected(I) and
      (FDocument[I] is TScreenLayoutRectangleLineLayer) then
    begin
      RectangleLine := TScreenLayoutRectangleLineLayer(FDocument[I]);
      Result := Max(Result, SelectionFrameOffset(RectangleLine.StrokeWidth,
        FZoom));
    end
    else if FDocument.IsLayerSelected(I) and
      (FDocument[I] is TScreenLayoutArcLayer) then
    begin
      ArcLayer := TScreenLayoutArcLayer(FDocument[I]);
      Result := Max(Result, SelectionFrameOffset(ArcLayer.StrokeWidth,
        FZoom));
    end
    else if FDocument.IsLayerSelected(I) and
      (FDocument[I] is TVectArtPathLayer) then
    begin
      PathLayer := TVectArtPathLayer(FDocument[I]);
      if not PathLayer.Closed then
        Result := Max(Result, SelectionFrameOffset(PathLayer.StrokeWidth,
          FZoom));
    end
    else if FDocument.IsLayerSelected(I) and
      (FDocument[I] is TScreenLayoutShapeLayer) then
    begin
      ShapeLayer := TScreenLayoutShapeLayer(FDocument[I]);
      Result := Max(Result, SelectionFrameOffset(ShapeLayer.StrokeWidth,
        FZoom));
    end;
end;

function TVectArtCanvasInteraction.SelectedLayerSelectionGeometry(
  out Geometry: TVectArtSelectionGeometry): Boolean;
var
  ArcLayer: TScreenLayoutArcLayer;
  I: Integer;
  ImageLayer: TVectArtImageLayer;
  LogicalQuad: TVectArtQuad;
  PathLayer: TVectArtPathLayer;
  PathVertices: TArray<TScreenLayoutVertex>;
  RectangleLine: TScreenLayoutRectangleLineLayer;
  RectangleLayer: TVectArtRectangleLayer;
  ScreenQuad: TVectArtScreenQuad;
begin
  if (FDocument <> nil) and (FDocument.SelectionCount = 1) and
    (FDocument.SelectedIndex > 0) and
    (FDocument[FDocument.SelectedIndex] is
      TScreenLayoutRectangleLineLayer) then
  begin
    RectangleLine := TScreenLayoutRectangleLineLayer(
      FDocument[FDocument.SelectedIndex]);
    LogicalQuad := RectangleCorners(RectangleLine.Bounds,
      RectangleLine.RotationDegrees);
    for I := 0 to High(ScreenQuad) do
      ScreenQuad[I] := Point(ToScreenX(LogicalQuad[I].X),
        ToScreenY(LogicalQuad[I].Y));
    Geometry := BuildRotatedSelectionGeometry(ScreenQuad,
      SelectionFrameOffset(RectangleLine.StrokeWidth, FZoom));
    Exit(True);
  end;
  if (FDocument <> nil) and (FDocument.SelectionCount = 1) and
    (FDocument.SelectedIndex > 0) and
    (FDocument[FDocument.SelectedIndex] is TScreenLayoutArcLayer) then
  begin
    ArcLayer := TScreenLayoutArcLayer(FDocument[FDocument.SelectedIndex]);
    LogicalQuad := RectangleCorners(ArcLayer.Bounds,
      ArcLayer.RotationDegrees);
    for I := 0 to High(ScreenQuad) do
      ScreenQuad[I] := Point(ToScreenX(LogicalQuad[I].X),
        ToScreenY(LogicalQuad[I].Y));
    Geometry := BuildRotatedSelectionGeometry(ScreenQuad,
      SelectionFrameOffset(ArcLayer.StrokeWidth, FZoom));
    Exit(True);
  end;
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
    (FDocument[FDocument.SelectedIndex] is TScreenLayoutShapeLayer) then
  begin
    Geometry := BuildPathSelectionGeometry(
      LayerScreenRect(FDocument.SelectedIndex),
      SelectedLayersFrameOffset);
    Exit(True);
  end;
  if (FDocument <> nil) and (FDocument.SelectionCount = 1) and
    (FDocument.SelectedIndex > 0) and
    (FDocument[FDocument.SelectedIndex] is TVectArtPathLayer) then
  begin
    PathLayer := TVectArtPathLayer(FDocument[FDocument.SelectedIndex]);
    PathVertices := PathLayer.Vertices;
    if not PathLayer.Closed and
      ScreenLayoutPathIsStraightLine(PathVertices) then
      Geometry := BuildLineSelectionGeometry(
        Point(ToScreenX(PathVertices[0].Position.X),
          ToScreenY(PathVertices[0].Position.Y)),
        Point(ToScreenX(PathVertices[1].Position.X),
          ToScreenY(PathVertices[1].Position.Y)))
    else
      Geometry := BuildPathSelectionGeometry(
        LayerScreenRect(FDocument.SelectedIndex),
        SelectionFrameOffset(0, FZoom));
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
    SelectionFrameOffset(0, FZoom));
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
  ArcHandles: TScreenLayoutArcAngleHandles;
  ArcLayer: TScreenLayoutArcLayer;
  ArcShapeLayer: TScreenLayoutEllipseArcShapeLayer;
  CenterX: Single;
  CenterY: Single;
  CornerHandle: TScreenLayoutRoundedCornerHandle;
  CornerHandles: TArray<TScreenLayoutRoundedCornerHandle>;
  Geometry: TVectArtSelectionGeometry;
  ImageBounds: TRectF;
  ImageLayer: TVectArtImageLayer;
  PathBounds: TRectF;
  PathLayer: TVectArtPathLayer;
  RectangleLine: TScreenLayoutRectangleLineLayer;
  RectangleLayer: TVectArtRectangleLayer;
  RadiusHandleRect: TRect;
  RoundedBounds: TRectF;
  RoundedRotation: Single;
  SelectionRect: TRect;
  ShapeBounds: TRectF;
  ShapeLayer: TScreenLayoutShapeLayer;
  WasSelected: Boolean;
begin
  Result := False;
  if (FDocument = nil) or (FZoom <= 0) then
    Exit;
  if Button = mbRight then
  begin
    if FPathInteraction.DeleteVertexAt(X, Y) then
      Exit(True);
    if FShapeInteraction.DeleteVertexAt(X, Y) then
      Exit(True);
    Exit(False);
  end;
  if Button <> mbLeft then
    Exit;
  if FPathInteraction.ApplyVertexKindAt(X, Y) or
    FShapeInteraction.ApplyVertexKindAt(X, Y) then
    Exit(False);
  if FPathInteraction.BeginBezierHandleDragAt(X, Y) then
  begin
    FDragMode := vcdmPathBezierHandle;
    FDragStartMouse := Point(X, Y);
    Exit(True);
  end;
  if FShapeInteraction.BeginBezierHandleDragAt(X, Y) then
  begin
    FDragMode := vcdmShapeBezierHandle;
    FDragStartMouse := Point(X, Y);
    Exit(True);
  end;
  if ssCtrl in Shift then
  begin
    FDragLayerIndex := HitTestLayer(X, Y);
    if FDragLayerIndex > 0 then
      FDocument.ToggleSelectedLayer(FDragLayerIndex);
    FDragLayerIndex := -1;
    // 選択だけでドラッグは開始しないため、Canvasへマウスキャプチャを要求しない。
    Exit(False);
  end;
  if not SelectionContainsLockedLayer and
    FPathInteraction.BeginVertexDragAt(X, Y) then
  begin
    FDragMode := vcdmPathVertex;
    FDragStartMouse := Point(X, Y);
    Exit(True);
  end;
  if not SelectionContainsLockedLayer and
    FShapeInteraction.BeginVertexDragAt(X, Y) then
  begin
    FDragMode := vcdmShapeVertex;
    FDragStartMouse := Point(X, Y);
    Exit(True);
  end;
  if FPathInteraction.InsertVertexAt(X, Y) or
    FShapeInteraction.InsertVertexAt(X, Y) then
    Exit(False);
  FPathInteraction.ClearSelection;
  FShapeInteraction.ClearSelection;
  if not SelectionContainsLockedLayer and
    SelectedArcAngleHandlesCore(ArcHandles) then
  begin
    if PtInRect(ArcHandles.StartHandle, Point(X, Y)) then
      FDragMode := vcdmArcStartAngle
    else if PtInRect(ArcHandles.EndHandle, Point(X, Y)) then
      FDragMode := vcdmArcEndAngle;
    if FDragMode in [vcdmArcStartAngle, vcdmArcEndAngle] then
    begin
      FDragLayerIndex := FDocument.SelectedIndex;
      if FDocument[FDragLayerIndex] is TScreenLayoutArcLayer then
      begin
        ArcLayer := TScreenLayoutArcLayer(FDocument[FDragLayerIndex]);
        FArcStartAngle := ArcLayer.StartAngleDegrees;
        FArcStartSweep := ArcLayer.SweepAngleDegrees;
      end
      else
      begin
        ArcShapeLayer := TScreenLayoutEllipseArcShapeLayer(
          FDocument[FDragLayerIndex]);
        FArcStartAngle := ArcShapeLayer.StartAngleDegrees;
        FArcStartSweep := ArcShapeLayer.SweepAngleDegrees;
      end;
      FDragStartMouse := Point(X, Y);
      Exit(True);
    end;
  end;
  if not SelectionContainsLockedLayer and
    SelectedRoundedRectangleRadiusHandle(RadiusHandleRect) and
    PtInRect(RadiusHandleRect, Point(X, Y)) then
  begin
    FSelectedRoundedCorner := slrcNone;
    FDragMode := vcdmRoundedRadius;
    FDragLayerIndex := FDocument.SelectedIndex;
    RoundedRectangleValues(FDocument[FDragLayerIndex], RoundedBounds,
      FRoundedRadiusStartValue, RoundedRotation);
    FDragStartMouse := Point(X, Y);
    Exit(True);
  end;
  CornerHandles := SelectedRoundedRectangleCornerHandles;
  for CornerHandle in CornerHandles do
    if not SelectionContainsLockedLayer and
      PtInRect(CornerHandle.Bounds, Point(X, Y)) then
    begin
      FSelectedRoundedCorner := CornerHandle.Corner;
      FDragMode := vcdmRoundedCornerRadius;
      FDragLayerIndex := FDocument.SelectedIndex;
      RoundedRectangleValues(FDocument[FDragLayerIndex], RoundedBounds,
        FRoundedRadiusStartValue, RoundedRotation);
      FDragStartMouse := Point(X, Y);
      Exit(True);
    end;
  FSelectedRoundedCorner := slrcNone;
  SelectionRect := SelectedLayersScreenRect;
  if not SelectionRect.IsEmpty and not SelectionContainsLockedLayer then
  begin
    if not SelectedLayerSelectionGeometry(Geometry) then
      Geometry := BuildSelectionGeometry(SelectionRect,
        SelectedLayersFrameOffset);
    if not FAxisAlignedSelection and (FDocument.SelectionCount = 1) and
      HitTestRotationHandle(Point(X, Y), Geometry) and
      ((FDocument[FDocument.SelectedIndex] is TScreenLayoutRectangleLineLayer) or
       (FDocument[FDocument.SelectedIndex] is TVectArtRectangleLayer) or
       (FDocument[FDocument.SelectedIndex] is TScreenLayoutArcLayer) or
       (FDocument[FDocument.SelectedIndex] is TVectArtImageLayer) or
       (FDocument[FDocument.SelectedIndex] is TVectArtPathLayer) or
       (FDocument[FDocument.SelectedIndex] is TScreenLayoutShapeLayer)) then
    begin
      FDragMode := vcdmRotate;
      FDragLayerIndex := FDocument.SelectedIndex;
      FDragIsImage := FDocument[FDragLayerIndex] is TVectArtImageLayer;
      FDragIsPath := FDocument[FDragLayerIndex] is TVectArtPathLayer;
      FDragIsShape := FDocument[FDragLayerIndex] is
        TScreenLayoutShapeLayer;
      if FDragIsImage then
      begin
        ImageLayer := TVectArtImageLayer(FDocument[FDragLayerIndex]);
        FDragStartImagePoints := ImageLayer.Points;
        ImageBounds := ImagePointsBounds(ImageLayer.Points);
        FRotationStartValue := 0;
        CenterX := ToScreenX((ImageBounds.Left + ImageBounds.Right) * 0.5);
        CenterY := ToScreenY((ImageBounds.Top + ImageBounds.Bottom) * 0.5);
      end
      else if FDragIsPath then
      begin
        PathLayer := TVectArtPathLayer(FDocument[FDragLayerIndex]);
        FDragStartPathVertices := PathLayer.Vertices;
        PathBounds := ScreenLayoutPathVerticesBounds(
          FDragStartPathVertices);
        FRotationStartValue := 0;
        CenterX := ToScreenX((PathBounds.Left + PathBounds.Right) * 0.5);
        CenterY := ToScreenY((PathBounds.Top + PathBounds.Bottom) * 0.5);
      end
      else if FDragIsShape then
      begin
        ShapeLayer := TScreenLayoutShapeLayer(FDocument[FDragLayerIndex]);
        FDragStartShapeContours := CloneScreenLayoutShapeContours(
          ShapeLayer.Contours);
        ShapeBounds := ScreenLayoutShapeContoursBounds(
          FDragStartShapeContours);
        FRotationStartValue := 0;
        CenterX := ToScreenX((ShapeBounds.Left + ShapeBounds.Right) * 0.5);
        CenterY := ToScreenY((ShapeBounds.Top + ShapeBounds.Bottom) * 0.5);
      end
      else
      begin
        if FDocument[FDragLayerIndex] is TScreenLayoutRectangleLineLayer then
        begin
          RectangleLine := TScreenLayoutRectangleLineLayer(
            FDocument[FDragLayerIndex]);
          FRotationStartValue := RectangleLine.RotationDegrees;
          CenterX := ToScreenX((RectangleLine.Bounds.Left +
            RectangleLine.Bounds.Right) * 0.5);
          CenterY := ToScreenY((RectangleLine.Bounds.Top +
            RectangleLine.Bounds.Bottom) * 0.5);
        end
        else if FDocument[FDragLayerIndex] is TScreenLayoutArcLayer then
        begin
          ArcLayer := TScreenLayoutArcLayer(FDocument[FDragLayerIndex]);
          FRotationStartValue := ArcLayer.RotationDegrees;
          CenterX := ToScreenX((ArcLayer.Bounds.Left +
            ArcLayer.Bounds.Right) * 0.5);
          CenterY := ToScreenY((ArcLayer.Bounds.Top +
            ArcLayer.Bounds.Bottom) * 0.5);
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
        FDragIsImage := (FDocument.SelectionCount = 1) and
          (FDocument[FDragLayerIndex] is TVectArtImageLayer);
        FDragIsPath := (FDocument.SelectionCount = 1) and
          (FDocument[FDragLayerIndex] is TVectArtPathLayer);
        FDragIsShape := (FDocument.SelectionCount = 1) and
          (FDocument[FDragLayerIndex] is TScreenLayoutShapeLayer);
        if FDragIsImage then
          FDragStartImagePoints := TVectArtImageLayer(
            FDocument[FDragLayerIndex]).Points
        else if FDragIsPath then
          FDragStartPathVertices := TVectArtPathLayer(
            FDocument[FDragLayerIndex]).Vertices
        else if FDragIsShape then
          FDragStartShapeContours := CloneScreenLayoutShapeContours(
            TScreenLayoutShapeLayer(
              FDocument[FDragLayerIndex]).Contours)
        else
          CaptureMoveSelection;
        if (FDocument.SelectionCount = 1) and
          (FDocument[FDragLayerIndex] is TScreenLayoutRectangleLineLayer) then
          FDragStartBounds := TScreenLayoutRectangleLineLayer(
            FDocument[FDragLayerIndex]).Bounds
        else if (FDocument.SelectionCount = 1) and
          (FDocument[FDragLayerIndex] is TScreenLayoutArcLayer) then
          FDragStartBounds := TScreenLayoutArcLayer(
            FDocument[FDragLayerIndex]).Bounds
        else if (FDocument.SelectionCount = 1) and
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
        ((FDocument[FDragLayerIndex] is TScreenLayoutRectangleLineLayer) or
         (FDocument[FDragLayerIndex] is TVectArtRectangleLayer) or
         (FDocument[FDragLayerIndex] is TScreenLayoutArcLayer));
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
      FDragIsImage := (FDocument.SelectionCount = 1) and
        (FDocument[FDragLayerIndex] is TVectArtImageLayer);
      FDragIsPath := (FDocument.SelectionCount = 1) and
        (FDocument[FDragLayerIndex] is TVectArtPathLayer);
      FDragIsShape := (FDocument.SelectionCount = 1) and
        (FDocument[FDragLayerIndex] is TScreenLayoutShapeLayer);
      if FDragIsPath then
        FDragStartPathVertices := TVectArtPathLayer(
          FDocument[FDragLayerIndex]).Vertices
      else if FDragIsImage then
        FDragStartImagePoints := TVectArtImageLayer(
          FDocument[FDragLayerIndex]).Points
      else if FDragIsShape then
        FDragStartShapeContours := CloneScreenLayoutShapeContours(
          TScreenLayoutShapeLayer(FDocument[FDragLayerIndex]).Contours)
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
  ArcLayer: TScreenLayoutArcLayer;
  ArcShapeLayer: TScreenLayoutEllipseArcShapeLayer;
  CenterX: Single;
  CenterY: Single;
  CurrentMouseAngle: Single;
  DX: Single;
  DY: Single;
  I: Integer;
  ImagePointIndex: Integer;
  NewBounds: TRectF;
  NewImagePoints: TVectArtImagePoints;
  NewPathVertices: TArray<TScreenLayoutVertex>;
  NewShapeContours: TArray<TScreenLayoutContour>;
  ImageBounds: TRectF;
  PathBounds: TRectF;
  RectangleLine: TScreenLayoutRectangleLineLayer;
  RectangleLayer: TVectArtRectangleLayer;
  LocalPoint: TPointF;
  LocalStartPoint: TPointF;
  MaximumRadius: Single;
  NewRadii: TScreenLayoutCornerRadii;
  Radius: Single;
  RoundedBounds: TRectF;
  RoundedRotation: Single;
  ShapeBounds: TRectF;
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
  if FDragMode in [vcdmPathVertex, vcdmPathBezierHandle] then
  begin
    FPathInteraction.DragTo(Shift, X, Y);
    Exit(True);
  end;
  if FDragMode in [vcdmShapeVertex, vcdmShapeBezierHandle] then
  begin
    FShapeInteraction.DragTo(Shift, X, Y);
    Exit(True);
  end;
  if FDragMode in [vcdmArcStartAngle, vcdmArcEndAngle] then
  begin
    if (FDragLayerIndex <= 0) or
      not ((FDocument[FDragLayerIndex] is TScreenLayoutArcLayer) or
        (FDocument[FDragLayerIndex] is TScreenLayoutEllipseArcShapeLayer)) then
      Exit(True);
    if FDocument[FDragLayerIndex] is TScreenLayoutArcLayer then
    begin
      ArcLayer := TScreenLayoutArcLayer(FDocument[FDragLayerIndex]);
      CurrentMouseAngle := ScreenLayoutEllipseAngleAtPoint(ArcLayer.Bounds,
        ArcLayer.RotationDegrees,
        TPointF.Create(ToLogicalX(X), ToLogicalY(Y)));
    end
    else
    begin
      ArcShapeLayer := TScreenLayoutEllipseArcShapeLayer(
        FDocument[FDragLayerIndex]);
      CurrentMouseAngle := ScreenLayoutEllipseAngleAtPoint(
        ArcShapeLayer.Bounds, ArcShapeLayer.RotationDegrees,
        TPointF.Create(ToLogicalX(X), ToLogicalY(Y)));
    end;
    if FDragMode = vcdmArcStartAngle then
      if FDocument[FDragLayerIndex] is TScreenLayoutArcLayer then
        FDocument.SetArcAngles(FDragLayerIndex, CurrentMouseAngle,
          ClockwiseAngleDelta(CurrentMouseAngle,
            FArcStartAngle + FArcStartSweep))
      else
        FDocument.SetEllipseArcShapeAngles(FDragLayerIndex,
          CurrentMouseAngle, ClockwiseAngleDelta(CurrentMouseAngle,
            FArcStartAngle + FArcStartSweep))
    else
      if FDocument[FDragLayerIndex] is TScreenLayoutArcLayer then
        FDocument.SetArcAngles(FDragLayerIndex, FArcStartAngle,
          ClockwiseAngleDelta(FArcStartAngle, CurrentMouseAngle))
      else
        FDocument.SetEllipseArcShapeAngles(FDragLayerIndex, FArcStartAngle,
          ClockwiseAngleDelta(FArcStartAngle, CurrentMouseAngle));
    Exit(True);
  end;
  if FDragMode = vcdmRoundedRadius then
  begin
    if (FDragLayerIndex <= 0) or not RoundedRectangleValues(
      FDocument[FDragLayerIndex], RoundedBounds, NewRadii,
      RoundedRotation) then
      Exit(True);
    CenterX := (RoundedBounds.Left + RoundedBounds.Right) * 0.5;
    CenterY := (RoundedBounds.Top + RoundedBounds.Bottom) * 0.5;
    LocalPoint := RotatePointAround(TPointF.Create(ToLogicalX(X),
      ToLogicalY(Y)), TPointF.Create(CenterX, CenterY),
      -RoundedRotation);
    LocalStartPoint := RotatePointAround(TPointF.Create(
      ToLogicalX(FDragStartMouse.X), ToLogicalY(FDragStartMouse.Y)),
      TPointF.Create(CenterX, CenterY), -RoundedRotation);
    Radius := EnsureRange(FRoundedRadiusStartValue.TopLeft +
      LocalPoint.X - LocalStartPoint.X, 0.0,
      Min(RoundedBounds.Width, RoundedBounds.Height) * 0.5);
    if FDocument[FDragLayerIndex] is
      TScreenLayoutRoundedRectangleLineLayer then
      FDocument.SetRoundedRectangleLineCornerRadii(FDragLayerIndex,
        UniformScreenLayoutCornerRadii(Radius))
    else
      FDocument.SetRoundedRectangleCornerRadii(FDragLayerIndex,
        UniformScreenLayoutCornerRadii(Radius));
    Exit(True);
  end;
  if FDragMode = vcdmRoundedCornerRadius then
  begin
    if (FDragLayerIndex <= 0) or not RoundedRectangleValues(
      FDocument[FDragLayerIndex], RoundedBounds, NewRadii,
      RoundedRotation) or
      (FSelectedRoundedCorner = slrcNone) then
      Exit(True);
    CenterX := (RoundedBounds.Left + RoundedBounds.Right) * 0.5;
    CenterY := (RoundedBounds.Top + RoundedBounds.Bottom) * 0.5;
    LocalPoint := RotatePointAround(TPointF.Create(ToLogicalX(X),
      ToLogicalY(Y)), TPointF.Create(CenterX, CenterY),
      -RoundedRotation);
    case FSelectedRoundedCorner of
      slrcTopLeft:
        begin
          Radius := ((LocalPoint.X - RoundedBounds.Left) +
            (LocalPoint.Y - RoundedBounds.Top)) * 0.5;
          MaximumRadius := Min(
            RoundedBounds.Width - NewRadii.TopRight,
            RoundedBounds.Height - NewRadii.BottomLeft);
          NewRadii.TopLeft := EnsureRange(Radius, 0.0,
            Max(MaximumRadius, 0.0));
        end;
      slrcTopRight:
        begin
          Radius := ((RoundedBounds.Right - LocalPoint.X) +
            (LocalPoint.Y - RoundedBounds.Top)) * 0.5;
          MaximumRadius := Min(
            RoundedBounds.Width - NewRadii.TopLeft,
            RoundedBounds.Height - NewRadii.BottomRight);
          NewRadii.TopRight := EnsureRange(Radius, 0.0,
            Max(MaximumRadius, 0.0));
        end;
      slrcBottomRight:
        begin
          Radius := ((RoundedBounds.Right - LocalPoint.X) +
            (RoundedBounds.Bottom - LocalPoint.Y)) * 0.5;
          MaximumRadius := Min(
            RoundedBounds.Width - NewRadii.BottomLeft,
            RoundedBounds.Height - NewRadii.TopRight);
          NewRadii.BottomRight := EnsureRange(Radius, 0.0,
            Max(MaximumRadius, 0.0));
        end;
      slrcBottomLeft:
        begin
          Radius := ((LocalPoint.X - RoundedBounds.Left) +
            (RoundedBounds.Bottom - LocalPoint.Y)) * 0.5;
          MaximumRadius := Min(
            RoundedBounds.Width - NewRadii.BottomRight,
            RoundedBounds.Height - NewRadii.TopLeft);
          NewRadii.BottomLeft := EnsureRange(Radius, 0.0,
            Max(MaximumRadius, 0.0));
        end;
    end;
    if FDocument[FDragLayerIndex] is
      TScreenLayoutRoundedRectangleLineLayer then
      FDocument.SetRoundedRectangleLineCornerRadii(FDragLayerIndex, NewRadii)
    else
      FDocument.SetRoundedRectangleCornerRadii(FDragLayerIndex, NewRadii);
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
      NewPathVertices := TranslateScreenLayoutPathVertices(
        FDragStartPathVertices, DX, DY);
      FDocument.SetPathVertices(FDragLayerIndex, NewPathVertices);
      Exit(True);
    end;
    if FDragIsShape then
    begin
      NewShapeContours := TranslateScreenLayoutShapeContours(
        FDragStartShapeContours, DX, DY);
      FDocument.SetShapeContours(FDragLayerIndex, NewShapeContours);
      Exit(True);
    end;
    for I := 0 to High(FMoveLayerIndices) do
    begin
      NewBounds := FMoveStartBounds[I];
      NewBounds.Offset(DX, DY);
      if FDocument[FMoveLayerIndices[I]] is TScreenLayoutRectangleLineLayer then
        FDocument.SetRectangleLineBounds(FMoveLayerIndices[I], NewBounds)
      else if FDocument[FMoveLayerIndices[I]] is TScreenLayoutArcLayer then
        FDocument.SetArcBounds(FMoveLayerIndices[I], NewBounds)
      else
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
    for I := 0 to High(FMovePathLayerIndices) do
    begin
      NewPathVertices := TranslateScreenLayoutPathVertices(
        FMoveStartPathVertices[I], DX, DY);
      FDocument.SetPathVertices(FMovePathLayerIndices[I], NewPathVertices);
    end;
    for I := 0 to High(FMoveShapeLayerIndices) do
    begin
      NewShapeContours := TranslateScreenLayoutShapeContours(
        FMoveStartShapeContours[I], DX, DY);
      FDocument.SetShapeContours(FMoveShapeLayerIndices[I],
        NewShapeContours);
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
    if FDragIsPath and
      (FDocument[FDragLayerIndex] is TVectArtPathLayer) then
    begin
      PathBounds := ScreenLayoutPathVerticesBounds(FDragStartPathVertices);
      CenterX := ToScreenX((PathBounds.Left + PathBounds.Right) * 0.5);
      CenterY := ToScreenY((PathBounds.Top + PathBounds.Bottom) * 0.5);
      CurrentMouseAngle := RadToDeg(ArcTan2(Y - CenterY, X - CenterX));
      NewPathVertices := RotateScreenLayoutPathVertices(
        FDragStartPathVertices,
        TPointF.Create((PathBounds.Left + PathBounds.Right) * 0.5,
          (PathBounds.Top + PathBounds.Bottom) * 0.5),
        CurrentMouseAngle - FRotationStartMouseAngle);
      FDocument.SetPathVertices(FDragLayerIndex, NewPathVertices);
      Exit(True);
    end;
    if FDragIsShape and
      (FDocument[FDragLayerIndex] is TScreenLayoutShapeLayer) then
    begin
      ShapeBounds := ScreenLayoutShapeContoursBounds(
        FDragStartShapeContours);
      CenterX := ToScreenX((ShapeBounds.Left + ShapeBounds.Right) * 0.5);
      CenterY := ToScreenY((ShapeBounds.Top + ShapeBounds.Bottom) * 0.5);
      CurrentMouseAngle := RadToDeg(ArcTan2(Y - CenterY, X - CenterX));
      NewShapeContours := RotateScreenLayoutShapeContours(
        FDragStartShapeContours,
        TPointF.Create((ShapeBounds.Left + ShapeBounds.Right) * 0.5,
          (ShapeBounds.Top + ShapeBounds.Bottom) * 0.5),
        CurrentMouseAngle - FRotationStartMouseAngle);
      FDocument.SetShapeContours(FDragLayerIndex, NewShapeContours);
      Exit(True);
    end;
    if FDocument[FDragLayerIndex] is TScreenLayoutRectangleLineLayer then
    begin
      RectangleLine := TScreenLayoutRectangleLineLayer(
        FDocument[FDragLayerIndex]);
      CenterX := ToScreenX((RectangleLine.Bounds.Left +
        RectangleLine.Bounds.Right) * 0.5);
      CenterY := ToScreenY((RectangleLine.Bounds.Top +
        RectangleLine.Bounds.Bottom) * 0.5);
      CurrentMouseAngle := RadToDeg(ArcTan2(Y - CenterY, X - CenterX));
      FDocument.SetRectangleLineRotation(FDragLayerIndex,
        FRotationStartValue + CurrentMouseAngle - FRotationStartMouseAngle);
      Exit(True);
    end;
    if FDocument[FDragLayerIndex] is TScreenLayoutArcLayer then
    begin
      ArcLayer := TScreenLayoutArcLayer(FDocument[FDragLayerIndex]);
      CenterX := ToScreenX((ArcLayer.Bounds.Left +
        ArcLayer.Bounds.Right) * 0.5);
      CenterY := ToScreenY((ArcLayer.Bounds.Top +
        ArcLayer.Bounds.Bottom) * 0.5);
      CurrentMouseAngle := RadToDeg(ArcTan2(Y - CenterY, X - CenterX));
      FDocument.SetArcRotation(FDragLayerIndex,
        FRotationStartValue + CurrentMouseAngle - FRotationStartMouseAngle);
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
    if FDragMode in [vcdmPathVertex, vcdmPathBezierHandle] then
      FPathInteraction.CommitDrag
    else if FDragMode in [vcdmShapeVertex, vcdmShapeBezierHandle] then
      FShapeInteraction.CommitDrag
    else if FDragMode in [vcdmMove, vcdmResize] then
      if FDragIsImage then
        CommitImagePointsCommand
      else if FDragIsPath then
        CommitPathVerticesCommand
      else if FDragIsShape then
        CommitShapeContoursCommand
      else
        CommitBoundsCommand;
    if FDragMode = vcdmRotate then
      if FDragIsImage then
        CommitImagePointsCommand
      else if FDragIsPath then
        CommitPathVerticesCommand
      else if FDragIsShape then
        CommitShapeContoursCommand
      else
        CommitRotationCommand;
    if FDragMode in [vcdmRoundedRadius, vcdmRoundedCornerRadius] then
      CommitRoundedRadiusCommand;
    if FDragMode in [vcdmArcStartAngle, vcdmArcEndAngle] then
      CommitArcAnglesCommand;
    if FToggleSelectionModeOnClick and not FMoveOccurred then
      FAxisAlignedSelection := not FAxisAlignedSelection;
    EndDrag;
  end;
end;

function TVectArtCanvasInteraction.SelectedPathVertexRects: TArray<TRect>;
begin
  Result := FPathInteraction.SelectedVertexRects;
end;

function TVectArtCanvasInteraction.SelectedShapeVertexRects: TArray<TRect>;
begin
  Result := FShapeInteraction.SelectedVertexRects;
end;

function TVectArtCanvasInteraction.SelectedShapeVertexKindButtons:
  TArray<TScreenLayoutVertexKindButton>;
begin
  Result := FPathInteraction.SelectedVertexKindButtons;
  if Length(Result) = 0 then
    Result := FShapeInteraction.SelectedVertexKindButtons;
end;

function TVectArtCanvasInteraction.SelectedShapeVertexRect(
  out VertexRect: TRect): Boolean;
begin
  Result := FPathInteraction.SelectedVertexRect(VertexRect);
  if not Result then
    Result := FShapeInteraction.SelectedVertexRect(VertexRect);
end;

function TVectArtCanvasInteraction.SelectedShapeBezierHandles(
  out Handles: TScreenLayoutBezierHandles): Boolean;
begin
  Result := FPathInteraction.SelectedBezierHandles(Handles);
  if not Result then
    Result := FShapeInteraction.SelectedBezierHandles(Handles);
end;

function TVectArtCanvasInteraction.RoundedRectangleRadiusHandle(
  out HandleRect: TRect): Boolean;
begin
  Result := SelectedRoundedRectangleRadiusHandle(HandleRect);
end;

function TVectArtCanvasInteraction.RoundedRectangleCornerHandles:
  TArray<TScreenLayoutRoundedCornerHandle>;
begin
  Result := SelectedRoundedRectangleCornerHandles;
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
  ArcLayer: TScreenLayoutArcLayer;
  Center: TPointF;
  CurrentLogical: TPointF;
  DX: Single;
  DY: Single;
  LocalCurrent: TPointF;
  LocalStart: TPointF;
  NewAnchor: TPointF;
  NewCenter: TPointF;
  RectangleLine: TScreenLayoutRectangleLineLayer;
  RectangleLayer: TVectArtRectangleLayer;
  RotationDegrees: Single;
  StartAnchor: TPointF;
  StartLogical: TPointF;
begin
  Result := FDragStartBounds;
  RotationDegrees := 0.0;
  if (FDocument <> nil) and (FDocument.SelectionCount = 1) and
    (FDragLayerIndex > 0) and
    (FDocument[FDragLayerIndex] is TScreenLayoutRectangleLineLayer) then
  begin
    RectangleLine := TScreenLayoutRectangleLineLayer(
      FDocument[FDragLayerIndex]);
    RotationDegrees := RectangleLine.RotationDegrees;
  end
  else if (FDocument <> nil) and (FDocument.SelectionCount = 1) and
    (FDragLayerIndex > 0) and
    (FDocument[FDragLayerIndex] is TScreenLayoutArcLayer) then
  begin
    ArcLayer := TScreenLayoutArcLayer(FDocument[FDragLayerIndex]);
    RotationDegrees := ArcLayer.RotationDegrees;
  end
  else if (FDocument <> nil) and (FDocument.SelectionCount = 1) and
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
