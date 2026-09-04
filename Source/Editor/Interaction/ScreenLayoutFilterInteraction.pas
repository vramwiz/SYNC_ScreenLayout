// フィルター効果枠の描画とキャンバス上の直接編集を担当する。
unit ScreenLayoutFilterInteraction;

interface

uses
  System.Types, Vcl.Controls, Vcl.Direct2D, Vcl.Graphics,
  ScreenLayoutDocument, ScreenLayoutEditHistory, ScreenLayoutEditorState,
  ScreenLayoutFilters;

type
  TScreenLayoutFilterInteraction = class
  private type
    TDragKind = (dkNone, dkBlur, dkOutline, dkShadow);
    THandleSide = (hsLeft, hsTop, hsRight, hsBottom);
  private
    FCanvasBounds: TRect;
    FDocument: TVectArtDocument;
    FDragFilter: TScreenLayoutFilter; // 操作中だけ参照し、所有権はレイヤーに残す。
    FDragKind: TDragKind;
    FDragOldValue1: Single;           // 幅、半径、または影Xの開始値。
    FDragOldValue2: Single;           // 影操作時だけ使用するYの開始値。
    FDragSide: THandleSide;
    FDragStart: TPoint;
    FEditHistory: TVectArtEditHistory;
    FEditorState: TVectArtEditorState;
    FZoom: Single;
    function CursorForSide(Side: THandleSide): TCursor;
    procedure DrawBlur(ACanvas: TCanvas); overload;
    procedure DrawBlur(ACanvas: TDirect2DCanvas); overload;
    procedure DrawOutline(ACanvas: TCanvas); overload;
    procedure DrawOutline(ACanvas: TDirect2DCanvas); overload;
    procedure DrawShadow(ACanvas: TCanvas); overload;
    procedure DrawShadow(ACanvas: TDirect2DCanvas); overload;
    function GetBlurEditRect(out EditRect: TRect): Boolean;
    function GetHandleCenter(const EditRect: TRect;
      Side: THandleSide): TPoint;
    function GetOutlineEditRect(out EditRect: TRect): Boolean;
    function GetShadowEditRect(out EditRect: TRect): Boolean;
    function HitHandle(X, Y: Integer; const EditRect: TRect;
      out Side: THandleSide): Boolean;
    function LayerScreenRect(Layer: TVectArtLayer;
      out ScreenRect: TRect): Boolean;
    function ToScreenX(Value: Single): Integer;
    function ToScreenY(Value: Single): Integer;
  public
    // 操作対象と論理座標から画面座標へ変換するための表示状態を更新する。
    procedure Configure(Document: TVectArtDocument;
      EditHistory: TVectArtEditHistory; EditorState: TVectArtEditorState;
      const CanvasBounds: TRect; Zoom: Single);
    // 選択フィルターに対応する効果枠と操作ハンドルをGDIへ描画する。
    procedure Draw(ACanvas: TCanvas); overload;
    // 選択フィルターに対応する効果枠と操作ハンドルをDirect2Dへ描画する。
    procedure Draw(ACanvas: TDirect2DCanvas); overload;
    // ハンドルまたは影枠の直接編集を開始し、取得した場合にTrueを返す。
    function MouseDown(X, Y: Integer): Boolean;
    // 直接編集を更新する。ドラッグ中または専用カーソル上ならTrueを返す。
    function MouseMove(X, Y: Integer): Boolean;
    // ドラッグ全体を1つのUndo履歴として確定し、確定対象ならTrueを返す。
    function MouseUp: Boolean;
    // 現在位置に対応するフィルター編集カーソルを返す。
    function CursorAt(X, Y: Integer): TCursor;
  end;

implementation

uses
  System.Math,
  ScreenLayoutFilterCommands, ScreenLayoutGeometry,
  ScreenLayoutLayerGeometry, ScreenLayoutOverlayHandles,
  ScreenLayoutOverlayPrimitives, ScreenLayoutOverlayShapes;

