// フィルターUIの見出し、操作列、一覧、下端の補助設定を1つのFrameへまとめる。
// 一覧固有の描画と入力はScreenLayoutFilterListControlへ委譲する。
unit ScreenLayoutFilterFrame;

interface

uses
  System.Classes, System.Types, Vcl.Controls, Vcl.ExtCtrls, Vcl.Forms,
  Vcl.Graphics, Vcl.Menus, Vcl.StdCtrls, ScreenLayoutContext,
  ScreenLayoutDocument, ScreenLayoutFilterDetailsFrame,
  ScreenLayoutFilterListControl, ScreenLayoutFilters;

type
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
    // レイアウト変更時に一体で載せ替えられる3領域を生成する。
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    // 単一選択中のレイヤーまたはグループから一覧と補助設定を再同期する。
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
  COLOR_HEADER           = TColor($00292929);
  COLOR_TEXT_PRIMARY     = TColor($00EEEEEE);
  CAPTION_HEIGHT         = 28;
  DETAIL_HEIGHT          = 88;
  HEADER_HEIGHT          = 58;

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
  FCaptionLabel.Caption := 'フィルター';
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
  FAddButton.Hint := 'フィルターを追加';
  FAddButton.ShowHint := True;
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
  FDeleteButton.Hint := '選択したフィルターを削除';
  FDeleteButton.ShowHint := True;
  FDeleteButton.Color := COLOR_BUTTON;
  FDeleteButton.Font.Color := COLOR_TEXT_PRIMARY;
  FDeleteButton.ParentBackground := False;
  FDeleteButton.OnClick := DeleteButtonClick;

  FAddMenu := TPopupMenu.Create(Self);
  AddMenuItem('縁取り', slfkOutline);
  AddMenuItem('影', slfkShadow);
  AddMenuItem('ぼかし', slfkBlur);

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
