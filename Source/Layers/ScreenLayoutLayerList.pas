// レイヤー一覧の描画方式切替、クリック判定、Document接続を担当する。
unit ScreenLayoutLayerList;

interface

uses
  System.Classes, System.Types, Vcl.Controls, Vcl.Direct2D, Vcl.ExtCtrls,
  ScreenLayoutDocument, ScreenLayoutEditCommands, ScreenLayoutEditHistory,
  ScreenLayoutEditorState, ScreenLayoutLayerRenderer,
  VerticalScrollBarControl;

type
  TScreenLayoutLayerDropMode = (sldmNone, sldmReorder, sldmIntoGroup);

  TVectArtLayerListControl = class(TCustomControl)
  private
    FDirect2DEnabled: Boolean;
    FDocument: TVectArtDocument;
    FEditHistory: TVectArtEditHistory;
    FEditorState: TVectArtEditorState;
    FDragCandidateIndex: Integer;
    FDragStartPoint: TPoint;
    FDraggingLayer: Boolean;
    FDragDropMode: TScreenLayoutLayerDropMode;
    FDragIndicatorY: Integer;
    FDragSourceIndices: TArray<Integer>;
    FDragSourceGroup: TScreenLayoutGroupLayer;
    FDragScrollDirection: Integer;
    FDragScrollTimer: TTimer;
    FDragTargetIndex: Integer;
    FDragTargetGroup: TScreenLayoutGroupLayer;
    FDragTargetParent: TScreenLayoutGroupLayer;
    FDragTargetSourceIndex: Integer;
    FHoverTargetGroup: TScreenLayoutGroupLayer;
    FHoverTimer: TTimer;
    FRenderer: TVectArtLayerRenderer;
    FSelectionAnchorIndex: Integer;
    FScrollBar: TVerticalScrollBarControl;
    FUpdatingScrollBar: Boolean;
    function DragSourcesEditable: Boolean;
    function IsDragSourceLayer(Layer: TVectArtLayer): Boolean;
    function LayerBounds: TRect;
    procedure ResetDragState;
    procedure RestoreDragSourceContext;
    procedure DragScrollTimerTick(Sender: TObject);
    procedure SelectGroupChildRange(AnchorIndex, TargetIndex: Integer;
      KeepExisting: Boolean);
    function SelectedSourceIndices(
      Parent: TScreenLayoutGroupLayer): TArray<Integer>;
    function ScrollBarWidth: Integer;
    procedure ScrollBarChanged(Sender: TObject);
    procedure SetHoverTarget(Value: TScreenLayoutGroupLayer);
    procedure SetDragScrollDirection(Value: Integer);
    procedure SyncRendererContext;
    procedure HoverTimerTick(Sender: TObject);
    procedure ToggleGroupExpanded(Group: TScreenLayoutGroupLayer;
      Parent: TScreenLayoutGroupLayer);
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
  System.Generics.Collections, System.Math, System.SysUtils, Winapi.Windows,
  Vcl.Graphics,
  ScreenLayoutGroupChildCommands;

const
  COLOR_LIST_BACKGROUND = TColor($001A1A1A);
  COLOR_DROP_TARGET = TColor($00D69C4A);
  LAYER_DRAG_THRESHOLD = 5;
  DRAG_SCROLL_INTERVAL = 50;
  DRAG_SCROLL_MARGIN = 28;
  DRAG_SCROLL_PIXELS = 12;
  GROUP_HOVER_OPEN_DELAY = 700;
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
  FDragScrollTimer := TTimer.Create(Self);
  FDragScrollTimer.Enabled := False;
  FDragScrollTimer.Interval := DRAG_SCROLL_INTERVAL;
  FDragScrollTimer.OnTimer := DragScrollTimerTick;
  FHoverTimer := TTimer.Create(Self);
  FHoverTimer.Enabled := False;
  FHoverTimer.Interval := GROUP_HOVER_OPEN_DELAY;
  FHoverTimer.OnTimer := HoverTimerTick;
  FScrollBar := TVerticalScrollBarControl.Create(Self);
  FScrollBar.Parent := Self;
  FScrollBar.Visible := False;
  FScrollBar.OnChange := ScrollBarChanged;
  FSelectionAnchorIndex := -1;
  FDragCandidateIndex := -1;
  FDragDropMode := sldmNone;
  FDragIndicatorY := -1;
  FDragTargetIndex := -1;
  FDragTargetSourceIndex := -1;