const
  BLUR_EFFECT_RADIUS_MULTIPLIER = 3.0; // Skiaの効果範囲計算と同じ広がり。
  COLOR_FILTER_EDIT = TColor($000080FF);
  FILTER_HANDLE_RADIUS = 6;            // 低ズームでも操作できる画面上の半径。
  MAX_BLUR_RADIUS = 50.0;
  MAX_OUTLINE_WIDTH = 40.0;

procedure TScreenLayoutFilterInteraction.Configure(
  Document: TVectArtDocument; EditHistory: TVectArtEditHistory;
  EditorState: TVectArtEditorState; const CanvasBounds: TRect; Zoom: Single);
begin
  FDocument := Document;
  FEditHistory := EditHistory;
  FEditorState := EditorState;
  FCanvasBounds := CanvasBounds;
  FZoom := Zoom;
end;

function TScreenLayoutFilterInteraction.CursorAt(X, Y: Integer): TCursor;
var
  EditRect: TRect;
  Side: THandleSide;
begin
  Result := crDefault;
  if FDragKind = dkShadow then
    Exit(crSizeAll);
  if FDragKind in [dkBlur, dkOutline] then
    Exit(CursorForSide(FDragSide));
  if GetBlurEditRect(EditRect) and HitHandle(X, Y, EditRect, Side) then
    Exit(CursorForSide(Side));
  if GetOutlineEditRect(EditRect) and HitHandle(X, Y, EditRect, Side) then
    Exit(CursorForSide(Side));
  if GetShadowEditRect(EditRect) and PtInRect(EditRect, Point(X, Y)) then
    Exit(crSizeAll);
end;

function TScreenLayoutFilterInteraction.CursorForSide(
  Side: THandleSide): TCursor;
begin
  if Side in [hsLeft, hsRight] then
    Result := crSizeWE
  else
    Result := crSizeNS;
end;

procedure TScreenLayoutFilterInteraction.Draw(ACanvas: TCanvas);
begin
  DrawBlur(ACanvas);
  DrawOutline(ACanvas);
  DrawShadow(ACanvas);
end;

procedure TScreenLayoutFilterInteraction.Draw(ACanvas: TDirect2DCanvas);
begin
  DrawBlur(ACanvas);
  DrawOutline(ACanvas);
  DrawShadow(ACanvas);
end;

procedure TScreenLayoutFilterInteraction.DrawBlur(ACanvas: TCanvas);
var
  EditRect: TRect;
  Side: THandleSide;
  SourceRect: TRect;
begin
  if not GetBlurEditRect(EditRect) or
    not LayerScreenRect(FEditorState.SelectedFilterLayer, SourceRect) then
    Exit;
  DrawOverlayFrameRect(ACanvas, EditRect, COLOR_FILTER_EDIT, psDot);
  DrawOverlayFrameRect(ACanvas, SourceRect, COLOR_FILTER_EDIT);
  for Side := Low(THandleSide) to High(THandleSide) do
    with GetHandleCenter(EditRect, Side) do
      DrawOverlayHandleEllipse(ACanvas,
        Rect(X - FILTER_HANDLE_RADIUS, Y - FILTER_HANDLE_RADIUS,
          X + FILTER_HANDLE_RADIUS + 1, Y + FILTER_HANDLE_RADIUS + 1),
        clWhite, COLOR_FILTER_EDIT);
end;

procedure TScreenLayoutFilterInteraction.DrawBlur(
  ACanvas: TDirect2DCanvas);
var
  EditRect: TRect;
  Side: THandleSide;
  SourceRect: TRect;
