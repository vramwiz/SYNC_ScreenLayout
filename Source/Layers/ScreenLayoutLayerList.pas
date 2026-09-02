// レイヤー一覧の描画方式切替、クリック判定、Document接続を担当する。
unit ScreenLayoutLayerList;

interface

uses
  System.Classes, System.Types, Vcl.Controls, Vcl.Direct2D, ScreenLayoutDocument,
  ScreenLayoutEditCommands, ScreenLayoutEditHistory, ScreenLayoutEditorState,
  ScreenLayoutLayerRenderer, VerticalScrollBarControl;

type
  TVectArtLayerListControl = class(TCustomControl)
  private
    FDirect2DEnabled: Boolean;
    FDocument: TVectArtDocument;
    FEditHistory: TVectArtEditHistory;
    FEditorState: TVectArtEditorState;
    FDragCandidateIndex: Integer;
    FDragStartPoint: TPoint;
    FDraggingLayer: Boolean;
    FDragTargetIndex: Integer;
    FRenderer: TVectArtLayerRenderer;
    FSelectionAnchorIndex: Integer;
    FScrollBar: TVerticalScrollBarControl;
    FUpdatingScrollBar: Boolean;
    function LayerBounds: TRect;
    function ScrollBarWidth: Integer;
    procedure ScrollBarChanged(Sender: TObject);
    procedure UpdateScrollBar;
    procedure PaintDirect2D;
    procedure PaintGDI;
    procedure SetDocument(const Value: TVectArtDocument);
  protected
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer;
      MousePos: TPoint): Boolean; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState;
      X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState;
      X, Y: Integer); override;
    procedure Paint; override;
    procedure Resize; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    property Document: TVectArtDocument read FDocument write SetDocument;
    property EditHistory: TVectArtEditHistory read FEditHistory
      write FEditHistory;
    property EditorState: TVectArtEditorState read FEditorState
      write FEditorState;
  end;

implementation

uses
  System.Math, Winapi.Windows, Vcl.Graphics,
  ScreenLayoutLayerStructureCommands;

const
  COLOR_LIST_BACKGROUND = TColor($001A1A1A);
  COLOR_DROP_TARGET = TColor($00D69C4A);
  LAYER_DRAG_THRESHOLD = 5;
  LAYER_SCROLL_BAR_WIDTH = 14;
  LAYER_WHEEL_ROWS = 3;

constructor TVectArtLayerListControl.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Color := COLOR_LIST_BACKGROUND;
  ControlStyle := ControlStyle + [csOpaque];
  DoubleBuffered := True;
  TabStop := True;
  FDirect2DEnabled := TDirect2DCanvas.Supported;
  FRenderer := TVectArtLayerRenderer.Create;
  FScrollBar := TVerticalScrollBarControl.Create(Self);
  FScrollBar.Parent := Self;
  FScrollBar.Visible := False;
  FScrollBar.OnChange := ScrollBarChanged;
  FSelectionAnchorIndex := -1;
  FDragCandidateIndex := -1;
  FDragTargetIndex := -1;
end;

function TVectArtLayerListControl.DoMouseWheel(Shift: TShiftState;
  WheelDelta: Integer; MousePos: TPoint): Boolean;
var
  Delta: Integer;
begin
  UpdateScrollBar;
  Result := FScrollBar.Visible and (WheelDelta <> 0);
  if Result then
  begin
    Delta := MulDiv(WheelDelta,
      FRenderer.ScrollStep * LAYER_WHEEL_ROWS, WHEEL_DELTA);
    FRenderer.ScrollOffset := FRenderer.ScrollOffset + Delta;
    UpdateScrollBar;
    Invalidate;
  end
  else
    Result := inherited DoMouseWheel(Shift, WheelDelta, MousePos);
end;

function TVectArtLayerListControl.LayerBounds: TRect;
begin
  Result := ClientRect;
  if (FScrollBar <> nil) and FScrollBar.Visible then
    Result.Right := Max(Result.Left,
      Result.Right - FScrollBar.Width - 1);
end;

function TVectArtLayerListControl.ScrollBarWidth: Integer;
begin
  Result := MulDiv(LAYER_SCROLL_BAR_WIDTH, CurrentPPI, 96);
end;

destructor TVectArtLayerListControl.Destroy;
begin
  FRenderer.Free;
  inherited Destroy;
end;