end;

procedure TVectArtLayerListControl.DragScrollTimerTick(Sender: TObject);
var
  ClientPoint: TPoint;
  NewOffset: Integer;
  ScreenPoint: TPoint;
begin
  if not FDraggingLayer or (FDragScrollDirection = 0) then
  begin
    SetDragScrollDirection(0);
    Exit;
  end;
  NewOffset := FRenderer.ScrollOffset +
    FDragScrollDirection * DRAG_SCROLL_PIXELS;
  FRenderer.ScrollOffset := NewOffset;
  UpdateScrollBar;
  if FRenderer.ScrollOffset = NewOffset then
  begin
    GetCursorPos(ScreenPoint);
    ClientPoint := ScreenToClient(ScreenPoint);
    MouseMove([ssLeft], ClientPoint.X, ClientPoint.Y);
  end
  else
    SetDragScrollDirection(0);
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

function TVectArtLayerListControl.DragSourcesEditable: Boolean;
var
  Index: Integer;
begin
  Result := Length(FDragSourceIndices) > 0;
  if not Result then
    Exit;
  for Index in FDragSourceIndices do
    if FDragSourceGroup <> nil then
    begin
      if (Index < 0) or (Index >= FDragSourceGroup.ChildCount) or
        FDragSourceGroup[Index].Locked then
        Exit(False);
    end
    else if (FDocument = nil) or (Index <= 0) or
      (Index >= FDocument.LayerCount) or FDocument[Index].Locked then
      Exit(False);
end;

function TVectArtLayerListControl.IsDragSourceLayer(
  Layer: TVectArtLayer): Boolean;
var
  Index: Integer;
begin
  Result := False;
  for Index in FDragSourceIndices do
    if FDragSourceGroup <> nil then
    begin
      if (Index >= 0) and (Index < FDragSourceGroup.ChildCount) and
        (FDragSourceGroup[Index] = Layer) then
        Exit(True);
    end
    else if (FDocument <> nil) and (Index > 0) and
      (Index < FDocument.LayerCount) and (FDocument[Index] = Layer) then
      Exit(True);
end;

procedure TVectArtLayerListControl.HoverTimerTick(Sender: TObject);
var
  Target: TScreenLayoutGroupLayer;
begin
  FHoverTimer.Enabled := False;
  Target := FHoverTargetGroup;
  FHoverTargetGroup := nil;
  if not FDraggingLayer or (Target = nil) or (FEditorState = nil) then
    Exit;
  FEditorState.OpenGroupInDocument(FDocument, Target);
  if FEditorState.OpenGroup <> Target then
    Exit;
  FDragDropMode := sldmIntoGroup;
  FDragTargetGroup := Target;
  FDragTargetIndex := -1;
  FSelectionAnchorIndex := -1;
  SyncRendererContext;
  UpdateScrollBar;
  Invalidate;
end;

procedure TVectArtLayerListControl.ToggleGroupExpanded(
  Group: TScreenLayoutGroupLayer; Parent: TScreenLayoutGroupLayer);
begin
  if (FEditorState = nil) or (Group = nil) then
    Exit;
  if FEditorState.IsGroupInOpenPath(Group) then
  begin
    if Parent <> nil then
      FEditorState.OpenGroupInDocument(FDocument, Parent)
    else
      FEditorState.OpenGroup := nil;
  end
  else
    FEditorState.OpenGroupInDocument(FDocument, Group);
  FSelectionAnchorIndex := -1;
  ResetDragState;
  Invalidate;
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
  Command: TVectArtEditCommand;
  Parent: TScreenLayoutGroupLayer;
  SourceIndex: Integer;
