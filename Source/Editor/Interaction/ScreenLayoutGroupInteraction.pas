// 開いたグループの子選択、当たり判定、ドラッグ変形と履歴確定を管理する。
unit ScreenLayoutGroupInteraction;

interface

uses
  System.Types, ScreenLayoutDocument, ScreenLayoutEditHistory,
  ScreenLayoutEditorState, ScreenLayoutSelectionGeometry;

type
  TScreenLayoutGroupDragMode = (slgdmNone, slgdmMove, slgdmResize,
    slgdmRotate);

  TScreenLayoutGroupDrag = class
  private
    FCurrentBounds: TRectF;
    FDocument: TVectArtDocument;
    FDX: Single;
    FDY: Single;
    FLayers: TArray<TVectArtLayer>;
    FMode: TScreenLayoutGroupDragMode;
    FResizeHandle: TVectArtSelectionHandle;
    FRotationCenter: TPointF;
    FRotationDegrees: Single;
    FRotationStartAngle: Single;
    FStartBounds: TRectF;
    FStartPoint: TPoint;
    function GetActive: Boolean;
    procedure Reset;
  public
    // 選択子の移動を開始し、履歴確定に必要な開始状態を保持する。
    procedure BeginMove(Document: TVectArtDocument;
      const Layers: TArray<TVectArtLayer>; const StartPoint: TPoint);
    // 選択子全体の外接範囲を基準に拡大縮小を開始する。
    procedure BeginResize(Document: TVectArtDocument;
      const Layers: TArray<TVectArtLayer>; const StartPoint: TPoint;
      Handle: TVectArtSelectionHandle; const Bounds: TRectF);
    // 選択子全体を共通中心回りに回転する操作を開始する。
    procedure BeginRotate(Document: TVectArtDocument;
      const Layers: TArray<TVectArtLayer>; const Center: TPointF;
      StartAngle: Single);
    // 適用済みの変形量を1回のUndo単位として履歴へ確定する。
    function Finish(EditHistory: TVectArtEditHistory): Boolean;
    // 現在のマウス位置に対応する移動または拡大縮小をDocumentへ反映する。
    function UpdateMoveOrResize(X, Y: Integer; Zoom: Single): Boolean;
    // 現在角度に対応する回転差分をDocumentへ反映する。
    function UpdateRotation(CurrentAngle: Single): Boolean;
    property Active: Boolean read GetActive;
    property Mode: TScreenLayoutGroupDragMode read FMode;
    property ResizeHandle: TVectArtSelectionHandle read FResizeHandle;
    property RotationCenter: TPointF read FRotationCenter;
  end;

// グループ内の指定点で最前面にある表示中の直下レイヤーを返す。
function HitTestGroupChild(Group: TScreenLayoutGroupLayer;
  const LogicalPoint: TPointF): TVectArtLayer;
// 開いているグループで選択中の子全体を囲む外接範囲を返す。
function TryGetOpenGroupSelectionBounds(EditorState: TVectArtEditorState;
  out Bounds: TRectF): Boolean;
// 選択中のすべての子がロックされておらず変形可能ならTrueを返す。
function OpenGroupSelectionEditable(EditorState: TVectArtEditorState): Boolean;

implementation

uses
  System.Math, ScreenLayoutEditCommands, ScreenLayoutGroupTransformCommands,
  ScreenLayoutLayerGeometry;

procedure TScreenLayoutGroupDrag.BeginMove(Document: TVectArtDocument;
  const Layers: TArray<TVectArtLayer>; const StartPoint: TPoint);
begin
  Reset;
  FDocument := Document;
  FLayers := Copy(Layers);
  FStartPoint := StartPoint;
  FMode := slgdmMove;
end;

procedure TScreenLayoutGroupDrag.BeginResize(Document: TVectArtDocument;
  const Layers: TArray<TVectArtLayer>; const StartPoint: TPoint;
  Handle: TVectArtSelectionHandle; const Bounds: TRectF);
begin
  Reset;
  FDocument := Document;
  FLayers := Copy(Layers);
  FStartPoint := StartPoint;
  FResizeHandle := Handle;
  FStartBounds := Bounds;
  FCurrentBounds := Bounds;
  FMode := slgdmResize;
end;

procedure TScreenLayoutGroupDrag.BeginRotate(Document: TVectArtDocument;
  const Layers: TArray<TVectArtLayer>; const Center: TPointF;
  StartAngle: Single);
begin
  Reset;
  FDocument := Document;
  FLayers := Copy(Layers);
  FRotationCenter := Center;
  FRotationStartAngle := StartAngle;
  FMode := slgdmRotate;
end;

function TScreenLayoutGroupDrag.Finish(
  EditHistory: TVectArtEditHistory): Boolean;
var
  Command: TVectArtCompoundCommand;
  I: Integer;
begin
  Result := FMode <> slgdmNone;
  if not Result then
    Exit;
  if (EditHistory <> nil) and (Length(FLayers) > 0) then
  begin
    Command := TVectArtCompoundCommand.Create;
    case FMode of
      slgdmMove:
        if not SameValue(FDX, 0.0) or not SameValue(FDY, 0.0) then
          for I := 0 to High(FLayers) do
            Command.Add(TScreenLayoutTranslateLayerCommand.Create(
              FDocument, FLayers[I], FDX, FDY));
      slgdmResize:
        if not FStartBounds.EqualsTo(FCurrentBounds) then
          for I := 0 to High(FLayers) do
            Command.Add(TScreenLayoutScaleLayerCommand.Create(
              FDocument, FLayers[I], FStartBounds, FCurrentBounds));
      slgdmRotate:
        if not SameValue(FRotationDegrees, 0.0) then
          for I := 0 to High(FLayers) do
            Command.Add(TScreenLayoutRotateLayerCommand.Create(
              FDocument, FLayers[I], FRotationCenter, FRotationDegrees));
    end;
    if Command.Count > 0 then
      EditHistory.AddApplied(Command)
    else
      Command.Free;
  end;
  Reset;
