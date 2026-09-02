// レイヤー一覧の描画方式切替、クリック判定、Document接続を担当する。
unit ScreenLayoutLayerList;

interface

uses
  System.Classes, System.Types, Vcl.Controls, Vcl.Direct2D, ScreenLayoutDocument,
  ScreenLayoutEditCommands, ScreenLayoutEditHistory, ScreenLayoutEditorState,
  ScreenLayoutLayerRenderer;

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
    procedure PaintDirect2D;
    procedure PaintGDI;
    procedure SetDocument(const Value: TVectArtDocument);
  protected
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState;
      X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState;
      X, Y: Integer); override;
    procedure Paint; override;
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
  System.Math, Vcl.Graphics, ScreenLayoutLayerStructureCommands;

const
  COLOR_LIST_BACKGROUND = TColor($001A1A1A);
  COLOR_DROP_TARGET = TColor($00D69C4A);
  LAYER_DRAG_THRESHOLD = 5;

constructor TVectArtLayerListControl.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Color := COLOR_LIST_BACKGROUND;
  ControlStyle := ControlStyle + [csOpaque];
  DoubleBuffered := True;
  TabStop := True;
  FDirect2DEnabled := TDirect2DCanvas.Supported;
  FRenderer := TVectArtLayerRenderer.Create;
  FSelectionAnchorIndex := -1;
  FDragCandidateIndex := -1;
  FDragTargetIndex := -1;
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
    Index := FRenderer.LayerIndexAt(ClientRect, Y);
    if Index >= 0 then
    begin
      ItemRect := FRenderer.LayerItemRect(ClientRect, Index);
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
      Index := FRenderer.LayerIndexAt(ClientRect, Y);
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
  if FEditorState <> nil then
    FRenderer.OpenGroup := FEditorState.RootOpenGroup
  else
    FRenderer.OpenGroup := nil;
  if FDirect2DEnabled then
    try
      PaintDirect2D;
      Exit;
    except
      FDirect2DEnabled := False;
    end;
  PaintGDI;
end;

procedure TVectArtLayerListControl.PaintDirect2D;
var
  Direct2DCanvas: TDirect2DCanvas;
  IndicatorY: Integer;
  TargetRect: TRect;
begin
  Direct2DCanvas := TDirect2DCanvas.Create(Canvas, ClientRect);
  try
    Direct2DCanvas.BeginDraw;
    try
      FRenderer.DrawLayers(Direct2DCanvas, ClientRect);
      if FDraggingLayer and (FDragTargetIndex > 0) and
        (FDragTargetIndex <> FDragCandidateIndex) then
      begin
        TargetRect := FRenderer.LayerItemRect(ClientRect,
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
  FRenderer.DrawLayers(Canvas, ClientRect);
  if FDraggingLayer and (FDragTargetIndex > 0) and
    (FDragTargetIndex <> FDragCandidateIndex) then
  begin
    TargetRect := FRenderer.LayerItemRect(ClientRect, FDragTargetIndex);
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
  Invalidate;
end;

end.
