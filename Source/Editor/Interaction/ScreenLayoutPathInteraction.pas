// 単一Pathの頂点選択、区間分割、ベジェハンドル操作と表示用幾何を管理する。
unit ScreenLayoutPathInteraction;

interface

uses
  System.Classes, System.Types, Vcl.Controls, ScreenLayoutDocument,
  ScreenLayoutEditHistory, ScreenLayoutShapeInteraction;

type
  TScreenLayoutPathInteraction = class
  private
    FCanvasBounds: TRect;
    FDocument: TVectArtDocument;
    FDragBezierHandle: TScreenLayoutBezierHandleKind;
    FDragLayerIndex: Integer;
    FDragStartVertices: TArray<TScreenLayoutVertex>;
    FDragVertexIndex: Integer;
    FEditHistory: TVectArtEditHistory;
    FSelectedLayerIndex: Integer;
    FSelectedVertexIndex: Integer;
    FZoom: Single;
    procedure ApplySelectedVertexKind(Kind: TScreenLayoutVertexKind);
    function HitTestBezierHandle(X, Y: Integer;
      out HandleKind: TScreenLayoutBezierHandleKind): Boolean;
    function HitTestSegment(X, Y: Integer; out SegmentIndex: Integer;
      out Parameter: Single): Boolean;
    function HitTestVertex(X, Y: Integer; out VertexIndex: Integer): Boolean;
    function HitTestVertexKindButton(X, Y: Integer;
      out Kind: TScreenLayoutVertexKind): Boolean;
    function SelectedPathLayer(out PathLayer: TVectArtLayer): Boolean;
    function ToLogicalX(Value: Single): Single;
    function ToLogicalY(Value: Single): Single;
    function ToScreenX(Value: Single): Integer;
    function ToScreenY(Value: Single): Integer;
  public
    // 選択を持たない入力管理オブジェクトを生成する。
    constructor Create;
    // 操作対象、履歴、表示座標変換に必要な現在のキャンバス状態を設定する。
    procedure Configure(ADocument: TVectArtDocument;
      AEditHistory: TVectArtEditHistory; const ACanvasBounds: TRect;
      AZoom: Single);
    // 選択頂点と進行中の頂点ドラッグを破棄する。
    procedure ClearSelection;
    // 頂点ドラッグの前後差分を1件のUndo履歴として確定する。
    procedure CommitDrag;
    // 履歴を追加せず、進行中のドラッグ状態だけを終了する。
    procedure EndDrag;
    // 指定位置の頂点を削除し、成功時はUndo履歴へ記録する。
    function DeleteVertexAt(X, Y: Integer): Boolean;
    // 指定位置の頂点種別ボタンを適用し、成功時はUndo履歴へ記録する。
    function ApplyVertexKindAt(X, Y: Integer): Boolean;
    // 指定位置のベジェ制御点を捕捉し、ドラッグを開始できた場合にTrueを返す。
    function BeginBezierHandleDragAt(X, Y: Integer): Boolean;
    // 指定位置のアンカーを選択し、ドラッグを開始できた場合にTrueを返す。
    function BeginVertexDragAt(X, Y: Integer): Boolean;
    // 指定位置に最も近い区間を分割し、成功時はUndo履歴へ記録する。
    function InsertVertexAt(X, Y: Integer): Boolean;
    // Path編集要素に対応するカーソルがあればCursorへ設定してTrueを返す。
    function CursorAt(X, Y: Integer; out Cursor: TCursor): Boolean;
    // 進行中のアンカーまたは制御点ドラッグをDocumentへ反映する。
    function DragTo(Shift: TShiftState; X, Y: Integer): Boolean;
    // 選択中Pathの全アンカーを画面座標の矩形列として返す。
    function SelectedVertexRects: TArray<TRect>;
    // 選択中Pathを直線・ベジェ共通の画面座標点列へ展開して返す。
    function SelectedPathPoints: TArray<TPoint>;
    // 選択アンカーの外側へ表示する鋭角／ベジェ種別ボタンを返す。
    function SelectedVertexKindButtons:
      TArray<TScreenLayoutVertexKindButton>;
    // 選択アンカーの現在の鋭角／ベジェ種別を返す。
    function SelectedVertexKind(out Kind: TScreenLayoutVertexKind): Boolean;
    // 選択アンカーへ鋭角／ベジェ種別を適用し、対象があればTrueを返す。
    function SetSelectedVertexKind(
      Kind: TScreenLayoutVertexKind): Boolean;
    // 現在選択しているアンカーの画面範囲を返す。
    function SelectedVertexRect(out VertexRect: TRect): Boolean;
    // 選択中のベジェ頂点について、接線と両側の制御ハンドルを返す。
    function SelectedBezierHandles(
      out Handles: TScreenLayoutBezierHandles): Boolean;
  end;