begin
  if (Button = mbLeft) and (FDocument <> nil) then
  begin
    SyncRendererContext;
    if CanFocus then
      SetFocus;
    Index := FRenderer.LayerIndexAt(LayerBounds, Y);
    if Index > 0 then
    begin
      ItemRect := FRenderer.LayerItemRect(LayerBounds, Index);
      Layer := FRenderer.LayerAt(Index);
      Parent := FRenderer.LayerParentAt(Index);
      SourceIndex := FRenderer.LayerSourceIndexAt(Index);
      if (Layer is TScreenLayoutGroupLayer) and
        PtInRect(FRenderer.ExpandButtonRect(ItemRect), Point(X, Y)) then
      begin
        if ssDouble in Shift then
          ToggleGroupExpanded(TScreenLayoutGroupLayer(Layer), Parent);
        Exit;
      end;
      if (ssDouble in Shift) and (Layer is TScreenLayoutGroupLayer) and
        (FEditorState <> nil) then
      begin
        ToggleGroupExpanded(TScreenLayoutGroupLayer(Layer), Parent);
        Exit;
      end;
      if PtInRect(FRenderer.VisibilityButtonRect(ItemRect), Point(X, Y)) then
      begin
        NewValue := not Layer.Visible;
        if Parent <> nil then
          Command := TScreenLayoutGroupChildBooleanCommand.Create(FDocument,
            Layer, vlbpVisible, not NewValue, NewValue)
        else
          Command := TVectArtLayerBooleanCommand.Create(FDocument,
            SourceIndex,
            vlbpVisible, not NewValue, NewValue);
        Command.Execute;
        if FEditHistory <> nil then
          FEditHistory.AddApplied(Command)
        else
          Command.Free;
        Exit;
      end;
      if PtInRect(FRenderer.LockButtonRect(ItemRect), Point(X, Y)) then
      begin
        NewValue := not Layer.Locked;
        if Parent <> nil then
          Command := TScreenLayoutGroupChildBooleanCommand.Create(FDocument,
            Layer, vlbpLocked, not NewValue, NewValue)
        else
          Command := TVectArtLayerBooleanCommand.Create(FDocument,
            SourceIndex,
            vlbpLocked, not NewValue, NewValue);
        Command.Execute;
        if FEditHistory <> nil then
          FEditHistory.AddApplied(Command)
        else
          Command.Free;
        Exit;
      end;
      if (Layer is TScreenLayoutGroupLayer) and (FEditorState <> nil) and
        FEditorState.IsGroupInOpenPath(TScreenLayoutGroupLayer(Layer)) then
        Exit;
      if Parent <> nil then
      begin
        if FEditorState.OpenGroup <> Parent then
          FEditorState.OpenGroupInDocument(FDocument, Parent);
        if ssShift in Shift then
        begin
          if FSelectionAnchorIndex <= 0 then
            FSelectionAnchorIndex := SourceIndex + 1;
          SelectGroupChildRange(FSelectionAnchorIndex, SourceIndex + 1,
            ssCtrl in Shift);
        end
        else if ssCtrl in Shift then
        begin
          FEditorState.ToggleOpenGroupChild(Layer);
          FSelectionAnchorIndex := SourceIndex + 1;
        end
        else
        begin
          if not FEditorState.IsOpenGroupChildSelected(Layer) or
            (FEditorState.OpenGroupChildCount <= 1) then
            FEditorState.OpenGroupChild := Layer;
          FSelectionAnchorIndex := SourceIndex + 1;
        end;
      end
      else if ssShift in Shift then
      begin
        FEditorState.OpenGroup := nil;
        if FSelectionAnchorIndex <= 0 then
          if FDocument.SelectedIndex > 0 then
            FSelectionAnchorIndex := FDocument.SelectedIndex
          else
            FSelectionAnchorIndex := SourceIndex;
        FDocument.SelectLayerRange(FSelectionAnchorIndex, SourceIndex,
          ssCtrl in Shift);
      end
      else if ssCtrl in Shift then
      begin
        FEditorState.OpenGroup := nil;
        FDocument.ToggleSelectedLayer(SourceIndex);
        FSelectionAnchorIndex := SourceIndex;
      end
      else
      begin
        FEditorState.OpenGroup := nil;
        if not FDocument.IsLayerSelected(SourceIndex) or
          (FDocument.SelectionCount <= 1) then
          FDocument.SelectedIndex := SourceIndex;
        FSelectionAnchorIndex := SourceIndex;
      end;
      if not (ssShift in Shift) and not (ssCtrl in Shift) and
        not Layer.Locked then
      begin
        FDragCandidateIndex := Index;
        FDragDropMode := sldmReorder;
        FDragSourceGroup := Parent;
        FDragSourceIndices := SelectedSourceIndices(Parent);
        if not DragSourcesEditable then
        begin
          ResetDragState;
          Exit;
        end;
        FDragTargetIndex := Index;
        FDragTargetGroup := nil;
        FDragTargetParent := Parent;
        FDragTargetSourceIndex := SourceIndex;
        FDragStartPoint := Point(X, Y);
        MouseCapture := True;
      end;
      Exit;
    end;
  end;
  inherited MouseDown(Button, Shift, X, Y);
