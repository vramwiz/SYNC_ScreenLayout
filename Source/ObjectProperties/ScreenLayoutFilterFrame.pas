// Provides the self-contained filter stack UI and its list interactions.
// Filter rendering and parameter-detail editors are intentionally kept elsewhere.
unit ScreenLayoutFilterFrame;

interface

uses
  System.Classes, System.Types, Vcl.Controls, Vcl.ExtCtrls, Vcl.Forms,
  Vcl.Graphics, Vcl.Menus, Vcl.StdCtrls, ScreenLayoutContext,
  ScreenLayoutDocument, ScreenLayoutFilterDetailsFrame, ScreenLayoutFilters;

type
  TScreenLayoutFilterIndexEvent = procedure(Sender: TObject;
    Index: Integer) of object;
  TScreenLayoutFilterMoveEvent = procedure(Sender: TObject;
    FromIndex, ToIndex: Integer) of object;
  TScreenLayoutFilterValueEvent = procedure(Sender: TObject;
    Index: Integer; Value: Single) of object;

  TScreenLayoutFilterListControl = class(TCustomControl)
  private
    FDragCandidateIndex: Integer;
    FDragStartPoint: TPoint;
    FDragTargetIndex: Integer;
    FDragging: Boolean;
    FLayer: TVectArtLayer;
    FOnMoveFilter: TScreenLayoutFilterMoveEvent;
    FOnSelectionChanged: TNotifyEvent;
    FOnToggleEnabled: TScreenLayoutFilterIndexEvent;
    FOnValueChanged: TScreenLayoutFilterValueEvent;
    FOnValueGestureEnd: TScreenLayoutFilterIndexEvent;
    FOnValueGestureStart: TScreenLayoutFilterIndexEvent;
    FSelectedIndex: Integer;
    FSliderDragIndex: Integer;
    function FilterIndexAt(Y: Integer): Integer;
    function HandleRect(Index: Integer): TRect;
    function RowHeight: Integer;
    function SliderRect(Index: Integer): TRect;
    function SwitchRect(Index: Integer): TRect;
    procedure UpdateSliderValue(Index, X: Integer);
    procedure SetLayer(const Value: TVectArtLayer);
    procedure SetSelectedIndex(const Value: Integer);
  protected
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState;
      X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState;
      X, Y: Integer); override;
    procedure Paint; override;
  public
    constructor Create(AOwner: TComponent); override;
    property Layer: TVectArtLayer read FLayer write SetLayer;
    property OnMoveFilter: TScreenLayoutFilterMoveEvent read FOnMoveFilter
      write FOnMoveFilter;
    property OnSelectionChanged: TNotifyEvent read FOnSelectionChanged
      write FOnSelectionChanged;
    property OnToggleEnabled: TScreenLayoutFilterIndexEvent
      read FOnToggleEnabled write FOnToggleEnabled;
    property OnValueChanged: TScreenLayoutFilterValueEvent
      read FOnValueChanged write FOnValueChanged;
    property OnValueGestureEnd: TScreenLayoutFilterIndexEvent
      read FOnValueGestureEnd write FOnValueGestureEnd;
    property OnValueGestureStart: TScreenLayoutFilterIndexEvent
      read FOnValueGestureStart write FOnValueGestureStart;
    property SelectedIndex: Integer read FSelectedIndex write SetSelectedIndex;
  end;

  TScreenLayoutFilterFrame = class(TFrame)
  private
    FAddButton: TPanel;
    FAddMenu: TPopupMenu;
    FCaptionLabel: TLabel;
    FContext: IVectArtDesignerContext;
    FDeleteButton: TPanel;
    FDetailsFrame: TScreenLayoutFilterDetailsFrame;
    FFilterList: TScreenLayoutFilterListControl;
    FHeaderPanel: TPanel;
    FToolbarPanel: TPanel;
    FValueGestureFilter: TScreenLayoutFilter;
    FValueGestureOldParameters: TScreenLayoutFilter;
    procedure AddButtonClick(Sender: TObject);
    procedure AddFilterClick(Sender: TObject);
    procedure DeleteButtonClick(Sender: TObject);
    procedure FilterMoved(Sender: TObject; FromIndex, ToIndex: Integer);
    procedure FilterSelectionChanged(Sender: TObject);
    procedure FilterToggleEnabled(Sender: TObject; Index: Integer);
    procedure FilterValueChanged(Sender: TObject; Index: Integer;
      Value: Single);
    procedure FilterValueGestureEnd(Sender: TObject; Index: Integer);
    procedure FilterValueGestureStart(Sender: TObject; Index: Integer);
    procedure SetContext(const Value: IVectArtDesignerContext);
    procedure UpdateControlState;
  public
    // Creates the header, filter-list client area, and bottom-aligned detail area.
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    // Refreshes the stack from the current single layer or group selection.
    procedure RefreshFromDocument;
    property Context: IVectArtDesignerContext read FContext write SetContext;
  end;