begin
  if not GetBlurEditRect(EditRect) or
    not LayerScreenRect(FEditorState.SelectedFilterLayer, SourceRect) then
    Exit;
  DrawOverlayFrameRect(ACanvas, EditRect, COLOR_FILTER_EDIT, psDot);
  DrawOverlayFrameRect(ACanvas, SourceRect, COLOR_FILTER_EDIT);
  for Side := Low(THandleSide) to High(THandleSide) do
    with GetHandleCenter(EditRect, Side) do
      DrawOverlayHandleEllipse(ACanvas,
        Rect(X - FILTER_HANDLE_RADIUS, Y - FILTER_HANDLE_RADIUS,
          X + FILTER_HANDLE_RADIUS + 1, Y + FILTER_HANDLE_RADIUS + 1),
        clWhite, COLOR_FILTER_EDIT);
end;

procedure TScreenLayoutFilterInteraction.DrawOutline(ACanvas: TCanvas);
var
  Center: TPoint;
  EditRect: TRect;
  Side: THandleSide;
begin
  if not GetOutlineEditRect(EditRect) then
    Exit;
  DrawOverlayFrameRect(ACanvas, EditRect, COLOR_FILTER_EDIT);
  for Side := Low(THandleSide) to High(THandleSide) do
  begin
    Center := GetHandleCenter(EditRect, Side);
    DrawOverlayHandleRect(ACanvas,
      Rect(Center.X - FILTER_HANDLE_RADIUS,
        Center.Y - FILTER_HANDLE_RADIUS, Center.X + FILTER_HANDLE_RADIUS + 1,
        Center.Y + FILTER_HANDLE_RADIUS + 1), clWhite, COLOR_FILTER_EDIT);
  end;
end;

procedure TScreenLayoutFilterInteraction.DrawOutline(
  ACanvas: TDirect2DCanvas);
var
  Center: TPoint;
  EditRect: TRect;
  Side: THandleSide;
begin
  if not GetOutlineEditRect(EditRect) then
    Exit;
  DrawOverlayFrameRect(ACanvas, EditRect, COLOR_FILTER_EDIT);
  for Side := Low(THandleSide) to High(THandleSide) do
  begin
    Center := GetHandleCenter(EditRect, Side);
    DrawOverlayHandleRect(ACanvas,
      Rect(Center.X - FILTER_HANDLE_RADIUS,
        Center.Y - FILTER_HANDLE_RADIUS, Center.X + FILTER_HANDLE_RADIUS + 1,
        Center.Y + FILTER_HANDLE_RADIUS + 1), clWhite, COLOR_FILTER_EDIT);
  end;
end;

procedure TScreenLayoutFilterInteraction.DrawShadow(ACanvas: TCanvas);
var
  EditRect: TRect;
  LayerRect: TRect;
  ShadowCenter: TPoint;
begin
  if not GetShadowEditRect(EditRect) or
    not LayerScreenRect(FEditorState.SelectedFilterLayer, LayerRect) then
    Exit;
  ShadowCenter := EditRect.CenterPoint;
  DrawOverlayLine(ACanvas, LayerRect.CenterPoint, ShadowCenter,
    COLOR_FILTER_EDIT);
  DrawOverlayFrameRect(ACanvas, EditRect, COLOR_FILTER_EDIT);
  DrawOverlayHandleRect(ACanvas,
    Rect(ShadowCenter.X - 3, ShadowCenter.Y - 3,
      ShadowCenter.X + 4, ShadowCenter.Y + 4), COLOR_FILTER_EDIT,
    COLOR_FILTER_EDIT);
end;

procedure TScreenLayoutFilterInteraction.DrawShadow(
  ACanvas: TDirect2DCanvas);
var
  EditRect: TRect;
  LayerRect: TRect;
  ShadowCenter: TPoint;
begin
  if not GetShadowEditRect(EditRect) or
    not LayerScreenRect(FEditorState.SelectedFilterLayer, LayerRect) then
    Exit;
  ShadowCenter := EditRect.CenterPoint;
  DrawOverlayLine(ACanvas, LayerRect.CenterPoint, ShadowCenter,
    COLOR_FILTER_EDIT);
  DrawOverlayFrameRect(ACanvas, EditRect, COLOR_FILTER_EDIT);
  DrawOverlayHandleRect(ACanvas,
    Rect(ShadowCenter.X - 3, ShadowCenter.Y - 3,
      ShadowCenter.X + 4, ShadowCenter.Y + 4), COLOR_FILTER_EDIT,
    COLOR_FILTER_EDIT);