end;

procedure TVectArtLayerListControl.MouseMove(Shift: TShiftState;
  X, Y: Integer);
var
  I: Integer;
  Index: Integer;
  ItemRect: TRect;
  Layer: TVectArtLayer;
  MiddleMargin: Integer;
  OpenGroup: TScreenLayoutGroupLayer;
  TargetSourceIndex: Integer;
begin
  if (FDragCandidateIndex > 0) and (ssLeft in Shift) then
  begin
    if not FDraggingLayer and
      ((Abs(X - FDragStartPoint.X) >= LAYER_DRAG_THRESHOLD) or
       (Abs(Y - FDragStartPoint.Y) >= LAYER_DRAG_THRESHOLD)) then
      FDraggingLayer := True;
    if FDraggingLayer then
    begin
      if Y < LayerBounds.Top + MulDiv(DRAG_SCROLL_MARGIN,
        CurrentPPI, 96) then
        SetDragScrollDirection(1)
      else if Y >= LayerBounds.Bottom - MulDiv(DRAG_SCROLL_MARGIN,
        CurrentPPI, 96) then
        SetDragScrollDirection(-1)
      else
        SetDragScrollDirection(0);
      OpenGroup := nil;
      if FEditorState <> nil then
        OpenGroup := FEditorState.OpenGroup;
      FDragDropMode := sldmNone;
      FDragTargetGroup := nil;
      Index := FRenderer.LayerIndexAt(LayerBounds, Y);
      if Index > 0 then
      begin
        FDragTargetIndex := Index;
        Layer := FRenderer.LayerAt(Index);
        FDragTargetParent := FRenderer.LayerParentAt(Index);
        TargetSourceIndex := FRenderer.LayerSourceIndexAt(Index);
        ItemRect := FRenderer.LayerItemRect(LayerBounds, Index);
        MiddleMargin := Max(ItemRect.Height div 4, 1);
        if (Layer is TScreenLayoutGroupLayer) and not Layer.Locked and
          not IsDragSourceLayer(Layer) and
          (Y >= ItemRect.Top + MiddleMargin) and
          (Y < ItemRect.Bottom - MiddleMargin) then
        begin
          FDragDropMode := sldmIntoGroup;
          FDragTargetGroup := TScreenLayoutGroupLayer(Layer);
          SetHoverTarget(FDragTargetGroup);
        end
        else
        begin
          SetHoverTarget(nil);
          if not IsDragSourceLayer(Layer) then
          begin
            FDragDropMode := sldmReorder;
            if Y < ItemRect.Top + ItemRect.Height div 2 then
            begin
              FDragTargetSourceIndex := TargetSourceIndex + 1;
              FDragIndicatorY := ItemRect.Top;
            end
            else
            begin
              FDragTargetSourceIndex := TargetSourceIndex;
              FDragIndicatorY := ItemRect.Bottom;
            end;
            if FDragTargetParent = FDragSourceGroup then
              for I in FDragSourceIndices do
                if I < FDragTargetSourceIndex then
                  Dec(FDragTargetSourceIndex);
          end;
        end;
      end;
      if Index <= 0 then
      begin
        SetHoverTarget(nil);
        if OpenGroup <> FDragSourceGroup then
        begin
          FDragDropMode := sldmIntoGroup;
          FDragTargetGroup := OpenGroup;
          FDragTargetIndex := -1;
        end;
      end;
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
  Command: TVectArtEditCommand;
  DestinationIndex: Integer;
  MoveApplied: Boolean;