implementation

uses
  System.Math, Winapi.Windows, ScreenLayoutEditCommands,
  ScreenLayoutEditorState, ScreenLayoutFilterCommands,
  ScreenLayoutObjectPropertySelection;

{$R ScreenLayoutFilterFrame.dfm}

const
  COLOR_BACKGROUND       = TColor($00212121);
  COLOR_BUTTON           = TColor($00303030);
  COLOR_DISABLED         = TColor($00606060);
  COLOR_DRAG_HANDLE      = TColor($00707070);
  COLOR_HEADER           = TColor($00292929);
  COLOR_ROW              = TColor($00252525);
  COLOR_ROW_SELECTED     = TColor($0042382E);
  COLOR_SLIDER           = TColor($00404040);
  COLOR_SLIDER_VALUE     = TColor($00D69C4A);
  COLOR_SWITCH_OFF       = TColor($00505050);
  COLOR_SWITCH_ON        = TColor($006AA84F);
  COLOR_TEXT_PRIMARY     = TColor($00EEEEEE);
  COLOR_TEXT_SECONDARY   = TColor($00909090);
  CAPTION_HEIGHT         = 28;
  DETAIL_HEIGHT          = 88;
  DRAG_THRESHOLD         = 5;
  FILTER_ROW_HEIGHT      = 38;
  HEADER_HEIGHT          = 58;

function FilterColor(Filter: TScreenLayoutFilter;
  out Value: TColor): Boolean;
begin
  Result := True;
  if Filter is TScreenLayoutOutlineFilter then
    Value := TScreenLayoutOutlineFilter(Filter).Color
  else if Filter is TScreenLayoutShadowFilter then
    Value := TScreenLayoutShadowFilter(Filter).Color
  else
  begin
    Value := clNone;
    Result := False;
  end;
end;

function FilterRepresentativeRatio(Filter: TScreenLayoutFilter): Single;
begin
  if Filter is TScreenLayoutOutlineFilter then
    Result := TScreenLayoutOutlineFilter(Filter).Width / 40.0
  else if Filter is TScreenLayoutShadowFilter then
    Result := TScreenLayoutShadowFilter(Filter).BlurRadius / 50.0
  else if Filter is TScreenLayoutBlurFilter then
    Result := TScreenLayoutBlurFilter(Filter).Radius / 50.0
  else
    Result := 0.0;
  Result := EnsureRange(Result, 0.0, 1.0);
end;

function FilterRepresentativeMaximum(
  Filter: TScreenLayoutFilter): Single;
begin
  if Filter is TScreenLayoutOutlineFilter then
    Result := 40.0
  else
    Result := 50.0;
end;

{ TScreenLayoutFilterListControl }

constructor TScreenLayoutFilterListControl.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Align := alClient;
  Color := COLOR_BACKGROUND;
  ControlStyle := ControlStyle + [csOpaque];
  DoubleBuffered := True;
  ParentBackground := False;
  FDragCandidateIndex := -1;
  FDragTargetIndex := -1;
  FSelectedIndex := -1;
  FSliderDragIndex := -1;
end;

function TScreenLayoutFilterListControl.FilterIndexAt(Y: Integer): Integer;
begin
  Result := Y div RowHeight;
  if (FLayer = nil) or (Result < 0) or (Result >= FLayer.FilterCount) then
    Result := -1;
end;

function TScreenLayoutFilterListControl.HandleRect(Index: Integer): TRect;
var
  Top: Integer;
begin
  Top := Index * RowHeight;
  Result := Rect(MulDiv(5, CurrentPPI, 96),
    Top + MulDiv(12, CurrentPPI, 96), MulDiv(17, CurrentPPI, 96),
    Top + MulDiv(26, CurrentPPI, 96));
end;