procedure TVectArtLayerListControl.MouseDown(Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
var
  Index: Integer;
  ItemRect: TRect;
  Layer: TVectArtLayer;
  NewValue: Boolean;
begin
  if (Button = mbLeft) and (FDocument <> nil) then
  begin
    if CanFocus then
      SetFocus;
    Index := FRenderer.LayerIndexAt(LayerBounds, Y);
    if Index >= 0 then
    begin
      ItemRect := FRenderer.LayerItemRect(LayerBounds, Index);
      Layer := FDocument[Index];
      if (ssDouble in Shift) and (Layer is TScreenLayoutGroupLayer) and
        (FEditorState <> nil) then
      begin
        FDocument.SelectedIndex := Index;
        if FEditorState.RootOpenGroup = Layer then
          FEditorState.OpenGroup := nil
        else
          FEditorState.OpenGroup := TScreenLayoutGroupLayer(Layer);
        Exit;
      end;
      if (FEditorState <> nil) and (FEditorState.OpenGroup <> nil) and
        (Layer <> FEditorState.RootOpenGroup) then
        FEditorState.OpenGroup := nil;
      if PtInRect(FRenderer.VisibilityButtonRect(ItemRect), Point(X, Y)) then
      begin
        NewValue := not Layer.Visible;
        FDocument.SetLayerVisible(Index, NewValue);
        if FEditHistory <> nil then
          FEditHistory.AddApplied(TVectArtLayerBooleanCommand.Create(
            FDocument, Index, vlbpVisible, not NewValue, NewValue));
        Exit;
      end;
      if PtInRect(FRenderer.LockButtonRect(ItemRect), Point(X, Y)) then
      begin
        NewValue := not Layer.Locked;
        FDocument.SetLayerLocked(Index, NewValue);
        if FEditHistory <> nil then
          FEditHistory.AddApplied(TVectArtLayerBooleanCommand.Create(
            FDocument, Index, vlbpLocked, not NewValue, NewValue));
        Exit;
      end;
      if ssShift in Shift then
      begin
        if FSelectionAnchorIndex <= 0 then
          if FDocument.SelectedIndex > 0 then
            FSelectionAnchorIndex := FDocument.SelectedIndex
          else
            FSelectionAnchorIndex := Index;
        FDocument.SelectLayerRange(FSelectionAnchorIndex, Index,
          ssCtrl in Shift);
      end
      else if ssCtrl in Shift then
      begin
        FDocument.ToggleSelectedLayer(Index);
        FSelectionAnchorIndex := Index;
      end
      else
      begin
        FDocument.SelectedIndex := Index;
        FSelectionAnchorIndex := Index;
        if not Layer.Locked then
        begin
          FDragCandidateIndex := Index;
          FDragTargetIndex := Index;
          FDragStartPoint := Point(X, Y);
          MouseCapture := True;
        end;
      end;
      Exit;
    end;
  end;
  inherited MouseDown(Button, Shift, X, Y);
end;

procedure TVectArtLayerListControl.MouseMove(Shift: TShiftState;
  X, Y: Integer);
var
  Index: Integer;
begin
  if (FDragCandidateIndex > 0) and (ssLeft in Shift) then
  begin
    if not FDraggingLayer and
      ((Abs(X - FDragStartPoint.X) >= LAYER_DRAG_THRESHOLD) or
       (Abs(Y - FDragStartPoint.Y) >= LAYER_DRAG_THRESHOLD)) then
      FDraggingLayer := True;
    if FDraggingLayer then
    begin
      Index := FRenderer.LayerIndexAt(LayerBounds, Y);
      if Index > 0 then
        FDragTargetIndex := Index;
      Cursor := crSizeAll;
      Invalidate;
      Exit;
    end;
  end;
  inherited MouseMove(Shift, X, Y);
end;

procedure TVectArtLayerListControl.MouseUp(Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
var
  AfterSelection: TArray<Integer>;
  BeforeSelection: TArray<Integer>;
  OldIndex: Integer;
  NewIndex: Integer;
begin
  if (Button = mbLeft) and (FDragCandidateIndex > 0) then
  begin
    MouseCapture := False;
    OldIndex := FDragCandidateIndex;
    NewIndex := FDragTargetIndex;
    if FDraggingLayer and (NewIndex > 0) and (OldIndex <> NewIndex) and
      (OldIndex < FDocument.LayerCount) and
      (NewIndex < FDocument.LayerCount) then
    begin
      BeforeSelection := FDocument.GetSelectedLayerIndices;
      FDocument.MoveLayer(OldIndex, NewIndex);
      AfterSelection := FDocument.GetSelectedLayerIndices;
      if FEditHistory <> nil then
        FEditHistory.AddApplied(TVectArtMoveLayerCommand.Create(FDocument,
          OldIndex, NewIndex, BeforeSelection, AfterSelection));
      FSelectionAnchorIndex := NewIndex;
    end;
    FDragCandidateIndex := -1;
    FDragTargetIndex := -1;
    FDraggingLayer := False;
    Cursor := crDefault;
    Invalidate;
    Exit;
  end;
  inherited MouseUp(Button, Shift, X, Y);
end;

procedure TVectArtLayerListControl.Paint;
begin
  UpdateScrollBar;
  if FEditorState <> nil then
    FRenderer.OpenGroup := FEditorState.RootOpenGroup
  else
    FRenderer.OpenGroup := nil;
  if FDirect2DEnabled then
    try
      PaintDirect2D;
      UpdateScrollBar;
      Exit;
    except
      FDirect2DEnabled := False;
    end;
  PaintGDI;
  UpdateScrollBar;
end;

procedure TVectArtLayerListControl.PaintDirect2D;
var
  Direct2DCanvas: TDirect2DCanvas;
  IndicatorY: Integer;
  TargetRect: TRect;
begin
  Direct2DCanvas := TDirect2DCanvas.Create(Canvas, LayerBounds);
  try
    Direct2DCanvas.BeginDraw;
    try
      FRenderer.DrawLayers(Direct2DCanvas, LayerBounds);
      if FDraggingLayer and (FDragTargetIndex > 0) and
        (FDragTargetIndex <> FDragCandidateIndex) then
      begin
        TargetRect := FRenderer.LayerItemRect(LayerBounds,
          FDragTargetIndex);
        if FDragTargetIndex > FDragCandidateIndex then
          IndicatorY := TargetRect.Top
        else
          IndicatorY := TargetRect.Bottom;
        Direct2DCanvas.Pen.Color := COLOR_DROP_TARGET;
        Direct2DCanvas.Pen.Width := 3;
        Direct2DCanvas.MoveTo(TargetRect.Left, IndicatorY);
        Direct2DCanvas.LineTo(TargetRect.Right, IndicatorY);
        Direct2DCanvas.Pen.Width := 1;
      end;
    finally
      Direct2DCanvas.EndDraw;
    end;
  finally
    Direct2DCanvas.Free;
  end;
end;

procedure TVectArtLayerListControl.PaintGDI;
var
  IndicatorY: Integer;
  TargetRect: TRect;
begin
  FRenderer.DrawLayers(Canvas, LayerBounds);
  if FDraggingLayer and (FDragTargetIndex > 0) and
    (FDragTargetIndex <> FDragCandidateIndex) then
  begin
    TargetRect := FRenderer.LayerItemRect(LayerBounds, FDragTargetIndex);
    if FDragTargetIndex > FDragCandidateIndex then
      IndicatorY := TargetRect.Top
    else
      IndicatorY := TargetRect.Bottom;
    Canvas.Pen.Color := COLOR_DROP_TARGET;
    Canvas.Pen.Width := 3;
    Canvas.MoveTo(TargetRect.Left, IndicatorY);
    Canvas.LineTo(TargetRect.Right, IndicatorY);
    Canvas.Pen.Width := 1;
  end;
end;

procedure TVectArtLayerListControl.Resize;
begin
  inherited;
  if FScrollBar <> nil then
  begin
    FScrollBar.SetBounds(Max(ClientWidth - ScrollBarWidth, 0), 0,
      ScrollBarWidth, ClientHeight);
    UpdateScrollBar;
  end;
end;

procedure TVectArtLayerListControl.ScrollBarChanged(Sender: TObject);
begin
  if FUpdatingScrollBar then
    Exit;
  FRenderer.ScrollOffset := FScrollBar.Maximum - FScrollBar.Position;
  Invalidate;
end;

procedure TVectArtLayerListControl.SetDocument(
  const Value: TVectArtDocument);
begin
  if FDocument = Value then
    Exit;
  FDocument := Value;
  FSelectionAnchorIndex := -1;
  FDragCandidateIndex := -1;
  FDragTargetIndex := -1;
  FDraggingLayer := False;
  FRenderer.Document := Value;
  UpdateScrollBar;
  Invalidate;
end;

procedure TVectArtLayerListControl.UpdateScrollBar;
var
  Bounds: TRect;
  MaximumOffset: Integer;
begin
  if (FScrollBar = nil) or (FRenderer = nil) then
    Exit;
  Bounds := ClientRect;
  MaximumOffset := FRenderer.MaximumScrollOffset(Bounds);
  FUpdatingScrollBar := True;
  try
    FScrollBar.Visible := MaximumOffset > 0;
    FScrollBar.SetBounds(Max(ClientWidth - ScrollBarWidth, 0), 0,
      ScrollBarWidth, ClientHeight);
    Bounds := LayerBounds;
    MaximumOffset := FRenderer.MaximumScrollOffset(Bounds);
    FRenderer.ScrollOffset := EnsureRange(FRenderer.ScrollOffset, 0,
      MaximumOffset);
    FScrollBar.SmallChange := FRenderer.ScrollStep;
    FScrollBar.LargeChange := Max(Bounds.Height -
      FRenderer.ScrollStep, FRenderer.ScrollStep);
    FScrollBar.SetRange(MaximumOffset, Max(Bounds.Height, 1));
    FScrollBar.Position := MaximumOffset - FRenderer.ScrollOffset;
  finally
    FUpdatingScrollBar := False;
  end;
end;

end.