end;

function TScreenLayoutFilterInteraction.GetBlurEditRect(
  out EditRect: TRect): Boolean;
var
  Blur: TScreenLayoutBlurFilter;
  Bounds: TRectF;
  EffectRadius: Single;
begin
  Result := False;
  EditRect := TRect.Empty;
  if (FEditorState = nil) or
    not (FEditorState.SelectedFilter is TScreenLayoutBlurFilter) or
    (FEditorState.SelectedFilterLayer = nil) or
    FEditorState.SelectedFilterLayer.Locked or
    not TryGetScreenLayoutLayerBounds(FEditorState.SelectedFilterLayer,
      Bounds) then
    Exit;
  Blur := TScreenLayoutBlurFilter(FEditorState.SelectedFilter);
  if not Blur.Enabled then
    Exit;
  EffectRadius := Max(Blur.Radius, 0.0) *
    BLUR_EFFECT_RADIUS_MULTIPLIER;
  Bounds.Inflate(EffectRadius, EffectRadius);
  EditRect := Rect(ToScreenX(Bounds.Left), ToScreenY(Bounds.Top),
    ToScreenX(Bounds.Right), ToScreenY(Bounds.Bottom));
  Result := True;
end;

function TScreenLayoutFilterInteraction.GetHandleCenter(
  const EditRect: TRect; Side: THandleSide): TPoint;
begin
  case Side of
    hsLeft: Result := Point(EditRect.Left, EditRect.CenterPoint.Y);
    hsTop: Result := Point(EditRect.CenterPoint.X, EditRect.Top);
    hsRight: Result := Point(EditRect.Right, EditRect.CenterPoint.Y);
  else
    Result := Point(EditRect.CenterPoint.X, EditRect.Bottom);
  end;
end;

function TScreenLayoutFilterInteraction.GetOutlineEditRect(
  out EditRect: TRect): Boolean;
var
  Bounds: TRectF;
  Outline: TScreenLayoutOutlineFilter;
begin
  Result := False;
  EditRect := TRect.Empty;
  if (FEditorState = nil) or
    not (FEditorState.SelectedFilter is TScreenLayoutOutlineFilter) or
    (FEditorState.SelectedFilterLayer = nil) or
    FEditorState.SelectedFilterLayer.Locked or
    not TryGetScreenLayoutLayerBounds(FEditorState.SelectedFilterLayer,
      Bounds) then
    Exit;
  Outline := TScreenLayoutOutlineFilter(FEditorState.SelectedFilter);
  if not Outline.Enabled then
    Exit;
  Bounds.Inflate(Max(Outline.Width, 0.0), Max(Outline.Width, 0.0));
  EditRect := Rect(ToScreenX(Bounds.Left), ToScreenY(Bounds.Top),
    ToScreenX(Bounds.Right), ToScreenY(Bounds.Bottom));
  Result := True;
end;

function TScreenLayoutFilterInteraction.GetShadowEditRect(
  out EditRect: TRect): Boolean;
var
  Bounds: TRectF;
  Shadow: TScreenLayoutShadowFilter;