begin
  if (Button = mbLeft) and (FDragCandidateIndex > 0) then
  begin
    MouseCapture := False;
    MoveApplied := False;
    if FDraggingLayer and (FEditorState <> nil) and
      (FDragDropMode = sldmIntoGroup) and
      (FDragTargetGroup <> nil) then
    begin
      DestinationIndex := FDragTargetGroup.ChildCount;
      if FDragTargetGroup = FDragSourceGroup then
        Dec(DestinationIndex, Length(FDragSourceIndices));
      Command := TScreenLayoutReparentLayersCommand.Create(FDocument,
        FEditorState, FDragSourceGroup, FDragSourceIndices, FDragTargetGroup,
        DestinationIndex);
      Command.Execute;
      if FEditHistory <> nil then
        FEditHistory.AddApplied(Command)
      else
        Command.Free;
      MoveApplied := True;
      FSelectionAnchorIndex := -1;
    end
    else if FDraggingLayer and (FDragDropMode = sldmReorder) and
      (FDragTargetSourceIndex >= 0) then
    begin
      Command := TScreenLayoutReparentLayersCommand.Create(FDocument,
        FEditorState, FDragSourceGroup, FDragSourceIndices,
        FDragTargetParent, FDragTargetSourceIndex);
      Command.Execute;
      if FEditHistory <> nil then
        FEditHistory.AddApplied(Command)
      else
        Command.Free;
      MoveApplied := True;
      FSelectionAnchorIndex := -1;
    end;
    if FDraggingLayer and not MoveApplied then
      RestoreDragSourceContext;
    ResetDragState;
    Invalidate;
    Exit;
  end;
  inherited MouseUp(Button, Shift, X, Y);
end;

procedure TVectArtLayerListControl.Paint;
begin
  SyncRendererContext;
  UpdateScrollBar;
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

procedure TVectArtLayerListControl.ResetDragState;
begin
  SetDragScrollDirection(0);
  SetHoverTarget(nil);
  MouseCapture := False;
  FDragCandidateIndex := -1;
  FDragDropMode := sldmNone;
  FDragIndicatorY := -1;
  SetLength(FDragSourceIndices, 0);
  FDragSourceGroup := nil;
  FDragTargetIndex := -1;
  FDragTargetGroup := nil;
  FDragTargetParent := nil;
  FDragTargetSourceIndex := -1;
  FDraggingLayer := False;
  Cursor := crDefault;
end;

procedure TVectArtLayerListControl.RestoreDragSourceContext;
begin
  if FEditorState = nil then
    Exit;
  if FDragSourceGroup <> nil then
    FEditorState.OpenGroupInDocument(FDocument, FDragSourceGroup)
  else
    FEditorState.OpenGroup := nil;
end;

function TVectArtLayerListControl.SelectedSourceIndices(
  Parent: TScreenLayoutGroupLayer): TArray<Integer>;
var
  I: Integer;
  Indices: TList<Integer>;