end;

function TScreenLayoutGroupDrag.GetActive: Boolean;
begin
  Result := FMode <> slgdmNone;
end;

procedure TScreenLayoutGroupDrag.Reset;
begin
  FDocument := nil;
  SetLength(FLayers, 0);
  FMode := slgdmNone;
  FDX := 0;
  FDY := 0;
  FResizeHandle := vshNone;
  FRotationDegrees := 0;
end;

function TScreenLayoutGroupDrag.UpdateMoveOrResize(
  X, Y: Integer; Zoom: Single): Boolean;
var
  DX: Single;
  DY: Single;
  I: Integer;
  TargetBounds: TRectF;
begin
  Result := FMode in [slgdmMove, slgdmResize];
  if not Result then
    Exit;
  DX := (X - FStartPoint.X) / Zoom;
  DY := (Y - FStartPoint.Y) / Zoom;
  if FMode = slgdmMove then
  begin
    for I := 0 to High(FLayers) do
      TranslateScreenLayoutLayer(FLayers[I], DX - FDX, DY - FDY);
    FDX := DX;
    FDY := DY;
  end
  else
  begin
    TargetBounds := FStartBounds;
    if FResizeHandle in [vshTopLeft, vshLeft, vshBottomLeft] then
      TargetBounds.Left := Min(FStartBounds.Right - 1,
        FStartBounds.Left + DX);
    if FResizeHandle in [vshTopRight, vshRight, vshBottomRight] then
      TargetBounds.Right := Max(FStartBounds.Left + 1,
        FStartBounds.Right + DX);
    if FResizeHandle in [vshTopLeft, vshTop, vshTopRight] then
      TargetBounds.Top := Min(FStartBounds.Bottom - 1,
        FStartBounds.Top + DY);
    if FResizeHandle in [vshBottomLeft, vshBottom, vshBottomRight] then
      TargetBounds.Bottom := Max(FStartBounds.Top + 1,
        FStartBounds.Bottom + DY);
    for I := 0 to High(FLayers) do
      ScaleScreenLayoutLayer(FLayers[I], FCurrentBounds, TargetBounds);
    FCurrentBounds := TargetBounds;
  end;
  FDocument.Changed;
end;

function TScreenLayoutGroupDrag.UpdateRotation(
  CurrentAngle: Single): Boolean;
var
  DesiredDegrees: Single;
  I: Integer;
  IncrementDegrees: Single;
begin
  Result := FMode = slgdmRotate;
  if not Result then
    Exit;
  DesiredDegrees := CurrentAngle - FRotationStartAngle;
  while DesiredDegrees > 180 do
    DesiredDegrees := DesiredDegrees - 360;
  while DesiredDegrees < -180 do
    DesiredDegrees := DesiredDegrees + 360;
  IncrementDegrees := DesiredDegrees - FRotationDegrees;
  for I := 0 to High(FLayers) do
    RotateScreenLayoutLayer(FLayers[I], FRotationCenter, IncrementDegrees);
  FRotationDegrees := DesiredDegrees;
  FDocument.Changed;
end;

function HitTestGroupChild(Group: TScreenLayoutGroupLayer;
  const LogicalPoint: TPointF): TVectArtLayer;
var
  Bounds: TRectF;
  I: Integer;
begin
  Result := nil;
  if Group = nil then
    Exit;
  for I := Group.ChildCount - 1 downto 0 do
    if Group[I].Visible and TryGetScreenLayoutLayerBounds(Group[I], Bounds) and
      Bounds.Contains(LogicalPoint) then
      Exit(Group[I]);
end;

function TryGetOpenGroupSelectionBounds(EditorState: TVectArtEditorState;
  out Bounds: TRectF): Boolean;
var
  ChildBounds: TRectF;
  Layer: TVectArtLayer;
begin
  Result := False;
  Bounds := TRectF.Empty;
  if EditorState = nil then
    Exit;
  for Layer in EditorState.GetOpenGroupChildren do
    if TryGetScreenLayoutLayerBounds(Layer, ChildBounds) then
    begin
      if not Result then
        Bounds := ChildBounds
      else
      begin
        Bounds.Left := Min(Bounds.Left, ChildBounds.Left);
        Bounds.Top := Min(Bounds.Top, ChildBounds.Top);
        Bounds.Right := Max(Bounds.Right, ChildBounds.Right);
        Bounds.Bottom := Max(Bounds.Bottom, ChildBounds.Bottom);
      end;
      Result := True;
    end;
end;

function OpenGroupSelectionEditable(EditorState: TVectArtEditorState): Boolean;
var
  Layer: TVectArtLayer;
begin
  Result := (EditorState <> nil) and (EditorState.OpenGroupChildCount > 0);
  if not Result then
    Exit;
  for Layer in EditorState.GetOpenGroupChildren do
    if Layer.Locked then
      Exit(False);
end;

end.