begin
  Result := False;
  EditRect := TRect.Empty;
  if (FEditorState = nil) or
    not (FEditorState.SelectedFilter is TScreenLayoutShadowFilter) or
    (FEditorState.SelectedFilterLayer = nil) or
    FEditorState.SelectedFilterLayer.Locked or
    not TryGetScreenLayoutLayerBounds(FEditorState.SelectedFilterLayer,
      Bounds) then
    Exit;
  Shadow := TScreenLayoutShadowFilter(FEditorState.SelectedFilter);
  if not Shadow.Enabled then
    Exit;
  Bounds.Offset(Shadow.OffsetX, Shadow.OffsetY);
  EditRect := Rect(ToScreenX(Bounds.Left), ToScreenY(Bounds.Top),
    ToScreenX(Bounds.Right), ToScreenY(Bounds.Bottom));
  if EditRect.Width = 0 then
    Inc(EditRect.Right);
  if EditRect.Height = 0 then
    Inc(EditRect.Bottom);
  Result := True;
end;

function TScreenLayoutFilterInteraction.HitHandle(X, Y: Integer;
  const EditRect: TRect; out Side: THandleSide): Boolean;
var
  Candidate: THandleSide;
  Center: TPoint;
begin
  for Candidate := Low(THandleSide) to High(THandleSide) do
  begin
    Center := GetHandleCenter(EditRect, Candidate);
    if PtInRect(Rect(Center.X - FILTER_HANDLE_RADIUS,
      Center.Y - FILTER_HANDLE_RADIUS, Center.X + FILTER_HANDLE_RADIUS + 1,
      Center.Y + FILTER_HANDLE_RADIUS + 1), Point(X, Y)) then
    begin
      Side := Candidate;
      Exit(True);
    end;
  end;
  Side := hsLeft;
  Result := False;
end;

function TScreenLayoutFilterInteraction.LayerScreenRect(
  Layer: TVectArtLayer; out ScreenRect: TRect): Boolean;
var
  Bounds: TRectF;
begin
  Result := (Layer <> nil) and TryGetScreenLayoutLayerBounds(Layer, Bounds);
  if not Result then
  begin
    ScreenRect := TRect.Empty;
    Exit;
  end;
  ScreenRect := Rect(ToScreenX(Bounds.Left), ToScreenY(Bounds.Top),
    ToScreenX(Bounds.Right), ToScreenY(Bounds.Bottom));
end;

function TScreenLayoutFilterInteraction.MouseDown(X, Y: Integer): Boolean;
var
  EditRect: TRect;
  Side: THandleSide;
begin
  Result := False;
  if (FDocument = nil) or (FEditorState = nil) then
    Exit;
  if GetBlurEditRect(EditRect) and HitHandle(X, Y, EditRect, Side) then
  begin
    FDragKind := dkBlur;
    FDragFilter := FEditorState.SelectedFilter;
    FDragOldValue1 := TScreenLayoutBlurFilter(FDragFilter).Radius;
    FDragSide := Side;
  end
  else if GetOutlineEditRect(EditRect) and HitHandle(X, Y, EditRect, Side) then
  begin
    FDragKind := dkOutline;
    FDragFilter := FEditorState.SelectedFilter;
    FDragOldValue1 := TScreenLayoutOutlineFilter(FDragFilter).Width;
    FDragSide := Side;
  end
  else if GetShadowEditRect(EditRect) and PtInRect(EditRect, Point(X, Y)) then
  begin
    FDragKind := dkShadow;
    FDragFilter := FEditorState.SelectedFilter;
    FDragOldValue1 := TScreenLayoutShadowFilter(FDragFilter).OffsetX;
    FDragOldValue2 := TScreenLayoutShadowFilter(FDragFilter).OffsetY;
  end
  else
    Exit;
  FDragStart := Point(X, Y);
  FDocument.BeginInteractiveUpdate;
  Result := True;
end;

function TScreenLayoutFilterInteraction.MouseMove(X, Y: Integer): Boolean;
var
  Delta: Single;