begin
  if Parent = nil then
    Exit(FDocument.GetSelectedLayerIndices);
  Indices := TList<Integer>.Create;
  try
    for I := 0 to Parent.ChildCount - 1 do
      if FEditorState.IsOpenGroupChildSelected(Parent[I]) then
        Indices.Add(I);
    Result := Indices.ToArray;
  finally
    Indices.Free;
  end;
end;

procedure TVectArtLayerListControl.SelectGroupChildRange(AnchorIndex,
  TargetIndex: Integer; KeepExisting: Boolean);
var
  I: Integer;
  FirstIndex: Integer;
  LastIndex: Integer;
  Layer: TVectArtLayer;
  Selected: TList<TVectArtLayer>;
begin
  if (FEditorState = nil) or (FEditorState.OpenGroup = nil) then
    Exit;
  Selected := TList<TVectArtLayer>.Create;
  try
    if KeepExisting then
      for Layer in FEditorState.GetOpenGroupChildren do
        Selected.Add(Layer);
    FirstIndex := Min(AnchorIndex, TargetIndex) - 1;
    LastIndex := Max(AnchorIndex, TargetIndex) - 1;
    for I := FirstIndex to LastIndex do
      if (I >= 0) and (I < FEditorState.OpenGroup.ChildCount) then
      begin
        Layer := FEditorState.OpenGroup[I];
        if Selected.IndexOf(Layer) < 0 then
          Selected.Add(Layer);
      end;
    FEditorState.SetOpenGroupChildren(Selected.ToArray);
  finally
    Selected.Free;
  end;
end;

procedure TVectArtLayerListControl.SyncRendererContext;
begin
  FRenderer.EditorState := FEditorState;
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
      if FDraggingLayer and (FDragDropMode = sldmIntoGroup) and
        (FDragTargetIndex > 0) then
      begin
        TargetRect := FRenderer.LayerItemRect(LayerBounds,
          FDragTargetIndex);
        Direct2DCanvas.Brush.Style := bsClear;
        Direct2DCanvas.Pen.Color := COLOR_DROP_TARGET;
        Direct2DCanvas.Pen.Width := 3;
        Direct2DCanvas.Rectangle(TargetRect);
        Direct2DCanvas.Pen.Width := 1;
      end
      else if FDraggingLayer and (FDragDropMode = sldmReorder) and
        (FDragTargetIndex > 0) and
        (FDragTargetIndex <> FDragCandidateIndex) then
      begin
        TargetRect := FRenderer.LayerItemRect(LayerBounds,
          FDragTargetIndex);
        IndicatorY := FDragIndicatorY;
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
  if FDraggingLayer and (FDragDropMode = sldmIntoGroup) and
    (FDragTargetIndex > 0) then
  begin
    TargetRect := FRenderer.LayerItemRect(LayerBounds, FDragTargetIndex);
    Canvas.Brush.Style := bsClear;
    Canvas.Pen.Color := COLOR_DROP_TARGET;
    Canvas.Pen.Width := 3;
    Canvas.Rectangle(TargetRect);
    Canvas.Pen.Width := 1;
  end
  else if FDraggingLayer and (FDragDropMode = sldmReorder) and
    (FDragTargetIndex > 0) and
    (FDragTargetIndex <> FDragCandidateIndex) then
  begin
    TargetRect := FRenderer.LayerItemRect(LayerBounds, FDragTargetIndex);
    IndicatorY := FDragIndicatorY;
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

procedure TVectArtLayerListControl.SetHoverTarget(
  Value: TScreenLayoutGroupLayer);
begin
  if FHoverTargetGroup = Value then
    Exit;
  FHoverTimer.Enabled := False;
  FHoverTargetGroup := Value;
  FHoverTimer.Enabled := Value <> nil;
end;

procedure TVectArtLayerListControl.SetDragScrollDirection(Value: Integer);
begin
  Value := Sign(Value);
  if FDragScrollDirection = Value then
    Exit;
  FDragScrollTimer.Enabled := False;
  FDragScrollDirection := Value;
  FDragScrollTimer.Enabled := Value <> 0;
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
  SyncRendererContext;
  Bounds := LayerBounds;
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