implementation

uses
  System.Math, ScreenLayoutGeometry, ScreenLayoutShapeEditCommands,
  ScreenLayoutPathOperations;

const
  VERTEX_HANDLE_SIZE           = 9;
  BEZIER_VERTEX_HIT_PADDING    = 6;
  BEZIER_CONTROL_HANDLE_SIZE   = 9;
  VERTEX_KIND_BUTTON_GAP       = 4;
  VERTEX_KIND_BUTTON_OFFSET    = 34;
  VERTEX_KIND_BUTTON_SIZE      = 22;
  SEGMENT_HIT_DISTANCE         = 6.0;
  BEZIER_HIT_SUBDIVISIONS      = 32;

function DistanceToSegmentParameter(const PointValue, StartPoint,
  EndPoint: TPointF; out Parameter: Single): Single;
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
  Parameter := Projection;
end;

function CubicBezierPoint(const StartPoint, Control1, Control2,
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

constructor TScreenLayoutPathInteraction.Create;
begin
  inherited Create;
  FSelectedLayerIndex := -1;
  ClearSelection;
  EndDrag;
end;

procedure TScreenLayoutPathInteraction.Configure(
  ADocument: TVectArtDocument; AEditHistory: TVectArtEditHistory;
  const ACanvasBounds: TRect; AZoom: Single);
var
  SelectedLayerIndex: Integer;
begin
  SelectedLayerIndex := -1;
  if (ADocument <> nil) and (ADocument.SelectionCount = 1) then
    SelectedLayerIndex := ADocument.SelectedIndex;
  if (ADocument <> FDocument) or
    (SelectedLayerIndex <> FSelectedLayerIndex) then
    ClearSelection;
  FDocument := ADocument;
  FEditHistory := AEditHistory;
  FCanvasBounds := ACanvasBounds;
  FZoom := AZoom;
  FSelectedLayerIndex := SelectedLayerIndex;
end;

procedure TScreenLayoutPathInteraction.ClearSelection;
begin
  FSelectedVertexIndex := -1;
end;

function TScreenLayoutPathInteraction.SelectedPathLayer(
  out PathLayer: TVectArtLayer): Boolean;
begin
  PathLayer := nil;
  Result := (FDocument <> nil) and (FDocument.SelectionCount = 1) and
    (FDocument.SelectedIndex > 0) and
    FDocument[FDocument.SelectedIndex].SupportsPathEditing;
  if Result then
  begin
    PathLayer := FDocument[FDocument.SelectedIndex];
    Result := not PathLayer.Locked;
  end;
end;

function TScreenLayoutPathInteraction.ToLogicalX(Value: Single): Single;
begin
  Result := ScreenToLogicalX(Value, FCanvasBounds, FZoom,
    FDocument.CanvasLayer.Width);
end;

function TScreenLayoutPathInteraction.ToLogicalY(Value: Single): Single;
begin
  Result := ScreenToLogicalY(Value, FCanvasBounds, FZoom,
    FDocument.CanvasLayer.Height);
end;

function TScreenLayoutPathInteraction.ToScreenX(Value: Single): Integer;
begin
  Result := LogicalToScreenX(Value, FCanvasBounds, FZoom,
    FDocument.CanvasLayer.Width);
end;

function TScreenLayoutPathInteraction.ToScreenY(Value: Single): Integer;
begin
  Result := LogicalToScreenY(Value, FCanvasBounds, FZoom,
    FDocument.CanvasLayer.Height);
end;

function TScreenLayoutPathInteraction.HitTestVertex(X, Y: Integer;
  out VertexIndex: Integer): Boolean;
var
  CandidateDistance: Single;
  CenterX: Integer;
  CenterY: Integer;
  HalfSize: Integer;
  HandleRect: TRect;
  I: Integer;
  NearestDistance: Single;
  PathLayer: TVectArtLayer;
  Vertices: TArray<TScreenLayoutVertex>;
begin
  Result := False;
  VertexIndex := -1;
  if not SelectedPathLayer(PathLayer) then
    Exit;
  Vertices := PathLayer.EditablePathVertices;
  HalfSize := VERTEX_HANDLE_SIZE div 2;
  NearestDistance := MaxSingle;
  for I := 0 to High(Vertices) do
  begin
    CenterX := ToScreenX(Vertices[I].Position.X);
    CenterY := ToScreenY(Vertices[I].Position.Y);
    HandleRect := Rect(CenterX - HalfSize, CenterY - HalfSize,
      CenterX - HalfSize + VERTEX_HANDLE_SIZE,
      CenterY - HalfSize + VERTEX_HANDLE_SIZE);
    if Vertices[I].Kind = slvkBezier then
      InflateRect(HandleRect, BEZIER_VERTEX_HIT_PADDING,
        BEZIER_VERTEX_HIT_PADDING);
    if PtInRect(HandleRect, Point(X, Y)) then
    begin
      CandidateDistance := Sqr(X - CenterX) + Sqr(Y - CenterY);
      if CandidateDistance < NearestDistance then
      begin
        NearestDistance := CandidateDistance;
        VertexIndex := I;
        Result := True;
      end;
    end;
  end;
end;

function TScreenLayoutPathInteraction.HitTestVertexKindButton(X,
  Y: Integer; out Kind: TScreenLayoutVertexKind): Boolean;
var
  ButtonInfo: TScreenLayoutVertexKindButton;
begin
  Result := False;
  Kind := slvkSharp;
  for ButtonInfo in SelectedVertexKindButtons do
    if PtInRect(ButtonInfo.Bounds, Point(X, Y)) then
    begin
      Kind := ButtonInfo.Kind;
      Exit(True);
    end;
end;

function TScreenLayoutPathInteraction.HitTestBezierHandle(X, Y: Integer;
  out HandleKind: TScreenLayoutBezierHandleKind): Boolean;
var
  Handles: TScreenLayoutBezierHandles;
  VertexRect: TRect;
begin
  Result := False;
  HandleKind := slbhNone;
  if not SelectedBezierHandles(Handles) then
    Exit;
  HandleKind := ScreenLayoutBezierHandleAt(Handles, Point(X, Y));
  if (HandleKind <> slbhNone) and
    (((HandleKind = slbhIncoming) and
      not PtInRect(Handles.IncomingRect, Point(X, Y))) or
     ((HandleKind = slbhOutgoing) and
      not PtInRect(Handles.OutgoingRect, Point(X, Y)))) and
    SelectedVertexRect(VertexRect) and PtInRect(VertexRect, Point(X, Y)) then
    HandleKind := slbhNone;
  Result := HandleKind <> slbhNone;
end;

function TScreenLayoutPathInteraction.HitTestSegment(X, Y: Integer;
  out SegmentIndex: Integer; out Parameter: Single): Boolean;
var
  BestDistance: Single;
  Control1: TPointF;
  Control2: TPointF;
  CurrentDistance: Single;
  CurrentParameter: Single;
  EndParameter: Single;
  EndPoint: TPointF;
  I: Integer;
  LocalParameter: Single;
  MousePoint: TPointF;
  PathLayer: TVectArtLayer;
  StartParameter: Single;
  StartPoint: TPointF;
  SubdivisionEnd: TPointF;
  SubdivisionIndex: Integer;
  SubdivisionStart: TPointF;
  Vertices: TArray<TScreenLayoutVertex>;
begin
  Result := False;
  SegmentIndex := -1;
  Parameter := 0;
  if not SelectedPathLayer(PathLayer) then
    Exit;
  Vertices := PathLayer.EditablePathVertices;
  MousePoint := TPointF.Create(X, Y);
  BestDistance := 1.0E30;
  for I := 0 to High(Vertices) - 1 do
  begin
    StartPoint := TPointF.Create(ToScreenX(Vertices[I].Position.X),
      ToScreenY(Vertices[I].Position.Y));
    EndPoint := TPointF.Create(ToScreenX(Vertices[I + 1].Position.X),
      ToScreenY(Vertices[I + 1].Position.Y));
    if Vertices[I].OutgoingSegment = slskLine then
    begin
      CurrentDistance := DistanceToSegmentParameter(MousePoint,
        StartPoint, EndPoint, CurrentParameter);
      if CurrentDistance < BestDistance then
      begin
        BestDistance := CurrentDistance;
        SegmentIndex := I;
        Parameter := CurrentParameter;
      end;
      Continue;
    end;
    Control1 := TPointF.Create(ToScreenX(Vertices[I].Position.X +
      Vertices[I].OutgoingControl.X), ToScreenY(Vertices[I].Position.Y +
      Vertices[I].OutgoingControl.Y));
    Control2 := TPointF.Create(ToScreenX(Vertices[I + 1].Position.X +
      Vertices[I + 1].IncomingControl.X),
      ToScreenY(Vertices[I + 1].Position.Y +
      Vertices[I + 1].IncomingControl.Y));
    for SubdivisionIndex := 0 to BEZIER_HIT_SUBDIVISIONS - 1 do
    begin
      StartParameter := SubdivisionIndex / BEZIER_HIT_SUBDIVISIONS;
      EndParameter := (SubdivisionIndex + 1) / BEZIER_HIT_SUBDIVISIONS;
      SubdivisionStart := CubicBezierPoint(StartPoint, Control1, Control2,
        EndPoint, StartParameter);
      SubdivisionEnd := CubicBezierPoint(StartPoint, Control1, Control2,
        EndPoint, EndParameter);
      CurrentDistance := DistanceToSegmentParameter(MousePoint,
        SubdivisionStart, SubdivisionEnd, LocalParameter);
      if CurrentDistance < BestDistance then
      begin
        BestDistance := CurrentDistance;
        SegmentIndex := I;
        Parameter := (SubdivisionIndex + LocalParameter) /
          BEZIER_HIT_SUBDIVISIONS;
      end;
    end;
  end;
  Result := BestDistance <= SEGMENT_HIT_DISTANCE;
  if not Result then
  begin
    SegmentIndex := -1;
    Parameter := 0;
  end;
end;

procedure TScreenLayoutPathInteraction.ApplySelectedVertexKind(
  Kind: TScreenLayoutVertexKind);
var
  NewVertices: TArray<TScreenLayoutVertex>;
  OldVertices: TArray<TScreenLayoutVertex>;
  PathLayer: TVectArtLayer;
begin
  if not SelectedPathLayer(PathLayer) or (FSelectedVertexIndex < 0) then
    Exit;
  OldVertices := PathLayer.EditablePathVertices;
  if (FSelectedVertexIndex > High(OldVertices)) or
    (OldVertices[FSelectedVertexIndex].Kind = Kind) then
    Exit;
  NewVertices := CloneScreenLayoutPathVertices(OldVertices);
  SetScreenLayoutPathVertexKind(NewVertices, FSelectedVertexIndex, Kind);
  ApplyScreenLayoutPathVertices(FDocument, FDocument.SelectedIndex,
    NewVertices, True);
  if FEditHistory <> nil then
    FEditHistory.AddApplied(TScreenLayoutPathVerticesCommand.Create(
      FDocument, FDocument.SelectedIndex, OldVertices, NewVertices, True));
end;

function TScreenLayoutPathInteraction.ApplyVertexKindAt(X,
  Y: Integer): Boolean;
var
  Kind: TScreenLayoutVertexKind;
begin
  Result := HitTestVertexKindButton(X, Y, Kind);
  if Result then
    ApplySelectedVertexKind(Kind);
end;

function TScreenLayoutPathInteraction.InsertVertexAt(X,
  Y: Integer): Boolean;
var
  NewVertexIndex: Integer;
  NewVertices: TArray<TScreenLayoutVertex>;
  OldVertices: TArray<TScreenLayoutVertex>;
  Parameter: Single;
  PathLayer: TVectArtLayer;
  SegmentIndex: Integer;
begin
  Result := HitTestSegment(X, Y, SegmentIndex, Parameter);
  if not Result or not SelectedPathLayer(PathLayer) then
    Exit;
  OldVertices := PathLayer.EditablePathVertices;
  NewVertices := CloneScreenLayoutPathVertices(OldVertices);
  NewVertexIndex := InsertScreenLayoutPathVertex(NewVertices, SegmentIndex,
    Parameter);
  if NewVertexIndex < 0 then
    Exit(False);
  ApplyScreenLayoutPathVertices(FDocument, FDocument.SelectedIndex,
    NewVertices, True);
  FSelectedVertexIndex := NewVertexIndex;
  if FEditHistory <> nil then
    FEditHistory.AddApplied(TScreenLayoutPathVerticesCommand.Create(
      FDocument, FDocument.SelectedIndex, OldVertices, NewVertices, True));
end;

function TScreenLayoutPathInteraction.DeleteVertexAt(X,
  Y: Integer): Boolean;
var
  NewVertices: TArray<TScreenLayoutVertex>;
  OldVertices: TArray<TScreenLayoutVertex>;
  PathLayer: TVectArtLayer;
  VertexIndex: Integer;
begin
  Result := HitTestVertex(X, Y, VertexIndex);
  if not Result or not SelectedPathLayer(PathLayer) then
    Exit;
  OldVertices := PathLayer.EditablePathVertices;
  NewVertices := CloneScreenLayoutPathVertices(OldVertices);
  if not DeleteScreenLayoutPathVertex(NewVertices, VertexIndex) then
    Exit;
  ApplyScreenLayoutPathVertices(FDocument, FDocument.SelectedIndex,
    NewVertices, True);
  ClearSelection;
  if FEditHistory <> nil then
    FEditHistory.AddApplied(TScreenLayoutPathVerticesCommand.Create(
      FDocument, FDocument.SelectedIndex, OldVertices, NewVertices, True));
end;

function TScreenLayoutPathInteraction.BeginBezierHandleDragAt(X,
  Y: Integer): Boolean;
var
  HandleKind: TScreenLayoutBezierHandleKind;
  PathLayer: TVectArtLayer;
begin
  Result := HitTestBezierHandle(X, Y, HandleKind) and
    SelectedPathLayer(PathLayer);
  if not Result then
    Exit;
  FDragBezierHandle := HandleKind;
  FDragVertexIndex := FSelectedVertexIndex;
  FDragLayerIndex := FDocument.SelectedIndex;
  FDragStartVertices := PathLayer.EditablePathVertices;
end;

function TScreenLayoutPathInteraction.BeginVertexDragAt(X,
  Y: Integer): Boolean;
var
  PathLayer: TVectArtLayer;
begin
  Result := HitTestVertex(X, Y, FDragVertexIndex) and
    SelectedPathLayer(PathLayer);
  if not Result then
    Exit;
  FSelectedVertexIndex := FDragVertexIndex;
  FDragLayerIndex := FDocument.SelectedIndex;
  FDragStartVertices := PathLayer.EditablePathVertices;
  FDragBezierHandle := slbhNone;
end;

function TScreenLayoutPathInteraction.DragTo(Shift: TShiftState;
  X, Y: Integer): Boolean;
var
  Angle: Single;
  ControlLength: Single;
  ControlVector: TPointF;
  NewVertices: TArray<TScreenLayoutVertex>;
  OppositeLength: Single;
begin
  Result := (FDragLayerIndex > 0) and
    FDocument[FDragLayerIndex].SupportsPathEditing;
  if not Result then
    Exit;
  NewVertices := CloneScreenLayoutPathVertices(FDragStartVertices);
  if (FDragVertexIndex < 0) or
    (FDragVertexIndex > High(NewVertices)) then
    Exit;
  if FDragBezierHandle = slbhNone then
  begin
    NewVertices[FDragVertexIndex].Position := TPointF.Create(
      EnsureRange(ToLogicalX(X), FDocument.CanvasLayer.Width * -0.5,
        FDocument.CanvasLayer.Width * 0.5),
      EnsureRange(ToLogicalY(Y), FDocument.CanvasLayer.Height * -0.5,
        FDocument.CanvasLayer.Height * 0.5));
    ApplyScreenLayoutPathVertices(FDocument, FDragLayerIndex,
      NewVertices, True);
    Exit;
  end;
  with NewVertices[FDragVertexIndex] do
    ControlVector := TPointF.Create(ToLogicalX(X) - Position.X,
      ToLogicalY(Y) - Position.Y);
  ControlLength := Hypot(ControlVector.X, ControlVector.Y);
  if (ssShift in Shift) and (ControlLength > 0.001) then
  begin
    Angle := ArcTan2(ControlVector.Y, ControlVector.X);
    Angle := Round(Angle / (Pi / 12)) * (Pi / 12);
    ControlVector := TPointF.Create(Cos(Angle) * ControlLength,
      Sin(Angle) * ControlLength);
  end;
  if FDragBezierHandle = slbhIncoming then
  begin
    OppositeLength := Hypot(FDragStartVertices[
      FDragVertexIndex].OutgoingControl.X, FDragStartVertices[
      FDragVertexIndex].OutgoingControl.Y);
    NewVertices[FDragVertexIndex].IncomingControl := ControlVector;
    if ControlLength > 0.001 then
      NewVertices[FDragVertexIndex].OutgoingControl := TPointF.Create(
        -ControlVector.X / ControlLength * OppositeLength,
        -ControlVector.Y / ControlLength * OppositeLength);
  end
  else
  begin
    OppositeLength := Hypot(FDragStartVertices[
      FDragVertexIndex].IncomingControl.X, FDragStartVertices[
      FDragVertexIndex].IncomingControl.Y);
    NewVertices[FDragVertexIndex].OutgoingControl := ControlVector;
    if ControlLength > 0.001 then
      NewVertices[FDragVertexIndex].IncomingControl := TPointF.Create(
        -ControlVector.X / ControlLength * OppositeLength,
        -ControlVector.Y / ControlLength * OppositeLength);
  end;
  ApplyScreenLayoutPathVertices(FDocument, FDragLayerIndex,
    NewVertices, True);
end;

procedure TScreenLayoutPathInteraction.CommitDrag;
var
  PathLayer: TVectArtLayer;
begin
  if (FEditHistory <> nil) and (FDragLayerIndex > 0) and
    FDocument[FDragLayerIndex].SupportsPathEditing then
  begin
    PathLayer := FDocument[FDragLayerIndex];
    if not ScreenLayoutPathVerticesEqual(FDragStartVertices,
      PathLayer.EditablePathVertices) then
      FEditHistory.AddApplied(TScreenLayoutPathVerticesCommand.Create(
        FDocument, FDragLayerIndex, FDragStartVertices,
        PathLayer.EditablePathVertices, True));
  end;
  EndDrag;
end;

procedure TScreenLayoutPathInteraction.EndDrag;
begin
  FDragLayerIndex := -1;
  FDragVertexIndex := -1;
  FDragBezierHandle := slbhNone;
  FDragStartVertices := nil;
end;

function TScreenLayoutPathInteraction.CursorAt(X, Y: Integer;
  out Cursor: TCursor): Boolean;
var
  HandleKind: TScreenLayoutBezierHandleKind;
  Parameter: Single;
  SegmentIndex: Integer;
  VertexIndex: Integer;
begin
  Cursor := crDefault;
  if HitTestBezierHandle(X, Y, HandleKind) or
    HitTestVertex(X, Y, VertexIndex) then
    Cursor := crSizeAll
  else if HitTestSegment(X, Y, SegmentIndex, Parameter) then
    Cursor := crCross;
  Result := Cursor <> crDefault;
end;

function TScreenLayoutPathInteraction.SelectedVertexKind(
  out Kind: TScreenLayoutVertexKind): Boolean;
var
  PathLayer: TVectArtLayer;
  Vertices: TArray<TScreenLayoutVertex>;
begin
  Kind := slvkSharp;
  Result := SelectedPathLayer(PathLayer) and
    (FSelectedVertexIndex >= 0);
  if not Result then
    Exit;
  Vertices := PathLayer.EditablePathVertices;
  Result := FSelectedVertexIndex <= High(Vertices);
  if Result then
    Kind := Vertices[FSelectedVertexIndex].Kind;
end;

function TScreenLayoutPathInteraction.SetSelectedVertexKind(
  Kind: TScreenLayoutVertexKind): Boolean;
var
  CurrentKind: TScreenLayoutVertexKind;
begin
  Result := SelectedVertexKind(CurrentKind);
  if Result and (CurrentKind <> Kind) then
    ApplySelectedVertexKind(Kind);
end;

function TScreenLayoutPathInteraction.SelectedVertexRects: TArray<TRect>;
var
  HalfSize: Integer;
  I: Integer;
  PathLayer: TVectArtLayer;
  Vertices: TArray<TScreenLayoutVertex>;
  X: Integer;
  Y: Integer;
begin
  Result := nil;
  if not SelectedPathLayer(PathLayer) then
    Exit;
  Vertices := PathLayer.EditablePathVertices;
  SetLength(Result, Length(Vertices));
  HalfSize := VERTEX_HANDLE_SIZE div 2;
  for I := 0 to High(Vertices) do
  begin
    X := ToScreenX(Vertices[I].Position.X);
    Y := ToScreenY(Vertices[I].Position.Y);
    Result[I] := Rect(X - HalfSize, Y - HalfSize,
      X - HalfSize + VERTEX_HANDLE_SIZE,
      Y - HalfSize + VERTEX_HANDLE_SIZE);
  end;
end;

function TScreenLayoutPathInteraction.SelectedPathPoints: TArray<TPoint>;
var
  I: Integer;
  Layer: TVectArtLayer;
  LogicalPoints: TArray<TPointF>;
begin
  Result := nil;
  if not SelectedPathLayer(Layer) then
    Exit;
  LogicalPoints := FlattenScreenLayoutPathVertices(
    Layer.EditablePathVertices);
  SetLength(Result, Length(LogicalPoints));
  for I := 0 to High(LogicalPoints) do
    Result[I] := Point(ToScreenX(LogicalPoints[I].X),
      ToScreenY(LogicalPoints[I].Y));
end;

function TScreenLayoutPathInteraction.SelectedVertexKindButtons:
  TArray<TScreenLayoutVertexKindButton>;
var
  Bounds: TRectF;
  ButtonCenterX: Single;
  ButtonCenterY: Single;
  ButtonIndex: Integer;
  CenterX: Integer;
  CenterY: Integer;
  DirectionLength: Single;
  DirectionX: Single;
  DirectionY: Single;
  HalfDistance: Single;
  HalfSize: Integer;
  PathLayer: TVectArtLayer;
  TangentX: Single;
  TangentY: Single;
  TargetX: Single;
  TargetY: Single;
  Vertex: TScreenLayoutVertex;
  Vertices: TArray<TScreenLayoutVertex>;
  VertexX: Integer;
  VertexY: Integer;
begin
  Result := nil;
  if not SelectedPathLayer(PathLayer) or (FSelectedVertexIndex < 0) then
    Exit;
  Vertices := PathLayer.EditablePathVertices;
  if FSelectedVertexIndex > High(Vertices) then
    Exit;
  Vertex := Vertices[FSelectedVertexIndex];
  Bounds := ScreenLayoutPathVerticesBounds(Vertices);
  VertexX := ToScreenX(Vertex.Position.X);
  VertexY := ToScreenY(Vertex.Position.Y);
  CenterX := ToScreenX((Bounds.Left + Bounds.Right) * 0.5);
  CenterY := ToScreenY((Bounds.Top + Bounds.Bottom) * 0.5);
  DirectionX := VertexX - CenterX;
  DirectionY := VertexY - CenterY;
  DirectionLength := Hypot(DirectionX, DirectionY);
  if DirectionLength < 0.001 then
  begin
    DirectionX := 0;
    DirectionY := -1;
  end
  else
  begin
    DirectionX := DirectionX / DirectionLength;
    DirectionY := DirectionY / DirectionLength;
  end;
  TargetX := VertexX + DirectionX * VERTEX_KIND_BUTTON_OFFSET;
  TargetY := VertexY + DirectionY * VERTEX_KIND_BUTTON_OFFSET;
  TangentX := -DirectionY;
  TangentY := DirectionX;
  HalfDistance := (VERTEX_KIND_BUTTON_SIZE + VERTEX_KIND_BUTTON_GAP) * 0.5;
  HalfSize := VERTEX_KIND_BUTTON_SIZE div 2;
  SetLength(Result, 2);
  for ButtonIndex := 0 to High(Result) do
  begin
    if ButtonIndex = 0 then
    begin
      Result[ButtonIndex].Kind := slvkSharp;
      ButtonCenterX := TargetX - TangentX * HalfDistance;
      ButtonCenterY := TargetY - TangentY * HalfDistance;
    end
    else
    begin
      Result[ButtonIndex].Kind := slvkBezier;
      ButtonCenterX := TargetX + TangentX * HalfDistance;
      ButtonCenterY := TargetY + TangentY * HalfDistance;
    end;
    Result[ButtonIndex].Bounds := Rect(Round(ButtonCenterX) - HalfSize,
      Round(ButtonCenterY) - HalfSize, Round(ButtonCenterX) + HalfSize,
      Round(ButtonCenterY) + HalfSize);
    Result[ButtonIndex].Selected := Result[ButtonIndex].Kind = Vertex.Kind;
  end;
end;

function TScreenLayoutPathInteraction.SelectedVertexRect(
  out VertexRect: TRect): Boolean;
var
  HalfSize: Integer;
  PathLayer: TVectArtLayer;
  Vertex: TScreenLayoutVertex;
  Vertices: TArray<TScreenLayoutVertex>;
  X: Integer;
  Y: Integer;
begin
  Result := False;
  VertexRect := TRect.Empty;
  if not SelectedPathLayer(PathLayer) or (FSelectedVertexIndex < 0) then
    Exit;
  Vertices := PathLayer.EditablePathVertices;
  if FSelectedVertexIndex > High(Vertices) then
    Exit;
  Vertex := Vertices[FSelectedVertexIndex];
  X := ToScreenX(Vertex.Position.X);
  Y := ToScreenY(Vertex.Position.Y);
  HalfSize := VERTEX_HANDLE_SIZE div 2;
  VertexRect := Rect(X - HalfSize, Y - HalfSize,
    X - HalfSize + VERTEX_HANDLE_SIZE,
    Y - HalfSize + VERTEX_HANDLE_SIZE);
  Result := True;
end;

function TScreenLayoutPathInteraction.SelectedBezierHandles(
  out Handles: TScreenLayoutBezierHandles): Boolean;
var
  HalfSize: Integer;
  PathLayer: TVectArtLayer;
  Vertex: TScreenLayoutVertex;
  Vertices: TArray<TScreenLayoutVertex>;
begin
  Result := False;
  Handles := Default(TScreenLayoutBezierHandles);
  if not SelectedPathLayer(PathLayer) or (FSelectedVertexIndex < 0) then
    Exit;
  Vertices := PathLayer.EditablePathVertices;
  if FSelectedVertexIndex > High(Vertices) then
    Exit;
  Vertex := Vertices[FSelectedVertexIndex];
  if Vertex.Kind <> slvkBezier then
    Exit;
  Handles.VertexPoint := Point(ToScreenX(Vertex.Position.X),
    ToScreenY(Vertex.Position.Y));
  Handles.IncomingPoint := Point(ToScreenX(Vertex.Position.X +
    Vertex.IncomingControl.X), ToScreenY(Vertex.Position.Y +
    Vertex.IncomingControl.Y));
  Handles.OutgoingPoint := Point(ToScreenX(Vertex.Position.X +
    Vertex.OutgoingControl.X), ToScreenY(Vertex.Position.Y +
    Vertex.OutgoingControl.Y));
  HalfSize := BEZIER_CONTROL_HANDLE_SIZE div 2;
  if FSelectedVertexIndex > 0 then
    Handles.IncomingRect := Rect(Handles.IncomingPoint.X - HalfSize,
      Handles.IncomingPoint.Y - HalfSize,
      Handles.IncomingPoint.X - HalfSize + BEZIER_CONTROL_HANDLE_SIZE,
      Handles.IncomingPoint.Y - HalfSize + BEZIER_CONTROL_HANDLE_SIZE);
  if FSelectedVertexIndex < High(Vertices) then
    Handles.OutgoingRect := Rect(Handles.OutgoingPoint.X - HalfSize,
      Handles.OutgoingPoint.Y - HalfSize,
      Handles.OutgoingPoint.X - HalfSize + BEZIER_CONTROL_HANDLE_SIZE,
      Handles.OutgoingPoint.Y - HalfSize + BEZIER_CONTROL_HANDLE_SIZE);
  Result := True;
end;

end.
