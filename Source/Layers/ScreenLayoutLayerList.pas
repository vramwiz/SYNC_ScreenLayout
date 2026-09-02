// レイヤー一覧の描画方式切替、クリック判定、Document接続を担当する。
unit ScreenLayoutLayerList;

interface

uses
  System.Classes, Vcl.Controls, Vcl.Direct2D, ScreenLayoutDocument,
  ScreenLayoutEditCommands, ScreenLayoutEditHistory,
  ScreenLayoutLayerRenderer;

type
  TVectArtLayerListControl = class(TCustomControl)
  private
    FDirect2DEnabled: Boolean;
    FDocument: TVectArtDocument;
    FEditHistory: TVectArtEditHistory;
    FRenderer: TVectArtLayerRenderer;
    FSelectionAnchorIndex: Integer;
    procedure PaintDirect2D;
    procedure PaintGDI;
    procedure SetDocument(const Value: TVectArtDocument);
  protected
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState;
      X, Y: Integer); override;
    procedure Paint; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    property Document: TVectArtDocument read FDocument write SetDocument;
    property EditHistory: TVectArtEditHistory read FEditHistory
      write FEditHistory;
  end;

implementation

uses
  System.Types, Vcl.Graphics;

const
  COLOR_LIST_BACKGROUND = TColor($001A1A1A);

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
      end;
      Exit;
    end;
  end;
  inherited MouseDown(Button, Shift, X, Y);
end;

procedure TVectArtLayerListControl.Paint;
begin
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
begin
  Direct2DCanvas := TDirect2DCanvas.Create(Canvas, ClientRect);
  try
    Direct2DCanvas.BeginDraw;
    try
      FRenderer.DrawLayers(Direct2DCanvas, ClientRect);
    finally
      Direct2DCanvas.EndDraw;
    end;
  finally
    Direct2DCanvas.Free;
  end;
end;

procedure TVectArtLayerListControl.PaintGDI;
begin
  FRenderer.DrawLayers(Canvas, ClientRect);
end;

procedure TVectArtLayerListControl.SetDocument(
  const Value: TVectArtDocument);
begin
  if FDocument = Value then
    Exit;
  FDocument := Value;
  FSelectionAnchorIndex := -1;
  FRenderer.Document := Value;
  Invalidate;
end;

end.