begin
  Result := FDragKind <> dkNone;
  if not Result then
    Exit(CursorAt(X, Y) <> crDefault);
  case FDragKind of
    dkBlur:
    begin
      if FDragSide in [hsLeft, hsRight] then
        Delta := (X - FDragStart.X) / Max(FZoom, 0.001)
      else
        Delta := (Y - FDragStart.Y) / Max(FZoom, 0.001);
      if FDragSide in [hsLeft, hsTop] then
        Delta := -Delta;
      TScreenLayoutBlurFilter(FDragFilter).Radius := EnsureRange(
        FDragOldValue1 + Delta / BLUR_EFFECT_RADIUS_MULTIPLIER,
        0.0, MAX_BLUR_RADIUS);
    end;
    dkOutline:
    begin
      if FDragSide in [hsLeft, hsRight] then
        Delta := (X - FDragStart.X) / Max(FZoom, 0.001)
      else
        Delta := (Y - FDragStart.Y) / Max(FZoom, 0.001);
      if FDragSide in [hsLeft, hsTop] then
        Delta := -Delta;
      TScreenLayoutOutlineFilter(FDragFilter).Width := EnsureRange(
        FDragOldValue1 + Delta, 0.0, MAX_OUTLINE_WIDTH);
    end;
    dkShadow:
    begin
      TScreenLayoutShadowFilter(FDragFilter).OffsetX := FDragOldValue1 +
        (X - FDragStart.X) / Max(FZoom, 0.001);
      TScreenLayoutShadowFilter(FDragFilter).OffsetY := FDragOldValue2 +
        (Y - FDragStart.Y) / Max(FZoom, 0.001);
    end;
  end;
  FDocument.Changed;
end;

function TScreenLayoutFilterInteraction.MouseUp: Boolean;
var
  Changed: Boolean;
  Command: TScreenLayoutSetFilterParametersCommand;
  NewParameters: TScreenLayoutFilter;
  OldParameters: TScreenLayoutFilter;
begin
  Result := FDragKind <> dkNone;
  if not Result then
    Exit;
  Changed := False;
  case FDragKind of
    dkBlur:
      Changed := not SameValue(TScreenLayoutBlurFilter(FDragFilter).Radius,
        FDragOldValue1);
    dkOutline:
      Changed := not SameValue(
        TScreenLayoutOutlineFilter(FDragFilter).Width, FDragOldValue1);
    dkShadow:
      Changed := not SameValue(
        TScreenLayoutShadowFilter(FDragFilter).OffsetX, FDragOldValue1) or
        not SameValue(TScreenLayoutShadowFilter(FDragFilter).OffsetY,
          FDragOldValue2);
  end;
  if Changed then
  begin
    OldParameters := TScreenLayoutFilter(FDragFilter).Clone;
    NewParameters := TScreenLayoutFilter(FDragFilter).Clone;
    try
      case FDragKind of
        dkBlur:
          TScreenLayoutBlurFilter(OldParameters).Radius := FDragOldValue1;
        dkOutline:
          TScreenLayoutOutlineFilter(OldParameters).Width := FDragOldValue1;
        dkShadow:
        begin
          TScreenLayoutShadowFilter(OldParameters).OffsetX := FDragOldValue1;
          TScreenLayoutShadowFilter(OldParameters).OffsetY := FDragOldValue2;
        end;
      end;
      Command := TScreenLayoutSetFilterParametersCommand.Create(FDocument,
        TScreenLayoutFilter(FDragFilter), OldParameters, NewParameters);
      if FEditHistory <> nil then
        FEditHistory.AddApplied(Command)
      else
        Command.Free;
    finally
      NewParameters.Free;
      OldParameters.Free;
    end;
  end;
  FDragKind := dkNone;
  FDragFilter := nil;
  FDocument.EndInteractiveUpdate;
end;

function TScreenLayoutFilterInteraction.ToScreenX(Value: Single): Integer;
begin
  Result := LogicalToScreenX(Value, FCanvasBounds, FZoom,
    FDocument.CanvasLayer.Width);
end;

function TScreenLayoutFilterInteraction.ToScreenY(Value: Single): Integer;
begin
  Result := LogicalToScreenY(Value, FCanvasBounds, FZoom,
    FDocument.CanvasLayer.Height);
end;

end.