procedure TScreenLayoutFilterListControl.MouseDown(Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
var
  Index: Integer;
begin
  inherited;
  if Button <> mbLeft then
    Exit;
  Index := FilterIndexAt(Y);
  SelectedIndex := Index;
  if Index < 0 then
    Exit;
  if PtInRect(SwitchRect(Index), Point(X, Y)) then
  begin
    if Assigned(FOnToggleEnabled) then
      FOnToggleEnabled(Self, Index);
    Exit;
  end;
  if PtInRect(SliderRect(Index), Point(X, Y)) then
  begin
    FSliderDragIndex := Index;
    MouseCapture := True;
    if Assigned(FOnValueGestureStart) then
      FOnValueGestureStart(Self, Index);
    UpdateSliderValue(Index, X);
    Exit;
  end;
  if PtInRect(HandleRect(Index), Point(X, Y)) then
  begin
    FDragCandidateIndex := Index;
    FDragStartPoint := Point(X, Y);
    FDragTargetIndex := Index;
  end;
end;

procedure TScreenLayoutFilterListControl.MouseMove(Shift: TShiftState;
  X, Y: Integer);
var
  TargetIndex: Integer;
begin
  inherited;
  if (ssLeft in Shift) and (FSliderDragIndex >= 0) then
  begin
    UpdateSliderValue(FSliderDragIndex, X);
    Exit;
  end;
  if not (ssLeft in Shift) or (FDragCandidateIndex < 0) or
    (FLayer = nil) then
    Exit;
  if not FDragging and
    (Abs(X - FDragStartPoint.X) < DRAG_THRESHOLD) and
    (Abs(Y - FDragStartPoint.Y) < DRAG_THRESHOLD) then
    Exit;
  FDragging := True;
  TargetIndex := EnsureRange(Y div RowHeight, 0, FLayer.FilterCount - 1);
  if FDragTargetIndex <> TargetIndex then
  begin
    FDragTargetIndex := TargetIndex;
    Invalidate;
  end;
end;

procedure TScreenLayoutFilterListControl.MouseUp(Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
var
  FromIndex: Integer;
  ToIndex: Integer;
begin
  inherited;
  if Button <> mbLeft then
    Exit;
  if FSliderDragIndex >= 0 then
  begin
    UpdateSliderValue(FSliderDragIndex, X);
    if Assigned(FOnValueGestureEnd) then
      FOnValueGestureEnd(Self, FSliderDragIndex);
    FSliderDragIndex := -1;
    MouseCapture := False;
    Exit;
  end;
  FromIndex := FDragCandidateIndex;
  ToIndex := FDragTargetIndex;
  FDragCandidateIndex := -1;
  FDragTargetIndex := -1;
  if FDragging and (FromIndex >= 0) and (ToIndex >= 0) and
    (FromIndex <> ToIndex) and Assigned(FOnMoveFilter) then
    FOnMoveFilter(Self, FromIndex, ToIndex);
  FDragging := False;
  Invalidate;
end;

procedure TScreenLayoutFilterListControl.Paint;
var
  ColorRect: TRect;
  ColorValue: TColor;
  Filter: TScreenLayoutFilter;
  Handle: TRect;
  I: Integer;
  KnobRadius: Integer;
  KnobX: Integer;
  KnobY: Integer;
  RowRect: TRect;
  SliderRect: TRect;
  SwitchBounds: TRect;
  TextRect: TRect;
begin
  Canvas.Brush.Color := COLOR_BACKGROUND;
  Canvas.FillRect(ClientRect);
  Canvas.Font.Name := 'Segoe UI';
  Canvas.Font.Height := -12;
  Canvas.Brush.Style := bsSolid;
  if (FLayer = nil) or (FLayer.FilterCount = 0) then
  begin
    Canvas.Font.Color := COLOR_TEXT_SECONDARY;
    Canvas.Brush.Style := bsClear;
    TextRect := ClientRect;
    DrawText(Canvas.Handle, 'No filters', -1, TextRect,
      DT_CENTER or DT_VCENTER or DT_SINGLELINE or DT_NOPREFIX);
    Exit;
  end;

  for I := 0 to FLayer.FilterCount - 1 do
  begin
    Filter := FLayer.Filters[I];
    RowRect := Rect(0, I * RowHeight, ClientWidth,
      (I + 1) * RowHeight - 1);
    if I = FSelectedIndex then
      Canvas.Brush.Color := COLOR_ROW_SELECTED
    else
      Canvas.Brush.Color := COLOR_ROW;
    Canvas.FillRect(RowRect);

    Handle := HandleRect(I);
    Canvas.Brush.Color := COLOR_DRAG_HANDLE;
    Canvas.Pen.Color := COLOR_DRAG_HANDLE;
    Canvas.Rectangle(Handle);

    SwitchBounds := SwitchRect(I);
    if Filter.Enabled then
    begin
      Canvas.Brush.Color := COLOR_SWITCH_ON;
      Canvas.Pen.Color := COLOR_SWITCH_ON;
    end
    else
    begin
      Canvas.Brush.Color := COLOR_SWITCH_OFF;
      Canvas.Pen.Color := COLOR_SWITCH_OFF;
    end;
    Canvas.RoundRect(SwitchBounds.Left, SwitchBounds.Top,
      SwitchBounds.Right, SwitchBounds.Bottom,
      SwitchBounds.Height, SwitchBounds.Height);

    TextRect := Rect(MulDiv(48, CurrentPPI, 96), RowRect.Top,
      MulDiv(96, CurrentPPI, 96), RowRect.Bottom);
    Canvas.Font.Color := COLOR_TEXT_PRIMARY;
    Canvas.Brush.Style := bsClear;
    DrawText(Canvas.Handle, PChar(Filter.DisplayName), -1, TextRect,
      DT_LEFT or DT_VCENTER or DT_SINGLELINE or DT_END_ELLIPSIS or
      DT_NOPREFIX);
    Canvas.Brush.Style := bsSolid;

    ColorRect := Rect(Max(ClientWidth - MulDiv(24, CurrentPPI, 96),
      MulDiv(104, CurrentPPI, 96)), RowRect.Top + MulDiv(9, CurrentPPI, 96),
      ClientWidth - MulDiv(6, CurrentPPI, 96),
      RowRect.Bottom - MulDiv(9, CurrentPPI, 96));
    SliderRect := Self.SliderRect(I);
    InflateRect(SliderRect, 0, -7);
    if SliderRect.Right > SliderRect.Left then
    begin
      KnobX := SliderRect.Left + Round(SliderRect.Width *
        FilterRepresentativeRatio(Filter));
      KnobY := (SliderRect.Top + SliderRect.Bottom) div 2;
      Canvas.Brush.Color := COLOR_SLIDER;
      Canvas.FillRect(SliderRect);
      SliderRect.Right := KnobX;
      Canvas.Brush.Color := COLOR_SLIDER_VALUE;
      Canvas.FillRect(SliderRect);
      KnobRadius := MulDiv(6, CurrentPPI, 96);
      Canvas.Brush.Color := clWhite;
      Canvas.Pen.Color := clBlack;
      Canvas.Pen.Width := Max(MulDiv(2, CurrentPPI, 96), 1);
      Canvas.Ellipse(KnobX - KnobRadius, KnobY - KnobRadius,
        KnobX + KnobRadius + 1, KnobY + KnobRadius + 1);
      Canvas.Pen.Width := 1;
    end;
    if FilterColor(Filter, ColorValue) then
    begin
      Canvas.Brush.Color := ColorValue;
      Canvas.Pen.Color := COLOR_TEXT_SECONDARY;
      Canvas.Rectangle(ColorRect);
    end;

    if FDragging and (I = FDragTargetIndex) then
    begin
      Canvas.Pen.Color := COLOR_SLIDER_VALUE;
      Canvas.Pen.Width := 2;
      Canvas.MoveTo(RowRect.Left, RowRect.Top);
      Canvas.LineTo(RowRect.Right, RowRect.Top);
      Canvas.Pen.Width := 1;
    end;
  end;
end;

function TScreenLayoutFilterListControl.SliderRect(Index: Integer): TRect;
var
  ColorLeft: Integer;
  Top: Integer;
begin
  Top := Index * RowHeight;
  ColorLeft := Max(ClientWidth - MulDiv(24, CurrentPPI, 96),
    MulDiv(104, CurrentPPI, 96));
  Result := Rect(MulDiv(100, CurrentPPI, 96),
    Top + MulDiv(10, CurrentPPI, 96),
    ColorLeft - MulDiv(4, CurrentPPI, 96),
    Top + MulDiv(28, CurrentPPI, 96));
end;

function TScreenLayoutFilterListControl.RowHeight: Integer;
begin
  Result := MulDiv(FILTER_ROW_HEIGHT, CurrentPPI, 96);
end;

procedure TScreenLayoutFilterListControl.SetLayer(
  const Value: TVectArtLayer);
begin
  if FLayer = Value then
    Exit;
  FLayer := Value;
  FSelectedIndex := -1;
  FDragCandidateIndex := -1;
  FSliderDragIndex := -1;
  FDragging := False;
  Invalidate;
  if Assigned(FOnSelectionChanged) then
    FOnSelectionChanged(Self);
end;

procedure TScreenLayoutFilterListControl.UpdateSliderValue(Index,
  X: Integer);
var
  Bounds: TRect;
  Ratio: Single;
begin
  if (FLayer = nil) or (Index < 0) or (Index >= FLayer.FilterCount) then
    Exit;
  Bounds := SliderRect(Index);
  if Bounds.Width <= 0 then
    Exit;
  Ratio := EnsureRange((X - Bounds.Left) / Bounds.Width, 0.0, 1.0);
  if Assigned(FOnValueChanged) then
    FOnValueChanged(Self, Index,
      Ratio * FilterRepresentativeMaximum(FLayer.Filters[Index]));
end;

procedure TScreenLayoutFilterListControl.SetSelectedIndex(
  const Value: Integer);
var
  NewValue: Integer;
begin
  NewValue := Value;
  if (FLayer = nil) or (NewValue < 0) or
    (NewValue >= FLayer.FilterCount) then
    NewValue := -1;
  if FSelectedIndex = NewValue then
    Exit;
  FSelectedIndex := NewValue;
  Invalidate;
  if Assigned(FOnSelectionChanged) then
    FOnSelectionChanged(Self);
end;

function TScreenLayoutFilterListControl.SwitchRect(Index: Integer): TRect;
var
  Top: Integer;
begin
  Top := Index * RowHeight;
  Result := Rect(MulDiv(22, CurrentPPI, 96),
    Top + MulDiv(12, CurrentPPI, 96), MulDiv(43, CurrentPPI, 96),
    Top + MulDiv(26, CurrentPPI, 96));
end;

{ TScreenLayoutFilterFrame }

procedure TScreenLayoutFilterFrame.AddButtonClick(Sender: TObject);
var
  PopupPoint: TPoint;
begin
  if not FAddButton.Enabled then
    Exit;
  PopupPoint := FAddButton.ClientToScreen(Point(0, FAddButton.Height));
  FAddMenu.Popup(PopupPoint.X, PopupPoint.Y);
end;

procedure TScreenLayoutFilterFrame.AddFilterClick(Sender: TObject);
var
  Command: TScreenLayoutAddFilterCommand;
  Filter: TScreenLayoutFilter;
  Kind: TScreenLayoutFilterKind;
  Layer: TVectArtLayer;
begin
  if not (Sender is TMenuItem) or (FContext = nil) then
    Exit;
  Layer := ScreenLayoutSelectedSingleLayer(FContext);
  if (Layer = nil) or Layer.Locked then
    Exit;
  Kind := TScreenLayoutFilterKind(TMenuItem(Sender).Tag);
  Filter := CreateDefaultScreenLayoutFilter(Kind);
  Command := TScreenLayoutAddFilterCommand.Create(FContext.Document, Layer,
    Layer.FilterCount, Filter);
  Command.Execute;
  if FContext.EditHistory <> nil then
    FContext.EditHistory.AddApplied(Command)
  else
    Command.Free;
  FFilterList.SelectedIndex := Layer.FilterCount - 1;
  UpdateControlState;
end;

constructor TScreenLayoutFilterFrame.Create(AOwner: TComponent);

  procedure AddMenuItem(const Caption: string;
    Kind: TScreenLayoutFilterKind);
  var
    Item: TMenuItem;
  begin
    Item := TMenuItem.Create(FAddMenu);
    Item.Caption := Caption;
    Item.Tag := Ord(Kind);
    Item.OnClick := AddFilterClick;
    FAddMenu.Items.Add(Item);
  end;

begin
  inherited Create(AOwner);
  Align := alClient;
  Color := COLOR_BACKGROUND;
  ParentBackground := False;
  DoubleBuffered := True;

  FHeaderPanel := TPanel.Create(Self);
  FHeaderPanel.Parent := Self;
  FHeaderPanel.Align := alTop;
  FHeaderPanel.Height := MulDiv(HEADER_HEIGHT, CurrentPPI, 96);
  FHeaderPanel.BevelOuter := bvNone;
  FHeaderPanel.Color := COLOR_HEADER;
  FHeaderPanel.ParentBackground := False;

  FCaptionLabel := TLabel.Create(Self);
  FCaptionLabel.Parent := FHeaderPanel;
  FCaptionLabel.Align := alTop;
  FCaptionLabel.AutoSize := False;
  FCaptionLabel.Height := MulDiv(CAPTION_HEIGHT, CurrentPPI, 96);
  FCaptionLabel.Caption := 'Filters';
  FCaptionLabel.Font.Name := 'Segoe UI';
  FCaptionLabel.Font.Height := -12;
  FCaptionLabel.Font.Style := [fsBold];
  FCaptionLabel.Font.Color := COLOR_TEXT_PRIMARY;
  FCaptionLabel.Layout := tlCenter;
  FCaptionLabel.Margins.Left := MulDiv(8, CurrentPPI, 96);
  FCaptionLabel.AlignWithMargins := True;

  FToolbarPanel := TPanel.Create(Self);
  FToolbarPanel.Parent := FHeaderPanel;
  FToolbarPanel.Align := alClient;
  FToolbarPanel.BevelOuter := bvNone;
  FToolbarPanel.Color := COLOR_HEADER;
  FToolbarPanel.ParentBackground := False;

  FAddButton := TPanel.Create(Self);
  FAddButton.Parent := FToolbarPanel;
  FAddButton.SetBounds(MulDiv(5, CurrentPPI, 96), 2,
    MulDiv(26, CurrentPPI, 96), MulDiv(24, CurrentPPI, 96));
  FAddButton.BevelOuter := bvNone;
  FAddButton.Caption := '+';
  FAddButton.Color := COLOR_BUTTON;
  FAddButton.Font.Color := COLOR_TEXT_PRIMARY;
  FAddButton.ParentBackground := False;
  FAddButton.OnClick := AddButtonClick;

  FDeleteButton := TPanel.Create(Self);
  FDeleteButton.Parent := FToolbarPanel;
  FDeleteButton.SetBounds(MulDiv(35, CurrentPPI, 96), 2,
    MulDiv(26, CurrentPPI, 96), MulDiv(24, CurrentPPI, 96));
  FDeleteButton.BevelOuter := bvNone;
  FDeleteButton.Caption := 'x';
  FDeleteButton.Color := COLOR_BUTTON;
  FDeleteButton.Font.Color := COLOR_TEXT_PRIMARY;
  FDeleteButton.ParentBackground := False;
  FDeleteButton.OnClick := DeleteButtonClick;

  FAddMenu := TPopupMenu.Create(Self);
  AddMenuItem('Outline', slfkOutline);
  AddMenuItem('Shadow', slfkShadow);
  AddMenuItem('Blur', slfkBlur);

  FDetailsFrame := TScreenLayoutFilterDetailsFrame.Create(Self);
  FDetailsFrame.Parent := Self;
  FDetailsFrame.Align := alBottom;
  FDetailsFrame.Height := MulDiv(DETAIL_HEIGHT, CurrentPPI, 96);

  FFilterList := TScreenLayoutFilterListControl.Create(Self);
  FFilterList.Parent := Self;
  FFilterList.Align := alClient;
  FFilterList.OnMoveFilter := FilterMoved;
  FFilterList.OnSelectionChanged := FilterSelectionChanged;
  FFilterList.OnToggleEnabled := FilterToggleEnabled;
  FFilterList.OnValueChanged := FilterValueChanged;
  FFilterList.OnValueGestureEnd := FilterValueGestureEnd;
  FFilterList.OnValueGestureStart := FilterValueGestureStart;
  FDetailsFrame.OnChanged := FilterSelectionChanged;
  UpdateControlState;
end;

destructor TScreenLayoutFilterFrame.Destroy;
begin
  if (FValueGestureOldParameters <> nil) and (FContext <> nil) and
    (FContext.Document <> nil) then
    FContext.Document.EndInteractiveUpdate;
  FValueGestureOldParameters.Free;
  inherited Destroy;
end;

procedure TScreenLayoutFilterFrame.DeleteButtonClick(Sender: TObject);
var
  Command: TScreenLayoutRemoveFilterCommand;
  Index: Integer;
  Layer: TVectArtLayer;
begin
  if FContext = nil then
    Exit;
  Layer := FFilterList.Layer;
  Index := FFilterList.SelectedIndex;
  if (Layer = nil) or Layer.Locked or (Index < 0) or
    (Index >= Layer.FilterCount) then
    Exit;
  Command := TScreenLayoutRemoveFilterCommand.Create(FContext.Document,
    Layer, Index);
  Command.Execute;
  if FContext.EditHistory <> nil then
    FContext.EditHistory.AddApplied(Command)
  else
    Command.Free;
  FFilterList.SelectedIndex := Min(Index, Layer.FilterCount - 1);
  UpdateControlState;
end;

procedure TScreenLayoutFilterFrame.FilterMoved(Sender: TObject;
  FromIndex, ToIndex: Integer);
var
  Command: TScreenLayoutMoveFilterCommand;
  Layer: TVectArtLayer;
begin
  if FContext = nil then
    Exit;
  Layer := FFilterList.Layer;
  if (Layer = nil) or Layer.Locked then
    Exit;
  Command := TScreenLayoutMoveFilterCommand.Create(FContext.Document,
    Layer, FromIndex, ToIndex);
  Command.Execute;
  if FContext.EditHistory <> nil then
    FContext.EditHistory.AddApplied(Command)
  else
    Command.Free;
  FFilterList.SelectedIndex := ToIndex;
end;

procedure TScreenLayoutFilterFrame.FilterSelectionChanged(Sender: TObject);
var
  Filter: TScreenLayoutFilter;
  Layer: TVectArtLayer;
begin
  UpdateControlState;
  if (FContext = nil) or (FContext.EditorState = nil) then
    Exit;
  Layer := FFilterList.Layer;
  if (Layer <> nil) and (FFilterList.SelectedIndex >= 0) and
    (FFilterList.SelectedIndex < Layer.FilterCount) then
    Filter := Layer.Filters[FFilterList.SelectedIndex]
  else
    Filter := nil;
  // Only an actual filter selection enters direct filter-edit mode.
  // Refreshing the list after a document selection change also raises this
  // event with Filter=nil; that must not cancel an active creation tool.
  if Filter <> nil then
    FContext.EditorState.CurrentTool := vetSelect;
  FContext.EditorState.SelectFilter(Layer, Filter);
end;

procedure TScreenLayoutFilterFrame.FilterToggleEnabled(Sender: TObject;
  Index: Integer);
var
  Command: TScreenLayoutSetFilterEnabledCommand;
  Filter: TScreenLayoutFilter;
  Layer: TVectArtLayer;
begin
  if FContext = nil then
    Exit;
  Layer := FFilterList.Layer;
  if (Layer = nil) or Layer.Locked or (Index < 0) or
    (Index >= Layer.FilterCount) then
    Exit;
  Filter := Layer.Filters[Index];
  Command := TScreenLayoutSetFilterEnabledCommand.Create(FContext.Document,
    Filter, Filter.Enabled, not Filter.Enabled);
  Command.Execute;
  if FContext.EditHistory <> nil then
    FContext.EditHistory.AddApplied(Command)
  else
    Command.Free;
  FFilterList.Invalidate;
end;

procedure TScreenLayoutFilterFrame.FilterValueChanged(Sender: TObject;
  Index: Integer; Value: Single);
var
  Filter: TScreenLayoutFilter;
  Layer: TVectArtLayer;
begin
  if (FContext = nil) or (FContext.Document = nil) then
    Exit;
  Layer := FFilterList.Layer;
  if (Layer = nil) or Layer.Locked or (Index < 0) or
    (Index >= Layer.FilterCount) then
    Exit;
  Filter := Layer.Filters[Index];
  if Filter is TScreenLayoutOutlineFilter then
    TScreenLayoutOutlineFilter(Filter).Width := Value
  else if Filter is TScreenLayoutShadowFilter then
    TScreenLayoutShadowFilter(Filter).BlurRadius := Value
  else if Filter is TScreenLayoutBlurFilter then
    TScreenLayoutBlurFilter(Filter).Radius := Value
  else
    Exit;
  FContext.Document.Changed;
  FFilterList.Invalidate;
end;

procedure TScreenLayoutFilterFrame.FilterValueGestureEnd(Sender: TObject;
  Index: Integer);
var
  Command: TScreenLayoutSetFilterParametersCommand;
begin
  if FValueGestureOldParameters = nil then
    Exit;
  if (FContext <> nil) and (FContext.EditHistory <> nil) and
    (FValueGestureFilter <> nil) and
    not SameValue(FilterRepresentativeRatio(FValueGestureOldParameters),
      FilterRepresentativeRatio(FValueGestureFilter)) then
  begin
    Command := TScreenLayoutSetFilterParametersCommand.Create(
      FContext.Document, FValueGestureFilter,
      FValueGestureOldParameters, FValueGestureFilter);
    FContext.EditHistory.AddApplied(Command);
  end;
  FValueGestureOldParameters.Free;
  FValueGestureOldParameters := nil;
  FValueGestureFilter := nil;
  if (FContext <> nil) and (FContext.Document <> nil) then
    FContext.Document.EndInteractiveUpdate;
end;

procedure TScreenLayoutFilterFrame.FilterValueGestureStart(Sender: TObject;
  Index: Integer);
var
  Layer: TVectArtLayer;
begin
  if (FContext = nil) or (FContext.Document = nil) then
    Exit;
  Layer := FFilterList.Layer;
  if (Layer = nil) or Layer.Locked or (Index < 0) or
    (Index >= Layer.FilterCount) then
    Exit;
  FValueGestureOldParameters.Free;
  FValueGestureFilter := Layer.Filters[Index];
  FValueGestureOldParameters := FValueGestureFilter.Clone;
  FContext.Document.BeginInteractiveUpdate;
end;

procedure TScreenLayoutFilterFrame.RefreshFromDocument;
var
  DesiredIndex: Integer;
  I: Integer;
  Layer: TVectArtLayer;
begin
  Layer := ScreenLayoutSelectedSingleLayer(FContext);
  FFilterList.Layer := Layer;
  DesiredIndex := -1;
  if (Layer <> nil) and (FContext <> nil) and (FContext.EditorState <> nil) and
    (FContext.EditorState.SelectedFilterLayer = Layer) then
    for I := 0 to Layer.FilterCount - 1 do
      if Layer.Filters[I] = FContext.EditorState.SelectedFilter then
      begin
        DesiredIndex := I;
        Break;
      end;
  FFilterList.SelectedIndex := DesiredIndex;
  FFilterList.Invalidate;
  UpdateControlState;
end;

procedure TScreenLayoutFilterFrame.SetContext(
  const Value: IVectArtDesignerContext);
begin
  if FValueGestureOldParameters <> nil then
  begin
    if (FContext <> nil) and (FContext.Document <> nil) then
      FContext.Document.EndInteractiveUpdate;
    FValueGestureOldParameters.Free;
    FValueGestureOldParameters := nil;
    FValueGestureFilter := nil;
  end;
  if (FContext <> nil) and (FContext.EditorState <> nil) then
    FContext.EditorState.SelectFilter(nil, nil);
  FContext := Value;
  FDetailsFrame.Context := FContext;
  RefreshFromDocument;
end;

procedure TScreenLayoutFilterFrame.UpdateControlState;
var
  Editable: Boolean;
  Filter: TScreenLayoutFilter;
  Layer: TVectArtLayer;
begin
  Layer := FFilterList.Layer;
  Editable := (Layer <> nil) and not Layer.Locked;
  FAddButton.Enabled := Editable;
  if Editable then
    FAddButton.Font.Color := COLOR_TEXT_PRIMARY
  else
    FAddButton.Font.Color := COLOR_DISABLED;
  FDeleteButton.Enabled := Editable and
    (FFilterList.SelectedIndex >= 0);
  if FDeleteButton.Enabled then
    FDeleteButton.Font.Color := COLOR_TEXT_PRIMARY
  else
    FDeleteButton.Font.Color := COLOR_DISABLED;

  if (Layer <> nil) and (FFilterList.SelectedIndex >= 0) and
    (FFilterList.SelectedIndex < Layer.FilterCount) then
  begin
    Filter := Layer.Filters[FFilterList.SelectedIndex];
    FDetailsFrame.SelectFilter(Layer, Filter);
  end
  else
    FDetailsFrame.SelectFilter(Layer, nil);
end;

end.
